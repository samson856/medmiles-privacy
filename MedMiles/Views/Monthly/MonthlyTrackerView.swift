import SwiftUI
import Auth

struct MonthlyTrackerView: View {
    @EnvironmentObject var authService: AuthService
    @StateObject private var viewModel = MonthlyExpenseViewModel()

    @State private var showAddMisc = false
    @State private var editingMisc: MiscExpense?
    @State private var deletingMisc: MiscExpense?
    @State private var showDeleteConfirmation = false
    @State private var showSavedConfirmation = false
    @State private var showClearConfirmation = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Month selector
                MonthSelectorRibbon(
                    selectedMonth: $viewModel.selectedMonth,
                    hasDataForMonth: { viewModel.hasData(for: $0) }
                )

                // Info bar
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.caption2)
                    Text("Keep bank statements as proof of recurring payments")
                        .font(.caption2)
                }
                .foregroundColor(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)

                // Column headers
                HStack {
                    Text("Item")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("Amount")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .frame(width: 80, alignment: .trailing)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
                .background(Color(.systemGray6))

                Form {
                    // Structured sections
                    ForEach(MonthlyExpense.fieldKeys, id: \.section) { section in
                        Section(header: Text(section.section)) {
                            ForEach(section.items, id: \.key) { item in
                                LineItemRow(
                                    label: item.label,
                                    key: item.key,
                                    value: binding(for: item.key),
                                    isRecurring: recurringBinding(for: item.key)
                                )
                            }
                        }
                    }

                    // Misc expenses section
                    Section(header: Text("Other Expenses")) {
                        ForEach(viewModel.miscExpenses) { expense in
                            MiscExpenseRow(
                                expense: expense,
                                onEdit: { editingMisc = expense },
                                onDelete: {
                                    deletingMisc = expense
                                    showDeleteConfirmation = true
                                }
                            )
                        }

                        Button {
                            showAddMisc = true
                        } label: {
                            Label("Add expense", systemImage: "plus.circle")
                                .font(.subheadline)
                                .foregroundColor(Color(Constants.Colors.mintTeal))
                        }
                    }

                    // Error message
                    if let error = viewModel.errorMessage {
                        Section {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(Color(Constants.Colors.errorRed))
                        }
                    }

                    // Month total
                    Section {
                        HStack {
                            Text("\(MonthlyExpenseViewModel.monthNames[viewModel.selectedMonth - 1]) Total")
                                .font(.headline)
                            Spacer()
                            Text("$\(NSDecimalNumber(decimal: viewModel.monthTotal).doubleValue, specifier: "%.2f")")
                                .font(.headline)
                                .foregroundColor(Color(Constants.Colors.mintTeal))
                        }
                        .padding(.vertical, 4)
                    }

                    // Save button
                    Section {
                        Button {
                            saveMonth()
                        } label: {
                            HStack {
                                Spacer()
                                if viewModel.isSaving {
                                    ProgressView().tint(.white)
                                }
                                Text("Save \(MonthlyExpenseViewModel.monthNames[viewModel.selectedMonth - 1])")
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
                        Text("Recurring items auto-fill to remaining months")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .listRowBackground(Color.clear)
                    }
                }
                .scrollDismissesKeyboard(.interactively)
                .toolbar {
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
            }
            .background(Color(Constants.Colors.background).ignoresSafeArea())
            .navigationTitle("Monthly Expenses")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showClearConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                            .foregroundColor(Color(Constants.Colors.errorRed))
                    }
                    .accessibilityLabel("Clear month data")
                }
            }
            .task {
                await loadData()
            }
            .onChange(of: viewModel.selectedMonth) { _, _ in
                Task { await loadData() }
            }
            .sheet(isPresented: $showAddMisc) {
                AddMiscExpenseSheet { date, category, description, amount in
                    guard let userId = authService.currentSession?.user.id else { return }
                    Task {
                        await viewModel.addMiscExpense(userId: userId, date: date, category: category,
                                                        description: description, amount: amount)
                    }
                }
            }
            .sheet(item: $editingMisc) { expense in
                EditMiscExpenseSheet(expense: expense) { date, category, description, amount in
                    guard let userId = authService.currentSession?.user.id else { return }
                    Task {
                        let hasReceipt = !LocalStorageService.shared.receiptFilenames(for: expense.id).isEmpty
                        _ = await viewModel.updateMiscExpense(expenseId: expense.id, userId: userId,
                                                           date: date, category: category,
                                                           description: description, amount: amount,
                                                           hasReceipt: hasReceipt)
                    }
                }
            }
            .confirmationDialog("Clear all data for this month?", isPresented: $showClearConfirmation, titleVisibility: .visible) {
                Button("Clear Month", role: .destructive) {
                    clearMonth()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will reset all line items to $0 for \(MonthlyExpenseViewModel.monthNames[viewModel.selectedMonth - 1]). Other expenses won't be affected.")
            }
            .confirmationDialog("Delete this expense?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    guard let expense = deletingMisc,
                          let userId = authService.currentSession?.user.id else { return }
                    Task {
                        _ = await viewModel.deleteMiscExpense(expenseId: expense.id, userId: userId)
                        for filename in LocalStorageService.shared.receiptFilenames(for: expense.id) {
                            LocalStorageService.shared.deleteReceipt(filename: filename)
                        }
                    }
                    deletingMisc = nil
                }
                Button("Cancel", role: .cancel) { deletingMisc = nil }
            }
            .overlay {
                if showSavedConfirmation {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.largeTitle)
                            .foregroundColor(Color(Constants.Colors.successGreen))
                        Text("Month Saved!")
                            .font(.headline)
                    }
                    .padding(32)
                    .background(.ultraThinMaterial)
                    .cornerRadius(16)
                }
            }
        }
    }

    private func loadData() async {
        guard let userId = authService.currentSession?.user.id else { return }
        await viewModel.loadMonth(userId: userId)
    }

    private func clearMonth() {
        for key in viewModel.fieldValues.keys {
            viewModel.fieldValues[key] = ""
        }
        for key in viewModel.recurringFlags.keys {
            viewModel.recurringFlags[key] = false
        }
        saveMonth()
    }

    private func saveMonth() {
        guard let userId = authService.currentSession?.user.id else { return }
        Task {
            let success = await viewModel.saveMonth(userId: userId)
            if success {
                showSavedConfirmation = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    showSavedConfirmation = false
                }
            }
        }
    }

    // Helper to create bindings for field values
    private func binding(for key: String) -> Binding<String> {
        Binding(
            get: { viewModel.fieldValues[key] ?? "" },
            set: { viewModel.fieldValues[key] = $0 }
        )
    }

    private func recurringBinding(for key: String) -> Binding<Bool> {
        Binding(
            get: { viewModel.recurringFlags[key] ?? false },
            set: { viewModel.recurringFlags[key] = $0 }
        )
    }
}
