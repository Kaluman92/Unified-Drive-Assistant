//
//  ToolsMenuView.swift
//  Unified Drive Assistant
//
//  ============================================================
//  TOOLS BLOCK
//  ------------------------------------------------------------
//  Entry point for everything beyond fault lookup: sizing
//  calculators and phone-sensor tools. Reached from the wrench
//  icon in ContentView's toolbar.
//  ============================================================

import SwiftUI

struct ToolsMenuView: View {
    var body: some View {
        List {
            Section("Sizing") {
                NavigationLink {
                    VSDSizingView()
                } label: {
                    ToolRow(icon: "function", title: "VSD Sizing",
                            subtitle: "Drive current, braking resistor & regen sizing")
                }
            }
            .listRowBackground(UDATheme.surface)

            Section {
                NavigationLink {
                    VibrationAnalysisView()
                } label: {
                    ToolRow(icon: "waveform.path.ecg", title: "Vibration Analysis",
                            subtitle: "Accelerometer signature vs. severity baseline")
                }
                NavigationLink {
                    SpeedMeasurementView()
                } label: {
                    ToolRow(icon: "speedometer", title: "Speed Measurement",
                            subtitle: "Optical RPM tachometer or calibrated linear speed")
                }
            } header: {
                Text("Sensor tools")
            } footer: {
                Text("Indicative, on-site readings — not a substitute for calibrated instruments.")
            }
            .listRowBackground(UDATheme.surface)
        }
        .navigationTitle("Tools")
        .scrollContentBackground(.hidden)
        .background(UDATheme.background)
    }
}

private struct ToolRow: View {
    let icon: String
    let title: String
    let subtitle: String
    var body: some View {
        HStack(spacing: UDATheme.spacingM) {
            Image(systemName: icon)
                .foregroundColor(UDATheme.accentPressed)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(UDATheme.bodyBold).foregroundColor(UDATheme.textPrimary)
                Text(subtitle).font(UDATheme.caption).foregroundColor(UDATheme.textSecondary)
            }
        }
    }
}

#Preview {
    NavigationStack { ToolsMenuView() }
}
