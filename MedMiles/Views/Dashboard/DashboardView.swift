import SwiftUI
import Auth

struct DashboardView: View {
    @EnvironmentObject var authService: AuthService
    @StateObject private var viewModel = DashboardViewModel()
    @AppStorage("hasSeenStorageWarning") private var hasSeenStorageWarning = false

    // Navigation state
    @State private var showExpenses = false
    @State private var showCredentials = false
    @State private var showTaxCenter = false
    @State private var showExportCenter = false
    @State private var showIndividualExpenses = false
    @State private var showHomeOffice = false
    @State private var showSettings = false
    @State private var showReceiptScanner = false
    @State private var showTaxExplanation = false

    // Year selector (set in Settings)
    @AppStorage("selectedTaxYear") private var selectedYear = Calendar.current.component(.year, from: Date())

    private func fmt(_ val: Decimal) -> String {
        String(format: "$%.2f", NSDecimalNumber(decimal: val).doubleValue)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Network error banner
                    if let error = viewModel.errorMessage {
                        HStack(spacing: 10) {
                            Image(systemName: "wifi.slash")
                                .foregroundColor(Color(Constants.Colors.errorRed))
                            Text(error)
                                .font(.caption)
                                .foregroundColor(Color(Constants.Colors.errorRed))
                            Spacer()
                            Button("Retry") {
                                viewModel.errorMessage = nil
                                guard let userId = authService.currentSession?.user.id else { return }
                                Task { await viewModel.loadDashboard(userId: userId) }
                            }
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(Color(Constants.Colors.mintTeal))
                        }
                        .padding(12)
                        .background(Color(Constants.Colors.errorRed).opacity(0.1))
                        .cornerRadius(10)
                    }

                    // Year mismatch warning banner
                    if selectedYear != Calendar.current.component(.year, from: Date()) {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "calendar.badge.exclamationmark")
                                .foregroundColor(Color(Constants.Colors.warningAmber))
                                .font(.title3)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Viewing \(String(selectedYear)) data")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                Text("You have \(String(selectedYear)) selected as your tax year. Dashboard totals and reports reflect \(String(selectedYear)) data, not the current year. Change your tax year in Settings to see current data.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(14)
                        .background(Color(Constants.Colors.warningAmber).opacity(0.12))
                        .cornerRadius(12)
                    }

                    // Local storage warning banner
                    if !hasSeenStorageWarning {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(Color(Constants.Colors.warningAmber))
                                .font(.title3)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Your data is stored locally")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                Text("Receipts and documents are saved on this device only. They are not backed up to the cloud. We recommend enabling iCloud backups in your iPhone Settings to protect your data.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Button {
                                withAnimation { hasSeenStorageWarning = true }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .accessibilityLabel("Dismiss storage warning")
                        }
                        .padding(14)
                        .background(Color(Constants.Colors.warningAmber).opacity(0.12))
                        .cornerRadius(12)
                    }

                    // YTD Metric Cards
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        MetricCard(
                            title: "Total Income",
                            value: fmt(viewModel.ytdIncome),
                            icon: "dollarsign.arrow.circlepath",
                            valueColor: Color(Constants.Colors.mintTeal)
                        )
                        .accessibilityLabel("Total income: \(fmt(viewModel.ytdIncome))")

