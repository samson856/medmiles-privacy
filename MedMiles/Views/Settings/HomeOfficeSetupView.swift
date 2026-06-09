import SwiftUI
import Auth

struct HomeOfficeSetupView: View {
    @EnvironmentObject var authService: AuthService
    @StateObject private var viewModel = HomeOfficeViewModel()
    @Environment(\.dismiss) private var dismiss

    @State private var totalSqFt = ""
    @State private var officeSqFt = ""
    @State private var activeMonths: [Bool] = Array(repeating: true, count: 12)
    @State private var showSavedConfirmation = false
    @State private var hasLoaded = false

    private var businessUsePct: String {
        guard let total = Decimal(string: totalSqFt), total > 0,
              let office = Decimal(string: officeSqFt), office > 0 else { return "0.0%" }
        let pct = (office / total) * 100
        return String(format: "%.1f%%", NSDecimalNumber(decimal: pct).doubleValue)
    }

    private var activeMonthCount: Int {
        activeMonths.filter { $0 }.count
    }

    private var estimatedDeduction: String {
        guard let total = Decimal(string: totalSqFt), total > 0,
              let office = Decimal(string: officeSqFt), office > 0 else { return "$0.00" }
        // Simplified method: $5/sq ft (IRS simplified method, max 300 sq ft)
        let cappedSqFt = min(office, 300)
        let annualRate: Decimal = 5
        let monthFraction = Decimal(activeMonthCount) / 12
        let estimate = cappedSqFt * annualRate * monthFraction
        return String(format: "$%.2f", NSDecimalNumber(decimal: estimate).doubleValue)
    }

    var body: some View {
        Form {
            // Info banner
            Section {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(Color(Constants.Colors.mintTeal))
                    Text("Your business use percentage is calculated from your square footage and applied to housing and utility costs in the monthly tracker.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // Square footage
            Section(header: Text("Square Footage")) {
                HStack {
                    Text("Total Home")
                    Spacer()
                    TextField("sq ft", text: $totalSqFt)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                    Text("sq ft")
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("Office Space")
                    Spacer()
                    TextField("sq ft", text: $officeSqFt)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                    Text("sq ft")
                        .foregroundColor(.secondary)
                }
            }

            // Business use percentage — prominent display
            Section {
                VStack(spacing: 8) {
                    Text("Business Use")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text(businessUsePct)
                        .font(.largeTitle.bold())
                        .foregroundColor(Color(Constants.Colors.mintTeal))
                    Text("of your home is used for business")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }

            // Active months
            Section(header: Text("Active Months (\(activeMonthCount) of 12)")) {
                VStack(spacing: 4) {
                    Text("Select the months you worked as a 1099 contractor")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
                        ForEach(0..<12, id: \.self) { index in
                            Button {
                                activeMonths[index].toggle()
                            } label: {
                                Text(HomeOffice.monthNames[index])
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(
                                        activeMonths[index]
                                            ? Color(Constants.Colors.mintTeal)
                                            : Color(.systemGray5)
                                    )
                                    .foregroundColor(
                                        activeMonths[index] ? .white : .secondary
                                    )
                                    .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            // Estimated deduction
            Section {
                VStack(spacing: 6) {
                    Text("Estimated Annual Deduction")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text(estimatedDeduction)
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(Color(Constants.Colors.successGreen))
                    Text("Using IRS simplified method ($5/sq ft, max 300 sq ft)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("This is an estimate only. Consult your CPA for the best method for your situation.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .italic()
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }

            // Error
            if let error = viewModel.errorMessage {
                Section {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(Color(Constants.Colors.errorRed))
                }
            }

            // Save button
            Section {
                Button {
                    saveHomeOffice()
                } label: {
                    HStack {
                        Spacer()
                        if viewModel.isSaving {
                            ProgressView().tint(.white)
                        }
                        Text("Save Home Office")
                            .fontWeight(.semibold)
                        Spacer()
                    }
                    .padding(.vertical, 6)
                }
                .listRowBackground(Color(Constants.Colors.mintTeal))
                .foregroundColor(.white)
                .disabled(viewModel.isSaving)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Home Office")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard let userId = authService.currentSession?.user.id else { return }
            await viewModel.loadHomeOffice(userId: userId)
            if let ho = viewModel.homeOffice {
                totalSqFt = ho.totalSqFt.map { "\(NSDecimalNumber(decimal: $0).doubleValue)" } ?? ""
                officeSqFt = ho.officeSqFt.map { "\(NSDecimalNumber(decimal: $0).doubleValue)" } ?? ""
                activeMonths = ho.activeMonths
            }
            hasLoaded = true
        }
        .overlay {
            if showSavedConfirmation {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.largeTitle)
                        .foregroundColor(Color(Constants.Colors.successGreen))
                    Text("Home Office Saved!")
                        .font(.headline)
                }
                .padding(32)
                .background(.ultraThinMaterial)
                .cornerRadius(16)
            }
        }
    }

    private func saveHomeOffice() {
        guard let userId = authService.currentSession?.user.id else { return }
        Task {
            let success = await viewModel.saveHomeOffice(
                userId: userId,
                totalSqFt: totalSqFt,
                officeSqFt: officeSqFt,
                activeMonths: activeMonths
            )
            if success {
                showSavedConfirmation = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    showSavedConfirmation = false
                }
            }
        }
    }
}
