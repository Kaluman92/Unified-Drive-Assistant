//
//  SettingsView.swift
//  Unified Drive Assistant
//
//  ============================================================
//  SETTINGS BLOCK
//  ------------------------------------------------------------
//  All app-level settings live here: AI assistant, appearance
//  (light/dark), feedback, and account. Each section owns its
//  own piece of state (ThemeManager, AIAssistantService,
//  AuthManager) — this view just lays them out.
//  ============================================================

import SwiftUI

struct SettingsView: View {
    @StateObject private var assistant = AIAssistantService.shared
    @StateObject private var auth = AuthManager.shared
    @StateObject private var theme = ThemeManager.shared
    @StateObject private var geofence = SiteGeofenceManager.shared
    @State private var showReviewSheet = false

    var body: some View {
        List {
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
                if let email = auth.currentUser?.email {
                    Text(email)
                        .foregroundColor(UDATheme.textSecondary)
                }
                Button("Log out", role: .destructive) {
                    auth.signOut()
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
    }
}

#Preview {
    NavigationStack { SettingsView() }
}
