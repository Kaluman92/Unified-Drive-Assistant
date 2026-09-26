//
//  ExpertRequestView.swift
//  Unified Drive Assistant
//
//  ============================================================
//  PRO BLOCK — ASK AN EXPERT (priority email ticket)
//  ------------------------------------------------------------
//  Pro-only. Collects everything an engineer needs to help —
//  brand, drive, fault code, urgency, site, description, photos —
//  and sends it as one email to your expert inbox via the
//  device's Mail app (same MailComposeView as Feedback). No
//  backend needed; replies come back by email.
//
//  Every ticket includes the sender's App Store subscription ID,
//  so your team can confirm they really are Pro before replying
//  (App Store Connect → Sales and Trends / Subscriptions).
//
//  IMPORTANT — set the real expert inbox in ExpertSupport.recipient.
//  ============================================================

import SwiftUI
import PhotosUI
import MessageUI

enum ExpertSupport {
    /// Where Pro tickets are sent. Defaults to the feedback inbox —
    /// change to a dedicated expert address when you have one.
    static let recipient = ReviewComposer.feedbackRecipient
    static let maxPhotos = 4
}

/// Use this as the entry point: shows the ticket form for Pro members and
/// the upgrade screen for everyone else, switching over the moment a
/// purchase completes.
struct ExpertAccessView: View {
    var fault: FaultCode? = nil
    @StateObject private var store = ProStore.shared

    var body: some View {
        NavigationStack {
            if store.isPro {
                ExpertRequestView(fault: fault)
            } else {
                ProPaywallView(dismissOnPurchase: false)
            }
        }
    }
}

private enum Urgency: String, CaseIterable, Identifiable {
    case lineDown = "Line down — production stopped"
    case degraded = "Running, but with problems"
    case question = "General question"

    var id: String { rawValue }

    var subjectTag: String {
        switch self {
        case .lineDown: return "LINE DOWN"
        case .degraded: return "DEGRADED"
        case .question: return "QUESTION"
        }
    }
}

struct ExpertRequestView: View {
    let fault: FaultCode?

    @StateObject private var auth = AuthManager.shared
    @StateObject private var store = ProStore.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var brand: String
    @State private var driveModel: String
    @State private var faultCode: String
    @State private var urgency: Urgency = .degraded
    @State private var site = ""
    @State private var details = ""
    @State private var phone = ""
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var photos: [UIImage] = []
    @State private var showMail = false
    @State private var showSentConfirmation = false
    @State private var showNoEmailApp = false
    @State private var showSignIn = false

    init(fault: FaultCode? = nil) {
        self.fault = fault
        _brand = State(initialValue: fault?.brand ?? Vendor.siemens.rawValue)
        _driveModel = State(initialValue: fault?.familyLabel ?? "")
        _faultCode = State(initialValue: fault.map { "\($0.code) — \($0.title)" } ?? "")
    }

