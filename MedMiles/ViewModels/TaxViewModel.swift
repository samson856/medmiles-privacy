import Foundation
import Supabase
import Combine

@MainActor
final class TaxViewModel: ObservableObject {
    private let client = SupabaseService.shared.client

    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var filingStatus: String = "single"

    // YTD totals
    @Published var grossIncome: Decimal = 0
    @Published var totalMiles: Decimal = 0
    @Published var totalTripExpenses: Decimal = 0
    @Published var totalMealSpend: Decimal = 0
    @Published var totalMiscExpenses: Decimal = 0
    @Published var homeOfficeExpenses: Decimal = 0
    @Published var directBusinessExpenses: Decimal = 0
    @Published var cellPhoneExpenses: Decimal = 0
    @Published var healthInsuranceExpenses: Decimal = 0
    @Published var businessUsePct: Decimal = 0

    // Current quarter totals
    @Published var quarterIncome: Decimal = 0
    @Published var quarterDeductions: Decimal = 0

    @Published var currentYear = Calendar.current.component(.year, from: Date())

    var tc: TaxConstants {
        TaxConstantsService.shared.constantsForYear(currentYear)
    }

    /// Switch to a different tax year and reload all data
    func switchYear(to year: Int, userId: UUID) async {
        currentYear = year
        await TaxConstantsService.shared.fetchConstants(for: currentYear)
        await loadTaxData(userId: userId)
    }

    // MARK: - Quarter Helpers

    /// Current quarter number (1-4) based on today's date
    var currentQuarter: Int {
        let month = Calendar.current.component(.month, from: Date())
        return ((month - 1) / 3) + 1
    }

    /// Date range for a given quarter
    private func quarterDateRange(quarter: Int, year: Int) -> (start: String, end: String) {
        switch quarter {
        case 1: return ("\(year)-01-01", "\(year)-03-31")
        case 2: return ("\(year)-04-01", "\(year)-06-30")
        case 3: return ("\(year)-07-01", "\(year)-09-30")
        default: return ("\(year)-10-01", "\(year)-12-31")
        }
    }

    /// Check if a date string falls within a quarter
    private func isInQuarter(_ dateStr: String, quarter: Int, year: Int) -> Bool {
        let range = quarterDateRange(quarter: quarter, year: year)
        return dateStr >= range.start && dateStr <= range.end
    }

    /// Check if a month number falls within a quarter
    private func isMonthInQuarter(_ month: Int, quarter: Int) -> Bool {
        let startMonth = (quarter - 1) * 3 + 1
        let endMonth = quarter * 3
        return month >= startMonth && month <= endMonth
    }

    // MARK: - Load

    func loadTaxData(userId: UUID) async {
        isLoading = true
        defer { isLoading = false }

        let startDate = "\(currentYear)-01-01"
        let endDate = "\(currentYear)-12-31"
        let quarter = currentQuarter

        do {
            // Profile for filing status
            let profile: Profile = try await client.from("profiles")
                .select()
                .eq("id", value: userId)
                .single()
                .execute()
                .value
            filingStatus = profile.filingStatus ?? "single"

            // Income
            let income: [Income] = try await client.from("income")
                .select()
                .eq("user_id", value: userId)
                .gte("date_of_service", value: startDate)
                .lte("date_of_service", value: endDate)
                .execute()
                .value
            var incTotal: Decimal = 0
            var qInc: Decimal = 0
            for entry in income {
                incTotal += entry.grossPay
                if isInQuarter(entry.dateOfService, quarter: quarter, year: currentYear) {
                    qInc += entry.grossPay
                }
            }
            grossIncome = incTotal
            quarterIncome = qInc

            // Trips — mileage AND expenses
            let trips: [Trip] = try await client.from("trips")
                .select()
                .eq("user_id", value: userId)
                .gte("date", value: startDate)
                .lte("date", value: endDate)
                .execute()
                .value
            var tripMiles: Decimal = 0
            var tripExp: Decimal = 0
            var qMiles: Decimal = 0
            var qTripExp: Decimal = 0
            for trip in trips {
                let miles = trip.distanceMiles ?? 0
                let expenses = (trip.tolls ?? 0) + (trip.parking ?? 0) + (trip.ferry ?? 0) + (trip.otherExpense ?? 0)
                tripMiles += miles
                tripExp += expenses
                if isInQuarter(trip.date, quarter: quarter, year: currentYear) {
                    qMiles += miles
                    qTripExp += expenses
                }
            }
            totalMiles = tripMiles
            totalTripExpenses = tripExp

            // Meals
            let meals: [Meal] = try await client.from("meals")
                .select()
                .eq("user_id", value: userId)
                .gte("date", value: startDate)
                .lte("date", value: endDate)
                .execute()
                .value
            var mealTotal: Decimal = 0
            var qMeals: Decimal = 0
            for meal in meals {
                let total = meal.calculatedTotal
                mealTotal += total
                if isInQuarter(meal.date, quarter: quarter, year: currentYear) {
                    qMeals += total
                }
            }
            totalMealSpend = mealTotal

            // Home office — get business use %
            let hoResults: [HomeOffice] = try await client.from("home_office")
                .select()
                .eq("user_id", value: userId)
                .eq("tax_year", value: currentYear)
                .execute()
                .value
            let ho = hoResults.first
            businessUsePct = ho?.businessUsePct ?? 0

            // Monthly expenses — split into categories
            let monthly: [MonthlyExpense] = try await client.from("monthly_expenses")
                .select()
                .eq("user_id", value: userId)
                .eq("tax_year", value: currentYear)
                .execute()
                .value

            var hoExpTotal: Decimal = 0
            var bizExpTotal: Decimal = 0
            var healthTotal: Decimal = 0
            var cellPhoneTotal: Decimal = 0
            var qHomeOffice: Decimal = 0
            var qBiz: Decimal = 0
            var qCellPhone: Decimal = 0

            let pctFraction = businessUsePct / 100

            for exp in monthly {
                let housingUtilities = exp.rentMortgage + exp.rentersHomeownersIns +
                    exp.realEstateTaxes + exp.electric + exp.waterSewer +
                    exp.gasPropane + exp.garbage + exp.internet + exp.hoaDues
                hoExpTotal += housingUtilities
                cellPhoneTotal += exp.cellPhone

                let biz = exp.malpracticeLiability + exp.workersComp +
                    exp.professionalMemberships + exp.softwareSubscriptions
                bizExpTotal += biz

                healthTotal += exp.healthInsurance

                if isMonthInQuarter(exp.month, quarter: quarter) {
                    qHomeOffice += housingUtilities * pctFraction
                    qCellPhone += exp.cellPhone * pctFraction
                    qBiz += biz
                }
            }

            homeOfficeExpenses = hoExpTotal * pctFraction
            cellPhoneExpenses = cellPhoneTotal * pctFraction
            directBusinessExpenses = bizExpTotal
            healthInsuranceExpenses = healthTotal

            // Misc expenses
            let misc: [MiscExpense] = try await client.from("misc_expenses")
                .select()
                .eq("user_id", value: userId)
                .eq("tax_year", value: currentYear)
                .execute()
                .value
            var miscTotal: Decimal = 0
            var qMisc: Decimal = 0
            for exp in misc {
                miscTotal += exp.amount
                if isInQuarter(exp.date, quarter: quarter, year: currentYear) {
                    qMisc += exp.amount
                }
            }
            totalMiscExpenses = miscTotal

            // Calculate quarter deductions
            let qMileageDed = qMiles * tc.irsMileageRate
            let qMealDed = qMeals * tc.mealDeductionPct
            quarterDeductions = qMileageDed + qTripExp + qMealDed + qHomeOffice + qCellPhone + qBiz + qMisc

        } catch {
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain {
                errorMessage = "Unable to connect. Check your internet connection and try again."
            } else {
                errorMessage = "Unable to load tax data. Pull down to refresh."
            }
        }
    }

