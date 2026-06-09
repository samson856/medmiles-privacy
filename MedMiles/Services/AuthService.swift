import Foundation
import Combine
import Supabase

@MainActor
final class AuthService: ObservableObject {
    private let client = SupabaseService.shared.client
    private var authStateTask: Task<Void, Never>?

    @Published var currentSession: Session?
    @Published var currentProfile: Profile?
    @Published var isLoading = true   // Start true so splash shows while restoring
    @Published var needsProfileSetup = false

    var isAuthenticated: Bool {
        currentSession != nil
    }

    init() {
        // Listen for auth state changes (sign in, sign out, token refresh)
        authStateTask = Task { [weak self] in
            guard let self else { return }
            for await (event, session) in self.client.auth.authStateChanges {
                guard !Task.isCancelled else { break }
                switch event {
                case .signedIn, .tokenRefreshed:
                    if let session {
                        self.currentSession = session
                        LocalStorageService.shared.setCurrentUser(userId: session.user.id)
                        StoreKitService.shared.currentUserId = session.user.id
                    }
                case .signedOut:
                    self.currentSession = nil
                    self.currentProfile = nil
                    self.needsProfileSetup = false
                default:
                    break
                }
            }
        }
    }

    deinit {
        authStateTask?.cancel()
    }

    // MARK: - Session

    @MainActor
    func restoreSession() async {
        // If we already have an active session (e.g. just signed in),
        // don't clobber it — iPad scene lifecycle can re-trigger .task
        guard currentSession == nil else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            let session = try await client.auth.session
            currentSession = session
            LocalStorageService.shared.setCurrentUser(userId: session.user.id)
            StoreKitService.shared.currentUserId = session.user.id
            await fetchProfile(userId: session.user.id)

            // Re-schedule tax deadline reminders if enabled
            let currentYear = Calendar.current.component(.year, from: Date())
            NotificationService.shared.scheduleQuarterlyReminders(for: currentYear)
        } catch {
            // No stored session — user needs to log in
            currentSession = nil
            currentProfile = nil
        }
    }

    /// Silently refresh session when app returns from background.
    /// Does NOT touch isLoading — avoids flashing the splash screen.
    @MainActor
    func refreshSessionQuietly() async {
        guard currentSession != nil else { return } // nothing to refresh
        do {
            let session = try await client.auth.session
            currentSession = session
        } catch {
            // Token refresh failed — don't kick user out immediately,
            // the auth state listener will handle .signedOut if truly expired
        }
    }

    // MARK: - Sign Up

    @MainActor
    func signUp(email: String, password: String) async throws {
        // Don't set isLoading here — it causes the root view to flash back to splash screen

        let response = try await client.auth.signUp(email: email, password: password)
        currentSession = response.session

        if let userId = response.session?.user.id {
            LocalStorageService.shared.setCurrentUser(userId: userId)
            StoreKitService.shared.currentUserId = userId
            try await createProfile(userId: userId, email: email)
            needsProfileSetup = true

            // Schedule tax deadline reminders if enabled
            let currentYear = Calendar.current.component(.year, from: Date())
            NotificationService.shared.scheduleQuarterlyReminders(for: currentYear)
        }
    }

    // MARK: - Sign In

    @MainActor
    func signIn(email: String, password: String) async throws {
        // Don't set isLoading here — it causes the root view to flash back to splash screen
        // The LoginView has its own loading state via the button's ProgressView

        let session = try await client.auth.signIn(email: email, password: password)
        currentSession = session
        LocalStorageService.shared.setCurrentUser(userId: session.user.id)
        StoreKitService.shared.currentUserId = session.user.id
        await fetchProfile(userId: session.user.id)

        // Schedule tax deadline reminders if enabled
        let currentYear = Calendar.current.component(.year, from: Date())
        NotificationService.shared.scheduleQuarterlyReminders(for: currentYear)
    }

    // MARK: - Password Reset

    @MainActor
    func resetPassword(email: String) async throws {
        try await client.auth.resetPasswordForEmail(email)
    }

    // MARK: - Sign Out

    @MainActor
    func signOut() async throws {
        try await client.auth.signOut()
        LocalStorageService.shared.clearCurrentUser()
        StoreKitService.shared.clearFreeExportTracking()
        currentSession = nil
        currentProfile = nil
        needsProfileSetup = false
        UserDefaults.standard.set(false, forKey: "hasCompletedOnboarding")
    }

    // MARK: - Delete Account

    /// Permanently deletes the user's account and all associated data.
    /// 1. Calls Supabase RPC to delete the auth user (CASCADE removes all table data)
    /// 2. Clears local receipt files
    /// 3. Clears all local state and signs out
    @MainActor
    func deleteAccount() async throws {
        guard currentSession?.user.id != nil else {
            throw NSError(domain: "AuthService", code: 1, userInfo: [NSLocalizedDescriptionKey: "No active session"])
        }

        // Delete the auth user via Supabase RPC (CASCADE deletes all user data)
        try await client.rpc("delete_own_account").execute()

        // Clear all local receipt files
        LocalStorageService.shared.deleteAllReceipts()
        LocalStorageService.shared.clearCurrentUser()

        // Clear subscription tracking
        StoreKitService.shared.clearFreeExportTracking()

        // Clear all UserDefaults
        UserDefaults.standard.set(false, forKey: "hasCompletedOnboarding")
        UserDefaults.standard.removeObject(forKey: "taxDeadlineRemindersEnabled")

        // Remove pending notifications
        NotificationService.shared.removeAllReminders()

        // Clear auth state
        currentSession = nil
        currentProfile = nil
        needsProfileSetup = false
    }

    // MARK: - Profile

    @MainActor
    func fetchProfile(userId: UUID) async {
        do {
            let profile: Profile = try await client.from("profiles")
                .select()
                .eq("id", value: userId)
                .single()
                .execute()
                .value

            currentProfile = profile
            StoreKitService.shared.backendProOverride = profile.isPro ?? false
            needsProfileSetup = (profile.fullName == nil || profile.profession == nil)
        } catch {
            // Profile doesn't exist yet — create it
            if let email = currentSession?.user.email {
                try? await createProfile(userId: userId, email: email)
            }
            needsProfileSetup = true
        }
    }

    @MainActor
    func createProfile(userId: UUID, email: String) async throws {
        let newProfile: [String: String] = [
            "id": userId.uuidString,
            "email": email
        ]
        try await client.from("profiles")
            .insert(newProfile)
            .execute()
    }

    @MainActor
    func updateProfile(fullName: String, profession: String, specialty: String, state: String, filingStatus: String) async throws {
        guard let userId = currentSession?.user.id else { return }

        let updates: [String: String] = [
            "full_name": fullName,
            "profession": profession,
            "specialty": specialty,
            "state": state,
            "filing_status": filingStatus,
            "updated_at": ISO8601DateFormatter().string(from: Date())
        ]

        try await client.from("profiles")
            .update(updates)
            .eq("id", value: userId)
            .execute()

        await fetchProfile(userId: userId)
        needsProfileSetup = false
    }
}
