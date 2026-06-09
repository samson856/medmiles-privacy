import Foundation
import Supabase
import Combine

@MainActor
final class DashboardViewModel: ObservableObject {
    private let client = SupabaseService.shared.client

    @Published var isLoading = false

    // YTD data
    @Published var ytdIncome: Decimal = 0
    @Published var ytdMileageMiles: Decimal = 0
    @Published var ytdTripExpenses: Decimal = 0  // tolls, parking, ferry, other
    @Published var ytdMealSpend: Decimal = 0
    @Published var ytdHomeOfficeExpenses: Decimal = 0   // housing/utilities × business use %
    @Published var ytdCellPhoneExpenses: Decimal = 0    // cell phone × business use %
    @Published var ytdDirectBizExpenses: Decimal = 0    // malpractice, memberships, etc.
    @Published var ytdMiscExpenses: Decimal = 0

    // Counts
    @Published var tripCount: Int = 0
    @Published var incomeCount: Int = 0
    @Published var pendingIncomeCount: Int = 0
    @Published var mealCount: Int = 0
    @Published var errorMessage: String?

    // Current year
    @Published var currentYear = Calendar.current.component(.year, from: Date())

    /// Switch to a different tax year and reload all data
    func switchYear(to year: Int, userId: UUID) async {
        currentYear = year
        await TaxConstantsService.shared.fetchConstants(for: currentYear)
        await loadDashboard(userId: userId)
    }

    // MARK: - Load All YTD Data

    func loadDashboard(userId: UUID, attempt: Int = 0) async {
        isLoading = true
        defer { isLoading = false }

        // Ensure we have the latest tax constants before calculating estimates
        await TaxConstantsService.shared.fetchConstants(for: currentYear)

        do {
            let startDate = "\(currentYear)-01-01"
            let endDate = "\(currentYear)-12-31"

            async let tripsResult: [Trip] = client.from("trips")
                .select()
                .eq("user_id", value: userId)
                .gte("date", value: startDate)
                .lte("date", value: endDate)
                .execute()
                .value

            async let incomeResult: [Income] = client.from("income")
                .select()
                .eq("user_id", value: userId)
                .gte("date_of_service", value: startDate)
                .lte("date_of_service", value: endDate)
                .execute()
                .value

            async let mealsResult: [Meal] = client.from("meals")
                .select()
                .eq("user_id", value: userId)
                .gte("date", value: startDate)
                .lte("date", value: endDate)
                .execute()
                .value

            async let monthlyResult: [MonthlyExpense] = client.from("monthly_expenses")
                .select()
                .eq("user_id", value: userId)
                .eq("tax_year", value: currentYear)
                .execute()
                .value

            async let miscResult: [MiscExpense] = client.from("misc_expenses")
                .select()
                .eq("user_id", value: userId)
                .eq("tax_year", value: currentYear)
                .execute()
                .value

            async let hoResult: [HomeOffice] = client.from("home_office")
                .select()
                .eq("user_id", value: userId)
                .eq("tax_year", value: currentYear)
                .execute()
                .value

            let trips = try await tripsResult
            let income = try await incomeResult
            let meals = try await mealsResult
            let monthly = try await monthlyResult
            let misc = try await miscResult
            let homeOffices = try await hoResult
            let businessUsePct = homeOffices.first?.businessUsePct ?? 0

            // Trips
            tripCount = trips.count
            var totalMiles: Decimal = 0
            var totalTripExp: Decimal = 0
            for trip in trips {
                totalMiles += trip.distanceMiles ?? 0
                let tolls: Decimal = trip.tolls ?? 0
                let parking: Decimal = trip.parking ?? 0
                let ferry: Decimal = trip.ferry ?? 0
                let other: Decimal = trip.otherExpense ?? 0
                totalTripExp += tolls + parking + ferry + other
            }
            ytdMileageMiles = totalMiles
            ytdTripExpenses = totalTripExp

            // Income
            incomeCount = income.count
            var totalIncome: Decimal = 0
            var pendingCount = 0
            for entry in income {
                totalIncome += entry.grossPay
                if entry.status == "pending" { pendingCount += 1 }
            }
            ytdIncome = totalIncome
            pendingIncomeCount = pendingCount

            // Meals
            mealCount = meals.count
            var totalMeals: Decimal = 0
            for meal in meals {
                totalMeals += meal.calculatedTotal
            }
            ytdMealSpend = totalMeals

            // Monthly expenses — split by category
            var hoExpTotal: Decimal = 0
            var cellPhoneTotal: Decimal = 0
            var bizExpTotal: Decimal = 0
            for exp in monthly {
                // Housing + utilities → deductible at business use %
                let housingUtilities = exp.rentMortgage + exp.rentersHomeownersIns +
                    exp.realEstateTaxes + exp.electric + exp.waterSewer +
                    exp.gasPropane + exp.garbage + exp.internet + exp.hoaDues
                hoExpTotal += housingUtilities
                cellPhoneTotal += exp.cellPhone
                // 100% deductible business expenses
                bizExpTotal += exp.malpracticeLiability + exp.workersComp +
                    exp.professionalMemberships + exp.softwareSubscriptions
                // Vehicle costs excluded (included in standard mileage rate)
                // Health insurance excluded (separate Form 1040 deduction)
            }
            let pctFraction = businessUsePct / 100
            ytdHomeOfficeExpenses = hoExpTotal * pctFraction
            ytdCellPhoneExpenses = cellPhoneTotal * pctFraction
            ytdDirectBizExpenses = bizExpTotal

            // Misc expenses
            var totalMisc: Decimal = 0
            for exp in misc {
                totalMisc += exp.amount
            }
            ytdMiscExpenses = totalMisc

            // Success — clear any stale error banner left over from a prior attempt.
            errorMessage = nil

        } catch is CancellationError {
            // A newer load replaced this one, or the view went away. Not a real error.
            return
        } catch {
            let nsError = error as NSError

            // URLSession reports a cancelled request as -999. That is NOT a
            // connectivity problem — it happens during normal navigation, the
            // launch transition, or overlapping refreshes — so never alert on it.
            if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled {
                return
            }

            // Retry once for genuine transient hiccups (cold start, brief drop)
            // before showing the user an alert.
            let transientCodes = [
                NSURLErrorTimedOut,
                NSURLErrorCannotConnectToHost,
                NSURLErrorCannotFindHost,
                NSURLErrorNetworkConnectionLost,
                NSURLErrorNotConnectedToInternet,
            ]
            if attempt == 0, nsError.domain == NSURLErrorDomain, transientCodes.contains(nsError.code) {
                try? await Task.sleep(nanoseconds: 800_000_000) // 0.8s
                if Task.isCancelled { return }
                await loadDashboard(userId: userId, attempt: 1)
                return
            }

            if nsError.domain == NSURLErrorDomain {
                errorMessage = "Unable to connect. Check your internet connection and try again."
            } else {
                errorMessage = "Unable to load data. Pull down to refresh."
            }
        }
    }

