import Foundation

struct Trip: Codable, Identifiable, Hashable {
    let id: UUID
    let userId: UUID
    var date: String  // "2026-03-23" format from Supabase
    var trackingMethod: String  // "odometer" or "address"

    // Odometer mode
    var odometerStart: Decimal?
    var odometerStop: Decimal?

    // Address mode
    var startAddress: String?
    var endAddress: String?

    // Shared fields
    var distanceMiles: Decimal?
    var destinationCity: String?
    var agencyId: UUID?
    var visitTypeId: UUID?
    var contractVisitId: String?

    // Trip expenses
    var tolls: Decimal?
    var parking: Decimal?
    var ferry: Decimal?
    var otherExpense: Decimal?

    var notes: String?
    let createdAt: String?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case date
        case trackingMethod = "tracking_method"
        case odometerStart = "odometer_start"
        case odometerStop = "odometer_stop"
        case startAddress = "start_address"
        case endAddress = "end_address"
        case distanceMiles = "distance_miles"
        case destinationCity = "destination_city"
        case agencyId = "agency_id"
        case visitTypeId = "visit_type_id"
        case contractVisitId = "contract_visit_id"
        case tolls, parking, ferry
        case otherExpense = "other_expense"
        case notes
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    // Helper to get a displayable Date
    var displayDate: Date {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: date) ?? Date()
    }
}
