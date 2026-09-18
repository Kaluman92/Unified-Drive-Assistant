//
//  VibrationEngine.swift
//  Unified Drive Assistant
//
//  ============================================================
//  SENSORS BLOCK — VIBRATION ANALYSIS ENGINE
//  ------------------------------------------------------------
//  Captures accelerometer data via CoreMotion, converts it to an
//  approximate vibration velocity (mm/s RMS — the metric vibration
//  standards actually classify machines by), and compares it
//  against severity bands loosely modelled on the publicly known
//  general shape of ISO 10816/20816 machine-vibration severity
//  classes.
//
//  FIX NOTE (stationary-phone false positive): earlier versions of
//  this file picked a single "dominant" FFT bin and converted it to
//  velocity via v = a/ω with no minimum-frequency floor and no
//  windowing. With a phone lying still, tiny residual DC bias (the
//  sensor's rest reading is never exactly 1.000g) leaked into the
//  lowest FFT bins — a well-known artifact of unwindowed FFTs — and
//  dividing by that near-zero frequency's tiny ω inflated the
//  result into a bogus "Unsatisfactory" reading. Fixed by: (1) a
//  Hann window to suppress that leakage, (2) ignoring all content
//  below a minimum frequency floor (default 8 Hz — real motor/
//  bearing vibration is well above that; near-0 Hz content is
//  gravity/tilt drift, not vibration), and (3) integrating velocity
//  across the whole valid spectrum (broadband RMS) rather than
//  trusting one bin, plus (4) an explicit noise-floor gate that
//  reports "no significant vibration" instead of a spurious number
//  when the signal is essentially just sensor noise.
//
//  READ THIS BEFORE TRUSTING A VERDICT:
//  - A phone's accelerometer is NOT a calibrated vibration
//    instrument. No mounting calibration, no fixed transducer
//    coupling, consumer-grade MEMS sensor. Treat every result as
//    INDICATIVE — a "this might be worth a closer look with a
//    real vibration meter," not a certified measurement.
//  - The severity bands below are generic placeholders reflecting
//    the general shape of published guidance, not a reproduction
//    of the actual ISO 10816/20816 document (which is copyrighted
//    and not something I can source/reproduce here). If you have
//    the real standard or a manufacturer's exact machine-class
//    thresholds, replace the values in `thresholdsMmPerSecRMS`.
//  - Machine class (I–IV) affects which thresholds apply. This
//    file defaults to Class II (typical medium industrial motors,
//    15–75 kW) unless nameplate data suggests otherwise — see
//    `MachineClass.from(ratedPowerKW:)`.
//  ============================================================

import Foundation
import CoreMotion
import Accelerate

enum VibrationSeverity: String, CaseIterable {
    case good = "Good"           // Zone A-ish — newly commissioned / like-new
    case acceptable = "Acceptable" // Zone B-ish — fine for long-term operation
    case unsatisfactory = "Unsatisfactory" // Zone C-ish — restricted operation, plan maintenance
    case unacceptable = "Unacceptable"     // Zone D-ish — vibration likely to cause damage

    /// One-line meaning, for the in-app legend.
    var briefMeaning: String {
        switch self {
        case .good: return "Like new"
        case .acceptable: return "OK long-term"
        case .unsatisfactory: return "Plan maintenance"
        case .unacceptable: return "Investigate now"
        }
    }

    var colorHex: String {
        switch self {
        case .good: return "2ECC71"
        case .acceptable: return "2FD9C6"
        case .unsatisfactory: return "F5A623"
        case .unacceptable: return "FF5B5B"
        }
    }
}

enum MachineClass: String, CaseIterable {
    case classI = "Class I (small, <15 kW)"
    case classII = "Class II (medium, 15–75 kW)"
    case classIII = "Class III (large, rigid mount)"
    case classIV = "Class IV (large, soft mount)"

    static func from(ratedPowerKW: Double) -> MachineClass {
        switch ratedPowerKW {
        case ..<15: return .classI
        case 15..<75: return .classII
        case 75..<300: return .classIII
        default: return .classIV
        }
    }

    /// Generic placeholder mm/s RMS thresholds (upper bound of each zone),
    /// loosely following the general shape of publicly known ISO
    /// 10816-style guidance. NOT the exact standard — see file header.
    var thresholdsMmPerSecRMS: (good: Double, acceptable: Double, unsatisfactory: Double) {
        switch self {
        case .classI:   return (0.71, 1.8, 4.5)
        case .classII:  return (1.12, 2.8, 7.1)
        case .classIII: return (1.8, 4.5, 11.2)
        case .classIV:  return (2.8, 7.1, 18.0)
        }
    }

    func severity(forMmPerSecRMS v: Double) -> VibrationSeverity {
        let t = thresholdsMmPerSecRMS
        if v <= t.good { return .good }
        if v <= t.acceptable { return .acceptable }
        if v <= t.unsatisfactory { return .unsatisfactory }
        return .unacceptable
    }