    // MARK: - Computed

    var ytdDeductions: Decimal {
        let tc = TaxConstantsService.shared.constantsForYear(currentYear)
        let mileageDeduction = ytdMileageMiles * tc.irsMileageRate
        let mealDeduction = ytdMealSpend * tc.mealDeductionPct
        return mileageDeduction + ytdTripExpenses + mealDeduction +
            ytdHomeOfficeExpenses + ytdCellPhoneExpenses + ytdDirectBizExpenses + ytdMiscExpenses
    }

    var netProfit: Decimal {
        ytdIncome - ytdDeductions
    }

    var estimatedQuarterlyTax: Decimal {
        guard ytdIncome > 0 else { return 0 }
        let tc = TaxConstantsService.shared.constantsForYear(currentYear)
        let seIncome = ytdIncome * tc.seIncomeMultiplier
        let seTax = seIncome * tc.seTaxRate
        let roughIncomeTax = ytdIncome * (Decimal(string: "0.15") ?? Decimal(0))
        let annualEstimate = seTax + roughIncomeTax
        return max(annualEstimate / 4, 0)
    }

    var nextQuarterlyDeadline: (quarter: String, date: String, daysUntil: Int)? {
        let calendar = Calendar.current
        let now = Date()

        let deadlines: [(String, Int, Int)] = [
            ("Q1", 4, 15),   // Apr 15
            ("Q2", 6, 15),   // Jun 15
            ("Q3", 9, 15),   // Sep 15
            ("Q4", 1, 15),   // Jan 15 next year
        ]

        for (quarter, month, day) in deadlines {
            var components = DateComponents()
            components.year = quarter == "Q4" ? currentYear + 1 : currentYear
            components.month = month
            components.day = day

            if let deadline = calendar.date(from: components), deadline > now {
                let days = calendar.dateComponents([.day], from: now, to: deadline).day ?? 0
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                return (quarter, formatter.string(from: deadline), days)
            }
        }
        return nil
    }
}
