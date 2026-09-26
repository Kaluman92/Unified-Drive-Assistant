//
//  ProStore.swift
//  Unified Drive Assistant
//
//  ============================================================
//  PRO BLOCK — SUBSCRIPTION STATE (StoreKit 2)
//  ------------------------------------------------------------
//  "Pro" = an auto-renewing subscription (monthly or yearly) that
//  unlocks priority human expert assistance (ExpertRequestView).
//
//  The purchase UI itself is Apple's SubscriptionStoreView (see
//  ProPaywallView.swift), which already handles prices, the
//  auto-renew wording, and Restore Purchases the way App Review
//  expects. This class only answers "is this person Pro right
//  now?" and keeps that answer current.
//
//  SETUP:
//  • Local testing (Simulator, no App Store Connect needed):
//    Product → Scheme → Edit Scheme → Run → Options →
//    StoreKit Configuration → "UnifiedDriveAssistant.storekit".
//  • Real release: create a subscription group with two
//    auto-renewable subscriptions in App Store Connect using
//    EXACTLY the product IDs below, and set real prices there.
//  ============================================================

import Foundation
import Combine
import StoreKit

@MainActor
final class ProStore: ObservableObject {

    static let shared = ProStore()

    static let monthlyID = "com.silcore.uda.pro.monthly"
    static let yearlyID  = "com.silcore.uda.pro.yearly"
    static let productIDs = [monthlyID, yearlyID]

    /// Links shown under the paywall. Apple requires both for subscriptions.
    /// Terms: Apple's standard EULA (fine unless you write your own).
    /// Privacy: served by GitHub Pages from docs/privacy.html in this repo.
    /// Also linked from Settings → Privacy, and must match App Store Connect.
    static let termsURL   = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    static let privacyURL = URL(string: "https://kaluman92.github.io/Unified-Drive-Assistant/privacy.html")!

    @Published private(set) var isPro = false
    @Published private(set) var activeProductID: String?
    /// App Store's original transaction ID — included in expert tickets so
    /// your team can verify the sender's subscription in App Store Connect.
    @Published private(set) var originalTransactionID: UInt64?
    @Published var errorMessage: String?

    private var updatesTask: Task<Void, Never>?

    private init() {
        // Renewals, refunds, Ask-to-Buy approvals and purchases made on
        // other devices all arrive here, even while the app is running.
        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await transaction.finish()
                }
                await self?.refreshEntitlements()
            }
        }
        Task { await refreshEntitlements() }
    }

    var planName: String? {
        switch activeProductID {
        case Self.monthlyID: return "Monthly"
        case Self.yearlyID:  return "Yearly"
        default:             return nil
        }
    }

    /// Re-reads what the App Store says this Apple ID currently owns.
    func refreshEntitlements() async {
        var active: Transaction?
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  Self.productIDs.contains(transaction.productID),
                  transaction.revocationDate == nil else { continue }
            active = transaction
        }
        isPro = active != nil
        activeProductID = active?.productID
        originalTransactionID = active?.originalID
    }

    /// Called by the paywall after a purchase completes.
    func handlePurchase(_ result: Result<Product.PurchaseResult, Error>) async {
        switch result {
        case .success(.success(.verified(let transaction))):
            await transaction.finish()
        case .success(.success(.unverified(_, let error))):
            errorMessage = "The App Store couldn't verify that purchase: \(error.localizedDescription)"
        case .failure(let error):
            errorMessage = "Purchase failed: \(error.localizedDescription)"
        default:
            break   // cancelled or pending (e.g. Ask to Buy)
        }
        await refreshEntitlements()
    }

    func restorePurchases() async {
        errorMessage = nil
        do {
            try await AppStore.sync()
        } catch {
            errorMessage = "Couldn't restore purchases: \(error.localizedDescription)"
        }
        await refreshEntitlements()
    }
}
