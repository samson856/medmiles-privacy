import SwiftUI
import Auth

struct MealTabView: View {
    @EnvironmentObject var authService: AuthService
    @StateObject private var viewModel = MealViewModel()

    @State private var selectedTab = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("View", selection: $selectedTab) {
                    Text("Log Meal").tag(0)
                    Text("History").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 24)
                .padding(.vertical, 8)

                if viewModel.isLoading && viewModel.meals.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Group {
                        if selectedTab == 0 {
                            MealLogView(viewModel: viewModel)
                        } else {
                            MealHistoryView(viewModel: viewModel)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(Color(Constants.Colors.background).ignoresSafeArea())
            .navigationTitle("Meals")
            .task {
                guard let userId = authService.currentSession?.user.id else { return }
                await viewModel.loadAll(userId: userId)
            }
        }
    }
}
