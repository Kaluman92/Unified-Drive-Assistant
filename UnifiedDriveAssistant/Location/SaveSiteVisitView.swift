//
//  SaveSiteVisitView.swift
//  Unified Drive Assistant
//
//  ============================================================
//  LOCATION BLOCK — SAVE SITE VISIT UI
//  ------------------------------------------------------------
//  Presented from FaultDetailView when the user taps "Save as
//  site visit". Reverse-geocodes the current location as a
//  starting guess for the site name (CLGeocoder — standard,
//  on-device-first API), but the name is always user-editable
//  since indoor/underground GPS often reverse-geocodes to a
//  nearby street rather than the actual plant name.
//
//  PERMISSION PHILOSOPHY: iPhone Settings (Never/Ask/While Using/
//  Always) is the single source of truth — this screen doesn't
//  duplicate that as an in-app toggle or status panel. It just
//  calls `requestLocationAccess()` once on appear (required so the app
//  even shows up as an option in iPhone Settings the first time),
//  and afterward respects whatever's actually set there. If access
//  is off, `LocationPermissionBanner` points to iPhone Settings —
//  see Settings/SettingsView.swift for the same pattern.
//  ============================================================

import SwiftUI
import CoreLocation

struct SaveSiteVisitView: View {
    let vendor: String
    let faultCode: String
    let faultTitle: String

    @Environment(\.dismiss) private var dismiss
    @StateObject private var permission = LocationPermission.shared
    @State private var siteName: String = ""
    @State private var note: String = ""
    @State private var isLocating = false
    @State private var showSlowLocationHint = false
    @State private var resolvedLocation: CLLocation?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Fault", value: "\(vendor) · \(faultCode)")
                    LabeledContent("Description", value: faultTitle)
                }
                .listRowBackground(UDATheme.surface)

                Section("Site") {
                    // Only the iOS-standard "access is off, here's the
                    // Settings link" banner — no separate in-app status
                    // display. Whatever's set in iPhone Settings (Never/
                    // While Using/Always) is respected as-is.
                    LocationPermissionBanner(permission: permission)

                    if isLocating {
                        HStack(spacing: UDATheme.spacingS) {
                            ProgressView()
                            Text("Finding your location…")
                                .font(UDATheme.caption)
                                .foregroundColor(UDATheme.textSecondary)
                        }
                        if showSlowLocationHint {
                            Text("Taking longer than usual — this is common indoors/underground, or on first use while GPS gets a fix. You can keep waiting, or stop and save with just a manual site name.")
                                .font(UDATheme.caption)
                                .foregroundColor(UDATheme.textSecondary)
                            Button("Stop waiting") {
                                isLocating = false
                            }
                            .font(UDATheme.caption)
                            .foregroundColor(UDATheme.accentPressed)
                        }
                    }

                    if let clError = permission.lastErrorDescription {
                        Text(clError)
                            .font(UDATheme.caption)
                            .foregroundColor(UDATheme.danger)
                        Button("Retry") {
                            isLocating = true
                            showSlowLocationHint = false
                            permission.retryLocation()
                        }
                        .font(UDATheme.caption)
                        .foregroundColor(UDATheme.accentPressed)
                    }

                    TextField("Site name (e.g. Plant 3 — Crusher Building)", text: $siteName)
                    if resolvedLocation == nil {
                        Text("No GPS fix yet — type a site name to save anyway.")
                            .font(UDATheme.caption)
                            .foregroundColor(UDATheme.textSecondary)
                    }
                }
                .listRowBackground(UDATheme.surface)

                Section("Equipment note") {
                    TextEditor(text: $note)
                        .frame(minHeight: 100)
                    Text("What equipment was this, and what did you find? This is what actually identifies it later — location only narrows down which site.")
                        .font(UDATheme.caption)
                        .foregroundColor(UDATheme.textSecondary)
                }
                .listRowBackground(UDATheme.surface)

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(UDATheme.caption)
                            .foregroundColor(UDATheme.danger)
                    }
                    .listRowBackground(UDATheme.surface)
                }
            }
            .scrollContentBackground(.hidden)
            .background(UDATheme.background)
            .navigationTitle("Save Site Visit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
            .onAppear {
                // One call handles all cases: authorized -> fetches
                // immediately; not yet asked -> shows the standard iOS
                // prompt (required once so "While Using the App" even
                // appears as an option in iPhone Settings); denied ->
                // no-ops, and the banner above already explains why.
                locate()
            }
            .onChange(of: permission.currentLocation) { _, newLocation in
                guard let newLocation else { return }
                // Reacts whenever a location arrives, no matter how long it
                // takes — no hard timeout that permanently gives up. GPS can
                // genuinely take longer than a few seconds on first use.
                resolvedLocation = newLocation
                isLocating = false
                showSlowLocationHint = false
                errorMessage = nil
                reverseGeocode(newLocation)
            }
        }
    }

    /// Can save once there's SOMETHING to identify the site by — either a
    /// GPS fix, or a manually typed name (for when GPS never resolves,
    /// e.g. underground). Never blocks saving purely on location.
    private var canSave: Bool {
        resolvedLocation != nil || !siteName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func locate() {
        isLocating = true
        errorMessage = nil
        permission.requestLocationAccess()
        if permission.status == .deniedOrRestricted {
            isLocating = false
            return
        }
        // Purely informational — after a longer grace period, hint that
        // this is taking a while (common indoors/underground/first-use),
        // without ever stopping the actual listening in onChange above.
        Task {
            try? await Task.sleep(nanoseconds: 8_000_000_000)   // 8s
            if resolvedLocation == nil && isLocating {
                showSlowLocationHint = true
            }
        }
    }

    private func reverseGeocode(_ location: CLLocation) {
        guard siteName.isEmpty else { return }
        CLGeocoder().reverseGeocodeLocation(location) { placemarks, _ in
            guard let placemark = placemarks?.first else { return }
            let guess = [placemark.name, placemark.locality].compactMap { $0 }.joined(separator: ", ")
            if !guess.isEmpty {
                DispatchQueue.main.async {
                    if siteName.isEmpty { siteName = guess }
                }
            }
        }
    }

    private func save() {
        let visit = SiteVisit(
            latitude: resolvedLocation?.coordinate.latitude,
            longitude: resolvedLocation?.coordinate.longitude,
            siteName: siteName.isEmpty ? "Unnamed site" : siteName,
            vendor: vendor,
            faultCode: faultCode,
            faultTitle: faultTitle,
            note: note
        )
        SiteVisitStore.shared.save(visit)
        dismiss()
    }
}

#Preview {
    SaveSiteVisitView(vendor: "Siemens", faultCode: "F30027", faultTitle: "Overcurrent")
}
