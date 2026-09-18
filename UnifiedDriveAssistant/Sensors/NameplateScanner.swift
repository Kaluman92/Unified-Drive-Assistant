//
//  NameplateScanner.swift
//  Unified Drive Assistant
//
//  ============================================================
//  SENSORS BLOCK — MOTOR NAMEPLATE OCR
//  ------------------------------------------------------------
//  Uses on-device Vision text recognition (no network call, no
//  data leaves the device) to read a photographed motor
//  nameplate and pull out kW/HP rating and RPM using pattern
//  matching. This is real OCR text, not an AI guess — the numbers
//  shown are whatever Vision actually read off the plate. Always
//  let the user confirm/correct them, since OCR on a scratched or
//  glare-lit metal nameplate is genuinely imperfect.
//  ============================================================

import Foundation
import Vision
import UIKit

struct MotorNameplateData {
    var ratedPowerKW: Double?
    var ratedSpeedRPM: Double?
    var rawRecognizedText: [String]
}

enum NameplateScanner {

    static func scan(image: UIImage, completion: @escaping (MotorNameplateData) -> Void) {
        guard let cgImage = image.cgImage else {
            completion(MotorNameplateData(ratedPowerKW: nil, ratedSpeedRPM: nil, rawRecognizedText: []))
            return
        }

        let request = VNRecognizeTextRequest { request, _ in
            guard let observations = request.results as? [VNRecognizedTextObservation] else {
                completion(MotorNameplateData(ratedPowerKW: nil, ratedSpeedRPM: nil, rawRecognizedText: []))
                return
            }
            let lines = observations.compactMap { $0.topCandidates(1).first?.string }
            completion(parse(lines: lines))
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false   // nameplates are codes/units, not prose

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        DispatchQueue.global(qos: .userInitiated).async {
            try? handler.perform([request])
        }
    }

    /// Looks for common nameplate patterns like "22 kW", "30HP", "1450 RPM",
    /// "1450 r/min". Pure pattern matching on the OCR'd text — no inference
    /// beyond what's literally printed on the plate.
    private static func parse(lines: [String]) -> MotorNameplateData {
        var kw: Double?
        var rpm: Double?
        let joined = lines.joined(separator: " ")

        if let match = firstMatch(in: joined, pattern: #"(\d+(?:[.,]\d+)?)\s*kW"#, group: 1) {
            kw = Double(match.replacingOccurrences(of: ",", with: "."))
        } else if let match = firstMatch(in: joined, pattern: #"(\d+(?:[.,]\d+)?)\s*HP"#, group: 1) {
            // 1 HP ≈ 0.7457 kW — standard unit conversion, not a guess.
            if let hp = Double(match.replacingOccurrences(of: ",", with: ".")) {
                kw = hp * 0.7457
            }
        }

        if let match = firstMatch(in: joined, pattern: #"(\d{2,5})\s*(?:RPM|r/min)"#, group: 1) {
            rpm = Double(match)
        }

        return MotorNameplateData(ratedPowerKW: kw, ratedSpeedRPM: rpm, rawRecognizedText: lines)
    }

    private static func firstMatch(in text: String, pattern: String, group: Int) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              let matchRange = Range(match.range(at: group), in: text) else { return nil }
        return String(text[matchRange])
    }
}
