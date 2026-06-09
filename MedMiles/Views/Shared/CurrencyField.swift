import SwiftUI

struct CurrencyField: View {
    let label: String
    @Binding var value: String
    var placeholder: String = "$0.00"

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !label.isEmpty {
                Text(label)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(Color(Constants.Colors.graphite))
            }

            TextField(placeholder, text: $value)
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
                .frame(width: 100)
        }
    }
}

/// Compact version for inline use (e.g. trip expenses row)
struct CurrencyFieldCompact: View {
    let label: String
    @Binding var value: String
    var placeholder: String = "$0.00"

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(Color(Constants.Colors.graphite))
            Spacer()
            TextField(placeholder, text: $value)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
                .textFieldStyle(.roundedBorder)
        }
    }
}
