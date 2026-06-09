import SwiftUI
import Auth

struct CredentialListView: View {
    @EnvironmentObject var authService: AuthService
    @StateObject private var viewModel = CredentialViewModel()

    @State private var showAddSheet = false
    @State private var isGenerating = false
    @State private var showShareSheet = false
    @State private var generatedPDFURL: URL?
    @State private var isSelectingCredentials = false
    @State private var selectedCredentialIDs: Set<UUID> = []

    var body: some View {
        VStack(spacing: 0) {
            // Summary bar
            if !viewModel.credentials.isEmpty {
                HStack(spacing: 12) {
                    Label("\(viewModel.activeCount) active", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(Color(Constants.Colors.successGreen))

                    if viewModel.expiringSoonCount > 0 {
                        Label("\(viewModel.expiringSoonCount) expiring", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundColor(Color(Constants.Colors.warningAmber))
                    }

                    if viewModel.expiredCount > 0 {
                        Label("\(viewModel.expiredCount) expired", systemImage: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(Color(Constants.Colors.errorRed))
                    }

                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Color(.systemBackground))
            }

            if viewModel.isLoading && viewModel.credentials.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.credentials.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text.fill")
                        .font(.largeTitle)
                        .foregroundColor(Color(.systemGray3))
                    Text("No credentials yet")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("Tap + to add your first license or certification")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    // Generate document button
                    Section {
                        if isSelectingCredentials {
                            // Select All / Deselect All
                            Button {
                                if selectedCredentialIDs.count == viewModel.credentials.count {
                                    selectedCredentialIDs.removeAll()
                                } else {
                                    selectedCredentialIDs = Set(viewModel.credentials.map { $0.id })
                                }
                            } label: {
                                HStack {
                                    Image(systemName: selectedCredentialIDs.count == viewModel.credentials.count ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(Color(Constants.Colors.mintTeal))
                                    Text(selectedCredentialIDs.count == viewModel.credentials.count ? "Deselect All" : "Select All")
                                        .font(.subheadline)
                                        .foregroundColor(.primary)
                                    Spacer()
                                    Text("\(selectedCredentialIDs.count) selected")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }

                            // Generate & Cancel buttons
                            HStack(spacing: 12) {
                                Button {
                                    isSelectingCredentials = false
                                    selectedCredentialIDs.removeAll()
                                } label: {
                                    Text("Cancel")
                                        .fontWeight(.medium)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 8)
                                }
                                .buttonStyle(.bordered)

                                Button {
                                    generateDocument()
                                } label: {
                                    HStack {
                                        if isGenerating {
                                            ProgressView().tint(.white)
                                                .padding(.trailing, 2)
                                        }
                                        Text("Generate (\(selectedCredentialIDs.count))")
                                            .fontWeight(.semibold)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(Color(Constants.Colors.mintTeal))
                                .disabled(selectedCredentialIDs.isEmpty || isGenerating)
                            }
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                        } else {
                            Button {
                                selectedCredentialIDs = Set(viewModel.credentials.map { $0.id })
                                isSelectingCredentials = true
                            } label: {
                                HStack {
                                    Spacer()
                                    Image(systemName: "doc.richtext")
                                    Text("Generate Credential Package")
                                        .fontWeight(.semibold)
                                    Spacer()
                                }
                                .padding(.vertical, 6)
                            }
                            .accessibilityLabel("Generate credential package")
                            .listRowBackground(Color(Constants.Colors.mintTeal))
                            .foregroundColor(.white)
                        }
                    }

                    // Credential list
                    Section {
                        ForEach(viewModel.credentials) { credential in
                            if isSelectingCredentials {
                                Button {
                                    if selectedCredentialIDs.contains(credential.id) {
                                        selectedCredentialIDs.remove(credential.id)
                                    } else {
                                        selectedCredentialIDs.insert(credential.id)
                                    }
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: selectedCredentialIDs.contains(credential.id) ? "checkmark.circle.fill" : "circle")
                                            .foregroundColor(selectedCredentialIDs.contains(credential.id) ? Color(Constants.Colors.mintTeal) : Color(.systemGray3))
                                            .font(.title3)
                                        CredentialRow(credential: credential)
                                    }
                                }
                                .listRowBackground(selectedCredentialIDs.contains(credential.id) ? Color(Constants.Colors.mintTeal).opacity(0.05) : Color(.systemBackground))
                            } else {
                                NavigationLink(destination: CredentialDetailView(credential: credential, viewModel: viewModel)) {
                                    CredentialRow(credential: credential)
                                }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .refreshable {
                    guard let userId = authService.currentSession?.user.id else { return }
                    await viewModel.loadAll(userId: userId)
                }
            }
        }
        .background(Color(Constants.Colors.background))
        .navigationTitle("Credentials")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus")
                        .foregroundColor(Color(Constants.Colors.mintTeal))
                }
                .accessibilityLabel("Add credential")
            }
        }
        .sheet(isPresented: $showAddSheet) {
            CredentialAddView(viewModel: viewModel)
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = generatedPDFURL {
                ShareSheet(items: [url])
            }
        }
        .task {
            guard let userId = authService.currentSession?.user.id else { return }
            await viewModel.loadAll(userId: userId)
        }
    }

    private func generateDocument() {
        isGenerating = true
        let credentials = viewModel.credentials.filter { selectedCredentialIDs.contains($0.id) }
        let userName = authService.currentProfile?.fullName ?? "MedMiles User"

        DispatchQueue.global(qos: .userInitiated).async {
            let pdf = CredentialPDFGenerator.generate(
                credentials: credentials,
                userName: userName
            )

            DispatchQueue.main.async {
                isGenerating = false
                isSelectingCredentials = false
                selectedCredentialIDs.removeAll()
                generatedPDFURL = pdf
                if pdf != nil {
                    showShareSheet = true
                }
            }
        }
    }
}

struct CredentialRow: View {
    let credential: Credential

    var body: some View {
        HStack(spacing: 12) {
            // Status dot
            Circle()
                .fill(Color(credential.statusColor))
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 4) {
                Text(credential.credentialType)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                if let issuer = credential.issuingBody, !issuer.isEmpty {
                    Text(issuer)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if let expDate = credential.displayExpirationDate {
                    Text("Exp: \(expDate, style: .date)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Status badge
            Text(credential.statusLabel)
                .font(.caption2)
                .fontWeight(.medium)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color(credential.statusColor).opacity(0.15))
                .foregroundColor(Color(credential.statusColor))
                .cornerRadius(6)
        }
        .padding(.vertical, 4)
    }
}
