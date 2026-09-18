//
//  OpticalTachometer.swift
//  Unified Drive Assistant
//
//  ============================================================
//  SENSORS BLOCK — OPTICAL TACHOMETER (rotational speed)
//  ------------------------------------------------------------
//  Measures RPM of a rotating shaft/coupling using the camera:
//  point it at a shaft with ONE piece of reflective tape or a
//  contrast mark, sample brightness in a region of interest every
//  frame, FFT the brightness-over-time signal, and the dominant
//  blink frequency × 60 = RPM. This is the same principle real
//  handheld optical tachometers use — it's a genuine measurement
//  technique, not a simulated number.
//
//  PREVIEW vs MEASURING (two separate lifecycles):
//  Camera activation (`activatePreview`/`deactivatePreview`) is
//  now separate from measurement (`startMeasuring`/`stopMeasuring`).
//  Earlier, the session only started when "Start measuring" was
//  tapped, so the preview box was blank the whole time you were
//  trying to aim the camera — there was no way to actually see
//  what you were pointing at. Now the live feed activates as soon
//  as the screen appears (once permission is granted), and the
//  Start/Stop button only toggles whether frames are being
//  sampled/analyzed — the camera itself stays live throughout.
//
//  ACCURACY NOTES:
//  - Needs good, even lighting and a clearly visible mark.
//  - Max reliably detectable RPM is limited by camera frame rate
//    (Nyquist: max RPM ≈ fps × 30). This tries to lock the highest
//    frame-rate format the device supports for better headroom.
//  - This measures ROTATIONAL speed only. For general linear speed
//    of a moving object, see LinearSpeedTracker.swift instead —
//    different technique, different accuracy trade-offs.
//  ============================================================

import Foundation
import AVFoundation
import Accelerate
import CoreGraphics

@MainActor
final class OpticalTachometer: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {

    @Published var currentRPM: Double?
    /// True when a measurement completed but found no genuine periodic
    /// blink — i.e. the target isn't actually rotating (or no reflective
    /// mark is in view). The UI should show a "stationary" message instead
    /// of a bogus RPM number when this is true.
    @Published var isStationary = false
    /// True while frames are actively being sampled/analyzed for RPM.
    @Published var isRunning = false
    /// True once the camera session is configured and actually streaming —
    /// independent of whether measurement is running. The preview should be
    /// visible whenever this is true.
    @Published var isPreviewActive = false
    @Published var errorMessage: String?
    @Published var frameRateInUse: Double = 30

    let permission = CameraPermission()

