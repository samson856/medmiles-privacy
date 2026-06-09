import SwiftUI
import Auth

struct TripEditView: View {
    @EnvironmentObject var authService: AuthService
    @ObservedObject var viewModel: TripViewModel
    @Environment(\.dismiss) private var dismiss

    let trip: Trip

    @State private var trackingMethod: String
    @State private var date: Date
    @State private var odometerStart: String
    @State private var odometerStop: String
    @State private var startAddress: String
    @State private var endAddress: String
    @State private var manualMiles: String
    @State private var destinationCity: String
    @State private var selectedAgencyId: UUID?
    @State private var selectedVisitTypeId: UUID?
    @State private var contractVisitId: String
    @State private var tolls: String
    @State private var parking: String
    @State private var ferry: String
    @State private var otherExpense: String
    @State private var notes: String
    @State private var receiptFilenames: [String] = []
    @State private var isCalculatingDistance = false
    @State private var showDeleteConfirmation = false

    init(trip: Trip, viewModel: TripViewModel) {
        self.trip = trip
        self.viewModel = viewModel

        _trackingMethod = State(initialValue: trip.trackingMethod)
        _date = State(initialValue: trip.displayDate)
        _odometerStart = State(initialValue: trip.odometerStart.map { "\(NSDecimalNumber(decimal: $0).doubleValue)" } ?? "")
        _odometerStop = State(initialValue: trip.odometerStop.map { "\(NSDecimalNumber(decimal: $0).doubleValue)" } ?? "")
        _startAddress = State(initialValue: trip.startAddress ?? "")
        _endAddress = State(initialValue: trip.endAddress ?? "")
        _manualMiles = State(initialValue: trip.distanceMiles.map { "\(NSDecimalNumber(decimal: $0).doubleValue)" } ?? "")
        _destinationCity = State(initialValue: trip.destinationCity ?? "")
        _selectedAgencyId = State(initialValue: trip.agencyId)
        _selectedVisitTypeId = State(initialValue: trip.visitTypeId)
        _contractVisitId = State(initialValue: trip.contractVisitId ?? "")
        _tolls = State(initialValue: trip.tolls.map { NSDecimalNumber(decimal: $0).doubleValue > 0 ? "\(NSDecimalNumber(decimal: $0).doubleValue)" : "" } ?? "")
        _parking = State(initialValue: trip.parking.map { NSDecimalNumber(decimal: $0).doubleValue > 0 ? "\(NSDecimalNumber(decimal: $0).doubleValue)" : "" } ?? "")
        _ferry = State(initialValue: trip.ferry.map { NSDecimalNumber(decimal: $0).doubleValue > 0 ? "\(NSDecimalNumber(decimal: $0).doubleValue)" : "" } ?? "")
        _otherExpense = State(initialValue: trip.otherExpense.map { NSDecimalNumber(decimal: $0).doubleValue > 0 ? "\(NSDecimalNumber(decimal: $0).doubleValue)" : "" } ?? "")
        _notes = State(initialValue: trip.notes ?? "")
        _receiptFilenames = State(initialValue: LocalStorageService.shared.receiptFilenames(for: trip.id))
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
                            if let filename = LocalStorageService.shared.saveReceipt(image: image, for: trip.id) {
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
                            if let filename = LocalStorageService.shared.saveFileFromURL(url, for: trip.id) {
                                receiptFilenames.append(filename)
                            }
                        }
                    )
                }
            }

            Section {
                TextField("Notes (optional)", text: $notes)
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
                    updateTrip()
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
                        Text("Delete Trip")
                        Spacer()
                    }
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Edit Trip")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Delete this trip?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                deleteTrip()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone.")
        }
    }

    private func updateTrip() {
        guard let userId = authService.currentSession?.user.id else { return }
        Task {
            let success = await viewModel.updateTrip(
                tripId: trip.id,
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
                dismiss()
            }
        }
    }

    private func deleteTrip() {
        guard let userId = authService.currentSession?.user.id else { return }
        Task {
            let success = await viewModel.deleteTrip(tripId: trip.id, userId: userId)
            if success {
                dismiss()
            }
        }
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
}
