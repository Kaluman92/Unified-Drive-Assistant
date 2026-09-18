//
//  VSDSizingView.swift
//  Unified Drive Assistant
//
//  ============================================================
//  SIZING BLOCK — UI
//  ------------------------------------------------------------
//  Vendor tabs here only change which set of editable
//  margin/derating defaults are pre-filled — see
//  VSDSizingEngine.swift's header for why those defaults are
//  generic placeholders, not the vendor's real published figures.
//  ============================================================

import SwiftUI

struct VSDSizingView: View {
    @State private var vendor: Vendor = .siemens

    @State private var powerKW: String = "22"
    @State private var voltage: String = "400"
    @State private var powerFactor: String = "0.85"
    @State private var efficiency: String = "0.93"

    @State private var oversizingMargin: String = "10"
    @State private var altitude: String = "0"
    @State private var ambientTemp: String = "30"
    @State private var altitudeDerateRate: String = "1.0"
    @State private var tempDerateRate: String = "2.0"

    @State private var showBraking = false
    @State private var inertia: String = "5"
    @State private var speedRPM: String = "1450"
    @State private var decelTime: String = "3"
    @State private var dutyCycle: String = "60"
    @State private var dcBusVoltage: String = "770"

    // Built here, outside any ViewBuilder closure, because a ViewBuilder body
    // can only contain declarations and View-returning expressions — a plain
    // mutation statement like `derating.x = y` doesn't fit either, which is
    // exactly what caused the "buildExpression is unavailable" errors below.
    private var motorInput: MotorSizingInput {
        MotorSizingInput(
            ratedPowerKW: Double(powerKW) ?? 0,
            lineVoltage: Double(voltage) ?? 0,
            powerFactor: Double(powerFactor) ?? 0,
            efficiency: Double(efficiency) ?? 0
        )
    }

    private var deratingInput: DriveDeratingInput {
        var derating = DriveDeratingInput()
        derating.oversizingMarginPercent = Double(oversizingMargin) ?? 0
        derating.altitudeMeters = Double(altitude) ?? 0
        derating.altitudeDeratePercentPer100mAbove1000m = Double(altitudeDerateRate) ?? 1.0
        derating.ambientTempC = Double(ambientTemp) ?? 30
        derating.tempDeratePercentPerDegreeAbove40C = Double(tempDerateRate) ?? 2.0
        return derating
    }

    var body: some View {
        Form {
            Section("Manufacturer") {
                Picker("Manufacturer", selection: $vendor) {
                    ForEach(Vendor.allCases) { v in
                        Text(v.rawValue).tag(v)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: vendor) { _, _ in applyVendorDefaults() }
            }
            .listRowBackground(UDATheme.surface)

            Section("Motor") {
                LabeledField(label: "Rated power (kW)", text: $powerKW)
                LabeledField(label: "Line voltage (V)", text: $voltage)
                LabeledField(label: "Power factor (0–1)", text: $powerFactor)
                LabeledField(label: "Efficiency (0–1)", text: $efficiency)
            }
            .listRowBackground(UDATheme.surface)

            Section("Sizing margin & derating") {
                LabeledField(label: "Oversizing margin (%)", text: $oversizingMargin)
                LabeledField(label: "Altitude (m)", text: $altitude)
                LabeledField(label: "Altitude derate (%/100 m > 1000 m)", text: $altitudeDerateRate)
                LabeledField(label: "Ambient temperature (°C)", text: $ambientTemp)
                LabeledField(label: "Temp derate (%/°C > 40°C)", text: $tempDerateRate)
            }
            .listRowBackground(UDATheme.surface)

            Section("Result") {
                let result = VSDSizingEngine.sizeDrive(motor: motorInput, derating: deratingInput)

                ResultRow(label: "Motor full-load current", value: String(format: "%.1f A", result.motorFullLoadCurrentA))
                ResultRow(label: "Total derating applied", value: String(format: "%.1f %%", result.totalDeratePercent))
                ResultRow(label: "Minimum drive current rating", value: String(format: "%.1f A", result.requiredDriveCurrentA), emphasized: true)
            }
            .listRowBackground(UDATheme.surface)

            Section {
                Toggle("Include braking resistor / regen sizing", isOn: $showBraking.animation())
                    .tint(UDATheme.accent)
            }
            .listRowBackground(UDATheme.surface)

            if showBraking {
                Section("Load & braking") {
                    LabeledField(label: "Total inertia at motor shaft (kg·m²)", text: $inertia)
                    LabeledField(label: "Speed being decelerated from (RPM)", text: $speedRPM)
                    LabeledField(label: "Deceleration time (s)", text: $decelTime)
                    LabeledField(label: "Duty cycle period (s)", text: $dutyCycle)
                    LabeledField(label: "DC bus chopper threshold (V)", text: $dcBusVoltage)
                }
                .listRowBackground(UDATheme.surface)
                .transition(.opacity)

                Section("Braking resistor result") {
                    let input = BrakingSizingInput(
                        totalInertiaKgM2: Double(inertia) ?? 0,
                        speedRPM: Double(speedRPM) ?? 0,
                        decelTimeSeconds: Double(decelTime) ?? 0,
                        dutyCycleSeconds: Double(dutyCycle) ?? 0,
                        dcBusTripVoltage: Double(dcBusVoltage) ?? 770
                    )
                    let result = VSDSizingEngine.sizeBraking(input)

                    ResultRow(label: "Peak braking power", value: String(format: "%.2f kW", result.peakBrakingPowerKW), emphasized: true)
                    ResultRow(label: "Continuous power rating (resistor)", value: String(format: "%.2f kW", result.continuousPowerRatingKW))
                    ResultRow(label: "Recommended resistor value", value: String(format: "%.1f Ω", result.recommendedResistorOhms), emphasized: true)
                    ResultRow(label: "Duty cycle", value: String(format: "%.1f %%", result.dutyCyclePercent))
                }
                .listRowBackground(UDATheme.surface)
                .transition(.opacity)
            }

            Section {
                Text("⚠️ Estimate only, from generic physics-based defaults — confirm against \(vendor.rawValue)'s actual datasheet before ordering equipment.")
                    .font(UDATheme.caption)
                    .foregroundColor(UDATheme.textSecondary)
            }
            .listRowBackground(UDATheme.surfaceElevated)
        }
        .animation(.easeInOut(duration: 0.2), value: showBraking)
        .scrollContentBackground(.hidden)
        .background(UDATheme.background)
        .navigationTitle("VSD Sizing")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Vendor tabs currently exist for UI organization only — they do NOT
    /// encode real per-vendor differences, because I don't have a genuine
    /// published source for each manufacturer's exact oversizing margin or
    /// DC bus chopper threshold. Every vendor gets the same generic
    /// placeholder default below. If you supply the real published figure
    /// for a given manufacturer/model, tell me and I'll make this switch
    /// statement actually vendor-specific instead of a no-op.
    private func applyVendorDefaults() {
        oversizingMargin = "10"
        dcBusVoltage = "770"
    }
}

private struct LabeledField: View {
    let label: String
    @Binding var text: String
    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(UDATheme.textSecondary)
            Spacer()
            TextField("", text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .foregroundColor(UDATheme.textPrimary)
        }
    }
}

private struct ResultRow: View {
    let label: String
    let value: String
    var emphasized: Bool = false
    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(UDATheme.textSecondary)
            Spacer()
            Text(value)
                .font(emphasized ? UDATheme.bodyBold : UDATheme.body)
                .foregroundColor(emphasized ? UDATheme.accentPressed : UDATheme.textPrimary)
        }
    }
}

#Preview {
    VSDSizingView()
}
