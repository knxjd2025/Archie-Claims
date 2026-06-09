import SwiftUI

/// "Archie" — the AI roofing claim assistant, powered by Claude Opus 4.8 via
/// the Anthropic Messages API (streaming).
struct AssistantView: View {
    @EnvironmentObject private var appState: AppState

    @AppStorage(AppSettings.modelOverrideKey) private var modelOverride = ""
    @AppStorage(AppSettings.proxyBaseURLKey) private var proxyBaseURL = ""

    @State private var messages: [ChatMessage] = []
    @State private var draft = ""
    @State private var isStreaming = false
    @State private var streamTask: Task<Void, Never>?
    @State private var errorText: String?
    @FocusState private var composerFocused: Bool

    private let quickPrompts = [
        "Write a 20-second door script for a neighborhood that just took hail",
        "Explain ACV vs RCV and depreciation in homeowner-friendly terms",
        "Give me a roof inspection photo checklist for a hail claim",
        "Draft a follow-up text for a homeowner who wasn't home"
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
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
                    .onChange(of: messages.last?.text) {
                        if let last = messages.last {
                            scrollProxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }

                composer
            }
            .navigationTitle("Archie AI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
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
                Text("Your storm claim sidekick — door scripts, damage documentation, claim explanations, follow-ups. Tap a house on the map and choose **Ask Archie** to bring its storm data with you.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("AI guidance only — not legal or insurance advice.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal)

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

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
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
            .disabled(!isStreaming && draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    // MARK: - Sending

    private func send() {
        guard !isStreaming else { return }
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        guard let apiKey = KeychainStore.read(), !apiKey.isEmpty else {
            errorText = "Add your Anthropic API key in Settings → AI Assistant to use Archie."
            return
        }

        errorText = nil
        draft = ""
        composerFocused = false

        // Attach property context (once) as a tagged block in the user turn.
        var outgoingText = trimmed
        if let context = appState.pendingPropertyContext {
            outgoingText = "<property_context>\n\(context)\n</property_context>\n\n\(trimmed)"
            appState.pendingPropertyContext = nil
        }

        let userMessage = ChatMessage(role: .user, text: outgoingText)
        messages.append(userMessage)
        let history = messages

        let assistantMessage = ChatMessage(role: .assistant, text: "")
        messages.append(assistantMessage)
        isStreaming = true

        let service = ClaudeService(
            apiKey: apiKey,
            baseURL: AppSettings.baseURL(from: proxyBaseURL),
            model: AppSettings.model(from: modelOverride)
        )

        streamTask = Task {
            do {
                for try await delta in service.streamReply(history: history) {
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

/// A chat bubble. Assistant text renders basic Markdown.
struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }
            Group {
                if message.text.isEmpty && message.role == .assistant {
                    ProgressView()
                        .padding(10)
                } else if message.role == .assistant {
                    Text(LocalizedStringKey(message.text))
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

    /// Hide the machine-readable property context block from the bubble.
    private var displayUserText: String {
        guard message.text.hasPrefix("<property_context>"),
              let range = message.text.range(of: "</property_context>") else {
            return message.text
        }
        let visible = String(message.text[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        return "🏠 [Property storm data attached]\n\(visible)"
    }
}
