import SwiftUI
import StoreKit

struct SubscriptionView: View {
    @StateObject private var store = StoreKitService.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header
                VStack(spacing: 8) {
                    Image("medmiles-icon-final-graphite")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 64, height: 64)
                        .cornerRadius(14)

                    Text("MedMiles Pro")
                        .font(.title)
                        .fontWeight(.bold)

                    if store.isPro {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundColor(Color(Constants.Colors.successGreen))
                            Text("You're a Pro member")
                                .fontWeight(.medium)
                                .foregroundColor(Color(Constants.Colors.successGreen))
                        }
                        .padding(.top, 4)
                    } else {
                        Text("Unlock everything MedMiles has to offer")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.top, 24)

                // Feature comparison
                VStack(spacing: 0) {
                    FeatureRow(feature: "Monthly trips", free: "10/month", pro: "Unlimited")
                    Divider()
                    FeatureRow(feature: "Individual expenses", free: "5/month", pro: "Unlimited")
                    Divider()
                    FeatureRow(feature: "Credentials", free: "3 total", pro: "Unlimited")
                    Divider()
                    FeatureRow(feature: "Export reports", free: "—", pro: "✓")
                    Divider()
                    FeatureRow(feature: "Credential package", free: "—", pro: "✓")
                    Divider()
                    FeatureRow(feature: "Income tracking", free: "✓", pro: "✓")
                    Divider()
                    FeatureRow(feature: "Meal tracking", free: "✓", pro: "✓")
                    Divider()
                    FeatureRow(feature: "Monthly bills", free: "✓", pro: "✓")
                    Divider()
                    FeatureRow(feature: "Tax estimates", free: "✓", pro: "✓")
                }
                .background(Color(.systemBackground))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(.systemGray5), lineWidth: 1)
                )

                if !store.isPro {
                    // Pricing cards
                    VStack(spacing: 12) {
                        // Annual (best value)
                        if let annual = store.annualProduct {
                            Button {
                                Task { await store.purchase(annual) }
                            } label: {
                                VStack(spacing: 6) {
                                    HStack {
                                        Text("Annual")
                                            .font(.headline)
                                            .foregroundColor(.white)
                                        Spacer()
                                        Text("BEST VALUE")
                                            .font(.caption2)
                                            .fontWeight(.bold)
                                            .foregroundColor(Color(Constants.Colors.mintTeal))
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 3)
                                            .background(Color.white)
                                            .cornerRadius(4)
                                    }
                                    HStack {
                                        Text(annual.displayPrice + "/year")
                                            .font(.title3)
                                            .fontWeight(.bold)
                                            .foregroundColor(.white)
                                        Spacer()
                                        Text("Save 33%")
                                            .font(.caption)
                                            .foregroundColor(.white.opacity(0.8))
                                    }
                                }
                                .padding(16)
                                .background(Color(Constants.Colors.mintTeal))
                                .cornerRadius(12)
                            }
                        }

                        // Monthly
                        if let monthly = store.monthlyProduct {
                            Button {
                                Task { await store.purchase(monthly) }
                            } label: {
                                VStack(spacing: 6) {
                                    HStack {
                                        Text("Monthly")
                                            .font(.headline)
                                            .foregroundColor(Color(Constants.Colors.graphite))
                                        Spacer()
                                    }
                                    HStack {
                                        Text(monthly.displayPrice + "/month")
                                            .font(.title3)
                                            .fontWeight(.bold)
                                            .foregroundColor(Color(Constants.Colors.graphite))
                                        Spacer()
                                    }
                                }
                                .padding(16)
                                .background(Color(.systemBackground))
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color(.systemGray4), lineWidth: 1)
                                )
                            }
                        }

                        // Lifetime (one-time purchase)
                        if let lifetime = store.lifetimeProduct {
                            Button {
                                Task { await store.purchase(lifetime) }
                            } label: {
                                VStack(spacing: 6) {
                                    HStack {
                                        Text("Lifetime")
                                            .font(.headline)
                                            .foregroundColor(.white)
                                        Spacer()
                                        Text("ONE TIME")
                                            .font(.caption2)
                                            .fontWeight(.bold)
                                            .foregroundColor(Color(Constants.Colors.warningAmber))
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 3)
                                            .background(Color.white)
                                            .cornerRadius(4)
                                    }
                                    HStack {
                                        Text(lifetime.displayPrice + " once")
                                            .font(.title3)
                                            .fontWeight(.bold)
                                            .foregroundColor(.white)
                                        Spacer()
                                        Text("Pay once, keep forever")
                                            .font(.caption)
                                            .foregroundColor(.white.opacity(0.8))
                                    }
                                }
                                .padding(16)
                                .background(Color(Constants.Colors.warningAmber))
                                .cornerRadius(12)
                            }
                        }

                        // Products not loaded fallback
                        if store.products.isEmpty && !store.isLoading {
                            VStack(spacing: 12) {
                                Text("Unable to load subscription options.")
                                    .font(.headline)
                                    .foregroundColor(Color(Constants.Colors.graphite))
                                Text("Please check your internet connection and try again.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .padding()
                        }
                    }

                    // Restore purchases
                    Button {
                        Task { await store.restorePurchases() }
                    } label: {
                        Text("Restore Purchases")
                            .font(.subheadline)
                            .foregroundColor(Color(Constants.Colors.mintTeal))
                    }
                    .padding(.top, 8)
                }

                if let error = store.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(Color(Constants.Colors.errorRed))
                }

                // Manage subscription
                if store.isPro {
                    Button {
                        if let url = URL(string: "itms-apps://apps.apple.com/account/subscriptions") {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        HStack {
                            Spacer()
                            Text("Manage Subscription")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Spacer()
                        }
                        .padding(.vertical, 12)
                        .background(Color(.systemGray6))
                        .cornerRadius(10)
                    }
                    .foregroundColor(Color(Constants.Colors.mintTeal))
                }

                // Legal
                VStack(spacing: 8) {
                    Text("Subscriptions auto-renew unless cancelled at least 24 hours before the end of the current period. Payment will be charged to your Apple ID account. Manage or cancel anytime in your Apple ID settings. Lifetime purchase is a one-time, non-refundable payment that grants permanent access to all Pro features.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)

                    HStack(spacing: 16) {
                        if let url = URL(string: "https://northpeakcare-website.web.app/medmiles-privacy.html") {
                            Link("Privacy Policy", destination: url)
                                .font(.caption2)
                        }
                        if let url = URL(string: "https://northpeakcare-website.web.app/medmiles-terms.html") {
                            Link("Terms of Use", destination: url)
                                .font(.caption2)
                        }
                    }
                    .foregroundColor(Color(Constants.Colors.mintTeal))
                }
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .padding(.horizontal, 20)
        }
        .background(Color(Constants.Colors.background).ignoresSafeArea())
        .navigationTitle("Subscription")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if store.isLoading {
                ProgressView()
                    .padding()
                    .background(.ultraThinMaterial)
                    .cornerRadius(12)
            }
        }
    }
}

struct FeatureRow: View {
    let feature: String
    let free: String
    let pro: String

    var body: some View {
        HStack {
            Text(feature)
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(free)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 70)

            Text(pro)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(Color(Constants.Colors.mintTeal))
                .frame(width: 70)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
