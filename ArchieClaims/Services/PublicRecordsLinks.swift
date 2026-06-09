import Foundation

/// Builds links to FREE, publicly available sources where a user can look up
/// property and contact information for an address: county assessor records,
/// free people-search sites, and plain web search.
///
/// The app does not scrape or store anything from these sites — it opens them
/// in an in-app browser. Users are reminded to verify information and to
/// comply with applicable laws (e.g. TCPA for calls/texts, local solicitation
/// rules, do-not-knock lists) before contacting anyone.
enum PublicRecordsLinks {

    struct PublicLink: Identifiable {
        var id: String { title }
        let title: String
        let subtitle: String
        let url: URL
    }

    static func links(address: String, city: String, state: String, postalCode: String, county: String) -> [PublicLink] {
        var results: [PublicLink] = []
        let street = address.components(separatedBy: ",").first ?? address
        let cityStateZip = [city, state, postalCode].filter { !$0.isEmpty }.joined(separator: " ")

        func encode(_ value: String) -> String {
            value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
        }

        // County assessor / official property records (via NETR's free directory
        // of official county sites, plus a targeted web search).
        if !state.isEmpty {
            if let url = URL(string: "https://publicrecords.netronline.com/state/\(encode(state))") {
                results.append(PublicLink(
                    title: "County Property Records",
                    subtitle: "Official assessor & recorder sites (NETR directory)",
                    url: url
                ))
            }
            let assessorQuery = "\(county.isEmpty ? city : county) county \(state) property assessor search \(street)"
            if let url = URL(string: "https://www.google.com/search?q=\(encode(assessorQuery))") {
                results.append(PublicLink(
                    title: "Assessor Search",
                    subtitle: "Find the parcel & owner of record",
                    url: url
                ))
            }
        }

        // Free people-search sites (publicly aggregated data — verify before use).
        if let url = URL(string: "https://www.truepeoplesearch.com/resultaddress?streetaddress=\(encode(street))&citystatezip=\(encode(cityStateZip))") {
            results.append(PublicLink(
                title: "TruePeopleSearch",
                subtitle: "Free resident & phone lookup by address",
                url: url
            ))
        }
        if let url = URL(string: "https://www.fastpeoplesearch.com/address/\(encode(street.replacingOccurrences(of: " ", with: "-")))_\(encode(city.replacingOccurrences(of: " ", with: "-")))-\(encode(state))") {
            results.append(PublicLink(
                title: "FastPeopleSearch",
                subtitle: "Free resident lookup by address",
                url: url
            ))
        }

        // Plain web search for the full address.
        let full = [street, cityStateZip].filter { !$0.isEmpty }.joined(separator: ", ")
        if let url = URL(string: "https://www.google.com/search?q=\(encode("\"\(full)\""))") {
            results.append(PublicLink(
                title: "Web Search",
                subtitle: "Everything public about this address",
                url: url
            ))
        }
        return results
    }

    static let complianceNote = """
    These are public sources — accuracy is not guaranteed; verify before use. Use contact info responsibly \
    and lawfully: honor do-not-knock lists and local solicitation permits, and follow TCPA/do-not-call rules \
    for calls and texts.
    """
}
