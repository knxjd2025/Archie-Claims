import SwiftUI

/// Saved doors, filterable by status.
struct LeadsView: View {
    @EnvironmentObject private var leadStore: LeadStore
    @EnvironmentObject private var syncService: LeadSyncService
    @State private var filter: Lead.Status?
    @State private var searchText = ""

    private var filtered: [Lead] {
        leadStore.leads
            .filter { lead in
                (filter == nil || lead.status == filter) &&
                (searchText.isEmpty
                 || lead.address.localizedCaseInsensitiveContains(searchText)
                 || lead.homeownerName.localizedCaseInsensitiveContains(searchText))
            }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    var body: some View {
        NavigationStack {
            Group {
                if leadStore.leads.isEmpty {
                    ContentUnavailableView(
                        "No leads yet",
                        systemImage: "person.3",
                        description: Text("Tap houses on the Canvass map and save them as leads. They'll show up here and as pins on the map.")
                    )
                } else {
                    List {
                        ForEach(filtered) { lead in
                            NavigationLink(value: lead.id) {
                                LeadRow(lead: lead)
                            }
                        }
                        .onDelete { offsets in
                            leadStore.delete(at: offsets, in: filtered)
                        }
                    }
                    .searchable(text: $searchText, prompt: "Address or name")
                }
            }
            .navigationTitle("Leads")
            .navigationDestination(for: UUID.self) { id in
                if let lead = leadStore.leads.first(where: { $0.id == id }) {
                    LeadDetailView(lead: lead)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !leadStore.leads.isEmpty {
                    syncBar
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("All") { filter = nil }
                        ForEach(Lead.Status.allCases) { status in
                            Button(status.rawValue) { filter = status }
                        }
                    } label: {
                        Label(filter?.rawValue ?? "All", systemImage: "line.3.horizontal.decrease.circle")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var syncBar: some View {
        let pending = syncService.pendingCount
        HStack(spacing: 8) {
            if syncService.isSyncing {
                ProgressView().controlSize(.small)
                Text("Syncing to Archie CRM…").font(.caption)
            } else if pending > 0 {
                Image(systemName: "arrow.up.circle").foregroundStyle(Color.accentColor)
                Text("\(pending) lead\(pending == 1 ? "" : "s") to sync").font(.caption)
            } else {
                Image(systemName: "checkmark.icloud").foregroundStyle(.green)
                Text("All leads synced to Archie CRM").font(.caption)
            }
            Spacer()
            if pending > 0 && !syncService.isSyncing {
                Button("Push \(pending)") { syncService.pushNow() }
                    .font(.caption.weight(.semibold))
                    .disabled(ArchieBackendService.signedInEmail == nil)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

struct LeadRow: View {
    let lead: Lead

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: lead.status.symbolName)
                .font(.caption)
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(lead.status.color, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(lead.shortAddress)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(lead.homeownerName.isEmpty ? lead.status.rawValue : "\(lead.homeownerName) · \(lead.status.rawValue)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(lead.updatedAt, style: .date)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                syncBadge
            }
        }
    }

    @ViewBuilder
    private var syncBadge: some View {
        switch lead.effectiveSyncState {
        case .synced:
            Image(systemName: "checkmark.icloud.fill")
                .font(.caption2)
                .foregroundStyle(.green)
                .accessibilityLabel("Synced to CRM")
        case .syncing:
            Image(systemName: "arrow.triangle.2.circlepath.icloud")
                .font(.caption2)
                .foregroundStyle(.secondary)
        case .failed:
            Image(systemName: "exclamationmark.icloud")
                .font(.caption2)
                .foregroundStyle(.orange)
        case .local, .queued:
            Image(systemName: "icloud.and.arrow.up")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .accessibilityLabel("Not yet synced")
        }
    }
}
