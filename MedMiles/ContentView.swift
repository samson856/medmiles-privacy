import SwiftUI

struct ContentView: View {
    @EnvironmentObject var authService: AuthService

    var body: some View {
        TabView {
            // Home / Dashboard
            DashboardView()
                .tabItem {
                    Label("Home", systemImage: "square.grid.2x2.fill")
                }

            // Income
            IncomeTabView()
                .tabItem {
                    Label("Income", systemImage: "banknote.fill")
                }

            // Trips
            TripsTabView()
                .tabItem {
                    Label("Trips", systemImage: "road.lanes")
                }

            // Meals
            MealTabView()
                .tabItem {
                    Label("Meals", systemImage: "cup.and.heat.waves.fill")
                }
        }
        .tint(Color(Constants.Colors.mintTeal))
    }
}
