import Foundation
import Supabase
import Combine

/// Fetches tax constants from Supabase, caches them locally in UserDefaults.
/// Falls back to cached values when offline, and to hardcoded defaults if nothing is cached.
@MainActor
final class TaxConstantsService: ObservableObject {
    static let shared = TaxConstantsService()

    private let client = SupabaseService.shared.client
    private let cacheKeyPrefix = "TaxConstants_"

    @Published var constants: [Int: TaxConstants] = [:]
    /// True when the current year's constants came from hardcoded defaults (not Supabase or cache)
    @Published var usingDefaults = false
    /// Set of years that were successfully fetched from Supabase
    private var fetchedFromServer: Set<Int> = []

    private init() {}

    /// Get constants for a specific tax year. Loads from memory, then cache, then defaults.
    func constantsForYear(_ year: Int) -> TaxConstants {
        if let cached = constants[year] {
            return cached
        }
        // Try loading from UserDefaults cache
        if let data = UserDefaults.standard.data(forKey: "\(cacheKeyPrefix)\(year)"),
           let decoded = try? JSONDecoder().decode(TaxConstants.self, from: data) {
            constants[year] = decoded
            return decoded
        }
        usingDefaults = true
        return TaxConstants.defaults(for: year)
    }

    /// Fetch constants from Supabase for the given tax year. Caches on success.
    func fetchConstants(for year: Int) async {
        do {
            let results: [TaxConstants] = try await client.from("tax_constants")
                .select()
                .eq("tax_year", value: year)
                .execute()
                .value

            if let fetched = results.first {
                constants[year] = fetched
                fetchedFromServer.insert(year)
                usingDefaults = false
                // Cache to UserDefaults
                if let data = try? JSONEncoder().encode(fetched) {
                    UserDefaults.standard.set(data, forKey: "\(cacheKeyPrefix)\(year)")
                }
            } else {
                // No row for this year in Supabase — mark as using defaults
                if !hasCachedValues(for: year) {
                    usingDefaults = true
                }
            }
        } catch {
            if !hasCachedValues(for: year) {
                usingDefaults = true
            }
        }
    }

    /// Force refresh — clears cache for the year and re-fetches from Supabase
    func refreshConstants(for year: Int) async {
        constants.removeValue(forKey: year)
        UserDefaults.standard.removeObject(forKey: "\(cacheKeyPrefix)\(year)")
        fetchedFromServer.remove(year)
        await fetchConstants(for: year)
    }

    /// Convenience: fetch current year's constants
    func fetchCurrentYear() async {
        let year = Calendar.current.component(.year, from: Date())
        await fetchConstants(for: year)
    }

    /// Check if we have cached (non-default) values for a year
    private func hasCachedValues(for year: Int) -> Bool {
        if constants[year] != nil { return true }
        return UserDefaults.standard.data(forKey: "\(cacheKeyPrefix)\(year)") != nil
    }
}
