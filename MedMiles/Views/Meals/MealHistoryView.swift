import SwiftUI
import Auth

struct MealHistoryView: View {
    @EnvironmentObject var authService: AuthService
    @ObservedObject var viewModel: MealViewModel

    var body: some View {
        Group {
            if viewModel.meals.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "fork.knife.circle.fill")
                        .font(.largeTitle)
                        .foregroundColor(Color(.systemGray3))
                    Text("No meals logged yet")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("Tap \"Log Meal\" to get started")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    // Summary bar
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Total: $\(NSDecimalNumber(decimal: viewModel.totalMealSpend).doubleValue, specifier: "%.2f")")
                                .font(.subheadline)
                                .fontWeight(.bold)
                        }
                        Spacer()
                        Text("Deductible: $\(NSDecimalNumber(decimal: viewModel.deductibleAmount).doubleValue, specifier: "%.2f")")
                            .font(.caption)
                            .foregroundColor(Color(Constants.Colors.successGreen))
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(Color(.systemBackground))

                    let grouped = MonthGrouping.group(viewModel.meals, by: \.date)
                    List {
                        ForEach(grouped) { group in
                            Section(header: Text(group.label)) {
                                ForEach(group.items) { meal in
                                    NavigationLink(destination: MealEditView(meal: meal, viewModel: viewModel)) {
                                        MealRow(meal: meal, agencies: viewModel.agencies)
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .refreshable {
                        guard let userId = authService.currentSession?.user.id else { return }
                        await viewModel.loadAll(userId: userId)
                    }
                }
            }
        }
        .background(Color(Constants.Colors.background))
    }
}

struct MealRow: View {
    let meal: Meal
    let agencies: [Agency]

    private var agencyName: String {
        guard let id = meal.agencyId else { return "No company" }
        return agencies.first(where: { $0.id == id })?.name ?? "Unknown"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(agencyName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text(meal.displayDate, style: .date)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text("$\(NSDecimalNumber(decimal: meal.calculatedTotal).doubleValue, specifier: "%.2f")")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(Color(Constants.Colors.mintTeal))
            }

            HStack(spacing: 12) {
                if meal.breakfast > 0 {
                    Label("B: $\(NSDecimalNumber(decimal: meal.breakfast).doubleValue, specifier: "%.0f")", systemImage: "sunrise")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                if meal.lunch > 0 {
                    Label("L: $\(NSDecimalNumber(decimal: meal.lunch).doubleValue, specifier: "%.0f")", systemImage: "sun.max")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                if meal.dinner > 0 {
                    Label("D: $\(NSDecimalNumber(decimal: meal.dinner).doubleValue, specifier: "%.0f")", systemImage: "moon")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                if let receipt = meal.receiptNumber, !receipt.isEmpty {
                    Label(receipt, systemImage: "doc.text")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
