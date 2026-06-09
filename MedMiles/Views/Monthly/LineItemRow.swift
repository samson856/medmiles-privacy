import SwiftUI

struct LineItemRow: View {
    let label: String
    let key: String
    @Binding var value: String
    @Binding var isRecurring: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(label)
                    .font(.subheadline)
                    .lineLimit(1)

                Spacer()

                TextField("$0.00", text: $value)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                    .font(.subheadline)
            }

            // "Copy to remaining months" button — only show when there's a value
            if let dec = Decimal(string: value), dec > 0 {
                Button {
                    isRecurring.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: isRecurring ? "checkmark.circle.fill" : "arrow.right.circle")
                            .font(.caption2)
                        Text(isRecurring ? "Copying to remaining months" : "Copy to remaining months")
                            .font(.caption2)
                    }
                    .foregroundColor(isRecurring ? Color(Constants.Colors.successGreen) : Color(Constants.Colors.mintTeal))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 2)
    }
}
