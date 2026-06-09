import SwiftUI
import Auth

struct TripHistoryView: View {
    @EnvironmentObject var authService: AuthService
    @ObservedObject var viewModel: TripViewModel
    @AppStorage("selectedTaxYear") private var selectedTaxYear = Calendar.current.component(.year, from: Date())
    @State private var searchText = ""
    @State private var beginningOdometerText = ""
    @State private var endingOdometerText = ""
    @State private var hasDismissedOdometerReminder = false

    private var totalWorkMiles: Decimal {
        viewModel.trips
            .filter { $0.date.hasPrefix("\(selectedTaxYear)") }
            .compactMap { $0.distanceMiles }
            .reduce(Decimal.zero, +)
    }

    private var filteredTrips: [Trip] {
        guard !searchText.isEmpty else { return viewModel.trips }
        return viewModel.trips.filter { trip in
            let agencyName = trip.agencyId.flatMap { id in viewModel.agencies.first(where: { $0.id == id })?.name } ?? ""
            let visitTypeName = trip.visitTypeId.flatMap { id in viewModel.visitTypes.first(where: { $0.id == id })?.name } ?? ""
            let destination = trip.destinationCity ?? ""
            let contractVisitId = trip.contractVisitId ?? ""
            return agencyName.localizedCaseInsensitiveContains(searchText)
                || visitTypeName.localizedCaseInsensitiveContains(searchText)
                || destination.localizedCaseInsensitiveContains(searchText)
                || contractVisitId.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        List {
            if beginningOdometerText.isEmpty && !hasDismissedOdometerReminder {
                Section {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                            .foregroundColor(Color(Constants.Colors.warningAmber))
                            .font(.title3)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Record your starting mileage")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Text("Enter your odometer reading from the start of \(String(selectedTaxYear)) to track your total annual miles for tax purposes.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Button {
                            withAnimation {
                                UserDefaults.standard.set(true, forKey: "hasDismissedOdometerReminder_\(selectedTaxYear)")
                                hasDismissedOdometerReminder = true
                            }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Dismiss odometer reminder")
                    }
                }
            }

            Section(header: Text("Annual Mileage (\(String(selectedTaxYear)))")) {
                HStack {
                    Text("Beginning Odometer")
                    Spacer()
                    TextField("Enter reading", text: $beginningOdometerText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 120)
                        .onChange(of: beginningOdometerText) { _, newValue in
                            if let val = Double(newValue), val > 0 {
                                UserDefaults.standard.set(val, forKey: "beginningOdometer_\(selectedTaxYear)")
                            } else if newValue.isEmpty {
                                UserDefaults.standard.removeObject(forKey: "beginningOdometer_\(selectedTaxYear)")
                            }
                        }
                }

                HStack {
                    Text("Ending Odometer")
                    Spacer()
                    TextField("Enter reading", text: $endingOdometerText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 120)
                        .onChange(of: endingOdometerText) { _, newValue in
                            if let val = Double(newValue), val > 0 {
                                UserDefaults.standard.set(val, forKey: "endingOdometer_\(selectedTaxYear)")
                            } else if newValue.isEmpty {
                                UserDefaults.standard.removeObject(forKey: "endingOdometer_\(selectedTaxYear)")
                            }
                        }
                }

                let beginning = Double(beginningOdometerText) ?? 0
                let ending = Double(endingOdometerText) ?? 0
                if beginning > 0 && ending > 0 {
                    HStack {
                        Text("Total Miles Driven")
                            .fontWeight(.bold)
                        Spacer()
                        Text(String(format: "%.0f mi", ending - beginning))
                            .fontWeight(.bold)
                            .foregroundColor(Color(Constants.Colors.mintTeal))
                    }
                }

                HStack {
                    Text("Total Work Miles")
                        .fontWeight(.bold)
                    Spacer()
                    Text("\(NSDecimalNumber(decimal: totalWorkMiles).intValue) mi")
                        .fontWeight(.bold)
                        .foregroundColor(Color(Constants.Colors.mintTeal))
                }

                Text("Enter your odometer readings at the start and end of the year to track total annual miles.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if viewModel.trips.isEmpty {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "car.fill")
                            .font(.largeTitle)
                            .foregroundColor(Color(.systemGray3))
                        Text("No trips logged yet")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text("Tap \"Log Trip\" to get started")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                }
            } else {
                let grouped = MonthGrouping.group(filteredTrips, by: \.date)
                ForEach(grouped) { group in
                    Section(header: Text(group.label)) {
                        ForEach(group.items) { trip in
                            NavigationLink(value: trip) {
                                TripRow(trip: trip, agencies: viewModel.agencies, visitTypes: viewModel.visitTypes)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $searchText, prompt: "Search trips")
        .refreshable {
            guard let userId = authService.currentSession?.user.id else { return }
            await viewModel.loadAll(userId: userId)
        }
        .background(Color(Constants.Colors.background))
        .onAppear { loadOdometerValues() }
        .onChange(of: selectedTaxYear) { _, _ in loadOdometerValues() }
    }

    private func loadOdometerValues() {
        let savedBegin = UserDefaults.standard.double(forKey: "beginningOdometer_\(selectedTaxYear)")
        beginningOdometerText = savedBegin > 0 ? String(format: "%.0f", savedBegin) : ""
        let savedEnd = UserDefaults.standard.double(forKey: "endingOdometer_\(selectedTaxYear)")
        endingOdometerText = savedEnd > 0 ? String(format: "%.0f", savedEnd) : ""
        hasDismissedOdometerReminder = UserDefaults.standard.bool(forKey: "hasDismissedOdometerReminder_\(selectedTaxYear)")
    }
}

struct TripRow: View {
    let trip: Trip
    let agencies: [Agency]
    let visitTypes: [VisitType]

    private var agencyName: String {
        guard let id = trip.agencyId else { return "" }
        return agencies.first(where: { $0.id == id })?.name ?? ""
    }

    private var visitTypeName: String {
        guard let id = trip.visitTypeId else { return "" }
        return visitTypes.first(where: { $0.id == id })?.name ?? ""
    }

    private var totalExpenses: Decimal {
        (trip.tolls ?? 0) + (trip.parking ?? 0) + (trip.ferry ?? 0) + (trip.otherExpense ?? 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    if !agencyName.isEmpty {
                        Text(agencyName)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                    if let city = trip.destinationCity, !city.isEmpty {
                        Text(city)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    if let miles = trip.distanceMiles {
                        Text("\(NSDecimalNumber(decimal: miles).doubleValue, specifier: "%.1f") mi")
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundColor(Color(Constants.Colors.mintTeal))
                    }

                    Text(trip.displayDate, style: .date)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            HStack(spacing: 8) {
                if !visitTypeName.isEmpty {
                    Text(visitTypeName)
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color(Constants.Colors.mintTeal).opacity(0.15))
                        .foregroundColor(Color(Constants.Colors.mintTeal))
                        .cornerRadius(4)
                }

                if trip.trackingMethod == "odometer" {
                    Label("Odometer", systemImage: "gauge.with.needle")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } else {
                    Label("Address", systemImage: "map")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                if totalExpenses > 0 {
                    Text("$\(NSDecimalNumber(decimal: totalExpenses).doubleValue, specifier: "%.2f") expenses")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
