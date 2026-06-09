import Foundation

struct Credential: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    var credentialType: String
    var issuingBody: String?
    var issueDate: String?
    var expirationDate: String?
    var documentUrl: String?
    var documentFilename: String?
    var status: String?  // "current", "expiring_soon", "expired" — computed by DB
    var alertPrefPush: Bool?
    var alertPrefEmail: Bool?
    var alertIntervals: [Int]?
    var alertSent90: Bool?
    var alertSent60: Bool?
    var alertSent30: Bool?
    var notes: String?
    let createdAt: String?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case credentialType = "credential_type"
        case issuingBody = "issuing_body"
        case issueDate = "issue_date"
        case expirationDate = "expiration_date"
        case documentUrl = "document_url"
        case documentFilename = "document_filename"
        case status
        case alertPrefPush = "alert_pref_push"
        case alertPrefEmail = "alert_pref_email"
        case alertIntervals = "alert_intervals"
        case alertSent90 = "alert_sent_90"
        case alertSent60 = "alert_sent_60"
        case alertSent30 = "alert_sent_30"
        case notes
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    var displayIssueDate: Date? {
        guard let d = issueDate else { return nil }
        return Self.dateFormatter.date(from: d)
    }

    var displayExpirationDate: Date? {
        guard let d = expirationDate else { return nil }
        return Self.dateFormatter.date(from: d)
    }

    var daysUntilExpiration: Int? {
        guard let expDate = displayExpirationDate else { return nil }
        return Calendar.current.dateComponents([.day], from: Date(), to: expDate).day
    }

    /// Computed client-side from expiration date for real-time accuracy
    var computedStatus: String {
        guard let expDate = displayExpirationDate else { return "current" }
        if expDate < Date() { return "expired" }
        if let days = daysUntilExpiration, days <= 90 { return "expiring_soon" }
        return "current"
    }

    var statusColor: String {
        switch computedStatus {
        case "expired": return Constants.Colors.errorRed
        case "expiring_soon": return Constants.Colors.warningAmber
        default: return Constants.Colors.successGreen
        }
    }

    var statusLabel: String {
        switch computedStatus {
        case "expired": return "Expired"
        case "expiring_soon":
            if let days = daysUntilExpiration {
                return "\(days) days"
            }
            return "Expiring Soon"
        default: return "Current"
        }
    }

    static let commonTypes = [
        // Nursing
        "RN License", "LPN License", "CNA Certification",
        // EMS / Medics
        "EMT-B Certification", "AEMT Certification", "Paramedic License",
        "NREMT Certification", "PHTLS", "ITLS", "AMLS",
        // Respiratory Therapy
        "RRT License", "CRT Certification", "RT State License",
        // Physical / Occupational Therapy
        "PT License", "PTA License", "OT License", "OTA License",
        // Phlebotomy
        "Phlebotomy Certification", "CPT Certification",
        // Universal Certs
        "BLS", "ACLS", "PALS", "NRP", "TNCC", "ENPC",
        "CPR Certification", "First Aid",
        "TB Screening", "Drug Screen",
        "State License", "DEA Registration",
        "Malpractice Insurance", "Liability Insurance",
        "Driver's License", "Auto Insurance",
        "Other"
    ]
}
