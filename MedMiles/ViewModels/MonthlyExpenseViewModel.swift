import Foundation
import Supabase
import Combine

@MainActor
final class MonthlyExpenseViewModel: ObservableObject {
    private let client = SupabaseService.shared.client

    @Published var currentExpense: MonthlyExpense?
    @Published var miscExpenses: [MiscExpense] = []
    @Published var allMonthlyExpenses: [MonthlyExpense] = []
    @Published var selectedMonth: Int
    @Published var selectedYear: Int
    @Published var isLoading = false
    @Published var isSaving = false
    @Published var errorMessage: String?

    // Editable field values keyed by DB column name
    @Published var fieldValues: [String: String] = [:]
    @Published var recurringFlags: [String: Bool] = [:]

    init() {
        let now = Calendar.current.component(.month, from: Date())
        let year = Calendar.current.component(.year, from: Date())
        selectedMonth = now
        selectedYear = year
    }

    // MARK: - Load

    func loadMonth(userId: UUID) async {
        isLoading = true
        defer { isLoading = false }

        do {
            // Load all months for the year (needed for recurring logic)
            let allExpenses: [MonthlyExpense] = try await client.from("monthly_expenses")
                .select()
                .eq("user_id", value: userId)
                .eq("tax_year", value: selectedYear)
                .order("month")
                .execute()
                .value
            allMonthlyExpenses = allExpenses

            // Find current month
            currentExpense = allExpenses.first(where: { $0.month == selectedMonth })

            // Load misc expenses for this month
            let misc: [MiscExpense] = try await client.from("misc_expenses")
                .select()
                .eq("user_id", value: userId)
                .eq("tax_year", value: selectedYear)
                .eq("month", value: selectedMonth)
                .order("date", ascending: false)
                .execute()
                .value
            miscExpenses = misc

            // Populate field values from loaded data
            populateFields()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func populateFields() {
        guard let exp = currentExpense else {
            fieldValues = [:]
            recurringFlags = [:]
            return
        }

        fieldValues = [
            "rent_mortgage": decToStr(exp.rentMortgage),
            "renters_homeowners_ins": decToStr(exp.rentersHomeownersIns),
            "real_estate_taxes": decToStr(exp.realEstateTaxes),
            "electric": decToStr(exp.electric),
            "water_sewer": decToStr(exp.waterSewer),
            "gas_propane": decToStr(exp.gasPropane),
            "garbage": decToStr(exp.garbage),
            "internet": decToStr(exp.internet),
            "hoa_dues": decToStr(exp.hoaDues),
            "cell_phone": decToStr(exp.cellPhone),
            "malpractice_liability": decToStr(exp.malpracticeLiability),
            "health_insurance": decToStr(exp.healthInsurance),
            "workers_comp": decToStr(exp.workersComp),
            "car_insurance": decToStr(exp.carInsurance),
            "car_payment_interest": decToStr(exp.carPaymentInterest),
            "maintenance_repairs": decToStr(exp.maintenanceRepairs),
            "professional_memberships": decToStr(exp.professionalMemberships),
            "software_subscriptions": decToStr(exp.softwareSubscriptions),
        ]

        recurringFlags = (exp.recurringFlags ?? [:]) as [String: Bool]
    }

    private func decToStr(_ val: Decimal) -> String {
        val == 0 ? "" : String(format: "%.2f", NSDecimalNumber(decimal: val).doubleValue)
    }

    // MARK: - Save

    func saveMonth(userId: UUID) async -> Bool {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        var data: [String: AnyJSON] = [
            "user_id": .string(userId.uuidString),
            "tax_year": .integer(selectedYear),
            "month": .integer(selectedMonth),
        ]

        // Add all field values (reject negative values)
        for (key, value) in fieldValues {
            let dec = max(Decimal(string: value) ?? 0, 0)
            data[key] = .double(NSDecimalNumber(decimal: dec).doubleValue)
        }

        // Add recurring flags
        var flagsDict: [String: AnyJSON] = [:]
        for (key, value) in recurringFlags {
            flagsDict[key] = .bool(value)
        }
        data["recurring_flags"] = .object(flagsDict)
        data["updated_at"] = .string(ISO8601DateFormatter().string(from: Date()))

        do {
            if currentExpense != nil {
                // Update existing
                try await client.from("monthly_expenses")
                    .update(data)
                    .eq("user_id", value: userId)
                    .eq("tax_year", value: selectedYear)
                    .eq("month", value: selectedMonth)
                    .execute()
            } else {
                // Insert new
                try await client.from("monthly_expenses")
                    .insert(data)
                    .execute()
            }

            // Handle recurring: copy toggled fields to remaining months
            await applyRecurring(userId: userId)

            await loadMonth(userId: userId)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func applyRecurring(userId: UUID) async {
        let activeRecurring = recurringFlags.filter { $0.value == true }
        guard !activeRecurring.isEmpty else { return }

        guard selectedMonth < 12 else {
            errorMessage = "No remaining months to copy to"
            return
        }

        for futureMonth in (selectedMonth + 1)...12 {
            var updateData: [String: AnyJSON] = [
                "updated_at": .string(ISO8601DateFormatter().string(from: Date()))
            ]

            for (key, _) in activeRecurring {
                if let value = fieldValues[key], let dec = Decimal(string: value) {
                    updateData[key] = .double(NSDecimalNumber(decimal: dec).doubleValue)
                }
            }

            // Check if month exists
            let existing = allMonthlyExpenses.first(where: { $0.month == futureMonth })
            do {
                if existing != nil {
                    try await client.from("monthly_expenses")
                        .update(updateData)
                        .eq("user_id", value: userId)
                        .eq("tax_year", value: selectedYear)
                        .eq("month", value: futureMonth)
                        .execute()
                } else {
                    // Create the month with recurring values
                    var insertData = updateData
                    insertData["user_id"] = .string(userId.uuidString)
                    insertData["tax_year"] = .integer(selectedYear)
                    insertData["month"] = .integer(futureMonth)
                    try await client.from("monthly_expenses")
                        .insert(insertData)
                        .execute()
                }
            } catch {
                // Non-critical: recurring copy to future month failed; current month is already saved
            }
        }
    }

    // MARK: - Misc Expenses

    func addMiscExpense(userId: UUID, date: Date, category: String, description: String,
                        amount: String) async -> UUID? {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withFullDate]

        guard let amtDec = Decimal(string: amount), amtDec > 0 else {
            errorMessage = "Please enter a valid amount"
            return nil
        }

        let data: [String: AnyJSON] = [
            "user_id": .string(userId.uuidString),
            "date": .string(dateFormatter.string(from: date)),
            "tax_year": .integer(selectedYear),
            "month": .integer(selectedMonth),
            "category": .string(category),
            "description": .string(description),
            "amount": .double(NSDecimalNumber(decimal: amtDec).doubleValue),
            "has_receipt": .bool(false),
        ]

        do {
            let result: MiscExpense = try await client.from("misc_expenses")
                .insert(data)
                .select()
                .single()
                .execute()
                .value
            await loadMonth(userId: userId)
            return result.id
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func updateMiscExpense(expenseId: UUID, userId: UUID, date: Date, category: String,
                           description: String, amount: String, hasReceipt: Bool) async -> Bool {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withFullDate]

        guard let amtDec = Decimal(string: amount), amtDec > 0 else {
            errorMessage = "Please enter a valid amount"
            return false
        }

        let data: [String: AnyJSON] = [
            "date": .string(dateFormatter.string(from: date)),
            "category": .string(category),
            "description": .string(description),
            "amount": .double(NSDecimalNumber(decimal: amtDec).doubleValue),
            "has_receipt": .bool(hasReceipt),
            "updated_at": .string(ISO8601DateFormatter().string(from: Date())),
        ]

        do {
            try await client.from("misc_expenses").update(data).eq("id", value: expenseId).eq("user_id", value: userId).execute()
            await loadMonth(userId: userId)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func deleteMiscExpense(expenseId: UUID, userId: UUID) async -> Bool {
        do {
            try await client.from("misc_expenses").delete().eq("id", value: expenseId).eq("user_id", value: userId).execute()
            await loadMonth(userId: userId)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    // MARK: - Computed

    var structuredTotal: Decimal {
        fieldValues.values.reduce(Decimal.zero) { $0 + (Decimal(string: $1) ?? 0) }
    }

    var miscTotal: Decimal {
        miscExpenses.reduce(Decimal.zero) { $0 + $1.amount }
    }

    var monthTotal: Decimal {
        structuredTotal + miscTotal
    }

    func hasData(for month: Int) -> Bool {
        allMonthlyExpenses.contains(where: { $0.month == month && $0.monthTotal > 0 })
    }

    static let monthNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                              "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
}
