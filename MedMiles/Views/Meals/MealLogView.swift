import SwiftUI
import Auth

struct MealLogView: View {
    @EnvironmentObject var authService: AuthService
    @ObservedObject var viewModel: MealViewModel

    // Pre-fill support
    let prefillData: ScanPrefillData?
    let onSaveComplete: ((UUID) -> Void)?

    @State private var date: Date
    @State private var breakfast: String
    @State private var lunch: String
    @State private var dinner: String
    @State private var selectedAgencyId: UUID?
    @State private var receiptNumber: String
    @State private var businessPurpose: String
    @State private var receiptFilenames: [String]
    @State private var pendingImages: [UIImage]
    @State private var showSavedConfirmation = false

    // Smart scan state (active when in scanner mode)
    @State private var pendingScanImage: UIImage?
    @State private var pendingScanResult: ScannedReceipt?
    @State private var showMealSlotPicker = false
    @State private var isScanning = false
    @State private var autoSaveMessage: String?

    init(viewModel: MealViewModel,
         prefillData: ScanPrefillData? = nil,
         onSaveComplete: ((UUID) -> Void)? = nil) {
        self.viewModel = viewModel
        self.prefillData = prefillData
        self.onSaveComplete = onSaveComplete

        _date = State(initialValue: prefillData?.date ?? Date())
        _selectedAgencyId = State(initialValue: nil)
        _receiptNumber = State(initialValue: "")
        _businessPurpose = State(initialValue: prefillData?.merchantName ?? "")

        // Put amount into the correct meal slot
        let amt = prefillData?.amount ?? ""
        let slot = prefillData?.mealSlot ?? .lunch
        _breakfast = State(initialValue: slot == .breakfast ? amt : "")
        _lunch = State(initialValue: slot == .lunch ? amt : "")
        _dinner = State(initialValue: slot == .dinner ? amt : "")

        // Pre-save the scanned receipt image
        if let image = prefillData?.capturedImage {
            var filenames: [String] = []
            let tempId = UUID()
            if let filename = LocalStorageService.shared.saveReceipt(image: image, for: tempId) {
                filenames.append(filename)
            }
            _receiptFilenames = State(initialValue: filenames)
            _pendingImages = State(initialValue: [image])
        } else {
            _receiptFilenames = State(initialValue: [])
            _pendingImages = State(initialValue: [])
        }
    }

