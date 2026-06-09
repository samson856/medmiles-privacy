import Foundation
import Supabase
import Combine

@MainActor
final class IncomeViewModel: ObservableObject {
    private let client = SupabaseService.shared.client

    @Published var incomeEntries: [Income] = []
    @Published var agencies: [Agency] = []
    @Published var visitTypes: [VisitType] = []
    @Published var isLoading = false
    @Published var isSaving = false
    @Published var errorMessage: String?

    // MARK: - Load Data

    func loadAll(userId: UUID) async {
        isLoading = true
        defer { isLoading = false }

        do {
            async let incomeResult: [Income] = client.from("income")
                .select()
                .eq("user_id", value: userId)
                .order("date_of_service", ascending: false)
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

            incomeEntries = try await incomeResult
            agencies = try await agenciesResult
            visitTypes = try await visitTypesResult
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Save Income

    func saveIncome(userId: UUID, contractVisitId: String, dateOfService: Date,
                    agencyId: UUID?, visitTypeId: UUID?, destinationCity: String,
                    rateType: String, advertisedRate: String, grossPay: String,
                    taxSetAsideAmount: String, status: String, datePaid: Date?,
                    notes: String) async -> Bool {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withFullDate]

        guard let grossPayDecimal = Decimal(string: grossPay), grossPayDecimal > 0 else {
            errorMessage = "Please enter a valid gross pay amount"
            return false
        }

        var data: [String: AnyJSON] = [
            "user_id": .string(userId.uuidString),
            "date_of_service": .string(dateFormatter.string(from: dateOfService)),
            "gross_pay": .double(NSDecimalNumber(decimal: grossPayDecimal).doubleValue),
            "status": .string(status),
        ]

        if !contractVisitId.isEmpty { data["contract_visit_id"] = .string(contractVisitId) }
        if let aid = agencyId { data["agency_id"] = .string(aid.uuidString) }
        if let vtid = visitTypeId { data["visit_type_id"] = .string(vtid.uuidString) }
        if !destinationCity.isEmpty { data["destination_city"] = .string(destinationCity) }
        if !rateType.isEmpty { data["rate_type"] = .string(rateType) }
        if !advertisedRate.isEmpty { data["advertised_rate"] = .string(advertisedRate) }
        if let setAside = Decimal(string: taxSetAsideAmount) {
            if setAside > grossPayDecimal {
                errorMessage = "Set-aside amount cannot exceed gross pay"
                return false
            }
            data["tax_set_aside_amount"] = .double(NSDecimalNumber(decimal: setAside).doubleValue)
        }
        if status == "completed", let paid = datePaid {
            data["date_paid"] = .string(dateFormatter.string(from: paid))
        }
        if !notes.isEmpty { data["notes"] = .string(notes) }

        do {
            try await client.from("income").insert(data).execute()
            await loadAll(userId: userId)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    // MARK: - Update Income

    func updateIncome(incomeId: UUID, userId: UUID, contractVisitId: String,
                      dateOfService: Date, agencyId: UUID?, visitTypeId: UUID?,
                      destinationCity: String, rateType: String, advertisedRate: String,
                      grossPay: String, taxSetAsideAmount: String, status: String,
                      datePaid: Date?, notes: String) async -> Bool {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withFullDate]

        guard let grossPayDecimal = Decimal(string: grossPay), grossPayDecimal > 0 else {
            errorMessage = "Please enter a valid gross pay amount"
            return false
        }

        var data: [String: AnyJSON] = [
            "date_of_service": .string(dateFormatter.string(from: dateOfService)),
            "gross_pay": .double(NSDecimalNumber(decimal: grossPayDecimal).doubleValue),
            "status": .string(status),
            "updated_at": .string(ISO8601DateFormatter().string(from: Date())),
        ]

        data["contract_visit_id"] = contractVisitId.isEmpty ? .null : .string(contractVisitId)
        data["agency_id"] = agencyId.map { .string($0.uuidString) } ?? .null
        data["visit_type_id"] = visitTypeId.map { .string($0.uuidString) } ?? .null
        data["destination_city"] = destinationCity.isEmpty ? .null : .string(destinationCity)
        data["rate_type"] = rateType.isEmpty ? .null : .string(rateType)
        data["advertised_rate"] = advertisedRate.isEmpty ? .null : .string(advertisedRate)
        if let setAside = Decimal(string: taxSetAsideAmount) {
            if setAside > grossPayDecimal {
                errorMessage = "Set-aside amount cannot exceed gross pay"
                return false
            }
            data["tax_set_aside_amount"] = .double(NSDecimalNumber(decimal: setAside).doubleValue)
        } else {
            data["tax_set_aside_amount"] = .double(0)
        }
        if status == "completed", let paid = datePaid {
            data["date_paid"] = .string(dateFormatter.string(from: paid))
        } else {
            data["date_paid"] = .null
        }
        data["notes"] = notes.isEmpty ? .null : .string(notes)

        do {
            try await client.from("income").update(data).eq("id", value: incomeId).eq("user_id", value: userId).execute()
            await loadAll(userId: userId)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    // MARK: - Delete Income

    func deleteIncome(incomeId: UUID, userId: UUID) async -> Bool {
        do {
            try await client.from("income").delete().eq("id", value: incomeId).eq("user_id", value: userId).execute()
            await loadAll(userId: userId)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    // MARK: - Agencies & Visit Types

    @discardableResult
    func addAgency(userId: UUID, name: String) async -> UUID? {
        if let existing = agencies.first(where: { $0.name.lowercased() == name.lowercased() }) {
            return existing.id
        }
        let data: [String: String] = ["user_id": userId.uuidString, "name": name]
        do {
            try await client.from("agencies").insert(data).execute()
            let updated: [Agency] = try await client.from("agencies")
                .select().eq("user_id", value: userId).order("name").execute().value
            agencies = updated
            return updated.first(where: { $0.name == name })?.id
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    @discardableResult
    func addVisitType(userId: UUID, name: String) async -> UUID? {
        // Return existing if already present
        if let existing = visitTypes.first(where: { $0.name.lowercased() == name.lowercased() }) {
            return existing.id
        }
        let data: [String: String] = ["user_id": userId.uuidString, "name": name]
        do {
            try await client.from("visit_types").insert(data).execute()
            let updated: [VisitType] = try await client.from("visit_types")
                .select().eq("user_id", value: userId).order("name").execute().value
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

    // MARK: - Computed

    var totalGrossPay: Decimal {
        incomeEntries.reduce(0) { $0 + $1.grossPay }
    }

    var totalTaxSetAside: Decimal {
        incomeEntries.reduce(0) { $0 + ($1.taxSetAsideAmount ?? 0) }
    }

    var totalNetPay: Decimal {
        totalGrossPay - totalTaxSetAside
    }

    var pendingCount: Int {
        incomeEntries.filter { $0.status == "pending" }.count
    }

    var completedCount: Int {
        incomeEntries.filter { $0.status == "completed" }.count
    }
}
