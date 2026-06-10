import SwiftUI

/// Saved doors, filterable by status.
struct LeadsView: View {
    @EnvironmentObject private var leadStore: LeadStore
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
            Text(lead.updatedAt, style: .date)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}
