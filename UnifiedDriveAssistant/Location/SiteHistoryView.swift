//
//  SiteHistoryView.swift
//  Unified Drive Assistant
//
//  ============================================================
//  LOCATION BLOCK — FULL SITE HISTORY UI
//  ------------------------------------------------------------
//  Every saved site visit, most recent first, grouped by site
//  name. Reachable from the clock icon in ContentView's toolbar.
//  ============================================================

import SwiftUI

struct SiteHistoryView: View {
    @ObservedObject private var store = SiteVisitStore.shared

    private var groupedBySite: [(site: String, visits: [SiteVisit])] {
        let groups = Dictionary(grouping: store.visits, by: { $0.siteName })
        return groups
            .map { (site: $0.key, visits: $0.value.sorted { $0.timestamp > $1.timestamp }) }
            .sorted { ($0.visits.first?.timestamp ?? .distantPast) > ($1.visits.first?.timestamp ?? .distantPast) }
    }

    var body: some View {
        Group {
            if store.visits.isEmpty {
                VStack(spacing: UDATheme.spacingS) {
                    Spacer()
                    Text("No site visits saved yet")
                        .font(UDATheme.body)
                        .foregroundColor(UDATheme.textSecondary)
                    Text("Look up a fault, then tap \"Save as site visit\" to start building history for a location.")
                        .font(UDATheme.caption)
                        .foregroundColor(UDATheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, UDATheme.spacingL)
                    Spacer()
                }
            } else {
                List {
                    ForEach(groupedBySite, id: \.site) { group in
                        Section(group.site) {
                            ForEach(group.visits) { visit in
                                VisitRow(visit: visit)
                            }
                            .onDelete { offsets in
                                for index in offsets {
                                    SiteVisitStore.shared.delete(group.visits[index])
                                }
                            }
                        }
                        .listRowBackground(UDATheme.surface)
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .background(UDATheme.background)
        .navigationTitle("Site History")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct VisitRow: View {
    let visit: SiteVisit

    private var dateLabel: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: visit.timestamp)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("\(visit.vendor) · \(visit.faultCode)")
                    .font(UDATheme.faultCode)
                    .foregroundColor(UDATheme.textPrimary)
                Spacer()
                Text(dateLabel)
                    .font(UDATheme.caption)
                    .foregroundColor(UDATheme.textSecondary)
            }
            Text(visit.faultTitle)
                .font(UDATheme.body)
                .foregroundColor(UDATheme.textSecondary)
            if !visit.note.isEmpty {
                Text(visit.note)
                    .font(UDATheme.caption)
                    .foregroundColor(UDATheme.textPrimary)
                    .padding(.top, 2)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack { SiteHistoryView() }
}
