//
//  FaultListView.swift
//  Unified Drive Assistant
//
//  ============================================================
//  FAULT LOOKUP BLOCK — LIST
//  ------------------------------------------------------------
//  Search + scrollable list for the currently selected vendor.
//  Row styling driven entirely by UDATheme.
//  ============================================================

import SwiftUI

struct FaultListView: View {
    let vendor: Vendor

    @StateObject private var store = FaultDataStore.shared
    @State private var query = ""

    private var results: [FaultCode] {
        store.search(query, in: vendor)
    }

    var body: some View {
        VStack(spacing: 0) {
            searchField

            if results.isEmpty {
                Spacer()
                Text(query.isEmpty ? "No fault data loaded for \(vendor.rawValue) yet." : "No matches for “\(query)”.")
                    .font(UDATheme.body)
                    .foregroundColor(UDATheme.textSecondary)
                    .transition(.opacity)
                Spacer()
            } else {
                List(results) { fault in
                    NavigationLink(value: fault) {
                        FaultRow(fault: fault)
                    }
                    .listRowBackground(UDATheme.background)
                    .listRowSeparatorTint(UDATheme.divider)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: results.isEmpty)
        .background(UDATheme.background)
        // navigationDestination(for: FaultCode.self) lives at the ROOT
        // NavigationStack in HomeView.swift, not here — see that file's
        // comment for why. Deep-nesting it here caused a real bug: tapping
        // a fault would sometimes show the previous vendor's fault list
        // first, only revealing the correct detail after pressing back.
    }

    private var searchField: some View {
        HStack(spacing: UDATheme.spacingS) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(UDATheme.textSecondary)
            TextField("Search code or keyword, e.g. F01000", text: $query)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(UDATheme.textSecondary)
                }
            }
        }
        .padding(UDATheme.spacingS)
        .background(UDATheme.surface)
        .cornerRadius(UDATheme.chamferSmall)
        .padding(UDATheme.spacingM)
    }
}

private struct FaultRow: View {
    let fault: FaultCode

    private var severityColor: Color {
        switch fault.severity {
        case .fault:        return UDATheme.danger
        case .alarm:        return UDATheme.warning
        case .faultOrAlarm: return UDATheme.warning
        case .unknown:      return UDATheme.textSecondary
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: UDATheme.spacingM) {
            Text(fault.code)
                .font(UDATheme.faultCode)
                .foregroundColor(severityColor)
                .frame(width: 90, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(fault.title)
                    .font(UDATheme.bodyBold)
                    .foregroundColor(UDATheme.textPrimary)
                    .lineLimit(2)
                HStack(spacing: UDATheme.spacingXS) {
                    Text(fault.severity.rawValue)
                        .font(UDATheme.caption)
                        .foregroundColor(UDATheme.textSecondary)
                    Text("·")
                        .font(UDATheme.caption)
                        .foregroundColor(UDATheme.textSecondary)
                    Text(fault.familyLabel)
                        .font(UDATheme.caption)
                        .foregroundColor(fault.isCommonAcrossFamilies ? UDATheme.logoGreen : UDATheme.textSecondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, UDATheme.spacingXS)
    }
}
