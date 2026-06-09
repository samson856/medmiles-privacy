import Foundation
import StoreKit

/// Manages in-app review prompts at optimal moments.
/// Apple limits how often the prompt actually appears (~3 times per year),
/// so we gate requests to high-value moments to maximise the chance of a review.
@MainActor
final class ReviewService {
    static let shared = ReviewService()

    // MARK: - Keys
    private let tripCountKey   = "reviewTripCount"
    private let exportCountKey = "reviewExportCount"
    private let lastPromptKey  = "reviewLastPromptDate"

    // MARK: - Thresholds
    /// Prompt after this many trips saved
    private let tripThreshold = 5
    /// Prompt after first export
    private let exportThreshold = 1
    /// Minimum days between prompts (Apple enforces its own limit too)
    private let daysBetweenPrompts = 30

    private init() {}

    // MARK: - Public API

    /// Call after a trip is saved successfully.
    func recordTripSaved() {
        let count = UserDefaults.standard.integer(forKey: tripCountKey) + 1
        UserDefaults.standard.set(count, forKey: tripCountKey)

        if count == tripThreshold {
            requestReviewIfEligible()
        }
    }

    /// Call after an export completes successfully.
    func recordExportCompleted() {
        let count = UserDefaults.standard.integer(forKey: exportCountKey) + 1
        UserDefaults.standard.set(count, forKey: exportCountKey)

        if count == exportThreshold {
            requestReviewIfEligible()
        }
    }

    // MARK: - Private

    private func requestReviewIfEligible() {
        let now = Date()

        // Respect minimum interval between prompts
        if let lastPrompt = UserDefaults.standard.object(forKey: lastPromptKey) as? Date {
            let daysSince = Calendar.current.dateComponents([.day], from: lastPrompt, to: now).day ?? 0
            guard daysSince >= daysBetweenPrompts else { return }
        }

        UserDefaults.standard.set(now, forKey: lastPromptKey)

        // Use the current window scene to present the review prompt
        guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
        else { return }

        // Delay slightly so the user sees their success state first
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            SKStoreReviewController.requestReview(in: scene)
        }
    }
}