    // MARK: - YTD Tax Calculations

    var mileageDeduction: Decimal {
        totalMiles * tc.irsMileageRate
    }

    var mealDeduction: Decimal {
        totalMealSpend * tc.mealDeductionPct
    }

    var totalDeductions: Decimal {
        mileageDeduction + totalTripExpenses + mealDeduction +
        homeOfficeExpenses + cellPhoneExpenses + directBusinessExpenses + totalMiscExpenses
    }

    var netIncome: Decimal {
        max(grossIncome - totalDeductions, 0)
    }

    var seTax: Decimal {
        let taxableBase = grossIncome * tc.seIncomeMultiplier
        return taxableBase * tc.seTaxRate
    }

    var halfSETaxDeduction: Decimal {
        seTax * Decimal(0.5)
    }

    var adjustedGrossIncome: Decimal {
        grossIncome - halfSETaxDeduction
    }

    var standardDeduction: Decimal {
        tc.standardDeduction(for: filingStatus)
    }

    var taxableIncome: Decimal {
        max(adjustedGrossIncome - standardDeduction, 0)
    }

    var estimatedIncomeTax: Decimal {
        tc.federalIncomeTax(on: taxableIncome)
    }

    var totalEstimatedTax: Decimal {
        seTax + estimatedIncomeTax
    }

    var quarterlyPayment: Decimal {
        totalEstimatedTax / 4
    }

    // MARK: - Quarter estimate based on quarter-specific data
    var quarterEstimatedPayment: Decimal {
        let qSETaxBase = quarterIncome * tc.seIncomeMultiplier
        let qSETax = qSETaxBase * tc.seTaxRate
        let qHalfSE = qSETax * Decimal(0.5)
        let qTaxableIncome = max(quarterIncome - qHalfSE - (standardDeduction / 4), 0)
        let qIncomeTax = tc.federalIncomeTax(on: qTaxableIncome)
        return max(qSETax + qIncomeTax, 0)
    }

    // MARK: - Quarterly Deadlines

    var quarterlyDeadlines: [(quarter: String, date: String, daysUntil: Int, isPast: Bool)] {
        let calendar = Calendar.current
        let now = Date()
        let formatter = DateFormatter()
        formatter.dateStyle = .medium

        let deadlines: [(String, Int, Int, Int)] = [
            ("Q1", currentYear, 4, 15),
            ("Q2", currentYear, 6, 15),
            ("Q3", currentYear, 9, 15),
            ("Q4", currentYear + 1, 1, 15),
        ]

        return deadlines.map { quarter, year, month, day in
            var components = DateComponents()
            components.year = year
            components.month = month
            components.day = day
            let deadline = calendar.date(from: components) ?? now
            let days = calendar.dateComponents([.day], from: now, to: deadline).day ?? 0
            return (quarter, formatter.string(from: deadline), days, deadline < now)
        }
    }

    var nextUpcomingDeadline: (quarter: String, date: String, daysUntil: Int)? {
        quarterlyDeadlines.first(where: { !$0.isPast })
            .map { ($0.quarter, $0.date, $0.daysUntil) }
    }
}
