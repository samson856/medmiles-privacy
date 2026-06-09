import Foundation

enum MealItemType: String, Codable, CaseIterable {
    case breakfast, lunch, dinner

    var label: String {
        switch self {
        case .breakfast: return "Breakfast"
        case .lunch: return "Lunch"
        case .dinner: return "Dinner"
        }
    }
}

/// A single meal line item. A day can have several of the same type.
struct MealItem: Codable, Identifiable, Equatable {
    var id: UUID
    var type: MealItemType
    var amount: Decimal

    init(id: UUID = UUID(), type: MealItemType, amount: Decimal) {
        self.id = id
        self.type = type
        self.amount = amount
    }
}

/// Editable (form) representation of a line item — amount kept as a String so
/// in-progress typing (e.g. "12.") isn't clobbered.
struct EditableMealItem: Identifiable, Equatable {
    let id: UUID
    var type: MealItemType
    var amount: String

    init(id: UUID = UUID(), type: MealItemType, amount: String) {
        self.id = id
        self.type = type
        self.amount = amount
    }
}

struct Meal: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    var date: String  // "2026-03-23" format
    private var rawBreakfast: Decimal?
    private var rawLunch: Decimal?
    private var rawDinner: Decimal?
    var lineItems: [MealItem]?
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
        case rawBreakfast = "breakfast"
        case rawLunch = "lunch"
        case rawDinner = "dinner"
        case lineItems = "line_items"
        case dayTotal = "day_total"
        case agencyId = "agency_id"
        case businessPurpose = "business_purpose"
        case attendees
        case receiptNumber = "receipt_number"
        case receiptUrls = "receipt_urls"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    /// Source of truth: explicit line items when present, otherwise synthesized
    /// from the legacy per-type scalar columns (one item per non-zero slot) so
    /// meals saved before line items still display correctly.
    var items: [MealItem] {
        if let lineItems, !lineItems.isEmpty {
            return lineItems
        }
        var result: [MealItem] = []
        if let b = rawBreakfast, b > 0 { result.append(MealItem(type: .breakfast, amount: b)) }
        if let l = rawLunch, l > 0 { result.append(MealItem(type: .lunch, amount: l)) }
        if let d = rawDinner, d > 0 { result.append(MealItem(type: .dinner, amount: d)) }
        return result
    }

    private func sum(of type: MealItemType) -> Decimal {
        items.filter { $0.type == type }.reduce(0) { $0 + $1.amount }
    }

    // Per-type totals (computed) — keeps every existing reader working.
    var breakfast: Decimal { sum(of: .breakfast) }
    var lunch: Decimal { sum(of: .lunch) }
    var dinner: Decimal { sum(of: .dinner) }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    var displayDate: Date {
        Self.dateFormatter.date(from: date) ?? Date()
    }

    var calculatedTotal: Decimal {
        items.reduce(0) { $0 + $1.amount }
    }
}
