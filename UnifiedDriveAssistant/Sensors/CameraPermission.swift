//
//  CameraPermission.swift
//  Unified Drive Assistant
//
//  ============================================================
//  SENSORS BLOCK — CAMERA PERMISSION GATE
//  ------------------------------------------------------------
//  Shared by every camera-based tool (Optical Tachometer, Linear
//  Speed Tracker, nameplate scanning in Vibration Analysis) so
//  none of them ever touch AVCaptureSession/UIImagePickerController
//  without first checking authorization. The crash this fixes came
//  from starting camera configuration before permission was
//  granted — now every entry point checks status first and shows a
//  message + "Open Settings" link instead of attempting to
//  configure the camera at all when it isn't authorized.
//
//  ONE THING NO CODE CHANGE CAN FIX: if `NSCameraUsageDescription`
//  is missing from your Xcode target's Info tab entirely (not just
//  "not yet granted" — actually absent from Info.plist), iOS
//  terminates the app immediately and unconditionally the moment
//  ANY code touches the camera, before this permission check even
//  runs. That's an OS-level requirement, not something this file
//  can guard against — see App/InfoPlist-AdditionsNeeded.md. If
//  you're still crashing after this fix, check that key is
//  actually present first.
//  ============================================================

import Foundation
import AVFoundation
import SwiftUI

enum CameraPermissionStatus {
    case authorized
    case notDetermined
    case deniedOrRestricted
}

@MainActor
final class CameraPermission: ObservableObject {
    @Published private(set) var status: CameraPermissionStatus

    init() {
        self.status = Self.currentStatus()
    }

    static func currentStatus() -> CameraPermissionStatus {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return .authorized
        case .notDetermined: return .notDetermined
        case .denied, .restricted: return .deniedOrRestricted
        @unknown default: return .deniedOrRestricted
        }
    }

    /// Re-checks the OS-level status — call when the app returns to the
    /// foreground after the user may have changed Settings.
    func refresh() {
        status = Self.currentStatus()
    }

    /// Only meaningful when status is .notDetermined — shows the system's
    /// one-time permission prompt. Calling this when already denied does
    /// nothing (iOS won't re-prompt; the user must use Settings).
    func request(completion: @escaping (Bool) -> Void = { _ in }) {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            Task { @MainActor in
                self.status = granted ? .authorized : .deniedOrRestricted
                completion(granted)
            }
        }
    }

    /// Call this instead of touching AVCaptureSession/UIImagePickerController
    /// directly. Requests access if undetermined, and only calls `onReady`
    /// once permission is actually granted — never configures the camera
    /// on a denied/restricted/undetermined path.
    func ensureAuthorized(onReady: @escaping () -> Void) {
        switch status {
        case .authorized:
            onReady()
        case .notDetermined:
            request { granted in
                if granted { onReady() }
            }
        case .deniedOrRestricted:
            break   // caller's UI should already be showing CameraPermissionBanner instead of a working button
        }
    }
}

/// Drop this into any camera-tool screen. Shows nothing when authorized;
/// shows an explanation + "Open Settings" link when denied/restricted.
struct CameraPermissionBanner: View {
    @ObservedObject var permission: CameraPermission

    var body: some View {
        if permission.status == .deniedOrRestricted {
            VStack(alignment: .leading, spacing: UDATheme.spacingS) {
                Text("Camera access is off for Unified Drive Assistant, so this tool can't run.")
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