    /// Display-ready mm/s RMS range for a given tier, for the in-app legend.
    func rangeLabel(for severity: VibrationSeverity) -> String {
        let t = thresholdsMmPerSecRMS
        switch severity {
        case .good:           return "0–\(String(format: "%.2f", t.good))"
        case .acceptable:     return "\(String(format: "%.2f", t.good))–\(String(format: "%.2f", t.acceptable))"
        case .unsatisfactory: return "\(String(format: "%.2f", t.acceptable))–\(String(format: "%.2f", t.unsatisfactory))"
        case .unacceptable:   return "above \(String(format: "%.2f", t.unsatisfactory))"
        }
    }
}

struct VibrationSignature {
    let dominantFrequencyHz: Double
    let peakAccelerationG: Double
    let velocityMmPerSecRMS: Double
    let spectrum: [(frequencyHz: Double, magnitude: Double)]
    let machineClass: MachineClass
    let severity: VibrationSeverity
    /// True when the reading was below the noise floor — i.e. essentially a
    /// still/stationary device. Shown in the UI instead of a misleadingly
    /// precise number.
    let isBelowNoiseFloor: Bool
}

/// Captures accelerometer data and produces a VibrationSignature.
@MainActor
final class VibrationCapture: ObservableObject {
    private let motionManager = CMMotionManager()
    private var samples: [Double] = []
    private let sampleRateHz: Double = 100

    /// 10 seconds gives ~1000 samples — enough for a 0.1 Hz-resolution
    /// spectrum and a much more stable reading than the earlier 4-second
    /// window, which was short enough that a single noisy sample could
    /// swing the result.
    private let captureDurationSeconds: Double = 10

    /// Content below this frequency is excluded from both the dominant-
    /// frequency pick and the velocity integration. Originally 2 Hz (just
    /// enough to clear gravity/tilt drift), raised to 8 Hz after real-device
    /// testing showed low-frequency content (table resonance, floor
    /// vibration from foot traffic, HVAC) swinging the result — velocity =
    /// acceleration / ω, so a tiny acceleration at a low frequency converts
    /// to a disproportionately larger velocity than the same acceleration
    /// at a higher frequency. 8 Hz is a reasonable floor because real AC
    /// motor content essentially never runs below that — even an 8-pole
    /// motor on 50 Hz mains has a running-speed fundamental around 12.5 Hz.
    private let minValidFrequencyHz: Double = 8.0

    /// Below this broadband velocity, report "no significant vibration"
    /// rather than a specific (likely noise-driven) number. This is a
    /// generic placeholder, not a calibrated instrument's noise spec —
    /// tune it if you find it too sensitive/insensitive on your device.
    private let noiseFloorMmPerSecRMS: Double = 0.15

    @Published var isCapturing = false
    @Published var progress: Double = 0
    @Published var lastResult: VibrationSignature?
    @Published var errorMessage: String?

    func startCapture(machineClass: MachineClass, completion: @escaping (VibrationSignature?) -> Void) {
        guard motionManager.isAccelerometerAvailable else {
            errorMessage = "This device doesn't report accelerometer data."
            completion(nil)
            return
        }
        samples.removeAll()
        isCapturing = true
        progress = 0
        errorMessage = nil

        motionManager.accelerometerUpdateInterval = 1.0 / sampleRateHz
        let startTime = Date()

        motionManager.startAccelerometerUpdates(to: .main) { [weak self] data, error in
            guard let self, let data else { return }
            // Use the magnitude of the 3-axis vector minus gravity's ~1g baseline,
            // so we're capturing vibration, not device orientation.
            let magnitude = sqrt(data.acceleration.x * data.acceleration.x
                                + data.acceleration.y * data.acceleration.y
                                + data.acceleration.z * data.acceleration.z) - 1.0
            self.samples.append(magnitude)

            let elapsed = Date().timeIntervalSince(startTime)
            self.progress = min(1.0, elapsed / self.captureDurationSeconds)

            if elapsed >= self.captureDurationSeconds {
                self.motionManager.stopAccelerometerUpdates()
                self.isCapturing = false
                let result = self.analyze(machineClass: machineClass)
                self.lastResult = result
                completion(result)
            }
        }
    }

    func cancel() {
        motionManager.stopAccelerometerUpdates()
        isCapturing = false
    }

