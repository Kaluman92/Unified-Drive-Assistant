//
//  BrandTabView.swift
//  Unified Drive Assistant
//
//  ============================================================
//  FAULT LOOKUP BLOCK — BRAND TABS
//  ------------------------------------------------------------
//  Segmented control across the top for Siemens / Schneider / ABB.
//  Each vendor gets a placeholder mark (initials in their brand
//  colour) rather than the real trademarked logo — see LOGOS.md
//  in the project root for where to drop the official assets
//  once you've pulled them from each vendor's press/media kit.
//  Once added, swap `VendorMarkView`'s Text initials for
//  `Image("siemens_logo")` etc.
//  ============================================================

import SwiftUI

struct BrandTabView: View {
    @Binding var selectedVendor: Vendor
    @Namespace private var underline

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Vendor.allCases) { vendor in
                Button {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        selectedVendor = vendor
                    }
                    if let uid = AuthManager.shared.currentUser?.uid {
                        AnalyticsService.shared.logBrandSelected(uid: uid, vendor: vendor)
                    }
                } label: {
                    VStack(spacing: UDATheme.spacingXS) {
                        VendorMarkView(vendor: vendor, isSelected: vendor == selectedVendor)
                        Text(vendor.rawValue)
                            .font(UDATheme.caption)
                            .fontWeight(vendor == selectedVendor ? .semibold : .regular)
                            .foregroundColor(vendor == selectedVendor ? UDATheme.textOnDark : UDATheme.textOnDark.opacity(0.55))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, UDATheme.spacingS)
                    .overlay(alignment: .bottom) {
                        if vendor == selectedVendor {
                            Rectangle()
                                .fill(UDATheme.accent)
                                .frame(height: 3)
                                .matchedGeometryEffect(id: "tabUnderline", in: underline)
                        }
                    }
                }
            }
        }
        .background(UDATheme.navBar)
    }
}

private struct VendorMarkView: View {
    let vendor: Vendor
    let isSelected: Bool

    private var vendorColor: Color {
        switch vendor {
        case .siemens:   return UDATheme.VendorColor.siemens
        case .schneider: return UDATheme.VendorColor.schneider
        case .abb:       return UDATheme.VendorColor.abb
        case .danfoss:   return UDATheme.VendorColor.danfoss
        }
    }

    private var initials: String {
        switch vendor {
        case .siemens:   return "SI"
        case .schneider: return "SE"
        case .abb:       return "AB"
        case .danfoss:   return "DF"
        }
    }

    var body: some View {
        // TODO: replace with Image("<vendor>_logo") once official assets are added.
        Text(initials)
            .font(.system(size: 13, weight: .bold, design: .monospaced))
            .foregroundColor(.white)
            .frame(width: 30, height: 30)
            .background(vendorColor.opacity(isSelected ? 1 : 0.5))
            .cornerRadius(UDATheme.chamferSmall)
    }
}
