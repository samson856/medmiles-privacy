import SwiftUI
import Auth
import Supabase

struct ExportCenterView: View {
    @EnvironmentObject var authService: AuthService
    @StateObject private var exportService = ExportService()
    private let pdfService = ExportPDFService()

    @State private var showShareSheet = false
    @State private var shareURL: URL?
    @State private var shareURLs: [URL] = []
    @State private var isExportingPDF = false
    @State private var isExportingReceipts = false

    @State private var taxYear = Calendar.current.component(.year, from: Date())
    @State private var exportStartDate: Date = Calendar.current.date(from: DateComponents(year: Calendar.current.component(.year, from: Date()), month: 1, day: 1))!
    @State private var exportEndDate: Date = Calendar.current.date(from: DateComponents(year: Calendar.current.component(.year, from: Date()), month: 12, day: 31))!

    private var availableYears: [Int] {
        let current = Calendar.current.component(.year, from: Date())
        return Array((current - 2)...current).reversed()
    }

    private let exportDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private var formattedStartDate: String {
        exportDateFormatter.string(from: exportStartDate)
    }

    private var formattedEndDate: String {
        exportDateFormatter.string(from: exportEndDate)
    }

    @State private var showUpgradePrompt = false
    private var store = StoreKitService.shared

    var body: some View {
        if !store.canExport() {
            UpgradePromptView(
                title: "Export is a Pro Feature",
                message: "You've used your free export. Upgrade to MedMiles Pro for unlimited CPA-ready reports.",
                isPresented: $showUpgradePrompt
            )
            .navigationTitle("Export Center")
        } else {
            VStack(spacing: 0) {
                if store.usesFreeExport() {
                    HStack(spacing: 8) {
                        Image(systemName: "gift.fill")
                            .foregroundColor(Color(Constants.Colors.mintTeal))
                        Text("You have 1 free export. After this, you'll need Pro for more.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(12)
                    .background(Color(Constants.Colors.mintTeal).opacity(0.1))
                    .cornerRadius(10)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }

                // Year selector
                Picker("Tax Year", selection: $taxYear) {
                    ForEach(availableYears, id: \.self) { year in
                        Text(String(year)).tag(year)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .onChange(of: taxYear) { newYear in
                    exportStartDate = Calendar.current.date(from: DateComponents(year: newYear, month: 1, day: 1))!
                    exportEndDate = Calendar.current.date(from: DateComponents(year: newYear, month: 12, day: 31))!
                }

                // Date range pickers
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("From")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        DatePicker("", selection: $exportStartDate, displayedComponents: .date)
                            .labelsHidden()
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("To")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        DatePicker("", selection: $exportEndDate, displayedComponents: .date)
                            .labelsHidden()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)

                exportContent
            }
        }
    }

    var exportContent: some View {
        Form {
            Section {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(Color(Constants.Colors.mintTeal))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Export your data as CSV files you can open in Excel or Google Sheets.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("All tax figures are estimates. Consult your CPA for tax advice.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .italic()
                    }
                }
            }

            // Full Export
            Section(header: Text("Complete Export")) {
                ExportOptionRow(
                    icon: "doc.richtext.fill",
                    title: "Full CPA Report (PDF)",
                    description: "Professional formatted PDF — Home Office, Monthly Bills, Expenses, Meals, Mileage, Pay",
                    fileType: "PDF",
                    isExporting: isExportingPDF
                ) {
                    await exportFullPDF()
                }

                ExportOptionRow(
                    icon: "tablecells.fill",
                    title: "Full CPA Workbook (CSV)",
                    description: "All 6 reports as CSV files for Excel / Google Sheets",
                    fileType: "CSV Bundle",
                    isExporting: exportService.isExporting
                ) {
                    await exportFull()
                }
            }

            // Individual Exports
            Section(header: Text("Individual Reports")) {
                ExportOptionRow(
                    icon: "car.fill",
                    title: "Mileage Log",
                    description: "All trips grouped by company with totals",
                    fileType: "PDF",
                    isExporting: isExportingPDF
                ) {
                    await exportSectionPDF(section: "mileage")
                }

                ExportOptionRow(
                    icon: "dollarsign.circle.fill",
                    title: "Income / Pay Report",
                    description: "Gross pay, tax set-aside, net pay grouped by company",
                    fileType: "PDF",
                    isExporting: isExportingPDF
                ) {
                    await exportSectionPDF(section: "pay")
                }

                ExportOptionRow(
                    icon: "bag.fill",
                    title: "Individual Expenses",
                    description: "All misc/individual expenses with receipt tracking",
                    fileType: "PDF",
                    isExporting: isExportingPDF
                ) {
                    await exportSectionPDF(section: "expenses")
                }

                ExportOptionRow(
                    icon: "fork.knife",
                    title: "Meals Report",
                    description: "Breakfast, lunch, dinner grouped by company",
                    fileType: "PDF",
                    isExporting: isExportingPDF
                ) {
                    await exportSectionPDF(section: "meals")
                }

                ExportOptionRow(
                    icon: "creditcard.fill",
                    title: "Monthly Bills & Home Office",
                    description: "Recurring bills by category + home office deduction",
                    fileType: "PDF",
                    isExporting: isExportingPDF
                ) {
                    await exportSectionPDF(section: "monthly_homeoffice")
                }
            }

            // Receipt Bundle
            Section(header: Text("Receipts")) {
                ExportOptionRow(
                    icon: "photo.on.rectangle.angled",
                    title: "Receipt Bundle",
                    description: "All stored receipt photos organized by Meals & Expenses",
                    fileType: "Files",
                    isExporting: isExportingReceipts
                ) {
                    await exportReceiptBundle()
                }
            }

            if let error = exportService.errorMessage {
                Section {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(Color(Constants.Colors.errorRed))
                }
            }
        }
        .navigationTitle("Export Center")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showShareSheet) {
            if !shareURLs.isEmpty {
                ShareSheet(items: shareURLs as [Any])
            } else if let url = shareURL {
                ShareSheet(items: [url] as [Any])
            }
        }
    }

    // MARK: - Export Actions

    private func exportSectionPDF(section: String) async {
        guard let userId = authService.currentSession?.user.id else { return }
        let userName = authService.currentProfile?.fullName ?? "User"
        isExportingPDF = true
        if let url = await pdfService.generateSectionPDF(userId: userId, taxYear: taxYear, userName: userName, section: section, startDate: formattedStartDate, endDate: formattedEndDate) {
            shareURL = url
            shareURLs = []
            showShareSheet = true
        }
        isExportingPDF = false
    }

    private func exportFullPDF() async {
        guard let userId = authService.currentSession?.user.id else { return }
        let userName = authService.currentProfile?.fullName ?? "User"
        isExportingPDF = true
        if let url = await pdfService.generateFullPDF(userId: userId, taxYear: taxYear, userName: userName, startDate: formattedStartDate, endDate: formattedEndDate) {
            shareURL = url
            shareURLs = []
            store.recordFreeExport()
            ReviewService.shared.recordExportCompleted()
            showShareSheet = true
        }
        isExportingPDF = false
    }

    private func exportFull() async {
        guard let userId = authService.currentSession?.user.id else { return }
        if let folderURL = await exportService.generateFullExport(userId: userId, taxYear: taxYear, startDate: formattedStartDate, endDate: formattedEndDate) {
            // Get all CSV files in the folder
            if let files = try? FileManager.default.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil) {
                shareURLs = files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
                shareURL = nil
                store.recordFreeExport()
                ReviewService.shared.recordExportCompleted()
                showShareSheet = true
            }
        }
    }

