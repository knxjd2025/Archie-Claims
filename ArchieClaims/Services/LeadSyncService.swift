import Foundation
import Network
import UIKit

/// Pushes canvassed doors to the Archie CRM via `POST /api/leads/sync`.
///
/// One-way (device → CRM). Every logged door is sent as a `door_knock`; the
/// server promotes qualified doors to CRM leads. The push is batched (≤200),
/// idempotent (keyed on the lead's UUID), and offline-safe: leads stay queued
/// on device and drain on the next trigger — app foreground, network regained,
/// a disposition change, or a manual push.
@MainActor
final class LeadSyncService: ObservableObject {

    /// Server caps a batch at 200 knocks.
    private static let maxBatch = 200
    private static let debounce: Duration = .milliseconds(1200)

    @Published private(set) var isSyncing = false
    @Published private(set) var pendingCount = 0
    /// Surfaced as a one-time banner when the free tier defers some leads.
    @Published var freeLimitNudge: String?
    /// Last whole-request failure (network/session), for optional UI.
    @Published private(set) var lastError: String?

    private let store: LeadStore
    private var baseURLOverride: String

    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.archieclaims.sync.netmonitor")
    private var isOnline = true

    private var debounceTask: Task<Void, Never>?
    private var retryCount = 0

    private let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private lazy var deviceInfo: String = {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion) / ArchieClaims \(version) (\(build))"
    }()

    init(store: LeadStore, baseURLOverride: String = "") {
        self.store = store
        self.baseURLOverride = baseURLOverride
        store.onLeadsChanged = { [weak self] in
            self?.requestSync()
        }
        refreshPending()
    }

    /// Begins network monitoring and does an initial drain. Call once at launch.
    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in
                guard let self else { return }
                let regained = online && !self.isOnline
                self.isOnline = online
                if regained { self.requestSync() }
            }
        }
        monitor.start(queue: monitorQueue)
        requestSync()
    }

    /// Lets the base URL track the user's Settings override.
    func updateBaseURL(_ override: String) {
        baseURLOverride = override
    }

    /// Debounced request to drain the queue. Safe to call often.
    func requestSync() {
        refreshPending()
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: Self.debounce)
            guard !Task.isCancelled else { return }
            await self?.syncNow()
        }
    }

    /// Forces an immediate drain (manual "Push" / "Send to CRM" buttons).
    func pushNow() {
        debounceTask?.cancel()
        Task { await syncNow() }
    }

    private func refreshPending() {
        pendingCount = store.pendingSyncCount
    }

    private var service: ArchieBackendService {
        ArchieBackendService(baseURL: AppSettings.archieBaseURL(from: baseURLOverride))
    }

    // MARK: - Drain

    private func syncNow() async {
        guard !isSyncing else { return }
        guard ArchieBackendService.signedInEmail != nil else { return } // sync once signed in
        guard isOnline else { return }

        let batch = store.leadsPendingSync(limit: Self.maxBatch)
        guard !batch.isEmpty else { refreshPending(); return }

        isSyncing = true
        defer { isSyncing = false; refreshPending() }

        let ids = Set(batch.map(\.id))
        store.markSyncing(ids)

        let payload: [String: Any] = ["knocks": batch.map(knockPayload)]

        do {
            let response = try await service.authorizedJSON(
                path: "api/leads/sync", method: "POST", body: payload
            )
            let dict = response as? [String: Any]
            let rows = (dict?["results"] as? [[String: Any]]) ?? []

            var updates: [LeadStore.SyncUpdate] = []
            for row in rows {
                guard let cid = row["client_id"] as? String, let id = UUID(uuidString: cid) else { continue }
                let ok = (row["ok"] as? Bool) ?? false
                updates.append(LeadStore.SyncUpdate(
                    id: id,
                    ok: ok,
                    crmLeadID: row["lead_id"] as? String,
                    knockID: row["door_knock_id"] as? String,
                    error: ok ? nil : (row["error"] as? String ?? "sync_failed")
                ))
            }
            // Any item the server didn't echo back stays in-flight → revert it.
            let echoed = Set(updates.map(\.id))
            store.applySyncResults(updates)
            store.markSyncFailed(ids.subtracting(echoed), error: "no_response")

            lastError = nil
            retryCount = 0
            handleFreeLimit(dict?["free_limit"] as? [String: Any])

            // More queued than one batch could hold → keep draining.
            if store.pendingSyncCount > 0, updates.contains(where: { $0.ok }) {
                requestSync()
            }
        } catch ArchieBackendService.BackendError.notSignedIn,
                ArchieBackendService.BackendError.sessionExpired {
            // Leave queued; they'll go out after the user signs in again.
            store.markSyncFailed(ids, error: "not_signed_in")
        } catch {
            store.markSyncFailed(ids, error: error.localizedDescription)
            lastError = error.localizedDescription
            scheduleRetry()
        }
    }

    private func scheduleRetry() {
        retryCount = min(retryCount + 1, 5)
        let delay = Duration.seconds(min(60, 5 * (1 << (retryCount - 1)))) // 5,10,20,40,60s
        Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard let self, !Task.isCancelled else { return }
            await self.syncNow()
        }
    }

    private func handleFreeLimit(_ freeLimit: [String: Any]?) {
        guard let deferred = freeLimit?["deferred"] as? Int, deferred > 0 else { return }
        freeLimitNudge = "\(deferred) lead\(deferred == 1 ? "" : "s") need a paid Archie plan to land in your CRM pipeline. The knocks are still saved on the canvassing map."
    }

    // MARK: - Wire payload

    private func knockPayload(_ lead: Lead) -> [String: Any] {
        var d: [String: Any] = [
            "client_id": lead.id.uuidString,
            "status": lead.status.wireValue,
            "knocked_at": isoFormatter.string(from: lead.knockedAt),
            "latitude": lead.latitude,
            "longitude": lead.longitude,
            "device_info": deviceInfo,
        ]
        let address = lead.address.trimmingCharacters(in: .whitespaces)
        if !address.isEmpty, address != "Locating address…" { d["address"] = address }
        if !lead.homeownerName.isEmpty { d["homeowner_name"] = lead.homeownerName }
        if !lead.phone.isEmpty { d["phone"] = lead.phone }
        if !lead.notes.isEmpty { d["notes"] = lead.notes }
        if !lead.stormSummary.isEmpty { d["storm_summary"] = lead.stormSummary }
        return d
    }
}
