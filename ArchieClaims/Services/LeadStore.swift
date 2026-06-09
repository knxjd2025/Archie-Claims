import Foundation

/// On-device lead storage. Persists to a JSON file in Application Support —
/// nothing leaves the phone.
@MainActor
final class LeadStore: ObservableObject {
    @Published private(set) var leads: [Lead] = []

    private let fileURL: URL

    init(filename: String = "leads.json") {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent(filename)
        load()
    }

    func add(_ lead: Lead) {
        leads.insert(lead, at: 0)
        save()
    }

    func update(_ lead: Lead) {
        guard let index = leads.firstIndex(where: { $0.id == lead.id }) else { return }
        var updated = lead
        updated.updatedAt = Date()
        leads[index] = updated
        save()
    }

    func delete(_ lead: Lead) {
        leads.removeAll { $0.id == lead.id }
        save()
    }

    func delete(at offsets: IndexSet, in filtered: [Lead]) {
        let ids = offsets.map { filtered[$0].id }
        leads.removeAll { ids.contains($0.id) }
        save()
    }

    func lead(near latitude: Double, longitude: Double, toleranceDegrees: Double = 0.0002) -> Lead? {
        leads.first {
            abs($0.latitude - latitude) < toleranceDegrees && abs($0.longitude - longitude) < toleranceDegrees
        }
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([Lead].self, from: data) else { return }
        leads = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(leads) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
