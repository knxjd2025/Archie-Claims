import Foundation
import CoreLocation

/// Fetches free, public storm data:
///  - Recent severe weather reports from the NOAA Storm Prediction Center (SPC)
///  - Active alerts for a point from the National Weather Service API
///
/// All sources are free and require no API key. SPC daily CSVs are cached on
/// disk so a day of canvassing doesn't re-download the same files.
actor StormDataService {
    static let shared = StormDataService()

    private let session: URLSession
    private var memoryCache: [String: [StormReport]] = [:]

    /// NWS asks API users to identify themselves via User-Agent.
    private var userAgent: String {
        "ArchieClaims/1.0 (roofing canvassing app; \(AppSettings.contactEmailForAPIs))"
    }

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - SPC storm reports

    /// All storm reports within `radiusMiles` of `coordinate` over the last
    /// `lookbackDays` SPC convective days, sorted newest first, closest first.
    func reports(
        near coordinate: CLLocationCoordinate2D,
        radiusMiles: Double,
        lookbackDays: Int
    ) async -> [NearbyStormReport] {
        let days = Self.recentConvectiveDays(lookbackDays: lookbackDays)

        var all: [StormReport] = []
        await withTaskGroup(of: [StormReport].self) { group in
            for day in days {
                group.addTask {
                    await self.reportsForDay(day)
                }
            }
            for await dayReports in group {
                all.append(contentsOf: dayReports)
            }
        }

        return all
            .map { NearbyStormReport(report: $0, distanceMiles: $0.distanceMiles(from: coordinate)) }
            .filter { $0.distanceMiles <= radiusMiles }
            .sorted { lhs, rhs in
                if lhs.report.dateUTC != rhs.report.dateUTC {
                    return lhs.report.dateUTC > rhs.report.dateUTC
                }
                return lhs.distanceMiles < rhs.distanceMiles
            }
    }

    /// Reports for one SPC convective day, from memory cache, disk cache, or network.
    private func reportsForDay(_ day: Date) async -> [StormReport] {
        let key = Self.yymmdd(day)
        if let cached = memoryCache[key] { return cached }

        if let disk = readDiskCache(key: key) {
            memoryCache[key] = disk
            return disk
        }

        guard let url = URL(string: "https://www.spc.noaa.gov/climo/reports/\(key)_rpts_filtered.csv") else {
            return []
        }
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let csv = String(data: data, encoding: .utf8) else {
                return []
            }
            let parsed = SPCReportParser.parse(csv: csv, convectiveDayUTC: day)
            memoryCache[key] = parsed
            writeDiskCache(key: key, reports: parsed, isToday: key == Self.yymmdd(Date()))
            return parsed
        } catch {
            return []
        }
    }

    // MARK: - NWS active alerts

    func activeAlerts(at coordinate: CLLocationCoordinate2D) async -> [NWSAlert] {
        let lat = String(format: "%.4f", coordinate.latitude)
        let lon = String(format: "%.4f", coordinate.longitude)
        guard let url = URL(string: "https://api.weather.gov/alerts/active?point=\(lat),\(lon)") else {
            return []
        }
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/geo+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return [] }
            return try JSONDecoder().decode(NWSAlertResponse.self, from: data).alerts
        } catch {
            return []
        }
    }

    // MARK: - Summaries

    /// One-paragraph plain-text summary of nearby storm evidence, used for lead
    /// snapshots and as context for the AI claim assistant.
    static func summary(of nearby: [NearbyStormReport], lookbackDays: Int) -> String {
        guard !nearby.isEmpty else {
            return "No SPC severe weather reports within range in the last \(lookbackDays) days."
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeZone = TimeZone(identifier: "UTC")

        let top = nearby.prefix(5).map { item in
            "\(item.report.magnitudeText) ~\(String(format: "%.1f", item.distanceMiles)) mi away near \(item.report.location), \(item.report.state) on \(formatter.string(from: item.report.dateUTC))"
        }
        let counts = Dictionary(grouping: nearby, by: { $0.report.kind })
            .map { "\($0.value.count) \($0.key.label.lowercased())" }
            .sorted()
            .joined(separator: ", ")
        return "Last \(lookbackDays) days: \(nearby.count) SPC reports in range (\(counts)). Closest/most recent: "
            + top.joined(separator: "; ") + "."
    }

    // MARK: - Date helpers

    /// SPC files are keyed by "convective day" (12Z–12Z) using the yymmdd of the
    /// day it starts. Walking back from yesterday avoids requesting files that
    /// don't exist yet and keeps results stable during the day.
    static func recentConvectiveDays(lookbackDays: Int, now: Date = Date()) -> [Date] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        let todayUTC = calendar.startOfDay(for: now)
        let clamped = max(1, min(lookbackDays, 120))
        return (0..<clamped).compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: todayUTC)
        }
    }

    static func yymmdd(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyMMdd"
        return formatter.string(from: date)
    }

    // MARK: - Disk cache

    private var cacheDirectory: URL? {
        guard let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dir = base.appendingPathComponent("spc-reports", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func readDiskCache(key: String) -> [StormReport]? {
        guard let url = cacheDirectory?.appendingPathComponent("\(key).json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode([StormReport].self, from: data)
    }

    private func writeDiskCache(key: String, reports: [StormReport], isToday: Bool) {
        // Today's file keeps updating on SPC's side — don't freeze it on disk.
        guard !isToday, let url = cacheDirectory?.appendingPathComponent("\(key).json"),
              let data = try? JSONEncoder().encode(reports) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
