import SwiftUI
import Auth

struct TaxPayment: Codable, Identifiable {
    var id: UUID = UUID()
    var quarter: String
    var amount: Double
    var datePaid: Date
}

struct TaxCenterView: View {
    @EnvironmentObject var authService: AuthService
    @StateObject private var viewModel = TaxViewModel()

    // Year selector
    @State private var selectedYear = Calendar.current.component(.year, from: Date())
    @State private var showDetails = false

    // Tax payments
    @State private var taxPayments: [TaxPayment] = []
    @State private var showAddPayment = false

    private var availableYears: [Int] {
        let current = Calendar.current.component(.year, from: Date())
        return Array((current - 2)...current).reversed()
    }

    private func fmt(_ val: Decimal) -> String {
        String(format: "$%.2f", NSDecimalNumber(decimal: val).doubleValue)
    }

    private var quarterLabel: String {
        "Q\(viewModel.currentQuarter)"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Year selector
                Picker("Tax Year", selection: $selectedYear) {
                    ForEach(availableYears, id: \.self) { year in
                        Text(String(year)).tag(year)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: selectedYear) { _, newYear in
                    guard let userId = authService.currentSession?.user.id else { return }
                    Task { await viewModel.switchYear(to: newYear, userId: userId) }
                }

                // Disclaimer banner
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.shield.fill")
                        .foregroundColor(Color(Constants.Colors.warningAmber))
                    Text("All figures are estimates. Consult a CPA for tax advice.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(12)
                .background(Color(Constants.Colors.warningAmber).opacity(0.1))
                .cornerRadius(10)

                // Tax constants fallback warning
                if TaxConstantsService.shared.usingDefaults {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(Color(Constants.Colors.warningAmber))
                        Text("Tax rates may not be current. Tap refresh to update.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Button("Refresh") {
                            Task { await TaxConstantsService.shared.refreshConstants(for: viewModel.currentYear) }
                        }
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(Color(Constants.Colors.mintTeal))
                        .accessibilityLabel("Refresh tax rates")
                    }
                    .padding(12)
                    .background(Color(Constants.Colors.warningAmber).opacity(0.1))
                    .cornerRadius(10)
                }

                // Network error
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
                            Task { await viewModel.loadTaxData(userId: userId) }
                        }
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(Color(Constants.Colors.mintTeal))
                    }
                    .padding(12)
                    .background(Color(Constants.Colors.errorRed).opacity(0.1))
                    .cornerRadius(10)
                }

                // ─── CURRENT QUARTER CARD ───
                if let deadline = viewModel.nextUpcomingDeadline {
                    VStack(spacing: 12) {
                        // Header
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(deadline.daysUntil <= 30 ? Color(Constants.Colors.errorRed) : Color(Constants.Colors.warningAmber))
                            Text("\(deadline.quarter) Estimated Payment")
                                .font(.subheadline)
                                .fontWeight(.bold)
                            Spacer()
                            Text("\(deadline.daysUntil) days left")
                                .font(.caption)
                                .fontWeight(.medium)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background((deadline.daysUntil <= 30 ? Color(Constants.Colors.errorRed) : Color(Constants.Colors.mintTeal)).opacity(0.15))
                                .foregroundColor(deadline.daysUntil <= 30 ? Color(Constants.Colors.errorRed) : Color(Constants.Colors.mintTeal))
                                .cornerRadius(6)
                        }

                        // Mini breakdown
                        VStack(spacing: 6) {
                            HStack {
                                Text("\(quarterLabel) Gross Income")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(fmt(viewModel.quarterIncome))
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }

                            Divider()

                            HStack {
                                Text("Due \(deadline.date)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(fmt(viewModel.quarterEstimatedPayment))
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundColor(Color(Constants.Colors.errorRed))
                            }

                            Text("Based on gross income only. Deductions not included — consult your CPA.")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(16)
                    .background(Color(Constants.Colors.errorRed).opacity(0.08))
                    .cornerRadius(12)
                }

                // ─── YEAR-TO-DATE SUMMARY ───
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(String(viewModel.currentYear)) Year-to-Date")
                        .font(.headline)
                        .padding(.bottom, 12)

                    TaxLineItem(label: "Gross Income", value: fmt(viewModel.grossIncome))

                    Divider().padding(.vertical, 4)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Image(systemName: "chart.line.uptrend.xyaxis")
                                .font(.title3)
                                .foregroundColor(Color(Constants.Colors.mintTeal))
                            Text("Projected Annual Deductions")
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundColor(.primary)
                        }
                        Text("Rough estimate — final amounts may vary")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color(Constants.Colors.mintTeal).opacity(0.10))
                    .cornerRadius(10)
                    .padding(.vertical, 8)

                    if viewModel.mileageDeduction > 0 {
                        TaxLineItem(label: "Mileage (\(NSDecimalNumber(decimal: viewModel.totalMiles).intValue) mi × $\(viewModel.tc.irsMileageRate))",
                                    value: "−\(fmt(viewModel.mileageDeduction))", valueColor: Color(Constants.Colors.successGreen))
                    }
                    if viewModel.totalTripExpenses > 0 {
                        TaxLineItem(label: "Trip Expenses (tolls, parking)", value: "−\(fmt(viewModel.totalTripExpenses))", valueColor: Color(Constants.Colors.successGreen))
                    }
                    if viewModel.mealDeduction > 0 {
                        TaxLineItem(label: "Meals (\(Int(NSDecimalNumber(decimal: viewModel.tc.mealDeductionPct * 100).doubleValue))%)", value: "−\(fmt(viewModel.mealDeduction))", valueColor: Color(Constants.Colors.successGreen))
                    }
                    if viewModel.homeOfficeExpenses + viewModel.cellPhoneExpenses > 0 {
                        TaxLineItem(label: "Home Office & Cell (\(NSDecimalNumber(decimal: viewModel.businessUsePct).intValue)%)",
                                    value: "−\(fmt(viewModel.homeOfficeExpenses + viewModel.cellPhoneExpenses))", valueColor: Color(Constants.Colors.successGreen))
                    }
                    if viewModel.directBusinessExpenses > 0 {
                        TaxLineItem(label: "Business Expenses", value: "−\(fmt(viewModel.directBusinessExpenses))", valueColor: Color(Constants.Colors.successGreen))
                    }
                    if viewModel.totalMiscExpenses > 0 {
                        TaxLineItem(label: "Other Expenses", value: "−\(fmt(viewModel.totalMiscExpenses))", valueColor: Color(Constants.Colors.successGreen))
                    }
                    TaxLineItem(label: "Total Projected Deductions", value: "−\(fmt(viewModel.totalDeductions))", valueColor: Color(Constants.Colors.successGreen), isBold: true)

                    // Show Details toggle
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            showDetails.toggle()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(showDetails ? "Hide Details" : "Show Details")
                                .font(.caption)
                                .fontWeight(.medium)
                            Image(systemName: showDetails ? "chevron.up" : "chevron.down")
                                .font(.caption2)
                        }
                        .foregroundColor(Color(Constants.Colors.mintTeal))
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 10)
                    }

                    if showDetails {
                        VStack(alignment: .leading, spacing: 0) {
                            Divider().padding(.vertical, 6)

                            Text("How We Calculated This")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)
                                .padding(.bottom, 6)

                            TaxLineItem(label: "Gross Income", value: fmt(viewModel.grossIncome))
                            TaxLineItem(label: "SE Tax (15.3% of 92.35%)", value: fmt(viewModel.seTax))
                            TaxLineItem(label: "½ SE Tax Deduction", value: "−\(fmt(viewModel.halfSETaxDeduction))", valueColor: Color(Constants.Colors.successGreen))
                            TaxLineItem(label: "Adjusted Gross Income", value: fmt(viewModel.adjustedGrossIncome))
                            TaxLineItem(label: "Standard Deduction (\(viewModel.filingStatus.replacingOccurrences(of: "_", with: " ").capitalized))", value: "−\(fmt(viewModel.standardDeduction))", valueColor: Color(Constants.Colors.successGreen))
                            TaxLineItem(label: "Taxable Income", value: fmt(viewModel.taxableIncome))
                            TaxLineItem(label: "Est. Federal Income Tax", value: fmt(viewModel.estimatedIncomeTax))
                            TaxLineItem(label: "Self-Employment Tax", value: fmt(viewModel.seTax))

                            Divider().padding(.vertical, 4)

                            TaxLineItem(label: "Total Estimated Tax", value: fmt(viewModel.totalEstimatedTax), isBold: true)

                            HStack(spacing: 6) {
                                Image(systemName: "info.circle")
                                    .font(.caption2)
                                Text("Estimated from gross income only. Deductions are tracked but not applied — consult your CPA for accurate tax liability.")
                                    .font(.caption2)
                            }
                            .foregroundColor(.secondary)
                            .padding(.top, 8)
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .padding(16)
                .background(Color(.systemBackground))
                .cornerRadius(12)
                .shadow(color: .black.opacity(0.04), radius: 4, y: 2)

                // ─── QUARTERLY DEADLINES ───
                VStack(alignment: .leading, spacing: 8) {
                    Text("Quarterly Deadlines")
                        .font(.headline)

                    ForEach(viewModel.quarterlyDeadlines, id: \.quarter) { deadline in
                        HStack {
                            Circle()
                                .fill(deadline.isPast ? Color(.systemGray4) : (deadline.daysUntil <= 30 ? Color(Constants.Colors.errorRed) : Color(Constants.Colors.mintTeal)))
                                .frame(width: 8, height: 8)

                            Text(deadline.quarter)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(deadline.isPast ? .secondary : .primary)

                            Text(deadline.date)
                                .font(.subheadline)
                                .foregroundColor(.secondary)

                            Spacer()

                            if deadline.isPast {
                                Text("Past")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            } else {
                                Text("\(deadline.daysUntil) days")
                                    .font(.caption2)
                                    .fontWeight(.medium)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background((deadline.daysUntil <= 30 ? Color(Constants.Colors.errorRed) : Color(Constants.Colors.mintTeal)).opacity(0.15))
                                    .foregroundColor(deadline.daysUntil <= 30 ? Color(Constants.Colors.errorRed) : Color(Constants.Colors.mintTeal))
                                    .cornerRadius(6)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .padding(16)
                .background(Color(.systemBackground))
                .cornerRadius(12)
                .shadow(color: .black.opacity(0.04), radius: 4, y: 2)

                // ─── TAXES PAID ───
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Taxes Paid")
                            .font(.headline)
                        Spacer()
                        Button {
                            showAddPayment = true
                        } label: {
                            Label("Add", systemImage: "plus.circle.fill")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(Color(Constants.Colors.mintTeal))
                        }
                    }

                    if taxPayments.isEmpty {
                        Text("No payments recorded for \(String(selectedYear)).")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.vertical, 4)
                    } else {
                        let totalPaid = taxPayments.reduce(0.0) { $0 + $1.amount }

                        ForEach(taxPayments.sorted { $0.quarter < $1.quarter }) { payment in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(payment.quarter)
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                    Text(payment.datePaid, style: .date)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                Text(String(format: "$%.2f", payment.amount))
                                    .font(.subheadline)
                                    .fontWeight(.bold)
                                    .foregroundColor(Color(Constants.Colors.mintTeal))

                                Button {
                                    withAnimation {
                                        taxPayments.removeAll { $0.id == payment.id }
                                        saveTaxPayments()
                                    }
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.caption)
                                        .foregroundColor(Color(Constants.Colors.errorRed))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Delete \(payment.quarter) payment")
                            }
                            .padding(.vertical, 4)
                        }

                        Divider().padding(.vertical, 4)

                        HStack {
                            Text("Total Paid")
                                .font(.subheadline)
                                .fontWeight(.bold)
                            Spacer()
                            Text(String(format: "$%.2f", totalPaid))
                                .font(.subheadline)
                                .fontWeight(.bold)
                                .foregroundColor(Color(Constants.Colors.mintTeal))
                        }
                    }
                }
                .padding(16)
                .background(Color(.systemBackground))
                .cornerRadius(12)
                .shadow(color: .black.opacity(0.04), radius: 4, y: 2)

                // ─── WHAT'S NOT INCLUDED ───
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(Color(Constants.Colors.mintTeal))
                        Text("What's Not Included")
                            .font(.subheadline)
                            .fontWeight(.bold)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("• State and local taxes")
                        Text("• Tax credits (child, earned income, etc.)")
                        Text("• Itemized deductions")
                        Text("• Retirement contributions (IRA, SEP)")
                        Text("• Health insurance premium deduction")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)

                    Text("A CPA can factor these in for a complete picture of your tax situation.")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(Color(Constants.Colors.graphite))
                        .padding(.top, 4)
                }
                .padding(16)
                .background(Color(Constants.Colors.mintTeal).opacity(0.08))
                .cornerRadius(12)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .background(Color(Constants.Colors.background).ignoresSafeArea())
        .navigationTitle("Tax Center")
        .task {
            guard let userId = authService.currentSession?.user.id else { return }
            await viewModel.loadTaxData(userId: userId)
        }
        .refreshable {
            guard let userId = authService.currentSession?.user.id else { return }
            await viewModel.loadTaxData(userId: userId)
        }
        .onAppear { loadTaxPayments() }
        .onChange(of: selectedYear) { _, _ in loadTaxPayments() }
        .sheet(isPresented: $showAddPayment) {
            AddTaxPaymentSheet(selectedYear: selectedYear) { payment in
                taxPayments.append(payment)
                saveTaxPayments()
            }
        }
    }

    private func loadTaxPayments() {
        guard let data = UserDefaults.standard.data(forKey: "taxPayments_\(selectedYear)"),
              let decoded = try? JSONDecoder().decode([TaxPayment].self, from: data) else {
            taxPayments = []
            return
        }
        taxPayments = decoded
    }

    private func saveTaxPayments() {
        if let encoded = try? JSONEncoder().encode(taxPayments) {
            UserDefaults.standard.set(encoded, forKey: "taxPayments_\(selectedYear)")
        }
    }
}

