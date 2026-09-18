//
//  NearbyVisitsBanner.swift
//  Unified Drive Assistant
//
//  ============================================================
//  LOCATION BLOCK — "YOU'VE BEEN HERE BEFORE" BANNER
//  ------------------------------------------------------------
//  Shown at the top of the fault-codes screen. Silently checks
//  location on appear (only if permission is already authorized —
//  never prompts from here; the prompt only happens when the user
//  deliberately taps "Save as site visit") and shows a one-line
//  banner if any past visits are within range.
//
//  FIX NOTE: this used to own its own .sheet(isPresented:) for Site
//  History, completely independent of the three sheets already
//  living on ContentView (Settings/Tools/Site History again).
//  Splitting sheet-presentation ownership across a parent and a
//  child deep in the same NavigationStack branch caused a real
//  navigation bug — tapping into a fault would sometimes show the
//  previous vendor's fault list first, only revealing the correct
//  detail after pressing back. This view is now "dumb": it reports
//  the tap via `onOpenHistory` and owns no presentation state of
//  its own. ContentView is the single owner of every sheet on this
//  screen — see its `showSiteHistory` state.
//  ============================================================

import SwiftUI

struct NearbyVisitsBanner: View {
    var onOpenHistory: () -> Void = {}

    @StateObject private var permission = LocationPermission.shared
    @ObservedObject private var store = SiteVisitStore.shared
    @State private var nearby: [SiteVisit] = []

    var body: some View {
        Group {
            if !nearby.isEmpty {
                Button {
                    onOpenHistory()
                } label: {
                    HStack(spacing: UDATheme.spacingS) {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundColor(UDATheme.accentPressed)
                        Text(bannerText)
                            .font(UDATheme.caption)
                            .foregroundColor(UDATheme.textPrimary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11))
                            .foregroundColor(UDATheme.textSecondary)
                    }
                    .padding(UDATheme.spacingS)
                    .background(UDATheme.surfaceElevated)
                    .cornerRadius(UDATheme.chamferSmall)
                }
            }
        }
        .onAppear(perform: checkNearby)
        .onChange(of: store.visits.count) { _, _ in
            // Re-check the moment a new visit is saved anywhere in the app
            // — don't rely solely on onAppear, which may not refire just
            // from navigating back to an already-built screen (e.g. saving
            // a visit from a pushed fault detail screen, then pressing
            // back to the same underlying fault list).
            checkNearby()
        }
    }

    private var bannerText: String {
        let siteName = nearby.first?.siteName ?? "this site"
        return nearby.count == 1
            ? "1 past fault logged at \(siteName)"
            : "\(nearby.count) past faults logged at \(siteName)"
    }

    /// Only checks if permission is already authorized — never prompts.
    /// The person opts into location the first time they save a visit, not
    /// passively by opening the fault list.
    private func checkNearby() {
        guard permission.status == .authorized else { return }
        permission.requestLocationAccess()
        Task {
            // 30 x 200ms = 6s — extended from the original 2s given
            // real-device GPS fixes have taken longer than that in testing.
            for _ in 0..<30 {
                try? await Task.sleep(nanoseconds: 200_000_000)
                if let location = permission.currentLocation {
                    nearby = store.visitsNear(latitude: location.coordinate.latitude,
                                               longitude: location.coordinate.longitude)
                    return
                }
            }
        }
    }
}
