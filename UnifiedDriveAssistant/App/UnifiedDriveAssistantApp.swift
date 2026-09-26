//
//  UnifiedDriveAssistantApp.swift
//  Unified Drive Assistant
//
//  ============================================================
//  APP BLOCK — ENTRY POINT
//  ============================================================

import SwiftUI

// Firebase is not wired up — sign-in is Apple/Google direct (see
// Auth/AuthManager.swift) and analytics is a local stand-in (see
// Analytics/AnalyticsService.swift).
//
// Sign-in is OPTIONAL (App Store guideline 5.1.1(v)): the app opens
// straight to Home, and nothing — fault lookup, tools, buying Pro, or
// sending an expert request — requires an account. Signing in (from
// Settings or the expert form) just links requests to the person.

@main
struct UnifiedDriveAssistantApp: App {
    @StateObject private var auth = AuthManager.shared
    @StateObject private var theme = ThemeManager.shared
    @StateObject private var lock = BiometricLock.shared
    // Created at launch (not on first visit to Settings) so App Store
    // renewals/refunds are picked up as soon as the app opens.
    @StateObject private var pro = ProStore.shared
    @Environment(\.scenePhase) private var scenePhase

    private var showLock: Bool { lock.isLocked }

    var body: some Scene {
        WindowGroup {
            HomeView()
            .tint(UDATheme.accentPressed)
            .preferredColorScheme(theme.mode.colorScheme)
            // Face ID lock — its own window so it also covers open sheets.
            .onAppear { LockWindow.update(visible: showLock) }
            .onChange(of: showLock) { _, visible in LockWindow.update(visible: visible) }
            // Completes the Google Sign-In browser round-trip.
            .onOpenURL { url in
                auth.handleOpenURL(url)
            }
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            switch phase {
            case .background:
                lock.lock()
            case .active:
                // Face ID prompt as soon as the app is in front — not before,
                // or iOS rejects it.
                Task { await lock.autoPrompt() }
            default:
                break
            }
        }
    }
}