struct AddTaxPaymentSheet: View {
    let selectedYear: Int
    let onSave: (TaxPayment) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var quarter = "Q1"
    @State private var amountText = ""
    @State private var datePaid = Date()

    private let quarters = ["Q1", "Q2", "Q3", "Q4"]

    var body: some View {
        NavigationStack {
            Form {
                Picker("Quarter", selection: $quarter) {
                    ForEach(quarters, id: \.self) { q in
                        Text(q).tag(q)
                    }
                }

                HStack {
                    Text("Amount")
                    Spacer()
                    TextField("$0.00", text: $amountText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 120)
                }

                DatePicker("Date Paid", selection: $datePaid, displayedComponents: .date)
            }
            .navigationTitle("Add Payment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let amount = Double(amountText), amount > 0 else { return }
                        let payment = TaxPayment(quarter: quarter, amount: amount, datePaid: datePaid)
                        onSave(payment)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(Double(amountText) == nil || (Double(amountText) ?? 0) <= 0)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.secondary)
                    }
                    .accessibilityLabel("Dismiss keyboard")
                    Spacer()
                }
            }
        }
        .presentationDetents([.medium])
    }
}

struct TaxLineItem: View {
    let label: String
    let value: String
    var valueColor: Color = .primary
    var isBold: Bool = false
    var isLarge: Bool = false

    var body: some View {
        HStack {
            Text(label)
                .font(isLarge ? .subheadline : .caption)
                .fontWeight(isBold ? .bold : .regular)
                .foregroundColor(isBold ? .primary : .secondary)
            Spacer()
            Text(value)
                .font(isLarge ? .title3 : .caption)
                .fontWeight(isBold ? .bold : .medium)
                .foregroundColor(valueColor)
        }
        .padding(.vertical, 2)
    }
}
