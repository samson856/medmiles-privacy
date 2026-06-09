import SwiftUI

struct AddAgencySheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    let onSave: (String) -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Add Client / Agency")
                    .font(.title3.bold())
                    .foregroundColor(Color(Constants.Colors.graphite))

                TextField("Agency name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal, 24)

                Button {
                    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        onSave(trimmed)
                        dismiss()
                    }
                } label: {
                    Text("Save")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? Color.gray.opacity(0.3)
                            : Color(Constants.Colors.mintTeal))
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .padding(.horizontal, 24)

                Spacer()
            }
            .padding(.top, 24)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.height(220)])
    }
}
