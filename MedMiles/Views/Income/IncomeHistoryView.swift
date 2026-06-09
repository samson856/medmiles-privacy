import SwiftUI
import Auth

struct IncomeHistoryView: View {
    @EnvironmentObject var authService: AuthService
    @ObservedObject var viewModel: IncomeViewModel
    @State private var searchText = ""

    private var filteredEntries: [Income] {
        guard !searchText.isEmpty else { return viewModel.incomeEntries }
        return viewModel.incomeEntries.filter { entry in
            let agencyName = entry.agencyId.flatMap { id in viewModel.agencies.first(where: { $0.id == id })?.name } ?? ""
            let notes = entry.notes ?? ""
            let contractId = entry.contractVisitId ?? ""
            return agencyName.localizedCaseInsensitiveContains(searchText)
                || notes.localizedCaseInsensitiveContains(searchText)
                || contractId.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        Group {
            if viewModel.incomeEntries.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "dollarsign.circle.fill")
                        .font(.largeTitle)
                        .foregroundColor(Color(.systemGray3))
                    Text("No income logged yet")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("Tap \"Log Income\" to get started")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    // Summary bar
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Total: $\(NSDecimalNumber(decimal: viewModel.totalGrossPay).doubleValue, specifier: "%.2f")")
                                .font(.subheadline)
                                .fontWeight(.bold)
                            Text("Net: $\(NSDecimalNumber(decimal: viewModel.totalNetPay).doubleValue, specifier: "%.2f")")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        HStack(spacing: 12) {
                            Label("\(viewModel.pendingCount) pending", systemImage: "clock")
                                .font(.caption2)
                                .foregroundColor(Color(Constants.Colors.warningAmber))
                            Label("\(viewModel.completedCount) paid", systemImage: "checkmark.circle")
                                .font(.caption2)
                                .foregroundColor(Color(Constants.Colors.successGreen))
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(Color(.systemBackground))

                    let grouped = MonthGrouping.group(filteredEntries, by: \.dateOfService)
                    List {
                        ForEach(grouped) { group in
                            Section(header: Text(group.label)) {
                                ForEach(group.items) { entry in
                                    NavigationLink(destination: IncomeEditView(income: entry, viewModel: viewModel)) {
                                        IncomeRow(income: entry, agencies: viewModel.agencies, visitTypes: viewModel.visitTypes)
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
        .searchable(text: $searchText, prompt: "Search income")
        .background(Color(Constants.Colors.background))
    }
}

struct IncomeRow: View {
    let income: Income
    let agencies: [Agency]
    let visitTypes: [VisitType]

    private var agencyName: String {
        guard let id = income.agencyId else { return "No agency" }
        return agencies.first(where: { $0.id == id })?.name ?? "Unknown"
    }

    private var visitTypeName: String {
        guard let id = income.visitTypeId else { return "" }
        return visitTypes.first(where: { $0.id == id })?.name ?? ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(agencyName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    if let city = income.destinationCity, !city.isEmpty {
                        Text(city)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    let netPay = income.grossPay - (income.taxSetAsideAmount ?? 0)
                    Text("Net Pay")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("$\(NSDecimalNumber(decimal: netPay).doubleValue, specifier: "%.2f")")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(Color(Constants.Colors.successGreen))

                    Text(income.displayDate, style: .date)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            HStack(spacing: 8) {
                if !visitTypeName.isEmpty {
                    Text(visitTypeName)
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color(Constants.Colors.mintTeal).opacity(0.15))
                        .foregroundColor(Color(Constants.Colors.mintTeal))
                        .cornerRadius(4)
                }

                // Status badge
                HStack(spacing: 4) {
                    Circle()
                        .fill(income.status == "completed"
                              ? Color(Constants.Colors.successGreen)
                              : Color(Constants.Colors.warningAmber))
                        .frame(width: 6, height: 6)
                    Text(income.status == "completed" ? "Completed" : "Pending")
                        .font(.caption2)
                        .foregroundColor(income.status == "completed"
                                         ? Color(Constants.Colors.successGreen)
                                         : Color(Constants.Colors.warningAmber))
                }

                if let setAside = income.taxSetAsideAmount, setAside > 0 {
                    Text("Tax: $\(NSDecimalNumber(decimal: setAside).doubleValue, specifier: "%.0f")")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
