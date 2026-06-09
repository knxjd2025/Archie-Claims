import Foundation

/// Parses NOAA Storm Prediction Center daily storm report CSVs
/// (https://www.spc.noaa.gov/climo/reports/yymmdd_rpts_filtered.csv).
///
/// The file is three CSV sections concatenated, each starting with its own
/// header row. The second column identifies the section:
///   Time,F_Scale,Location,County,State,Lat,Lon,Comments   → tornado reports
///   Time,Speed,Location,County,State,Lat,Lon,Comments     → wind reports
///   Time,Size,Location,County,State,Lat,Lon,Comments      → hail reports
enum SPCReportParser {

    static func parse(csv: String, convectiveDayUTC: Date) -> [StormReport] {
        var reports: [StormReport] = []
        var currentKind: StormReport.Kind?

        for rawLine in csv.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            // Section header rows switch the report kind.
            if line.uppercased().hasPrefix("TIME,") {
                let header = line.uppercased()
                if header.contains(",F_SCALE,") {
                    currentKind = .tornado
                } else if header.contains(",SPEED,") {
                    currentKind = .wind
                } else if header.contains(",SIZE,") {
                    currentKind = .hail
                } else {
                    currentKind = nil
                }
                continue
            }

            guard let kind = currentKind else { continue }
            guard let report = parseRow(line, kind: kind, dateUTC: convectiveDayUTC) else { continue }
            reports.append(report)
        }
        return reports
    }

    private static func parseRow(_ line: String, kind: StormReport.Kind, dateUTC: Date) -> StormReport? {
        let fields = splitCSVRow(line)
        // Time, Magnitude, Location, County, State, Lat, Lon, Comments
        guard fields.count >= 7 else { return nil }
        guard
            let lat = Double(fields[5].trimmingCharacters(in: .whitespaces)),
            let lon = Double(fields[6].trimmingCharacters(in: .whitespaces)),
            (-90.0...90.0).contains(lat),
            (-180.0...180.0).contains(lon)
        else { return nil }

        let comments = fields.count >= 8 ? fields[7...].joined(separator: ", ") : ""
        return StormReport(
            kind: kind,
            dateUTC: dateUTC,
            timeHHMM: fields[0].trimmingCharacters(in: .whitespaces),
            rawMagnitude: fields[1].trimmingCharacters(in: .whitespaces),
            location: fields[2].trimmingCharacters(in: .whitespaces),
            county: fields[3].trimmingCharacters(in: .whitespaces),
            state: fields[4].trimmingCharacters(in: .whitespaces),
            latitude: lat,
            longitude: lon,
            comments: comments.trimmingCharacters(in: .whitespaces)
        )
    }

    /// Minimal CSV field splitter that honors double-quoted fields.
    static func splitCSVRow(_ row: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        for character in row {
            switch character {
            case "\"":
                inQuotes.toggle()
            case "," where !inQuotes:
                fields.append(current)
                current = ""
            default:
                current.append(character)
            }
        }
        fields.append(current)
        return fields
    }
}
