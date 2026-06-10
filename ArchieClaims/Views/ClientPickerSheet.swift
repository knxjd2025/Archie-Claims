import SwiftUI

/// Search the Archie CRM (leads + customers) and attach a client to the chat.
/// Picking one pulls their CRM record, claim profile, documents on file, and
/// recent communications into the assistant's context.
struct ClientPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppSettings.archieBaseURLKey) private var archieBaseURL = ""

    @State private var searchText = ""
    @State private var hits: [ArchieBackendService.ClientHit] = []
    @State private var isSearching = false
    @State private var loadingHitID: String?
    @State private var errorText: String?
    @State private var searchTask: Task<Void, Never>?

    var onAttach: (ArchieBackendService.ClientAttachment) -> Void

    private var service: ArchieBackendService {
        ArchieBackendService(baseURL: AppSettings.archieBaseURL(from: archieBaseURL))
    }

    var body: some View {
        NavigationStack {
            List {
                if let errorText {
                    Label(errorText, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                if hits.isEmpty && !isSearching && searchText.count >= 2 && errorText == nil {
                    ContentUnavailableView(
                        "No clients found",
                        systemImage: "person.crop.circle.badge.questionmark",
                        description: Text("Search by name, address, phone, or email — same records as app.archie.now.")
                    )
                }

                ForEach(hits) { hit in
                    Button {
                        attach(hit)
                    } label: {
                        HStack {
                            Image(systemName: hit.entityType == "lead" ? "person.crop.circle" : "house.circle")
                                .font(.title3)
                                .foregroundStyle(Color.accentColor)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(hit.displayName)
                                    .font(.subheadline.weight(.medium))
                                Text(hit.displaySubtitle.isEmpty
                                     ? (hit.entityType == "lead" ? "Lead" : "Customer")
                                     : hit.displaySubtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if loadingHitID == hit.id {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(loadingHitID != nil)
                }
            }
            .listStyle(.plain)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Client name, address, phone…")
            .overlay {
                if isSearching && hits.isEmpty {
                    ProgressView()
                }
            }
            .onChange(of: searchText) {
                scheduleSearch()
            }
            .navigationTitle("Attach a Client")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard query.count >= 2 else {
            hits = []
            return
        }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            isSearching = true
            errorText = nil
            do {
                let results = try await service.searchClients(query: query)
                if !Task.isCancelled { hits = results }
            } catch {
                if !Task.isCancelled { errorText = error.localizedDescription }
            }
            isSearching = false
        }
    }

    private func attach(_ hit: ArchieBackendService.ClientHit) {
        loadingHitID = hit.id
        errorText = nil
        Task {
            do {
                let attachment = try await service.clientAttachment(for: hit)
                onAttach(attachment)
                dismiss()
            } catch {
                errorText = error.localizedDescription
            }
            loadingHitID = nil
        }
    }
}

/// Paste an email (or any correspondence) to attach to the chat — and, when a
/// client is attached, log it to their CRM communication history.
struct EmailPasteSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var subject = ""
    @State private var bodyText = ""

    var clientName: String?
    var onAdd: (_ subject: String, _ body: String) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Subject (optional)", text: $subject)
                    TextEditor(text: $bodyText)
                        .frame(minHeight: 220)
                        .overlay(alignment: .topLeading) {
                            if bodyText.isEmpty {
                                Text("Paste the email or correspondence text here…")
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 8)
                                    .padding(.leading, 4)
                                    .allowsHitTesting(false)
                            }
                        }
                } footer: {
                    if let clientName {
                        Text("Archie will use this in the conversation and log it to \(clientName)'s communication history in the CRM.")
                    } else {
                        Text("Archie will use this in the conversation. Attach a client first to also log it to their CRM history.")
                    }
                }
            }
            .navigationTitle("Add Email / Correspondence")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onAdd(subject.trimmingCharacters(in: .whitespaces), bodyText)
                        dismiss()
                    }
                    .disabled(bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
