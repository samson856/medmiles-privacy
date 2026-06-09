import SwiftUI
import Auth

struct TripLogView: View {
    @EnvironmentObject var authService: AuthService
    @ObservedObject var viewModel: TripViewModel

    @State private var trackingMethod = "odometer"
    @State private var date = Date()

    // Odometer fields
    @State private var odometerStart = ""
    @State private var odometerStop = ""

    // Address fields
    @State private var startAddress = ""
    @State private var endAddress = ""
    @State private var manualMiles = ""

    // Shared fields
    @State private var destinationCity = ""
    @State private var selectedAgencyId: UUID?
    @State private var selectedVisitTypeId: UUID?
    @State private var contractVisitId = ""

    // Trip expenses
    @State private var tolls = ""
    @State private var parking = ""
    @State private var ferry = ""
    @State private var otherExpense = ""

    @State private var notes = ""
    @State private var receiptFilenames: [String] = []
    @State private var showSavedConfirmation = false
    @State private var isCalculatingDistance = false
    @State private var mileageValidationError: String?
    @State private var showUpgradePrompt = false
    @State private var showUpgradeSheet = false

    private var currentMonthTripCount: Int {
        let now = Date()
        let calendar = Calendar.current
        let year = calendar.component(.year, from: now)
        let month = calendar.component(.month, from: now)
        let prefix = String(format: "%04d-%02d", year, month)
        return viewModel.trips.filter { $0.date.hasPrefix(prefix) }.count
    }

    private var hasAnyExpense: Bool {
        let t = Decimal(string: tolls) ?? 0
        let p = Decimal(string: parking) ?? 0
        let f = Decimal(string: ferry) ?? 0
        let o = Decimal(string: otherExpense) ?? 0
        return (t + p + f + o) > 0
    }

    private var calculatedMiles: String {
        if trackingMethod == "odometer" {
            let cleanStart = odometerStart.trimmingCharacters(in: .whitespaces)
            let cleanStop = odometerStop.trimmingCharacters(in: .whitespaces)
            guard !cleanStart.isEmpty, !cleanStop.isEmpty,
                  let start = Decimal(string: cleanStart),
                  let stop = Decimal(string: cleanStop),
                  stop > start else { return "" }
            let miles = stop - start
            return String(format: "%.1f", NSDecimalNumber(decimal: miles).doubleValue)
        }
        return manualMiles
    }

