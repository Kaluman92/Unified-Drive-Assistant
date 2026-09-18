//
//  ContentView.swift
//  Unified Drive Assistant
//
//  ============================================================
//  APP BLOCK — ROOT VIEW
//  ------------------------------------------------------------
//  Ties the Fault Lookup block (brand tabs + list) together with
//  Settings, inside a NavigationStack for the detail push.
//  ============================================================

import SwiftUI

struct ContentView: View {
    @State private var selectedVendor: Vendor = .siemens
    @State private var showSettings = false
    @State private var showTools = false
    @State private var showSiteHistory = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            // Restored — proven NOT to be the cause of the navigation bug
            // via direct testing (removing it entirely didn't fix it).
            NearbyVisitsBanner(onOpenHistory: { showSiteHistory = true })
                .padding(.horizontal, UDATheme.spacingM)
                .padding(.top, UDATheme.spacingS)

            BrandTabView(selectedVendor: $selectedVendor)

            FaultListView(vendor: selectedVendor)
                .id(selectedVendor)   // forces a fresh view so the transition below actually plays
                .transition(.opacity.combined(with: .move(edge: .trailing)))
        }
        .animation(.easeInOut(duration: 0.22), value: selectedVendor)
        .navigationTitle("\(selectedVendor.rawValue) Faults")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(UDATheme.navBar, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(colorScheme, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    showTools = true
                } label: {
                    Image(systemName: "wrench.and.screwdriver")
                        .foregroundColor(UDATheme.textOnDark)
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showSiteHistory = true
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundColor(UDATheme.textOnDark)
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .foregroundColor(UDATheme.textOnDark)
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack { SettingsView() }
        }
        .sheet(isPresented: $showTools) {
            NavigationStack { ToolsMenuView() }
        }
        .sheet(isPresented: $showSiteHistory) {
            NavigationStack { SiteHistoryView() }
        }
    }
}

#Preview {
    NavigationStack { ContentView() }
}
