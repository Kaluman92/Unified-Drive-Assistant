//
//  BiometricLock.swift
//  Unified Drive Assistant
//
//  ============================================================
//  AUTH BLOCK — FACE ID / TOUCH ID APP LOCK
//  ------------------------------------------------------------
//  Optional (Settings → Security), and independent of sign-in.
//  When on, this keeps the app locked behind Face ID
//  (or Touch ID / Optic ID, whichever the device has) every time
//  it's opened or comes back from the background. The device
//  passcode is always accepted as a fallback, so nobody gets
//  locked out if Face ID fails.
//
//  Needs NSFaceIDUsageDescription in the target's Info settings —
//  already added to project.pbxproj.
//  ============================================================

import SwiftUI
import UIKit
import Combine
import LocalAuthentication

@MainActor
final class BiometricLock: ObservableObject {

    static let shared = BiometricLock()

    @Published private(set) var isEnabled: Bool
    @Published private(set) var isLocked: Bool
    @Published var errorMessage: String?

    private let enabledKey = "uda_biometric_lock_enabled"
    private var isPrompting = false
    // Auto-prompt once per lock. Without this, cancelling the Face ID sheet
    // makes the app "active" again, which would re-prompt forever.
    private var shouldAutoPrompt = true

    private init() {
        let enabled = UserDefaults.standard.bool(forKey: enabledKey)
        isEnabled = enabled
        isLocked = enabled   // start locked on a cold launch
    }

    /// "Face ID", "Touch ID", "Optic ID" — or "Passcode" on devices with no biometrics enrolled.
    var methodName: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID:  return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default:       return "Passcode"
        }
    }

    var methodIcon: String {
        switch methodName {
        case "Face ID":  return "faceid"
        case "Touch ID": return "touchid"
        case "Optic ID": return "opticid"
        default:         return "lock.fill"
        }
    }

    /// Whether this device can use the lock at all (needs at least a passcode set).
    var isAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    /// Turning the lock ON asks for Face ID first, so it's proven to work
    /// before the person can be locked out by it.
    func setEnabled(_ enabled: Bool) async {
        errorMessage = nil
        if enabled {
            guard await authenticate(reason: "Turn on \(methodName) to unlock Unified Drive Assistant") else { return }
        }
        isEnabled = enabled
        isLocked = false
        UserDefaults.standard.set(enabled, forKey: enabledKey)
    }

    /// Called when the app goes to the background.
    func lock() {
        guard isEnabled else { return }
        isLocked = true
        shouldAutoPrompt = true
    }

    /// Prompts automatically the first time the lock screen is seen after locking.
    func autoPrompt() async {
        guard shouldAutoPrompt else { return }
        shouldAutoPrompt = false
        await unlock()
    }

    func unlock() async {
        guard isLocked, !isPrompting else { return }
        errorMessage = nil
        if await authenticate(reason: "Unlock Unified Drive Assistant") {
            isLocked = false
        }
    }

    private func authenticate(reason: String) async -> Bool {
        isPrompting = true
        defer { isPrompting = false }
        let context = LAContext()
        context.localizedFallbackTitle = "Use Passcode"
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch let error as LAError where error.code == .userCancel || error.code == .appCancel || error.code == .systemCancel {
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}

/// Shows the lock screen in its own window above everything else. A plain
/// SwiftUI overlay on the root view would sit UNDER any open sheet (paywall,
/// expert form, Mail), leaving that content visible while "locked".
@MainActor
enum LockWindow {
    private static var window: UIWindow?

    static func update(visible: Bool) {
        if visible {
            guard window == nil,
                  let scene = UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene })
                    .first else { return }
            let lockWindow = UIWindow(windowScene: scene)
            lockWindow.windowLevel = .alert + 1
            lockWindow.rootViewController = UIHostingController(rootView: LockScreenView(lock: .shared))
            switch ThemeManager.shared.mode.colorScheme {
            case .dark?:  lockWindow.overrideUserInterfaceStyle = .dark
            case .light?: lockWindow.overrideUserInterfaceStyle = .light
            default:      lockWindow.overrideUserInterfaceStyle = .unspecified
            }
            lockWindow.makeKeyAndVisible()
            window = lockWindow
        } else {
            window?.isHidden = true
            window = nil
        }
    }
}

/// Full-screen lock screen, hosted by LockWindow while locked.
/// The automatic Face ID prompt is triggered from the App's scenePhase
/// (this view lives in a UIKit-hosted window, where scenePhase isn't reliable).
struct LockScreenView: View {
    @ObservedObject var lock: BiometricLock

    var body: some View {
        ZStack {
            UDATheme.background.ignoresSafeArea()
            VStack(spacing: UDATheme.spacingL) {
                Spacer()
                Image("AppLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 160)
                Image(systemName: lock.methodIcon)
                    .font(.system(size: 44, weight: .regular))
                    .foregroundColor(UDATheme.accent)
                Text("Locked")
                    .font(UDATheme.title)
                    .foregroundColor(UDATheme.textPrimary)
                if let message = lock.errorMessage {
                    Text(message)
                        .font(UDATheme.caption)
                        .foregroundColor(UDATheme.danger)
                        .multilineTextAlignment(.center)
                }
                Spacer()
                Button {
                    Task { await lock.unlock() }
                } label: {
                    Label("Unlock with \(lock.methodName)", systemImage: lock.methodIcon)
                }
                .udaPrimaryButton()
                .padding(.horizontal, UDATheme.spacingL)
                .padding(.bottom, UDATheme.spacingXL)
            }
        }
    }
}
