import Foundation

struct MonthlyExpense: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    var taxYear: Int
    var month: Int  // 1-12

    // Housing
    var rentMortgage: Decimal
    var rentersHomeownersIns: Decimal
    var realEstateTaxes: Decimal

    // Utilities
    var electric: Decimal
    var waterSewer: Decimal
    var gasPropane: Decimal
    var garbage: Decimal
    var internet: Decimal
    var hoaDues: Decimal

    // Phone
    var cellPhone: Decimal

    // Insurance
    var malpracticeLiability: Decimal
    var healthInsurance: Decimal
    var workersComp: Decimal

    // Vehicle
    var carInsurance: Decimal
    var carPaymentInterest: Decimal
    var maintenanceRepairs: Decimal

    // Subscriptions
    var professionalMemberships: Decimal
    var softwareSubscriptions: Decimal

    // Recurring flags
    var recurringFlags: [String: Bool]?

    let createdAt: String?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case taxYear = "tax_year"
        case month
        case rentMortgage = "rent_mortgage"
        case rentersHomeownersIns = "renters_homeowners_ins"
        case realEstateTaxes = "real_estate_taxes"
        case electric
        case waterSewer = "water_sewer"
        case gasPropane = "gas_propane"
        case garbage
        case internet
        case hoaDues = "hoa_dues"
        case cellPhone = "cell_phone"
        case malpracticeLiability = "malpractice_liability"
        case healthInsurance = "health_insurance"
        case workersComp = "workers_comp"
        case carInsurance = "car_insurance"
        case carPaymentInterest = "car_payment_interest"
        case maintenanceRepairs = "maintenance_repairs"
        case professionalMemberships = "professional_memberships"
        case softwareSubscriptions = "software_subscriptions"
        case recurringFlags = "recurring_flags"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var monthTotal: Decimal {
        rentMortgage + rentersHomeownersIns + realEstateTaxes +
        electric + waterSewer + gasPropane + garbage + internet + hoaDues +
        cellPhone +
        malpracticeLiability + healthInsurance + workersComp +
        carInsurance + carPaymentInterest + maintenanceRepairs +
        professionalMemberships + softwareSubscriptions
    }

    static var fieldKeys: [(section: String, items: [(label: String, key: String)])] {
        [
            ("Housing", [
                ("Rent / Mortgage", "rent_mortgage"),
                ("Renters / Homeowners Ins.", "renters_homeowners_ins"),
                ("Real Estate Taxes", "real_estate_taxes"),
            ]),
            ("Utilities", [
                ("Electric", "electric"),
                ("Water / Sewer", "water_sewer"),
                ("Gas / Propane", "gas_propane"),
                ("Garbage", "garbage"),
                ("Internet", "internet"),
                ("HOA Dues", "hoa_dues"),
            ]),
            ("Phone", [
                ("Cell Phone", "cell_phone"),
            ]),
            ("Insurance", [
                ("Malpractice / Liability", "malpractice_liability"),
                ("Health Insurance", "health_insurance"),
                ("Workers' Comp", "workers_comp"),
            ]),
            ("Vehicle", [
                ("Car Insurance", "car_insurance"),
                ("Car Payment Interest", "car_payment_interest"),
                ("Maintenance / Repairs", "maintenance_repairs"),
            ]),
            ("Subscriptions", [
                ("Professional Memberships", "professional_memberships"),
                ("Software / Subscriptions", "software_subscriptions"),
            ]),
        ]
    }
}

struct MiscExpense: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    var date: String
    var taxYear: Int
    var month: Int
    var category: String
    var description: String?
    var amount: Decimal
    var receiptUrl: String?
    var hasReceipt: Bool
    var agencyId: UUID?
    let createdAt: String?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case date
        case taxYear = "tax_year"
        case month
        case category
        case description
        case amount
        case receiptUrl = "receipt_url"
        case hasReceipt = "has_receipt"
        case agencyId = "agency_id"
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

    static let categories: [(label: String, value: String)] = [
        ("Clinical Supplies", "clinical_supplies"),
        ("Equipment / Tools", "equipment"),
        ("Education / CE", "education_ce"),
        ("Licenses / Fees", "licenses_fees"),
        ("Uniforms / Scrubs", "uniforms"),
        ("Office Supplies", "office_supplies"),
        ("Professional Services", "professional_services"),
        ("Advertising", "advertising"),
        ("Drug Screens", "drug_screens"),
        ("B&O Taxes", "bno_taxes"),
        ("Donations", "donations"),
        ("Legal", "legal"),
        ("Depreciation", "depreciation"),
        ("Other", "other"),
    ]

    static func categoryLabel(for value: String) -> String {
        ExpenseCategoryManager.categoryLabel(for: value)
    }
}

final class ExpenseCategoryManager {
    static let shared = ExpenseCategoryManager()
    private let key = "customExpenseCategories"

    private init() {}

    var customCategories: [(label: String, value: String)] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([[String]].self, from: data) else {
            return []
        }
        return decoded.map { ($0[0], $0[1]) }
    }

    var allCategories: [(label: String, value: String)] {
        MiscExpense.categories + customCategories
    }

    func addCategory(label: String) {
        let value = label.lowercased().replacingOccurrences(of: " ", with: "_")
        var current = customCategories.map { [$0.label, $0.value] }
        guard !current.contains(where: { $0[1] == value }) else { return }
        guard !MiscExpense.categories.contains(where: { $0.value == value }) else { return }
        current.append([label, value])
        if let data = try? JSONEncoder().encode(current) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func deleteCategory(value: String) {
        var current = customCategories.map { [$0.label, $0.value] }
        current.removeAll { $0[1] == value }
        if let data = try? JSONEncoder().encode(current) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func isCustom(value: String) -> Bool {
        customCategories.contains { $0.value == value }
    }

    static func categoryLabel(for value: String) -> String {
        if let found = MiscExpense.categories.first(where: { $0.value == value }) {
            return found.label
        }
        return ExpenseCategoryManager.shared.customCategories.first(where: { $0.value == value })?.label ?? value
    }
}
