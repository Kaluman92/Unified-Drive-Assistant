//
//  ProPaywallView.swift
//  Unified Drive Assistant
//
//  ============================================================
//  PRO BLOCK — UPGRADE SCREEN
//  ------------------------------------------------------------
//  Built on Apple's SubscriptionStoreView: prices come live from
//  the App Store (or the local .storekit file while testing), and
//  the plan picker, auto-renew terms and Restore button are the
//  standard ones App Review is used to seeing. Only the marketing
//  header above the plans is ours.
//  ============================================================

import SwiftUI
import StoreKit

struct ProPaywallView: View {
    @StateObject private var store = ProStore.shared
    @Environment(\.dismiss) private var dismiss
    /// False when shown inside ExpertAccessView, which swaps itself to the
    /// ticket form once Pro is active instead of closing.
    var dismissOnPurchase = true

    var body: some View {
        SubscriptionStoreView(productIDs: ProStore.productIDs) {
            VStack(spacing: UDATheme.spacingM) {
                Image(systemName: "person.badge.shield.checkmark.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(UDATheme.logoMagenta)
                Text("Unified Drive Assistant Pro")
                    .font(UDATheme.title)
                    .foregroundColor(UDATheme.textPrimary)
                    .multilineTextAlignment(.center)
                Text("When the manual isn't enough, get a real drives engineer on your fault.")
                    .font(UDATheme.body)
                    .foregroundColor(UDATheme.textSecondary)
                    .multilineTextAlignment(.center)

                VStack(alignment: .leading, spacing: UDATheme.spacingS) {
                    Benefit(icon: "person.fill.questionmark", text: "Priority expert tickets, answered by Silcore Engineering")
                    Benefit(icon: "photo.on.rectangle.angled", text: "Send photos, fault codes and site details in one go")
                    Benefit(icon: "bolt.fill", text: "\"Line down\" requests go to the front of the queue")
                }
                .padding(.top, UDATheme.spacingS)

                // Our own Restore (instead of .storeButton(.visible, for: .restorePurchases))
                // so Pro status refreshes the moment the restore finishes.
                Button("Already subscribed? Restore purchases") {
                    Task {
                        await store.restorePurchases()
                        if store.isPro && dismissOnPurchase { dismiss() }
                    }
                }
                .font(UDATheme.caption)
                .foregroundColor(UDATheme.accentPressed)
            }
            .padding(UDATheme.spacingL)
        }
        .subscriptionStoreControlStyle(.prominentPicker)
        .subscriptionStorePolicyDestination(url: ProStore.termsURL, for: .termsOfService)
        .subscriptionStorePolicyDestination(url: ProStore.privacyURL, for: .privacyPolicy)
        .onInAppPurchaseCompletion { _, result in
            await store.handlePurchase(result)
            if store.isPro && dismissOnPurchase { dismiss() }
        }
        .tint(UDATheme.accentPressed)
        .background(UDATheme.background)
        .alert("Purchase problem", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.errorMessage ?? "")
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
        }
    }
}

private struct Benefit: View {
    let icon: String
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: UDATheme.spacingS) {
            Image(systemName: icon)
                .foregroundColor(UDATheme.accentPressed)
                .frame(width: 22)
            Text(text)
                .font(UDATheme.body)
                .foregroundColor(UDATheme.textPrimary)
        }
    }
}

#Preview {
    NavigationStack { ProPaywallView() }
}
