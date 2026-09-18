//
//  LoginView.swift
//  Unified Drive Assistant
//
//  ============================================================
//  AUTH BLOCK — UI (local stand-in — see AuthManager.swift header)
//  ------------------------------------------------------------
//  Simple email/password form while real Apple/Google sign-in is
//  parked for later. No external setup needed to build and run.
//  ============================================================

import SwiftUI

struct LoginView: View {
    @StateObject private var auth = AuthManager.shared
    @State private var email = ""
    @State private var password = ""
    @State private var isSignUpMode = false

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
                    TextField("Email", text: $email)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.emailAddress)
                        .padding(UDATheme.spacingM)
                        .background(UDATheme.surface)
                        .cornerRadius(UDATheme.chamferMedium)

                    SecureField("Password (6+ characters)", text: $password)
                        .padding(UDATheme.spacingM)
                        .background(UDATheme.surface)
                        .cornerRadius(UDATheme.chamferMedium)

                    if let errorMessage = auth.authErrorMessage {
                        Text(errorMessage)
                            .font(UDATheme.caption)
                            .foregroundColor(UDATheme.danger)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    Button {
                        Task {
                            if isSignUpMode {
                                await auth.signUp(email: email, password: password)
                            } else {
                                await auth.signIn(email: email, password: password)
                            }
                        }
                    } label: {
                        if auth.isBusy {
                            ProgressView().tint(UDATheme.bgBlack)
                        } else {
                            Text(isSignUpMode ? "Create Account" : "Sign In")
                        }
                    }
                    .udaPrimaryButton()
                    .disabled(auth.isBusy || email.isEmpty || password.count < 6)

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isSignUpMode.toggle()
                            auth.authErrorMessage = nil
                        }
                    } label: {
                        Text(isSignUpMode ? "Already have an account? Log in" : "New here? Create an account")
                            .font(UDATheme.caption)
                            .foregroundColor(UDATheme.textSecondary)
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: auth.authErrorMessage)
                .animation(.easeInOut(duration: 0.2), value: isSignUpMode)
                .padding(UDATheme.spacingL)
                .background(UDATheme.surfaceElevated)
                .cornerRadius(UDATheme.chamferLarge)
                .padding(.horizontal, UDATheme.spacingL)

                Spacer()
                Spacer()
            }
        }
    }
}

#Preview {
    LoginView()
}
