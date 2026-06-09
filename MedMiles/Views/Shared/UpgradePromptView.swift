import SwiftUI

struct UpgradePromptView: View {
    let title: String
    let message: String
    @Binding var isPresented: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer()

                Image(systemName: "lock.fill")
                    .font(.largeTitle)
                    .foregroundColor(Color(Constants.Colors.mintTeal))

                Text(title)
                    .font(.title2)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)

                Text(message)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                NavigationLink(destination: SubscriptionView()) {
                    Text("Upgrade to Pro")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color(Constants.Colors.mintTeal))
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .padding(.horizontal, 32)

                Button("Maybe Later") {
                    dismiss()
                }
                .font(.subheadline)
                .foregroundColor(.secondary)

                Spacer()
            }
            .background(Color(Constants.Colors.background).ignoresSafeArea())
        }
    }
}
