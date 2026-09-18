//
//  SpeedMeasurementView.swift
//  Unified Drive Assistant
//
//  ============================================================
//  SENSORS BLOCK — SPEED MEASUREMENT UI
//  ------------------------------------------------------------
//  Two genuinely different techniques behind one screen:
//  - Rotational (RPM): OpticalTachometer — blink-frequency FFT,
//    no calibration needed, for shafts/couplings/fans.
//  - Linear (m/s): LinearSpeedTracker — Vision object tracking,
//    REQUIRES a known real-world reference distance first, for
//    belts/conveyors/anything moving in a line.
//  See each engine file's header for why they're built differently.
//
//  CAMERA LIFECYCLE: each mode's live preview activates as soon as
//  its view appears (`.onAppear`) and deactivates when it's swapped
//  out or the screen closes (`.onDisappear`) — see the "PREVIEW vs
//  MEASURING" note in OpticalTachometer.swift for why this changed
//  from the earlier version, where the preview stayed blank until
//  you tapped Start. Only one mode's camera session runs at a
//  time; switching modes tears down the other's session first.
//  ============================================================

import SwiftUI
import AVFoundation

private enum SpeedMode: String, CaseIterable, Identifiable {
    case rotational = "Rotational (RPM)"
    case linear = "Linear (m/s)"
    var id: String { rawValue }
}

struct SpeedMeasurementView: View {
    @State private var mode: SpeedMode = .rotational
    @StateObject private var tachometer = OpticalTachometer()
    @StateObject private var linearTracker = LinearSpeedTracker()

    @State private var calibrationDistanceText: String = "1.0"

    var body: some View {
        VStack(spacing: 0) {
            Picker("Mode", selection: $mode) {
                ForEach(SpeedMode.allCases) { m in
                    Text(m.rawValue).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, UDATheme.spacingM)
            .padding(.top, UDATheme.spacingS)

            Group {
                if mode == .rotational {
                    rotationalView
                } else {
                    linearView
                }
            }
            .transition(.opacity)

            disclaimerBanner
        }
        .animation(.easeInOut(duration: 0.2), value: mode)
        .background(UDATheme.background)
        .navigationTitle("Speed Measurement")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            // Safety net — each subview already tears down its own camera on
            // its own onDisappear, but this covers leaving the whole screen.
            tachometer.deactivatePreview()
            linearTracker.deactivatePreview()
        }
    }

    private var disclaimerBanner: some View {
        Text("⚠️ Baseline readings only — not verified/certified measurements.")
            .font(UDATheme.caption)
            .foregroundColor(UDATheme.textSecondary)
            .padding(UDATheme.spacingS)
            .background(UDATheme.surfaceElevated)
            .cornerRadius(UDATheme.chamferSmall)
            .padding(.horizontal, UDATheme.spacingM)
            .padding(.top, UDATheme.spacingM)
    }

    // MARK: - Rotational (RPM)

