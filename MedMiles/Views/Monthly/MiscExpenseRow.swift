import SwiftUI

struct MiscExpenseRow: View {
    let expense: MiscExpense
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(MiscExpense.categoryLabel(for: expense.category))
                        .font(.subheadline)
                        .fontWeight(.medium)
                    if let desc = expense.description, !desc.isEmpty {
                        Text(desc)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                Text("$\(NSDecimalNumber(decimal: expense.amount).doubleValue, specifier: "%.2f")")
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }

            HStack(spacing: 8) {
                Text(expense.displayDate, style: .date)
                    .font(.caption2)
                    .foregroundColor(.secondary)

                if expense.hasReceipt {
                    Label("Receipt", systemImage: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundColor(Color(Constants.Colors.successGreen))
                } else if expense.amount >= 75 {
                    Label("No receipt - over $75", systemImage: "xmark.circle.fill")
                        .font(.caption2)
                        .foregroundColor(Color(Constants.Colors.errorRed))
                }

                Spacer()

                Button("Edit", action: onEdit)
                    .font(.caption2)
                    .foregroundColor(Color(Constants.Colors.mintTeal))
                    .buttonStyle(.borderless)

                Button("Delete", action: onDelete)
                    .font(.caption2)
                    .foregroundColor(Color(Constants.Colors.errorRed))
                    .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 4)
    }
}

struct AddMiscExpenseSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onSave: (Date, String, String, String) -> Void

    @State private var date = Date()
    @State private var category = ExpenseCategoryManager.shared.defaultCategoryValue(preferred: "clinical_supplies")
    @State private var description = ""
    @State private var amount = ""
    @State private var showManageCategories = false

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Date", selection: $date, displayedComponents: .date)

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

                TextField("Description", text: $description)

                HStack {
                    Text("Amount")
                    Spacer()
                    TextField("$0.00", text: $amount)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }

                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(Color(Constants.Colors.mintTeal))
                    Text("Save first, then tap Edit to attach a receipt.")
                        .font(.caption)
                        .foregroundColor(Color(Constants.Colors.mintTeal))
                }
            }
            .navigationTitle("Add Expense")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(date, category, description, amount)
                        dismiss()
                    }
                    .disabled(amount.isEmpty)
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
                }
            }
            .sheet(isPresented: $showManageCategories) {
                ManageCategoriesSheet()
            }
        }
    }
}

struct EditMiscExpenseSheet: View {
    @Environment(\.dismiss) private var dismiss
    let expense: MiscExpense
    let onSave: (Date, String, String, String) -> Void

    @State private var date: Date
    @State private var category: String
    @State private var description: String
    @State private var amount: String
    @State private var showManageCategories = false

    init(expense: MiscExpense, onSave: @escaping (Date, String, String, String) -> Void) {
        self.expense = expense
        self.onSave = onSave
        _date = State(initialValue: expense.displayDate)
        _category = State(initialValue: expense.category)
        _description = State(initialValue: expense.description ?? "")
        _amount = State(initialValue: String(format: "%.2f", NSDecimalNumber(decimal: expense.amount).doubleValue))
    }

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Date", selection: $date, displayedComponents: .date)

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

                TextField("Description", text: $description)

                HStack {
                    Text("Amount")
                    Spacer()
                    TextField("$0.00", text: $amount)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }

                // Receipt section
                Section(header: Text("Receipt")) {
                    ReceiptCaptureButton(
                        receiptFilenames: LocalStorageService.shared.receiptFilenames(for: expense.id),
                        onCapture: { image in
                            _ = LocalStorageService.shared.saveReceipt(image: image, for: expense.id)
                        },
                        onDelete: { filename in
                            LocalStorageService.shared.deleteReceipt(filename: filename)
                        }
                    )
                }
            }
            .navigationTitle("Edit Expense")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(date, category, description, amount)
                        dismiss()
                    }
                    .disabled(amount.isEmpty)
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
                }
            }
            .sheet(isPresented: $showManageCategories) {
                ManageCategoriesSheet()
            }
        }
    }
}

// MARK: - Manage Categories Sheet

struct ManageCategoriesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var newCategoryName = ""
    @State private var refreshKey = UUID()

    private var manager: ExpenseCategoryManager { .shared }

    var body: some View {
        NavigationStack {
            List {
                Section(header: Text("Add New Category")) {
                    HStack {
                        TextField("Category name", text: $newCategoryName)
                            .font(.subheadline)
                        Button {
                            let trimmed = newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmed.isEmpty else { return }
                            manager.addCategory(label: trimmed)
                            newCategoryName = ""
                            refreshKey = UUID()
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                                .foregroundColor(Color(Constants.Colors.mintTeal))
                        }
                        .disabled(newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }

                Section(header: Text("Built-in Categories"), footer: Text("Swipe left to remove any category you don't use.")) {
                    let builtIns = manager.visibleBuiltInCategories
                    if builtIns.isEmpty {
                        Text("All default categories removed")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(builtIns, id: \.value) { cat in
                            Text(cat.label)
                                .font(.subheadline)
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                manager.removeCategory(value: builtIns[index].value)
                            }
                            refreshKey = UUID()
                        }
                    }

                    if manager.hasHiddenBuiltIns {
                        Button {
                            manager.restoreDefaultCategories()
                            refreshKey = UUID()
                        } label: {
                            Label("Restore default categories", systemImage: "arrow.uturn.backward")
                                .font(.caption)
                                .foregroundColor(Color(Constants.Colors.mintTeal))
                        }
                    }
                }

                Section(header: Text("Custom Categories")) {
                    let custom = manager.customCategories
                    if custom.isEmpty {
                        Text("No custom categories yet")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(custom, id: \.value) { cat in
                            Text(cat.label)
                                .font(.subheadline)
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                manager.deleteCategory(value: custom[index].value)
                            }
                            refreshKey = UUID()
                        }
                    }
                }
            }
            .id(refreshKey)
            .navigationTitle("Manage Categories")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }
}