    var body: some View {
        Form {
            Section {
                Picker("Tracking Method", selection: $trackingMethod) {
                    Text("Odometer").tag("odometer")
                    Text("Address").tag("address")
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            if trackingMethod == "odometer" {
                Section {
                    HintBanner(
                        text: "Odometer readings provide the strongest IRS audit defense",
                        color: Color(Constants.Colors.successGreen)
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            }

            Section {
                DatePicker("Date", selection: $date, displayedComponents: .date)
            }

            if trackingMethod == "odometer" {
                Section(header: Text("Odometer Readings")) {
                    TextField("Start reading", text: $odometerStart)
                        .keyboardType(.decimalPad)
                    TextField("End reading", text: $odometerStop)
                        .keyboardType(.decimalPad)
                    if !calculatedMiles.isEmpty {
                        HStack {
                            Text("Total Miles")
                            Spacer()
                            Text("\(calculatedMiles) mi")
                                .fontWeight(.bold)
                                .foregroundColor(Color(Constants.Colors.mintTeal))
                        }
                    }
                }
            } else {
                Section(header: Text("Addresses")) {
                    TextField("Start location", text: $startAddress)
                        .onSubmit { calculateDistanceIfReady() }
                    TextField("End location", text: $endAddress)
                        .onSubmit { calculateDistanceIfReady() }

                    if !startAddress.isEmpty && !endAddress.isEmpty {
                        Button {
                            calculateDistanceIfReady()
                        } label: {
                            HStack {
                                if isCalculatingDistance {
                                    ProgressView().scaleEffect(0.8)
                                } else {
                                    Image(systemName: "location.fill")
                                }
                                Text(isCalculatingDistance ? "Calculating..." : "Calculate Miles")
                            }
                            .foregroundColor(Color(Constants.Colors.mintTeal))
                        }
                        .disabled(isCalculatingDistance)
                    }

                    TextField("Miles (auto or manual)", text: $manualMiles)
                        .keyboardType(.decimalPad)
                }
            }

            Section(header: Text("Trip Details")) {
                TextField("City or town", text: $destinationCity)

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

                TextField("Contract / Visit ID (optional)", text: $contractVisitId)
            }

            Section(header: Text("Trip Expenses")) {
                CurrencyFieldCompact(label: "Tolls", value: $tolls)
                CurrencyFieldCompact(label: "Parking", value: $parking)
                CurrencyFieldCompact(label: "Ferry", value: $ferry)
                CurrencyFieldCompact(label: "Other", value: $otherExpense)
            }

            if hasAnyExpense {
                Section(header: Text("Expense Receipts")) {
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

                Section {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(Color(Constants.Colors.warningAmber))
                        Text("Keep receipts for tolls, parking, and other trip expenses to support your deduction.")
                            .font(.caption)
                            .foregroundColor(Color(Constants.Colors.warningAmber))
                    }
                }
            }

            Section {
                TextField("Notes (optional)", text: $notes)
            }

            // Mileage validation error
            if let mileageError = mileageValidationError {
                Section {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(Color(Constants.Colors.errorRed))
                        Text(mileageError)
                            .font(.caption)
                            .foregroundColor(Color(Constants.Colors.errorRed))
                    }
                }
            }

            // Error display
            if let error = viewModel.errorMessage {
                Section {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(Color(Constants.Colors.errorRed))
                }
            }

            Section {
                Button {
                    saveTrip()
                } label: {
                    HStack {
                        Spacer()
                        if viewModel.isSaving {
                            ProgressView().tint(.white)
                        }
                        Text("Save Trip")
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
                Button("Done") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            }
        }
        .background(Color(Constants.Colors.background).ignoresSafeArea())
        .alert("Trip Limit Reached", isPresented: $showUpgradePrompt) {
            Button("Upgrade to Pro") { showUpgradeSheet = true }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Free accounts can log up to \(StoreKitService.freeTripsPerMonth) trips per month. Upgrade to Pro for unlimited trips.")
        }
        .sheet(isPresented: $showUpgradeSheet) {
            NavigationStack {
                SubscriptionView()
            }
        }
        .overlay {
            if showSavedConfirmation {
                savedConfirmationOverlay
            }
        }
    }

    // MARK: - Odometer Section

    private var odometerSection: some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Odometer Start")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(Color(Constants.Colors.graphite))
                TextField("Start reading", text: $odometerStart)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Odometer Stop")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(Color(Constants.Colors.graphite))
                TextField("End reading", text: $odometerStop)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
            }
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Address Section

    private var addressSection: some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Start Address")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(Color(Constants.Colors.graphite))
                TextField("Start location", text: $startAddress)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { calculateDistanceIfReady() }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("End Address")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(Color(Constants.Colors.graphite))
                TextField("End location", text: $endAddress)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { calculateDistanceIfReady() }
            }

            // Calculate button
            if !startAddress.isEmpty && !endAddress.isEmpty {
                Button {
                    calculateDistanceIfReady()
                } label: {
                    HStack(spacing: 6) {
                        if isCalculatingDistance {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "location.fill")
                        }
                        Text(isCalculatingDistance ? "Calculating..." : "Calculate Miles")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color(Constants.Colors.mintTeal).opacity(0.15))
                    .foregroundColor(Color(Constants.Colors.mintTeal))
                    .cornerRadius(8)
                }
                .disabled(isCalculatingDistance)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Miles")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(Color(Constants.Colors.graphite))
                TextField("Auto-calculated or enter manually", text: $manualMiles)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
            }
        }
        .padding(.horizontal, 24)
    }

