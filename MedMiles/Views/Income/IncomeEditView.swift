import SwiftUI
import Auth

struct IncomeEditView: View {
    @EnvironmentObject var authService: AuthService
    @ObservedObject var viewModel: IncomeViewModel
    @Environment(\.dismiss) private var dismiss

    let income: Income

    @State private var contractVisitId: String
    @State private var dateOfService: Date
    @State private var selectedAgencyId: UUID?
    @State private var selectedVisitTypeId: UUID?
    @State private var destinationCity: String
    @State private var rateType: String
    @State private var advertisedRate: String
    @State private var grossPay: String
    @State private var taxSetAsideAmount: String
    @State private var status: String
    @State private var datePaid: Date
    @State private var notes: String
    @State private var showDeleteConfirmation = false

    init(income: Income, viewModel: IncomeViewModel) {
        self.income = income
        self.viewModel = viewModel

        _contractVisitId = State(initialValue: income.contractVisitId ?? "")
        _dateOfService = State(initialValue: income.displayDate)
        _selectedAgencyId = State(initialValue: income.agencyId)
        _selectedVisitTypeId = State(initialValue: income.visitTypeId)
        _destinationCity = State(initialValue: income.destinationCity ?? "")
        _rateType = State(initialValue: income.rateType ?? "")
        _advertisedRate = State(initialValue: income.advertisedRate ?? "")
        _grossPay = State(initialValue: "\(NSDecimalNumber(decimal: income.grossPay).doubleValue)")
        _taxSetAsideAmount = State(initialValue: income.taxSetAsideAmount.map { "\(NSDecimalNumber(decimal: $0).doubleValue)" } ?? "")
        _status = State(initialValue: income.status)
        _datePaid = State(initialValue: income.displayDatePaid ?? Date())
        _notes = State(initialValue: income.notes ?? "")
    }

    private var suggestedSetAside: String {
        guard let gross = Decimal(string: grossPay), gross > 0 else { return "$0.00" }
        let suggested = gross * Constants.defaultTaxSetAsidePct / 100
        return String(format: "$%.2f", NSDecimalNumber(decimal: suggested).doubleValue)
    }

    private var setAsidePercentage: String {
        guard let gross = Decimal(string: grossPay), gross > 0,
              let setAside = Decimal(string: taxSetAsideAmount), setAside > 0 else { return "0%" }
        let pct = (setAside / gross) * 100
        return String(format: "%.1f%%", NSDecimalNumber(decimal: pct).doubleValue)
    }

    private var netPayAmount: String {
        guard let gross = Decimal(string: grossPay), gross > 0 else { return "$0.00" }
        let setAside = Decimal(string: taxSetAsideAmount) ?? 0
        let net = gross - setAside
        return String(format: "$%.2f", NSDecimalNumber(decimal: net).doubleValue)
    }