    private func exportReceiptBundle() async {
        guard let userId = authService.currentSession?.user.id else { return }
        isExportingReceipts = true
        defer { isExportingReceipts = false }

        let client = SupabaseService.shared.client

        do {
            // Fetch meals with receipts (filter by date range for tax year)
            let meals: [Meal] = try await client.from("meals")
                .select().eq("user_id", value: userId)
                .gte("date", value: formattedStartDate)
                .lte("date", value: formattedEndDate)
                .order("date", ascending: true).execute().value

            let agencies: [Agency] = try await client.from("agencies")
                .select().eq("user_id", value: userId).execute().value

            let miscExpenses: [MiscExpense] = try await client.from("misc_expenses")
                .select().eq("user_id", value: userId)
                .eq("tax_year", value: taxYear)
                .order("date", ascending: true).execute().value

            // Build meal receipt list
            let mealReceipts: [(mealDate: String, agencyName: String, filenames: [String])] = meals.compactMap { meal in
                let filenames = meal.receiptUrls ?? []
                guard !filenames.isEmpty else { return nil }
                let agencyName: String
                if let aid = meal.agencyId {
                    agencyName = agencies.first(where: { $0.id == aid })?.name ?? "Unassigned"
                } else {
                    agencyName = "Unassigned"
                }
                return (mealDate: meal.date, agencyName: agencyName, filenames: filenames)
            }

            // Build expense receipt list
            let expenseReceipts: [(expenseDate: String, category: String, agencyName: String, filenames: [String])] = miscExpenses.compactMap { exp in
                guard exp.hasReceipt else { return nil }
                // Get receipt files for this expense ID
                let filenames = LocalStorageService.shared.receiptFilenames(for: exp.id)
                guard !filenames.isEmpty else { return nil }
                let agencyName: String
                if let aid = exp.agencyId {
                    agencyName = agencies.first(where: { $0.id == aid })?.name ?? "Unassigned"
                } else {
                    agencyName = "Unassigned"
                }
                let categoryLabel = MiscExpense.categoryLabel(for: exp.category)
                return (expenseDate: exp.date, category: categoryLabel, agencyName: agencyName, filenames: filenames)
            }

            if let bundleDir = LocalStorageService.shared.bundleReceiptsForExport(
                mealReceipts: mealReceipts,
                expenseReceipts: expenseReceipts,
                taxYear: taxYear
            ) {
                // Collect all files in the bundle for sharing
                let fm = FileManager.default
                var files: [URL] = []
                if let enumerator = fm.enumerator(at: bundleDir, includingPropertiesForKeys: nil) {
                    while let fileURL = enumerator.nextObject() as? URL {
                        var isDir: ObjCBool = false
                        fm.fileExists(atPath: fileURL.path, isDirectory: &isDir)
                        if !isDir.boolValue {
                            files.append(fileURL)
                        }
                    }
                }

                if !files.isEmpty {
                    shareURLs = files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
                    shareURL = nil
                    showShareSheet = true
                }
            }
        } catch {
            exportService.errorMessage = "Failed to export receipts: \(error.localizedDescription)"
        }
    }
}

// MARK: - Export Option Row

struct ExportOptionRow: View {
    let icon: String
    let title: String
    let description: String
    let fileType: String
    let isExporting: Bool
    let action: () async -> Void

    var body: some View {
        Button {
            Task { await action() }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(Color(Constants.Colors.mintTeal))
                    .frame(width: 36)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    Text(description)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                if isExporting {
                    ProgressView()
                } else {
                    VStack(spacing: 2) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.caption)
                        Text(fileType)
                            .font(.caption2)
                    }
                    .foregroundColor(Color(Constants.Colors.mintTeal))
                }
            }
            .padding(.vertical, 4)
        }
        .disabled(isExporting)
    }
}

// Uses ShareSheet from Views/Shared/ShareSheet.swift
// UpgradePromptView from Views/Shared/UpgradePromptView.swift
