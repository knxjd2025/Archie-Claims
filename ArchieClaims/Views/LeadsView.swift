import SwiftUI

/// Saved doors, filterable by status.
struct LeadsView: View {
    @EnvironmentObject private var leadStore: LeadStore
    @EnvironmentObject private var syncService: LeadSyncService
    @State private var filter: Lead.Status?
    @State private var followUpsOnly = false
    @State private var searchText = ""

    private var dueCount: Int { leadStore.leads.filter(\.isFollowUpDue).count }

    private var filtered: [Lead] {
        let base = leadStore.leads.filter { lead in
            (filter == nil || lead.status == filter) &&
            (!followUpsOnly || lead.followUpAt != nil) &&
            (searchText.isEmpty
             || lead.address.localizedCaseInsensitiveContains(searchText)
             || lead.homeownerName.localizedCaseInsensitiveContains(searchText)
             || lead.tags.contains { $0.localizedCaseInsensitiveContains(searchText) })
        }
        if followUpsOnly {
            return base.sorted { ($0.followUpAt ?? .distantFuture) < ($1.followUpAt ?? .distantFuture) }
        }
        return base.sorted { $0.updatedAt > $1.updatedAt }
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
                    .overlay {
                        if filtered.isEmpty {
                            ContentUnavailableView(
                                followUpsOnly ? "No follow-ups" : "No matches",
                                systemImage: followUpsOnly ? "bell.slash" : "magnifyingglass",
                                description: Text(followUpsOnly
                                    ? "Set a follow-up on a lead and it'll show up here."
                                    : "Try a different search or filter.")
                            )
                        }
                    }
                    .searchable(text: $searchText, prompt: "Address, name, or tag")
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
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        followUpsOnly.toggle()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: followUpsOnly ? "bell.fill" : "bell")
                            if dueCount > 0 {
                                Text("\(dueCount)")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(.red, in: Capsule())
                            }
                        }
                    }
                    .tint(followUpsOnly ? .accentColor : (dueCount > 0 ? .red : .accentColor))
                }
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
            VStack(alignment: .leading, spacing: 3) {
                Text(lead.shortAddress)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(lead.homeownerName.isEmpty ? lead.status.rawValue : "\(lead.homeownerName) · \(lead.status.rawValue)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !lead.tags.isEmpty || lead.followUpAt != nil {
                    HStack(spacing: 4) {
                        if let followUp = lead.followUpAt {
                            Label {
                                Text(followUp, format: .dateTime.month(.abbreviated).day())
                            } icon: {
                                Image(systemName: "bell.fill")
                            }
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(lead.isFollowUpDue ? .red : .secondary)
                        }
                        ForEach(lead.tags.prefix(3), id: \.self) { TagChip(tag: $0) }
                        if lead.tags.count > 3 {
                            Text("+\(lead.tags.count - 3)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .lineLimit(1)
                }
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