    var body: some View {
        Form {
            Section {
                TextField("Contract / Visit ID (optional)", text: $contractVisitId)
                DatePicker("Date of Service", selection: $dateOfService, displayedComponents: .date)
            }

            Section(header: Text("Source")) {
                AgencyPicker(
                    selectedAgencyId: $selectedAgencyId,
                    agencies: viewModel.agencies,
                    onAddNew: { name in
                        guard let userId = authService.currentSession?.user.id else { return }
                        Task {
                            if let newId = await viewModel.addAgency(userId: userId, name: name) {
                                selectedAgencyId = newId
                            }
                        }
                    },
                    onDelete: { agencyId in
                        guard let userId = authService.currentSession?.user.id else { return }
                        Task { await viewModel.deleteAgency(agencyId: agencyId, userId: userId) }
                    }
                )

                VisitTypePicker(
                    selectedVisitTypeId: $selectedVisitTypeId,
                    visitTypes: viewModel.visitTypes,
                    onAddNew: { name in
                        guard let userId = authService.currentSession?.user.id else { return }
                        Task {
                            if let newId = await viewModel.addVisitType(userId: userId, name: name) {
                                selectedVisitTypeId = newId
                            }
                        }
                    },
                    onDelete: { visitTypeId in
                        guard let userId = authService.currentSession?.user.id else { return }
                        Task { await viewModel.deleteVisitType(visitTypeId: visitTypeId, userId: userId) }
                    }
                )

            }

            Section(header: Text("Pay Details")) {
                Picker("Rate Type", selection: $rateType) {
                    Text("Select").tag("")
                    Text("Flat Rate").tag("flat_rate")
                    Text("Hourly").tag("hourly")
                }

                HStack {
                    Text(rateType == "hourly" ? "Rate ($/hr)" : "Rate ($)")
                    Spacer()
                    TextField(rateType == "hourly" ? "$/hr" : "$0.00", text: $advertisedRate)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }

                HStack {
                    Text("Total Gross Pay")
                        .fontWeight(.semibold)
                    Spacer()
                    TextField("$0.00", text: $grossPay)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .font(.title3)
                        .fontWeight(.bold)
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(Color(Constants.Colors.errorRed))
                        Text("Tax Set-Aside")
                            .font(.headline)
                            .foregroundColor(Color(Constants.Colors.errorRed))
                    }

                    HStack {
                        Text("Suggested (30%)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(suggestedSetAside)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Amount set aside")
                            .font(.subheadline)
                        Spacer()
                        TextField("$0.00", text: $taxSetAsideAmount)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                    }

                    HStack {
                        Text("Your set-aside rate")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(setAsidePercentage)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(Color(Constants.Colors.mintTeal))
                    }

                    Text("30% is a general guideline. Consult your CPA for a rate tailored to your tax situation.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)

                    Divider()

                    HStack {
                        Text("Net Pay")
                            .font(.headline)
                        Spacer()
                        Text(netPayAmount)
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(Color(Constants.Colors.successGreen))
                    }
                    .padding(.top, 4)
                }
                .padding(.vertical, 4)
            }

            Section(header: Text("Payment Status")) {
                Picker("Status", selection: $status) {
                    Text("Pending").tag("pending")
                    Text("Completed").tag("completed")
                }
                .pickerStyle(.segmented)

                if status == "completed" {
                    DatePicker("Date Paid", selection: $datePaid, displayedComponents: .date)
                }
            }

            Section {
                TextField("Notes (optional)", text: $notes)
            }

            if let error = viewModel.errorMessage {
                Section {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(Color(Constants.Colors.errorRed))
                }
            }

            Section {
                Button {
                    updateIncome()
                } label: {
                    HStack {
                        Spacer()
                        if viewModel.isSaving {
                            ProgressView().tint(.white)
                        }
                        Text("Save Changes")
                            .fontWeight(.semibold)
                        Spacer()
                    }
                    .padding(.vertical, 6)
                }
                .listRowBackground(Color(Constants.Colors.mintTeal))
                .foregroundColor(.white)
                .disabled(viewModel.isSaving)
            }

            Section {
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    HStack {
                        Spacer()
                        Text("Delete Income Entry")
                        Spacer()
                    }
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Edit Income")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Delete this income entry?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                deleteIncome()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone.")
        }
    }

    private func updateIncome() {
        guard let userId = authService.currentSession?.user.id else { return }
        Task {
            let success = await viewModel.updateIncome(
                incomeId: income.id,
                userId: userId,
                contractVisitId: contractVisitId,
                dateOfService: dateOfService,
                agencyId: selectedAgencyId,
                visitTypeId: selectedVisitTypeId,
                destinationCity: destinationCity,
                rateType: rateType,
                advertisedRate: advertisedRate,
                grossPay: grossPay,
                taxSetAsideAmount: taxSetAsideAmount,
                status: status,
                datePaid: status == "completed" ? datePaid : nil,
                notes: notes
            )
            if success {
                dismiss()
            }
        }
    }

    private func deleteIncome() {
        guard let userId = authService.currentSession?.user.id else { return }
        Task {
            let success = await viewModel.deleteIncome(incomeId: income.id, userId: userId)
            if success {
                dismiss()
            }
        }
    }
}
