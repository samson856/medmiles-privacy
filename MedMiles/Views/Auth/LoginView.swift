import SwiftUI

struct LoginView: View {
    @EnvironmentObject var authService: AuthService

    @State private var email = ""
    @State private var password = ""
    @State private var showSignUp = false
    @State private var errorMessage: String?
    @State private var isSigningIn = false
    @State private var showResetPassword = false
    @State private var resetEmail = ""
    @State private var resetMessage: String?
    @State private var isResetting = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Spacer()

                // Logo area
                VStack(spacing: 8) {
                    Image("medmiles-icon-final-graphite")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 80, height: 80)
                        .cornerRadius(16)

                    Text("MedMiles")
                        .font(.largeTitle.bold())
                        .foregroundColor(Color(Constants.Colors.graphite))

                    Text("Track it all. Keep what's yours.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.bottom, 48)

                // Form fields
                VStack(spacing: 16) {
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .textFieldStyle(.roundedBorder)

                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .textFieldStyle(.roundedBorder)
                }
                .padding(.horizontal, 24)

                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(Color(Constants.Colors.errorRed))
                        .padding(.top, 8)
                }

                // Sign in button
                Button {
                    signIn()
                } label: {
                    HStack {
                        if isSigningIn {
                            ProgressView()
                                .tint(.white)
                        }
                        Text("Sign In")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color(Constants.Colors.mintTeal))
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .disabled(email.isEmpty || password.isEmpty || isSigningIn)
                .padding(.horizontal, 24)
                .padding(.top, 24)

                // Forgot password
                Button("Forgot Password?") {
                    resetEmail = email
                    resetMessage = nil
                    showResetPassword = true
                }
                .font(.subheadline)
                .foregroundColor(Color(Constants.Colors.mintTeal))
                .padding(.top, 12)

                Spacer()

                // Sign up link
                HStack(spacing: 4) {
                    Text("Don't have an account?")
                        .foregroundColor(.secondary)
                    Button("Sign Up") {
                        showSignUp = true
                    }
                    .foregroundColor(Color(Constants.Colors.mintTeal))
                    .fontWeight(.medium)
                }
                .font(.subheadline)
                .padding(.bottom, 32)
            }
            .background(Color(Constants.Colors.background).ignoresSafeArea())
            .navigationDestination(isPresented: $showSignUp) {
                SignUpView()
            }
            .alert("Reset Password", isPresented: $showResetPassword) {
                TextField("Email", text: $resetEmail)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                Button("Send Reset Link") {
                    resetPassword()
                }
                .disabled(resetEmail.isEmpty || isResetting)
                Button("Cancel", role: .cancel) {}
            } message: {
                if let msg = resetMessage {
                    Text(msg)
                } else {
                    Text("Enter your email address and we'll send you a link to reset your password.")
                }
            }
        }
    }

    private func signIn() {
        errorMessage = nil
        isSigningIn = true
        Task {
            do {
                try await authService.signIn(email: email, password: password)
            } catch {
                errorMessage = error.localizedDescription
            }
            isSigningIn = false
        }
    }

    private func resetPassword() {
        isResetting = true
        Task {
            do {
                try await authService.resetPassword(email: resetEmail)
                resetMessage = "If an account exists with that email, a reset link has been sent."
                showResetPassword = true
            } catch {
                resetMessage = "Unable to send reset link. Please try again."
                showResetPassword = true
            }
            isResetting = false
        }
    }
}
