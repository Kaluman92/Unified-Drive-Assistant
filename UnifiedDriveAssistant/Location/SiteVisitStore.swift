//
//  SiteVisitStore.swift
//  Unified Drive Assistant
//
//  ============================================================
//  LOCATION BLOCK — SITE VISIT DATA + PERSISTENCE
//  ------------------------------------------------------------
//  A "site visit" is created explicitly by the user tapping
//  "Save as site visit" on a looked-up fault — never automatically
//  in the background. Ties a fault lookup to a location, an
//  editable site name, and the user's own equipment note.
//
//  PERSISTENCE: unlike AnalyticsService (which is a deliberately
//  throwaway in-memory stub — see its file header), this data has
//  real lasting value to the person using it, so it's saved to a
//  JSON file in the app's Documents directory and survives app
//  restarts. It's still fully on-device / local-only for now.
//
//  RECONNECTING TO FIRESTORE LATER: swap `load()`/`persist()` for
//  Firestore reads/writes keyed by the signed-in user's uid — the
//  `SiteVisit` struct's Codable conformance already matches a
//  reasonable Firestore document shape (flat fields, ISO8601
//  timestamp), so this should be a fairly mechanical swap, same
//  pattern as AuthManager/AnalyticsService elsewhere in the app.
//
//  ACCURACY NOTE: GPS is unreliable or unavailable indoors/
//  underground, which is most of where this app gets used. This
//  is designed around that constraint rather than pretending it
//  isn't there — location narrows results to "this site" (a
//  ~200 m radius, tunable in `defaultRadiusMeters`), not "this
//  specific drive cabinet." The user's own note/site-name text is
//  what actually identifies the equipment; location just clusters
//  visits that are near each other.
//  ============================================================

import Foundation
import CoreLocation

struct SiteVisit: Identifiable, Codable, Equatable {
    let id: UUID
    /// Optional — GPS can genuinely never resolve in some environments
    /// (underground, deep indoors). A visit without coordinates still
    /// saves fine; it just won't show up in "nearby visits" checks, since
    /// there's nothing to measure distance from.
    let latitude: Double?
    let longitude: Double?
    var siteName: String     // user-editable; pre-filled with a best-effort reverse-geocode guess when a location is available
    let vendor: String
    let faultCode: String
    let faultTitle: String
    var note: String
    let timestamp: Date

    init(id: UUID = UUID(), latitude: Double?, longitude: Double?, siteName: String,
         vendor: String, faultCode: String, faultTitle: String, note: String,
         timestamp: Date = Date()) {
        self.id = id
        self.latitude = latitude
        self.longitude = longitude
        self.siteName = siteName
        self.vendor = vendor
        self.faultCode = faultCode
        self.faultTitle = faultTitle
        self.note = note
        self.timestamp = timestamp
    }
}

@MainActor
final class SiteVisitStore: ObservableObject {
    static let shared = SiteVisitStore()

    @Published private(set) var visits: [SiteVisit] = []

    /// How close (in metres) a past visit needs to be to count as "this
    /// site" when checking for nearby history. Generic default reflecting
    /// realistic GPS precision — see file header.
    let defaultRadiusMeters: Double = 200

    private let fileURL: URL

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = docs.appendingPathComponent("site_visits.json")
        load()
    }

    func save(_ visit: SiteVisit) {
        visits.insert(visit, at: 0)
        persist()
        SiteGeofenceManager.shared.refreshGeofences()
    }

    func update(_ visit: SiteVisit) {
        guard let index = visits.firstIndex(where: { $0.id == visit.id }) else { return }
        visits[index] = visit
        persist()
    }

    func delete(_ visit: SiteVisit) {
        visits.removeAll { $0.id == visit.id }
        persist()
    }

    /// Visits within `defaultRadiusMeters` of the given coordinate,
    /// nearest first. Visits saved without a GPS fix (latitude/longitude
    /// nil) are skipped here — there's nothing to measure distance from —
    /// but they still appear in the full Site History list.
    func visitsNear(latitude: Double, longitude: Double, radiusMeters: Double? = nil) -> [SiteVisit] {
        let radius = radiusMeters ?? defaultRadiusMeters
        let target = CLLocation(latitude: latitude, longitude: longitude)
        return visits
            .compactMap { visit -> (SiteVisit, CLLocationDistance)? in
                guard let lat = visit.latitude, let lon = visit.longitude else { return nil }
                let loc = CLLocation(latitude: lat, longitude: lon)
                return (visit, loc.distance(from: target))
            }
            .filter { $0.1 <= radius }
            .sorted { $0.1 < $1.1 }
            .map { $0.0 }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        visits = (try? decoder.decode([SiteVisit].self, from: data)) ?? []
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(visits) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
