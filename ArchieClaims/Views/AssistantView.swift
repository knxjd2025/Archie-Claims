import SwiftUI
import UniformTypeIdentifiers

/// "Archie" — the AI roofing claim assistant. By default it talks to the main
/// Archie CRM backend (sign in with your Archie account); a legacy
/// direct-Anthropic mode with a user-supplied key remains under Settings →
/// Advanced. Attach a CRM client to give Archie their claim profile, docs,
/// and communication history; attach insurance documents or pasted emails to
/// discuss them (and file them to the client's claim in the CRM).
struct AssistantView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var revenueCat: RevenueCatManager

    @AppStorage(AppSettings.archieBaseURLKey) private var archieBaseURL = ""

    @State private var messages: [ChatMessage] = []
    @State private var draft = ""
    @State private var isStreaming = false
    @State private var streamTask: Task<Void, Never>?
    @State private var errorText: String?
    @State private var showAuthSheet = false
    @State private var showClientPicker = false
    @State private var showEmailPaste = false
    @State private var showFileImporter = false
    @State private var attachedClient: ArchieBackendService.ClientAttachment?
    @State private var attachments: [ChatAttachment] = []
    @FocusState private var composerFocused: Bool

    /// A document or pasted email staged for the next message.
    struct ChatAttachment: Identifiable {
        enum Kind { case document, email }
        let id = UUID()
        let kind: Kind
        let name: String
        let text: String
        let data: Data?
        let mimeType: String
        var crmStatus: String? = nil
    }

    private var archieService: ArchieBackendService {
        ArchieBackendService(baseURL: AppSettings.archieBaseURL(from: archieBaseURL))
    }

    /// Prompts adapt to what's attached: a client, a property's storm data, or
    /// nothing yet — so the first message lands on something relevant.
    private var quickPrompts: [String] {
        if attachedClient != nil {
            return [
                "Where does this claim stand and what's my next step?",
                "Draft a follow-up to the adjuster on this claim",
                "Summarize this client's claim for a quick phone call",
                "What documentation is still missing for this claim?"
            ]
        }
        if appState.pendingPropertyContext != nil {
            return [
                "Summarize this storm evidence for the homeowner",
                "Is this hail size claim-worthy? Explain why",
                "Write a door script using this property's storm history",
                "Draft a text to this homeowner about a free inspection"
            ]
        }
        return [
            "Write a 20-second door script for a neighborhood that just took hail",
            "Explain ACV vs RCV and depreciation in homeowner-friendly terms",
            "Give me a roof inspection photo checklist for a hail claim",
            "Draft a follow-up text for a homeowner who wasn't home"
        ]
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let client = attachedClient {
                    clientBanner(client)
                }
                if let context = appState.pendingPropertyContext {
                    contextBanner(context)
                }

                ScrollViewReader { scrollProxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            if messages.isEmpty {
                                emptyState
                            }
                            ForEach(messages) { message in
                                MessageBubble(message: message)
                                    .id(message.id)
                            }
                            if let errorText {
                                Label(errorText, systemImage: "exclamationmark.triangle.fill")
                                    .font(.footnote)
                                    .foregroundStyle(.red)
                                    .padding(.horizontal)
                            }
                        }
                        .padding(.vertical, 12)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: messages.last?.text) {
                        if let last = messages.last {
                            scrollProxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }

                if !attachments.isEmpty {
                    attachmentChips
                }
                composer
            }
            .navigationTitle("Archie AI")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showAuthSheet) {
                ArchieAccountSheet { email in
                    revenueCat.logIn(appUserID: email)
                    errorText = nil
                }
            }
            .sheet(isPresented: $showClientPicker) {
                ClientPickerSheet { attachment in
                    attachedClient = attachment
                }
            }
            .sheet(isPresented: $showEmailPaste) {
                EmailPasteSheet(clientName: attachedClient?.displayName) { subject, body in
                    addEmailAttachment(subject: subject, body: body)
                }
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.pdf, .image, .plainText, .emailMessage],
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let url = urls.first {
                    addDocumentAttachment(from: url)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        if ArchieBackendService.signedInEmail == nil {
                            showAuthSheet = true
                        } else {
                            showClientPicker = true
                        }
                    } label: {
                        Image(systemName: attachedClient == nil
                              ? "person.crop.circle.badge.plus"
                              : "person.crop.circle.badge.checkmark")
                    }
                    .accessibilityLabel(attachedClient == nil ? "Attach a client" : "Change attached client")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        messages.removeAll()
                        errorText = nil
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .disabled(messages.isEmpty || isStreaming)
                    .accessibilityLabel("New conversation")
                }
            }
        }
    }

    // MARK: - Subviews

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("👋 I'm Archie")
                    .font(.title2.bold())
                Text("Your storm claim sidekick — door scripts, damage documentation, claim explanations, follow-ups. Attach a client (👤) to bring in their claim profile and CRM history, or attach an insurance estimate, doc, or email (📎) to work through it together.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("AI guidance only — not legal or insurance advice.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal)

            if ArchieBackendService.signedInEmail == nil {
                Button {
                    showAuthSheet = true
                } label: {
                    Label("Sign in or create your free Archie account", systemImage: "person.crop.circle.badge.checkmark")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal)
            }

            ForEach(quickPrompts, id: \.self) { prompt in
                Button {
                    draft = prompt
                    send()
                } label: {
                    Text(prompt)
                        .font(.subheadline)
                        .multilineTextAlignment(.leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .padding(.horizontal)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }

    private func clientBanner(_ client: ArchieBackendService.ClientAttachment) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "person.crop.circle.fill")
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 1) {
                Text("Client attached — Archie can use their CRM data")
                    .font(.caption.weight(.semibold))
                Text(client.summary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                attachedClient = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Detach client")
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    private func contextBanner(_ context: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "house.fill")
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 1) {
                Text("Property attached")
                    .font(.caption.weight(.semibold))
                Text(context.components(separatedBy: "\n").first ?? "")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                appState.pendingPropertyContext = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    private var attachmentChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(attachments) { attachment in
                    HStack(spacing: 6) {
                        Image(systemName: attachment.kind == .email ? "envelope.fill" : "doc.fill")
                            .font(.caption)
                            .foregroundStyle(Color.accentColor)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(attachment.name)
                                .font(.caption.weight(.medium))
                                .lineLimit(1)
                            if let status = attachment.crmStatus {
                                Text(status)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Button {
                            attachments.removeAll { $0.id == attachment.id }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityLabel("Remove \(attachment.name)")
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(.secondarySystemBackground), in: Capsule())
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 4)
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Menu {
                Button {
                    showFileImporter = true
                } label: {
                    Label("Attach document (PDF, photo…)", systemImage: "doc.badge.plus")
                }
                Button {
                    showEmailPaste = true
                } label: {
                    Label("Paste email / correspondence", systemImage: "envelope.badge")
                }
            } label: {
                Image(systemName: "paperclip")
                    .font(.system(size: 22))
                    .frame(width: 32, height: 36)
            }
            .disabled(isStreaming)
            .accessibilityLabel("Attach a document or email")

            TextField("Ask about claims, scripts, damage…", text: $draft, axis: .vertical)
                .lineLimit(1...5)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
                .focused($composerFocused)
                .disabled(isStreaming)

            Button {
                if isStreaming {
                    streamTask?.cancel()
                } else {
                    send()
                }
            } label: {
                Image(systemName: isStreaming ? "stop.circle.fill" : "arrow.up.circle.fill")
                    .font(.system(size: 30))
            }
            .disabled(!isStreaming
                      && draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      && attachments.isEmpty)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    // MARK: - Attachments

    private func addDocumentAttachment(from url: URL) {
        errorText = nil
        Task {
            do {
                let extraction = try await DocumentTextExtractor.extract(from: url)
                var attachment = ChatAttachment(
                    kind: .document,
                    name: extraction.filename,
                    text: extraction.text,
                    data: extraction.data,
                    mimeType: extraction.mimeType
                )
                attachment.crmStatus = crmPushPlanned ? "Saving to claim…" : nil
                attachments.append(attachment)
                if crmPushPlanned {
                    pushDocumentToCRM(attachment)
                }
            } catch {
                errorText = error.localizedDescription
            }
        }
    }

    private func addEmailAttachment(subject: String, body: String) {
        let name = subject.isEmpty ? "Pasted email" : subject
        var attachment = ChatAttachment(
            kind: .email,
            name: name,
            text: body,
            data: nil,
            mimeType: "text/plain"
        )
        let canLog = attachedClient != nil && (attachedClient?.leadID != nil || attachedClient?.jobID != nil)
        attachment.crmStatus = canLog ? "Logging to CRM…" : nil
        attachments.append(attachment)

        guard canLog, let client = attachedClient else { return }
        let attachmentID = attachment.id
        Task {
            do {
                try await archieService.logCommunication(
                    leadID: client.leadID,
                    jobID: client.jobID,
                    type: "email",
                    title: name,
                    description: body
                )
                setCRMStatus("Logged to \(client.displayName)'s CRM history", for: attachmentID)
            } catch {
                setCRMStatus("CRM log failed — still used in chat", for: attachmentID)
            }
        }
    }

    /// Files are pushed to the CRM only when a client with a claim is attached.
    private var crmPushPlanned: Bool {
        ArchieBackendService.signedInEmail != nil
            && attachedClient?.claimID != nil
    }

    private func pushDocumentToCRM(_ attachment: ChatAttachment) {
        guard let claimID = attachedClient?.claimID, let data = attachment.data else { return }
        let attachmentID = attachment.id
        Task {
            do {
                let url = try await archieService.uploadFile(
                    data: data,
                    filename: attachment.name,
                    mimeType: attachment.mimeType
                )
                try await archieService.registerClaimDocument(
                    claimID: claimID,
                    name: attachment.name,
                    fileURL: url,
                    documentType: Self.documentType(for: attachment),
                    fileSize: data.count,
                    mimeType: attachment.mimeType,
                    notes: "Uploaded from Archie Claims iOS"
                )
                setCRMStatus("Saved to claim ✓", for: attachmentID)
            } catch {
                setCRMStatus("Claim upload failed — still used in chat", for: attachmentID)
            }
        }
    }

    private static func documentType(for attachment: ChatAttachment) -> String {
        let lowered = attachment.name.lowercased()
        if attachment.mimeType.hasPrefix("image/") { return "photo" }
        if lowered.contains("denial") { return "denial_letter" }
        if lowered.contains("estimate") || lowered.contains("xactimate") { return "estimate" }
        return "correspondence"
    }

    private func setCRMStatus(_ status: String, for id: UUID) {
        if let index = attachments.firstIndex(where: { $0.id == id }) {
            attachments[index].crmStatus = status
        }
    }

    // MARK: - Sending

    private func send() {
        guard !isStreaming else { return }
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !attachments.isEmpty else { return }

        guard ArchieBackendService.signedInEmail != nil else {
            showAuthSheet = true
            return
        }

        errorText = nil
        draft = ""
        composerFocused = false

        // Build the outgoing turn: tagged context blocks first, question last.
        var blocks: [String] = []
        for attachment in attachments {
            switch attachment.kind {
            case .document:
                blocks.append("<attached_document name=\"\(attachment.name)\">\n\(attachment.text)\n</attached_document>")
            case .email:
                blocks.append("<email_communication subject=\"\(attachment.name)\">\n\(attachment.text)\n</email_communication>")
            }
        }
        if let context = appState.pendingPropertyContext {
            blocks.append("<property_context>\n\(context)\n</property_context>")
            appState.pendingPropertyContext = nil
        }
        let question = trimmed.isEmpty
            ? "Review the attached material and summarize the key points, amounts, and anything that needs my attention for this claim."
            : trimmed
        let outgoingText = (blocks + [question]).joined(separator: "\n\n")
        attachments = []

        let userMessage = ChatMessage(role: .user, text: outgoingText)
        messages.append(userMessage)
        let history = messages

        let assistantMessage = ChatMessage(role: .assistant, text: "")
        messages.append(assistantMessage)
        isStreaming = true

        let stream = archieService.streamReply(history: history, clientContext: attachedClient?.context)

        streamTask = Task {
            do {
                for try await delta in stream {
                    appendToLastAssistantMessage(delta)
                }
            } catch {
                if let last = messages.last, last.role == .assistant, last.text.isEmpty {
                    messages.removeLast()
                }
                let cancelled = error is CancellationError
                    || (error as? URLError)?.code == .cancelled
                if !cancelled {
                    errorText = error.localizedDescription
                }
            }
            isStreaming = false
            streamTask = nil
        }
    }

    private func appendToLastAssistantMessage(_ delta: String) {
        guard let index = messages.lastIndex(where: { $0.role == .assistant }) else { return }
        messages[index].text += delta
    }
}

/// A chat bubble. Assistant text renders full Markdown (lists, headings,
/// emphasis) per paragraph; machine-readable context blocks in user turns are
/// collapsed into attachment chips.
struct MessageBubble: View {
    let message: ChatMessage

    /// Renders assistant Markdown so claim explanations and photo checklists
    /// keep their list/heading structure instead of being flattened to one line.
    /// Splits on blank lines and renders each block as inline Markdown.
    static func markdown(_ text: String) -> some View {
        let blocks = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
            .map { line -> AttributedString in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty { return AttributedString(" ") }
                if let parsed = try? AttributedString(
                    markdown: line,
                    options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
                ) {
                    return parsed
                }
                return AttributedString(line)
            }
        return VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                Text(block)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }
            Group {
                if message.text.isEmpty && message.role == .assistant {
                    ProgressView()
                        .padding(10)
                } else if message.role == .assistant {
                    Self.markdown(message.text)
                        .textSelection(.enabled)
                } else {
                    Text(displayUserText)
                        .textSelection(.enabled)
                }
            }
            .font(.subheadline)
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .background(
                message.role == .user ? Color.accentColor.opacity(0.9) : Color(.secondarySystemBackground),
                in: RoundedRectangle(cornerRadius: 16)
            )
            .foregroundStyle(message.role == .user ? .white : .primary)
            if message.role == .assistant { Spacer(minLength: 40) }
        }
        .padding(.horizontal)
    }

    /// Collapses leading machine-readable blocks into short chips so the
    /// bubble shows what was attached without the raw payload.
    private var displayUserText: String {
        var remaining = Substring(message.text)
        var chips: [String] = []

        let tags: [(tag: String, chip: (String?) -> String)] = [
            ("property_context", { _ in "🏠 [Property storm data attached]" }),
            ("attached_document", { name in "📎 [Document: \(name ?? "attachment")]" }),
            ("email_communication", { name in "✉️ [Email: \(name ?? "correspondence")]" })
        ]

        outer: while true {
            let trimmed = remaining.drop(while: { $0.isWhitespace || $0.isNewline })
            for entry in tags where trimmed.hasPrefix("<\(entry.tag)") {
                guard let close = trimmed.range(of: "</\(entry.tag)>") else { break outer }
                let opening = trimmed[..<close.lowerBound]
                var name: String?
                if let attrStart = opening.range(of: "=\""),
                   let attrEnd = opening[attrStart.upperBound...].firstIndex(of: "\"") {
                    name = String(opening[attrStart.upperBound..<attrEnd])
                }
                chips.append(entry.chip(name))
                remaining = trimmed[close.upperBound...]
                continue outer
            }
            remaining = trimmed
            break
        }

        let visible = remaining.trimmingCharacters(in: .whitespacesAndNewlines)
        return (chips + (visible.isEmpty ? [] : [visible])).joined(separator: "\n")
    }
}