    private func calculateDistanceIfReady() {
        guard !startAddress.isEmpty, !endAddress.isEmpty else { return }
        isCalculatingDistance = true
        Task {
            if let miles = await GoogleMapsService.shared.calculateDistance(
                from: startAddress, to: endAddress
            ) {
                manualMiles = String(format: "%.1f", miles)
            }
            isCalculatingDistance = false
        }
    }

    // MARK: - Shared Fields

    private var sharedFieldsSection: some View {
        VStack(spacing: 12) {
            // Destination city
            VStack(alignment: .leading, spacing: 6) {
                Text("Destination City / Town")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(Color(Constants.Colors.graphite))
                TextField("City or town", text: $destinationCity)
                    .textFieldStyle(.roundedBorder)
            }

            // Agency picker
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

            // Visit type picker
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

            // Contract/visit ID
            VStack(alignment: .leading, spacing: 6) {
                Text("Contract / Visit ID")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(Color(Constants.Colors.graphite))
                TextField("Optional", text: $contractVisitId)
                    .textFieldStyle(.roundedBorder)
            }
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Trip Expenses

    private var tripExpensesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Trip Expenses")
                .font(.headline)
                .foregroundColor(Color(Constants.Colors.graphite))

            CurrencyFieldCompact(label: "Tolls", value: $tolls)
            CurrencyFieldCompact(label: "Parking", value: $parking)
            CurrencyFieldCompact(label: "Ferry", value: $ferry)
            CurrencyFieldCompact(label: "Other", value: $otherExpense)
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.systemGray5), lineWidth: 1)
        )
        .padding(.horizontal, 24)
    }

    // MARK: - Save

    private func saveTrip() {
        // Check subscription limit
        if !StoreKitService.shared.canLogTrip(currentMonthCount: currentMonthTripCount) {
            showUpgradePrompt = true
            return
        }

        // Validate mileage
        let miles = Decimal(string: calculatedMiles.trimmingCharacters(in: .whitespaces)) ?? 0
        if miles <= 0 {
            mileageValidationError = "Please enter a valid mileage greater than zero before saving."
            return
        }
        mileageValidationError = nil

        guard let userId = authService.currentSession?.user.id else { return }
        Task {
            let success = await viewModel.saveTrip(
                userId: userId,
                date: date,
                trackingMethod: trackingMethod,
                odometerStart: odometerStart,
                odometerStop: odometerStop,
                startAddress: startAddress,
                endAddress: endAddress,
                distanceMiles: manualMiles,
                destinationCity: destinationCity,
                agencyId: selectedAgencyId,
                visitTypeId: selectedVisitTypeId,
                contractVisitId: contractVisitId,
                tolls: tolls,
                parking: parking,
                ferry: ferry,
                otherExpense: otherExpense,
                notes: notes
            )
            if success {
                showSavedConfirmation = true
                resetForm()
                ReviewService.shared.recordTripSaved()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    showSavedConfirmation = false
                }
            }
        }
    }

    private func resetForm() {
        mileageValidationError = nil
        odometerStart = ""
        odometerStop = ""
        startAddress = ""
        endAddress = ""
        manualMiles = ""
        destinationCity = ""
        selectedAgencyId = nil
        selectedVisitTypeId = nil
        contractVisitId = ""
        tolls = ""
        parking = ""
        ferry = ""
        otherExpense = ""
        notes = ""
        receiptFilenames = []
        date = Date()
    }

    // MARK: - Confirmation Overlay

    private var savedConfirmationOverlay: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.largeTitle)
                .foregroundColor(Color(Constants.Colors.successGreen))
            Text("Trip Saved!")
                .font(.headline)
        }
        .padding(32)
        .background(.ultraThinMaterial)
        .cornerRadius(16)
    }
}

// MARK: - Hint Banner

struct HintBanner: View {
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle.fill")
                .foregroundColor(color)
            Text(text)
                .font(.caption)
                .foregroundColor(color)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.1))
        .cornerRadius(10)
        .padding(.horizontal, 24)
    }
}