                        MetricCard(
                            title: "Work Miles",
                            value: "\(NSDecimalNumber(decimal: viewModel.ytdMileageMiles).intValue) mi",
                            icon: "road.lanes",
                            valueColor: Color(Constants.Colors.mintTeal)
                        )
                        .accessibilityLabel("Work miles: \(NSDecimalNumber(decimal: viewModel.ytdMileageMiles).intValue) miles")
                    }

                    HStack(spacing: 12) {
                        MetricCard(
                            title: "Est. Quarterly Tax",
                            value: fmt(viewModel.estimatedQuarterlyTax),
                            icon: "hourglass.circle",
                            valueColor: Color(Constants.Colors.errorRed),
                            subtitle: viewModel.nextQuarterlyDeadline.map { "\($0.quarter) due \($0.date)" }
                        )
                        .frame(maxHeight: .infinity, alignment: .top)
                        .accessibilityLabel("Estimated quarterly tax: \(fmt(viewModel.estimatedQuarterlyTax))")
                        .onTapGesture { showTaxExplanation = true }

                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .foregroundColor(Color(Constants.Colors.warningAmber))
                                Text("Heads Up")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            Text("All tax figures are estimates. Consult your CPA.")
                                .font(.caption2)
                                .foregroundColor(Color(Constants.Colors.warningAmber))
                                .fontWeight(.medium)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(14)
                        .background(Color(.systemBackground))
                        .cornerRadius(12)
                        .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
                    }

                    // Scan Receipt button
                    Button {
                        showReceiptScanner = true
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "doc.viewfinder")
                                .font(.title3)
                            Text("Scan Receipt")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(Constants.Colors.mintTeal))
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .accessibilityLabel("Scan a receipt")

                    // Navigation icons — 2 rows of 3
                    VStack(spacing: 12) {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            DashboardIcon(title: "Monthly Bills", emoji: "scroll.fill", color: Color(Constants.Colors.mintTeal)) {
                                showExpenses = true
                            }

                            DashboardIcon(title: "Expenses", emoji: "tag.fill", color: Color(Constants.Colors.mintTeal)) {
                                showIndividualExpenses = true
                            }

                            DashboardIcon(title: "Credentials", emoji: "checkmark.seal.fill", color: Color(Constants.Colors.mintTeal)) {
                                showCredentials = true
                            }

                            DashboardIcon(title: "Home Office", emoji: "desktopcomputer", color: Color(Constants.Colors.mintTeal)) {
                                showHomeOffice = true
                            }

                            DashboardIcon(title: "Tax Center", emoji: "building.columns.fill", color: Color(Constants.Colors.mintTeal)) {
                                showTaxCenter = true
                            }

                            DashboardIcon(title: "Export", emoji: "arrow.up.doc.fill", color: Color(Constants.Colors.mintTeal)) {
                                showExportCenter = true
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .background(Color(Constants.Colors.background).ignoresSafeArea())
            .navigationTitle("MedMiles")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .foregroundColor(Color(Constants.Colors.graphite))
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .refreshable {
                guard let userId = authService.currentSession?.user.id else { return }
                await viewModel.loadDashboard(userId: userId)
            }
            .task {
                guard let userId = authService.currentSession?.user.id else { return }
                await viewModel.switchYear(to: selectedYear, userId: userId)
            }
            .onChange(of: selectedYear) { _, newYear in
                guard let userId = authService.currentSession?.user.id else { return }
                Task { await viewModel.switchYear(to: newYear, userId: userId) }
            }
            .overlay {
                if viewModel.isLoading && viewModel.ytdIncome == 0 && viewModel.tripCount == 0 {
                    VStack {
                        Spacer()
                        ProgressView("Loading dashboard…")
                            .progressViewStyle(.circular)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(Constants.Colors.background))
                }
            }
            .navigationDestination(isPresented: $showExpenses) {
                MonthlyTrackerView()
            }
            .navigationDestination(isPresented: $showIndividualExpenses) {
                IndividualExpenseTabView()
            }
            .navigationDestination(isPresented: $showCredentials) {
                CredentialListView()
            }
            .navigationDestination(isPresented: $showHomeOffice) {
                HomeOfficeSetupView()
            }
            .navigationDestination(isPresented: $showTaxCenter) {
                TaxCenterView()
            }
            .navigationDestination(isPresented: $showExportCenter) {
                ExportCenterView()
            }
            .navigationDestination(isPresented: $showSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showReceiptScanner) {
                ScannedReceiptReviewView()
            }
            .alert("Estimated Quarterly Tax", isPresented: $showTaxExplanation) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("This estimate is based on your gross income using standard self-employment tax rates (15.3%) and an approximate income tax rate (15%). Deductions are not included in this calculation — consult your CPA to ensure your quarterly payments reflect your most accurate, up-to-date personal deductions.")
            }
        }
    }
}

// MARK: - Dashboard Icon Button

struct DashboardIcon: View {
    let title: String
    var emoji: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: emoji)
                    .font(.title2)
                    .foregroundColor(color)
                    .frame(width: 48, height: 48)
                    .background(color.opacity(0.12))
                    .cornerRadius(12)

                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}
