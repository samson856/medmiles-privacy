import SwiftUI
import Auth

struct IndividualExpenseTabView: View {
    @EnvironmentObject var authService: AuthService
    @StateObject private var viewModel = IndividualExpenseViewModel()

    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            Picker("View", selection: $selectedTab) {
                Text("Log Expense").tag(0)
                Text("History").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 24)
            .padding(.vertical, 8)

            if viewModel.isLoading && viewModel.expenses.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Group {
                    if selectedTab == 0 {
                        IndividualExpenseLogView(viewModel: viewModel)
                    } else {
                        IndividualExpenseHistoryView(viewModel: viewModel)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(Constants.Colors.background).ignoresSafeArea())
        .navigationTitle("Expenses")
        .task {
            guard let userId = authService.currentSession?.user.id else { return }
            await viewModel.loadAll(userId: userId)
        }
    }
}
