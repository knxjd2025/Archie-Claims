import Foundation

/// CRM calls against the main Archie backend: client search, claim/CRM
/// context for the AI assistant, document upload (R2 presigned flow), and
/// communication logging. All endpoints require the Bearer JWT from
/// `ArchieBackendService`; a 401 triggers one silent re-login.
extension ArchieBackendService {

    // MARK: - Models

    struct ClientHit: Identifiable, Hashable {
        let id: String
        /// "lead" | "job" (estimates/invoices are surfaced but not attachable).
        let entityType: String
        let displayName: String
        let displaySubtitle: String
    }

    /// Everything the assistant gets to know about an attached client.
    struct ClientAttachment {
        let hit: ClientHit
        /// Compact JSON sent as `context.current_project` — the server injects
        /// it into the system prompt verbatim.
        let context: [String: Any]
        let claimID: String?
        let leadID: String?
        let jobID: String?
        let summary: String

        var displayName: String { hit.displayName }
    }

    // MARK: - Generic authorized JSON request

    /// Performs an authorized JSON request with one silent token refresh on 401.
    func authorizedJSON(
        path: String,
        method: String = "GET",
        query: [URLQueryItem] = [],
        body: [String: Any]? = nil
    ) async throws -> Any {
        guard var token = KeychainStore.read(account: KeychainStore.archieTokenAccount),
              !token.isEmpty else {
            throw BackendError.notSignedIn
        }

        var attempt = 0
        while true {
            attempt += 1
            var components = URLComponents(
                url: baseURL.appendingPathComponent(path),
                resolvingAgainstBaseURL: false
            )
            if !query.isEmpty { components?.queryItems = query }
            guard let url = components?.url else { throw BackendError.malformedResponse }

            var request = URLRequest(url: url)
            request.httpMethod = method
            request.timeoutInterval = 60
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            if let body {
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
            }

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw BackendError.malformedResponse }

            if http.statusCode == 401, attempt == 1 {
                token = try await refreshSessionToken()
                continue
            }
            if http.statusCode == 401 { throw BackendError.sessionExpired }
            if http.statusCode == 429 { throw BackendError.rateLimited }
            guard (200...299).contains(http.statusCode) else {
                throw BackendError.http(status: http.statusCode, message: Self.errorMessageText(from: data))
            }
            return (try? JSONSerialization.jsonObject(with: data)) ?? [:]
        }
    }

    // MARK: - Paid owner report (Tracerfy) + data credits

    struct OwnerPhone: Identifiable {
        var id: String { number }
        let number: String
        let type: String?
        let dnc: Bool
        let carrier: String?
    }

    struct OwnerReport {
        let name: String?
        let phones: [OwnerPhone]
        let emails: [String]
        let mailingAddress: String?
        let litigator: Bool
        let ownerOccupied: Bool?
        let propertyType: String?
        let yearBuilt: Int?
        let roofMaterial: String?
        let estimatedValue: Int?
        let roofPropensityScore: Int?
        let roofPropensityCategory: String?
        let remainingCredits: Int?
    }

    struct CreditItem: Identifiable {
        let id: String
        let kind: String        // "subscription" | "pack"
        let interval: String?   // "month" | "year"
        let credits: Int
        let label: String
        let appleUSD: Double
        let appleProductID: String
        let stripeUSD: Double
    }

    struct CreditInfo {
        var balance: Int
        var plan: String?
        var costPerReport: Int
        var items: [CreditItem]
        var paygAppleUSD: Double?
        var paygStripeUSD: Double?
        var stripeDiscountPercent: Int
    }

    enum OwnerLookupError: LocalizedError {
        case notConfigured
        case noOwnerFound
        case insufficientCredits
        case message(String)

        var errorDescription: String? {
            switch self {
            case .notConfigured:
                return "Owner lookup isn't set up yet. An admin needs to add the Tracerfy API token in the Archie backend."
            case .noOwnerFound:
                return "No owner record was found for this property."
            case .insufficientCredits:
                return "You're out of data credits."
            case .message(let m):
                return m
            }
        }
    }

    /// `GET /api/property/credits` — balance + plan + purchase catalog.
    func creditInfo() async throws -> CreditInfo {
        let result = try await authorizedJSON(path: "api/property/credits")
        guard let dict = result as? [String: Any] else { throw BackendError.malformedResponse }
        let catalog = dict["catalog"] as? [String: Any] ?? [:]
        let payg = catalog["pay_as_you_go"] as? [String: Any] ?? [:]
        let items = (catalog["items"] as? [[String: Any]] ?? []).compactMap { i -> CreditItem? in
            guard let id = i["id"] as? String, let credits = i["credits"] as? Int,
                  let productID = i["apple_product_id"] as? String else { return nil }
            return CreditItem(
                id: id,
                kind: i["kind"] as? String ?? "pack",
                interval: i["interval"] as? String,
                credits: credits,
                label: i["label"] as? String ?? "\(credits) credits",
                appleUSD: (i["apple_usd"] as? NSNumber)?.doubleValue ?? 0,
                appleProductID: productID,
                stripeUSD: (i["stripe_usd"] as? NSNumber)?.doubleValue ?? 0
            )
        }
        return CreditInfo(
            balance: dict["balance"] as? Int ?? 0,
            plan: dict["plan"] as? String,
            costPerReport: dict["cost_per_report"] as? Int ?? 1,
            items: items,
            paygAppleUSD: (payg["apple_usd"] as? NSNumber)?.doubleValue,
            paygStripeUSD: (payg["stripe_usd"] as? NSNumber)?.doubleValue,
            stripeDiscountPercent: catalog["stripe_discount_percent"] as? Int ?? 10
        )
    }

    /// `POST /api/property/credits/checkout` — Stripe web checkout URL (10% off).
    func creditCheckoutURL(itemID: String) async throws -> URL {
        let result = try await authorizedJSON(
            path: "api/property/credits/checkout", method: "POST", body: ["item_id": itemID]
        )
        guard let dict = result as? [String: Any],
              let urlString = dict["url"] as? String, let url = URL(string: urlString) else {
            throw BackendError.malformedResponse
        }
        return url
    }

    /// `POST /api/property/credits/iap` — redeem an Apple StoreKit purchase.
    /// Sends the signed JWS so the backend can verify it with Apple. Returns the
    /// new credit balance.
    @discardableResult
    func redeemIAP(productID: String, transactionID: String, jws: String) async throws -> Int {
        let result = try await authorizedJSON(
            path: "api/property/credits/iap", method: "POST",
            body: ["product_id": productID, "transaction_id": transactionID, "jws": jws]
        )
        return (result as? [String: Any])?["balance"] as? Int ?? 0
    }

    /// `POST /api/property/owner-report` — spends 1 data credit, returns the
    /// Tracerfy owner dossier (name, phones w/ DNC flags, emails, property data).
    func ownerReport(address: String, city: String, state: String, zip: String) async throws -> OwnerReport {
        do {
            let result = try await authorizedJSON(
                path: "api/property/owner-report",
                method: "POST",
                body: ["address": address, "city": city, "state": state, "zip": zip]
            )
            guard let dict = result as? [String: Any],
                  let owner = dict["owner"] as? [String: Any] else {
                throw OwnerLookupError.message("The owner report came back in an unexpected format.")
            }
            let phones = (owner["phones"] as? [[String: Any]] ?? []).compactMap { p -> OwnerPhone? in
                guard let number = p["number"] as? String, !number.isEmpty else { return nil }
                return OwnerPhone(number: number, type: p["type"] as? String,
                                  dnc: p["dnc"] as? Bool ?? false, carrier: p["carrier"] as? String)
            }
            return OwnerReport(
                name: owner["name"] as? String,
                phones: phones,
                emails: (owner["emails"] as? [String]) ?? [],
                mailingAddress: owner["mailing_address"] as? String,
                litigator: owner["litigator"] as? Bool ?? false,
                ownerOccupied: owner["owner_occupied"] as? Bool,
                propertyType: owner["property_type"] as? String,
                yearBuilt: owner["year_built"] as? Int,
                roofMaterial: owner["roof_material"] as? String,
                estimatedValue: owner["estimated_value"] as? Int,
                roofPropensityScore: owner["roof_propensity_score"] as? Int,
                roofPropensityCategory: owner["roof_propensity_category"] as? String,
                remainingCredits: dict["remaining_credits"] as? Int
            )
        } catch let BackendError.http(status, message) {
            switch status {
            case 503: throw OwnerLookupError.notConfigured
            case 404: throw OwnerLookupError.noOwnerFound
            case 402: throw OwnerLookupError.insufficientCredits
            default: throw OwnerLookupError.message(message)
            }
        }
    }

    // MARK: - Client search & context

    /// `GET /api/crm-dashboard/search` — one search across leads and jobs
    /// (customers). The server requires 2+ characters.
    func searchClients(query: String) async throws -> [ClientHit] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else { return [] }
        let result = try await authorizedJSON(
            path: "api/crm-dashboard/search",
            query: [URLQueryItem(name: "q", value: trimmed), URLQueryItem(name: "limit", value: "20")]
        )
        let rows = ((result as? [String: Any])?["results"] as? [[String: Any]]) ?? []
        return rows.compactMap { row in
            guard let id = Self.string(row["id"]),
                  let type = row["entity_type"] as? String,
                  type == "lead" || type == "job" else { return nil }
            return ClientHit(
                id: id,
                entityType: type,
                displayName: (row["display_name"] as? String) ?? "Unknown",
                displaySubtitle: (row["display_subtitle"] as? String) ?? ""
            )
        }
    }

    /// Builds the full AI context for a picked client: lead/job record, any
    /// linked claim (with documents), and recent communications.
    func clientAttachment(for hit: ClientHit) async throws -> ClientAttachment {
        var context: [String: Any] = [
            "client_name": hit.displayName,
            "crm_record_type": hit.entityType
        ]
        var leadID: String?
        var jobID: String?
        var summaryParts: [String] = [hit.displayName]

        if hit.entityType == "lead" {
            leadID = hit.id
            let detail = try await authorizedJSON(path: "api/leads/\(hit.id)")
            if let lead = (detail as? [String: Any])?["lead"] as? [String: Any] {
                context["lead"] = Self.compact(lead, keeping: [
                    "first_name", "last_name", "email", "phone", "address_line1", "city",
                    "state", "zip", "status", "priority", "source", "damage_type",
                    "damage_notes", "roof_type", "roof_age_years", "insurance_claim",
                    "estimated_value", "next_follow_up_date"
                ])
                if let address = lead["address_line1"] as? String { summaryParts.append(address) }
                if let status = lead["status"] as? String { summaryParts.append("lead: \(status)") }
            }
            if let activities = (detail as? [String: Any])?["activities"] as? [[String: Any]] {
                context["recent_activity"] = activities.prefix(5).map {
                    Self.compact($0, keeping: ["activity_type", "title", "created_at"])
                }
            }
        } else {
            jobID = hit.id
            let detail = try await authorizedJSON(
                path: "api/crm-jobs/\(hit.id)",
                query: [URLQueryItem(name: "include", value: "projects,invoices,activities")]
            )
            if let job = (detail as? [String: Any])?["job"] as? [String: Any] {
                context["customer"] = Self.compact(job, keeping: [
                    "first_name", "last_name", "email", "phone", "property_address",
                    "property_city", "property_state", "property_zip", "customer_type",
                    "pipeline_stage", "job_number", "insurance_claim", "insurance_carrier",
                    "notes", "total_lifetime_value", "total_projects"
                ])
                leadID = Self.string(job["lead_id"])
                if let address = job["property_address"] as? String { summaryParts.append(address) }
                if let stage = job["pipeline_stage"] as? String { summaryParts.append("stage: \(stage)") }
            }
        }

        // Claims: no lead_id/job_id filter server-side — search by name and
        // match client-side on the FK columns.
        var claimID: String?
        if let claims = try? await authorizedJSON(
            path: "api/claims",
            query: [URLQueryItem(name: "search", value: hit.displayName)]
        ), let rows = (claims as? [String: Any])?["claims"] as? [[String: Any]] {
            let match = rows.first { row in
                (leadID != nil && Self.string(row["lead_id"]) == leadID)
                    || (jobID != nil && Self.string(row["job_id"]) == jobID)
            } ?? (rows.count == 1 ? rows[0] : nil)
            if let claim = match {
                claimID = Self.string(claim["id"])
                context["insurance_claim"] = Self.compact(claim, keeping: [
                    "claim_number", "insurance_company", "policy_number", "status",
                    "claim_type", "priority", "date_of_loss", "adjuster_name",
                    "adjuster_phone", "adjuster_email", "total_estimated", "total_approved",
                    "deductible", "notes"
                ])
                if let number = claim["claim_number"] as? String { summaryParts.append("claim \(number)") }

                if let id = claimID,
                   let docs = try? await authorizedJSON(path: "api/claims/\(id)/documents"),
                   let docRows = (docs as? [String: Any])?["documents"] as? [[String: Any]] {
                    context["claim_documents_on_file"] = docRows.prefix(10).map {
                        Self.compact($0, keeping: ["name", "document_type", "created_at"])
                    }
                }
            }
        }

        // Recent communication log entries (calls/emails/texts/notes).
        var logQuery: [URLQueryItem] = [URLQueryItem(name: "limit", value: "10")]
        if let leadID { logQuery.append(URLQueryItem(name: "lead_id", value: leadID)) }
        else if let jobID { logQuery.append(URLQueryItem(name: "job_id", value: jobID)) }
        if logQuery.count > 1,
           let log = try? await authorizedJSON(path: "api/communications/log", query: logQuery),
           let entries = (log as? [String: Any])?["entries"] as? [[String: Any]] {
            context["recent_communications"] = entries.prefix(8).map {
                Self.compact($0, keeping: ["activity_type", "title", "description", "created_at"])
            }
        }

        return ClientAttachment(
            hit: hit,
            context: context,
            claimID: claimID,
            leadID: leadID,
            jobID: jobID,
            summary: summaryParts.joined(separator: " · ")
        )
    }

    // MARK: - Document upload (R2 presigned flow)

    /// Uploads file bytes via the backend's presigned R2 flow and returns the
    /// public URL. `size` is signed into the PUT, so Content-Length must match.
    func uploadFile(data: Data, filename: String, mimeType: String) async throws -> String {
        let presign = try await authorizedJSON(
            path: "api/r2/upload",
            method: "POST",
            body: ["filename": filename, "contentType": mimeType, "size": data.count]
        )
        guard let dict = presign as? [String: Any],
              let uploadURLString = dict["uploadUrl"] as? String,
              let publicURL = dict["publicUrl"] as? String,
              let uploadURL = URL(string: uploadURLString) else {
            throw BackendError.malformedResponse
        }

        var put = URLRequest(url: uploadURL)
        put.httpMethod = "PUT"
        put.timeoutInterval = 300
        put.setValue(mimeType, forHTTPHeaderField: "Content-Type")
        let (_, response) = try await URLSession.shared.upload(for: put, from: data)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw BackendError.http(
                status: (response as? HTTPURLResponse)?.statusCode ?? 0,
                message: "File upload to storage failed."
            )
        }
        return publicURL
    }

    /// Registers an uploaded file on a claim (`claim_documents`), which also
    /// logs a `document_uploaded` activity in the CRM.
    func registerClaimDocument(
        claimID: String,
        name: String,
        fileURL: String,
        documentType: String,
        fileSize: Int,
        mimeType: String,
        notes: String? = nil
    ) async throws {
        var body: [String: Any] = [
            "name": name,
            "file_url": fileURL,
            "document_type": documentType,
            "file_size": fileSize,
            "mime_type": mimeType
        ]
        if let notes { body["notes"] = notes }
        _ = try await authorizedJSON(path: "api/claims/\(claimID)/documents", method: "POST", body: body)
    }

    /// Logs an email/note against the client's lead or job in the CRM.
    func logCommunication(
        leadID: String?,
        jobID: String?,
        type: String,
        title: String,
        description: String
    ) async throws {
        var body: [String: Any] = [
            "communication_type": type,
            "title": String(title.prefix(200)),
            "description": String(description.prefix(8000)),
            "direction": "inbound"
        ]
        if let leadID { body["lead_id"] = leadID }
        else if let jobID { body["job_id"] = jobID }
        else { return }
        _ = try await authorizedJSON(path: "api/communications/log", method: "POST", body: body)
    }

    // MARK: - Helpers

    private func refreshSessionToken() async throws -> String {
        guard let email = KeychainStore.read(account: KeychainStore.archieEmailAccount),
              let password = KeychainStore.read(account: KeychainStore.archiePasswordAccount),
              !email.isEmpty, !password.isEmpty else {
            throw BackendError.sessionExpired
        }
        do {
            try await signIn(email: email, password: password)
        } catch {
            throw BackendError.sessionExpired
        }
        guard let token = KeychainStore.read(account: KeychainStore.archieTokenAccount) else {
            throw BackendError.sessionExpired
        }
        return token
    }

    static func errorMessageText(from data: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return String(data: data.prefix(300), encoding: .utf8) ?? "No details provided."
        }
        return (object["error"] as? String) ?? (object["message"] as? String) ?? "No details provided."
    }

    /// Keeps only the listed keys with non-empty, non-null values.
    private static func compact(_ dict: [String: Any], keeping keys: [String]) -> [String: Any] {
        var out: [String: Any] = [:]
        for key in keys {
            guard let value = dict[key], !(value is NSNull) else { continue }
            if let text = value as? String, text.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            out[key] = value
        }
        return out
    }

    private static func string(_ value: Any?) -> String? {
        if let s = value as? String { return s }
        if let n = value as? NSNumber { return n.stringValue }
        return nil
    }
}
