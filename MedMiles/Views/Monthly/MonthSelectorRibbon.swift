import SwiftUI

struct MonthSelectorRibbon: View {
    @Binding var selectedMonth: Int
    let hasDataForMonth: (Int) -> Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(1...12, id: \.self) { month in
                        let isSelected = month == selectedMonth
                        let hasData = hasDataForMonth(month)

                        Button {
                            selectedMonth = month
                        } label: {
                            VStack(spacing: 4) {
                                Text(MonthlyExpenseViewModel.monthNames[month - 1])
                                    .font(.subheadline)
                                    .fontWeight(isSelected ? .bold : .regular)

                                if hasData && !isSelected {
                                    Circle()
                                        .fill(Color(Constants.Colors.successGreen))
                                        .frame(width: 6, height: 6)
                                } else {
                                    Circle()
                                        .fill(Color.clear)
                                        .frame(width: 6, height: 6)
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(isSelected ? Color(Constants.Colors.mintTeal) : Color(.systemGray6))
                            .foregroundColor(isSelected ? .white : .primary)
                            .cornerRadius(20)
                        }
                        .id(month)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .onAppear {
                proxy.scrollTo(selectedMonth, anchor: .center)
            }
            .onChange(of: selectedMonth) { _, newValue in
                withAnimation {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
    }
}
