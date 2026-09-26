//
//  SettingsView.swift
//  Unified Drive Assistant
//
//  ============================================================
//  SETTINGS BLOCK
//  ------------------------------------------------------------
//  All app-level settings live here: Pro subscription, AI
//  assistant, security (Face ID), appearance (light/dark),
//  feedback, and account. Each section owns its
//  own piece of state (ThemeManager, AIAssistantService,
//  AuthManager) — this view just lays them out.
//  ============================================================

import SwiftUI
import StoreKit

struct SettingsView: View {
    @StateObject private var assistant = AIAssistantService.shared
    @StateObject private var auth = AuthManager.shared
    @StateObject private var theme = ThemeManager.shared
    @StateObject private var geofence = SiteGeofenceManager.shared
    @StateObject private var pro = ProStore.shared
    @StateObject private var lock = BiometricLock.shared
    @State private var showReviewSheet = false
    @State private var showPaywall = false
    @State private var showExpert = false
    @State private var showManageSubscription = false
    @State private var confirmDeleteAccount = false
    @State private var showSignIn = false

    var body: some View {
        List {
            Section {
                if pro.isPro {
                    Label("Pro · \(pro.planName ?? "Active")", systemImage: "checkmark.seal.fill")
                        .foregroundColor(UDATheme.accentPressed)
                        .font(UDATheme.bodyBold)
                    Button {
                        showExpert = true
                    } label: {
                        Label("Ask a human expert", systemImage: "person.fill.questionmark")
                    }
                    .foregroundColor(UDATheme.accentPressed)
                    Button("Manage subscription") {
                        showManageSubscription = true
                    }
                    .foregroundColor(UDATheme.textSecondary)
                } else {
                    Button {
                        showPaywall = true
                    } label: {
                        Label("Upgrade to Pro", systemImage: "person.badge.shield.checkmark.fill")
                            .font(UDATheme.bodyBold)
                    }
                    .foregroundColor(UDATheme.logoMagenta)
                    Text("Unlocks priority help from a human drives engineer — send the fault, photos and site details, and get a reply by email.")
                        .font(UDATheme.caption)
                        .foregroundColor(UDATheme.textSecondary)
                    Button("Restore purchases") {
                        Task { await pro.restorePurchases() }
                    }
                    .foregroundColor(UDATheme.textSecondary)
                }
                if let message = pro.errorMessage {
                    Text(message)
                        .font(UDATheme.caption)
                        .foregroundColor(UDATheme.danger)
                }
            } header: {
                Text("Pro")
            }
            .listRowBackground(UDATheme.surface)

            Section("Assistant") {
                Toggle("AI-guided troubleshooting", isOn: $assistant.isEnabled)
                    .tint(UDATheme.accent)
                Text("Adds optional plain-language guidance on request. Cause/Remedy fields are always shown regardless.")
                    .font(UDATheme.caption)
                    .foregroundColor(UDATheme.textSecondary)

                if assistant.isEnabled {
                    Picker("AI Model", selection: $assistant.selectedProvider) {
                        ForEach(AIProvider.allCases) { provider in
                            Text(provider.displayName).tag(provider)
                        }
                    }
                    .pickerStyle(.segmented)

                    SecureField("Your \(assistant.selectedProvider.displayName) API key",
                                text: Binding(
                                    get: { assistant.apiKey },
                                    set: { assistant.apiKey = $0 }
                                ))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    Text("Bring your own key — every user provides their own personal \(assistant.selectedProvider.displayName) API key from \(assistant.selectedProvider.keySourceDescription). This app has no shared or built-in key, and your key is stored securely on this device only (Keychain), never sent anywhere except directly to \(assistant.selectedProvider.displayName)'s own servers.")
                        .font(UDATheme.caption)
                        .foregroundColor(UDATheme.textSecondary)
                }
            }
            .listRowBackground(UDATheme.surface)

            Section("Privacy") {
                // App Store guideline 5.1.1(i): the policy must be easy to
                // find inside the app, not only in App Store Connect.
                Link(destination: ProStore.privacyURL) {
                    Label("Privacy Policy", systemImage: "hand.raised")
                }
                .foregroundColor(UDATheme.accentPressed)
                // Deliberately no in-app permission status/toggle here — iOS's
                // own Settings is the single source of truth for what's
                // allowed (Never / Ask / While Using / Always). This app just
                // reads and respects whatever's set there, rather than
                // duplicating that control inside the app.
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Label("Open iPhone Location Settings", systemImage: "location")
                }
                .foregroundColor(UDATheme.accentPressed)
                Text("Location for this app is controlled entirely in iPhone Settings → Privacy & Security → Location Services → Unified Drive Assistant. Choose \"While Using the App\" to use \"Save as site visit\" and nearby-site alerts. By default, never used to track movement in the background.")
                    .font(UDATheme.caption)
                    .foregroundColor(UDATheme.textSecondary)

                Toggle("Background site alerts", isOn: Binding(
                    get: { geofence.isEnabled },
                    set: { newValue in
                        newValue ? geofence.enable() : geofence.disable()
                    }
                ))
                .tint(UDATheme.accent)
                Text("Get a local notification when you physically enter the area of a site you've saved fault history for — even with the app closed. This is the one exception to \"when in use only\" above: turning this on asks iOS to upgrade to \"Always\" location access, used only to watch for entry into your own saved site locations (up to the most recent 20 — an iOS system limit), not to track your movement generally.")
                    .font(UDATheme.caption)
                    .foregroundColor(UDATheme.textSecondary)
            }
            .listRowBackground(UDATheme.surface)

            Section("Security") {
                Toggle("Require \(lock.methodName)", isOn: Binding(
                    get: { lock.isEnabled },
                    set: { newValue in Task { await lock.setEnabled(newValue) } }
                ))
                .tint(UDATheme.accent)
                .disabled(!lock.isAvailable)
                if let message = lock.errorMessage {
                    Text(message)
                        .font(UDATheme.caption)
                        .foregroundColor(UDATheme.danger)
                }
                Text(lock.isAvailable
                     ? "Locks the app every time it's opened or brought back from the background. Your device passcode always works as a backup."
                     : "Set up Face ID or a passcode in iPhone Settings to use this.")
                    .font(UDATheme.caption)
                    .foregroundColor(UDATheme.textSecondary)
            }
            .listRowBackground(UDATheme.surface)

            Section("Appearance") {
                Picker("Appearance", selection: $theme.mode) {
                    ForEach(AppColorMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                Text("\"System\" follows your device's own Light/Dark Mode setting.")
                    .font(UDATheme.caption)
                    .foregroundColor(UDATheme.textSecondary)
            }
            .listRowBackground(UDATheme.surface)

            Section("Feedback") {
                Button {
                    showReviewSheet = true
                } label: {
                    Label("Send a review", systemImage: "envelope")
                }
                .foregroundColor(UDATheme.accentPressed)
                Text("Sends a short review straight to us by email.")
                    .font(UDATheme.caption)
                    .foregroundColor(UDATheme.textSecondary)
            }
            .listRowBackground(UDATheme.surface)

            Section("Account") {
                if let user = auth.currentUser {
                    VStack(alignment: .leading, spacing: 2) {
                        if let name = user.name {
                            Text(name).foregroundColor(UDATheme.textPrimary)
                        }
                        Text(user.email ?? "No email shared")
                            .foregroundColor(UDATheme.textSecondary)
                        Text("Signed in with \(user.provider.displayName)")
                            .font(UDATheme.caption)
                            .foregroundColor(UDATheme.textSecondary)
                    }
                }
                if auth.isSignedIn {
                    Button("Log out", role: .destructive) {
                        auth.signOut()
                    }
                    Button("Delete account", role: .destructive) {
                        confirmDeleteAccount = true
                    }
                } else {
                    Button {
                        showSignIn = true
                    } label: {
                        Label("Sign in with Apple or Google", systemImage: "person.crop.circle")
                    }
                    .foregroundColor(UDATheme.accentPressed)
                    Text("Optional — everything works without an account. Signing in links your expert requests to you.")
                        .font(UDATheme.caption)
                        .foregroundColor(UDATheme.textSecondary)
                }
            }
            .listRowBackground(UDATheme.surface)
        }
        .navigationTitle("Settings")
        .scrollContentBackground(.hidden)
        .background(UDATheme.background)
        .sheet(isPresented: $showReviewSheet) {
            ReviewView()
        }
        .sheet(isPresented: $showPaywall) {
            NavigationStack { ProPaywallView() }
        }
        .sheet(isPresented: $showExpert) {
            ExpertAccessView()
        }
        .sheet(isPresented: $showSignIn) {
            NavigationStack { LoginView() }
        }
        .manageSubscriptionsSheet(isPresented: $showManageSubscription)
        .confirmationDialog("Delete your account?", isPresented: $confirmDeleteAccount, titleVisibility: .visible) {
            Button("Delete account", role: .destructive) {
                Task { await auth.deleteAccount() }
            }
        } message: {
            Text("This removes your sign-in from this device and disconnects Google if you used it. An active Pro subscription is NOT cancelled — manage that in the App Store. To fully remove Sign in with Apple, go to iPhone Settings → your name → Sign in with Apple.")
        }
    }
}

#Preview {
    NavigationStack { SettingsView() }
}
