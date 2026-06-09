import Foundation

struct Meal: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    var date: String  // "2026-03-23" format
    var breakfast: Decimal
    var lunch: Decimal
    var dinner: Decimal
    var dayTotal: Decimal?
    var agencyId: UUID?
    var businessPurpose: String?
    var attendees: String?
    var receiptNumber: String?
    var receiptUrls: [String]?
    let createdAt: String?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case date
        case breakfast, lunch, dinner
        case dayTotal = "day_total"
        case agencyId = "agency_id"
        case businessPurpose = "business_purpose"
        case attendees
        case receiptNumber = "receipt_number"
        case receiptUrls = "receipt_urls"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    var displayDate: Date {
        Self.dateFormatter.date(from: date) ?? Date()
    }

    var calculatedTotal: Decimal {
        breakfast + lunch + dinner
    }
}
