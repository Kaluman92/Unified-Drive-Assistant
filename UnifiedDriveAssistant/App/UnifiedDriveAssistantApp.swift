//
//  UnifiedDriveAssistantApp.swift
//  Unified Drive Assistant
//
//  ============================================================
//  APP BLOCK — ENTRY POINT
//  ============================================================

import SwiftUI

// Firebase is not wired up yet — AppDelegate/FirebaseApp.configure() will come
// back here once Auth/Firestore are reintroduced (see Auth/AuthManager.swift
// and Analytics/AnalyticsService.swift for the local stand-ins in the meantime).
//
// Apple/Google sign-in wiring (GoogleSignIn import, restorePreviousGoogleSignIn(),
// onOpenURL handling) was removed here too — parked until you're ready to go
// online. See Auth/AuthManager.swift's file header and README.md section 26.

@main
struct UnifiedDriveAssistantApp: App {
    @StateObject private var auth = AuthManager.shared
    @StateObject private var theme = ThemeManager.shared

    var body: some Scene {
        WindowGroup {
            Group {
                if auth.isSignedIn {
                    HomeView()
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.98)),
                            removal: .opacity
                        ))
                } else {
                    LoginView()
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.35), value: auth.isSignedIn)
            .tint(UDATheme.accentPressed)
            .preferredColorScheme(theme.mode.colorScheme)
        }
    }
}
