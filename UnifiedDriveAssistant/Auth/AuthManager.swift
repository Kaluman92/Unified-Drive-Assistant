//
//  AuthManager.swift
//  Unified Drive Assistant
//
//  ============================================================
//  AUTH BLOCK — SIGN IN WITH APPLE + GOOGLE
//  ------------------------------------------------------------
//  Replaces the old local email/password stand-in. Two ways in:
//
//  • Apple  — AuthenticationServices (SignInWithAppleButton in
//             LoginView calls prepareAppleRequest/handleAppleCompletion).
//  • Google — GoogleSignIn-iOS package (already added to the
//             Xcode project), via signInWithGoogle().
//
//  Sign-in is OPTIONAL — the app is fully usable without it (see
//  UnifiedDriveAssistantApp.swift). The signed-in user is kept in
//  the Keychain (not UserDefaults) so they stay signed in. On every launch the
//  stored session is re-checked with Apple/Google in the
//  background, and dropped if the person revoked access.
//
//  SETUP STILL NEEDED BEFORE THESE BUTTONS WORK:
//  1. Apple — the "Sign in with Apple" capability needs a PAID
//     Apple Developer Program membership. The entitlement file is
//     already wired up (Unified Drive Assistant.entitlements).
//  2. Google — create an iOS OAuth client ID in Google Cloud
//     Console, then replace BOTH placeholders in
//     Unified-Drive-Assistant-Info.plist: `GIDClientID` and the
//     reversed-client-ID URL scheme. Until then LoginView hides the
//     Google button (and signInWithGoogle() refuses rather than crash).
//
//  No backend: identity comes straight from Apple/Google and is
//  stored on-device only. Face ID locking lives separately in
//  Auth/BiometricLock.swift.
//  ============================================================

import Foundation
import Combine
import UIKit
import AuthenticationServices
import GoogleSignIn

enum AuthProvider: String, Codable {
    case apple
    case google

    var displayName: String {
        switch self {
        case .apple:  return "Apple"
        case .google: return "Google"
        }
    }
}

struct User: Codable, Equatable {
    let uid: String          // "apple:<id>" or "google:<id>" — stable per person per provider
    let email: String?
    let name: String?
    let provider: AuthProvider
}

@MainActor
final class AuthManager: ObservableObject {

    static let shared = AuthManager()

    @Published var currentUser: User?
    @Published var isSignedIn: Bool = false
    @Published var authErrorMessage: String?
    @Published var isBusy: Bool = false

    private let sessionKey = "current_user"
    private var revocationObserver: NSObjectProtocol?

