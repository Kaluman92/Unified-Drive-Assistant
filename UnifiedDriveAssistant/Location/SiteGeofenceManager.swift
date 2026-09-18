//
//  SiteGeofenceManager.swift
//  Unified Drive Assistant
//
//  ============================================================
//  LOCATION BLOCK — BACKGROUND SITE ALERTS (opt-in, geofenced)
//  ------------------------------------------------------------
//  Posts a local notification when the person physically enters
//  the vicinity of a site they've previously saved a fault visit
//  at — even with the app fully closed. This requires "Always"
//  location access, a real step up from the "when in use only"
//  design everywhere else in this app, and is ONLY ever activated
//  by an explicit toggle in Settings — never silently.
//
//  HOW IT WORKS (and why it's not continuous tracking):
//  Uses CoreLocation's REGION MONITORING (CLCircularRegion +
//  startMonitoring(for:)), not continuous location polling. iOS's
//  location daemon watches for entry into small, specific regions
//  on the app's behalf, waking it briefly only on an actual
//  boundary crossing — the app doesn't run continuously in the
//  background and isn't tracking movement generally, only whether
//  you've crossed into one of a small number of regions you
//  yourself created by saving a site visit.
//
//  REAL LIMITATION: iOS caps region monitoring at 20 regions per
//  app, system-wide, no exceptions. Since `SiteVisitStore` stores
//  newest-first, `refreshGeofences()` monitors the 20 MOST RECENT
//  visits with valid coordinates — older sites silently stop
//  getting background alerts once you have more than 20 saved.
//  They still show up fully in Site History; only the background
//  alert coverage is capped.
//
//  NO PAID APPLE DEVELOPER PROGRAM NEEDED: local notifications
//  (UNUserNotificationCenter) are different from remote/push
//  notifications — only push requires the paid Program. Region
//  monitoring likewise needs no special capability beyond the
//  "Always" authorization itself.
//  ============================================================

import Foundation
import CoreLocation
import UserNotifications

@MainActor
final class SiteGeofenceManager: NSObject, ObservableObject {

    static let shared = SiteGeofenceManager()

    /// Hard iOS system limit — cannot be raised.
    private let maxMonitoredRegions = 20
    /// Matches the existing "nearby visits" radius elsewhere in the app,
    /// for consistent behaviour between the in-app banner and background
    /// alerts.
    private let geofenceRadius: CLLocationDistance = 200

    @Published private(set) var isEnabled = false
    @Published private(set) var monitoredSiteCount = 0

    private let manager: CLLocationManager

    private override init() {
        manager = CLLocationManager()
        super.init()
        manager.delegate = self
        UNUserNotificationCenter.current().delegate = self
        isEnabled = UserDefaults.standard.bool(forKey: "background_site_alerts_enabled")
    }

    /// Call from the Settings toggle. Requests both the location upgrade
    /// and notification permission — both are real system prompts, and
    /// this is the only place either gets requested from.
    func enable() {
        UserDefaults.standard.set(true, forKey: "background_site_alerts_enabled")
        isEnabled = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            print("📍 [SiteGeofenceManager] notification permission granted=\(granted)")
        }
        LocationPermission.shared.requestAlwaysAuthorization()
        // If already Always-authorized (e.g. re-enabling after a previous
        // grant), refreshGeofences() won't be triggered by a fresh
        // delegate callback, so call it directly too.
        if LocationPermission.shared.isAlwaysAuthorized {
            refreshGeofences()
        }
    }

    func disable() {
        UserDefaults.standard.set(false, forKey: "background_site_alerts_enabled")
        isEnabled = false
        for region in manager.monitoredRegions {
            manager.stopMonitoring(for: region)
        }
        monitoredSiteCount = 0
    }

    /// Re-syncs monitored regions with the current SiteVisitStore contents.
    /// Call whenever a new visit is saved, and once after Always
    /// authorization is granted.
    func refreshGeofences() {
        guard isEnabled, LocationPermission.shared.isAlwaysAuthorized else { return }

        for region in manager.monitoredRegions {
            manager.stopMonitoring(for: region)
        }

        let candidates = SiteVisitStore.shared.visits
            .compactMap { visit -> (SiteVisit, CLLocationCoordinate2D)? in
                guard let lat = visit.latitude, let lon = visit.longitude else { return nil }
                return (visit, CLLocationCoordinate2D(latitude: lat, longitude: lon))
            }
            .prefix(maxMonitoredRegions)   // store is newest-first, so this is the 20 most recent

        for (visit, coordinate) in candidates {
            let region = CLCircularRegion(center: coordinate, radius: geofenceRadius, identifier: visit.id.uuidString)
            region.notifyOnEntry = true
            region.notifyOnExit = false
            manager.startMonitoring(for: region)
        }
        monitoredSiteCount = candidates.count
        print("📍 [SiteGeofenceManager] now monitoring \(candidates.count) region(s)")
    }

    private func postNotification(for visit: SiteVisit) {
        let content = UNMutableNotificationContent()
        content.title = "You're near a saved site"
        content.body = "\(visit.siteName) — \(visit.vendor) \(visit.faultCode) logged here before. Tap to view history."
        content.sound = .default
        let request = UNNotificationRequest(identifier: "geofence_\(visit.id.uuidString)_\(Date().timeIntervalSince1970)",
                                             content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

extension SiteGeofenceManager: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        print("📍 [SiteGeofenceManager] didEnterRegion — \(region.identifier)")
        Task { @MainActor in
            guard let uuid = UUID(uuidString: region.identifier),
                  let visit = SiteVisitStore.shared.visits.first(where: { $0.id == uuid }) else { return }
            self.postNotification(for: visit)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        print("📍 [SiteGeofenceManager] monitoring failed for region \(region?.identifier ?? "unknown"): \(error)")
    }
}

extension SiteGeofenceManager: UNUserNotificationCenterDelegate {
    /// Without this, local notifications are silently suppressed while the
    /// app is in the foreground — this makes them show as a banner + sound
    /// regardless of whether the app happens to be open when a geofence
    /// triggers, same as if the app were closed.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                             willPresent notification: UNNotification,
                                             withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .badge])
    }
}
