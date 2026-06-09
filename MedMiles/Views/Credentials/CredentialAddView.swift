import SwiftUI
import Auth

struct CredentialAddView: View {
    @EnvironmentObject var authService: AuthService
    @ObservedObject var viewModel: CredentialViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var credentialType = ""
    @State private var customType = ""
    @State private var issuingBody = ""
    @State private var hasIssueDate = false
    @State private var issueDate = Date()
    @State private var hasExpirationDate = false
    @State private var expirationDate = Date()
    @State private var alertPush = true
    @State private var alertEmail = true
    @State private var notes = ""
    @State private var documentImages: [String] = []
    @State private var showUpgradePrompt = false
    @State private var showUpgradeSheet = false

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Credential Info")) {
                    Picker("Type", selection: $credentialType) {
                        Text("Select type").tag("")
                        ForEach(Credential.commonTypes, id: \.self) { type in
                            Text(type).tag(type)
                        }
                    }

                    if credentialType == "Other" {
                        TextField("Credential name", text: $customType)
                    }

                    TextField("Issuing body (e.g. AHA, State DOH)", text: $issuingBody)
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
                            let tempId = UUID()
                            if let filename = LocalStorageService.shared.saveReceipt(image: image, for: tempId) {
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
                            let tempId = UUID()
                            if let filename = LocalStorageService.shared.saveFileFromURL(url, for: tempId) {
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
                        saveCredential()
                    } label: {
                        HStack {
                            Spacer()
                            if viewModel.isSaving {
                                ProgressView().tint(.white)
                            }
                            Text("Save Credential")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                        .padding(.vertical, 6)
                    }
                    .listRowBackground(Color(Constants.Colors.mintTeal))
                    .foregroundColor(.white)
                    .disabled(viewModel.isSaving || effectiveType.isEmpty)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Add Credential")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Credential Limit Reached", isPresented: $showUpgradePrompt) {
                Button("Upgrade to Pro") { showUpgradeSheet = true }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Free accounts can store up to \(StoreKitService.freeCredentials) credentials. Upgrade to Pro for unlimited credentials.")
            }
            .sheet(isPresented: $showUpgradeSheet) {
                NavigationStack {
                    SubscriptionView()
                }
            }
        }
    }

    private var effectiveType: String {
        credentialType == "Other" ? customType : credentialType
    }

    private func saveCredential() {
        // Check subscription limit
        if !StoreKitService.shared.canAddCredential(totalCount: viewModel.credentials.count) {
            showUpgradePrompt = true
            return
        }

        guard let userId = authService.currentSession?.user.id else { return }
        let type = effectiveType
        guard !type.isEmpty else { return }

        Task {
            let credId = await viewModel.addCredential(
                userId: userId,
                credentialType: type,
                issuingBody: issuingBody,
                issueDate: hasIssueDate ? issueDate : nil,
                expirationDate: hasExpirationDate ? expirationDate : nil,
                alertPush: alertPush,
                alertEmail: alertEmail,
                notes: notes
            )

            if let credId = credId {
                // Re-save documents under the credential's actual ID
                for oldFilename in documentImages {
                    let lowered = oldFilename.lowercased()
                    if lowered.hasSuffix(".pdf") || lowered.hasSuffix(".doc") || lowered.hasSuffix(".docx") {
                        // Non-image files: copy raw data to new ID
                        let oldURL = LocalStorageService.shared.receiptURL(filename: oldFilename)
                        if let data = try? Data(contentsOf: oldURL) {
                            let ext = (oldFilename as NSString).pathExtension
                            _ = LocalStorageService.shared.saveFile(data: data, for: credId, extension: ext)
                        }
                        LocalStorageService.shared.deleteReceipt(filename: oldFilename)
                    } else if let image = LocalStorageService.shared.loadReceipt(filename: oldFilename) {
                        // Image files: re-save as JPEG
                        _ = LocalStorageService.shared.saveReceipt(image: image, for: credId)
                        LocalStorageService.shared.deleteReceipt(filename: oldFilename)
                    }
                }
                dismiss()
            }
        }
    }
}
