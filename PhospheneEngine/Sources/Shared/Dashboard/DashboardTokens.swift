// DashboardTokens — Static design-system tokens for the Telemetry dashboard.
//
// Lives in Shared so future SwiftUI chrome (settings, inspector) can consume the
// same palette without depending on the Renderer module (D-080).
//
// All values are compile-time constants — no instances, no allocations.
// Color values are derived from `.impeccable.md` OKLCH spec via offline
// conversion (see DASH.1.1 closeout in DECISIONS.md D-081). Pure neutrals are
// avoided: every chrome and text token is tinted toward the brand purple hue
// (~278°) so dashboard surfaces feel cohesive with the Phosphene visualizer.

import CoreGraphics

#if canImport(AppKit)
import AppKit
#endif

// MARK: - DashboardTokens

/// Static design-system tokens for the Telemetry dashboard.
///
/// All access via nested-type dot-notation: `DashboardTokens.TypeScale.body`.
public struct DashboardTokens: Sendable {

    // MARK: - TypeScale

    /// Point sizes used across all dashboard panels.
    public struct TypeScale: Sendable {
        /// Axis ticks, footnotes — dashboard-specific extra-small step.
        public static let caption: CGFloat = 10
        /// UPPERCASE section labels — pair with `labelTracking`. Spec `xs`.
        public static let label: CGFloat = 11
        /// Legend entries, dense rows. Spec `sm`.
        public static let body: CGFloat = 13
        /// Body copy in cards, primary UI text. Spec `md`.
        public static let bodyLarge: CGFloat = 15
        /// Numeric readouts inside instrument cards. Spec `lg`.
        public static let numeric: CGFloat = 18
        /// Mode label, beat label. Spec `xl`.
        public static let hero: CGFloat = 24
        /// Tier-0 hero numerics (BPM, lock state). Spec `2xl`.
        public static let display: CGFloat = 36
        /// Core Text kerning units applied to uppercase `label`-size text.
        public static let labelTracking: CGFloat = 1.5
    }

    // MARK: - Spacing

    /// 4-pt baseline grid spacing constants (matches `.impeccable.md` spec).
    public struct Spacing: Sendable {
        public static let xs: CGFloat = 4
        public static let sm: CGFloat = 8
        public static let md: CGFloat = 12
        public static let lg: CGFloat = 16
        public static let xl: CGFloat = 24
        public static let xxl: CGFloat = 32
    }

    // MARK: - Color

    /// Brand and chrome colors, derived from the `.impeccable.md` OKLCH spec.
    ///
    /// Chrome and text tokens are tinted toward the brand purple hue (~278°);
    /// pure neutrals are intentionally absent. Status colors stay close to
    /// pure for legibility.
    public struct Color: Sendable {
        // MARK: Surface ladder (oklch hue 275-278)

        /// `oklch(0.09 0.012 275)` — page background, deepest surface.
        public static let bg = NSColor(srgbRed: 0.007, green: 0.009, blue: 0.019, alpha: 1.0)
        /// `oklch(0.13 0.015 278)` — cards, panels.
        public static let surface = NSColor(srgbRed: 0.024, green: 0.027, blue: 0.051, alpha: 1.0)
        /// `oklch(0.17 0.018 278)` — popovers, elevated chrome.
        public static let surfaceRaised = NSColor(srgbRed: 0.053, green: 0.058, blue: 0.091, alpha: 1.0)
        /// `oklch(0.22 0.014 278)` — dividers, outlines.
        public static let border = NSColor(srgbRed: 0.098, green: 0.102, blue: 0.130, alpha: 1.0)

        // MARK: Text (oklch hue 278, ascending lightness)

        /// `oklch(0.50 0.014 278)` — secondary text, muted labels.
        public static let textMuted = NSColor(srgbRed: 0.381, green: 0.387, blue: 0.421, alpha: 1.0)
        /// `oklch(0.80 0.010 278)` — body text, off-white tinted purple.
        public static let textBody = NSColor(srgbRed: 0.737, green: 0.742, blue: 0.770, alpha: 1.0)
        /// `oklch(0.94 0.008 278)` — headings, hero numerics.
        public static let textHeading = NSColor(srgbRed: 0.916, green: 0.920, blue: 0.943, alpha: 1.0)

        // MARK: Brand

        /// `oklch(0.62 0.20 292)` — primary accent: depth, session presence.
        public static let purple      = NSColor(srgbRed: 0.550, green: 0.403, blue: 0.949, alpha: 1.0)
        /// `oklch(0.35 0.12 292)` — subtle glow, background tint for active states.
        public static let purpleGlow  = NSColor(srgbRed: 0.243, green: 0.162, blue: 0.449, alpha: 1.0)
        /// `oklch(0.70 0.17 28)` — energy, action, primary CTAs, beat moments.
        public static let coral       = NSColor(srgbRed: 0.964, green: 0.430, blue: 0.377, alpha: 1.0)
        /// `oklch(0.45 0.10 28)` — coral at rest: hover states, inactive CTA.
        public static let coralMuted  = NSColor(srgbRed: 0.517, green: 0.237, blue: 0.207, alpha: 1.0)
        /// `oklch(0.70 0.13 192)` — analytical / precision: prep, MIR, stems.
        public static let teal        = NSColor(srgbRed: 0.000, green: 0.718, blue: 0.702, alpha: 1.0)
        /// `oklch(0.40 0.08 192)` — teal at rest.
        public static let tealMuted   = NSColor(srgbRed: 0.000, green: 0.332, blue: 0.324, alpha: 1.0)

        // MARK: Status (held close to pure for legibility)

        public static let statusGreen  = NSColor(srgbRed: 0.290, green: 0.871, blue: 0.502, alpha: 1.0)
        public static let statusYellow = NSColor(srgbRed: 0.980, green: 0.800, blue: 0.082, alpha: 1.0)
        public static let statusRed    = NSColor(srgbRed: 0.973, green: 0.443, blue: 0.443, alpha: 1.0)
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
