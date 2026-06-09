import Foundation
import StoreKit
import Combine

@MainActor
final class StoreKitService: ObservableObject {
    static let shared = StoreKitService()

    // Product IDs — must match App Store Connect and StoreKit config
    static let proMonthlyID = "com.samcan.medmiles.monthly"
    static let proAnnualID = "com.samcan.medmiles.yearly"
    static let proLifetimeID = "com.samcan.medmiles.lifetime"

    @Published var products: [Product] = []
    @Published var purchasedProductIDs: Set<String> = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var backendProOverride = false

    var isPro: Bool {
        backendProOverride || !purchasedProductIDs.isEmpty
    }

    private var updateListener: Task<Void, Never>?

    init() {
        updateListener = listenForTransactions()
        Task { await loadProducts() }
        Task { await updatePurchasedProducts() }
    }

    deinit {
        updateListener?.cancel()
    }

    // MARK: - Load Products

    func loadProducts() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let storeProducts = try await Product.products(for: [
                Self.proMonthlyID,
                Self.proAnnualID,
                Self.proLifetimeID
            ])
            products = storeProducts.sorted { $0.price < $1.price }
        } catch {
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain {
                errorMessage = "Unable to connect. Check your internet connection and try again."
            } else {
                errorMessage = "Unable to load subscription options. Please try again later."
            }
        }
    }

    // MARK: - Purchase

    func purchase(_ product: Product) async -> Bool {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let result = try await product.purchase()

            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                await updatePurchasedProducts()
                return true

            case .pending:
                errorMessage = "Purchase is pending approval."
                return false

            case .userCancelled:
                return false

            @unknown default:
                return false
            }
        } catch {
            errorMessage = "Purchase failed: \(error.localizedDescription)"
            return false
        }
    }

    // MARK: - Restore Purchases

    func restorePurchases() async {
        isLoading = true
        defer { isLoading = false }

        do {
            try await AppStore.sync()
            await updatePurchasedProducts()
        } catch {
            errorMessage = "Unable to restore purchases."
        }
    }

    // MARK: - Check Current Entitlements

    func updatePurchasedProducts() async {
        var purchased: Set<String> = []

        for await result in Transaction.currentEntitlements {
            if let transaction = try? checkVerified(result) {
                purchased.insert(transaction.productID)
            }
        }

        purchasedProductIDs = purchased
    }

    // MARK: - Listen for Transaction Updates

    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached {
            for await result in Transaction.updates {
                if let transaction = try? self.checkVerified(result) {
                    await transaction.finish()
                    await self.updatePurchasedProducts()
                }
            }
        }
    }

    // MARK: - Verify Transaction

    private nonisolated func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreError.verificationFailed
        case .verified(let safe):
            return safe
        }
    }

    // MARK: - Free Tier Limits

    static let freeTripsPerMonth = 10
    static let freeMiscExpensesPerMonth = 5
    static let freeCredentials = 3

    func canLogTrip(currentMonthCount: Int) -> Bool {
        isPro || currentMonthCount < Self.freeTripsPerMonth
    }

    func canLogMiscExpense(currentMonthCount: Int) -> Bool {
        isPro || currentMonthCount < Self.freeMiscExpensesPerMonth
    }

    func canAddCredential(totalCount: Int) -> Bool {
        isPro || totalCount < Self.freeCredentials
    }

    static let freeExportsAllowed = 1

    private var currentYear: Int {
        Calendar.current.component(.year, from: Date())
    }

    /// The UserDefaults key for free-export tracking, scoped per user.
    private var freeExportKey: String {
        if let userId = currentUserId {
            return "freeExportUsedYear_\(userId.uuidString)"
        }
        return "freeExportUsedYear"
    }

    /// Set by AuthService on sign-in / session restore so export limit is per-user.
    var currentUserId: UUID?

    private var freeExportUsedYear: Int {
        get { UserDefaults.standard.integer(forKey: freeExportKey) }
        set { UserDefaults.standard.set(newValue, forKey: freeExportKey) }
    }

    func canExport() -> Bool {
        isPro || freeExportUsedYear != currentYear
    }

    func usesFreeExport() -> Bool {
        !isPro
    }

    func recordFreeExport() {
        if !isPro {
            freeExportUsedYear = currentYear
        }
    }

    /// Clear export tracking on sign-out so a different user starts fresh.
    func clearFreeExportTracking() {
        currentUserId = nil
    }

    // MARK: - Helper

    var monthlyProduct: Product? {
        products.first { $0.id == Self.proMonthlyID }
    }

    var annualProduct: Product? {
        products.first { $0.id == Self.proAnnualID }
    }

    var lifetimeProduct: Product? {
        products.first { $0.id == Self.proLifetimeID }
    }
}

enum StoreError: LocalizedError {
    case verificationFailed

    var errorDescription: String? {
        switch self {
        case .verificationFailed:
            return "Transaction verification failed."
        }
    }
}
