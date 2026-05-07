// DashboardTokens — Static design-system tokens for the Telemetry dashboard.
//
// Lives in Shared so future SwiftUI chrome (settings, inspector) can consume the
// same palette without depending on the Renderer module (D-080).
//
// All values are compile-time constants — no instances, no allocations.
// Color additions require Matt's approval; the tuning pass is DASH.5.

import CoreGraphics

#if canImport(AppKit)
import AppKit
#endif

// MARK: - DashboardTokens

/// Static design-system tokens for the Telemetry dashboard.
///
/// All access via nested-type dot-notation: `DashboardTokens.TypeScale.body`.
/// Values are placeholders tuned in DASH.5 once the layout is rendered end-to-end.
public struct DashboardTokens: Sendable {

    // MARK: - TypeScale

    /// Point sizes used across all dashboard panels.
    public struct TypeScale: Sendable {
        /// Axis ticks, footnotes.
        public static let caption: CGFloat = 10
        /// UPPERCASE section labels — pair with `labelTracking`.
        public static let label: CGFloat = 11
        /// Body copy, legend entries.
        public static let body: CGFloat = 13
        /// Numeric readouts inside instrument cards.
        public static let numeric: CGFloat = 18
        /// Mode label, beat label.
        public static let hero: CGFloat = 24
        /// Tier-0 hero numerics (BPM, lock state).
        public static let display: CGFloat = 36
        /// Core Text kerning units applied to uppercase `label`-size text.
        public static let labelTracking: CGFloat = 1.5
    }

    // MARK: - Spacing

    /// 8-pt baseline grid spacing constants.
    public struct Spacing: Sendable {
        public static let xs: CGFloat = 4
        public static let sm: CGFloat = 8
        public static let md: CGFloat = 12
        public static let lg: CGFloat = 16
        public static let xl: CGFloat = 24
        public static let xxl: CGFloat = 32
    }

    // MARK: - Color

    /// Brand and chrome colors.  All values in sRGB; DASH.5 is the tuning pass.
    public struct Color: Sendable {
        // Brand
        /// ~#7B61FF — primary accent.
        public static let purple = NSColor(srgbRed: 0.482, green: 0.380, blue: 1.000, alpha: 1.0)
        /// ~#FF6B5B — warning / energy accent.
        public static let coral  = NSColor(srgbRed: 1.000, green: 0.420, blue: 0.357, alpha: 1.0)
        /// ~#2EC4B6 — secondary accent.
        public static let teal   = NSColor(srgbRed: 0.180, green: 0.769, blue: 0.714, alpha: 1.0)

        // Status
        public static let statusGreen  = NSColor(srgbRed: 0.290, green: 0.871, blue: 0.502, alpha: 1.0)
        public static let statusYellow = NSColor(srgbRed: 0.980, green: 0.800, blue: 0.082, alpha: 1.0)
        public static let statusRed    = NSColor(srgbRed: 0.973, green: 0.443, blue: 0.443, alpha: 1.0)

        // Chrome
        public static let chromeBg     = NSColor(white: 0.078, alpha: 0.92)
        public static let chromeBorder = NSColor(white: 1.0, alpha: 0.12)

        // Text
        public static let textPrimary   = NSColor(white: 1.0, alpha: 0.95)
        public static let textSecondary = NSColor(white: 1.0, alpha: 0.65)
        public static let textMuted     = NSColor(white: 1.0, alpha: 0.45)
    }

    // MARK: - Supporting enums

    /// Typographic weight variants supported by DashboardTextLayer.
    public enum Weight: Sendable { case regular, medium }

    /// Font family selection for DashboardTextLayer draw calls.
    public enum TextFont: Sendable {
        /// SF Mono — system monospaced, used for numerics and code-like labels.
        case mono
        /// Epilogue (bundled) or system sans fallback — used for prose labels.
        case prose
    }

    /// Horizontal text alignment within a draw call.
    public enum Alignment: Sendable { case left, center, right }

    // Prevent instantiation — all members are static.
    private init() {}
}
