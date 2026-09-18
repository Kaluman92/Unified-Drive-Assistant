//
//  FaultDataStore.swift
//  Unified Drive Assistant
//
//  ============================================================
//  DATA BLOCK — LOADING & SEARCH
//  ------------------------------------------------------------
//  Loads the bundled per-vendor JSON files once at launch and
//  serves fast in-memory search. Swap this loader out for a
//  Firestore/remote-config backed one later without touching
//  any view code — everything reads through `FaultDataStore.shared`.
//  ============================================================

import Foundation
import Combine

@MainActor
final class FaultDataStore: ObservableObject {

    static let shared = FaultDataStore()

    @Published private(set) var faultsByVendor: [Vendor: [FaultCode]] = [:]
    @Published private(set) var loadError: String?

    private init() {
        loadAll()
    }

    private func loadAll() {
        for vendor in Vendor.allCases {
            do {
                faultsByVendor[vendor] = try loadVendor(vendor)
            } catch {
                loadError = "Failed to load \(vendor.rawValue) fault list: \(error.localizedDescription)"
                faultsByVendor[vendor] = []
            }
        }
    }

    private func loadVendor(_ vendor: Vendor) throws -> [FaultCode] {
        guard let url = Bundle.main.url(forResource: vendor.resourceFileName, withExtension: "json") else {
            throw NSError(domain: "FaultDataStore", code: 404,
                           userInfo: [NSLocalizedDescriptionKey: "\(vendor.resourceFileName).json not found in bundle. Make sure it's added to Target Membership."])
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([FaultCode].self, from: data)
    }

    func faults(for vendor: Vendor) -> [FaultCode] {
        faultsByVendor[vendor] ?? []
    }

    /// Case-insensitive search across code and title for the given vendor.
    /// Empty query returns the full list.
    func search(_ query: String, in vendor: Vendor) -> [FaultCode] {
        let all = faults(for: vendor)
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return all }
        return all.filter { $0.searchKey.contains(trimmed) }
    }

    func fault(withID id: String, vendor: Vendor) -> FaultCode? {
        faults(for: vendor).first { $0.id == id }
    }
}