    private var rotationalView: some View {
        VStack(spacing: UDATheme.spacingM) {
            CameraPermissionBanner(permission: tachometer.permission)
                .padding(.horizontal, UDATheme.spacingM)

            ZStack {
                CameraPreviewView(session: tachometer.session)
                    .cornerRadius(UDATheme.chamferMedium)
                    .overlay(
                        Rectangle()
                            .stroke(UDATheme.accent, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                            .frame(width: 100, height: 100)
                    )

                if !tachometer.isPreviewActive {
                    Text(tachometer.permission.status == .deniedOrRestricted
                         ? "Camera off"
                         : "Starting camera…")
                        .font(UDATheme.caption)
                        .foregroundColor(UDATheme.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 300)
            .padding(.horizontal, UDATheme.spacingM)

            Text("Align a contrast mark on the shaft with the dashed box.")
                .font(UDATheme.caption)
                .foregroundColor(UDATheme.textSecondary)
                .padding(.horizontal, UDATheme.spacingM)

            if let rpm = tachometer.currentRPM {
                Text(String(format: "%.0f RPM", rpm))
                    .font(UDATheme.faultCodeLg)
                    .foregroundColor(UDATheme.accentPressed)
                Text("Baseline reading — not a certified measurement")
                    .font(UDATheme.caption)
                    .foregroundColor(UDATheme.textSecondary)
            } else if tachometer.isRunning && tachometer.isStationary {
                Text("Stationary")
                    .font(UDATheme.faultCodeLg)
                    .foregroundColor(UDATheme.textSecondary)
                Text("No rotation detected — object appears stationary, or no mark is in view.")
                    .font(UDATheme.caption)
                    .foregroundColor(UDATheme.textSecondary)
            }

            if let error = tachometer.errorMessage {
                Text(error).font(UDATheme.caption).foregroundColor(UDATheme.danger)
            }

            Button(tachometer.isRunning ? "Stop" : "Start measuring") {
                tachometer.isRunning ? tachometer.stopMeasuring() : tachometer.startMeasuring()
            }
            .udaPrimaryButton()
            .disabled(tachometer.permission.status == .deniedOrRestricted || !tachometer.isPreviewActive)
            .padding(.horizontal, UDATheme.spacingM)

            Spacer()
        }
        .padding(.top, UDATheme.spacingM)
        .onAppear { tachometer.activatePreview() }
        .onDisappear { tachometer.deactivatePreview() }
    }

    // MARK: - Linear (m/s)

    private var linearView: some View {
        VStack(spacing: UDATheme.spacingM) {
            CameraPermissionBanner(permission: linearTracker.permission)
                .padding(.horizontal, UDATheme.spacingM)

            if !linearTracker.isCalibrated {
                calibrationView
            } else {
                trackingView
            }
        }
        .padding(.top, UDATheme.spacingM)
    }

    private var calibrationView: some View {
        VStack(alignment: .leading, spacing: UDATheme.spacingM) {
            Text("CALIBRATE FIRST").font(UDATheme.caption).foregroundColor(UDATheme.textSecondary).tracking(1)
            Text("Requires a known real-world reference distance to convert pixels to speed. Enter the distance between two visible reference points, then calibrate.")
                .font(UDATheme.caption)
                .foregroundColor(UDATheme.textSecondary)

            HStack {
                Text("Reference distance (m)").foregroundColor(UDATheme.textSecondary)
                Spacer()
                TextField("", text: $calibrationDistanceText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .foregroundColor(UDATheme.textPrimary)
                    .frame(width: 80)
            }

            Text("Reference points are at 30% and 70% across the frame — place your markers there first.")
                .font(UDATheme.caption)
                .foregroundColor(UDATheme.textSecondary)

            Button("Calibrate") {
                let distance = Double(calibrationDistanceText) ?? 1.0
                linearTracker.calibrate(
                    pointA: CGPoint(x: 0.3, y: 0.5),
                    pointB: CGPoint(x: 0.7, y: 0.5),
                    realWorldDistanceMeters: distance
                )
            }
            .udaPrimaryButton()

            if let error = linearTracker.errorMessage {
                Text(error).font(UDATheme.caption).foregroundColor(UDATheme.danger)
            }
        }
        .udaCard()
        .padding(.horizontal, UDATheme.spacingM)
    }

    private var trackingView: some View {
        VStack(spacing: UDATheme.spacingM) {
            ZStack {
                CameraPreviewView(session: linearTracker.session)
                    .cornerRadius(UDATheme.chamferMedium)
                    .overlay(
                        Rectangle()
                            .stroke(UDATheme.logoOrange, lineWidth: 2)
                            .frame(width: 80, height: 80)
                    )

                if !linearTracker.isPreviewActive {
                    Text(linearTracker.permission.status == .deniedOrRestricted
                         ? "Camera off"
                         : "Starting camera…")
                        .font(UDATheme.caption)
                        .foregroundColor(UDATheme.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 300)
            .padding(.horizontal, UDATheme.spacingM)

            Text("Frame the moving object in the box, then tap Start.")
                .font(UDATheme.caption)
                .foregroundColor(UDATheme.textSecondary)
                .padding(.horizontal, UDATheme.spacingM)

            if let speed = linearTracker.currentSpeedMPS {
                Text(String(format: "%.2f m/s", speed))
                    .font(UDATheme.faultCodeLg)
                    .foregroundColor(UDATheme.accentPressed)
                Text("Baseline reading — not a certified measurement")
                    .font(UDATheme.caption)
                    .foregroundColor(UDATheme.textSecondary)
            }

            if let error = linearTracker.errorMessage {
                Text(error).font(UDATheme.caption).foregroundColor(UDATheme.danger)
            }

            HStack(spacing: UDATheme.spacingM) {
                Button(linearTracker.isRunning ? "Stop" : "Start") {
                    if linearTracker.isRunning {
                        linearTracker.stopTracking()
                    } else {
                        let box = CGRect(x: 0.42, y: 0.42, width: 0.16, height: 0.16)
                        linearTracker.startTracking(initialTrackingBox: box)
                    }
                }
                .udaPrimaryButton()
                .disabled(linearTracker.permission.status == .deniedOrRestricted || !linearTracker.isPreviewActive)

                Button("Re-calibrate") {
                    linearTracker.stopTracking()
                    linearTracker.isCalibrated = false
                }
                .foregroundColor(UDATheme.textSecondary)
            }
            .padding(.horizontal, UDATheme.spacingM)

            Spacer()
        }
        .onAppear { linearTracker.activatePreview() }
        .onDisappear { linearTracker.deactivatePreview() }
    }
}

#Preview {
    NavigationStack { SpeedMeasurementView() }
}
