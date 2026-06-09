import Foundation

/// Tax constants that change annually, fetched from Supabase and cached locally.
struct TaxConstants: Codable {
    let taxYear: Int
    let irsMileageRate: Decimal
    let seTaxRate: Decimal
    let seIncomeMultiplier: Decimal
    let mealDeductionPct: Decimal
    let homeOfficeSimplifiedRate: Decimal
    let homeOfficeMaxSqFt: Int
    let standardDeductionSingle: Decimal
    let standardDeductionMarriedJoint: Decimal
    let standardDeductionMarriedSeparate: Decimal
    let standardDeductionHeadOfHousehold: Decimal

    // Tax bracket thresholds (single filer) — stored as arrays
    let bracketRates: [Decimal]       // e.g. [0.10, 0.12, 0.22, 0.24, 0.32, 0.35, 0.37]
    let bracketThresholds: [Decimal]  // e.g. [0, 11600, 47150, 100525, 191950, 243725, 609350]

    let createdAt: String?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case taxYear = "tax_year"
        case irsMileageRate = "irs_mileage_rate"
        case seTaxRate = "se_tax_rate"
        case seIncomeMultiplier = "se_income_multiplier"
        case mealDeductionPct = "meal_deduction_pct"
        case homeOfficeSimplifiedRate = "home_office_simplified_rate"
        case homeOfficeMaxSqFt = "home_office_max_sq_ft"
        case standardDeductionSingle = "standard_deduction_single"
        case standardDeductionMarriedJoint = "standard_deduction_married_joint"
        case standardDeductionMarriedSeparate = "standard_deduction_married_separate"
        case standardDeductionHeadOfHousehold = "standard_deduction_head_of_household"
        case bracketRates = "bracket_rates"
        case bracketThresholds = "bracket_thresholds"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    // MARK: - Helpers

    func standardDeduction(for filingStatus: String) -> Decimal {
        switch filingStatus {
        case "married_joint": return standardDeductionMarriedJoint
        case "married_separate": return standardDeductionMarriedSeparate
        case "head_of_household": return standardDeductionHeadOfHousehold
        default: return standardDeductionSingle
        }
    }

    func federalIncomeTax(on taxableIncome: Decimal) -> Decimal {
        guard taxableIncome > 0 else { return 0 }
        var tax: Decimal = 0
        let rates = bracketRates
        let thresholds = bracketThresholds

        for i in 0..<rates.count {
            let lower = thresholds[i]
            let upper = (i + 1 < thresholds.count) ? thresholds[i + 1] : taxableIncome + 1
            if taxableIncome <= lower { break }
            let taxableInBracket = min(taxableIncome, upper) - lower
            tax += taxableInBracket * rates[i]
        }
        return tax
    }

    // MARK: - Hardcoded Defaults (fallback when offline + no cache)

    static func defaults(for year: Int) -> TaxConstants {
        let mileageRate: Decimal = year <= 2025
            ? (Decimal(string: "0.70") ?? 0)
            : (Decimal(string: "0.725") ?? 0)

        return TaxConstants(
            taxYear: year,
            irsMileageRate: mileageRate,
            seTaxRate: Decimal(string: "0.153") ?? 0,
            seIncomeMultiplier: Decimal(string: "0.9235") ?? 0,
            mealDeductionPct: Decimal(string: "0.5") ?? 0,
            homeOfficeSimplifiedRate: 5,
            homeOfficeMaxSqFt: 300,
            standardDeductionSingle: 15000,
            standardDeductionMarriedJoint: 30000,
            standardDeductionMarriedSeparate: 15000,
            standardDeductionHeadOfHousehold: 22500,
            bracketRates: [
                Decimal(string: "0.10") ?? Decimal(0), Decimal(string: "0.12") ?? Decimal(0),
                Decimal(string: "0.22") ?? Decimal(0), Decimal(string: "0.24") ?? Decimal(0),
                Decimal(string: "0.32") ?? Decimal(0), Decimal(string: "0.35") ?? Decimal(0),
                Decimal(string: "0.37") ?? Decimal(0)
            ],
            bracketThresholds: [0, 11925, 48475, 103350, 197300, 250525, 626350],
            createdAt: nil,
            updatedAt: nil
        )
    }
}
