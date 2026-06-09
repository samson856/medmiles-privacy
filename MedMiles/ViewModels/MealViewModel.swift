import Foundation
import Supabase
import Combine

@MainActor
final class MealViewModel: ObservableObject {
    private let client = SupabaseService.shared.client

    @Published var meals: [Meal] = []
    @Published var agencies: [Agency] = []
    @Published var isLoading = false
    @Published var isSaving = false
    @Published var errorMessage: String?

    // MARK: - Load Data

    func loadAll(userId: UUID) async {
        isLoading = true
        defer { isLoading = false }

        do {
            async let mealsResult: [Meal] = client.from("meals")
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

            meals = try await mealsResult
            agencies = try await agenciesResult
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Save Meal

    func saveMeal(userId: UUID, date: Date, breakfast: String, lunch: String,
                  dinner: String, agencyId: UUID?, receiptNumber: String,
                  notes: String) async -> UUID? {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withFullDate]

        let b = max(Decimal(string: breakfast) ?? 0, 0)
        let l = max(Decimal(string: lunch) ?? 0, 0)
        let d = max(Decimal(string: dinner) ?? 0, 0)

        if b == 0 && l == 0 && d == 0 {
            errorMessage = "Please enter at least one meal amount"
            return nil
        }

        var data: [String: AnyJSON] = [
            "user_id": .string(userId.uuidString),
            "date": .string(dateFormatter.string(from: date)),
            "breakfast": .double(NSDecimalNumber(decimal: b).doubleValue),
            "lunch": .double(NSDecimalNumber(decimal: l).doubleValue),
            "dinner": .double(NSDecimalNumber(decimal: d).doubleValue),
        ]

        if let aid = agencyId { data["agency_id"] = .string(aid.uuidString) }
        if !receiptNumber.isEmpty { data["receipt_number"] = .string(receiptNumber) }
        if !notes.isEmpty { data["business_purpose"] = .string(notes) }

        do {
            let result: Meal = try await client.from("meals")
                .insert(data)
                .select()
                .single()
                .execute()
                .value
            await loadAll(userId: userId)
            return result.id
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    // MARK: - Update Meal

    func updateMeal(mealId: UUID, userId: UUID, date: Date, breakfast: String,
                    lunch: String, dinner: String, agencyId: UUID?,
                    receiptNumber: String, notes: String) async -> Bool {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withFullDate]

        let b = max(Decimal(string: breakfast) ?? 0, 0)
        let l = max(Decimal(string: lunch) ?? 0, 0)
        let d = max(Decimal(string: dinner) ?? 0, 0)

        var data: [String: AnyJSON] = [
            "date": .string(dateFormatter.string(from: date)),
            "breakfast": .double(NSDecimalNumber(decimal: b).doubleValue),
            "lunch": .double(NSDecimalNumber(decimal: l).doubleValue),
            "dinner": .double(NSDecimalNumber(decimal: d).doubleValue),
            "updated_at": .string(ISO8601DateFormatter().string(from: Date())),
        ]

        data["agency_id"] = agencyId.map { .string($0.uuidString) } ?? .null
        data["receipt_number"] = receiptNumber.isEmpty ? .null : .string(receiptNumber)
        data["business_purpose"] = notes.isEmpty ? .null : .string(notes)

        do {
            try await client.from("meals").update(data).eq("id", value: mealId).eq("user_id", value: userId).execute()
            await loadAll(userId: userId)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    // MARK: - Delete Meal

    func deleteMeal(mealId: UUID, userId: UUID) async -> Bool {
        do {
            try await client.from("meals").delete().eq("id", value: mealId).eq("user_id", value: userId).execute()
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

    // MARK: - Delete Agency

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

    // MARK: - Year Filtering

    @Published var selectedYear: Int = Calendar.current.component(.year, from: Date())

    private var mealsForSelectedYear: [Meal] {
        let prefix = "\(selectedYear)-"
        return meals.filter { $0.date.hasPrefix(prefix) }
    }

    // MARK: - Computed

    var totalMealSpend: Decimal {
        mealsForSelectedYear.reduce(0) { $0 + $1.calculatedTotal }
    }

    var deductibleAmount: Decimal {
        let mealPct = TaxConstantsService.shared.constantsForYear(selectedYear).mealDeductionPct
        return totalMealSpend * mealPct
    }
}
