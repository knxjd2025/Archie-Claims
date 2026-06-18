import SwiftUI

// MARK: - Flow layout

/// A simple wrapping layout so tag chips flow onto multiple lines.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                totalHeight += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        totalHeight += rowHeight
        return CGSize(width: proposal.width ?? x, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Tag chip (display only)

/// A compact read-only tag pill for lead rows and detail headers.
struct TagChip: View {
    let tag: String
    var body: some View {
        let style = Lead.tagStyle(tag)
        Label(tag, systemImage: style.symbol)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(style.color.opacity(0.15), in: Capsule())
            .foregroundStyle(style.color)
    }
}

// MARK: - Tag editor

/// Toggleable tag chips plus a free-form "add tag" field. Binds directly to a
/// lead's `tags` array.
struct TagChipsEditor: View {
    @Binding var tags: [String]
    @State private var customTag = ""

    private var options: [String] {
        var seen = Set<String>()
        return (Lead.suggestedTags + tags).filter { seen.insert($0).inserted }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            FlowLayout(spacing: 8) {
                ForEach(options, id: \.self) { tag in
                    let on = tags.contains(tag)
                    let style = Lead.tagStyle(tag)
                    Button { toggle(tag) } label: {
                        Label(tag, systemImage: style.symbol)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(on ? AnyShapeStyle(style.color) : AnyShapeStyle(style.color.opacity(0.14)), in: Capsule())
                            .foregroundStyle(on ? Color.white : style.color)
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack(spacing: 8) {
                TextField("Add a custom tag", text: $customTag)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .onSubmit(addCustom)
                if !trimmedCustom.isEmpty {
                    Button("Add", action: addCustom)
                        .font(.caption.weight(.semibold))
                }
            }
        }
    }

    private var trimmedCustom: String { customTag.trimmingCharacters(in: .whitespaces) }

    private func toggle(_ tag: String) {
        if let i = tags.firstIndex(of: tag) { tags.remove(at: i) } else { tags.append(tag) }
    }

    private func addCustom() {
        let tag = trimmedCustom
        guard !tag.isEmpty else { return }
        if !tags.contains(tag) { tags.append(tag) }
        customTag = ""
    }
}

// MARK: - Follow-up editor

/// Quick follow-up scheduling: preset chips ("Tomorrow", "Next week") plus a
/// custom date picker. Binds to a lead's optional `followUpAt`.
struct FollowUpEditor: View {
    @Binding var date: Date?
    @State private var showCustom = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let date {
                HStack {
                    Label(Self.format(date), systemImage: date <= Date() ? "bell.badge.fill" : "bell.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(date <= Date() ? Color.red : Color.accentColor)
                    Spacer()
                    Button("Clear") { self.date = nil; showCustom = false }
                        .font(.caption)
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    presetChip("Today 5pm", Self.todayAt(17))
                    presetChip("Tomorrow", Self.daysFromNow(1, hour: 10))
                    presetChip("In 3 days", Self.daysFromNow(3, hour: 10))
                    presetChip("Next week", Self.daysFromNow(7, hour: 10))
                    Button { showCustom.toggle() } label: {
                        chipLabel("Pick a date…", symbol: "calendar")
                    }
                    .buttonStyle(.plain)
                }
            }
            if showCustom {
                DatePicker(
                    "Follow-up",
                    selection: Binding(get: { date ?? Self.daysFromNow(1, hour: 10) }, set: { date = $0 }),
                    in: Date()...,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .datePickerStyle(.compact)
            }
        }
    }

    private func presetChip(_ label: String, _ value: Date) -> some View {
        Button { date = value; showCustom = false } label: {
            chipLabel(label, symbol: nil)
        }
        .buttonStyle(.plain)
    }

    private func chipLabel(_ text: String, symbol: String?) -> some View {
        Group {
            if let symbol { Label(text, systemImage: symbol) } else { Text(text) }
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.accentColor.opacity(0.14), in: Capsule())
        .foregroundStyle(Color.accentColor)
    }

    // MARK: Date helpers

    static func format(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE MMM d, h:mm a"
        return formatter.string(from: date)
    }

    static func todayAt(_ hour: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date()
    }

    static func daysFromNow(_ days: Int, hour: Int) -> Date {
        let base = Calendar.current.date(byAdding: .day, value: days, to: Date()) ?? Date()
        return Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: base) ?? base
    }
}

// MARK: - Storm evidence headline

/// A bold one-line lead-in for the clicked property's NOAA evidence: the most
/// compelling severe-weather report nearby (biggest hail, else tornado, else
/// strongest wind). Gives a rep an instant pitch line.
struct StormEvidenceHeadline: View {
    let reports: [NearbyStormReport]

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    var body: some View {
        if let best = Self.best(from: reports) {
            HStack(spacing: 12) {
                Image(systemName: best.report.kind.symbolName)
                    .font(.title2)
                    .foregroundStyle(best.report.kind.color)
                    .frame(width: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(best.report.magnitudeText)
                        .font(.headline)
                    Text("\(String(format: "%.1f", best.distanceMiles)) mi from this house · \(Self.dateFormatter.string(from: best.report.dateUTC))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.vertical, 2)
        }
    }

    /// Picks the strongest evidence to lead with: biggest hail, then any
    /// tornado, then strongest wind, then the closest report.
    static func best(from reports: [NearbyStormReport]) -> NearbyStormReport? {
        let hail = reports.filter { $0.report.kind == .hail }
        if let topHail = hail.max(by: { ($0.report.hailSizeInches ?? 0) < ($1.report.hailSizeInches ?? 0) }) {
            return topHail
        }
        if let tornado = reports.first(where: { $0.report.kind == .tornado }) {
            return tornado
        }
        let wind = reports.filter { $0.report.kind == .wind }
        if let topWind = wind.max(by: { ($0.report.windSpeedMPH ?? 0) < ($1.report.windSpeedMPH ?? 0) }) {
            return topWind
        }
        return reports.first
    }
}
