import Foundation
import Combine
import Supabase

@MainActor
final class TripViewModel: ObservableObject {
    private let client = SupabaseService.shared.client

    @Published var trips: [Trip] = []
    @Published var agencies: [Agency] = []
    @Published var visitTypes: [VisitType] = []
    @Published var isLoading = false
    @Published var isSaving = false
    @Published var errorMessage: String?

    // MARK: - Load Data

    func loadAll(userId: UUID) async {
        isLoading = true
        defer { isLoading = false }

        async let tripsResult: [Trip] = client.from("trips")
            .select()
            .eq("user_id", value: userId)
            .order("date", ascending: false)
            .execute()
            .value

        async let agenciesResult: [Agency] = client.from("agencies")
            .select()
            .eq("user_id", value: userId)
            .order("name")
            .execute()
            .value

        async let visitTypesResult: [VisitType] = client.from("visit_types")
            .select()
            .eq("user_id", value: userId)
            .order("name")
            .execute()
            .value

        do {
            trips = try await tripsResult
            agencies = try await agenciesResult
            visitTypes = try await visitTypesResult
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Save Trip

    func saveTrip(userId: UUID, date: Date, trackingMethod: String,
                  odometerStart: String, odometerStop: String,
                  startAddress: String, endAddress: String,
                  distanceMiles: String, destinationCity: String,
                  agencyId: UUID?, visitTypeId: UUID?,
                  contractVisitId: String,
                  tolls: String, parking: String, ferry: String, otherExpense: String,
                  notes: String) async -> Bool {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withFullDate]

        var tripData: [String: AnyJSON] = [
            "user_id": .string(userId.uuidString),
            "date": .string(dateFormatter.string(from: date)),
            "tracking_method": .string(trackingMethod),
        ]

        if trackingMethod == "odometer" {
            if let start = Decimal(string: odometerStart),
               let stop = Decimal(string: odometerStop) {
                if stop < start {
                    errorMessage = "Odometer stop must be greater than start"
                    return false
                }
                tripData["odometer_start"] = .double(NSDecimalNumber(decimal: start).doubleValue)
                tripData["odometer_stop"] = .double(NSDecimalNumber(decimal: stop).doubleValue)
                let miles = stop - start
                tripData["distance_miles"] = .double(NSDecimalNumber(decimal: miles).doubleValue)
            } else {
                if let start = Decimal(string: odometerStart) {
                    tripData["odometer_start"] = .double(NSDecimalNumber(decimal: start).doubleValue)
                }
                if let stop = Decimal(string: odometerStop) {
                    tripData["odometer_stop"] = .double(NSDecimalNumber(decimal: stop).doubleValue)
                }
            }
        } else {
            if !startAddress.isEmpty { tripData["start_address"] = .string(startAddress) }
            if !endAddress.isEmpty { tripData["end_address"] = .string(endAddress) }
            if let miles = Decimal(string: distanceMiles) {
                tripData["distance_miles"] = .double(NSDecimalNumber(decimal: miles).doubleValue)
            }
        }

        if !destinationCity.isEmpty { tripData["destination_city"] = .string(destinationCity) }
        if let aid = agencyId { tripData["agency_id"] = .string(aid.uuidString) }
        if let vtid = visitTypeId { tripData["visit_type_id"] = .string(vtid.uuidString) }
        if !contractVisitId.isEmpty { tripData["contract_visit_id"] = .string(contractVisitId) }
        if let v = Decimal(string: tolls) { tripData["tolls"] = .double(NSDecimalNumber(decimal: max(v, 0)).doubleValue) }
        if let v = Decimal(string: parking) { tripData["parking"] = .double(NSDecimalNumber(decimal: max(v, 0)).doubleValue) }
        if let v = Decimal(string: ferry) { tripData["ferry"] = .double(NSDecimalNumber(decimal: max(v, 0)).doubleValue) }
        if let v = Decimal(string: otherExpense) { tripData["other_expense"] = .double(NSDecimalNumber(decimal: max(v, 0)).doubleValue) }
        if !notes.isEmpty { tripData["notes"] = .string(notes) }

        do {
            try await client.from("trips")
                .insert(tripData)
                .execute()
            await loadAll(userId: userId)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    // MARK: - Update Trip

    func updateTrip(tripId: UUID, userId: UUID, date: Date, trackingMethod: String,
                    odometerStart: String, odometerStop: String,
                    startAddress: String, endAddress: String,
                    distanceMiles: String, destinationCity: String,
                    agencyId: UUID?, visitTypeId: UUID?,
                    contractVisitId: String,
                    tolls: String, parking: String, ferry: String, otherExpense: String,
                    notes: String) async -> Bool {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withFullDate]

        var tripData: [String: AnyJSON] = [
            "date": .string(dateFormatter.string(from: date)),
            "tracking_method": .string(trackingMethod),
            "updated_at": .string(ISO8601DateFormatter().string(from: Date())),
        ]

        if trackingMethod == "odometer" {
            if let start = Decimal(string: odometerStart),
               let stop = Decimal(string: odometerStop) {
                if stop < start {
                    errorMessage = "Odometer stop must be greater than start"
                    return false
                }
                tripData["odometer_start"] = .double(NSDecimalNumber(decimal: start).doubleValue)
                tripData["odometer_stop"] = .double(NSDecimalNumber(decimal: stop).doubleValue)
                let miles = stop - start
                tripData["distance_miles"] = .double(NSDecimalNumber(decimal: miles).doubleValue)
            } else {
                if let start = Decimal(string: odometerStart) {
                    tripData["odometer_start"] = .double(NSDecimalNumber(decimal: start).doubleValue)
                }
                if let stop = Decimal(string: odometerStop) {
                    tripData["odometer_stop"] = .double(NSDecimalNumber(decimal: stop).doubleValue)
                }
            }
            tripData["start_address"] = .null
            tripData["end_address"] = .null
        } else {
            if !startAddress.isEmpty { tripData["start_address"] = .string(startAddress) }
            if !endAddress.isEmpty { tripData["end_address"] = .string(endAddress) }
            if let miles = Decimal(string: distanceMiles) {
                tripData["distance_miles"] = .double(NSDecimalNumber(decimal: miles).doubleValue)
            }
            tripData["odometer_start"] = .null
            tripData["odometer_stop"] = .null
        }

        tripData["destination_city"] = destinationCity.isEmpty ? .null : .string(destinationCity)
        tripData["agency_id"] = agencyId.map { .string($0.uuidString) } ?? .null
        tripData["visit_type_id"] = visitTypeId.map { .string($0.uuidString) } ?? .null
        tripData["contract_visit_id"] = contractVisitId.isEmpty ? .null : .string(contractVisitId)
        tripData["tolls"] = Decimal(string: tolls).map { .double(NSDecimalNumber(decimal: max($0, 0)).doubleValue) } ?? .double(0)
        tripData["parking"] = Decimal(string: parking).map { .double(NSDecimalNumber(decimal: max($0, 0)).doubleValue) } ?? .double(0)
        tripData["ferry"] = Decimal(string: ferry).map { .double(NSDecimalNumber(decimal: max($0, 0)).doubleValue) } ?? .double(0)
        tripData["other_expense"] = Decimal(string: otherExpense).map { .double(NSDecimalNumber(decimal: max($0, 0)).doubleValue) } ?? .double(0)
        tripData["notes"] = notes.isEmpty ? .null : .string(notes)

        do {
            try await client.from("trips")
                .update(tripData)
                .eq("id", value: tripId)
                .eq("user_id", value: userId)
                .execute()
            await loadAll(userId: userId)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    // MARK: - Delete Trip

    func deleteTrip(tripId: UUID, userId: UUID) async -> Bool {
        do {
            try await client.from("trips")
                .delete()
                .eq("id", value: tripId)
                .eq("user_id", value: userId)
                .execute()
            await loadAll(userId: userId)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    // MARK: - Agencies

    @discardableResult
    func addAgency(userId: UUID, name: String) async -> UUID? {
        if let existing = agencies.first(where: { $0.name.lowercased() == name.lowercased() }) {
            return existing.id
        }
        let data: [String: String] = [
            "user_id": userId.uuidString,
            "name": name
        ]
        do {
            try await client.from("agencies").insert(data).execute()
            let updated: [Agency] = try await client.from("agencies")
                .select()
                .eq("user_id", value: userId)
                .order("name")
                .execute()
                .value
            agencies = updated
            return updated.first(where: { $0.name == name })?.id
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    // MARK: - Visit Types

    @discardableResult
    func addVisitType(userId: UUID, name: String) async -> UUID? {
        // Return existing if already present
        if let existing = visitTypes.first(where: { $0.name.lowercased() == name.lowercased() }) {
            return existing.id
        }
        let data: [String: String] = [
            "user_id": userId.uuidString,
            "name": name
        ]
        do {
            try await client.from("visit_types").insert(data).execute()
            let updated: [VisitType] = try await client.from("visit_types")
                .select()
                .eq("user_id", value: userId)
                .order("name")
                .execute()
                .value
            visitTypes = updated
            return updated.first(where: { $0.name == name })?.id
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    // MARK: - Delete Agency / Visit Type

    func deleteAgency(agencyId: UUID, userId: UUID) async -> Bool {
        do {
            try await client.from("agencies").delete().eq("id", value: agencyId).eq("user_id", value: userId).execute()
            agencies.removeAll { $0.id == agencyId }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func deleteVisitType(visitTypeId: UUID, userId: UUID) async -> Bool {
        do {
            try await client.from("visit_types").delete().eq("id", value: visitTypeId).eq("user_id", value: userId).execute()
            visitTypes.removeAll { $0.id == visitTypeId }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
