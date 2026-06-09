import SwiftUI

struct SignUpView: View {
    @EnvironmentObject var authService: AuthService
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var errorMessage: String?
    @State private var isSigningUp = false

    private var passwordsMatch: Bool {
        !confirmPassword.isEmpty && password == confirmPassword
    }

    private var isFormValid: Bool {
        !email.isEmpty && password.count >= 6 && passwordsMatch
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 8) {
                Image("medmiles-icon-final-graphite")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 72, height: 72)
                    .cornerRadius(14)

                Text("Create Account")
                    .font(.title.bold())
                    .foregroundColor(Color(Constants.Colors.graphite))

                Text("You save lives. We save you money.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 40)

            VStack(spacing: 16) {
                TextField("Email", text: $email)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .textFieldStyle(.roundedBorder)

                SecureField("Password (min 6 characters)", text: $password)
                    .textContentType(.newPassword)
                    .textFieldStyle(.roundedBorder)

                SecureField("Confirm password", text: $confirmPassword)
                    .textContentType(.newPassword)
                    .textFieldStyle(.roundedBorder)

                if !confirmPassword.isEmpty && !passwordsMatch {
                    Text("Passwords don't match")
                        .font(.caption)
                        .foregroundColor(Color(Constants.Colors.errorRed))
                }
            }
            .padding(.horizontal, 24)

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(Color(Constants.Colors.errorRed))
                    .padding(.top, 8)
                    .padding(.horizontal, 24)
            }

            Button {
                signUp()
            } label: {
                HStack {
                    if isSigningUp {
                        ProgressView()
                            .tint(.white)
                    }
                    Text("Create Account")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color(Constants.Colors.mintTeal))
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .disabled(!isFormValid || isSigningUp)
            .padding(.horizontal, 24)
            .padding(.top, 24)

            Spacer()

            HStack(spacing: 4) {
                Text("Already have an account?")
                    .foregroundColor(.secondary)
                Button("Sign In") {
                    dismiss()
                }
                .foregroundColor(Color(Constants.Colors.mintTeal))
                .fontWeight(.medium)
            }
            .font(.subheadline)
            .padding(.bottom, 32)
        }
        .background(Color(Constants.Colors.background).ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .foregroundColor(Color(Constants.Colors.graphite))
                }
            }
        }
    }

    private func signUp() {
        errorMessage = nil
        isSigningUp = true
        Task {
            do {
                try await authService.signUp(email: email, password: password)
            } catch {
                errorMessage = error.localizedDescription
            }
            isSigningUp = false
        }
    }
}
