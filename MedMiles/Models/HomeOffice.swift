import Foundation

struct HomeOffice: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    var taxYear: Int
    var totalSqFt: Decimal?
    var officeSqFt: Decimal?
    var businessUsePct: Decimal?
    var activeMonths: [Bool]
    let createdAt: String?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case taxYear = "tax_year"
        case totalSqFt = "total_sq_ft"
        case officeSqFt = "office_sq_ft"
        case businessUsePct = "business_use_pct"
        case activeMonths = "active_months"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    func isMonthActive(_ month: Int) -> Bool {
        guard month >= 0, month < activeMonths.count else { return false }
        return activeMonths[month]
    }

    var activeMonthCount: Int {
        activeMonths.filter { $0 }.count
    }

    static let monthNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                             "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
}
