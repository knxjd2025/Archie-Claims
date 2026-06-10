import Foundation

/// On-device lead storage. Persists to a JSON file in Application Support —
/// nothing leaves the phone.
@MainActor
final class LeadStore: ObservableObject {
    @Published private(set) var leads: [Lead] = []
    /// Set when the last disk write failed — surfaced as a banner so a rep never
    /// silently loses a day of knocks to a full disk or encoding error.
    @Published var lastSaveError: String?

    /// Called after any user-facing change to a lead (create / disposition /
    /// edit / delete) so the sync service can schedule a debounced push. NOT
    /// fired by the sync write-back methods, which would loop.
    var onLeadsChanged: (() -> Void)?

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
        onLeadsChanged?()
    }

    func update(_ lead: Lead) {
        guard let index = leads.firstIndex(where: { $0.id == lead.id }) else { return }
        // Copy only user-editable fields onto the LIVE store entry so a stale
        // view snapshot (or a late background fill-in) can't clobber the
        // server-assigned sync fields (CRM ids, sync state).
        var updated = leads[index]
        updated.status = lead.status
        updated.homeownerName = lead.homeownerName
        updated.phone = lead.phone
        updated.notes = lead.notes
        updated.address = lead.address
        updated.stormSummary = lead.stormSummary
        updated.lastKnockAt = lead.lastKnockAt
        updated.updatedAt = Date()
        markDirty(&updated)
        leads[index] = updated
        save()
        onLeadsChanged?()
    }

    /// Records a knock outcome: updates the status and stamps `lastKnockAt` so
    /// the door counts toward today's tally. Use this (not `update`) whenever a
    /// door is dispositioned, vs. editing notes/contact fields.
    func setStatus(_ status: Lead.Status, for lead: Lead) {
        guard let index = leads.firstIndex(where: { $0.id == lead.id }) else { return }
        let now = Date()
        leads[index].status = status
        leads[index].lastKnockAt = now
        leads[index].updatedAt = now
        markDirty(&leads[index])
        save()
        onLeadsChanged?()
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

    /// A content edit re-queues a previously-synced lead so the CRM stays in
    /// step. Leaves leads that already need sync untouched, and never moves a
    /// lead out of an in-flight state here.
    private func markDirty(_ lead: inout Lead) {
        if lead.effectiveSyncState == .synced || lead.effectiveSyncState == .syncing {
            lead.syncState = .queued
        }
    }

    // MARK: - CRM sync state (driven by LeadSyncService; no onLeadsChanged)

    var pendingSyncCount: Int { leads.filter(\.needsSync).count }

    func leadsPendingSync(limit: Int) -> [Lead] {
        Array(leads.filter(\.needsSync).prefix(limit))
    }

    /// Marks the given leads in-flight just before a request goes out.
    func markSyncing(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        let now = Date()
        for i in leads.indices where ids.contains(leads[i].id) {
            leads[i].syncState = .syncing
            leads[i].lastSyncAttempt = now
        }
        save()
    }

    struct SyncUpdate {
        let id: UUID
        let ok: Bool
        let crmLeadID: String?
        let knockID: String?
        let error: String?
    }

    /// Applies per-item results from the sync endpoint. If a lead was edited
    /// while its request was in flight (state bumped back to `.queued`), a
    /// success is NOT finalized to `.synced` — it stays queued to re-send the
    /// newer content — but the returned CRM ids are still recorded.
    func applySyncResults(_ updates: [SyncUpdate]) {
        guard !updates.isEmpty else { return }
        for update in updates {
            guard let i = leads.firstIndex(where: { $0.id == update.id }) else { continue }
            if let crmLeadID = update.crmLeadID { leads[i].syncedCRMLeadID = crmLeadID }
            if let knockID = update.knockID { leads[i].syncedKnockID = knockID }
            if update.ok {
                leads[i].syncState = (leads[i].syncState == .syncing) ? .synced : .queued
                leads[i].syncError = nil
            } else if leads[i].syncState == .syncing {
                // Only mark failed if still in-flight; a lead edited mid-request
                // (bumped to .queued) keeps its newer state to re-send.
                leads[i].syncState = .failed
                leads[i].syncError = update.error
            }
        }
        save()
    }

    /// Reverts in-flight leads to `.failed` when a whole request fails (network,
    /// 429, session) so the next trigger retries them.
    func markSyncFailed(_ ids: Set<UUID>, error: String) {
        guard !ids.isEmpty else { return }
        for i in leads.indices where ids.contains(leads[i].id) && leads[i].syncState == .syncing {
            leads[i].syncState = .failed
            leads[i].syncError = error
        }
        save()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([Lead].self, from: data) else { return }
        leads = decoded
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(leads)
            try data.write(to: fileURL, options: .atomic)
            lastSaveError = nil
        } catch {
            lastSaveError = "Couldn't save leads to this device (\(error.localizedDescription)). Free up storage; your current leads are still on screen."
        }
    }
}
