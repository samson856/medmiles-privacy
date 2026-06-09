import SwiftUI
import Auth

struct TripsTabView: View {
    @EnvironmentObject var authService: AuthService
    @StateObject private var viewModel = TripViewModel()

    @State private var selectedTab = 0  // 0 = Log, 1 = History

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Log / History toggle
                Picker("View", selection: $selectedTab) {
                    Text("Log Trip").tag(0)
                    Text("History").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 24)
                .padding(.vertical, 8)

                if viewModel.isLoading && viewModel.trips.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Group {
                        if selectedTab == 0 {
                            TripLogView(viewModel: viewModel)
                        } else {
                            TripHistoryView(viewModel: viewModel)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(Color(Constants.Colors.background).ignoresSafeArea())
            .navigationTitle("Trips")
            .navigationDestination(for: Trip.self) { trip in
                TripEditView(trip: trip, viewModel: viewModel)
            }
            .task {
                guard let userId = authService.currentSession?.user.id else { return }
                await viewModel.loadAll(userId: userId)
            }
        }
    }
}
