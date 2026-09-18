//
//  FaultCode.swift
//  Unified Drive Assistant
//
//  ============================================================
//  DATA BLOCK — MODELS
//  ------------------------------------------------------------
//  Plain data model for a fault/alarm entry. Same shape is used
//  for Siemens, Schneider and ABB so the lookup and detail views
//  never need to know which vendor they're rendering.
//  ============================================================

import Foundation

enum Vendor: String, CaseIterable, Identifiable, Codable {
    case siemens   = "Siemens"
    case schneider = "Schneider"
    case abb       = "ABB"
    case danfoss   = "Danfoss"

    var id: String { rawValue }

    /// JSON resource file name (without extension) for this vendor.
    var resourceFileName: String {
        switch self {
        case .siemens:   return "siemens_s120_faults"
        case .schneider: return "schneider_faults"
        case .abb:       return "abb_faults"
        case .danfoss:   return "danfoss_faults"
        }
    }
}

enum FaultSeverity: String, Codable {
    case fault = "Fault"
    case alarm = "Alarm"
    case faultOrAlarm = "Fault/Alarm"
    case unknown = "Unknown"
}

struct FaultCode: Identifiable, Codable, Hashable {
    let id: String
    let code: String
    let type: String        // raw string from source data, mapped via `severity`
    let title: String
    let addInfo: String
    let cause: String
    let remedy: String
    let brand: String
    let families: [String]  // one or more drive families this code applies to —
                             // more than one means the code is common across those families

    var severity: FaultSeverity {
        FaultSeverity(rawValue: type) ?? .unknown
    }

    /// "S120" for a single family, "ATV930, ATV320, ATV340" when shared.
    var familyLabel: String {
        families.joined(separator: ", ")
    }

    var isCommonAcrossFamilies: Bool {
        families.count > 1
    }

    /// Text used for search matching — code + title + families, for speed.
    var searchKey: String {
        (code + " " + title + " " + familyLabel).lowercased()
    }
}
