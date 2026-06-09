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
    @State private var extras: [EditableMealItem]
    @State private var selectedAgencyId: UUID?
    @State private var receiptNumber: String
    @State private var businessPurpose: String
    @State private var receiptFilenames: [String]
    @State private var showDeleteConfirmation = false

    init(meal: Meal, viewModel: MealViewModel) {
        self.meal = meal
        self.viewModel = viewModel

        _date = State(initialValue: meal.displayDate)

        // Spread the meal's line items into quick rows (first of each type) + extras.
        var b = "", l = "", d = ""
        var ex: [EditableMealItem] = []
        var seen: Set<MealItemType> = []
        for item in meal.items {
            let s = item.amount > 0 ? String(format: "%.2f", NSDecimalNumber(decimal: item.amount).doubleValue) : ""
            if seen.contains(item.type) {
                ex.append(EditableMealItem(id: item.id, type: item.type, amount: s))
            } else {
                seen.insert(item.type)
                switch item.type {
                case .breakfast: b = s
                case .lunch: l = s
                case .dinner: d = s
                }
            }
        }
        _breakfast = State(initialValue: b)
        _lunch = State(initialValue: l)
        _dinner = State(initialValue: d)
        _extras = State(initialValue: ex)

        _selectedAgencyId = State(initialValue: meal.agencyId)
        _receiptNumber = State(initialValue: meal.receiptNumber ?? "")
        _businessPurpose = State(initialValue: meal.businessPurpose ?? "")
        _receiptFilenames = State(initialValue: LocalStorageService.shared.receiptFilenames(for: meal.id))
    }

    private var dayTotal: Decimal {
        collectItems().reduce(0) { $0 + $1.amount }
    }

    var body: some View {
        Form {
            Section {
                DatePicker("Date", selection: $date, displayedComponents: .date)
            }

            Section(header: Text("Meals")) {
                mealRow("Breakfast", text: $breakfast)
                mealRow("Lunch", text: $lunch)
                mealRow("Dinner", text: $dinner)

                ForEach($extras) { $extra in
                    HStack {
                        Text(extra.type.label)
                        Spacer()
                        TextField("$0.00", text: $extra.amount)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Button(role: .destructive) {
                            extras.removeAll { $0.id == extra.id }
                        } label: {
                            Image(systemName: "trash")
                                .foregroundColor(Color(Constants.Colors.errorRed))
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Remove \(extra.type.label)")
                    }
                }

                Menu {
                    Button("Breakfast") { addExtra(.breakfast) }
                    Button("Lunch") { addExtra(.lunch) }
                    Button("Dinner") { addExtra(.dinner) }
                } label: {
                    Label("Add another meal", systemImage: "plus.circle.fill")
                        .font(.subheadline)
                        .foregroundColor(Color(Constants.Colors.mintTeal))
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
        .dismissKeyboardButton()
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

    private func mealRow(_ label: String, text: Binding<String>) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("$0.00", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
        }
    }

    private func addExtra(_ type: MealItemType) {
        extras.append(EditableMealItem(type: type, amount: ""))
    }

    private func collectItems() -> [MealItem] {
        var result: [MealItem] = []
        if let b = Decimal(string: breakfast), b > 0 { result.append(MealItem(type: .breakfast, amount: b)) }
        if let l = Decimal(string: lunch), l > 0 { result.append(MealItem(type: .lunch, amount: l)) }
        if let d = Decimal(string: dinner), d > 0 { result.append(MealItem(type: .dinner, amount: d)) }
        for extra in extras {
            if let a = Decimal(string: extra.amount), a > 0 {
                result.append(MealItem(id: extra.id, type: extra.type, amount: a))
            }
        }
        return result
    }

    private func updateMeal() {
        guard let userId = authService.currentSession?.user.id else { return }
        Task {
            let success = await viewModel.updateMeal(
                mealId: meal.id,
                userId: userId,
                date: date,
                items: collectItems(),
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
