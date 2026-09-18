//
//  AuthManager.swift
//  Unified Drive Assistant
//
//  ============================================================
//  AUTH BLOCK — LOCAL STAND-IN (Apple/Google sign-in parked for later)
//  ------------------------------------------------------------
//  A real Sign in with Apple + Google implementation was already
//  built (Apple via AuthenticationServices, Google via the
//  GoogleSignIn-iOS package) but is intentionally not wired in
//  right now — it needs a paid Apple Developer Program membership
//  (for the Apple capability) and a Google Cloud OAuth client ID,
//  neither of which are ready yet. Rather than leave a build that
//  needs an unadded package and unconfigured credentials, this is
//  a simple local stand-in so the app builds and runs immediately
//  with zero external setup.
//
//  BRINGING REAL SIGN-IN BACK: ask to have Apple/Google sign-in
//  re-added once you're ready to go online — the full
//  implementation (AuthManager + LoginView + app-launch wiring)
//  was already written once; re-adding it is a quick restore, not
//  new work. README.md section 26 "Setting up Sign in with Apple
//  and Google" still documents the external setup (paid Program
//  enrollment, Google Cloud OAuth client ID) needed before that
//  code can actually run.
//
//  What this stand-in does: stores a simple email -> uid map in
//  UserDefaults on-device. Signing in accepts any email + a
//  password of 6+ characters, creating a local "account" on first
//  use. No real identity verification — purely for unblocking
//  local development and testing.
//  ============================================================

import Foundation
import Combine

struct User {
    let uid: String
    let email: String?
}

@MainActor
final class AuthManager: ObservableObject {

    static let shared = AuthManager()

    @Published var currentUser: User?
    @Published var isSignedIn: Bool = false
    @Published var authErrorMessage: String?
    @Published var isBusy: Bool = false

    private let accountsKey = "uda_local_accounts"   // [email: uid]
    private let sessionKey = "uda_local_session_email"

    private init() {
        if let email = UserDefaults.standard.string(forKey: sessionKey),
           let uid = accounts()[email] {
            currentUser = User(uid: uid, email: email)
            isSignedIn = true
        }
    }

    /// Creates a new local account with email + password.
    /// (Password isn't stored or checked yet — see file header.)
    func signUp(email: String, password: String) async {
        isBusy = true
        authErrorMessage = nil
        defer { isBusy = false }

        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard isValidEmail(normalizedEmail) else {
            authErrorMessage = "That email address doesn't look right."
            return
        }
        guard password.count >= 6 else {
            authErrorMessage = "Password needs to be at least 6 characters."
            return
        }

        var accts = accounts()
        if accts[normalizedEmail] != nil {
            authErrorMessage = "An account already exists for that email — try signing in instead."
            return
        }
        let uid = UUID().uuidString
        accts[normalizedEmail] = uid
        saveAccounts(accts)
        startSession(uid: uid, email: normalizedEmail)

        AnalyticsService.shared.logSignUp(uid: uid, email: normalizedEmail)
    }

    /// Signs in to an existing local account — or creates one on first use,
    /// so a separate sign-up step isn't required while testing.
    func signIn(email: String, password: String) async {
        isBusy = true
        authErrorMessage = nil
        defer { isBusy = false }

        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard password.count >= 6 else {
            authErrorMessage = "Email or password is incorrect."
            return
        }

        var accts = accounts()
        let uid = accts[normalizedEmail] ?? {
            let newUid = UUID().uuidString
            accts[normalizedEmail] = newUid
            saveAccounts(accts)
            return newUid
        }()
        startSession(uid: uid, email: normalizedEmail)

        AnalyticsService.shared.logSignIn(uid: uid, email: normalizedEmail)
    }

    func signOut() {
        UserDefaults.standard.removeObject(forKey: sessionKey)
        currentUser = nil
        isSignedIn = false
    }

    // MARK: - Local storage helpers

    private func startSession(uid: String, email: String) {
        UserDefaults.standard.set(email, forKey: sessionKey)
        currentUser = User(uid: uid, email: email)
        isSignedIn = true
    }

    private func accounts() -> [String: String] {
        UserDefaults.standard.dictionary(forKey: accountsKey) as? [String: String] ?? [:]
    }

    private func saveAccounts(_ accts: [String: String]) {
        UserDefaults.standard.set(accts, forKey: accountsKey)
    }

    private func isValidEmail(_ email: String) -> Bool {
        email.contains("@") && email.contains(".") && !email.hasPrefix("@") && !email.hasSuffix("@")
    }
}
