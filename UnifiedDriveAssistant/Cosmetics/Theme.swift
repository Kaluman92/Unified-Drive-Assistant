//
//  Theme.swift
//  Unified Drive Assistant
//
//  ============================================================
//  COSMETICS BLOCK
//  ------------------------------------------------------------
//  Every visual decision for the app lives in this one file:
//  colours, fonts, weights, corner treatment ("chamfers"),
//  spacing and stroke widths. Nothing outside this file should
//  hardcode a colour, font, or radius — views just reference
//  UDATheme.* so a single edit here restyles the whole app.
//
//  LIGHT / DARK MODE
//  ------------------------------------------------------------
//  Background/surface/text/divider colours live in
//  Assets.xcassets as adaptive colour sets (AppBackground,
//  AppSurface, AppSurfaceElevated, AppTextPrimary,
//  AppTextSecondary, AppDivider, AppNavBar) — each has a light
//  and dark value baked in, so `Color("AppBackground")` resolves
//  automatically. `ThemeManager` (below) holds the user's
//  Settings choice (System / Light / Dark) and the root view
//  applies it with `.preferredColorScheme(_:)`; "System" just
//  means we don't override, so it follows the device setting.
//  Brand accent colours (teal/green/magenta/orange) are the same
//  in both modes — only neutrals adapt. To retune a light/dark
//  value, edit the matching .colorset in Assets.xcassets, not
//  this file.
//
//  QUICK TWEAKS
//  - Want bolder headings?      -> edit `headline` / `title` weight below.
//  - Want italic captions?      -> add `.italic()` in `caption`.
//  - Want squarer corners?      -> lower the chamfer values.
//  - Want a different accent?   -> edit `accent`.
//  - Want the old brown theme back? -> see the commented block
//    at the bottom of this file; swap it back in wholesale.
//  ============================================================

import SwiftUI
import Combine

// MARK: - Light / Dark preference

enum AppColorMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }

    /// Value to hand to `.preferredColorScheme(_:)`. nil means "don't
    /// override — follow the device setting."
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}

/// Holds the user's Settings choice for app appearance, persisted locally.
/// Apply it once, at the root view, with:
///   .preferredColorScheme(ThemeManager.shared.mode.colorScheme)
@MainActor
final class ThemeManager: ObservableObject {
    static let shared = ThemeManager()

    @Published var mode: AppColorMode {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: "app_color_mode") }
    }

    private init() {
        let saved = UserDefaults.standard.string(forKey: "app_color_mode") ?? ""
        self.mode = AppColorMode(rawValue: saved) ?? .dark   // default: dark, matching the logo-driven look
    }
}

enum UDATheme {

    // MARK: - Brand palette (from the Unified Drive Assistant logo)
    // These stay the same across light and dark mode.

    static let logoGreen     = Color(hex: "2ECC71")   // pie-mark segment
    static let logoMagenta   = Color(hex: "E930C9")   // pie-mark segment
    static let logoOrange    = Color(hex: "F5A623")   // pie-mark segment
    static let tealAccent    = Color(hex: "2FD9C6")   // "ALL IN ONE PLACE" tagline colour
    static let bgBlack       = Color(hex: "0D0D0F")   // used for fixed-dark text/icons on top of the (always-bright) accent colour

    // MARK: - Semantic roles
    // Views should reference these, not raw hex values. Background/surface/
    // text/divider pull from adaptive colour-set assets (see file header);
    // everything else is a fixed brand colour.

    static let background      = Color("AppBackground")
    static let surface         = Color("AppSurface")
    static let surfaceElevated = Color("AppSurfaceElevated")
    static let navBar          = Color("AppNavBar")
    static let accent          = tealAccent           // primary CTA / active tab / links
    static let accentPressed   = logoGreen             // pressed/active state of the accent
    static let textPrimary     = Color("AppTextPrimary")
    static let textSecondary   = Color("AppTextSecondary")
    static let textOnDark      = Color("AppTextPrimary")   // name kept for compatibility; adapts like textPrimary
    static let divider         = Color("AppDivider")
    static let danger          = Color(hex: "FF5B5B")   // for "Fault" severity
    static let warning         = logoOrange             // for "Alarm" severity

    // MARK: - Brand-tab identity colours
    // Used ONLY for the small vendor badge/underline on each tab —
    // never for app chrome, so the app stays visually "Unified Drive
    // Assistant" first, not any one vendor's brand. Same in both modes.

