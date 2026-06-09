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

    // Day-editor / merge state (one meal entry per day)
    @State private var existingMealId: UUID?
    @State private var showSlotConflict = false
    @State private var conflictSlot: ScanPrefillData.MealSlot?
    @State private var conflictExisting: Decimal = 0
    @State private var conflictScanned: Decimal = 0
    @State private var didInitialLoad = false

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

        // The scanned receipt image is saved once in `.task` (not here) so it
        // can't be re-saved if SwiftUI re-initializes the view on a re-render.
        _receiptFilenames = State(initialValue: [])
        _pendingImages = State(initialValue: [])
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

            Section {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(Color(Constants.Colors.mintTeal))
                    Text("MedMiles keeps one meal entry per day. Double-check each amount is under the right meal (breakfast, lunch, or dinner).")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
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
                Spacer()
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
        .task {
            guard !didInitialLoad else { return }
            didInitialLoad = true
            // Save the scanned receipt image once (scanner mode only).
            if let image = prefillData?.capturedImage {
                let tempId = UUID()
                if let filename = LocalStorageService.shared.saveReceipt(image: image, for: tempId) {
                    receiptFilenames.append(filename)
                }
                pendingImages.append(image)
            }
            guard let userId = authService.currentSession?.user.id else { return }
            if viewModel.meals.isEmpty {
                await viewModel.loadAll(userId: userId)
            }
            loadExistingDay(initial: true)
        }
        .onChange(of: date) { _, _ in
            loadExistingDay(initial: false)
        }
        .alert("\(conflictSlot?.rawValue ?? "Meal") already logged", isPresented: $showSlotConflict, presenting: conflictSlot) { slot in
            Button("Add (\(money(conflictExisting + conflictScanned)))") {
                setField(slot, conflictExisting + conflictScanned)
            }
            Button("Replace (\(money(conflictScanned)))") {
                setField(slot, conflictScanned)
            }
        } message: { slot in
            Text("\(slot.rawValue) already has \(money(conflictExisting)) for this day. Add the new \(money(conflictScanned)) to it, or replace it?")
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
        let newAmt = max(Decimal(string: amount) ?? 0, 0)

        Task {
            // One entry per day: if that day already has a meal, merge into it.
            if let existing = viewModel.meals.first(where: {
                Calendar.current.isDate($0.displayDate, inSameDayAs: saveDate)
            }) {
                let b = existing.breakfast + (slot == .breakfast ? newAmt : 0)
                let l = existing.lunch + (slot == .lunch ? newAmt : 0)
                let d = existing.dinner + (slot == .dinner ? newAmt : 0)
                let ok = await viewModel.updateMeal(
                    mealId: existing.id,
                    userId: userId,
                    date: saveDate,
                    breakfast: fieldString(b),
                    lunch: fieldString(l),
                    dinner: fieldString(d),
                    agencyId: existing.agencyId,
                    receiptNumber: existing.receiptNumber ?? "",
                    notes: existing.businessPurpose ?? (pendingScanResult?.merchantName ?? "")
                )
                if ok { _ = LocalStorageService.shared.saveReceipt(image: image, for: existing.id) }
            } else {
                let mealId = await viewModel.saveMeal(
                    userId: userId,
                    date: saveDate,
                    breakfast: slot == .breakfast ? amount : "",
                    lunch: slot == .lunch ? amount : "",
                    dinner: slot == .dinner ? amount : "",
                    agencyId: nil,
                    receiptNumber: "",
                    notes: pendingScanResult?.merchantName ?? ""
                )
                if let mealId { _ = LocalStorageService.shared.saveReceipt(image: image, for: mealId) }
            }

            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            autoSaveMessage = "Meal saved for\n\(formatter.string(from: saveDate))"
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                autoSaveMessage = nil
            }
        }
    }

    // MARK: - Save

    private func saveMeal() {
        guard let userId = authService.currentSession?.user.id else { return }
        Task {
            // One entry per day: update the existing entry if this day already has
            // one, otherwise insert a new one.
            let savedId: UUID?
            if let existingId = existingMealId {
                let ok = await viewModel.updateMeal(
                    mealId: existingId,
                    userId: userId,
                    date: date,
                    breakfast: breakfast,
                    lunch: lunch,
                    dinner: dinner,
                    agencyId: selectedAgencyId,
                    receiptNumber: receiptNumber,
                    notes: businessPurpose
                )
                savedId = ok ? existingId : nil
            } else {
                savedId = await viewModel.saveMeal(
                    userId: userId,
                    date: date,
                    breakfast: breakfast,
                    lunch: lunch,
                    dinner: dinner,
                    agencyId: selectedAgencyId,
                    receiptNumber: receiptNumber,
                    notes: businessPurpose
                )
            }

            guard let mealId = savedId else { return }
            reassociateReceipts(to: mealId)
            // The form now represents the saved day's single entry, so any
            // further save updates it instead of inserting a duplicate.
            existingMealId = mealId
            receiptFilenames = LocalStorageService.shared.receiptFilenames(for: mealId)
            onSaveComplete?(mealId)
            showSavedConfirmation = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                showSavedConfirmation = false
            }
        }
    }

    /// Re-saves any receipt files that aren't yet under `mealId` (e.g. freshly
    /// scanned ones stored under a temp id), and leaves already-associated ones.
    private func reassociateReceipts(to mealId: UUID) {
        let prefix = mealId.uuidString
        for oldFilename in receiptFilenames where !oldFilename.hasPrefix(prefix) {
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
    }

    // MARK: - Day Editor (one entry per day)

    /// Loads the meal entry for the current `date` (if any) so the form always
    /// represents that single day. In scanner mode it merges the scanned amount
    /// into the chosen slot, prompting on a conflict.
    private func loadExistingDay(initial: Bool) {
        // Drop receipts loaded from a previously-shown day so they aren't
        // re-attached to a different day on save.
        if let oldId = existingMealId {
            let oldPrefix = oldId.uuidString
            receiptFilenames.removeAll { $0.hasPrefix(oldPrefix) }
        }

        let existing = viewModel.meals.first {
            Calendar.current.isDate($0.displayDate, inSameDayAs: date)
        }

        guard let existing else {
            existingMealId = nil
            if !initial {
                breakfast = ""
                lunch = ""
                dinner = ""
            }
            return
        }

        existingMealId = existing.id

        // Show the day's already-attached receipts alongside any new one.
        for f in LocalStorageService.shared.receiptFilenames(for: existing.id) where !receiptFilenames.contains(f) {
            receiptFilenames.append(f)
        }
        if selectedAgencyId == nil { selectedAgencyId = existing.agencyId }
        if businessPurpose.isEmpty { businessPurpose = existing.businessPurpose ?? "" }

        if initial, let slot = prefillData?.mealSlot {
            // Scanner merge: fill the non-scanned slots from the existing entry,
            // then merge the scanned amount into the chosen slot. The scanned
            // slot is always set deterministically (defaulting to Add) so no
            // amount is ever lost if the conflict prompt is dismissed.
            let scannedAmt = max(Decimal(string: prefillData?.amount ?? "") ?? 0, 0)
            if slot != .breakfast { breakfast = fieldString(existing.breakfast) }
            if slot != .lunch { lunch = fieldString(existing.lunch) }
            if slot != .dinner { dinner = fieldString(existing.dinner) }

            let existingSlotAmt = amount(existing, slot)
            setField(slot, existingSlotAmt + scannedAmt) // safe default = Add
            if existingSlotAmt > 0 && scannedAmt > 0 {
                conflictSlot = slot
                conflictExisting = existingSlotAmt
                conflictScanned = scannedAmt
                showSlotConflict = true
            }
        } else {
            breakfast = fieldString(existing.breakfast)
            lunch = fieldString(existing.lunch)
            dinner = fieldString(existing.dinner)
        }
    }

    private func amount(_ meal: Meal, _ slot: ScanPrefillData.MealSlot) -> Decimal {
        switch slot {
        case .breakfast: return meal.breakfast
        case .lunch: return meal.lunch
        case .dinner: return meal.dinner
        }
    }

    private func setField(_ slot: ScanPrefillData.MealSlot, _ value: Decimal) {
        switch slot {
        case .breakfast: breakfast = fieldString(value)
        case .lunch: lunch = fieldString(value)
        case .dinner: dinner = fieldString(value)
        }
    }

    private func fieldString(_ value: Decimal) -> String {
        value > 0 ? String(format: "%.2f", NSDecimalNumber(decimal: value).doubleValue) : ""
    }

    private func money(_ value: Decimal) -> String {
        "$" + String(format: "%.2f", NSDecimalNumber(decimal: value).doubleValue)
    }
}
