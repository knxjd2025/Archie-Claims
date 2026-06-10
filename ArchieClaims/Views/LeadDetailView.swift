import SwiftUI

/// Edit one lead: status, homeowner info, notes, storm snapshot, quick actions.
struct LeadDetailView: View {
    @EnvironmentObject private var leadStore: LeadStore
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var syncService: LeadSyncService
    @Environment(\.dismiss) private var dismiss

    @State var lead: Lead
    @State private var confirmDelete = false

    /// Live copy from the store so the sync badge updates after a push.
    private var current: Lead { leadStore.leads.first(where: { $0.id == lead.id }) ?? lead }

    var body: some View {
        Form {
            Section("Status") {
                Picker("Status", selection: $lead.status) {
                    ForEach(Lead.Status.allCases) { status in
                        Label(status.rawValue, systemImage: status.symbolName).tag(status)
                    }
                }
                .pickerStyle(.menu)
            }

            Section("Property") {
                Text(lead.address)
                    .font(.subheadline)
                    .textSelection(.enabled)
                if !lead.stormSummary.isEmpty {
                    Text(lead.stormSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Homeowner") {
                TextField("Name", text: $lead.homeownerName)
                    .textContentType(.name)
                TextField("Phone", text: $lead.phone)
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
            }

            Section("Notes") {
                TextField("Door notes, damage seen, callbacks…", text: $lead.notes, axis: .vertical)
                    .lineLimit(3...10)
            }

            Section {
                if !sanitizedPhone.isEmpty, let telURL = URL(string: "tel://\(sanitizedPhone)") {
                    Link(destination: telURL) {
                        Label("Call \(lead.homeownerName.isEmpty ? "Homeowner" : lead.homeownerName)", systemImage: "phone.fill")
                    }
                }
                if !sanitizedPhone.isEmpty, let smsURL = URL(string: "sms:\(sanitizedPhone)") {
                    Link(destination: smsURL) {
                        Label("Text Homeowner", systemImage: "message.fill")
                    }
                }
                Button {
                    appState.askArchie(about: assistantContext)
                    dismiss()
                } label: {
                    Label("Ask Archie about this lead", systemImage: "sparkles")
                }
                ShareLink(item: shareText) {
                    Label("Share Lead", systemImage: "square.and.arrow.up")
                }
            }

            crmSyncSection

            Section {
                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Label("Delete Lead", systemImage: "trash")
                }
            }
        }
        .navigationTitle(lead.shortAddress)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: lead.status) {
            // A status change is a knock — stamp it so it counts toward today.
            lead.lastKnockAt = Date()
        }
        .onChange(of: lead) {
            leadStore.update(lead)
        }
        .confirmationDialog("Delete this lead?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                leadStore.delete(lead)
                dismiss()
            }
        }
    }

    @ViewBuilder
    private var crmSyncSection: some View {
        Section {
            switch current.effectiveSyncState {
            case .synced:
                Label("Synced to Archie CRM", systemImage: "checkmark.icloud.fill")
                    .foregroundStyle(.green)
                if let url = current.crmURL {
                    Link(destination: url) {
                        Label("View in Archie CRM", systemImage: "arrow.up.right.square")
                    }
                }
            case .syncing:
                Label("Syncing to Archie CRM…", systemImage: "arrow.triangle.2.circlepath")
                    .foregroundStyle(.secondary)
            case .failed, .local, .queued:
                if ArchieBackendService.signedInEmail == nil {
                    Label("Sign in to Archie to sync this lead", systemImage: "icloud.slash")
                        .foregroundStyle(.secondary)
                } else {
                    Button {
                        syncService.pushNow()
                    } label: {
                        Label("Send to Archie CRM", systemImage: "icloud.and.arrow.up")
                    }
                    if current.effectiveSyncState == .failed, let err = current.syncError {
                        Text("Last attempt: \(err)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("CRM Sync")
        } footer: {
            Text("Qualified doors (Interested, Appointment, Inspected, Signed) become leads in your Archie CRM pipeline. Every door is logged as a knock.")
        }
    }

    private var sanitizedPhone: String {
        lead.phone.filter { $0.isNumber || $0 == "+" }
    }

    private var assistantContext: String {
        var lines = ["Address: \(lead.address)"]
        if !lead.homeownerName.isEmpty { lines.append("Homeowner: \(lead.homeownerName)") }
        lines.append("Lead status: \(lead.status.rawValue)")
        if !lead.stormSummary.isEmpty { lines.append("Storm data: \(lead.stormSummary)") }
        if !lead.notes.isEmpty { lines.append("Canvasser notes: \(lead.notes)") }
        return lines.joined(separator: "\n")
    }

    private var shareText: String {
        var lines = [lead.address, "Status: \(lead.status.rawValue)"]
        if !lead.homeownerName.isEmpty { lines.append("Homeowner: \(lead.homeownerName)") }
        if !lead.phone.isEmpty { lines.append("Phone: \(lead.phone)") }
        if !lead.stormSummary.isEmpty { lines.append("Storm: \(lead.stormSummary)") }
        if !lead.notes.isEmpty { lines.append("Notes: \(lead.notes)") }
        return lines.joined(separator: "\n")
    }
}
