import XCTest
import CoreLocation
@testable import ArchieClaims

final class SPCReportParserTests: XCTestCase {

    /// Fixture in the documented SPC filtered-CSV format: three sections
    /// (tornado, wind, hail), each with its own header row.
    private let fixtureCSV = """
    Time,F_Scale,Location,County,State,Lat,Lon,Comments
    2305,UNK,2 N PERKINS,PAYNE,OK,36.01,-97.03,Brief tornado touchdown (TSA)
    Time,Speed,Location,County,State,Lat,Lon,Comments
    2025,70,3 SSW CHICKASHA,GRADY,OK,34.99,-97.97,Power lines down (OUN)
    2130,UNK,JONES,OKLAHOMA,OK,35.57,-97.29,Tree limbs down (OUN)
    Time,Size,Location,County,State,Lat,Lon,Comments
    2010,175,4 W MOORE,CLEVELAND,OK,35.34,-97.56,"Golf ball hail, dents on vehicles (OUN)"
    2055,100,NORMAN,CLEVELAND,OK,35.22,-97.44,Quarter size hail (OUN)
    """

    private let day = Date(timeIntervalSince1970: 1_750_000_000)

    func testParsesAllSections() {
        let reports = SPCReportParser.parse(csv: fixtureCSV, convectiveDayUTC: day)
        XCTAssertEqual(reports.count, 5)
        XCTAssertEqual(reports.filter { $0.kind == .tornado }.count, 1)
        XCTAssertEqual(reports.filter { $0.kind == .wind }.count, 2)
        XCTAssertEqual(reports.filter { $0.kind == .hail }.count, 2)
    }

    func testHailSizeConversion() {
        let reports = SPCReportParser.parse(csv: fixtureCSV, convectiveDayUTC: day)
        let golfBall = reports.first { $0.kind == .hail && $0.location == "4 W MOORE" }
        XCTAssertNotNil(golfBall)
        XCTAssertEqual(golfBall?.hailSizeInches, 1.75)
        XCTAssertEqual(golfBall?.magnitudeText, "1.75\" hail")
    }

    func testWindSpeed() {
        let reports = SPCReportParser.parse(csv: fixtureCSV, convectiveDayUTC: day)
        let gust = reports.first { $0.kind == .wind && $0.location == "3 SSW CHICKASHA" }
        XCTAssertEqual(gust?.windSpeedMPH, 70)
        XCTAssertEqual(gust?.magnitudeText, "70 mph wind")

        let unknown = reports.first { $0.kind == .wind && $0.location == "JONES" }
        XCTAssertNil(unknown?.windSpeedMPH)
        XCTAssertEqual(unknown?.magnitudeText, "Damaging wind")
    }

    func testQuotedCommaInComments() {
        let reports = SPCReportParser.parse(csv: fixtureCSV, convectiveDayUTC: day)
        let golfBall = reports.first { $0.location == "4 W MOORE" }
        XCTAssertEqual(golfBall?.comments, "Golf ball hail, dents on vehicles (OUN)")
    }

    func testSkipsMalformedRows() {
        let malformed = """
        Time,Size,Location,County,State,Lat,Lon,Comments
        2010,175,BAD ROW MISSING FIELDS
        2055,100,NORMAN,CLEVELAND,OK,not-a-lat,-97.44,Broken latitude
        2056,125,NOBLE,CLEVELAND,OK,35.14,-97.39,Good row (OUN)
        """
        let reports = SPCReportParser.parse(csv: malformed, convectiveDayUTC: day)
        XCTAssertEqual(reports.count, 1)
        XCTAssertEqual(reports.first?.location, "NOBLE")
    }

    func testDistanceFilter() {
        let reports = SPCReportParser.parse(csv: fixtureCSV, convectiveDayUTC: day)
        // Property in Moore, OK — about a mile from the "4 W MOORE" report.
        let property = CLLocationCoordinate2D(latitude: 35.3395, longitude: -97.55)
        let nearby = reports
            .map { NearbyStormReport(report: $0, distanceMiles: $0.distanceMiles(from: property)) }
            .filter { $0.distanceMiles <= 10 }
        XCTAssertTrue(nearby.contains { $0.report.location == "4 W MOORE" })
        XCTAssertTrue(nearby.contains { $0.report.location == "NORMAN" })
        XCTAssertFalse(nearby.contains { $0.report.location == "2 N PERKINS" })
    }

    func testCSVSplitterHonorsQuotes() {
        let fields = SPCReportParser.splitCSVRow("a,\"b,c\",d")
        XCTAssertEqual(fields, ["a", "b,c", "d"])
    }
}
