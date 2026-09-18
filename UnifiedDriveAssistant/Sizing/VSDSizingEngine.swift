//
//  VSDSizingEngine.swift
//  Unified Drive Assistant
//
//  ============================================================
//  SIZING BLOCK — CALCULATION ENGINE
//  ------------------------------------------------------------
//  Pure calculation logic, no UI. Every formula here is standard
//  electrical/mechanical engineering physics (motor current from
//  power, kinetic energy dissipation for braking) — not a
//  manufacturer's proprietary selection table.
//
//  IMPORTANT — read before trusting a result:
//  The MARGIN/DERATING DEFAULTS below (oversizing %, altitude
//  derate, temperature derate, DC bus trip voltage) are generic,
//  commonly-seen industry figures, NOT any specific manufacturer's
//  published numbers. Exact figures vary by vendor and even by
//  drive model/firmware. Treat every result as a starting
//  estimate to check against the actual drive's datasheet before
//  ordering equipment — this tool cannot replace that datasheet.
//
//  To make this vendor-exact: supply the manufacturer's published
//  oversizing margin, altitude/temperature derating curve, and DC
//  bus chopper threshold (from a datasheet or manual you have —
//  same "you supply it, I structure it" pattern as the fault
//  data) and I'll wire them in as per-vendor default sets instead
//  of the generic ones below.
//  ============================================================

import Foundation

// MARK: - Inputs

struct MotorSizingInput {
    var ratedPowerKW: Double
    var lineVoltage: Double        // V, line-to-line
    var powerFactor: Double        // 0-1
    var efficiency: Double         // 0-1
    var phases: Int = 3

    /// Standard 3-phase motor full-load current formula: I = P / (√3 · V · PF · η)
    var fullLoadCurrentA: Double {
        guard lineVoltage > 0, powerFactor > 0, efficiency > 0 else { return 0 }
        if phases == 3 {
            return (ratedPowerKW * 1000) / (1.732_05 * lineVoltage * powerFactor * efficiency)
        } else {
            return (ratedPowerKW * 1000) / (lineVoltage * powerFactor * efficiency)
        }
    }
}

struct DriveDeratingInput {
    /// Generic default: many drives derate above 1000 m. This % is a
    /// placeholder, not any vendor's exact curve — see file header.
    var altitudeMeters: Double = 0
    var altitudeDeratePercentPer100mAbove1000m: Double = 1.0

    /// Generic default: many drives derate above 40°C ambient. Placeholder.
    var ambientTempC: Double = 30
    var tempDeratePercentPerDegreeAbove40C: Double = 2.0

    /// Generic default oversizing margin on top of motor FLC. Placeholder —
    /// vendors publish their own recommended margin per application/duty.
    var oversizingMarginPercent: Double = 10.0

    var totalDeratePercent: Double {
        let altitudeAbove1000 = max(0, altitudeMeters - 1000) / 100
        let altitudeDerate = altitudeAbove1000 * altitudeDeratePercentPer100mAbove1000m
        let tempAbove40 = max(0, ambientTempC - 40)
        let tempDerate = tempAbove40 * tempDeratePercentPerDegreeAbove40C
        return min(altitudeDerate + tempDerate, 60)   // clamp so a runaway input can't produce nonsense
    }
}

struct BrakingSizingInput {
    /// Total inertia reflected to the motor shaft (motor + load), kg·m².
    var totalInertiaKgM2: Double
    /// Speed being decelerated from, RPM.
    var speedRPM: Double
    /// Time allowed for the deceleration, seconds.
    var decelTimeSeconds: Double
    /// How often the braking event repeats within a duty cycle, seconds
    /// (e.g. a crane cycle every 60 s) — used for the resistor's
    /// continuous power rating, not just peak.
    var dutyCycleSeconds: Double
    /// DC bus chopper turn-on threshold, volts. Generic placeholder for a
    /// 400 V 3-phase supply — vendors publish their own exact trip point.
    var dcBusTripVoltage: Double = 770
}

// MARK: - Results

struct DriveSizingResult {
    let motorFullLoadCurrentA: Double
    let requiredDriveCurrentA: Double     // after margin + derating
    let totalDeratePercent: Double
}

struct BrakingSizingResult {
    let kineticEnergyJoules: Double
    let peakBrakingPowerKW: Double
    let continuousPowerRatingKW: Double   // averaged over duty cycle
    let recommendedResistorOhms: Double
    let dutyCyclePercent: Double
}

// MARK: - Engine

enum VSDSizingEngine {

    static func sizeDrive(motor: MotorSizingInput, derating: DriveDeratingInput) -> DriveSizingResult {
        let flc = motor.fullLoadCurrentA
        let withMargin = flc * (1 + derating.oversizingMarginPercent / 100)
        let derate = derating.totalDeratePercent
        let required = derate < 100 ? withMargin / (1 - derate / 100) : withMargin
        return DriveSizingResult(
            motorFullLoadCurrentA: flc,
            requiredDriveCurrentA: required,
            totalDeratePercent: derate
        )
    }

    static func sizeBraking(_ input: BrakingSizingInput) -> BrakingSizingResult {
        let omega = 2 * Double.pi * input.speedRPM / 60   // rad/s
        let energy = 0.5 * input.totalInertiaKgM2 * omega * omega   // Joules

        let peakPowerW = input.decelTimeSeconds > 0 ? energy / input.decelTimeSeconds : 0
        let peakPowerKW = peakPowerW / 1000

        let dutyPercent = input.dutyCycleSeconds > 0
            ? min(100, (input.decelTimeSeconds / input.dutyCycleSeconds) * 100)
            : 0
        let continuousKW = peakPowerKW * (dutyPercent / 100)

        // R = V^2 / P — resistor value that dissipates the peak power at the
        // drive's DC bus chopper threshold voltage.
        let resistorOhms = peakPowerW > 0 ? (input.dcBusTripVoltage * input.dcBusTripVoltage) / peakPowerW : 0

        return BrakingSizingResult(
            kineticEnergyJoules: energy,
            peakBrakingPowerKW: peakPowerKW,
            continuousPowerRatingKW: continuousKW,
            recommendedResistorOhms: resistorOhms,
            dutyCyclePercent: dutyPercent
        )
    }
}
