import Foundation
import Supabase
import Combine

@MainActor
final class CredentialViewModel: ObservableObject {
    private let client = SupabaseService.shared.client

    @Published var credentials: [Credential] = []
    @Published var isLoading = false
    @Published var isSaving = false
    @Published var errorMessage: String?

    // MARK: - Load

    func loadAll(userId: UUID) async {
        isLoading = true
        defer { isLoading = false }

        do {
            let result: [Credential] = try await client.from("credentials")
                .select()
                .eq("user_id", value: userId)
                .order("expiration_date")
                .execute()
                .value
            credentials = result
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Add

    func addCredential(userId: UUID, credentialType: String, issuingBody: String,
                       issueDate: Date?, expirationDate: Date?,
                       alertPush: Bool, alertEmail: Bool,
                       notes: String) async -> UUID? {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withFullDate]

        var data: [String: AnyJSON] = [
            "user_id": .string(userId.uuidString),
            "credential_type": .string(credentialType),
            "alert_pref_push": .bool(alertPush),
            "alert_pref_email": .bool(alertEmail),
        ]

        if !issuingBody.isEmpty { data["issuing_body"] = .string(issuingBody) }
        if let issue = issueDate { data["issue_date"] = .string(dateFormatter.string(from: issue)) }
        if let exp = expirationDate { data["expiration_date"] = .string(dateFormatter.string(from: exp)) }
        if !notes.isEmpty { data["notes"] = .string(notes) }

        do {
            let result: Credential = try await client.from("credentials")
                .insert(data)
                .select()
                .single()
                .execute()
                .value
            await loadAll(userId: userId)
            return result.id
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    // MARK: - Update

    func updateCredential(credentialId: UUID, userId: UUID, credentialType: String,
                          issuingBody: String, issueDate: Date?, expirationDate: Date?,
                          alertPush: Bool, alertEmail: Bool,
                          notes: String) async -> Bool {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withFullDate]

        var data: [String: AnyJSON] = [
            "credential_type": .string(credentialType),
            "alert_pref_push": .bool(alertPush),
            "alert_pref_email": .bool(alertEmail),
            "updated_at": .string(ISO8601DateFormatter().string(from: Date())),
        ]

        data["issuing_body"] = issuingBody.isEmpty ? .null : .string(issuingBody)
        if let issue = issueDate {
            data["issue_date"] = .string(dateFormatter.string(from: issue))
        } else {
            data["issue_date"] = .null
        }
        if let exp = expirationDate {
            data["expiration_date"] = .string(dateFormatter.string(from: exp))
        } else {
            data["expiration_date"] = .null
        }
        data["notes"] = notes.isEmpty ? .null : .string(notes)

        do {
            try await client.from("credentials")
                .update(data)
                .eq("id", value: credentialId)
                .eq("user_id", value: userId)
                .execute()
            await loadAll(userId: userId)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    // MARK: - Delete

    func deleteCredential(credentialId: UUID, userId: UUID) async -> Bool {
        do {
            try await client.from("credentials")
                .delete()
                .eq("id", value: credentialId)
                .eq("user_id", value: userId)
                .execute()
            // Clean up local document files
            for filename in LocalStorageService.shared.receiptFilenames(for: credentialId) {
                LocalStorageService.shared.deleteReceipt(filename: filename)
            }
            await loadAll(userId: userId)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    // MARK: - Computed

    var activeCount: Int {
        credentials.filter { $0.computedStatus == "current" }.count
    }

    var expiringSoonCount: Int {
        credentials.filter { $0.computedStatus == "expiring_soon" }.count
    }

    var expiredCount: Int {
        credentials.filter { $0.computedStatus == "expired" }.count
    }
}
