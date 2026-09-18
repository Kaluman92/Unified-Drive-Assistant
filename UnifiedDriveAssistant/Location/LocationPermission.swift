//
//  LocationPermission.swift
//  Unified Drive Assistant
//
//  ============================================================
//  LOCATION BLOCK — PERMISSION + ONE-SHOT LOCATION
//  ------------------------------------------------------------
//  Rewritten against the standard, widely-used CoreLocation
//  pattern (the same shape Apple's own sample code and most
//  production apps use) after two earlier fix attempts (moving
//  the request logic around, converting to a singleton) didn't
//  resolve a real-device "location never resolves, no error
//  either" report where every external cause was ruled out
//  (global toggle on, Maps/Weather worked fine on the same
//  device/network, no restriction profiles, full app relaunch).
//
//  KEY SIMPLIFICATION vs the previous version: one entry point,
//  `requestLocationAccess()`. No caller-supplied completion
//  closures — the delegate itself calls `requestLocation()`
//  directly the moment authorization is confirmed, whether that's
//  immediately (already authorized) or after the system prompt is
//  answered (`locationManagerDidChangeAuthorization`). This is
//  the standard shape; the previous custom `ensureAuthorized(onReady:)`
//  indirection added complexity without a clear benefit and is
//  removed here as one of the suspects.
//
//  DIAGNOSTIC LOGGING: every step prints to the console (search for
//  📍). If this still doesn't work, the next console log will show
//  exactly which step is failing — whether requestLocation() is
//  even being called, whether the delegate fires at all, etc. —
//  instead of guessing again.
//
//  This app defaults to "when in use" only — never "always" /
//  background tracking — UNLESS the person explicitly opts into
//  background site alerts in Settings (see `requestAlwaysAuthorization()`
//  below and `Location/SiteGeofenceManager.swift`). That upgrade is
//  never requested silently; it's only triggered by a deliberate
//  toggle, and even then it's used only for geofencing around the
//  person's own saved sites — event-driven entry alerts, not
//  continuous location polling.
//
//  ONE THING NO CODE CHANGE CAN FIX: if `NSLocationWhenInUseUsageDescription`
//  is missing from your Xcode target's Info tab entirely, iOS
//  terminates the app the moment any code requests location,
//  before this permission check even runs. See
//  App/InfoPlist-AdditionsNeeded.md.
//  ============================================================

import Foundation
import CoreLocation
import SwiftUI

enum LocationPermissionStatus {
    case authorized
    case notDetermined
    case deniedOrRestricted
}

@MainActor
final class LocationPermission: NSObject, ObservableObject, CLLocationManagerDelegate {

    static let shared = LocationPermission()

    @Published private(set) var status: LocationPermissionStatus = .notDetermined
    @Published private(set) var currentLocation: CLLocation?
    @Published private(set) var lastErrorDescription: String?
    /// True only after the person has explicitly opted into background
    /// site alerts (Settings) and granted the "Always" upgrade. Never
    /// requested automatically.
    @Published private(set) var isAlwaysAuthorized: Bool = false

    private let manager: CLLocationManager

    private override init() {
        manager = CLLocationManager()
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        status = Self.map(manager.authorizationStatus)
        isAlwaysAuthorized = (manager.authorizationStatus == .authorizedAlways)

        // DEFINITIVE CHECK — settles the Info.plist question with code
        // instead of reading the Xcode UI, which hasn't been conclusive.
        // This reads the ACTUAL COMPILED app bundle's Info.plist at
        // runtime, not the Xcode project source table.
        if let value = Bundle.main.object(forInfoDictionaryKey: "NSLocationWhenInUseUsageDescription") as? String, !value.isEmpty {
            print("📍 [LocationPermission] ✅ NSLocationWhenInUseUsageDescription IS present in the compiled app: \"\(value)\"")
        } else {
            print("📍 [LocationPermission] ❌ NSLocationWhenInUseUsageDescription is MISSING or EMPTY in the compiled app's Info.plist. THIS is why the permission dialog never appears — add it in the target's Info tab, then delete the app from your phone and reinstall (not just rebuild).")
        }
        print("📍 [LocationPermission] init — initial authorizationStatus.rawValue=\(manager.authorizationStatus.rawValue), mapped status=\(status)")
    }

