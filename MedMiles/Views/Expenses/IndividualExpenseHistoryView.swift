import SwiftUI
import Auth

struct IndividualExpenseHistoryView: View {
    @EnvironmentObject var authService: AuthService
    @ObservedObject var viewModel: IndividualExpenseViewModel
    @State private var searchText = ""

    private var filteredExpenses: [MiscExpense] {
        guard !searchText.isEmpty else { return viewModel.expenses }
        return viewModel.expenses.filter { expense in
            let categoryLabel = MiscExpense.categoryLabel(for: expense.category)
            let description = expense.description ?? ""
            let agencyName = expense.agencyId.flatMap { id in viewModel.agencies.first(where: { $0.id == id })?.name } ?? ""
            return categoryLabel.localizedCaseInsensitiveContains(searchText)
                || description.localizedCaseInsensitiveContains(searchText)
                || agencyName.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        Group {
            if viewModel.expenses.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "bag.fill")
                        .font(.largeTitle)
                        .foregroundColor(Color(.systemGray3))
                    Text("No expenses logged yet")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("Tap \"Log Expense\" to get started")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    // Summary bar
                    HStack {
                        Text("Total: $\(NSDecimalNumber(decimal: viewModel.totalSpend).doubleValue, specifier: "%.2f")")
                            .font(.subheadline)
                            .fontWeight(.bold)
                        Spacer()
                        Text("\(viewModel.expenses.count) expense\(viewModel.expenses.count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(Color(.systemBackground))

                    let grouped = MonthGrouping.group(filteredExpenses, by: \.date)
                    List {
                        ForEach(grouped) { group in
                            Section(header: Text(group.label)) {
                                ForEach(group.items) { expense in
                                    NavigationLink(destination: IndividualExpenseEditView(expense: expense, viewModel: viewModel)) {
                                        IndividualExpenseRow(expense: expense, agencies: viewModel.agencies)
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
        .searchable(text: $searchText, prompt: "Search expenses")
        .background(Color(Constants.Colors.background))
    }
}

struct IndividualExpenseRow: View {
    let expense: MiscExpense
    let agencies: [Agency]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(expense.description ?? "Expense")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .lineLimit(1)

                    Text(expense.displayDate, style: .date)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text("$\(NSDecimalNumber(decimal: expense.amount).doubleValue, specifier: "%.2f")")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(Color(Constants.Colors.mintTeal))
            }

            HStack(spacing: 8) {
                Text(MiscExpense.categoryLabel(for: expense.category))
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color(Constants.Colors.mintTeal).opacity(0.15))
                    .foregroundColor(Color(Constants.Colors.mintTeal))
                    .cornerRadius(4)

                if expense.hasReceipt || !LocalStorageService.shared.receiptFilenames(for: expense.id).isEmpty {
                    Label("Receipt", systemImage: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundColor(Color(Constants.Colors.successGreen))
                } else if expense.amount >= 75 {
                    Label("No receipt", systemImage: "exclamationmark.circle")
                        .font(.caption2)
                        .foregroundColor(Color(Constants.Colors.errorRed))
                }
            }
        }
        .padding(.vertical, 4)
    }
}
