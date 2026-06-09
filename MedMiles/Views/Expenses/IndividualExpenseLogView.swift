import SwiftUI
import Auth

struct IndividualExpenseLogView: View {
    @EnvironmentObject var authService: AuthService
    @ObservedObject var viewModel: IndividualExpenseViewModel

    // Pre-fill support
    let prefillData: ScanPrefillData?
    let onSaveComplete: ((UUID) -> Void)?

    @State private var date: Date
    @State private var item: String
    @State private var purpose: String
    @State private var category: String
    @State private var selectedAgencyId: UUID?
    @State private var amount: String
    @State private var receiptFilenames: [String]
    @State private var showSavedConfirmation = false
    @State private var showUpgradePrompt = false
    @State private var showUpgradeSheet = false

    private var currentMonthExpenseCount: Int {
        let month = Calendar.current.component(.month, from: Date())
        return viewModel.expenses.filter { $0.month == month }.count
    }

    init(viewModel: IndividualExpenseViewModel,
         prefillData: ScanPrefillData? = nil,
         onSaveComplete: ((UUID) -> Void)? = nil) {
        self.viewModel = viewModel
        self.prefillData = prefillData
        self.onSaveComplete = onSaveComplete

        _date = State(initialValue: prefillData?.date ?? Date())
        _item = State(initialValue: prefillData?.merchantName ?? "")
        _purpose = State(initialValue: "")
        _category = State(initialValue: "other")
        _selectedAgencyId = State(initialValue: nil)
        _amount = State(initialValue: prefillData?.amount ?? "")

        // Pre-save the scanned receipt image
        if let image = prefillData?.capturedImage {
            var filenames: [String] = []
            let tempId = UUID()
            if let filename = LocalStorageService.shared.saveReceipt(image: image, for: tempId) {
                filenames.append(filename)
            }
            _receiptFilenames = State(initialValue: filenames)
        } else {
            _receiptFilenames = State(initialValue: [])
        }
    }

    var body: some View {
        Form {
            Section {
                DatePicker("Date", selection: $date, displayedComponents: .date)
            }

            Section(header: Text("Details")) {
                TextField("Item", text: $item)

                TextField("Category / description", text: $purpose)
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
                        let tempId = UUID()
                        if let filename = LocalStorageService.shared.saveReceipt(image: image, for: tempId) {
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
                        let tempId = UUID()
                        if let filename = LocalStorageService.shared.saveFileFromURL(url, for: tempId) {
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
                    saveExpense()
                } label: {
                    HStack {
                        Spacer()
                        if viewModel.isSaving {
                            ProgressView().tint(.white)
                        }
                        Text("Save Expense")
                            .fontWeight(.semibold)
                        Spacer()
                    }
                    .padding(.vertical, 6)
                }
                .listRowBackground(Color(Constants.Colors.mintTeal))
                .foregroundColor(.white)
                .disabled(viewModel.isSaving || item.isEmpty)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            }
        }
        .alert("Expense Limit Reached", isPresented: $showUpgradePrompt) {
            Button("Upgrade to Pro") { showUpgradeSheet = true }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Free accounts can log up to \(StoreKitService.freeMiscExpensesPerMonth) individual expenses per month. Upgrade to Pro for unlimited expenses.")
        }
        .sheet(isPresented: $showUpgradeSheet) {
            NavigationStack {
                SubscriptionView()
            }
        }
        .overlay {
            if showSavedConfirmation {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.largeTitle)
                        .foregroundColor(Color(Constants.Colors.successGreen))
                    Text("Expense Saved!")
                        .font(.headline)
                }
                .padding(32)
                .background(.ultraThinMaterial)
                .cornerRadius(16)
            }
        }
    }

    private func saveExpense() {
        // Check subscription limit
        if !StoreKitService.shared.canLogMiscExpense(currentMonthCount: currentMonthExpenseCount) {
            showUpgradePrompt = true
            return
        }

        guard let userId = authService.currentSession?.user.id else { return }
        Task {
            let expId = await viewModel.saveExpense(
                userId: userId,
                date: date,
                item: item,
                description: purpose,
                category: category,
                agencyId: selectedAgencyId,
                amount: amount
            )
            if let expId = expId {
                // Re-save receipt files under the expense's actual ID
                if !receiptFilenames.isEmpty {
                    for oldFilename in receiptFilenames {
                        if let image = LocalStorageService.shared.loadReceipt(filename: oldFilename) {
                            _ = LocalStorageService.shared.saveReceipt(image: image, for: expId)
                            LocalStorageService.shared.deleteReceipt(filename: oldFilename)
                        } else {
                            let url = LocalStorageService.shared.receiptURL(filename: oldFilename)
                            if let data = try? Data(contentsOf: url) {
                                let ext = (oldFilename as NSString).pathExtension
                                _ = LocalStorageService.shared.saveFile(data: data, for: expId, extension: ext)
                                LocalStorageService.shared.deleteReceipt(filename: oldFilename)
                            }
                        }
                    }
                    await viewModel.markHasReceipt(expenseId: expId, userId: userId)
                }

                onSaveComplete?(expId)
                showSavedConfirmation = true
                resetForm()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    showSavedConfirmation = false
                }
            }
        }
    }

    private func resetForm() {
        date = Date()
        item = ""
        purpose = ""
        category = "other"
        selectedAgencyId = nil
        amount = ""
        receiptFilenames = []
    }
}
