import SwiftUI
import Auth

struct MealLogView: View {
    @EnvironmentObject var authService: AuthService
    @ObservedObject var viewModel: MealViewModel

    // Pre-fill support
    let prefillData: ScanPrefillData?
    let onSaveComplete: ((UUID) -> Void)?

    @State private var date: Date
    // Quick rows = the first item of each type. Extras = additional same-type items.
    @State private var breakfast: String
    @State private var lunch: String
    @State private var dinner: String
    @State private var extras: [EditableMealItem]
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

    // Day-editor state (one meal entry per day)
    @State private var existingMealId: UUID?
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
        _breakfast = State(initialValue: "")
        _lunch = State(initialValue: "")
        _dinner = State(initialValue: "")
        _extras = State(initialValue: [])
        _receiptFilenames = State(initialValue: [])
        _pendingImages = State(initialValue: [])
    }

    private var isInScannerMode: Bool { prefillData != nil }

    private var dayTotal: Decimal {
        collectItems().reduce(0) { $0 + $1.amount }
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
                    Text("MedMiles keeps one meal entry per day. Each scanned receipt is added as its own line — double-check it's the right meal (breakfast, lunch, or dinner).")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
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
            // Add the scanned amount as its own new line item.
            addMealAmount(itemType(from: slot), amount: scannedAmount)

            // Attach the receipt image
            let tempId = UUID()
            if let filename = LocalStorageService.shared.saveReceipt(image: image, for: tempId) {
                receiptFilenames.append(filename)
            }
            pendingImages.append(image)
        } else {
            // Different day — auto-save into that day's entry
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

    /// Adds a new meal amount to the form as its own line item (quick row if
    /// that type is still empty, otherwise an extra row).
    private func addMealAmount(_ type: MealItemType, amount: String) {
        guard let amt = Decimal(string: amount), amt > 0 else { return }
        var all = collectItems()
        all.append(MealItem(type: type, amount: amt))
        distribute(all)
    }

    private func autoSaveNewMeal(date saveDate: Date, slot: ScanPrefillData.MealSlot, amount: String, image: UIImage) {
        guard let userId = authService.currentSession?.user.id else { return }
        guard let newAmt = Decimal(string: amount), newAmt > 0 else { return }
        let newItem = MealItem(type: itemType(from: slot), amount: newAmt)

        Task {
            // One entry per day: merge into that day's entry if it exists.
            if let existing = viewModel.meals.first(where: {
                Calendar.current.isDate($0.displayDate, inSameDayAs: saveDate)
            }) {
                var items = existing.items
                items.append(newItem)
                let ok = await viewModel.updateMeal(
                    mealId: existing.id,
                    userId: userId,
                    date: saveDate,
                    items: items,
                    agencyId: existing.agencyId,
                    receiptNumber: existing.receiptNumber ?? "",
                    notes: existing.businessPurpose ?? (pendingScanResult?.merchantName ?? "")
                )
                if ok { _ = LocalStorageService.shared.saveReceipt(image: image, for: existing.id) }
            } else {
                let mealId = await viewModel.saveMeal(
                    userId: userId,
                    date: saveDate,
                    items: [newItem],
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
        let items = collectItems()
        Task {
            let savedId: UUID?
            if let existingId = existingMealId {
                let ok = await viewModel.updateMeal(
                    mealId: existingId,
                    userId: userId,
                    date: date,
                    items: items,
                    agencyId: selectedAgencyId,
                    receiptNumber: receiptNumber,
                    notes: businessPurpose
                )
                savedId = ok ? existingId : nil
            } else {
                savedId = await viewModel.saveMeal(
                    userId: userId,
                    date: date,
                    items: items,
                    agencyId: selectedAgencyId,
                    receiptNumber: receiptNumber,
                    notes: businessPurpose
                )
            }

            guard let mealId = savedId else { return }
            reassociateReceipts(to: mealId)
            // The form now represents the saved day's single entry, so a further
            // save updates it instead of inserting a duplicate.
            existingMealId = mealId
            receiptFilenames = LocalStorageService.shared.receiptFilenames(for: mealId)
            onSaveComplete?(mealId)
            showSavedConfirmation = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                showSavedConfirmation = false
            }
        }
    }

    /// Re-saves any receipt files not yet under `mealId` (freshly scanned ones
    /// stored under a temp id) and leaves already-associated ones.
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

    // MARK: - Day Editor (one entry per day, line items)

    /// Loads the meal entry for the current `date` (if any) so the form always
    /// represents that single day. In scanner mode it appends the scanned amount
    /// as a new line item.
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
        existingMealId = existing?.id

        if existing == nil && !initial {
            // Switched to a day with no entry.
            distribute([])
            return
        }

        if let existing {
            for f in LocalStorageService.shared.receiptFilenames(for: existing.id) where !receiptFilenames.contains(f) {
                receiptFilenames.append(f)
            }
            if selectedAgencyId == nil { selectedAgencyId = existing.agencyId }
            if businessPurpose.isEmpty { businessPurpose = existing.businessPurpose ?? "" }
        }

        var merged = existing?.items ?? []
        if initial, let slot = prefillData?.mealSlot {
            let scannedAmt = max(Decimal(string: prefillData?.amount ?? "") ?? 0, 0)
            if scannedAmt > 0 {
                merged.append(MealItem(type: itemType(from: slot), amount: scannedAmt))
            }
        }
        distribute(merged)
    }

    /// Spreads a list of items into the quick rows (first of each type) and the
    /// extra rows (everything else).
    private func distribute(_ items: [MealItem]) {
        breakfast = ""
        lunch = ""
        dinner = ""
        extras = []
        var seen: Set<MealItemType> = []
        for item in items {
            if seen.contains(item.type) {
                extras.append(EditableMealItem(id: item.id, type: item.type, amount: formatString(item.amount)))
            } else {
                seen.insert(item.type)
                switch item.type {
                case .breakfast: breakfast = formatString(item.amount)
                case .lunch: lunch = formatString(item.amount)
                case .dinner: dinner = formatString(item.amount)
                }
            }
        }
    }

    /// Builds the line-item list from the quick rows + extras.
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

    private func itemType(from slot: ScanPrefillData.MealSlot) -> MealItemType {
        switch slot {
        case .breakfast: return .breakfast
        case .lunch: return .lunch
        case .dinner: return .dinner
        }
    }

    private func formatString(_ value: Decimal) -> String {
        value > 0 ? String(format: "%.2f", NSDecimalNumber(decimal: value).doubleValue) : ""
    }
}
