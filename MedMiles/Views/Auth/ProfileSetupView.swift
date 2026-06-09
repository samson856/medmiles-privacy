import SwiftUI

struct ProfileSetupView: View {
    @EnvironmentObject var authService: AuthService

    @State private var fullName = ""
    @State private var errorMessage: String?
    @State private var isSaving = false

    private var isFormValid: Bool {
        !fullName.isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 8) {
                        Image(systemName: "person.crop.circle.badge.plus")
                            .font(.largeTitle)
                            .foregroundColor(Color(Constants.Colors.mintTeal))

                        Text("Set Up Your Profile")
                            .font(.title2.bold())
                            .foregroundColor(Color(Constants.Colors.graphite))

                        Text("Tell us about your practice so we can tailor your experience.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 24)

                    // Form
                    VStack(spacing: 20) {
                        // Full Name
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Full Name")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(Color(Constants.Colors.graphite))

                            TextField("Your full name", text: $fullName)
                                .textContentType(.name)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                    .padding(.horizontal, 24)

                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(Color(Constants.Colors.errorRed))
                    }

                    // Save button
                    Button {
                        saveProfile()
                    } label: {
                        HStack {
                            if isSaving {
                                ProgressView()
                                    .tint(.white)
                            }
                            Text("Complete Setup")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(isFormValid ? Color(Constants.Colors.mintTeal) : Color.gray.opacity(0.3))
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .disabled(!isFormValid || isSaving)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
                }
            }
            .background(Color(Constants.Colors.background).ignoresSafeArea())
            .navigationBarBackButtonHidden(true)
        }
    }

    private func saveProfile() {
        isSaving = true
        errorMessage = nil
        Task {
            do {
                try await authService.updateProfile(
                    fullName: fullName,
                    profession: "",
                    specialty: "",
                    state: "",
                    filingStatus: ""
                )
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }
}
