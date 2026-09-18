//
//  LinearSpeedTracker.swift
//  Unified Drive Assistant
//
//  ============================================================
//  SENSORS BLOCK — LINEAR SPEED (general moving object)
//  ------------------------------------------------------------
//  Tracks a point across video frames (Vision object tracking)
//  and converts pixel displacement to real-world speed — but only
//  once the user has calibrated pixels-per-metre by marking two
//  points a KNOWN real distance apart (e.g. two marks on a
//  conveyor frame, a belt width you've measured). Without that
//  calibration there is no way to honestly convert "pixels moved"
//  into "metres moved" from a single camera — so this deliberately
//  refuses to produce a number until it has one.
//
//  This is a genuinely different technique from OpticalTachometer
//  (which measures rotation via blink frequency and needs no
//  distance calibration at all) — use that one for shaft/motor
//  RPM, this one for belts, conveyors, or anything moving in a
//  straight line across the frame.
//  ============================================================

import Foundation
import Vision
import AVFoundation
import CoreGraphics

@MainActor
final class LinearSpeedTracker: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {

    @Published var currentSpeedMPS: Double?
    /// True while Vision object tracking is actively running.
    @Published var isRunning = false
    /// True once the camera session is configured and streaming —
    /// independent of whether tracking is running.
    @Published var isPreviewActive = false
    @Published var errorMessage: String?
    @Published var isCalibrated = false

    let permission = CameraPermission()

    // nonisolated(unsafe): same reasoning as OpticalTachometer.swift — start/
    // stop on AVCaptureSession is documented as safe off the main thread.
    nonisolated(unsafe) let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "uda.speedtracker.queue")
    private let sequenceHandler = VNSequenceRequestHandler()
    private var sessionConfigured = false

    private var trackingRequest: VNTrackObjectRequest?
    private var lastObservation: VNDetectedObjectObservation?
    private var lastTimestamp: CMTime?

    /// Set via calibration: real-world metres represented by 1.0 of
    /// normalized-image width. nil until the user calibrates.
    private var metersPerNormalizedUnit: Double?

    /// Called with two points (normalized [0,1] coords) the user tapped, and
    /// the real-world distance between them in metres, as measured on site.
    func calibrate(pointA: CGPoint, pointB: CGPoint, realWorldDistanceMeters: Double) {
        let dx = pointA.x - pointB.x
        let dy = pointA.y - pointB.y
        let normalizedDistance = sqrt(dx * dx + dy * dy)
        guard normalizedDistance > 0.001 else {
            errorMessage = "Calibration points are too close together."
            return
        }
        metersPerNormalizedUnit = realWorldDistanceMeters / normalizedDistance
        isCalibrated = true
        errorMessage = nil
    }

    // MARK: - Preview lifecycle (call from the view's onAppear/onDisappear)

    /// Configures the camera and starts the live preview. Safe to call
    /// repeatedly — a no-op if already active.
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
        session.beginConfiguration()
        session.sessionPreset = .high
        if let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) {
            session.addInput(input)
        }
        videoOutput.setSampleBufferDelegate(self, queue: queue)
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }
        session.commitConfiguration()
        sessionConfigured = true

        queue.async { [weak self] in self?.session.startRunning() }
        isPreviewActive = true
        errorMessage = nil
    }

    // MARK: - Tracking lifecycle (the Start/Stop button)

    /// Begins Vision object tracking from the given starting box. The camera
    /// must already be previewing (call activatePreview() first).
    func startTracking(initialTrackingBox: CGRect) {
        guard metersPerNormalizedUnit != nil else {
            errorMessage = "Calibrate a known real-world distance first — see the note on this screen."
            return
        }
        guard isPreviewActive else {
            errorMessage = "Camera isn't active yet — check the permission banner above."
            return
        }
        let observation = VNDetectedObjectObservation(boundingBox: initialTrackingBox)
        lastObservation = observation
        trackingRequest = VNTrackObjectRequest(detectedObjectObservation: observation)
        lastTimestamp = nil
        isRunning = true
        errorMessage = nil
    }

    func stopTracking() {
        isRunning = false
        trackingRequest = nil
        lastObservation = nil
    }

    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        Task { @MainActor in
            guard self.isRunning else { return }   // camera may be previewing without tracking
            guard let request = self.trackingRequest, let lastObs = self.lastObservation else { return }
            request.inputObservation = lastObs

            do {
                try self.sequenceHandler.perform([request], on: pixelBuffer)
                guard let result = request.results?.first as? VNDetectedObjectObservation else { return }

                if let lastTimestamp = self.lastTimestamp, let metersPerUnit = self.metersPerNormalizedUnit {
                    let dt = CMTimeGetSeconds(timestamp) - CMTimeGetSeconds(lastTimestamp)
                    if dt > 0 {
                        let dx = result.boundingBox.midX - lastObs.boundingBox.midX
                        let dy = result.boundingBox.midY - lastObs.boundingBox.midY
                        let normalizedDistance = sqrt(dx * dx + dy * dy)
                        let metersMoved = normalizedDistance * metersPerUnit
                        self.currentSpeedMPS = metersMoved / dt
                    }
                }

                self.lastObservation = result
                self.trackingRequest = VNTrackObjectRequest(detectedObjectObservation: result)
                self.lastTimestamp = timestamp
            } catch {
                self.errorMessage = "Lost tracking — re-select the object to keep measuring."
            }
        }
    }
}