    /// FFT the captured samples (Accelerate framework), then compute a
    /// broadband RMS velocity across all bins above `minValidFrequencyHz`
    /// (not just the single loudest bin) — see file header for why.
    private func analyze(machineClass: MachineClass) -> VibrationSignature {
        let n = samples.count
        guard n > 16 else {
            return VibrationSignature(dominantFrequencyHz: 0, peakAccelerationG: 0, velocityMmPerSecRMS: 0,
                                       spectrum: [], machineClass: machineClass, severity: .good,
                                       isBelowNoiseFloor: true)
        }

        // Remove this window's own residual mean (on top of the 1g baseline
        // already subtracted at capture time) — nulls the small calibration/
        // tilt bias that would otherwise leak into low-frequency bins.
        let windowMean = samples.reduce(0, +) / Double(n)
        let centered = samples.map { $0 - windowMean }

        let peakAccelG = centered.map { abs($0) }.max() ?? 0

        // Pad to next power of two for the FFT.
        let log2n = vDSP_Length(log2(Double(n)).rounded(.up))
        let paddedCount = 1 << Int(log2n)
        var padded = centered + Array(repeating: 0, count: max(0, paddedCount - n))

        // Hann window suppresses spectral leakage from the signal's edges —
        // without it, a stationary phone's tiny residual signal smears into
        // many bins and can look like a "peak" at some arbitrary frequency.
        var window = [Double](repeating: 0, count: paddedCount)
        vDSP_hann_windowD(&window, vDSP_Length(paddedCount), Int32(vDSP_HANN_NORM))
        vDSP_vmulD(padded, 1, window, 1, &padded, 1, vDSP_Length(paddedCount))
        // Hann reduces average amplitude to ~0.5 of the original — correct
        // for that so the resulting acceleration/velocity figures are in
        // roughly the right ballpark, not systematically halved.
        let windowGainCorrection = 2.0

        var realp = [Double](repeating: 0, count: paddedCount / 2)
        var imagp = [Double](repeating: 0, count: paddedCount / 2)

        var spectrum: [(Double, Double)] = []
        var dominantFreq: Double = 0
        var velocityRMSSquaredSum: Double = 0   // accumulate in quadrature across valid bins

        realp.withUnsafeMutableBufferPointer { realPtr in
            imagp.withUnsafeMutableBufferPointer { imagPtr in
                var splitComplex = DSPDoubleSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)

                guard let fftSetup = vDSP_create_fftsetupD(log2n, FFTRadix(kFFTRadix2)) else { return }
                defer { vDSP_destroy_fftsetupD(fftSetup) }

                padded.withUnsafeMutableBufferPointer { paddedPtr in
                    paddedPtr.baseAddress!.withMemoryRebound(to: DSPDoubleComplex.self, capacity: paddedCount / 2) { complexPtr in
                        vDSP_ctozD(complexPtr, 2, &splitComplex, 1, vDSP_Length(paddedCount / 2))
                    }
                }

                vDSP_fft_zripD(fftSetup, &splitComplex, 1, log2n, FFTDirection(FFT_FORWARD))

                var magnitudes = [Double](repeating: 0, count: paddedCount / 2)   // these are squared-magnitude (power)
                vDSP_zvmagsD(&splitComplex, 1, &magnitudes, 1, vDSP_Length(paddedCount / 2))

                let binHz = sampleRateHz / Double(paddedCount)
                var maxMag = 0.0
                var maxIdx = 0

                for i in 1..<magnitudes.count {   // skip bin 0 (DC)
                    let freq = Double(i) * binHz
                    spectrum.append((freq, magnitudes[i]))

                    guard freq >= minValidFrequencyHz else { continue }   // ignore gravity/tilt drift band

                    if magnitudes[i] > maxMag {
                        maxMag = magnitudes[i]
                        maxIdx = i
                    }

                    // Convert this bin's acceleration amplitude to a velocity
                    // contribution (v = a/ω for a sinusoidal component,
                    // standard SDOF vibration relationship) and accumulate
                    // in quadrature for a broadband RMS estimate, instead of
                    // trusting a single "loudest" bin.
                    let amplitudeG = 2 * sqrt(magnitudes[i]) / Double(paddedCount) * windowGainCorrection
                    let accelPeakMS2 = amplitudeG * 9.81
                    let omega = 2 * Double.pi * freq
                    let velocityPeakMS = accelPeakMS2 / omega
                    let velocityRMSBinMm = (velocityPeakMS / sqrt(2)) * 1000
                    velocityRMSSquaredSum += velocityRMSBinMm * velocityRMSBinMm
                }
                dominantFreq = maxIdx > 0 ? Double(maxIdx) * binHz : 0
            }
        }

        let velocityRMS = sqrt(velocityRMSSquaredSum)
        let belowNoiseFloor = velocityRMS < noiseFloorMmPerSecRMS
        let reportedVelocity = belowNoiseFloor ? 0 : velocityRMS
        let severity = machineClass.severity(forMmPerSecRMS: reportedVelocity)

        return VibrationSignature(
            dominantFrequencyHz: belowNoiseFloor ? 0 : dominantFreq,
            peakAccelerationG: peakAccelG,
            velocityMmPerSecRMS: reportedVelocity,
            spectrum: spectrum,
            machineClass: machineClass,
            severity: severity,
            isBelowNoiseFloor: belowNoiseFloor
        )
    }
}
