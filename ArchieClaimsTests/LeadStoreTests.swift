import XCTest
@testable import ArchieClaims

@MainActor
final class LeadStoreTests: XCTestCase {

    private func makeStore() -> LeadStore {
        LeadStore(filename: "leads-test-\(UUID().uuidString).json")
    }

    func testAddUpdateDelete() {
        let store = makeStore()
        XCTAssertTrue(store.leads.isEmpty)

        let lead = Lead(address: "123 Main St, Moore, OK 73160", latitude: 35.34, longitude: -97.49)
        store.add(lead)
        XCTAssertEqual(store.leads.count, 1)

        var updated = lead
        updated.status = .appointment
        updated.homeownerName = "Pat Homeowner"
        store.update(updated)
        XCTAssertEqual(store.leads.first?.status, .appointment)
        XCTAssertEqual(store.leads.first?.homeownerName, "Pat Homeowner")

        store.delete(updated)
        XCTAssertTrue(store.leads.isEmpty)
    }

    func testFindLeadNearCoordinate() {
        let store = makeStore()
        let lead = Lead(address: "123 Main St", latitude: 35.34000, longitude: -97.49000)
        store.add(lead)

        XCTAssertNotNil(store.lead(near: 35.34001, longitude: -97.49001))
        XCTAssertNil(store.lead(near: 35.35, longitude: -97.49))
    }

    func testShortAddress() {
        let lead = Lead(address: "123 Main St, Moore, OK 73160", latitude: 0, longitude: 0)
        XCTAssertEqual(lead.shortAddress, "123 Main St")
    }

    func testSetStatusStampsKnock() {
        let store = makeStore()
        let lead = Lead(address: "1 Oak", latitude: 35.1, longitude: -80.8)
        store.add(lead)

        store.setStatus(.signed, for: lead)
        let saved = store.leads.first
        XCTAssertEqual(saved?.status, .signed)
        XCTAssertNotNil(saved?.lastKnockAt)
        XCTAssertTrue(Calendar.current.isDateInToday(saved?.knockedAt ?? .distantPast))
    }

    func testKnockedAtFallsBackToUpdatedAt() {
        // A lead migrated from before lastKnockAt existed (nil) uses updatedAt.
        let lead = Lead(address: "2 Elm", latitude: 0, longitude: 0)
        XCTAssertNil(lead.lastKnockAt)
        XCTAssertEqual(lead.knockedAt, lead.updatedAt)
    }
}
