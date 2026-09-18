//
//  AnalyticsService.swift
//  Unified Drive Assistant
//
//  ============================================================
//  ANALYTICS BLOCK — LOCAL STAND-IN (Firestore not wired up yet)
//  ------------------------------------------------------------
//  Same public API as the Firebase-backed version
//  (logSignUp, logSignIn, logBrandSelected, logFaultLookup,
//  logAIAssistUsed, logAIAssistToggled) so AuthManager,
//  BrandTabView, FaultDetailView, and AIAssistantService all call
//  this exactly as before — nothing else needs to change.
//
//  For now, every event is just printed to the Xcode console and
//  appended to an in-memory array you can inspect while testing
//  (`AnalyticsService.shared.recentEvents`). Nothing leaves the
//  device yet.
//
//  TO BRING FIRESTORE BACK LATER: replace the body of `logEvent`
//  and the two `setData` calls with the Firestore-backed version
//  (see README.md "Firebase setup"). No other file needs to change.
//  ============================================================

import Foundation

struct AnalyticsEvent {
    let uid: String
    let name: String
    let extra: [String: Any]
    let timestamp: Date
}

final class AnalyticsService {

    static let shared = AnalyticsService()
    private init() {}

    /// Kept in memory only, for now — useful while testing locally.
    private(set) var recentEvents: [AnalyticsEvent] = []

    // MARK: - Account lifecycle

    func logSignUp(uid: String, email: String) {
        logEvent(uid: uid, name: "sign_up", extra: ["email": email])
    }

    func logSignIn(uid: String, email: String) {
        logEvent(uid: uid, name: "sign_in", extra: [:])
    }

    // MARK: - Usage events

    func logBrandSelected(uid: String, vendor: Vendor) {
        logEvent(uid: uid, name: "brand_selected", extra: ["vendor": vendor.rawValue])
    }

    func logFaultLookup(uid: String, vendor: Vendor, code: String) {
        logEvent(uid: uid, name: "fault_lookup", extra: ["vendor": vendor.rawValue, "code": code])
    }

    func logAIAssistUsed(uid: String, vendor: Vendor, code: String) {
        logEvent(uid: uid, name: "ai_assist_used", extra: ["vendor": vendor.rawValue, "code": code])
    }

    func logAIAssistToggled(uid: String, enabled: Bool) {
        logEvent(uid: uid, name: "ai_assist_toggled", extra: ["enabled": enabled])
    }

    // MARK: - Core writer

    private func logEvent(uid: String, name: String, extra: [String: Any]) {
        let event = AnalyticsEvent(uid: uid, name: name, extra: extra, timestamp: Date())
        recentEvents.append(event)
        #if DEBUG
        print("[Analytics] \(name) uid=\(uid) \(extra)")
        #endif
    }
}
