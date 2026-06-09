import SwiftUI

extension View {
    /// Adds a keyboard accessory toolbar with an "X" button so numeric keyboards
    /// (decimalPad / numberPad have no return key) can always be dismissed.
    /// Apply this to any screen with number entry so users can back out easily.
    func dismissKeyboardButton() -> some View {
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button {
                    UIApplication.shared.sendAction(
                        #selector(UIResponder.resignFirstResponder),
                        to: nil, from: nil, for: nil
                    )
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .accessibilityLabel("Dismiss keyboard")
            }
        }
    }
}
