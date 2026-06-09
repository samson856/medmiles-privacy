import UIKit
import Supabase

/// Generates a formatted PDF export of all MedMiles data for CPA review.
final class ExportPDFService {

    private let client = SupabaseService.shared.client
    private let margin: CGFloat = 40
    private let pageWidth: CGFloat = 612  // US Letter
    private let pageHeight: CGFloat = 792

    private var yPosition: CGFloat = 0
    private var context: CGContext?
    private var contentWidth: CGFloat { pageWidth - (margin * 2) }

    // Fonts
    private let titleFont = UIFont.boldSystemFont(ofSize: 18)
    private let sectionFont = UIFont.boldSystemFont(ofSize: 14)
    private let headerFont = UIFont.boldSystemFont(ofSize: 9)
    private let bodyFont = UIFont.systemFont(ofSize: 9)
    private let totalFont = UIFont.boldSystemFont(ofSize: 10)
    private let captionFont = UIFont.systemFont(ofSize: 8)

    // Colors
    private let graphite = UIColor(red: 54/255, green: 54/255, blue: 56/255, alpha: 1)
    private let teal = UIColor(red: 0, green: 181/255, blue: 165/255, alpha: 1)
    private let green = UIColor(red: 11/255, green: 138/255, blue: 110/255, alpha: 1)
    private let gray = UIColor.gray
    private let lightGray = UIColor(white: 0.92, alpha: 1)

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M/d/yyyy"
        return f
    }()

    private let isoDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    @MainActor
    func generateFullPDF(userId: UUID, taxYear: Int, userName: String, startDate: String? = nil, endDate: String? = nil) async -> URL? {
        let start = startDate ?? "\(taxYear)-01-01"
        let end = endDate ?? "\(taxYear)-12-31"
        // Fetch all data
        do {
            let agencies: [Agency] = try await client.from("agencies")
                .select().eq("user_id", value: userId).order("name").execute().value
            let visitTypes: [VisitType] = try await client.from("visit_types")
                .select().eq("user_id", value: userId).order("name").execute().value
            let trips: [Trip] = try await client.from("trips")
                .select().eq("user_id", value: userId)
                .gte("date", value: start).lte("date", value: end)
                .order("date", ascending: true).execute().value
            let income: [Income] = try await client.from("income")
                .select().eq("user_id", value: userId)
                .gte("date_of_service", value: start).lte("date_of_service", value: end)
                .order("date_of_service", ascending: true).execute().value
            let meals: [Meal] = try await client.from("meals")
                .select().eq("user_id", value: userId)
                .gte("date", value: start).lte("date", value: end)
                .order("date", ascending: true).execute().value
            let monthly: [MonthlyExpense] = try await client.from("monthly_expenses")
                .select().eq("user_id", value: userId)
                .eq("tax_year", value: taxYear)
                .order("month", ascending: true).execute().value
            let misc: [MiscExpense] = try await client.from("misc_expenses")
                .select().eq("user_id", value: userId)
                .eq("tax_year", value: taxYear)
                .order("date", ascending: true).execute().value

            var homeOffice: HomeOffice?
            let hoResults: [HomeOffice] = try await client.from("home_office")
                .select().eq("user_id", value: userId)
                .eq("tax_year", value: taxYear).execute().value
            homeOffice = hoResults.first

            return buildPDF(
                userName: userName, taxYear: taxYear,
                agencies: agencies, visitTypes: visitTypes,
                trips: trips, income: income, meals: meals,
                monthly: monthly, misc: misc, homeOffice: homeOffice
            )
        } catch {
            return nil
        }
    }

    @MainActor
    func generateSectionPDF(userId: UUID, taxYear: Int, userName: String, section: String, startDate: String? = nil, endDate: String? = nil) async -> URL? {
        let start = startDate ?? "\(taxYear)-01-01"
        let end = endDate ?? "\(taxYear)-12-31"
        do {
            let agencies: [Agency] = try await client.from("agencies")
                .select().eq("user_id", value: userId).order("name").execute().value
            let visitTypes: [VisitType] = try await client.from("visit_types")
                .select().eq("user_id", value: userId).order("name").execute().value

            let pdfURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("MedMiles_\(section)_\(taxYear).pdf")

            UIGraphicsBeginPDFContextToFile(pdfURL.path, .zero, [
                kCGPDFContextTitle as String: "MedMiles \(section.capitalized) — \(taxYear)",
                kCGPDFContextAuthor as String: userName,
            ])
            context = UIGraphicsGetCurrentContext()
            startNewPage()
            drawCover(userName: userName, taxYear: taxYear)

            switch section {
            case "mileage":
                let trips: [Trip] = try await client.from("trips")
                    .select().eq("user_id", value: userId)
                    .gte("date", value: start).lte("date", value: end)
                    .order("date", ascending: true).execute().value
                drawMileage(trips, agencies: agencies, visitTypes: visitTypes)

            case "pay":
                let income: [Income] = try await client.from("income")
                    .select().eq("user_id", value: userId)
                    .gte("date_of_service", value: start).lte("date_of_service", value: end)
                    .order("date_of_service", ascending: true).execute().value
                drawPay(income, agencies: agencies, visitTypes: visitTypes)

            case "expenses":
                let misc: [MiscExpense] = try await client.from("misc_expenses")
                    .select().eq("user_id", value: userId)
                    .eq("tax_year", value: taxYear)
                    .gte("date", value: start).lte("date", value: end)
                    .order("date", ascending: true).execute().value
                drawIndividualExpenses(misc, agencies: agencies)

            case "meals":
                let meals: [Meal] = try await client.from("meals")
                    .select().eq("user_id", value: userId)
                    .gte("date", value: start).lte("date", value: end)
                    .order("date", ascending: true).execute().value
                drawMeals(meals, agencies: agencies)

            case "monthly":
                let monthly: [MonthlyExpense] = try await client.from("monthly_expenses")
                    .select().eq("user_id", value: userId)
                    .eq("tax_year", value: taxYear)
                    .order("month", ascending: true).execute().value
                drawMonthlyBills(monthly, taxYear: taxYear)

            case "homeoffice":
                let hoResults: [HomeOffice] = try await client.from("home_office")
                    .select().eq("user_id", value: userId)
                    .eq("tax_year", value: taxYear).execute().value
                if let ho = hoResults.first {
                    drawHomeOffice(ho, taxYear: taxYear)
                }

            case "monthly_homeoffice":
                let monthly: [MonthlyExpense] = try await client.from("monthly_expenses")
                    .select().eq("user_id", value: userId)
                    .eq("tax_year", value: taxYear)
                    .order("month", ascending: true).execute().value
                var homeOffice: HomeOffice?
                let hoResults: [HomeOffice] = try await client.from("home_office")
                    .select().eq("user_id", value: userId)
                    .eq("tax_year", value: taxYear).execute().value
                homeOffice = hoResults.first
                drawMonthlyBillsAndHomeOffice(monthly, taxYear: taxYear, homeOffice: homeOffice)

            default:
                break
            }

            drawFooter()
            UIGraphicsEndPDFContext()
            return pdfURL
        } catch {
            return nil
        }
    }

    private func buildPDF(userName: String, taxYear: Int,
                          agencies: [Agency], visitTypes: [VisitType],
                          trips: [Trip], income: [Income], meals: [Meal],
                          monthly: [MonthlyExpense], misc: [MiscExpense],
                          homeOffice: HomeOffice?) -> URL? {

        let pdfURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MedMiles_\(taxYear)_\(userName.replacingOccurrences(of: " ", with: "_")).pdf")

        UIGraphicsBeginPDFContextToFile(pdfURL.path, .zero, [
            kCGPDFContextTitle as String: "MedMiles \(taxYear) Tax Report",
            kCGPDFContextAuthor as String: userName,
        ])
        context = UIGraphicsGetCurrentContext()

        // Page 1: Cover
        startNewPage()
        drawCover(userName: userName, taxYear: taxYear)

        // Monthly Bills + Home Office (combined)
        startNewPage()
        drawMonthlyBillsAndHomeOffice(monthly, taxYear: taxYear, homeOffice: homeOffice)

        // Individual Expenses
        startNewPage()
        drawIndividualExpenses(misc, agencies: agencies)

        // Meals grouped by company
        startNewPage()
        drawMeals(meals, agencies: agencies)

        // Mileage grouped by company
        startNewPage()
        drawMileage(trips, agencies: agencies, visitTypes: visitTypes)

        // Pay grouped by company
        startNewPage()
        drawPay(income, agencies: agencies, visitTypes: visitTypes)

        drawFooter()
        UIGraphicsEndPDFContext()
        return pdfURL
    }

    // MARK: - Page Management

    private func startNewPage() {
        UIGraphicsBeginPDFPageWithInfo(CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight), nil)
        yPosition = margin
        context = UIGraphicsGetCurrentContext()
    }

    private func checkPageBreak(_ needed: CGFloat) {
        if yPosition + needed > pageHeight - margin - 20 {
            drawFooter()
            startNewPage()
        }
    }

    // MARK: - Cover Page

    private func drawCover(userName: String, taxYear: Int) {
        if let appIcon = UIImage(named: "medmiles-icon-final-graphite") ?? UIImage(named: "AppIcon") {
            let iconSize: CGFloat = 50
            appIcon.draw(in: CGRect(x: margin, y: yPosition, width: iconSize, height: iconSize))
            drawText("MedMiles", at: CGPoint(x: margin + iconSize + 12, y: yPosition + 8), font: titleFont, color: graphite)
            drawText("Tax Report — \(taxYear)", at: CGPoint(x: margin + iconSize + 12, y: yPosition + 28), font: sectionFont, color: teal)
            yPosition += iconSize + 15
        } else {
            drawText("MedMiles Tax Report — \(taxYear)", at: CGPoint(x: margin, y: yPosition), font: titleFont, color: graphite)
            yPosition += 25
        }

        drawText("Prepared for: \(userName)", at: CGPoint(x: margin, y: yPosition), font: bodyFont, color: gray)
        yPosition += 14
        drawText("Generated: \(dateFormatter.string(from: Date()))", at: CGPoint(x: margin, y: yPosition), font: bodyFont, color: gray)
        yPosition += 14
        drawText("All tax figures are estimates. Consult your CPA for tax advice.", at: CGPoint(x: margin, y: yPosition), font: captionFont, color: .orange)
        yPosition += 20
        drawLine(color: teal, width: 1.5)
        yPosition += 15
    }

    // MARK: - Home Office

    private func drawHomeOffice(_ ho: HomeOffice, taxYear: Int) {
        checkPageBreak(100)

        // Teal banner header
        context?.setFillColor(teal.cgColor)
        context?.fill(CGRect(x: margin, y: yPosition - 2, width: contentWidth, height: 20))
        drawText("Home Office Deduction — \(taxYear)", at: CGPoint(x: margin + 4, y: yPosition + 1), font: sectionFont, color: .white)
        yPosition += 26

        let totalSqFt = ho.totalSqFt ?? 0
        let officeSqFt = ho.officeSqFt ?? 0
        // Use stored businessUsePct if available, otherwise calculate from square footage
        let pct: Decimal
        if let storedPct = ho.businessUsePct, storedPct > 0 {
            pct = storedPct
        } else {
            pct = totalSqFt > 0 ? (officeSqFt / totalSqFt) * 100 : 0
        }

        // Detail rows — two-column key/value layout
        let detailColWidths: [CGFloat] = [contentWidth * 0.6, contentWidth * 0.4]

        // Header row
        drawTableRow(["Detail", "Value"], widths: detailColWidths, font: headerFont, color: graphite, bgColor: lightGray)

        let rows: [(String, String)] = [
            ("Total Home Square Footage", totalSqFt > 0 ? "\(NSDecimalNumber(decimal: totalSqFt).intValue) sq ft" : "—"),
            ("Dedicated Office Square Footage", officeSqFt > 0 ? "\(NSDecimalNumber(decimal: officeSqFt).intValue) sq ft" : "—"),
            ("Business Use Percentage", pct > 0 ? String(format: "%.2f%%", NSDecimalNumber(decimal: pct).doubleValue) : "—"),
        ]

        for row in rows {
            checkPageBreak(14)
            drawTableRow([row.0, row.1], widths: detailColWidths, font: bodyFont, color: graphite)
        }

        // Active months summary
        let activeCount = ho.activeMonths.filter { $0 }.count
        if activeCount > 0 {
            checkPageBreak(14)
            drawTableRow(["Active Months", "\(activeCount) of 12"],
                         widths: detailColWidths, font: bodyFont, color: graphite)
        }

        yPosition += 20
    }

    // MARK: - Monthly Bills

    private func drawMonthlyBills(_ expenses: [MonthlyExpense], taxYear: Int) {
        drawMonthlyBillsAndHomeOffice(expenses, taxYear: taxYear, homeOffice: nil)
    }

    /// Combined monthly bills + home office export
    private func drawMonthlyBillsAndHomeOffice(_ expenses: [MonthlyExpense], taxYear: Int, homeOffice: HomeOffice?) {

        let monthNames = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]

        // Filter to only months that have data
        let activeExpenses = expenses.filter { $0.monthTotal > 0 }
        guard !activeExpenses.isEmpty else {
            drawSectionHeader("Monthly Bills — \(taxYear)")
            drawText("No monthly bills recorded.", at: CGPoint(x: margin, y: yPosition), font: bodyFont, color: gray)
            yPosition += 20
            if let ho = homeOffice { drawHomeOffice(ho, taxYear: taxYear) }
            return
        }

        // ── Table definitions: section name, fields, extractors ──

        let table1Fields: [(String, (MonthlyExpense) -> Decimal)] = [
            ("Rent/Mortgage", { $0.rentMortgage }),
            ("Renters/Homeowners Ins", { $0.rentersHomeownersIns }),
            ("Real Estate Taxes", { $0.realEstateTaxes }),
            ("Electric", { $0.electric }),
            ("Water/Sewer", { $0.waterSewer }),
            ("Gas/Propane", { $0.gasPropane }),
            ("Garbage", { $0.garbage }),
            ("Internet", { $0.internet }),
            ("HOA Dues", { $0.hoaDues }),
        ]

        let table2Fields: [(String, (MonthlyExpense) -> Decimal)] = [
            ("Cell Phone", { $0.cellPhone }),
            ("Malpractice/Liability", { $0.malpracticeLiability }),
            ("Health Insurance", { $0.healthInsurance }),
            ("Workers' Comp", { $0.workersComp }),
            ("Car Insurance", { $0.carInsurance }),
            ("Car Pmt Interest", { $0.carPaymentInterest }),
            ("Maint/Repairs", { $0.maintenanceRepairs }),
        ]

        let table3Fields: [(String, (MonthlyExpense) -> Decimal)] = [
            ("Prof. Memberships", { $0.professionalMemberships }),
            ("Software/Subscriptions", { $0.softwareSubscriptions }),
        ]

        let tables: [(title: String, fields: [(String, (MonthlyExpense) -> Decimal)])] = [
            ("Housing & Utilities", table1Fields),
            ("Phone, Insurance & Vehicle", table2Fields),
            ("Subscriptions", table3Fields),
        ]

        var billsGrandTotal: Decimal = 0

        for table in tables {
            // Filter to only fields that have data across ALL active months
            let activeFields = table.fields.filter { field in
                activeExpenses.contains { field.1($0) > 0 }
            }
            guard !activeFields.isEmpty else { continue }

            // ── Section banner (teal) ──
            checkPageBreak(60)
            context?.setFillColor(teal.cgColor)
            context?.fill(CGRect(x: margin, y: yPosition - 2, width: contentWidth, height: 20))
            drawText("\(table.title) — \(taxYear)", at: CGPoint(x: margin + 4, y: yPosition + 1), font: sectionFont, color: .white)
            yPosition += 22

            // Calculate column widths: Month + active fields + Total
            let monthColWidth: CGFloat = 62
            let totalColWidth: CGFloat = 56
            let remainingWidth = contentWidth - monthColWidth - totalColWidth
            let fieldColWidth = remainingWidth / CGFloat(activeFields.count)

            var colWidths: [CGFloat] = [monthColWidth]
            for _ in activeFields { colWidths.append(fieldColWidth) }
            colWidths.append(totalColWidth)

            // Column headers (gray background)
            var headers = ["Month"]
            for field in activeFields { headers.append(field.0) }
            headers.append("Total")
            drawTableRow(headers, widths: colWidths, font: headerFont, color: graphite, bgColor: lightGray)

            // Data rows — always show Jan through Dec
            var sectionTotal: Decimal = 0

            for monthNum in 1...12 {
                checkPageBreak(14)
                let monthLabel = monthNames[monthNum - 1]

                // Find the expense record for this month (if any)
                let exp = expenses.first(where: { $0.month == monthNum })

                var rowValues: [String] = [monthLabel]
                var rowTotal: Decimal = 0
                for field in activeFields {
                    let val = exp.map { field.1($0) } ?? 0
                    rowValues.append(val > 0 ? formatMoney(val) : "")
                    rowTotal += val
                }
                rowValues.append(rowTotal > 0 ? formatMoney(rowTotal) : "")
                sectionTotal += rowTotal

                drawTableRow(rowValues, widths: colWidths, font: bodyFont, color: graphite)
            }

            // Section total row — yellow highlight
            checkPageBreak(18)
            yPosition += 2
            context?.setFillColor(UIColor(red: 255/255, green: 255/255, blue: 0, alpha: 0.3).cgColor)
            context?.fill(CGRect(x: margin, y: yPosition - 2, width: contentWidth, height: 16))

            var totalRowValues: [String] = ["Total"]
            // Column totals for each active field
            for field in activeFields {
                let colTotal = expenses.reduce(Decimal(0)) { $0 + field.1($1) }
                totalRowValues.append(formatMoney(colTotal))
            }
            totalRowValues.append(formatMoney(sectionTotal))
            drawTableRow(totalRowValues, widths: colWidths, font: totalFont, color: graphite)

            yPosition += 16
            billsGrandTotal += sectionTotal
        }

        // ── Grand Total Summary ──
        checkPageBreak(24)
        yPosition += 4
        context?.setFillColor(UIColor(red: 255/255, green: 255/255, blue: 0, alpha: 0.45).cgColor)
        context?.fill(CGRect(x: margin, y: yPosition - 2, width: contentWidth, height: 18))

        let summaryWidths: [CGFloat] = [contentWidth * 0.6, contentWidth * 0.4]
        drawTableRow(["TOTAL MONTHLY BILLS (\(taxYear))", formatMoney(billsGrandTotal)],
                     widths: summaryWidths, font: totalFont, color: graphite)
        yPosition += 24

        // ── Home Office Deduction (if present) ──
        if let ho = homeOffice {
            drawHomeOffice(ho, taxYear: taxYear)
        }
    }

    // MARK: - Individual Expenses

    private func drawIndividualExpenses(_ expenses: [MiscExpense], agencies: [Agency]) {
        // Date | Item | Description | Company | Cost | Receipt Name
        let colWidths: [CGFloat] = [62, 80, 140, 80, 60, 78]

        let grouped = Dictionary(grouping: expenses) { agencyName($0.agencyId, agencies: agencies) }
        var grandTotal: Decimal = 0

        for (company, companyExpenses) in grouped.sorted(by: { $0.key < $1.key }) {
            checkPageBreak(50)

            // Company banner header (teal)
            context?.setFillColor(teal.cgColor)
            context?.fill(CGRect(x: margin, y: yPosition - 2, width: contentWidth, height: 20))
            drawText("\(company) — Expenses", at: CGPoint(x: margin + 4, y: yPosition + 1), font: sectionFont, color: .white)
            yPosition += 22

            // Column headers (gray background)
            drawTableRow(["Date", "Item", "Description", "Company", "Cost", "Receipt Name"],
                         widths: colWidths, font: headerFont, color: graphite, bgColor: lightGray)

            var companyTotal: Decimal = 0
            let sortedExpenses = companyExpenses.sorted { $0.date < $1.date }

            for exp in sortedExpenses {
                checkPageBreak(14)
                drawTableRow([
                    formatDate(exp.date),
                    MiscExpense.categoryLabel(for: exp.category),
                    exp.description ?? "",
                    company,
                    formatMoney(exp.amount),
                    exp.receiptUrl ?? ""
                ], widths: colWidths, font: bodyFont, color: graphite)
                companyTotal += exp.amount
            }

            // Company total row with green highlight
            yPosition += 2
            checkPageBreak(16)
            context?.setFillColor(UIColor(red: 11/255, green: 138/255, blue: 110/255, alpha: 0.15).cgColor)
            context?.fill(CGRect(x: margin, y: yPosition - 2, width: contentWidth, height: 14))
            drawTableRow([
                "\(company) Total", "", "", "",
                formatMoney(companyTotal), ""
            ], widths: colWidths, font: totalFont, color: green)
            yPosition += 8
            grandTotal += companyTotal
        }

        // Grand total row with yellow highlight
        checkPageBreak(20)
        context?.setFillColor(UIColor(red: 255/255, green: 255/255, blue: 0, alpha: 0.3).cgColor)
        context?.fill(CGRect(x: margin, y: yPosition - 2, width: contentWidth, height: 16))
        drawTableRow([
            "GRAND TOTAL", "", "", "",
            formatMoney(grandTotal), ""
        ], widths: colWidths, font: totalFont, color: graphite)
        yPosition += 24
    }

    // MARK: - Meals (grouped by company)

    private func drawMeals(_ meals: [Meal], agencies: [Agency]) {
        let colWidths: [CGFloat] = [68, 68, 68, 68, 72, 100, 88]
        // Date | Breakfast | Lunch | Dinner | Total | Company | Receipt Name

        let grouped = Dictionary(grouping: meals) { agencyName($0.agencyId, agencies: agencies) }
        var grandTotal: Decimal = 0

        for (company, companyMeals) in grouped.sorted(by: { $0.key < $1.key }) {
            checkPageBreak(50)

            // Company banner header (teal)
            context?.setFillColor(teal.cgColor)
            context?.fill(CGRect(x: margin, y: yPosition - 2, width: contentWidth, height: 20))
            drawText("\(company) — Meals", at: CGPoint(x: margin + 4, y: yPosition + 1), font: sectionFont, color: .white)
            yPosition += 22

            // Column headers (gray background)
            drawTableRow(["Date", "Breakfast", "Lunch", "Dinner", "Total", "Company", "Receipt Name"],
                         widths: colWidths, font: headerFont, color: graphite, bgColor: lightGray)

            var companyTotal: Decimal = 0
            let sortedMeals = companyMeals.sorted { $0.date < $1.date }

            for meal in sortedMeals {
                checkPageBreak(14)
                let total = meal.breakfast + meal.lunch + meal.dinner
                drawTableRow([
                    formatDate(meal.date),
                    formatMoney(meal.breakfast),
                    formatMoney(meal.lunch),
                    formatMoney(meal.dinner),
                    formatMoney(total),
                    company,
                    meal.receiptNumber ?? ""
                ], widths: colWidths, font: bodyFont, color: graphite)
                companyTotal += total
            }

            // Company total row with green highlight
            yPosition += 2
            checkPageBreak(16)
            context?.setFillColor(UIColor(red: 11/255, green: 138/255, blue: 110/255, alpha: 0.15).cgColor)
            context?.fill(CGRect(x: margin, y: yPosition - 2, width: contentWidth, height: 14))
            drawTableRow([
                "\(company) Total", "", "", "",
                formatMoney(companyTotal), "", ""
            ], widths: colWidths, font: totalFont, color: green)
            yPosition += 8
            grandTotal += companyTotal
        }

        // Grand total row with bold green highlight
        checkPageBreak(20)
        context?.setFillColor(UIColor(red: 255/255, green: 255/255, blue: 0, alpha: 0.3).cgColor)
        context?.fill(CGRect(x: margin, y: yPosition - 2, width: contentWidth, height: 16))
        drawTableRow([
            "GRAND TOTAL", "", "", "",
            formatMoney(grandTotal), "", ""
        ], widths: colWidths, font: totalFont, color: graphite)
        yPosition += 24
    }

    // MARK: - Mileage (grouped by company)

    private func drawMileage(_ trips: [Trip], agencies: [Agency], visitTypes: [VisitType]) {
        let grouped = Dictionary(grouping: trips) { agencyName($0.agencyId, agencies: agencies) }
        var grandTotalMiles: Decimal = 0
        var grandTotalExpenses: Decimal = 0

        // Column widths matching spreadsheet layout
        let colWidths: [CGFloat] = [58, 45, 68, 62, 62, 62, 50, 62, 50]
        // Date | Visit ID | Destination | Visit Type | Odo Start | Odo Stop | Miles | Expenses | Amount

        for (company, companyTrips) in grouped.sorted(by: { $0.key < $1.key }) {
            checkPageBreak(50)

            // Company banner header (like your spreadsheet title row)
            context?.setFillColor(teal.cgColor)
            context?.fill(CGRect(x: margin, y: yPosition - 2, width: contentWidth, height: 20))
            drawText(company, at: CGPoint(x: margin + 4, y: yPosition + 1), font: sectionFont, color: .white)
            yPosition += 22

            // Column headers (gray background like spreadsheet)
            drawTableRow(
                ["Date", "Visit ID", "Destination", "Type of Visit", "Odo Start", "Odo Stop", "Total Miles", "Expenses", "Amount"],
                widths: colWidths, font: headerFont, color: graphite, bgColor: lightGray
            )

            var companyMiles: Decimal = 0
            var companyExp: Decimal = 0

            for trip in companyTrips {
                checkPageBreak(14)
                let miles = trip.distanceMiles ?? 0
                let tolls = trip.tolls ?? 0
                let parking = trip.parking ?? 0
                let ferry = trip.ferry ?? 0
                let other = trip.otherExpense ?? 0
                let tripExp = tolls + parking + ferry + other

                let vtName = visitTypeName(trip.visitTypeId, visitTypes: visitTypes)

                // Odometer: show readings if odometer mode, blank if address mode
                let odoStart: String
                let odoStop: String
                if trip.trackingMethod == "odometer" {
                    odoStart = trip.odometerStart.map { formatNumber($0) } ?? ""
                    odoStop = trip.odometerStop.map { formatNumber($0) } ?? ""
                } else {
                    odoStart = ""
                    odoStop = ""
                }

                // Build expense type string (combine all into one label)
                var expenseTypes: [String] = []
                if tolls > 0 { expenseTypes.append("Tolls") }
                if parking > 0 { expenseTypes.append("Parking") }
                if ferry > 0 { expenseTypes.append("Ferry") }
                if other > 0 { expenseTypes.append("Other") }
                let expTypeStr = expenseTypes.joined(separator: ", ")

                drawTableRow([
                    formatDate(trip.date),
                    trip.contractVisitId ?? "",
                    trip.destinationCity ?? "",
                    vtName,
                    odoStart,
                    odoStop,
                    String(format: "%.0f", NSDecimalNumber(decimal: miles).doubleValue),
                    expTypeStr,
                    tripExp > 0 ? formatMoney(tripExp) : ""
                ], widths: colWidths, font: bodyFont, color: graphite)

                companyMiles += miles
                companyExp += tripExp
            }

            // Company total row — highlighted in green like your yellow row
            yPosition += 2
            let totalBgColor = UIColor(red: 11/255, green: 138/255, blue: 110/255, alpha: 0.15)
            context?.setFillColor(totalBgColor.cgColor)
            context?.fill(CGRect(x: margin, y: yPosition - 2, width: contentWidth, height: 16))

            let milesStr = String(format: "%.0f", NSDecimalNumber(decimal: companyMiles).doubleValue)
            drawTableRow([
                "\(companyTrips.count) trips", "", "", "", "", "",
                milesStr,
                "",
                companyExp > 0 ? formatMoney(companyExp) : ""
            ], widths: colWidths, font: totalFont, color: green)

            yPosition += 10

            grandTotalMiles += companyMiles
            grandTotalExpenses += companyExp
        }

        // Grand total row
        yPosition += 4
        let grandBgColor = UIColor(red: 11/255, green: 138/255, blue: 110/255, alpha: 0.25)
        context?.setFillColor(grandBgColor.cgColor)
        context?.fill(CGRect(x: margin, y: yPosition - 2, width: contentWidth, height: 18))

        let grandMilesStr = String(format: "%.0f", NSDecimalNumber(decimal: grandTotalMiles).doubleValue)
        drawText("TOTAL", at: CGPoint(x: margin + 4, y: yPosition), font: totalFont, color: graphite)
        // Position miles total under the miles column
        let milesX: CGFloat = colWidths[0...5].reduce(margin + 4) { $0 + $1 }
        drawText(grandMilesStr, at: CGPoint(x: milesX, y: yPosition), font: totalFont, color: green)
        // Position expense total under amount column
        let amountX: CGFloat = colWidths[0...7].reduce(margin + 4) { $0 + $1 }
        drawText(formatMoney(grandTotalExpenses), at: CGPoint(x: amountX, y: yPosition), font: totalFont, color: green)
        yPosition += 25
    }

    // MARK: - Pay (grouped by company)

    private func drawPay(_ income: [Income], agencies: [Agency], visitTypes: [VisitType]) {
        // Contract # | Service Date | Date Paid | Adv. Rate | Gross Pay | Set Aside | Tax % | Net Pay | Notes
        let colWidths: [CGFloat] = [52, 52, 52, 58, 62, 62, 45, 62, 55]

        let grouped = Dictionary(grouping: income) { agencyName($0.agencyId, agencies: agencies) }
        var grandGross: Decimal = 0
        var grandSetAside: Decimal = 0
        var grandNet: Decimal = 0

        for (company, companyIncome) in grouped.sorted(by: { $0.key < $1.key }) {
            checkPageBreak(50)

            // Company banner header (teal)
            context?.setFillColor(teal.cgColor)
            context?.fill(CGRect(x: margin, y: yPosition - 2, width: contentWidth, height: 20))
            drawText("\(company) Pay", at: CGPoint(x: margin + 4, y: yPosition + 1), font: sectionFont, color: .white)
            yPosition += 22

            // Column headers (gray background)
            drawTableRow(
                ["Contract #", "Service Date", "Date Paid", "Adv. Rate", "Gross Pay", "Set Aside", "Tax %", "Net Pay", "Notes"],
                widths: colWidths, font: headerFont, color: graphite, bgColor: lightGray
            )

            var companyGross: Decimal = 0
            var companySetAside: Decimal = 0

            let sortedIncome = companyIncome.sorted { $0.dateOfService < $1.dateOfService }

            for entry in sortedIncome {
                checkPageBreak(14)
                let setAside = entry.taxSetAsideAmount ?? 0
                let net = entry.grossPay - setAside
                let pct = entry.grossPay > 0 ? (setAside / entry.grossPay) * 100 : 0
                let pctStr = String(format: "%.1f%%", NSDecimalNumber(decimal: pct).doubleValue)

                let datePaidStr: String
                if let dp = entry.datePaid, !dp.isEmpty {
                    datePaidStr = formatDate(dp)
                } else {
                    datePaidStr = "Pending"
                }

                drawTableRow([
                    entry.contractVisitId ?? "",
                    formatDate(entry.dateOfService),
                    datePaidStr,
                    {
                        let rate = entry.advertisedRate ?? ""
                        if rate.isEmpty { return "" }
                        if entry.rateType == "hourly" { return "$\(rate)/hr" }
                        if entry.rateType == "flat_rate" { return "$\(rate) flat" }
                        return rate
                    }(),
                    formatMoney(entry.grossPay),
                    formatMoney(setAside),
                    pctStr,
                    formatMoney(net),
                    entry.notes ?? ""
                ], widths: colWidths, font: bodyFont, color: graphite)

                companyGross += entry.grossPay
                companySetAside += setAside
            }

            let companyNet = companyGross - companySetAside
            let companyPct = companyGross > 0 ? (companySetAside / companyGross) * 100 : 0
            let companyPctStr = String(format: "%.1f%%", NSDecimalNumber(decimal: companyPct).doubleValue)

            // Company total row with green highlight
            yPosition += 2
            checkPageBreak(16)
            context?.setFillColor(UIColor(red: 11/255, green: 138/255, blue: 110/255, alpha: 0.15).cgColor)
            context?.fill(CGRect(x: margin, y: yPosition - 2, width: contentWidth, height: 14))
            drawTableRow([
                "\(company) Total", "", "", "",
                formatMoney(companyGross),
                formatMoney(companySetAside),
                companyPctStr,
                formatMoney(companyNet),
                ""
            ], widths: colWidths, font: totalFont, color: green)
            yPosition += 8

            grandGross += companyGross
            grandSetAside += companySetAside
        }

        grandNet = grandGross - grandSetAside
        let grandPct = grandGross > 0 ? (grandSetAside / grandGross) * 100 : 0
        let grandPctStr = String(format: "%.1f%%", NSDecimalNumber(decimal: grandPct).doubleValue)

        // Grand total row with yellow highlight
        checkPageBreak(20)
        context?.setFillColor(UIColor(red: 255/255, green: 255/255, blue: 0, alpha: 0.3).cgColor)
        context?.fill(CGRect(x: margin, y: yPosition - 2, width: contentWidth, height: 16))
        drawTableRow([
            "GRAND TOTAL", "", "", "",
            formatMoney(grandGross),
            formatMoney(grandSetAside),
            grandPctStr,
            formatMoney(grandNet),
            ""
        ], widths: colWidths, font: totalFont, color: graphite)
        yPosition += 24
    }

    // MARK: - Drawing Helpers

    private func drawText(_ text: String, at point: CGPoint, font: UIFont, color: UIColor) {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        (text as NSString).draw(at: point, withAttributes: attrs)
    }

    private func drawSectionHeader(_ title: String) {
        checkPageBreak(30)
        drawText(title, at: CGPoint(x: margin, y: yPosition), font: sectionFont, color: graphite)
        yPosition += 18
        drawLine(color: teal, width: 1)
        yPosition += 8
    }

    private func drawLine(color: UIColor, width: CGFloat) {
        context?.setStrokeColor(color.cgColor)
        context?.setLineWidth(width)
        context?.move(to: CGPoint(x: margin, y: yPosition))
        context?.addLine(to: CGPoint(x: pageWidth - margin, y: yPosition))
        context?.strokePath()
    }

    private func drawTableRow(_ values: [String], widths: [CGFloat], font: UIFont, color: UIColor, bgColor: UIColor? = nil) {
        let rowHeight: CGFloat = 14

        if let bg = bgColor {
            context?.setFillColor(bg.cgColor)
            context?.fill(CGRect(x: margin, y: yPosition - 2, width: contentWidth, height: rowHeight))
        }

        var xPos = margin + 4
        for (i, val) in values.enumerated() {
            let w = i < widths.count ? widths[i] : 60
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
            let rect = CGRect(x: xPos, y: yPosition, width: w - 4, height: rowHeight)
            (val as NSString).draw(in: rect, withAttributes: attrs)
            xPos += w
        }
        yPosition += rowHeight
    }

    private func drawFooter() {
        let footerY = pageHeight - 25
        if let appIcon = UIImage(named: "medmiles-icon-final-graphite") ?? UIImage(named: "AppIcon") {
            appIcon.draw(in: CGRect(x: margin, y: footerY - 2, width: 12, height: 12))
            drawText("MedMiles — Track it all. Keep what's yours.  |  All figures are estimates.", at: CGPoint(x: margin + 16, y: footerY), font: captionFont, color: gray)
        } else {
            drawText("MedMiles — All figures are estimates. Consult your CPA.", at: CGPoint(x: margin, y: footerY), font: captionFont, color: gray)
        }
    }

    // MARK: - Helpers

    private func formatMoney(_ val: Decimal) -> String {
        String(format: "$%.2f", NSDecimalNumber(decimal: val).doubleValue)
    }

    private static let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return formatter
    }()

    private func formatNumber(_ val: Decimal) -> String {
        let num = NSDecimalNumber(decimal: val).intValue
        return Self.numberFormatter.string(from: NSNumber(value: num)) ?? "\(num)"
    }

    private func formatDate(_ dateStr: String) -> String {
        if let date = isoDateFormatter.date(from: dateStr) {
            return dateFormatter.string(from: date)
        }
        return dateStr
    }

    private func agencyName(_ agencyId: UUID?, agencies: [Agency]) -> String {
        guard let id = agencyId else { return "Unassigned" }
        return agencies.first(where: { $0.id == id })?.name ?? "Unknown"
    }

    private func visitTypeName(_ vtId: UUID?, visitTypes: [VisitType]) -> String {
        guard let id = vtId else { return "" }
        return visitTypes.first(where: { $0.id == id })?.name ?? ""
    }
}