    enum VendorColor {
        static let siemens   = Color(hex: "00B4B0")
        static let schneider = logoGreen
        static let abb       = logoMagenta
        static let danfoss   = logoOrange
    }

    // MARK: - App identity strings
    // Central place for display copy so a future rename is one edit.

    static let appName    = "Unified Drive Assistant"
    static let appTagline = "ALL IN ONE PLACE"

    // MARK: - Typography
    // Standard system font (San Francisco, .default design) throughout —
    // switched away from SF Rounded for a more serious, less consumer-app
    // feel, matching the rest of iOS exactly. Sizes are deliberately compact
    // (title 24pt, body 14pt, caption 11pt) so informational/disclaimer text
    // reads as secondary detail rather than competing with the functional
    // controls above it. SF Mono is used for fault codes specifically, since
    // a monospaced code reads as more "engineering / diagnostic" than
    // proportional text.

    static let title       = Font.system(size: 24, weight: .bold, design: .default)
    static let headline    = Font.system(size: 17, weight: .semibold, design: .default)
    static let body        = Font.system(size: 14, weight: .regular, design: .default)
    static let bodyBold    = Font.system(size: 14, weight: .semibold, design: .default)
    static let caption     = Font.system(size: 11, weight: .regular, design: .default)
    static let tagline     = Font.system(size: 11, weight: .bold, design: .monospaced)   // for "ALL IN ONE PLACE"-style labels
    static let faultCode   = Font.system(size: 15, weight: .bold, design: .monospaced)
    static let faultCodeLg = Font.system(size: 22, weight: .bold, design: .monospaced)

    // MARK: - Chamfers (corner treatment)
    // "Chamfer" here = a small, deliberate corner cut rather than the fully
    // rounded default iOS look — reads as tooling/industrial, not consumer-app.
    // Keep these small and consistent; do not use continuous/pill radii.

    static let chamferSmall: CGFloat  = 3    // chips, badges
    static let chamferMedium: CGFloat = 6    // cards, list rows
    static let chamferLarge: CGFloat  = 10   // sheets, modals

    // MARK: - Stroke & spacing
    static let hairline: CGFloat = 1
    static let spacingXS: CGFloat = 4
    static let spacingS: CGFloat  = 8
    static let spacingM: CGFloat  = 16
    static let spacingL: CGFloat  = 24
    static let spacingXL: CGFloat = 32
}

// MARK: - Reusable style modifiers

struct UDACard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(UDATheme.spacingM)
            .background(UDATheme.surface)
            .overlay(
                RoundedRectangle(cornerRadius: UDATheme.chamferMedium, style: .circular)
                    .stroke(UDATheme.divider, lineWidth: UDATheme.hairline)
            )
            .cornerRadius(UDATheme.chamferMedium)
    }
}

struct UDAPrimaryButton: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(UDATheme.bodyBold)
            .foregroundColor(UDATheme.bgBlack)
            .padding(.vertical, UDATheme.spacingS + 2)
            .frame(maxWidth: .infinity)
            .background(UDATheme.accent)
            .cornerRadius(UDATheme.chamferMedium)
    }
}

extension View {
    func udaCard() -> some View { modifier(UDACard()) }
    func udaPrimaryButton() -> some View { modifier(UDAPrimaryButton()) }
}

// MARK: - Hex color helper

extension Color {
    init(hex: String) {
        let scanner = Scanner(string: hex)
        var rgb: UInt64 = 0
        scanner.scanHexInt64(&rgb)
        let r = Double((rgb >> 16) & 0xFF) / 255
        let g = Double((rgb >> 8) & 0xFF) / 255
        let b = Double(rgb & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - Previous "ProSil" light/brown theme (kept for easy revert)
// This predates the light/dark adaptive system above. If you want the
// original brown/yellow/white/black look as a fixed (non-adaptive) theme,
// replace the "Semantic roles" section above with literal Color(hex:)
// values built from these — you'd lose automatic light/dark switching for
// that palette, since it was designed as a single fixed look.
//
// static let brownDark   = Color(hex: "3B2A1A")
// static let brownMid    = Color(hex: "6B4A2C")
// static let brownLight  = Color(hex: "9C7A4E")
// static let ochreYellow = Color(hex: "D9A441")
// static let ochreDeep   = Color(hex: "B4832A")
// static let paperWhite  = Color(hex: "FAF6EF")
// static let inkBlack    = Color(hex: "1B1712")
