import SwiftUI
import Auth

struct IndividualExpenseEditView: View {
    @EnvironmentObject var authService: AuthService
    @ObservedObject var viewModel: IndividualExpenseViewModel
    @Environment(\.dismiss) private var dismiss

    let expense: MiscExpense

    @State private var date: Date
    @State private var item: String
    @State private var purpose: String
    @State private var category: String
    @State private var selectedAgencyId: UUID?
    @State private var amount: String
    @State private var receiptFilenames: [String]
    @State private var showDeleteConfirmation = false
    @State private var showManageCategories = false

    init(expense: MiscExpense, viewModel: IndividualExpenseViewModel) {
        self.expense = expense
        self.viewModel = viewModel

        _date = State(initialValue: expense.displayDate)

        // Split description back into item + purpose if it contains " — "
        let desc = expense.description ?? ""
        if desc.contains(" — ") {
            let parts = desc.components(separatedBy: " — ")
            _item = State(initialValue: parts.first ?? desc)
            _purpose = State(initialValue: parts.dropFirst().joined(separator: " — "))
        } else {
            _item = State(initialValue: desc)
            _purpose = State(initialValue: "")
        }

        _category = State(initialValue: expense.category)
        _selectedAgencyId = State(initialValue: expense.agencyId)
        _amount = State(initialValue: String(format: "%.2f", NSDecimalNumber(decimal: expense.amount).doubleValue))
        _receiptFilenames = State(initialValue: LocalStorageService.shared.receiptFilenames(for: expense.id))
    }

    var body: some View {
        Form {
            Section {
                DatePicker("Date", selection: $date, displayedComponents: .date)
            }

            Section(header: Text("Details")) {
                TextField("Item", text: $item)

                HStack {
                    Picker("Category", selection: $category) {
                        ForEach(ExpenseCategoryManager.shared.categoriesIncluding(value: category), id: \.value) { cat in
                            Text(cat.label).tag(cat.value)
                        }
                    }
                }

                Button {
                    showManageCategories = true
                } label: {
                    Label("Manage Categories", systemImage: "folder.badge.gearshape")
                        .font(.caption)
                        .foregroundColor(Color(Constants.Colors.mintTeal))
                }

                TextField("Description (optional)", text: $purpose)
            }

            Section(header: Text("Company")) {
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
            }

            Section(header: Text("Cost")) {
                HStack {
                    Text("Amount")
                        .fontWeight(.semibold)
                    Spacer()
                    TextField("$0.00", text: $amount)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .font(.title3)
                        .fontWeight(.bold)
                }
            }

            Section(header: Text("Receipt")) {
                ReceiptCaptureButton(
                    receiptFilenames: receiptFilenames,
                    onCapture: { image in
                        if let filename = LocalStorageService.shared.saveReceipt(image: image, for: expense.id) {
                            receiptFilenames.append(filename)
                        }
                    },
                    onDelete: { filename in
                        LocalStorageService.shared.deleteReceipt(filename: filename)
                        receiptFilenames.removeAll { $0 == filename }
                    },
                    onFileImport: { url in
                        guard url.startAccessingSecurityScopedResource() else { return }
                        defer { url.stopAccessingSecurityScopedResource() }
                        if let filename = LocalStorageService.shared.saveFileFromURL(url, for: expense.id) {
                            receiptFilenames.append(filename)
                        }
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
                    updateExpense()
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
                        Text("Delete Expense")
                        Spacer()
                    }
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .dismissKeyboardButton()
        .navigationTitle("Edit Expense")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showManageCategories) {
            ManageCategoriesSheet()
        }
        .confirmationDialog("Delete this expense?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                deleteExpense()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone.")
        }
    }

    private func updateExpense() {
        guard let userId = authService.currentSession?.user.id else { return }
        let hasReceipt = !receiptFilenames.isEmpty
        Task {
            let success = await viewModel.updateExpense(
                expenseId: expense.id,
                userId: userId,
                date: date,
                item: item,
                description: purpose,
                category: category,
                agencyId: selectedAgencyId,
                amount: amount,
                hasReceipt: hasReceipt
            )
            if success {
                dismiss()
            }
        }
    }

    private func deleteExpense() {
        guard let userId = authService.currentSession?.user.id else { return }
        Task {
            let success = await viewModel.deleteExpense(expenseId: expense.id, userId: userId)
            if success {
                dismiss()
            }
        }
    }
}
