//
//  FaultDetailView.swift
//  Unified Drive Assistant
//
//  ============================================================
//  FAULT LOOKUP BLOCK — DETAIL
//  ------------------------------------------------------------
//  The Cause and Remedy fields shown here come straight from your
//  verified source spreadsheet — this is the "facts, not just AI"
//  layer. AIAssistantView is appended below it, opt-in, and never
//  replaces these fields.
//  ============================================================

import SwiftUI

struct FaultDetailView: View {
    let fault: FaultCode
    @State private var showSaveSiteVisit = false
    // Guards against onAppear firing more than once for the same push — a
    // known SwiftUI quirk with navigationDestination(for:)-driven pushes,
    // independent of the earlier duplicate-declaration bug. Ensures the
    // analytics event (and anything else added to onAppear later) only
    // fires once per fault viewed, regardless of how many times the
    // framework calls onAppear underneath.
    @State private var hasLoggedAppearance = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: UDATheme.spacingL) {

                VStack(alignment: .leading, spacing: UDATheme.spacingXS) {
                    Text(fault.code)
                        .font(UDATheme.faultCodeLg)
                        .foregroundColor(UDATheme.accentPressed)
                    Text(fault.title)
                        .font(UDATheme.title)
                        .foregroundColor(UDATheme.textPrimary)
                    HStack(spacing: UDATheme.spacingS) {
                        Tag(text: fault.severity.rawValue)
                        Tag(text: "\(fault.brand) · \(fault.familyLabel)")
                        if fault.isCommonAcrossFamilies {
                            Tag(text: "COMMON FAULT", tint: UDATheme.logoGreen)
                        }
                    }
                    if fault.isCommonAcrossFamilies {
                        Text("This fault code is shared across \(fault.families.count) \(fault.brand) drive families: \(fault.familyLabel).")
                            .font(UDATheme.caption)
                            .foregroundColor(UDATheme.textSecondary)
                    }
                }

                if !fault.addInfo.isEmpty {
                    FieldBlock(label: "ADDITIONAL INFO", text: fault.addInfo)
                }

                FieldBlock(label: "CAUSE", text: fault.cause)
                if !fault.remedy.isEmpty {
                    FieldBlock(label: "REMEDY", text: fault.remedy)
                } else {
                    Text("No specific remedy provided in the source data for this code — refer to the drive's manual, or ask the AI assistant below for general guidance on the cause above.")
                        .font(UDATheme.caption)
                        .foregroundColor(UDATheme.textSecondary)
                }

                AIAssistantView(fault: fault)

                // Restored — proven NOT to be the cause of the navigation
                // bug via direct testing (removing it entirely didn't fix it).
                Button {
                    showSaveSiteVisit = true
                } label: {
                    Label("Save as site visit", systemImage: "mappin.and.ellipse")
                }
                .foregroundColor(UDATheme.accentPressed)
                .font(UDATheme.bodyBold)
            }
            .padding(UDATheme.spacingM)
        }
        .background(UDATheme.background)
        .onAppear {
            guard !hasLoggedAppearance else { return }
            hasLoggedAppearance = true
            if let uid = AuthManager.shared.currentUser?.uid {
                AnalyticsService.shared.logFaultLookup(uid: uid, vendor: Vendor(rawValue: fault.brand) ?? .siemens, code: fault.code)
            }
        }
        .sheet(isPresented: $showSaveSiteVisit) {
            SaveSiteVisitView(vendor: fault.brand, faultCode: fault.code, faultTitle: fault.title)
        }
    }
}

private struct FieldBlock: View {
    let label: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: UDATheme.spacingXS) {
            Text(label)
                .font(UDATheme.caption)
                .foregroundColor(UDATheme.textSecondary)
                .tracking(1)
            Text(text)
                .font(UDATheme.body)
                .foregroundColor(UDATheme.textPrimary)
        }
        .udaCard()
    }
}

private struct Tag: View {
    let text: String
    var tint: Color = UDATheme.accent
    var body: some View {
        Text(text)
            .font(UDATheme.caption)
            .foregroundColor(UDATheme.bgBlack)
            .padding(.horizontal, UDATheme.spacingS)
            .padding(.vertical, 4)
            .background(tint.opacity(0.6))
            .cornerRadius(UDATheme.chamferSmall)
    }
}
