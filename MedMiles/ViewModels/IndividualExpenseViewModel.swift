import Foundation
import Supabase
import Combine

@MainActor
final class IndividualExpenseViewModel: ObservableObject {
    private let client = SupabaseService.shared.client

    @Published var expenses: [MiscExpense] = []
    @Published var agencies: [Agency] = []
    @Published var isLoading = false
    @Published var isSaving = false
    @Published var errorMessage: String?

    private let currentYear = Calendar.current.component(.year, from: Date())

    // MARK: - Load

    func loadAll(userId: UUID) async {
        isLoading = true
        defer { isLoading = false }

        do {
            let result: [MiscExpense] = try await client.from("misc_expenses")
                .select()
                .eq("user_id", value: userId)
                .eq("tax_year", value: currentYear)
                .order("date", ascending: false)
                .execute()
                .value
            expenses = result

            let agencyResult: [Agency] = try await client.from("agencies")
                .select()
                .eq("user_id", value: userId)
                .order("name")
                .execute()
                .value
            agencies = agencyResult
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Save

    func saveExpense(userId: UUID, date: Date, item: String, description: String,
                     category: String, agencyId: UUID?, amount: String) async -> UUID? {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withFullDate]

        guard let amtDec = Decimal(string: amount), amtDec > 0 else {
            errorMessage = "Please enter a valid amount"
            return nil
        }

        let month = Calendar.current.component(.month, from: date)

        // Combine item + description for the description field
        let fullDesc = description.isEmpty ? item : "\(item) — \(description)"

        var data: [String: AnyJSON] = [
            "user_id": .string(userId.uuidString),
            "date": .string(dateFormatter.string(from: date)),
            "tax_year": .integer(currentYear),
            "month": .integer(month),
            "category": .string(category),
            "description": .string(fullDesc),
            "amount": .double(NSDecimalNumber(decimal: amtDec).doubleValue),
            "has_receipt": .bool(false),
        ]

        if let aid = agencyId { data["agency_id"] = .string(aid.uuidString) }

        do {
            let result: MiscExpense = try await client.from("misc_expenses")
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

    /// Update the has_receipt flag after receipt files are linked to an expense.
    func markHasReceipt(expenseId: UUID, userId: UUID) async {
        let data: [String: AnyJSON] = [
            "has_receipt": .bool(true),
            "updated_at": .string(ISO8601DateFormatter().string(from: Date())),
        ]
        do {
            try await client.from("misc_expenses")
                .update(data)
                .eq("id", value: expenseId)
                .eq("user_id", value: userId)
                .execute()
        } catch {
            // Non-critical: receipt files are already saved locally
        }
    }

    // MARK: - Update

    func updateExpense(expenseId: UUID, userId: UUID, date: Date, item: String,
                       description: String, category: String, agencyId: UUID?,
                       amount: String, hasReceipt: Bool) async -> Bool {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withFullDate]

        guard let amtDec = Decimal(string: amount), amtDec > 0 else {
            errorMessage = "Please enter a valid amount"
            return false
        }

        let month = Calendar.current.component(.month, from: date)
        let fullDesc = description.isEmpty ? item : "\(item) — \(description)"

        let data: [String: AnyJSON] = [
            "date": .string(dateFormatter.string(from: date)),
            "month": .integer(month),
            "category": .string(category),
            "description": .string(fullDesc),
            "amount": .double(NSDecimalNumber(decimal: amtDec).doubleValue),
            "has_receipt": .bool(hasReceipt),
            "updated_at": .string(ISO8601DateFormatter().string(from: Date())),
        ]

        do {
            try await client.from("misc_expenses").update(data).eq("id", value: expenseId).eq("user_id", value: userId).execute()
            await loadAll(userId: userId)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    // MARK: - Delete

    func deleteExpense(expenseId: UUID, userId: UUID) async -> Bool {
        do {
            try await client.from("misc_expenses").delete().eq("id", value: expenseId).eq("user_id", value: userId).execute()
            for filename in LocalStorageService.shared.receiptFilenames(for: expenseId) {
                LocalStorageService.shared.deleteReceipt(filename: filename)
            }
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

    // MARK: - Computed

    var totalSpend: Decimal {
        expenses.reduce(Decimal.zero) { $0 + $1.amount }
    }
}
