import SwiftUI
import Auth

struct MealEditView: View {
    @EnvironmentObject var authService: AuthService
    @ObservedObject var viewModel: MealViewModel
    @Environment(\.dismiss) private var dismiss

    let meal: Meal

    @State private var date: Date
    @State private var breakfast: String
    @State private var lunch: String
    @State private var dinner: String
    @State private var selectedAgencyId: UUID?
    @State private var receiptNumber: String
    @State private var businessPurpose: String
    @State private var receiptFilenames: [String]
    @State private var showDeleteConfirmation = false

    init(meal: Meal, viewModel: MealViewModel) {
        self.meal = meal
        self.viewModel = viewModel

        _date = State(initialValue: meal.displayDate)
        _breakfast = State(initialValue: meal.breakfast > 0 ? "\(NSDecimalNumber(decimal: meal.breakfast).doubleValue)" : "")
        _lunch = State(initialValue: meal.lunch > 0 ? "\(NSDecimalNumber(decimal: meal.lunch).doubleValue)" : "")
        _dinner = State(initialValue: meal.dinner > 0 ? "\(NSDecimalNumber(decimal: meal.dinner).doubleValue)" : "")
        _selectedAgencyId = State(initialValue: meal.agencyId)
        _receiptNumber = State(initialValue: meal.receiptNumber ?? "")
        _businessPurpose = State(initialValue: meal.businessPurpose ?? "")
        _receiptFilenames = State(initialValue: LocalStorageService.shared.receiptFilenames(for: meal.id))
    }

    private var dayTotal: Decimal {
        let b = Decimal(string: breakfast) ?? 0
        let l = Decimal(string: lunch) ?? 0
        let d = Decimal(string: dinner) ?? 0
        return b + l + d
    }

    var body: some View {
        Form {
            Section {
                DatePicker("Date", selection: $date, displayedComponents: .date)
            }

            Section(header: Text("Meals")) {
                HStack {
                    Text("Breakfast")
                    Spacer()
                    TextField("$0.00", text: $breakfast)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                }

                HStack {
                    Text("Lunch")
                    Spacer()
                    TextField("$0.00", text: $lunch)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                }

                HStack {
                    Text("Dinner")
                    Spacer()
                    TextField("$0.00", text: $dinner)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                }

                HStack {
                    Text("Day Total")
                        .fontWeight(.bold)
                    Spacer()
                    Text("$\(NSDecimalNumber(decimal: dayTotal).doubleValue, specifier: "%.2f")")
                        .fontWeight(.bold)
                        .foregroundColor(Color(Constants.Colors.mintTeal))
                }
            }

            Section(header: Text("Details")) {
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

                TextField("Receipt name (optional)", text: $receiptNumber)
            }

            Section(header: Text("Receipt")) {
                ReceiptCaptureButton(
                    receiptFilenames: receiptFilenames,
                    onCapture: { image in
                        if let filename = LocalStorageService.shared.saveReceipt(image: image, for: meal.id) {
                            receiptFilenames.append(filename)
                        }
                    },
                    onDelete: { filename in
                        LocalStorageService.shared.deleteReceipt(filename: filename)
                        receiptFilenames.removeAll { $0 == filename }
                    }
                )
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
                    updateMeal()
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
                        Text("Delete Meal Entry")
                        Spacer()
                    }
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Edit Meal")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Delete this meal entry?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                deleteMeal()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone.")
        }
    }

    private func updateMeal() {
        guard let userId = authService.currentSession?.user.id else { return }
        Task {
            let success = await viewModel.updateMeal(
                mealId: meal.id,
                userId: userId,
                date: date,
                breakfast: breakfast,
                lunch: lunch,
                dinner: dinner,
                agencyId: selectedAgencyId,
                receiptNumber: receiptNumber,
                notes: businessPurpose
            )
            if success {
                dismiss()
            }
        }
    }

    private func deleteMeal() {
        guard let userId = authService.currentSession?.user.id else { return }
        Task {
            let success = await viewModel.deleteMeal(mealId: meal.id, userId: userId)
            if success {
                dismiss()
            }
        }
    }
}
