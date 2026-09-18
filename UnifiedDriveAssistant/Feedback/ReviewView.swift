//
//  ReviewView.swift
//  Unified Drive Assistant
//
//  ============================================================
//  FEEDBACK BLOCK — UI
//  ------------------------------------------------------------
//  A star rating + free-text box. "Send" opens the device's Mail
//  app pre-addressed to ReviewComposer.feedbackRecipient (see
//  ReviewComposer.swift) with the rating and text filled in — the
//  user still taps Send in Mail themselves.
//  ============================================================

import SwiftUI
import MessageUI

struct ReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var auth = AuthManager.shared

    @State private var rating = 0
    @State private var reviewText = ""
    @State private var showMailComposer = false
    @State private var showNoMailAlert = false
    @State private var showSentConfirmation = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Rate the app") {
                    HStack(spacing: UDATheme.spacingS) {
                        ForEach(1...5, id: \.self) { star in
                            Image(systemName: star <= rating ? "star.fill" : "star")
                                .foregroundColor(UDATheme.logoOrange)
                                .font(.system(size: 22))
                                .onTapGesture { rating = star }
                        }
                    }
                    .padding(.vertical, UDATheme.spacingXS)
                }
                .listRowBackground(UDATheme.surface)

                Section("Your review") {
                    TextEditor(text: $reviewText)
                        .frame(minHeight: 140)
                    Text("This will be sent to \(ReviewComposer.feedbackRecipient) as an email from your device.")
                        .font(UDATheme.caption)
                        .foregroundColor(UDATheme.textSecondary)
                }
                .listRowBackground(UDATheme.surface)
            }
            .scrollContentBackground(.hidden)
            .background(UDATheme.background)
            .navigationTitle("Send a Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Send") {
                        if ReviewComposer.canSendMail {
                            showMailComposer = true
                        } else {
                            showNoMailAlert = true
                        }
                    }
                    .disabled(reviewText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showMailComposer) {
                MailComposeView(
                    subject: "Unified Drive Assistant — Review (\(rating)/5 stars)",
                    body: reviewBody
                ) { result in
                    showMailComposer = false
                    if result == .sent {
                        showSentConfirmation = true
                    }
                }
            }
            .alert("No Mail account set up", isPresented: $showNoMailAlert) {
                Button("Copy review instead") {
                    UIPasteboard.general.string = reviewBody
                }
                Button("OK", role: .cancel) {}
            } message: {
                Text("This device doesn't have Mail configured, so we can't open a pre-filled email. You can copy your review and send it to \(ReviewComposer.feedbackRecipient) another way.")
            }
            .alert("Thanks for the feedback!", isPresented: $showSentConfirmation) {
                Button("Done") { dismiss() }
            }
        }
    }

    private var reviewBody: String {
        var lines = ["Rating: \(rating)/5 stars", ""]
        lines.append(reviewText)
        lines.append("")
        if let email = auth.currentUser?.email {
            lines.append("— sent from Unified Drive Assistant, account: \(email)")
        } else {
            lines.append("— sent from Unified Drive Assistant")
        }
        return lines.joined(separator: "\n")
    }
}

#Preview {
    ReviewView()
}
