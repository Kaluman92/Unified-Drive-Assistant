//
//  VibrationAnalysisView.swift
//  Unified Drive Assistant
//
//  ============================================================
//  SENSORS BLOCK — VIBRATION ANALYSIS UI
//  ------------------------------------------------------------
//  Flow: (optionally) scan the motor's nameplate to get its rated
//  power, which sets the machine class -> hold the phone flat
//  against the motor casing -> capture ~4s of accelerometer data
//  -> see the signature and a verdict against the severity bands.
//  ============================================================

import SwiftUI
import PhotosUI

struct VibrationAnalysisView: View {
    @StateObject private var capture = VibrationCapture()
    @StateObject private var permission = CameraPermission()
    @State private var machineClass: MachineClass = .classII
    @State private var nameplate: MotorNameplateData?
    @State private var showImagePicker = false
    @State private var selectedImage: UIImage?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: UDATheme.spacingM) {

                nameplateSection

                machineClassSection

                captureSection

                if let result = capture.lastResult {
                    resultSection(result)
                    severityLegend(for: result.machineClass)
                }

                if let error = capture.errorMessage {
                    Text(error)
                        .font(UDATheme.caption)
                        .foregroundColor(UDATheme.danger)
                }

                calibrationWarning
            }
            .padding(UDATheme.spacingM)
        }
        .background(UDATheme.background)
        .navigationTitle("Vibration Analysis")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showImagePicker) {
            NameplateImagePicker(image: $selectedImage)
        }
        .onChange(of: selectedImage) { _, newImage in
            guard let newImage else { return }
            NameplateScanner.scan(image: newImage) { data in
                DispatchQueue.main.async {
                    nameplate = data
                    if let kw = data.ratedPowerKW {
                        machineClass = MachineClass.from(ratedPowerKW: kw)
                    }
                }
            }
        }
    }

    private var calibrationWarning: some View {
        Text("⚠️ Indicative only — not a calibrated vibration instrument.")
            .font(UDATheme.caption)
            .foregroundColor(UDATheme.textSecondary)
            .padding(UDATheme.spacingS)
            .background(UDATheme.surfaceElevated)
            .cornerRadius(UDATheme.chamferSmall)
    }

    private var nameplateSection: some View {
        VStack(alignment: .leading, spacing: UDATheme.spacingS) {
            Text("MOTOR NAMEPLATE").font(UDATheme.caption).foregroundColor(UDATheme.textSecondary).tracking(1)

            CameraPermissionBanner(permission: permission)

            Button {
                permission.ensureAuthorized {
                    showImagePicker = true
                }
            } label: {
                Label("Scan nameplate photo", systemImage: "camera")
            }
            .foregroundColor(UDATheme.accentPressed)
            .disabled(permission.status == .deniedOrRestricted)

            if let nameplate {
                if let kw = nameplate.ratedPowerKW {
                    Text("Detected: \(String(format: "%.1f", kw)) kW")
                        .font(UDATheme.body)
                        .foregroundColor(UDATheme.textPrimary)
                } else {
                    Text("Couldn't read a power rating — set machine class manually.")
                        .font(UDATheme.caption)
                        .foregroundColor(UDATheme.textSecondary)
                }
                if let rpm = nameplate.ratedSpeedRPM {
                    Text("Detected: \(Int(rpm)) RPM")
                        .font(UDATheme.body)
                        .foregroundColor(UDATheme.textPrimary)
                }
            }
        }
        .udaCard()
    }

    private var machineClassSection: some View {
        VStack(alignment: .leading, spacing: UDATheme.spacingS) {
            Text("MACHINE CLASS").font(UDATheme.caption).foregroundColor(UDATheme.textSecondary).tracking(1)
            Picker("Machine class", selection: $machineClass) {
                ForEach(MachineClass.allCases, id: \.self) { c in
                    Text(c.rawValue).tag(c)
                }
            }
            .pickerStyle(.menu)
            .tint(UDATheme.accentPressed)
        }
        .udaCard()
    }

    private var captureSection: some View {
        VStack(spacing: UDATheme.spacingM) {
            if capture.isCapturing {
                VStack(spacing: UDATheme.spacingS) {
                    ProgressView(value: capture.progress)
                        .tint(UDATheme.accent)
                    Text("Hold the phone steady against the motor casing…")
                        .font(UDATheme.caption)
                        .foregroundColor(UDATheme.textSecondary)
                    Button("Cancel", role: .destructive) { capture.cancel() }
                        .font(UDATheme.caption)
                }
            } else {
                Button {
                    capture.startCapture(machineClass: machineClass) { _ in }
                } label: {
                    Text("Start 10-second capture")
                }
                .udaPrimaryButton()
            }
        }
        .udaCard()
    }

    private func resultSection(_ result: VibrationSignature) -> some View {
        VStack(alignment: .leading, spacing: UDATheme.spacingS) {
            Text("SIGNATURE").font(UDATheme.caption).foregroundColor(UDATheme.textSecondary).tracking(1)

            HStack {
                Text(result.severity.rawValue)
                    .font(UDATheme.headline)
                    .foregroundColor(Color(hex: result.severity.colorHex))
                Spacer()
                Text(result.machineClass.rawValue)
                    .font(UDATheme.caption)
                    .foregroundColor(UDATheme.textSecondary)
            }

            if result.isBelowNoiseFloor {
                Text("No significant vibration detected — within sensor noise floor.")
                    .font(UDATheme.caption)
                    .foregroundColor(UDATheme.textSecondary)
            }

            Divider().background(UDATheme.divider)

            resultRow("Dominant frequency", result.isBelowNoiseFloor ? "—" : String(format: "%.1f Hz", result.dominantFrequencyHz))
            resultRow("Velocity (RMS, approx.)", String(format: "%.2f mm/s", result.velocityMmPerSecRMS))
            resultRow("Peak acceleration", String(format: "%.2f g", result.peakAccelerationG))

            Text("Near running speed → imbalance; ~2× running speed → misalignment; high frequency → bearing wear. General patterns, not a diagnosis.")
                .font(UDATheme.caption)
                .foregroundColor(UDATheme.textSecondary)
                .padding(.top, UDATheme.spacingXS)
        }
        .udaCard()
    }

    private func resultRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundColor(UDATheme.textSecondary)
            Spacer()
            Text(value).foregroundColor(UDATheme.textPrimary)
        }
        .font(UDATheme.body)
    }

    /// Compact legend: colour, tier name, one-line meaning, and the actual
    /// mm/s range for the currently selected machine class — since the
    /// thresholds shift depending on machine size.
    private func severityLegend(for machineClass: MachineClass) -> some View {
        VStack(alignment: .leading, spacing: UDATheme.spacingXS) {
            Text("WHAT THE RESULT MEANS").font(UDATheme.caption).foregroundColor(UDATheme.textSecondary).tracking(1)
            ForEach(VibrationSeverity.allCases, id: \.self) { severity in
                HStack(spacing: UDATheme.spacingS) {
                    Circle()
                        .fill(Color(hex: severity.colorHex))
                        .frame(width: 8, height: 8)
                    Text(severity.rawValue)
                        .font(UDATheme.caption)
                        .foregroundColor(UDATheme.textPrimary)
                        .frame(width: 90, alignment: .leading)
                    Text(machineClass.rangeLabel(for: severity) + " mm/s")
                        .font(UDATheme.caption)
                        .foregroundColor(UDATheme.textSecondary)
                        .frame(width: 90, alignment: .leading)
                    Text(severity.briefMeaning)
                        .font(UDATheme.caption)
                        .foregroundColor(UDATheme.textSecondary)
                }
            }
        }
        .udaCard()
    }
}

/// Minimal camera/photo picker for the nameplate photo.
struct NameplateImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: NameplateImagePicker
        init(_ parent: NameplateImagePicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            parent.image = info[.originalImage] as? UIImage
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

#Preview {
    NavigationStack { VibrationAnalysisView() }
}