    private init() {
        if let stored = loadStoredUser() {
            currentUser = stored
            isSignedIn = true
            Task { await validateStoredSession(stored) }
        }

        // Fires if the person removes this app under
        // Settings → Apple ID → Sign in with Apple while it's running.
        revocationObserver = NotificationCenter.default.addObserver(
            forName: ASAuthorizationAppleIDProvider.credentialRevokedNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                if self?.currentUser?.provider == .apple { self?.signOut() }
            }
        }
    }

    // MARK: - Apple

    func prepareAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        authErrorMessage = nil
        request.requestedScopes = [.fullName, .email]
    }

    func handleAppleCompletion(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code == .canceled { return }
            authErrorMessage = "Apple sign-in failed: \(error.localizedDescription)"

        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                authErrorMessage = "Apple sign-in returned an unexpected credential."
                return
            }
            let uid = "apple:\(credential.user)"
            // Apple only sends name + email on the very FIRST sign-in, so fall
            // back to the identity token's email claim, then to what we saved
            // last time.
            let cached = loadCachedProfile(uid: uid)
            let name = credential.fullName
                .map { PersonNameComponentsFormatter().string(from: $0) }
                .flatMap { $0.isEmpty ? nil : $0 }
            let user = User(
                uid: uid,
                email: credential.email ?? emailClaim(from: credential.identityToken) ?? cached?.email,
                name: name ?? cached?.name,
                provider: .apple
            )
            startSession(user)
        }
    }

    // MARK: - Google

    /// False until the real OAuth client ID replaces the placeholder in
    /// Unified-Drive-Assistant-Info.plist. GoogleSignIn throws an
    /// Objective-C exception (a crash) if you call it unconfigured.
    var isGoogleConfigured: Bool {
        guard let id = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String else { return false }
        return id.hasSuffix(".apps.googleusercontent.com") && !id.contains("YOUR")
    }

    func signInWithGoogle() async {
        authErrorMessage = nil
        guard isGoogleConfigured else {
            authErrorMessage = "Google sign-in isn't set up yet — add your OAuth client ID to Unified-Drive-Assistant-Info.plist."
            return
        }
        guard let presenter = Self.topViewController() else { return }

        isBusy = true
        defer { isBusy = false }
        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
            guard let googleID = result.user.userID else {
                authErrorMessage = "Google didn't return an account ID — please try again."
                return
            }
            startSession(User(
                uid: "google:\(googleID)",
                email: result.user.profile?.email,
                name: result.user.profile?.name,
                provider: .google
            ))
        } catch {
            if let googleError = error as? GIDSignInError, googleError.code == .canceled { return }
            authErrorMessage = "Google sign-in failed: \(error.localizedDescription)"
        }
    }

    /// Called from the app's onOpenURL — completes the Google browser round-trip.
    func handleOpenURL(_ url: URL) {
        _ = GIDSignIn.sharedInstance.handle(url)
    }

    // MARK: - Sign out / delete

    func signOut() {
        if currentUser?.provider == .google {
            GIDSignIn.sharedInstance.signOut()
        }
        KeychainHelper.delete(forKey: sessionKey, service: KeychainHelper.authService)
        currentUser = nil
        isSignedIn = false
    }

    /// App Store rule 5.1.1(v): apps with sign-in must offer account
    /// deletion. With no backend, "the account" is this device's sign-in
    /// data — this removes it and, for Google, revokes the app's access.
    /// Apple access is revoked by the person in Settings → Apple ID →
    /// Sign in with Apple (full server-side revocation needs a backend).
    func deleteAccount() async {
        guard let user = currentUser else { return }
        if user.provider == .google {
            try? await GIDSignIn.sharedInstance.disconnect()
        }
        KeychainHelper.delete(forKey: profileKey(uid: user.uid), service: KeychainHelper.authService)
        signOut()
    }

    // MARK: - Session storage

    private func startSession(_ user: User) {
        if let data = try? JSONEncoder().encode(user), let json = String(data: data, encoding: .utf8) {
            KeychainHelper.set(json, forKey: sessionKey, service: KeychainHelper.authService)
            // Kept after sign-out so Apple's missing-name-on-repeat-sign-in
            // doesn't lose the person's name/email.
            KeychainHelper.set(json, forKey: profileKey(uid: user.uid), service: KeychainHelper.authService)
        }
        currentUser = user
        isSignedIn = true
        AnalyticsService.shared.logSignIn(uid: user.uid, email: user.email ?? "")
    }

    private func loadStoredUser() -> User? {
        decodeUser(KeychainHelper.get(forKey: sessionKey, service: KeychainHelper.authService))
    }

    private func loadCachedProfile(uid: String) -> User? {
        decodeUser(KeychainHelper.get(forKey: profileKey(uid: uid), service: KeychainHelper.authService))
    }

    private func profileKey(uid: String) -> String { "profile_\(uid)" }

    private func decodeUser(_ json: String?) -> User? {
        guard let data = json?.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(User.self, from: data)
    }

    /// Re-checks a restored session with the provider. Only signs out when
    /// the provider says access is gone — never just because we're offline.
    private func validateStoredSession(_ user: User) async {
        switch user.provider {
        case .apple:
            let appleID = String(user.uid.dropFirst("apple:".count))
            let state = try? await ASAuthorizationAppleIDProvider().credentialState(forUserID: appleID)
            if state == .revoked || state == .notFound { signOut() }
        case .google:
            if GIDSignIn.sharedInstance.hasPreviousSignIn() {
                _ = try? await GIDSignIn.sharedInstance.restorePreviousSignIn()
            } else {
                signOut()
            }
        }
    }

    // MARK: - Helpers

    /// Apple's identity token is a JWT whose payload carries an `email`
    /// claim even on repeat sign-ins, when `credential.email` is nil.
    private func emailClaim(from identityToken: Data?) -> String? {
        guard let token = identityToken.flatMap({ String(data: $0, encoding: .utf8) }) else { return nil }
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 { payload += "=" }
        guard let data = Data(base64Encoded: payload),
              let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return claims["email"] as? String
    }

    private static func topViewController() -> UIViewController? {
        let root = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController
        var top = root
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
