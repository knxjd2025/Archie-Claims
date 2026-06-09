import XCTest
@testable import ArchieClaims

final class StormDataServiceTests: XCTestCase {

    func testYYMMDDFormatting() {
        // 2026-06-09 12:00:00 UTC
        let date = Date(timeIntervalSince1970: 1_781_006_400)
        XCTAssertEqual(StormDataService.yymmdd(date), "260609")
    }

    func testRecentConvectiveDaysCountAndOrder() {
        let now = Date(timeIntervalSince1970: 1_781_006_400)
        let days = StormDataService.recentConvectiveDays(lookbackDays: 14, now: now)
        XCTAssertEqual(days.count, 14)
        XCTAssertEqual(StormDataService.yymmdd(days[0]), "260609")
        XCTAssertEqual(StormDataService.yymmdd(days[1]), "260608")
        // Strictly descending, no duplicates.
        let keys = days.map { StormDataService.yymmdd($0) }
        XCTAssertEqual(Set(keys).count, keys.count)
    }

    func testLookbackClamping() {
        let tooMany = StormDataService.recentConvectiveDays(lookbackDays: 9999)
        XCTAssertEqual(tooMany.count, 120)
        let tooFew = StormDataService.recentConvectiveDays(lookbackDays: 0)
        XCTAssertEqual(tooFew.count, 1)
    }

    func testSummaryEmpty() {
        let text = StormDataService.summary(of: [], lookbackDays: 30)
        XCTAssertTrue(text.contains("No SPC severe weather reports"))
        XCTAssertTrue(text.contains("30"))
    }

    func testSummaryWithReports() {
        let report = StormReport(
            kind: .hail,
            dateUTC: Date(timeIntervalSince1970: 1_781_006_400),
            timeHHMM: "2010",
            rawMagnitude: "175",
            location: "4 W MOORE",
            county: "CLEVELAND",
            state: "OK",
            latitude: 35.34,
            longitude: -97.56,
            comments: ""
        )
        let summary = StormDataService.summary(
            of: [NearbyStormReport(report: report, distanceMiles: 1.2)],
            lookbackDays: 30
        )
        XCTAssertTrue(summary.contains("1.75\" hail"))
        XCTAssertTrue(summary.contains("1.2 mi"))
        XCTAssertTrue(summary.contains("1 hail"))
    }
}
