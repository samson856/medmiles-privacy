import Foundation
import Supabase
import Combine

@MainActor
final class HomeOfficeViewModel: ObservableObject {
    private let client = SupabaseService.shared.client

    @Published var homeOffice: HomeOffice?
    @Published var isLoading = false
    @Published var isSaving = false
    @Published var errorMessage: String?

    var businessUsePct: Decimal {
        guard let total = homeOffice?.totalSqFt, total > 0,
              let office = homeOffice?.officeSqFt, office > 0 else { return 0 }
        let pct = (office / total) * 100
        return pct
    }

    func loadHomeOffice(userId: UUID, taxYear: Int = Calendar.current.component(.year, from: Date())) async {
        isLoading = true
        defer { isLoading = false }

        do {
            let results: [HomeOffice] = try await client.from("home_office")
                .select()
                .eq("user_id", value: userId)
                .eq("tax_year", value: taxYear)
                .execute()
                .value

            homeOffice = results.first
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveHomeOffice(userId: UUID, totalSqFt: String, officeSqFt: String,
                        activeMonths: [Bool], taxYear: Int = Calendar.current.component(.year, from: Date())) async -> Bool {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        guard let totalVal = Decimal(string: totalSqFt), totalVal > 0 else {
            errorMessage = "Please enter your total home square footage"
            return false
        }

        guard let officeVal = Decimal(string: officeSqFt), officeVal > 0 else {
            errorMessage = "Please enter your office square footage"
            return false
        }

        if officeVal > totalVal {
            errorMessage = "Office space cannot be larger than total home"
            return false
        }

        let calculatedPct = (officeVal / totalVal) * 100

        do {
            if let existing = homeOffice {
                // Update existing
                let updates: [String: AnyJSON] = [
                    "total_sq_ft": .double(NSDecimalNumber(decimal: totalVal).doubleValue),
                    "office_sq_ft": .double(NSDecimalNumber(decimal: officeVal).doubleValue),
                    "business_use_pct": .double(NSDecimalNumber(decimal: calculatedPct).doubleValue),
                    "active_months": .array(activeMonths.map { .bool($0) }),
                    "updated_at": .string(ISO8601DateFormatter().string(from: Date()))
                ]
                try await client.from("home_office")
                    .update(updates)
                    .eq("id", value: existing.id)
                    .eq("user_id", value: userId)
                    .execute()
            } else {
                // Insert new
                let data: [String: AnyJSON] = [
                    "user_id": .string(userId.uuidString),
                    "tax_year": .integer(taxYear),
                    "total_sq_ft": .double(NSDecimalNumber(decimal: totalVal).doubleValue),
                    "office_sq_ft": .double(NSDecimalNumber(decimal: officeVal).doubleValue),
                    "business_use_pct": .double(NSDecimalNumber(decimal: calculatedPct).doubleValue),
                    "active_months": .array(activeMonths.map { .bool($0) })
                ]
                try await client.from("home_office")
                    .insert(data)
                    .execute()
            }

            await loadHomeOffice(userId: userId, taxYear: taxYear)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
