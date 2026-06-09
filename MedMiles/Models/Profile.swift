import Foundation

struct Profile: Codable, Identifiable {
    let id: UUID
    var email: String
    var fullName: String?
    var profession: String?
    var specialty: String?
    var state: String?
    var filingStatus: String?
    var taxSetAsidePct: Decimal?
    var plan: String?
    var isPro: Bool?
    var createdAt: Date?
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, email, profession, specialty, state, plan
        case fullName = "full_name"
        case filingStatus = "filing_status"
        case taxSetAsidePct = "tax_set_aside_pct"
        case isPro = "is_pro"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

extension Profile {
    static let professions = [
        "Registered Nurse (RN)",
        "Licensed Practical Nurse (LPN)",
        "Certified Nursing Assistant (CNA)",
        "EMT",
        "Paramedic",
        "Physical Therapist (PT)",
        "Occupational Therapist (OT)",
        "Respiratory Therapist (RT)",
        "Phlebotomist",
        "Radiologic Technologist",
        "Surgical Technologist",
        "Medical Laboratory Technician",
        "Speech-Language Pathologist",
        "Other"
    ]

    static let usStates = [
        "AL", "AK", "AZ", "AR", "CA", "CO", "CT", "DE", "FL", "GA",
        "HI", "ID", "IL", "IN", "IA", "KS", "KY", "LA", "ME", "MD",
        "MA", "MI", "MN", "MS", "MO", "MT", "NE", "NV", "NH", "NJ",
        "NM", "NY", "NC", "ND", "OH", "OK", "OR", "PA", "RI", "SC",
        "SD", "TN", "TX", "UT", "VT", "VA", "WA", "WV", "WI", "WY",
        "DC"
    ]

    static let filingStatuses = [
        ("single", "Single"),
        ("married_joint", "Married Filing Jointly"),
        ("married_separate", "Married Filing Separately"),
        ("head_of_household", "Head of Household")
    ]
}