    // nonisolated(unsafe): AVCaptureSession.startRunning()/stopRunning() are
    // documented by Apple as safe (in fact preferred) to call off the main
    // thread, and this session is never mutated concurrently in a way that
    // would race. Marking it nonisolated(unsafe) lets the background-queue
    // closures below touch it without a Swift 6 actor-isolation error.
    nonisolated(unsafe) let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "uda.tachometer.queue")
    private var sessionConfigured = false

    private var brightnessSamples: [Double] = []
    private let windowSeconds: Double = 3.0

    /// Gate 1 threshold: raw brightness signal must vary by at least this
    /// many luma units (0–255 scale) of standard deviation to be considered
    /// real signal rather than camera sensor noise (typically well under 1).
    private let minBrightnessStdDev: Double = 1.0

    /// Gate 2 threshold: the dominant FFT bin must be at least this many
    /// times the median of the rest of the spectrum to count as a genuine
    /// periodic peak rather than the largest of many similar noise bins.
    private let minPeakProminenceRatio: Double = 6.0
    private var samplesToKeep: Int { Int(frameRateInUse * windowSeconds) }

    /// Region of interest in normalized [0,1] coordinates, set by the user
    /// dragging a box over the reflective mark in the preview.
    /// nonisolated(unsafe): read directly inside the nonisolated
    /// `captureOutput` delegate callback below, which runs on `queue`, not
    /// the main actor. It's written from the UI on the main actor. A CGRect
    /// is four plain Doubles, so the worst case from an unsynchronized
    /// read/write race is one frame sampling a slightly-stale ROI — not a
    /// correctness or safety issue for this feature.
    nonisolated(unsafe) var regionOfInterest: CGRect = CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2)

    // MARK: - Preview lifecycle (call from the view's onAppear/onDisappear)

    /// Configures the camera and starts the live preview. Safe to call
    /// repeatedly — a no-op if already active. Never touches
    /// AVCaptureSession until permission is confirmed authorized.
    func activatePreview() {
        errorMessage = nil
        permission.ensureAuthorized { [weak self] in
            self?.configureAndStartSession()
        }
        if permission.status == .deniedOrRestricted {
            errorMessage = "Camera access is off — see the settings link above."
        }
    }

    /// Stops the camera entirely. Call when leaving the screen.
    func deactivatePreview() {
        isRunning = false
        queue.async { [weak self] in self?.session.stopRunning() }
        isPreviewActive = false
    }

    private func configureAndStartSession() {
        guard !sessionConfigured else {
            queue.async { [weak self] in self?.session.startRunning() }
            isPreviewActive = true
            return
        }
        guard let device = AVCaptureDevice.default(for: .video) else {
            errorMessage = "No camera available."
            return
        }
        do {
            session.beginConfiguration()
            session.sessionPreset = .high

            if let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) {
                session.addInput(input)
            }

            // Try to lock the highest supported frame rate for better RPM headroom.
            if let bestFormat = device.formats.max(by: { a, b in
                (a.videoSupportedFrameRateRanges.first?.maxFrameRate ?? 0) <
                (b.videoSupportedFrameRateRanges.first?.maxFrameRate ?? 0)
            }), let bestRange = bestFormat.videoSupportedFrameRateRanges.first {
                try device.lockForConfiguration()
                device.activeFormat = bestFormat
                device.activeVideoMinFrameDuration = bestRange.minFrameDuration
                device.activeVideoMaxFrameDuration = bestRange.minFrameDuration
                frameRateInUse = bestRange.maxFrameRate
                device.unlockForConfiguration()
            }

            videoOutput.setSampleBufferDelegate(self, queue: queue)
            videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }

            session.commitConfiguration()
            sessionConfigured = true

            queue.async { [weak self] in self?.session.startRunning() }
            isPreviewActive = true
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't configure the camera: \(error.localizedDescription)"
        }
    }

    // MARK: - Measurement lifecycle (the Start/Stop button)

    /// Begins sampling frames for RPM analysis. The camera must already be
    /// previewing (call activatePreview() first, normally from onAppear).
    func startMeasuring() {
        guard isPreviewActive else {
            errorMessage = "Camera isn't active yet — check the permission banner above."
            return
        }
        brightnessSamples.removeAll()
        currentRPM = nil
        isStationary = false
        isRunning = true
    }

    func stopMeasuring() {
        isRunning = false
    }

    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let brightness = Self.averageBrightness(pixelBuffer: pixelBuffer, roi: regionOfInterest)

        Task { @MainActor in
            guard self.isRunning else { return }   // camera may be previewing without measuring
            self.brightnessSamples.append(brightness)
            if self.brightnessSamples.count > self.samplesToKeep {
                self.brightnessSamples.removeFirst(self.brightnessSamples.count - self.samplesToKeep)
            }
            if self.brightnessSamples.count >= Int(self.frameRateInUse * 1.5) {
                switch self.estimateRPM() {
                case .rotating(let rpm):
                    self.currentRPM = rpm
                    self.isStationary = false
                case .stationary:
                    self.currentRPM = nil
                    self.isStationary = true
                case .insufficientData:
                    break   // not enough samples yet — leave the current display as-is
                }
            }
        }
    }

    /// Average luma over the region of interest — cheap, no ML, real pixel data.
    nonisolated private static func averageBrightness(pixelBuffer: CVPixelBuffer, roi: CGRect) -> Double {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return 0 }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let buffer = base.assumingMemoryBound(to: UInt8.self)

        let x0 = Int(roi.minX * CGFloat(width)), x1 = Int(roi.maxX * CGFloat(width))
        let y0 = Int(roi.minY * CGFloat(height)), y1 = Int(roi.maxY * CGFloat(height))

        var total: Double = 0
        var count: Double = 0
        var y = max(0, y0)
        while y < min(height, y1) {
            var x = max(0, x0)
            while x < min(width, x1) {
                let offset = y * bytesPerRow + x * 4  // BGRA
                let b = Double(buffer[offset]), g = Double(buffer[offset + 1]), r = Double(buffer[offset + 2])
                total += 0.299 * r + 0.587 * g + 0.114 * b   // standard luma weighting
                count += 1
                x += 2   // subsample for speed — brightness average doesn't need every pixel
            }
            y += 2
        }
        return count > 0 ? total / count : 0
    }

    /// FFT the brightness signal, find the dominant blink frequency, convert to RPM.
    enum RPMEstimate {
        case rotating(rpm: Double)
        case stationary
        case insufficientData
    }

    /// FFT the brightness signal and decide between three outcomes, not
    /// just "here's a frequency" — the earlier version always reported
    /// *some* dominant bin as RPM, even when the target was stationary and
    /// that "peak" was just sensor noise or ambient light flicker. Fixed
    /// with two gates: (1) the raw brightness signal must actually vary by
    /// more than a noise-level amount, and (2) the dominant bin must stand
    /// out clearly above the rest of the spectrum (peak prominence), not
    /// just be whichever noise bin happened to be largest.
    private func estimateRPM() -> RPMEstimate {
        let n = brightnessSamples.count
        guard n >= 16 else { return .insufficientData }

        let mean = brightnessSamples.reduce(0, +) / Double(n)
        var signal = brightnessSamples.map { $0 - mean }   // remove DC offset

        // Gate 1: is there any meaningful brightness variation at all? A
        // stationary target (or no reflective mark actually in view) gives
        // a near-flat brightness signal — just camera sensor noise, well
        // under 1 luma unit of standard deviation. A real mark crossing the
        // ROI swings brightness by tens of luma units.
        let variance = signal.reduce(0) { $0 + $1 * $1 } / Double(n)
        let stdDev = sqrt(variance)
        guard stdDev >= minBrightnessStdDev else { return .stationary }

        let log2n = vDSP_Length(log2(Double(n)).rounded(.down))
        let paddedCount = 1 << Int(log2n)
        signal = Array(signal.suffix(paddedCount))
        guard signal.count == paddedCount, paddedCount >= 8 else { return .insufficientData }

        var realp = [Double](repeating: 0, count: paddedCount / 2)
        var imagp = [Double](repeating: 0, count: paddedCount / 2)
        var dominantFreq: Double = 0
        var isPeakSignificant = false

        realp.withUnsafeMutableBufferPointer { realPtr in
            imagp.withUnsafeMutableBufferPointer { imagPtr in
                var splitComplex = DSPDoubleSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
                guard let fftSetup = vDSP_create_fftsetupD(log2n, FFTRadix(kFFTRadix2)) else { return }
                defer { vDSP_destroy_fftsetupD(fftSetup) }

                signal.withUnsafeMutableBufferPointer { sigPtr in
                    sigPtr.baseAddress!.withMemoryRebound(to: DSPDoubleComplex.self, capacity: paddedCount / 2) { complexPtr in
                        vDSP_ctozD(complexPtr, 2, &splitComplex, 1, vDSP_Length(paddedCount / 2))
                    }
                }
                vDSP_fft_zripD(fftSetup, &splitComplex, 1, log2n, FFTDirection(FFT_FORWARD))

                var magnitudes = [Double](repeating: 0, count: paddedCount / 2)
                vDSP_zvmagsD(&splitComplex, 1, &magnitudes, 1, vDSP_Length(paddedCount / 2))

                let binHz = frameRateInUse / Double(paddedCount)
                var maxMag = 0.0, maxIdx = 1
                for i in 1..<magnitudes.count {   // skip DC bin
                    if magnitudes[i] > maxMag { maxMag = magnitudes[i]; maxIdx = i }
                }
                dominantFreq = Double(maxIdx) * binHz

                // Gate 2: peak prominence. The dominant bin must stand out
                // clearly above the median of the rest of the spectrum —
                // otherwise it's just whichever noise bin happened to be
                // largest, not a genuine periodic blink.
                let otherMags = (1..<magnitudes.count).filter { $0 != maxIdx }.map { magnitudes[$0] }
                let sorted = otherMags.sorted()
                let median = sorted.isEmpty ? 0 : sorted[sorted.count / 2]
                isPeakSignificant = median > 0 && (maxMag / median) >= minPeakProminenceRatio
            }
        }

        guard dominantFreq > 0, isPeakSignificant else { return .stationary }
        return .rotating(rpm: dominantFreq * 60)   // Hz -> RPM (one blink per revolution)
    }
}
