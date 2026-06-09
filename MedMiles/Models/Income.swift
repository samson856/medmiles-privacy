import Foundation

struct Income: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    var contractVisitId: String?
    var dateOfService: String  // "2026-03-23" format
    var datePaid: String?
    var agencyId: UUID?
    var visitTypeId: UUID?
    var destinationCity: String?
    var rateType: String?  // "flat_rate" | "hourly"
    var advertisedRate: String?
    var grossPay: Decimal
    var taxSetAsideAmount: Decimal?
    var taxSetAsidePct: Decimal?
    var netPay: Decimal?
    var status: String  // "pending" | "completed"
    var notes: String?
    let createdAt: String?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case contractVisitId = "contract_visit_id"
        case dateOfService = "date_of_service"
        case datePaid = "date_paid"
        case agencyId = "agency_id"
        case visitTypeId = "visit_type_id"
        case destinationCity = "destination_city"
        case rateType = "rate_type"
        case advertisedRate = "advertised_rate"
        case grossPay = "gross_pay"
        case taxSetAsideAmount = "tax_set_aside_amount"
        case taxSetAsidePct = "tax_set_aside_pct"
        case netPay = "net_pay"
        case status
        case notes
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    var displayDate: Date {
        Self.dateFormatter.date(from: dateOfService) ?? Date()
    }

    var displayDatePaid: Date? {
        guard let datePaid = datePaid else { return nil }
        return Self.dateFormatter.date(from: datePaid)
    }
}
