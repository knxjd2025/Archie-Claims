import SwiftUI

/// Filter sheet for the storm overlay / history — pick kinds, a minimum hail
/// size, and a date window (e.g. to isolate a single storm event).
struct StormFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var filter: StormFilter

    @State private var useDateRange = false
    @State private var fromDate = Date()
    @State private var toDate = Date()

    var body: some View {
        NavigationStack {
            Form {
                Section("Storm types") {
                    ForEach(StormReport.Kind.allCases, id: \.self) { kind in
                        Toggle(isOn: binding(for: kind)) {
                            Label(kind.label, systemImage: kind.symbolName)
                                .foregroundStyle(kind.color)
                        }
                    }
                }

                Section("Minimum hail size") {
                    VStack(alignment: .leading) {
                        Text(filter.minHailInches == 0
                             ? "Any hail size"
                             : String(format: "%.2f\" or larger", filter.minHailInches))
                            .font(.subheadline)
                        Slider(value: $filter.minHailInches, in: 0...3, step: 0.25)
                    }
                    if filter.minHailInches > 0 {
                        Text(hailContext(filter.minHailInches))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Toggle("Limit to a date range", isOn: $useDateRange)
                    if useDateRange {
                        DatePicker("From", selection: $fromDate, displayedComponents: .date)
                        DatePicker("To", selection: $toDate, in: fromDate..., displayedComponents: .date)
                    }
                } header: {
                    Text("Storm date")
                } footer: {
                    Text("Set both dates to a single day to canvass exactly where a known storm hit.")
                }

                Section {
                    Button("Reset filters", role: .destructive) {
                        filter = StormFilter()
                        useDateRange = false
                    }
                    .disabled(!filter.isActive)
                }
            }
            .navigationTitle("Filter Storms")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: useDateRange) { syncDates() }
            .onChange(of: fromDate) { syncDates() }
            .onChange(of: toDate) { syncDates() }
            .onAppear {
                if let f = filter.fromDate { fromDate = f }
                if let t = filter.toDate { toDate = t }
                useDateRange = filter.fromDate != nil || filter.toDate != nil
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func binding(for kind: StormReport.Kind) -> Binding<Bool> {
        Binding(
            get: { filter.kinds.contains(kind) },
            set: { on in
                if on { filter.kinds.insert(kind) } else { filter.kinds.remove(kind) }
                if filter.kinds.isEmpty { filter.kinds = [kind] } // never empty
            }
        )
    }

    private func syncDates() {
        filter.fromDate = useDateRange ? fromDate : nil
        filter.toDate = useDateRange ? toDate : nil
    }

    private func hailContext(_ inches: Double) -> String {
        switch inches {
        case ..<1.0: return "Roughly quarter-size and up — possible shingle bruising."
        case ..<1.5: return "Golf-ball range — common roof-damage threshold."
        case ..<2.0: return "Hen-egg and up — likely roof damage."
        default: return "Baseball-size and up — severe roof damage likely."
        }
    }
}

/// Full searchable, sortable storm history for a tapped house — beyond the
/// property sheet's top-12 preview.
struct StormHistoryView: View {
    let reports: [NearbyStormReport]

    @State private var filter = StormFilter()
    @State private var sort: SortOption = .recent
    @State private var showFilter = false

    enum SortOption: String, CaseIterable, Identifiable {
        case recent = "Newest"
        case closest = "Closest"
        case biggest = "Biggest hail"
        var id: String { rawValue }
    }

    private var filtered: [NearbyStormReport] {
        let matched = reports.filter { filter.matches($0.report) }
        switch sort {
        case .recent:
            return matched.sorted { $0.report.dateUTC > $1.report.dateUTC }
        case .closest:
            return matched.sorted { $0.distanceMiles < $1.distanceMiles }
        case .biggest:
            return matched.sorted {
                ($0.report.hailSizeInches ?? -1) > ($1.report.hailSizeInches ?? -1)
            }
        }
    }

    var body: some View {
        List {
            Section {
                Picker("Sort", selection: $sort) {
                    ForEach(SortOption.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            Section {
                if filtered.isEmpty {
                    ContentUnavailableView("No matching reports", systemImage: "cloud.sun")
                } else {
                    ForEach(filtered) { item in
                        StormReportRow(item: item)
                    }
                }
            } header: {
                Text("\(filtered.count) of \(reports.count) reports")
            }
        }
        .navigationTitle("Storm History")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showFilter = true
                } label: {
                    Image(systemName: filter.isActive
                          ? "line.3.horizontal.decrease.circle.fill"
                          : "line.3.horizontal.decrease.circle")
                }
            }
        }
        .sheet(isPresented: $showFilter) {
            StormFilterSheet(filter: $filter)
        }
    }
}
