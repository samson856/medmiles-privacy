import SwiftUI

@main
struct MedMilesApp: App {
    @StateObject private var authService = AuthService()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(authService)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var authService: AuthService
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("appearanceMode") private var appearanceMode: String = "system"

    private var colorScheme: ColorScheme? {
        switch appearanceMode {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    var body: some View {
        Group {
            if authService.isLoading {
                // Splash / loading
                VStack(spacing: 12) {
                    Image("medmiles-icon-final-graphite")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 80, height: 80)
                        .cornerRadius(16)
                    Text("MedMiles")
                        .font(.title.bold())
                        .foregroundColor(Color(Constants.Colors.graphite))
                    ProgressView()
                        .padding(.top, 8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(Constants.Colors.background).ignoresSafeArea())
            } else if !authService.isAuthenticated {
                LoginView()
            } else if !hasCompletedOnboarding {
                OnboardingView {
                    hasCompletedOnboarding = true
                }
            } else {
                ContentView()
            }
        }
        .preferredColorScheme(colorScheme)
        .task {
            // Only restore if not already authenticated — prevents iPad
            // scene lifecycle re-triggers from clobbering an active session
            if !authService.isAuthenticated {
                await authService.restoreSession()
            }
            await TaxConstantsService.shared.fetchCurrentYear()
            NotificationService.shared.requestPermission()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                // Silently refresh token when returning from background —
                // no isLoading flash, no splash screen
                Task { await authService.refreshSessionQuietly() }
            }
        }
    }
}
