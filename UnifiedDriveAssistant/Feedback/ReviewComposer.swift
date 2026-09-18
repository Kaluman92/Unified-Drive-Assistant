//
//  ReviewComposer.swift
//  Unified Drive Assistant
//
//  ============================================================
//  FEEDBACK BLOCK — MAIL BRIDGE
//  ------------------------------------------------------------
//  Sends the user's review as an email using the device's own
//  Mail app, via MFMailComposeViewController. No backend, no API
//  key, no setup required — works today.
//
//  IMPORTANT — set your real address below:
//  `feedbackRecipient` is a placeholder. Replace it with the
//  address you actually want reviews sent to before shipping.
//
//  Limitation: this opens Apple's mail-compose sheet pre-filled
//  and addressed to you — the user still taps Send themselves,
//  and it only works if they have a Mail account configured on
//  the device (checked via `canSendMail` below; falls back to a
//  message if not). For fully automatic, silent submission with
//  no Mail account required, you'd need a backend endpoint (e.g.
//  the same Cloud Function pattern used for the AI assistant,
//  posting to an email-sending service like SendGrid) — that's a
//  bigger lift than this file, ask if you want it scaffolded.
//  ============================================================

import SwiftUI
import MessageUI

enum ReviewComposer {
    /// Where reviews get sent.
    static let feedbackRecipient = "Silcore.engineering@gmail.com"

    static var canSendMail: Bool {
        MFMailComposeViewController.canSendMail()
    }
}

/// SwiftUI wrapper around MFMailComposeViewController.
struct MailComposeView: UIViewControllerRepresentable {
    let subject: String
    let body: String
    let onFinish: (MFMailComposeResult) -> Void

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.mailComposeDelegate = context.coordinator
        vc.setToRecipients([ReviewComposer.feedbackRecipient])
        vc.setSubject(subject)
        vc.setMessageBody(body, isHTML: false)
        return vc
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let onFinish: (MFMailComposeResult) -> Void
        init(onFinish: @escaping (MFMailComposeResult) -> Void) { self.onFinish = onFinish }

        func mailComposeController(_ controller: MFMailComposeViewController,
                                    didFinishWith result: MFMailComposeResult,
                                    error: Error?) {
            controller.dismiss(animated: true)
            onFinish(result)
        }
    }
}
