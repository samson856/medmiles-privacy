import SwiftUI
import Auth

struct CredentialDetailView: View {
    @EnvironmentObject var authService: AuthService
    @ObservedObject var viewModel: CredentialViewModel
    @Environment(\.dismiss) private var dismiss

    let credential: Credential

    @State private var credentialType: String
    @State private var issuingBody: String
    @State private var hasIssueDate: Bool
    @State private var issueDate: Date
    @State private var hasExpirationDate: Bool
    @State private var expirationDate: Date
    @State private var alertPush: Bool
    @State private var alertEmail: Bool
    @State private var notes: String
    @State private var documentImages: [String]
    @State private var showDeleteConfirmation = false

    init(credential: Credential, viewModel: CredentialViewModel) {
        self.credential = credential
        self.viewModel = viewModel

        _credentialType = State(initialValue: credential.credentialType)
        _issuingBody = State(initialValue: credential.issuingBody ?? "")
        _hasIssueDate = State(initialValue: credential.issueDate != nil)
        _issueDate = State(initialValue: credential.displayIssueDate ?? Date())
        _hasExpirationDate = State(initialValue: credential.expirationDate != nil)
        _expirationDate = State(initialValue: credential.displayExpirationDate ?? Date())
        _alertPush = State(initialValue: credential.alertPrefPush ?? false)
        _alertEmail = State(initialValue: credential.alertPrefEmail ?? false)
        _notes = State(initialValue: credential.notes ?? "")
        _documentImages = State(initialValue: LocalStorageService.shared.receiptFilenames(for: credential.id))
    }

    var body: some View {
        Form {
            // Status header
            Section {
                HStack(spacing: 12) {
                    Circle()
                        .fill(Color(credential.statusColor))
                        .frame(width: 14, height: 14)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(credential.statusLabel)
                            .font(.headline)
                            .foregroundColor(Color(credential.statusColor))

                        if let days = credential.daysUntilExpiration {
                            if days > 0 {
                                Text("\(days) days until expiration")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } else if days == 0 {
                                Text("Expires today")
                                    .font(.caption)
                                    .foregroundColor(Color(Constants.Colors.errorRed))
                            } else {
                                Text("Expired \(abs(days)) days ago")
                                    .font(.caption)
                                    .foregroundColor(Color(Constants.Colors.errorRed))
                            }
                        }
                    }
                }
            }

            Section(header: Text("Credential Info")) {
                Picker("Type", selection: $credentialType) {
                    ForEach(Credential.commonTypes, id: \.self) { type in
                        Text(type).tag(type)
                    }
                    // Keep custom type if not in common list
                    if !Credential.commonTypes.contains(credentialType) {
                        Text(credentialType).tag(credentialType)
                    }
                }

                TextField("Issuing body", text: $issuingBody)
            }

            Section(header: Text("Dates")) {
                Toggle("Has issue date", isOn: $hasIssueDate)
                if hasIssueDate {
                    DatePicker("Issue Date", selection: $issueDate, displayedComponents: .date)
                }

                Toggle("Has expiration date", isOn: $hasExpirationDate)
                if hasExpirationDate {
                    DatePicker("Expiration Date", selection: $expirationDate, displayedComponents: .date)
                }
            }

            Section(header: Text("Document")) {
                ReceiptCaptureButton(
                    receiptFilenames: documentImages,
                    onCapture: { image in
                        if let filename = LocalStorageService.shared.saveReceipt(image: image, for: credential.id) {
                            documentImages.append(filename)
                        }
                    },
                    onDelete: { filename in
                        LocalStorageService.shared.deleteReceipt(filename: filename)
                        documentImages.removeAll { $0 == filename }
                    },
                    onFileImport: { url in
                        guard url.startAccessingSecurityScopedResource() else { return }
                        defer { url.stopAccessingSecurityScopedResource() }
                        if let filename = LocalStorageService.shared.saveFileFromURL(url, for: credential.id) {
                            documentImages.append(filename)
                        }
                    }
                )
            }

            if hasExpirationDate {
                Section(header: Text("Alert Preferences")) {
                    Toggle("Push notifications", isOn: $alertPush)
                    Toggle("Expiration reminder", isOn: $alertEmail)

                    HStack(spacing: 6) {
                        Image(systemName: "info.circle")
                            .font(.caption2)
                        Text("Alerts at 90, 60, and 30 days before expiration")
                            .font(.caption2)
                    }
                    .foregroundColor(.secondary)
                }
            }

            Section {
                TextField("Notes (optional)", text: $notes)
            }

            if let error = viewModel.errorMessage {
                Section {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(Color(Constants.Colors.errorRed))
                }
            }

            Section {
                Button {
                    updateCredential()
                } label: {
                    HStack {
                        Spacer()
                        if viewModel.isSaving {
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
                .disabled(viewModel.isSaving)
            }

            Section {
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    HStack {
                        Spacer()
                        Text("Delete Credential")
                        Spacer()
                    }
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(credential.credentialType)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Delete this credential?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                deleteCredential()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently remove the credential and any attached documents.")
        }
    }

    private func updateCredential() {
        guard let userId = authService.currentSession?.user.id else { return }
        Task {
            let success = await viewModel.updateCredential(
                credentialId: credential.id,
                userId: userId,
                credentialType: credentialType,
                issuingBody: issuingBody,
                issueDate: hasIssueDate ? issueDate : nil,
                expirationDate: hasExpirationDate ? expirationDate : nil,
                alertPush: alertPush,
                alertEmail: alertEmail,
                notes: notes
            )
            if success {
                dismiss()
            }
        }
    }

    private func deleteCredential() {
        guard let userId = authService.currentSession?.user.id else { return }
        Task {
            let success = await viewModel.deleteCredential(credentialId: credential.id, userId: userId)
            if success {
                dismiss()
            }
        }
    }
}
