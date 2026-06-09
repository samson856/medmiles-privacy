import SwiftUI
import Auth
import Supabase

struct SettingsView: View {
    @EnvironmentObject var authService: AuthService
    @Environment(\.dismiss) private var dismiss

    @State private var fullName = ""
    @State private var selectedState = ""
    @State private var filingStatus = ""
    @State private var taxSetAsidePct = ""
    @AppStorage("selectedTaxYear") private var selectedTaxYear = Calendar.current.component(.year, from: Date())
    @AppStorage("taxDeadlineRemindersEnabled") private var taxDeadlineRemindersEnabled = false
    @AppStorage("appearanceMode") private var appearanceMode: String = "system"
    @State private var isSaving = false
    @State private var showSavedConfirmation = false
    @State private var showSignOutConfirmation = false
    @State private var showDeleteAccountConfirmation = false
    @State private var deleteConfirmationText = ""
    @State private var isDeletingAccount = false
    @State private var deleteError: String?
    @State private var errorMessage: String?

    private var availableYears: [Int] {
        let current = Calendar.current.component(.year, from: Date())
        return Array((current - 2)...current).reversed()
    }

    var body: some View {
        Form {
            // Profile section
            Section(header: Text("Profile")) {
                HStack {
                    Text("Email")
                    Spacer()
                    Text(authService.currentProfile?.email ?? "")
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("Full Name")
                    Spacer()
                    TextField("Your name", text: $fullName)
                        .multilineTextAlignment(.trailing)
                }
            }

            // Tax preferences
            Section(header: Text("Tax Preferences")) {
                Picker("Tax Year", selection: $selectedTaxYear) {
                    ForEach(availableYears, id: \.self) { year in
                        Text(String(year)).tag(year)
                    }
                }

                Picker("State", selection: $selectedState) {
                    Text("Select").tag("")
                    ForEach(Profile.usStates, id: \.self) { state in
                        Text(state).tag(state)
                    }
                }

                Picker("Filing Status", selection: $filingStatus) {
                    Text("Select").tag("")
                    ForEach(Profile.filingStatuses, id: \.0) { status in
                        Text(status.1).tag(status.0)
                    }
                }

                HStack {
                    Text("Default Tax Set-Aside")
                    Spacer()
                    TextField("30", text: $taxSetAsidePct)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 60)
                    Text("%")
                        .foregroundColor(.secondary)
                }

                Text("This percentage is used as the default suggestion when logging income. Consult your CPA for a rate tailored to your situation.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Toggle("Tax Deadline Reminders", isOn: $taxDeadlineRemindersEnabled)
                    .onChange(of: taxDeadlineRemindersEnabled) { _, enabled in
                        NotificationService.shared.isRemindersEnabled = enabled
                        if enabled {
                            let currentYear = Calendar.current.component(.year, from: Date())
                            NotificationService.shared.scheduleQuarterlyReminders(for: currentYear)
                        } else {
                            NotificationService.shared.cancelAllReminders()
                        }
                    }

                Text("Receive reminders 30 days and 7 days before each quarterly estimated tax payment deadline.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Subscription
            Section(header: Text("Subscription")) {
                HStack {
                    Text("Current Plan")
                    Spacer()
                    Text((authService.currentProfile?.plan ?? "free").capitalized)
                        .foregroundColor(Color(Constants.Colors.mintTeal))
                        .fontWeight(.medium)
                }

                if authService.currentProfile?.plan == "free" || authService.currentProfile?.plan == nil {
                    Text("Upgrade to Pro for unlimited trips, expenses, credentials, and CPA-ready exports.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                NavigationLink(destination: SubscriptionView()) {
                    HStack {
                        Image(systemName: "star.fill")
                            .foregroundColor(Color(Constants.Colors.mintTeal))
                        Text(StoreKitService.shared.isPro ? "Manage Subscription" : "Upgrade to Pro")
                            .foregroundColor(.primary)
                        Spacer()
                        if StoreKitService.shared.isPro {
                            Text("Pro")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color(Constants.Colors.mintTeal))
                                .cornerRadius(4)
                        }
                    }
                }
            }

            // Save
            Section {
                Button {
                    saveProfile()
                } label: {
                    HStack {
                        Spacer()
                        if isSaving {
                            ProgressView().tint(.white)
                        }
                        Text("Save Changes")
                            .fontWeight(.semibold)
                        Spacer()
                    }
                    .padding(.vertical, 6)
                }
                .listRowBackground(Color(Constants.Colors.mintTeal))
                .foregroundColor(.white)
                .disabled(isSaving)
            }

            if let error = errorMessage {
                Section {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(Color(Constants.Colors.errorRed))
                }
            }

            // Feedback
            Section(header: Text("Feedback")) {
                Button {
                    sendFeedbackEmail()
                } label: {
                    HStack {
                        Image(systemName: "envelope.fill")
                            .foregroundColor(Color(Constants.Colors.mintTeal))
                        Text("Suggestions & Feedback")
                            .foregroundColor(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Text("Help us improve MedMiles. We read every message.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Appearance
            Section(header: Text("Appearance")) {
                Picker("Theme", selection: $appearanceMode) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                .pickerStyle(.segmented)

                Text("Choose how MedMiles appears. \"System\" follows your device settings.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // App info
            Section(header: Text("About")) {
                HStack {
                    Text("Version")
                    Spacer()
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("Tax Year")
                    Spacer()
                    Text(String(Calendar.current.component(.year, from: Date())))
                        .foregroundColor(.secondary)
                }

                if let url = URL(string: "https://northpeakcare-website.web.app/medmiles-privacy.html") {
                    Link(destination: url) {
                        HStack {
                            Text("Privacy Policy")
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                if let url = URL(string: "https://northpeakcare-website.web.app/medmiles-terms.html") {
                    Link(destination: url) {
                        HStack {
                            Text("Terms of Use")
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            // Sign out
            Section {
                Button(role: .destructive) {
                    showSignOutConfirmation = true
                } label: {
                    HStack {
                        Spacer()
                        Text("Sign Out")
                        Spacer()
                    }
                }
            }

            // Delete account
            Section {
                Button(role: .destructive) {
                    deleteConfirmationText = ""
                    deleteError = nil
                    showDeleteAccountConfirmation = true
                } label: {
                    HStack {
                        Spacer()
                        Text("Delete Account")
                        Spacer()
                    }
                }
            } footer: {
                Text("Permanently deletes your account and all data. This cannot be undone.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .dismissKeyboardButton()
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Sign out of MedMiles?", isPresented: $showSignOutConfirmation, titleVisibility: .visible) {
            Button("Sign Out", role: .destructive) {
                Task { try? await authService.signOut() }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Delete Account", isPresented: $showDeleteAccountConfirmation) {
            TextField("Type DELETE to confirm", text: $deleteConfirmationText)
                .autocapitalization(.none)
            Button("Delete My Account", role: .destructive) {
                guard deleteConfirmationText.uppercased() == "DELETE" else {
                    deleteError = "Please type DELETE to confirm."
                    showDeleteAccountConfirmation = true
                    return
                }
                isDeletingAccount = true
                Task {
                    do {
                        try await authService.deleteAccount()
                    } catch {
                        deleteError = error.localizedDescription
                    }
                    isDeletingAccount = false
                }
            }
            .disabled(deleteConfirmationText.uppercased() != "DELETE")
            Button("Cancel", role: .cancel) {}
        } message: {
            if let error = deleteError {
                Text(error)
            } else {
                Text("This will permanently delete your account and all data including trips, expenses, income records, credentials, and receipts. This cannot be undone.\n\nType DELETE to confirm.")
            }
        }
        .task {
            loadCurrentProfile()
        }
        .overlay {
            if showSavedConfirmation {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.largeTitle)
                        .foregroundColor(Color(Constants.Colors.successGreen))
                    Text("Settings Saved!")
                        .font(.headline)
                }
                .padding(32)
                .background(.ultraThinMaterial)
                .cornerRadius(16)
            }
        }
    }

    private func loadCurrentProfile() {
        guard let profile = authService.currentProfile else { return }
        fullName = profile.fullName ?? ""
        selectedState = profile.state ?? ""
        filingStatus = profile.filingStatus ?? ""

        if let pct = profile.taxSetAsidePct {
            taxSetAsidePct = "\(NSDecimalNumber(decimal: pct).doubleValue)"
        } else {
            taxSetAsidePct = "30"
        }

    }

    private func sendFeedbackEmail() {
        let email = "medmilesfeedback@gmail.com"
        let subject = "MedMiles Feedback"
        let profession = authService.currentProfile?.profession ?? "Unknown"
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let body = "\n\n---\nApp Version: \(appVersion)\nProfession: \(profession)\nPlatform: iOS"
        let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? subject
        let encodedBody = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? body
        if let url = URL(string: "mailto:\(email)?subject=\(encodedSubject)&body=\(encodedBody)") {
            UIApplication.shared.open(url)
        }
    }

    private func saveProfile() {
        isSaving = true
        errorMessage = nil

        Task {
            do {
                try await authService.updateProfile(
                    fullName: fullName,
                    profession: authService.currentProfile?.profession ?? "",
                    specialty: authService.currentProfile?.specialty ?? "",
                    state: selectedState,
                    filingStatus: filingStatus
                )

                // Update tax set-aside percentage
                if let pct = Decimal(string: taxSetAsidePct),
                   let userId = authService.currentSession?.user.id {
                    let updates: [String: String] = [
                        "tax_set_aside_pct": "\(pct)",
                        "updated_at": ISO8601DateFormatter().string(from: Date())
                    ]
                    try await SupabaseService.shared.client
                        .from("profiles")
                        .update(updates)
                        .eq("id", value: userId)
                        .execute()
                }

                showSavedConfirmation = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    showSavedConfirmation = false
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }
}
