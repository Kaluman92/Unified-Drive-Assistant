//
//  HomeView.swift
//  Unified Drive Assistant
//
//  ============================================================
//  HOME BLOCK
//  ------------------------------------------------------------
//  What the user sees right after logging in — three visual
//  choices (Drive Fault Codes, Special Tools, Settings) instead
//  of landing straight in the Siemens tab. Each card uses one of
//  the three colours from the app's own logo, so the choice of
//  colour per card isn't arbitrary — it ties back to the brand
//  mark shown on the login screen.
//  ============================================================

import SwiftUI

/// Value-based destinations for the three home cards. Introduced to make
/// the WHOLE navigation stack consistently value-based — see the file
/// header note below on why the previous mix of styles was replaced.
enum HomeDestination: Hashable {
    case faultCodes
    case tools
    case settings
}

struct HomeView: View {
    @State private var showSiteHistory = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: UDATheme.spacingM) {
                    ZStack {
                        headerBackground
                        VStack(spacing: UDATheme.spacingXS) {
                            Image("AppLogo")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 160)
                            Text(UDATheme.appTagline)
                                .font(UDATheme.tagline)
                                .foregroundColor(UDATheme.tealAccent)
                                .tracking(3)
                        }
                        .padding(.vertical, UDATheme.spacingL)
                    }
                    .padding(.bottom, UDATheme.spacingS)

                    // Shows the "N past faults logged here" alert right on
                    // the screen the person actually sees first when
                    // opening the app — the same banner used to only live
                    // inside the Drive Fault Codes screen, which meant it
                    // never appeared until you'd already navigated there.
                    NearbyVisitsBanner(onOpenHistory: { showSiteHistory = true })

                    // Changed from anonymous NavigationLink { ContentView() }
                    // to value-based NavigationLink(value:) — see file
                    // header. All three home cards and the fault-detail
                    // push now go through the same value-based mechanism.
                    NavigationLink(value: HomeDestination.faultCodes) {
                        HomeCardView(
                            title: "Drive Fault Codes",
                            subtitle: "Siemens, Schneider, ABB, Danfoss",
                            icon: "bolt.trianglebadge.exclamationmark",
                            accentColor: UDATheme.logoGreen
                        )
                    }

                    NavigationLink(value: HomeDestination.tools) {
                        HomeCardView(
                            title: "Special Tools",
                            subtitle: "VSD sizing, vibration, speed measurement",
                            icon: "wrench.and.screwdriver.fill",
                            accentColor: UDATheme.logoOrange
                        )
                    }

                    NavigationLink(value: HomeDestination.settings) {
                        HomeCardView(
                            title: "Settings",
                            subtitle: "Assistant, appearance, feedback, account",
                            icon: "gearshape.fill",
                            accentColor: UDATheme.logoMagenta
                        )
                    }

                    Spacer(minLength: UDATheme.spacingL)

                    // Legal disclaimer: fault code data is sourced from
                    // publicly available manufacturer documentation, and
                    // vendor names are used for identification only — no
                    // affiliation with Siemens, Schneider Electric, ABB,
                    // or Danfoss is implied. Kept small and low-contrast
                    // so it doesn't compete with the cards above, but
                    // still legible without zooming.
                    disclaimerText
                        .padding(.horizontal, UDATheme.spacingM)
                        .padding(.bottom, UDATheme.spacingS)
                }
                .padding(UDATheme.spacingM)
            }
            .background(UDATheme.background)
            .navigationBarHidden(true)
            // FIX ATTEMPT: previously, this stack mixed anonymous
            // NavigationLink { DestinationView() } pushes (for the three
            // home cards) with value-based NavigationLink(value:) pushes
            // (for fault rows, several levels deeper). That specific mix
            // has documented quirks on some iOS versions that can produce
            // exactly the "wrong screen shown, back reveals the correct
            // one" bug reported here — even with only one
            // navigationDestination(for:) declared correctly at the root
            // (which was verified and is not the cause). Converting
            // EVERYTHING in this stack to value-based navigation removes
            // that style mix entirely, which is the next real experiment
            // rather than another guess at "which file has a duplicate."
            .navigationDestination(for: FaultCode.self) { fault in
                FaultDetailView(fault: fault)
            }
            .navigationDestination(for: HomeDestination.self) { destination in
                switch destination {
                case .faultCodes:
                    ContentView()
                case .tools:
                    ToolsMenuView()
                case .settings:
                    SettingsView()
                }
            }
            .sheet(isPresented: $showSiteHistory) {
                NavigationStack { SiteHistoryView() }
            }
        }
    }

    /// Soft, blurred blobs of the logo's three colours behind the header —
    /// an abstract approximation of the wavy artwork on the reference
    /// mock, built from plain SwiftUI shapes rather than a static image so
    /// it scales cleanly to any screen size.
    private var headerBackground: some View {
        ZStack {
            Circle()
                .fill(UDATheme.logoGreen.opacity(0.25))
                .frame(width: 180, height: 180)
                .blur(radius: 60)
                .offset(x: -90, y: -30)
            Circle()
                .fill(UDATheme.logoMagenta.opacity(0.22))
                .frame(width: 160, height: 160)
                .blur(radius: 60)
                .offset(x: 100, y: 10)
            Circle()
                .fill(UDATheme.logoOrange.opacity(0.18))
                .frame(width: 140, height: 140)
                .blur(radius: 55)
                .offset(x: 10, y: 50)
        }
        .frame(maxWidth: .infinity)
        .clipped()
    }

    private var disclaimerText: some View {
        Text("Fault code data is compiled from publicly available manufacturer documentation and technical manuals. Siemens, Schneider Electric, ABB, and Danfoss are trademarks of their respective owners. Unified Drive Assistant is an independent tool developed by Silcore Engineering and is not affiliated with, sponsored by, or endorsed by these companies.")
            .font(.system(size: 10, weight: .regular))
            .foregroundColor(UDATheme.textSecondary.opacity(0.7))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A large, visual card — icon in a coloured circle, title, subtitle, chevron.
/// Deliberately NOT a plain list row: this is the "visual representation"
/// entry point the person asked for.
private struct HomeCardView: View {
    let title: String
    let subtitle: String
    let icon: String
    let accentColor: Color

    var body: some View {
        HStack(spacing: UDATheme.spacingM) {
            ZStack {
                Circle()
                    .fill(accentColor.opacity(0.18))
                    .frame(width: 64, height: 64)
                Image(systemName: icon)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundColor(accentColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(UDATheme.headline)
                    .foregroundColor(UDATheme.textPrimary)
                Text(subtitle)
                    .font(UDATheme.caption)
                    .foregroundColor(UDATheme.textSecondary)
                    .lineLimit(2)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundColor(UDATheme.textSecondary)
        }
        .padding(UDATheme.spacingM)
        .background(UDATheme.surface)
        .overlay(
            RoundedRectangle(cornerRadius: UDATheme.chamferLarge, style: .circular)
                .stroke(accentColor.opacity(0.35), lineWidth: UDATheme.hairline)
        )
        .cornerRadius(UDATheme.chamferLarge)
    }
}

#Preview {
    HomeView()
}