    private var isInScannerMode: Bool { prefillData != nil }

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
                        if isInScannerMode {
                            // Smart scan: OCR the new receipt, then ask which slot
                            scanAndAddReceipt(image)
                        } else {
                            // Normal mode: just attach the image
                            pendingImages.append(image)
                            let tempId = UUID()
                            if let filename = LocalStorageService.shared.saveReceipt(image: image, for: tempId) {
                                receiptFilenames.append(filename)
                            }
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
                    saveMeal()
                } label: {
                    HStack {
                        Spacer()
                        if viewModel.isSaving {
                            ProgressView().tint(.white)
                        }
                        Text("Save Meal")
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
        .confirmationDialog("Which meal is this receipt for?", isPresented: $showMealSlotPicker) {
            Button("Breakfast") { handleSlotSelected(.breakfast) }
            Button("Lunch") { handleSlotSelected(.lunch) }
            Button("Dinner") { handleSlotSelected(.dinner) }
            Button("Cancel", role: .cancel) {
                // Still attach the image even if they cancel slot selection
                attachPendingImageOnly()
            }
        }
        .overlay {
            if isScanning {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.large)
                    Text("Scanning receipt...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(32)
                .background(.ultraThinMaterial)
                .cornerRadius(16)
            }
        }
        .overlay {
            if showSavedConfirmation {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.largeTitle)
                        .foregroundColor(Color(Constants.Colors.successGreen))
                    Text("Meal Saved!")
                        .font(.headline)
                }
                .padding(32)
                .background(.ultraThinMaterial)
                .cornerRadius(16)
            }
        }
        .overlay {
            if let message = autoSaveMessage {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.largeTitle)
                        .foregroundColor(Color(Constants.Colors.successGreen))
                    Text(message)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                }
                .padding(32)
                .background(.ultraThinMaterial)
                .cornerRadius(16)
            }
        }
    }

    // MARK: - Smart Scan

    private func scanAndAddReceipt(_ image: UIImage) {
        isScanning = true
        Task {
            do {
                let result = try await ReceiptScannerService.shared.scan(image: image)
                pendingScanResult = result
                pendingScanImage = image
            } catch {
                // OCR failed — still attach the image, just no amount extraction
                pendingScanResult = nil
                pendingScanImage = image
            }
            isScanning = false
            showMealSlotPicker = true
        }
    }

    private func handleSlotSelected(_ slot: ScanPrefillData.MealSlot) {
        guard let image = pendingScanImage else { return }
        let scannedDate = pendingScanResult?.date ?? date
        let scannedAmount = pendingScanResult?.totalAmount ?? ""

        let isSameDay = Calendar.current.isDate(scannedDate, inSameDayAs: date)

        if isSameDay {
            // Add amount to the selected slot on the current form
            addAmountToSlot(slot, amount: scannedAmount)

            // Attach the receipt image
            let tempId = UUID()
            if let filename = LocalStorageService.shared.saveReceipt(image: image, for: tempId) {
                receiptFilenames.append(filename)
            }
            pendingImages.append(image)
        } else {
            // Different day — auto-save a new meal entry
            autoSaveNewMeal(date: scannedDate, slot: slot, amount: scannedAmount, image: image)
        }

        pendingScanImage = nil
        pendingScanResult = nil
    }

    private func attachPendingImageOnly() {
        guard let image = pendingScanImage else { return }
        let tempId = UUID()
        if let filename = LocalStorageService.shared.saveReceipt(image: image, for: tempId) {
            receiptFilenames.append(filename)
        }
        pendingImages.append(image)
        pendingScanImage = nil
        pendingScanResult = nil
    }

    private func addAmountToSlot(_ slot: ScanPrefillData.MealSlot, amount: String) {
        guard !amount.isEmpty, let newVal = Decimal(string: amount) else { return }

        switch slot {
        case .breakfast:
            let existing = Decimal(string: breakfast) ?? 0
            breakfast = formatDecimal(existing + newVal)
        case .lunch:
            let existing = Decimal(string: lunch) ?? 0
            lunch = formatDecimal(existing + newVal)
        case .dinner:
            let existing = Decimal(string: dinner) ?? 0
            dinner = formatDecimal(existing + newVal)
        }
    }

    private func formatDecimal(_ value: Decimal) -> String {
        String(format: "%.2f", NSDecimalNumber(decimal: value).doubleValue)
    }

    private func autoSaveNewMeal(date saveDate: Date, slot: ScanPrefillData.MealSlot, amount: String, image: UIImage) {
        guard let userId = authService.currentSession?.user.id else { return }

        let b = slot == .breakfast ? amount : ""
        let l = slot == .lunch ? amount : ""
        let d = slot == .dinner ? amount : ""

        Task {
            let mealId = await viewModel.saveMeal(
                userId: userId,
                date: saveDate,
                breakfast: b,
                lunch: l,
                dinner: d,
                agencyId: nil,
                receiptNumber: "",
                notes: pendingScanResult?.merchantName ?? ""
            )
            if let mealId {
                _ = LocalStorageService.shared.saveReceipt(image: image, for: mealId)

                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                autoSaveMessage = "Meal saved for\n\(formatter.string(from: saveDate))"
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    autoSaveMessage = nil
                }
            }
        }
    }

    // MARK: - Save

    private func saveMeal() {
        guard let userId = authService.currentSession?.user.id else { return }
        Task {
            let mealId = await viewModel.saveMeal(
                userId: userId,
                date: date,
                breakfast: breakfast,
                lunch: lunch,
                dinner: dinner,
                agencyId: selectedAgencyId,
                receiptNumber: receiptNumber,
                notes: businessPurpose
            )
            if let mealId {
                // Re-save receipt files under the meal's actual ID
                for oldFilename in receiptFilenames {
                    if let image = LocalStorageService.shared.loadReceipt(filename: oldFilename) {
                        _ = LocalStorageService.shared.saveReceipt(image: image, for: mealId)
                        LocalStorageService.shared.deleteReceipt(filename: oldFilename)
                    } else {
                        let url = LocalStorageService.shared.receiptURL(filename: oldFilename)
                        if let data = try? Data(contentsOf: url) {
                            let ext = (oldFilename as NSString).pathExtension
                            _ = LocalStorageService.shared.saveFile(data: data, for: mealId, extension: ext)
                            LocalStorageService.shared.deleteReceipt(filename: oldFilename)
                        }
                    }
                }

                onSaveComplete?(mealId)
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
        breakfast = ""
        lunch = ""
        dinner = ""
        selectedAgencyId = nil
        receiptNumber = ""
        businessPurpose = ""
        receiptFilenames = []
        pendingImages = []
    }
}