    private static func map(_ status: CLAuthorizationStatus) -> LocationPermissionStatus {
        switch status {
        case .authorizedAlways, .authorizedWhenInUse: return .authorized
        case .notDetermined: return .notDetermined
        case .denied, .restricted: return .deniedOrRestricted
        @unknown default: return .deniedOrRestricted
        }
    }

    /// Single entry point. Requests the system permission prompt if not
    /// yet determined; if already authorized, immediately requests a
    /// one-shot location. This is the whole API — no completion closures,
    /// no separate "request permission" vs "request location" calls from
    /// outside this class.
    func requestLocationAccess() {
        print("📍 [LocationPermission] requestLocationAccess() called — current status=\(status)")
        switch status {
        case .authorized:
            print("📍 already authorized — calling manager.requestLocation() now")
            manager.requestLocation()
        case .notDetermined:
            print("📍 not determined — calling manager.requestWhenInUseAuthorization()")
            manager.requestWhenInUseAuthorization()
        case .deniedOrRestricted:
            print("📍 denied/restricted — doing nothing, banner should already explain why")
        }
    }

    /// Manual retry after a failure, or to refresh an existing fix.
    func retryLocation() {
        print("📍 [LocationPermission] retryLocation() called — status=\(status)")
        lastErrorDescription = nil
        guard status == .authorized else { return }
        manager.requestLocation()
    }

    /// Upgrades to "Always" access — ONLY call this from an explicit user
    /// action (the "Background site alerts" toggle in Settings), never
    /// automatically. Apple's two-step flow requires "When In Use" to
    /// already be granted before this upgrade can be requested; if it
    /// isn't yet, this requests that first and the upgrade prompt follows
    /// once the person grants it.
    func requestAlwaysAuthorization() {
        print("📍 [LocationPermission] requestAlwaysAuthorization() called — current status=\(status)")
        guard status == .authorized else {
            print("📍 not yet authorized for When In Use — requesting that first")
            requestLocationAccess()
            return
        }
        manager.requestAlwaysAuthorization()
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let rawStatus = manager.authorizationStatus
        print("📍 [delegate] locationManagerDidChangeAuthorization fired — rawValue=\(rawStatus.rawValue)")
        Task { @MainActor in
            self.status = Self.map(rawStatus)
            self.isAlwaysAuthorized = (rawStatus == .authorizedAlways)
            print("📍 [delegate→MainActor] status now \(self.status), isAlwaysAuthorized=\(self.isAlwaysAuthorized)")
            if self.status == .authorized {
                print("📍 now authorized — calling manager.requestLocation() from delegate")
                self.manager.requestLocation()
            }
            if self.isAlwaysAuthorized {
                SiteGeofenceManager.shared.refreshGeofences()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        print("📍 [delegate] didUpdateLocations fired — count=\(locations.count)")
        guard let location = locations.last else { return }
        Task { @MainActor in
            self.currentLocation = location
            self.lastErrorDescription = nil
            print("📍 [delegate→MainActor] currentLocation set: lat=\(location.coordinate.latitude), lon=\(location.coordinate.longitude)")
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("📍 [delegate] didFailWithError fired — \(error)")
        let description: String
        if let clError = error as? CLError {
            switch clError.code {
            case .denied:
                description = "Location access denied"
            case .locationUnknown:
                description = "Location temporarily unavailable (common indoors/underground)"
            case .network:
                description = "Network error while resolving location"
            default:
                description = "CoreLocation error: \(clError.code.rawValue)"
            }
        } else {
            description = error.localizedDescription
        }
        Task { @MainActor in
            self.lastErrorDescription = description
            print("📍 [delegate→MainActor] lastErrorDescription set: \(description)")
        }
    }
}

/// Drop this into any location-feature screen. Shows nothing when
/// authorized; shows an explanation + "Open Settings" link when
/// denied/restricted.
struct LocationPermissionBanner: View {
    @ObservedObject var permission: LocationPermission

    var body: some View {
        if permission.status == .deniedOrRestricted {
            VStack(alignment: .leading, spacing: UDATheme.spacingS) {
                Text("Location access is off, so site history can't be tagged or looked up here.")
                    .font(UDATheme.caption)
                    .foregroundColor(UDATheme.textSecondary)
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .font(UDATheme.caption)
                .foregroundColor(UDATheme.accentPressed)
            }
            .padding(UDATheme.spacingS)
            .background(UDATheme.surfaceElevated)
            .cornerRadius(UDATheme.chamferSmall)
        }
    }
}
