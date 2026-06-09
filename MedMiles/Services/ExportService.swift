import Foundation
import Supabase
import Combine

@MainActor
final class ExportService: ObservableObject {
    private let client = SupabaseService.shared.client

    @Published var isExporting = false
    @Published var errorMessage: String?

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private let displayDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M/d/yyyy"
        return f
    }()

    private func formatDate(_ dateStr: String) -> String {
        if let date = dateFormatter.date(from: dateStr) {
            return displayDateFormatter.string(from: date)
        }
        return dateStr
    }

    private func formatMoney(_ val: Decimal) -> String {
        String(format: "$%.2f", NSDecimalNumber(decimal: val).doubleValue)
    }

    private func csvEscape(_ text: String) -> String {
        if text.contains(",") || text.contains("\"") || text.contains("\n") {
            return "\"\(text.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return text
    }

    private func agencyName(_ agencyId: UUID?, agencies: [Agency]) -> String {
        guard let id = agencyId else { return "Unassigned" }
        return agencies.first(where: { $0.id == id })?.name ?? "Unknown"
    }

    private func visitTypeName(_ vtId: UUID?, visitTypes: [VisitType]) -> String {
        guard let id = vtId else { return "" }
        return visitTypes.first(where: { $0.id == id })?.name ?? ""
    }

    // MARK: - Load All Data

    private func loadAllData(userId: UUID, taxYear: Int, startDate: String? = nil, endDate: String? = nil) async throws -> ExportData {
        let start = startDate ?? "\(taxYear)-01-01"
        let end = endDate ?? "\(taxYear)-12-31"
        let trips: [Trip] = try await client.from("trips")
            .select().eq("user_id", value: userId)
            .gte("date", value: start).lte("date", value: end)
            .order("date").execute().value
        let income: [Income] = try await client.from("income")
            .select().eq("user_id", value: userId)
            .gte("date_of_service", value: start).lte("date_of_service", value: end)
            .order("date_of_service").execute().value
        let meals: [Meal] = try await client.from("meals")
            .select().eq("user_id", value: userId)
            .gte("date", value: start).lte("date", value: end)
            .order("date").execute().value
        let monthly: [MonthlyExpense] = try await client.from("monthly_expenses")
            .select().eq("user_id", value: userId).eq("tax_year", value: taxYear)
            .order("month").execute().value
        let misc: [MiscExpense] = try await client.from("misc_expenses")
            .select().eq("user_id", value: userId).eq("tax_year", value: taxYear)
            .gte("date", value: start).lte("date", value: end)
            .order("date").execute().value
        let agencies: [Agency] = try await client.from("agencies")
            .select().eq("user_id", value: userId).execute().value
        let visitTypes: [VisitType] = try await client.from("visit_types")
            .select().eq("user_id", value: userId).execute().value

        let hoResults: [HomeOffice] = try await client.from("home_office")
            .select().eq("user_id", value: userId).eq("tax_year", value: taxYear).execute().value

        return ExportData(
            trips: trips, income: income, meals: meals,
            monthly: monthly, misc: misc, agencies: agencies,
            visitTypes: visitTypes, homeOffice: hoResults.first
        )
    }

    // MARK: - Generate Full CPA Workbook (multiple CSVs zipped)

    func generateFullExport(userId: UUID, taxYear: Int, startDate: String? = nil, endDate: String? = nil) async -> URL? {
        isExporting = true
        errorMessage = nil
        defer { isExporting = false }

        do {
            let data = try await loadAllData(userId: userId, taxYear: taxYear, startDate: startDate, endDate: endDate)
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("MedMiles_Export_\(taxYear)")

            // Clean up old export
            try? FileManager.default.removeItem(at: tempDir)
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

            // Generate each CSV
            let files: [(String, String)] = [
                ("1_Home_Office.csv", generateHomeOfficeCSV(data: data, taxYear: taxYear)),
                ("2_Monthly_Bills.csv", generateMonthlyBillsCSV(data: data, taxYear: taxYear)),
                ("3_Expenses.csv", generateExpensesCSV(data: data)),
                ("4_Meals.csv", generateMealsCSV(data: data)),
                ("5_Mileage.csv", generateMileageCSV(data: data, taxYear: taxYear)),
                ("6_Pay.csv", generatePayCSV(data: data)),
            ]

            for (filename, content) in files {
                let fileURL = tempDir.appendingPathComponent(filename)
                try content.write(to: fileURL, atomically: true, encoding: .utf8)
            }

            return tempDir
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    // MARK: - Individual Exports

    func generateMileageExport(userId: UUID, taxYear: Int) async -> URL? {
        isExporting = true
        errorMessage = nil
        defer { isExporting = false }

        do {
            let data = try await loadAllData(userId: userId, taxYear: taxYear)
            let csv = generateMileageCSV(data: data, taxYear: taxYear)
            return saveCSV(csv, filename: "MedMiles_Mileage_\(taxYear).csv")
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func generateIncomeExport(userId: UUID, taxYear: Int) async -> URL? {
        isExporting = true
        errorMessage = nil
        defer { isExporting = false }

        do {
            let data = try await loadAllData(userId: userId, taxYear: taxYear)
            let csv = generatePayCSV(data: data)
            return saveCSV(csv, filename: "MedMiles_Income_\(taxYear).csv")
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func generateExpenseExport(userId: UUID, taxYear: Int) async -> URL? {
        isExporting = true
        errorMessage = nil
        defer { isExporting = false }

        do {
            let data = try await loadAllData(userId: userId, taxYear: taxYear)
            let csv = generateExpensesCSV(data: data)
            return saveCSV(csv, filename: "MedMiles_Expenses_\(taxYear).csv")
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func generateMealsExport(userId: UUID, taxYear: Int) async -> URL? {
        isExporting = true
        errorMessage = nil
        defer { isExporting = false }

        do {
            let data = try await loadAllData(userId: userId, taxYear: taxYear)
            let csv = generateMealsCSV(data: data)
            return saveCSV(csv, filename: "MedMiles_Meals_\(taxYear).csv")
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    private func saveCSV(_ content: String, filename: String) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    // MARK: - CSV Generators

    private func generateHomeOfficeCSV(data: ExportData, taxYear: Int) -> String {
        var lines: [String] = []
        lines.append("MedMiles - Home Office,\(taxYear)")
        lines.append("")

        if let ho = data.homeOffice {
            let total = ho.totalSqFt.map { "\(NSDecimalNumber(decimal: $0).doubleValue)" } ?? "0"
            let office = ho.officeSqFt.map { "\(NSDecimalNumber(decimal: $0).doubleValue)" } ?? "0"
            let pct = ho.businessUsePct.map { "\(NSDecimalNumber(decimal: $0).doubleValue)%" } ?? "0%"

            lines.append("Total Home Sq Ft,\(total)")
            lines.append("Office Sq Ft,\(office)")
            lines.append("Business Use %,\(pct)")
            lines.append("")

            lines.append("Active Months")
            let monthNames = ["January","February","March","April","May","June",
                            "July","August","September","October","November","December"]
            for i in 0..<12 {
                let status = ho.isMonthActive(i) ? "Active" : "Inactive"
                lines.append("\(monthNames[i]),\(status)")
            }

            let activeCount = ho.activeMonths.filter { $0 }.count
            lines.append("")
            lines.append("*** TOTAL ACTIVE MONTHS ***,\(activeCount) of 12")

            // Simplified deduction estimate
            if let officeSqFt = ho.officeSqFt {
                let tc = TaxConstantsService.shared.constantsForYear(taxYear)
                let capped = min(officeSqFt, Decimal(tc.homeOfficeMaxSqFt))
                let fraction = Decimal(activeCount) / 12
                let estimate = capped * tc.homeOfficeSimplifiedRate * fraction
                lines.append("*** ESTIMATED DEDUCTION (Simplified Method) ***,\(formatMoney(estimate))")
            }
        } else {
            lines.append("No home office data configured for \(taxYear)")
        }

        lines.append("")
        let tcNote = TaxConstantsService.shared.constantsForYear(taxYear)
        lines.append("Note: This is an estimate using the IRS simplified method ($\(tcNote.homeOfficeSimplifiedRate)/sq ft max \(tcNote.homeOfficeMaxSqFt) sq ft). Consult your CPA.")

        return lines.joined(separator: "\n")
    }

    private func generateMonthlyBillsCSV(data: ExportData, taxYear: Int) -> String {
        var lines: [String] = []
        lines.append("MedMiles - Monthly Bills,\(taxYear)")
        lines.append("")

        // Header row
        lines.append("Month,Rent/Mortgage,Renters/Homeowners Ins,Real Estate Taxes,Electric,Water/Sewer,Gas/Propane,Garbage,Internet,HOA Dues,Cell Phone,Malpractice/Liability,Health Insurance,Workers Comp,Car Insurance,Car Payment Interest,Maintenance/Repairs,Professional Memberships,Software/Subscriptions,MONTH TOTAL")

        let monthNames = ["January","February","March","April","May","June",
                        "July","August","September","October","November","December"]

        var grandTotal: Decimal = 0

        for monthNum in 1...12 {
            if let exp = data.monthly.first(where: { $0.month == monthNum }) {
                let total = exp.monthTotal
                grandTotal += total
                let row = [
                    monthNames[monthNum - 1],
                    formatMoney(exp.rentMortgage),
                    formatMoney(exp.rentersHomeownersIns),
                    formatMoney(exp.realEstateTaxes),
                    formatMoney(exp.electric),
                    formatMoney(exp.waterSewer),
                    formatMoney(exp.gasPropane),
                    formatMoney(exp.garbage),
                    formatMoney(exp.internet),
                    formatMoney(exp.hoaDues),
                    formatMoney(exp.cellPhone),
                    formatMoney(exp.malpracticeLiability),
                    formatMoney(exp.healthInsurance),
                    formatMoney(exp.workersComp),
                    formatMoney(exp.carInsurance),
                    formatMoney(exp.carPaymentInterest),
                    formatMoney(exp.maintenanceRepairs),
                    formatMoney(exp.professionalMemberships),
                    formatMoney(exp.softwareSubscriptions),
                    formatMoney(total)
                ]
                lines.append(row.joined(separator: ","))
            } else {
                lines.append("\(monthNames[monthNum - 1]),$0.00,$0.00,$0.00,$0.00,$0.00,$0.00,$0.00,$0.00,$0.00,$0.00,$0.00,$0.00,$0.00,$0.00,$0.00,$0.00,$0.00,$0.00,$0.00")
            }
        }

        lines.append("*** YEARLY TOTAL ***,,,,,,,,,,,,,,,,,,, \(formatMoney(grandTotal))")

        return lines.joined(separator: "\n")
    }

    private func generateExpensesCSV(data: ExportData) -> String {
        var lines: [String] = []
        lines.append("MedMiles - Individual Expenses")
        lines.append("")
        lines.append("Date,Item,Purpose,Company,Cost,Receipt #")

        var grandTotal: Decimal = 0

        for exp in data.misc.sorted(by: { $0.date < $1.date }) {
            grandTotal += exp.amount
            let desc = exp.description ?? ""
            let category = MiscExpense.categoryLabel(for: exp.category)
            let company = agencyName(exp.agencyId, agencies: data.agencies)
            let row = [
                formatDate(exp.date),
                csvEscape(desc),
                csvEscape(category),
                csvEscape(company),
                formatMoney(exp.amount),
                exp.hasReceipt ? "Yes" : ""
            ]
            lines.append(row.joined(separator: ","))
        }

        lines.append("")
        lines.append("*** TOTAL EXPENSES ***,,,, \(formatMoney(grandTotal))")

        return lines.joined(separator: "\n")
    }

    private func generateMealsCSV(data: ExportData) -> String {
        var lines: [String] = []
        lines.append("MedMiles - Meals")
        lines.append("")

        // Group meals by agency
        let grouped = Dictionary(grouping: data.meals) { meal in
            agencyName(meal.agencyId, agencies: data.agencies)
        }

        var grandTotal: Decimal = 0
        let sortedCompanies = grouped.keys.sorted()

        for company in sortedCompanies {
            guard let meals = grouped[company] else { continue }

            lines.append("=== \(company) ===")
            lines.append("Date,Breakfast,Lunch,Dinner,Total,Receipt #")

            var companyTotal: Decimal = 0

            for meal in meals.sorted(by: { $0.date < $1.date }) {
                let total = meal.calculatedTotal
                companyTotal += total
                let row = [
                    formatDate(meal.date),
                    formatMoney(meal.breakfast),
                    formatMoney(meal.lunch),
                    formatMoney(meal.dinner),
                    formatMoney(total),
                    meal.receiptNumber ?? ""
                ]
                lines.append(row.joined(separator: ","))
            }

            grandTotal += companyTotal
            lines.append("*** \(company) TOTAL ***,,,, \(formatMoney(companyTotal))")
            lines.append("")
        }

        lines.append("*** GRAND TOTAL ***,,,, \(formatMoney(grandTotal))")
        lines.append("")
        lines.append("Note: Business meals are deductible. Consult your CPA.")

        return lines.joined(separator: "\n")
    }

    private func generateMileageCSV(data: ExportData, taxYear: Int) -> String {
        var lines: [String] = []
        lines.append("MedMiles - Mileage Log,\(taxYear)")
        lines.append("")

        let beginningOdometer = UserDefaults.standard.double(forKey: "beginningOdometer_\(taxYear)")
        let endingOdometer = UserDefaults.standard.double(forKey: "endingOdometer_\(taxYear)")

        if beginningOdometer > 0 || endingOdometer > 0 {
            lines.append("Annual Odometer Summary")
            if beginningOdometer > 0 {
                lines.append("Beginning Odometer,\(String(format: "%.0f", beginningOdometer))")
            }
            if endingOdometer > 0 {
                lines.append("Ending Odometer,\(String(format: "%.0f", endingOdometer))")
            }
            if beginningOdometer > 0 && endingOdometer > 0 {
                lines.append("Total Miles Driven,\(String(format: "%.0f", endingOdometer - beginningOdometer))")
            }
            lines.append("")
        }

        // Group trips by agency
        let grouped = Dictionary(grouping: data.trips) { trip in
            agencyName(trip.agencyId, agencies: data.agencies)
        }

        var grandTotalMiles: Decimal = 0
        var grandTotalExpenses: Decimal = 0
        let sortedCompanies = grouped.keys.sorted()

        for company in sortedCompanies {
            guard let trips = grouped[company] else { continue }

            lines.append("=== \(company) ===")
            lines.append("Date,Destination,Type of Visit,Odometer Start,Odometer Stop,Total Miles,Expense Type,Amount")

            var companyMiles: Decimal = 0
            var companyExpenses: Decimal = 0

            for trip in trips.sorted(by: { $0.date < $1.date }) {
                let miles = trip.distanceMiles ?? 0
                companyMiles += miles

                var expTypes: [String] = []
                var expTotal: Decimal = 0

                if let tolls = trip.tolls, tolls > 0 {
                    expTypes.append("Tolls")
                    expTotal += tolls
                }
                if let parking = trip.parking, parking > 0 {
                    expTypes.append("Parking")
                    expTotal += parking
                }
                if let ferry = trip.ferry, ferry > 0 {
                    expTypes.append("Ferry")
                    expTotal += ferry
                }
                if let other = trip.otherExpense, other > 0 {
                    expTypes.append("Other")
                    expTotal += other
                }

                let expenseType = expTypes.joined(separator: ", ")
                companyExpenses += expTotal

                let odoStart = trip.odometerStart.map { "\(NSDecimalNumber(decimal: $0).intValue)" } ?? ""
                let odoStop = trip.odometerStop.map { "\(NSDecimalNumber(decimal: $0).intValue)" } ?? ""
                let visitType = visitTypeName(trip.visitTypeId, visitTypes: data.visitTypes)
                let destination = trip.destinationCity ?? ""

                let row = [
                    formatDate(trip.date),
                    csvEscape(destination),
                    csvEscape(visitType),
                    odoStart,
                    odoStop,
                    "\(NSDecimalNumber(decimal: miles).doubleValue)",
                    csvEscape(expenseType),
                    expTotal > 0 ? formatMoney(expTotal) : ""
                ]
                lines.append(row.joined(separator: ","))
            }

            grandTotalMiles += companyMiles
            grandTotalExpenses += companyExpenses

            lines.append("*** \(company) TOTAL ***,,,,,\(NSDecimalNumber(decimal: companyMiles).doubleValue) miles,,\(formatMoney(companyExpenses))")
            lines.append("")
        }

        lines.append("*** GRAND TOTAL ***,,,,,\(NSDecimalNumber(decimal: grandTotalMiles).doubleValue) miles,,\(formatMoney(grandTotalExpenses))")

        return lines.joined(separator: "\n")
    }

    private func generatePayCSV(data: ExportData) -> String {
        var lines: [String] = []
        lines.append("MedMiles - Pay Information")
        lines.append("")

        // Group income by agency
        let grouped = Dictionary(grouping: data.income) { entry in
            agencyName(entry.agencyId, agencies: data.agencies)
        }

        var grandGross: Decimal = 0
        var grandTax: Decimal = 0
        var grandNet: Decimal = 0
        let sortedCompanies = grouped.keys.sorted()

        for company in sortedCompanies {
            guard let entries = grouped[company] else { continue }

            lines.append("=== \(company) ===")
            lines.append("Contract,Date Paid,Advertised Rate,Total Gross Pay,Tax Set-Aside,Actual Amount Set Aside,Actual Tax Set Aside %,Total Net Pay")

            var companyGross: Decimal = 0
            var companyTax: Decimal = 0
            var companyNet: Decimal = 0

            for entry in entries.sorted(by: { $0.dateOfService < $1.dateOfService }) {
                let gross = entry.grossPay
                let taxAmount = entry.taxSetAsideAmount ?? 0
                let net = gross - taxAmount
                let pctVal: String
                if gross > 0 {
                    let p = (taxAmount / gross) * 100
                    pctVal = String(format: "%.2f%%", NSDecimalNumber(decimal: p).doubleValue)
                } else {
                    pctVal = "0%"
                }

                companyGross += gross
                companyTax += taxAmount
                companyNet += net

                let contract = entry.contractVisitId ?? ""
                let datePaid = entry.datePaid.map { formatDate($0) } ?? ""
                let rate = entry.advertisedRate ?? ""
                let rateDisplay: String
                if entry.rateType == "hourly" {
                    rateDisplay = "\(rate)/hr"
                } else if entry.rateType == "flat_rate" {
                    rateDisplay = "\(rate) flat rate"
                } else {
                    rateDisplay = rate
                }

                let row = [
                    csvEscape(contract),
                    datePaid,
                    csvEscape(rateDisplay),
                    formatMoney(gross),
                    "",  // placeholder for suggested tax column
                    formatMoney(taxAmount),
                    pctVal,
                    formatMoney(net)
                ]
                lines.append(row.joined(separator: ","))
            }

            grandGross += companyGross
            grandTax += companyTax
            grandNet += companyNet

            let companyPct: String
            if companyGross > 0 {
                let p = (companyTax / companyGross) * 100
                companyPct = String(format: "%.2f%%", NSDecimalNumber(decimal: p).doubleValue)
            } else {
                companyPct = "0%"
            }

            lines.append("*** \(company) TOTAL ***,,,\(formatMoney(companyGross)),,\(formatMoney(companyTax)),\(companyPct),\(formatMoney(companyNet))")
            lines.append("")
        }

        let grandPct: String
        if grandGross > 0 {
            let p = (grandTax / grandGross) * 100
            grandPct = String(format: "%.2f%%", NSDecimalNumber(decimal: p).doubleValue)
        } else {
            grandPct = "0%"
        }

        lines.append("*** GRAND TOTAL ***,,,\(formatMoney(grandGross)),,\(formatMoney(grandTax)),\(grandPct),\(formatMoney(grandNet))")
        lines.append("")
        lines.append("Note: Tax estimates are for reference only. Consult your CPA for tax advice.")

        return lines.joined(separator: "\n")
    }
}

// MARK: - Data Container

struct ExportData {
    let trips: [Trip]
    let income: [Income]
    let meals: [Meal]
    let monthly: [MonthlyExpense]
    let misc: [MiscExpense]
    let agencies: [Agency]
    let visitTypes: [VisitType]
    let homeOffice: HomeOffice?
}
