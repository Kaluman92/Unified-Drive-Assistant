//
//  LoginView.swift
//  Unified Drive Assistant
//
//  ============================================================
//  AUTH BLOCK — UI (optional sign-in sheet)
//  ------------------------------------------------------------
//  Sign in with Apple or Google (see AuthManager.swift for the
//  setup each one still needs). Shown as a sheet from Settings →
//  Account and from the expert form — never required to use the
//  app. Closes itself once sign-in succeeds.
//  ============================================================

import SwiftUI
import AuthenticationServices

struct LoginView: View {
    @StateObject private var auth = AuthManager.shared
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            UDATheme.background.ignoresSafeArea()

            VStack(spacing: UDATheme.spacingL) {
                Spacer()

                VStack(spacing: UDATheme.spacingXS) {
                    Image("AppLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 220)
                    Text(UDATheme.appTagline)
                        .font(UDATheme.tagline)
                        .foregroundColor(UDATheme.tealAccent)
                        .tracking(3)
                }

                VStack(spacing: UDATheme.spacingM) {
                    Text("Sign in (optional)")
                        .font(UDATheme.headline)
                        .foregroundColor(UDATheme.textPrimary)

                    SignInWithAppleButton(.signIn) { request in
                        auth.prepareAppleRequest(request)
                    } onCompletion: { result in
                        auth.handleAppleCompletion(result)
                    }
                    .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                    .frame(height: 48)
                    .cornerRadius(UDATheme.chamferMedium)
                    // Rebuild on theme change so the button style follows it.
                    .id(colorScheme)

                    // Hidden until the real Google OAuth client ID is in
                    // Info.plist — App Review rejects visibly broken buttons.
                    if auth.isGoogleConfigured {
                        Button {
                            Task { await auth.signInWithGoogle() }
                        } label: {
                            HStack(spacing: UDATheme.spacingS) {
                                if auth.isBusy {
                                    ProgressView()
                                } else {
                                    GoogleMark()
                                    Text("Sign in with Google")
                                        .font(.system(size: 17, weight: .medium))
                                }
                            }
                            .foregroundColor(Color(hex: "1F1F1F"))
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(Color.white)
                            .overlay(
                                RoundedRectangle(cornerRadius: UDATheme.chamferMedium)
                                    .stroke(Color(hex: "747775"), lineWidth: UDATheme.hairline)
                            )
                            .cornerRadius(UDATheme.chamferMedium)
                        }
                        .disabled(auth.isBusy)
                    }

                    if let errorMessage = auth.authErrorMessage {
                        Text(errorMessage)
                            .font(UDATheme.caption)
                            .foregroundColor(UDATheme.danger)
                            .multilineTextAlignment(.center)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    Text("Everything in the app works without an account. Signing in links your expert requests to you, so our engineers know who they're helping. We only use your name and email for that.")
                        .font(UDATheme.caption)
                        .foregroundColor(UDATheme.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .animation(.easeInOut(duration: 0.2), value: auth.authErrorMessage)
                .padding(UDATheme.spacingL)
                .background(UDATheme.surfaceElevated)
                .cornerRadius(UDATheme.chamferLarge)
                .padding(.horizontal, UDATheme.spacingL)

                Spacer()
                Spacer()
            }
        }
        .onChange(of: auth.isSignedIn) { _, signedIn in
            if signedIn { dismiss() }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Not now") { dismiss() }
            }
        }
    }
}

/// Simple "G" badge so the Google button reads correctly without bundling
/// Google's logo asset. Swap for the official asset from Google's
/// branding guidelines before App Store submission if you prefer.
private struct GoogleMark: View {
    var body: some View {
        Text("G")
            .font(.system(size: 18, weight: .bold, design: .rounded))
            .foregroundStyle(
                AngularGradient(
                    colors: [Color(hex: "4285F4"), Color(hex: "34A853"), Color(hex: "FBBC05"), Color(hex: "EA4335"), Color(hex: "4285F4")],
                    center: .center
                )
            )
    }
}

#Preview {
    NavigationStack { LoginView() }
}
