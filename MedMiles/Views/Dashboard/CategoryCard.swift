import SwiftUI

struct CategoryCard: View {
    let title: String
    let value: String
    let icon: String
    var badge: String? = nil
    var badgeColor: Color = Color(Constants.Colors.mintTeal)

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(Color(Constants.Colors.mintTeal))
                .frame(width: 36, height: 36)
                .background(Color(Constants.Colors.mintTeal).opacity(0.12))
                .cornerRadius(8)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(value)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if let badge = badge {
                Text(badge)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(badgeColor.opacity(0.15))
                    .foregroundColor(badgeColor)
                    .cornerRadius(6)
            }

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(Color(.systemGray3))
        }
        .padding(14)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
    }
}
