import SwiftUI

struct OnboardingView: View {
    @State private var currentPage = 0
    let onComplete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $currentPage) {
                // Page 1: Welcome with logo
                VStack(spacing: 20) {
                    Spacer()

                    // App logo
                    Image("medmiles-icon-final-graphite")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 100, height: 100)
                        .cornerRadius(20)

                    Text("Welcome to MedMiles")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(Color(Constants.Colors.graphite))
                        .multilineTextAlignment(.center)

                    Text("Track it all. Keep what's yours.")
                        .font(.title3)
                        .fontWeight(.medium)
                        .foregroundColor(Color(Constants.Colors.mintTeal))
                        .multilineTextAlignment(.center)

                    Text("Built for 1099 medical professionals — nurses, medics, PTs, RTs, and allied health workers.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)

                    Spacer()
                    Spacer()
                }
                .tag(0)

                // Page 2: Track Everything
                OnboardingPage(
                    icon: "square.grid.2x2.fill",
                    iconColor: Color(Constants.Colors.mintTeal),
                    title: "Track Everything",
                    subtitle: "All of your 1099 expenses and deductions in one place.",
                    description: "Log mileage, income, meals, and expenses. No more spreadsheets, no more guessing."
                )
                .tag(1)

                // Page 3: Tax Ready
                OnboardingPage(
                    icon: "doc.text.fill",
                    iconColor: Color(Constants.Colors.mintTeal),
                    title: "Stay Tax Ready",
                    subtitle: "Quarterly estimates. CPA-ready reports.",
                    description: "Know what you owe before tax time. Export everything your accountant needs in one tap."
                )
                .tag(2)

                // Page 4: Credentials
                OnboardingPage(
                    icon: "checkmark.shield.fill",
                    iconColor: Color(Constants.Colors.mintTeal),
                    title: "Never Miss a Renewal",
                    subtitle: "Your credential vault, always up to date.",
                    description: "Store licenses and certs, get expiration alerts, and generate credential packages for agencies."
                )
                .tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut, value: currentPage)

            // Page indicator dots
            HStack(spacing: 8) {
                ForEach(0..<4) { index in
                    Circle()
                        .fill(index == currentPage
                              ? Color(Constants.Colors.mintTeal)
                              : Color(.systemGray4))
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.bottom, 32)

            // Buttons
            VStack(spacing: 12) {
                if currentPage < 3 {
                    Button {
                        withAnimation {
                            currentPage += 1
                        }
                    } label: {
                        Text("Next")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color(Constants.Colors.mintTeal))
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }

                    Button {
                        onComplete()
                    } label: {
                        Text("Skip")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                } else {
                    Button {
                        onComplete()
                    } label: {
                        Text("Get Started")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color(Constants.Colors.mintTeal))
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 48)
        }
        .background(Color(Constants.Colors.background).ignoresSafeArea())
    }
}

struct OnboardingPage: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let description: String

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            // Icon
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.12))
                    .frame(width: 120, height: 120)

                Image(systemName: icon)
                    .font(.largeTitle)
                    .foregroundColor(iconColor)
            }

            // Title
            Text(title)
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(Color(Constants.Colors.graphite))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            // Subtitle
            Text(subtitle)
                .font(.title3)
                .fontWeight(.medium)
                .foregroundColor(Color(Constants.Colors.mintTeal))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            // Description
            Text(description)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()
            Spacer()
        }
    }
}