    private var canSend: Bool {
        !details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Form {
            Section {
                Label("Pro · \(store.planName ?? "Active")", systemImage: "checkmark.seal.fill")
                    .foregroundColor(UDATheme.accentPressed)
                    .font(UDATheme.bodyBold)
                Text("A Silcore drives engineer will reply to \(auth.currentUser?.email ?? "the email address you send from") as soon as possible. Line-down requests are handled first.")
                    .font(UDATheme.caption)
                    .foregroundColor(UDATheme.textSecondary)
                if !auth.isSignedIn {
                    Button {
                        showSignIn = true
                    } label: {
                        Label("Sign in to link this request to your account (optional)", systemImage: "person.crop.circle")
                            .font(UDATheme.caption)
                    }
                    .foregroundColor(UDATheme.accentPressed)
                }
            }
            .listRowBackground(UDATheme.surface)

            Section("The drive") {
                Picker("Brand", selection: $brand) {
                    ForEach(Vendor.allCases) { Text($0.rawValue).tag($0.rawValue) }
                    Text("Other").tag("Other")
                }
                TextField("Model / family (e.g. S120, ATV930)", text: $driveModel)
                TextField("Fault code (if any)", text: $faultCode)
            }
            .listRowBackground(UDATheme.surface)

            Section("How urgent?") {
                Picker("Urgency", selection: $urgency) {
                    ForEach(Urgency.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
            .listRowBackground(UDATheme.surface)

            Section {
                TextEditor(text: $details)
                    .frame(minHeight: 120)
                    .overlay(alignment: .topLeading) {
                        if details.isEmpty {
                            Text("What's happening? What have you already tried? Motor size, load, recent changes…")
                                .foregroundColor(UDATheme.textSecondary)
                                .padding(.top, 8)
                                .padding(.leading, 4)
                                .allowsHitTesting(false)
                        }
                    }
            } header: {
                Text("Describe the problem")
            } footer: {
                Text("Required.")
            }
            .listRowBackground(UDATheme.surface)

            Section {
                PhotosPicker(selection: $photoItems,
                             maxSelectionCount: ExpertSupport.maxPhotos,
                             matching: .images) {
                    Label(photos.isEmpty ? "Add photos" : "Change photos (\(photos.count))",
                          systemImage: "photo.on.rectangle.angled")
                }
                .foregroundColor(UDATheme.accentPressed)
                if !photos.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: UDATheme.spacingS) {
                            ForEach(photos.indices, id: \.self) { index in
                                Image(uiImage: photos[index])
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 72, height: 72)
                                    .clipped()
                                    .cornerRadius(UDATheme.chamferSmall)
                            }
                        }
                    }
                }
            } header: {
                Text("Photos")
            } footer: {
                Text("Nameplate, drive display, wiring — up to \(ExpertSupport.maxPhotos).")
            }
            .listRowBackground(UDATheme.surface)

            Section("Site & contact (optional)") {
                TextField("Site / location", text: $site)
                TextField("Phone for a call-back", text: $phone)
                    .keyboardType(.phonePad)
            }
            .listRowBackground(UDATheme.surface)

            Section {
                Button {
                    send()
                } label: {
                    Label("Send to an expert", systemImage: "paperplane.fill")
                }
                .udaPrimaryButton()
                .disabled(!canSend)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            } footer: {
                if !ReviewComposer.canSendMail {
                    Text("No Mail account is set up on this device, so your default email app will open instead — photos will need to be attached there manually.")
                }
            }
        }
        .navigationTitle("Ask an Expert")
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .background(UDATheme.background)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
        }
        .onChange(of: photoItems) { _, items in
            Task { await loadPhotos(items) }
        }
        .sheet(isPresented: $showMail) {
            MailComposeView(
                recipient: ExpertSupport.recipient,
                subject: subject,
                body: emailBody,
                attachments: attachments
            ) { result in
                showMail = false
                if result == .sent { showSentConfirmation = true }
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showSignIn) {
            NavigationStack { LoginView() }
        }
        .alert("No email app found", isPresented: $showNoEmailApp) {
            Button("Copy request") {
                UIPasteboard.general.string = "To: \(ExpertSupport.recipient)\nSubject: \(subject)\n\n\(emailBody)"
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Copy your request and email it to \(ExpertSupport.recipient) from any email app.")
        }
        .alert("Request sent", isPresented: $showSentConfirmation) {
            Button("Done") { dismiss() }
        } message: {
            Text("An engineer will reply by email. For line-down requests, keep your phone handy.")
        }
    }

    // MARK: - Sending

    private func send() {
        if ReviewComposer.canSendMail {
            showMail = true
        } else {
            var components = URLComponents()
            components.scheme = "mailto"
            components.path = ExpertSupport.recipient
            components.queryItems = [
                URLQueryItem(name: "subject", value: subject),
                URLQueryItem(name: "body", value: emailBody)
            ]
            // No email app at all (e.g. Mail deleted): let them copy the
            // ticket instead of the button silently doing nothing.
            if let url = components.url {
                openURL(url) { accepted in
                    if !accepted { showNoEmailApp = true }
                }
            } else {
                showNoEmailApp = true
            }
        }
    }

    private var subject: String {
        let code = faultCode.isEmpty ? "No code" : faultCode
        return "[PRO][\(urgency.subjectTag)] \(brand) \(driveModel) — \(code)"
    }

    private var emailBody: String {
        let user = auth.currentUser
        let info = Bundle.main.infoDictionary
        let appVersion = "\(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))"
        return """
        URGENCY: \(urgency.rawValue)

        DRIVE
        Brand: \(brand)
        Model / family: \(driveModel.isEmpty ? "—" : driveModel)
        Fault code: \(faultCode.isEmpty ? "—" : faultCode)

        PROBLEM
        \(details)

        SITE: \(site.isEmpty ? "—" : site)
        CALL-BACK PHONE: \(phone.isEmpty ? "—" : phone)
        PHOTOS ATTACHED: \(ReviewComposer.canSendMail ? photos.count : 0)

        ——————————
        Name: \(user?.name ?? "—")
        Email: \(user?.email ?? "—")
        Account: \(user?.uid ?? "—") (\(user?.provider.displayName ?? "—"))
        Pro plan: \(store.planName ?? "—")
        Subscription ID: \(store.originalTransactionID.map { String($0) } ?? "—")
        App: \(appVersion) · iOS \(UIDevice.current.systemVersion) · \(UIDevice.current.model)
        """
    }

    private var attachments: [MailAttachment] {
        photos.enumerated().compactMap { index, image in
            image.jpegData(compressionQuality: 0.7).map {
                MailAttachment(data: $0, mimeType: "image/jpeg", fileName: "photo-\(index + 1).jpg")
            }
        }
    }

    private func loadPhotos(_ items: [PhotosPickerItem]) async {
        var loaded: [UIImage] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                loaded.append(image)
            }
        }
        photos = loaded
    }
}

#Preview {
    NavigationStack { ExpertRequestView() }
}
