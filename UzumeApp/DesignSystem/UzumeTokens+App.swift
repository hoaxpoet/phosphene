// UzumeTokens+App.swift — the app's semantic colour roles.
//
// `UzumeTokens.swift` beside this file is the vendored, drift-checked copy of the
// design system's Swift token file (D-228). It is never edited; roles the app needs
// that the package does not yet publish live here.
//
// Two things this file does that the vendored package does not, both recorded in
// docs/reviews/DS.1/UPSTREAM-FINDINGS.md:
//
//   1. It publishes the full `--color-*` role set from `tokens.css`, not just the
//      subset `UzumeColor` carries.
//   2. It pins those roles to the DARK theme block of `tokens.css`. Uzume is always
//      dark (DS.1 decision A): the frame stays dark so the performance is the only
//      bright thing. The vendored `UzumeColor` builds its roles on adaptive AppKit
//      system colours, which resolve to neither the light nor the dark tokens.css
//      values — `.windowBackgroundColor` in dark appearance is far lighter than
//      `--color-canvas` #0b0c10. So the app reads roles from here, and takes
//      spacing (`UzumeSpace`), radii (`UzumeRadius`) and the performed-light
//      spectrum (`UzumeColor.violet` … `.performedLight`) from the vendored file.
//
// Every value below carries the `--color-*` name it was transcribed from, so any
// app colour greps back to a line of tokens.css.

import SwiftUI

// MARK: - UzumeAppColor

/// Semantic colour roles, transcribed from the dark-theme block of
/// `uzume-site/tokens.css`. Consume these, never the primitives.
enum UzumeAppColor {

    // MARK: Surfaces

    static let canvas = Color(hex: 0x0B0C10)          // --color-canvas
    static let surface = Color(hex: 0x14151A)         // --color-surface
    static let surfaceRaised = Color(hex: 0x1D1F25)   // --color-surface-raised
    static let surfaceSelected = Color(hex: 0x292B33) // --color-surface-selected

    // MARK: Lines

    static let line = Color(hex: 0x34363F)            // --color-line
    static let lineSubtle = Color(hex: 0x25272E)      // --color-line-subtle

    // MARK: Text

    static let textPrimary = Color(hex: 0xF4F6F1)     // --color-text-primary
    static let textSecondary = Color(hex: 0xC5C9C3)   // --color-text-secondary
    static let textTertiary = Color(hex: 0xA4A8A2)    // --color-text-tertiary
    static let textDisabled = Color(hex: 0xA4A8A2)    // --color-text-disabled

    // MARK: Controls

    static let controlDisabledBackground = Color(hex: 0x292B33) // --color-control-disabled-background
    static let controlDisabledBorder = Color(hex: 0x34363F)     // --color-control-disabled-border

    // MARK: Accent

    static let accent = Color(hex: 0x7F6AFF)          // --color-accent
    static let accentHover = Color(hex: 0xA99BFF)     // --color-accent-hover
    static let accentPressed = Color(hex: 0x7865EE)   // --color-accent-pressed
    static let accentSubtle = Color(hex: 0x352B72)    // --color-accent-subtle
    static let onAccent = Color(hex: 0x0B0C10)        // --color-on-accent
    static let focus = Color(hex: 0xA99BFF)           // --color-focus

    // MARK: Status

    static let success = Color(hex: 0x67D6A2)         // --color-success
    static let successSubtle = Color(hex: 0x20553D)   // --color-success-subtle
    static let warning = Color(hex: 0xFFD60A)         // --color-warning
    static let warningSubtle = Color(hex: 0x665700)   // --color-warning-subtle
    static let danger = Color(hex: 0xFF8A75)          // --color-danger
    static let dangerSubtle = Color(hex: 0x7F2F25)    // --color-danger-subtle
    static let info = Color(hex: 0x64D2FF)            // --color-info
    static let infoSubtle = Color(hex: 0x15506D)      // --color-info-subtle

    /// Foreground / background / border triples for the four status tones.
    enum Status {
        static let warningForeground = Color(hex: 0xFFD60A) // --color-status-warning-foreground
        static let warningBackground = Color(hex: 0x282400) // --color-status-warning-background
        static let warningBorder = Color(hex: 0x8C7600)     // --color-status-warning-border

        static let dangerForeground = Color(hex: 0xFF8A75)  // --color-status-danger-foreground
        static let dangerBackground = Color(hex: 0x321914)  // --color-status-danger-background
        static let dangerBorder = Color(hex: 0xC55646)      // --color-status-danger-border

        static let successForeground = Color(hex: 0x67D6A2) // --color-status-success-foreground
        static let successBackground = Color(hex: 0x122B21) // --color-status-success-background
        static let successBorder = Color(hex: 0x2E835E)     // --color-status-success-border

        static let infoForeground = Color(hex: 0x64D2FF)    // --color-status-info-foreground
        static let infoBackground = Color(hex: 0x102735)    // --color-status-info-background
        static let infoBorder = Color(hex: 0x1976A3)        // --color-status-info-border
    }

    // MARK: Spectrum

    static let violet = UzumeColor.violet               // --color-violet
    static let cyan = UzumeColor.cyan                   // --color-cyan
    static let gold = UzumeColor.gold                   // --color-gold
    static let ember = UzumeColor.ember                 // --color-ember
    static let ivory = Color(hex: 0xF4F6F1)             // --color-ivory

    // MARK: Scrim

    static let scrim = Color.black.opacity(0.72)        // --color-scrim (rgb(0 0 0 / 72%))

    // MARK: - Over the performance frame

    /// Tints and fills drawn *over the live visual output*, where the layer beneath is
    /// an arbitrary preset frame rather than a known surface. `tokens.css` has no
    /// vocabulary for translucency over video, so these are app-only roles and their
    /// numbers are measured results, not palette choices — see
    /// `PerformanceBackdrop` and `PresetContrastCertificationTests`.
    /// Changing any of them re-opens a contrast measurement.
    enum Performance {
        /// Paired with `.ultraThinMaterial` to hold white text at ≥4.5:1 over any frame.
        /// `--color-scrim` (72%) is NOT a substitute — it changes the measured result.
        static let backdropTint = Color.black.opacity(0.45)
        /// Behind the shortcut-help panel and the audio-stall overlay.
        static let panelTint = Color.black.opacity(0.40)
        /// Behind the toast.
        static let toastTint = Color.black.opacity(0.35)
        /// Dims a live surface behind a modal panel (plan preview, ready timeout).
        static let sheetScrim = Color.black.opacity(0.60)

        /// Raised fill over the backdrop. Stays translucent so the blur reads through;
        /// over `--color-canvas` it lands within a hair of `--color-surface-raised`.
        static let fillSubtle = Color.white.opacity(0.07)
        /// Stronger raised fill — key caps, chips.
        static let fillStrong = Color.white.opacity(0.12)
        /// Disabled/absent fill.
        static let fillFaint = Color.white.opacity(0.03)
        /// Hover fill over the backdrop.
        static let fillHover = Color.white.opacity(0.10)
        /// Barely-there hover on an otherwise unfilled row.
        static let fillHoverFaint = Color.white.opacity(0.06)
        /// Track behind a determinate bar drawn over the frame.
        static let trackFill = Color.white.opacity(0.10)
        /// The bar itself, and other high-contrast marks over the frame.
        static let markStrong = Color.white.opacity(0.70)
        /// Solid glyph fill over the backdrop (transport play/pause).
        static let glyph = Color.white
        /// Filled indicator dot / icon knockout.
        static let indicatorFill = Color.white.opacity(0.85)
        /// Outline of an unfilled indicator dot.
        static let indicatorOutline = Color.white.opacity(0.40)
    }
}

// MARK: - Hex convenience

private extension Color {
    /// Transcribes a `tokens.css` hex literal. sRGB, opaque.
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

// MARK: - UzumeAppRadius

/// Corner radii the vendored `UzumeRadius` does not carry.
///
/// `UzumeRadius` (compact 6 / standard 10 / prominent 14) and `tokens.css`
/// (`--radius-sm` 6 / `--radius-md` 12 / `--radius-lg` 16) agree only on the
/// smallest rung — an upstream disagreement, recorded in UPSTREAM-FINDINGS.md.
/// The app follows `tokens.css`, and takes `UzumeRadius.standard` (10) directly
/// where a measured value depends on it (see `PerformanceBackdrop`).
enum UzumeAppRadius {
    static let sm: CGFloat = 6   // --radius-sm  (0.375rem)
    static let md: CGFloat = 12  // --radius-md  (0.75rem)
    static let lg: CGFloat = 16  // --radius-lg  (1rem)
}

// MARK: - UzumeAppMotion

/// Motion durations from `DESIGN.md` §Shared States and Motion, which the vendored
/// tokens do not carry: control feedback 120 ms, standard state change 240 ms, authored
/// opening 480 ms, all exponential ease-out. Reduced motion keeps opacity crossfades and
/// drops everything spatial — DESIGN.md: "content appears immediately or through a
/// native crossfade". Added at DS.6; recorded in docs/reviews/DS.6/UPSTREAM-FINDINGS.md.
enum UzumeAppMotion {
    static let feedback: Double = 0.12   // control feedback
    static let standard: Double = 0.24   // standard state change
    static let opening: Double = 0.48    // authored opening

    /// Exponential ease-out. SwiftUI has no `easeOutExpo`; this is the cubic-bézier
    /// approximation of it (0.16, 1, 0.3, 1).
    static func easeOut(_ duration: Double) -> Animation {
        .timingCurve(0.16, 1, 0.3, 1, duration: duration)
    }

    /// A state change: the ease-out, or under reduced motion a plain crossfade of the
    /// same length. Opacity only either way — callers keep spatial transitions out.
    static func stateChange(reduceMotion: Bool) -> Animation {
        reduceMotion ? .linear(duration: standard) : easeOut(standard)
    }
}

// MARK: - UzumeAppShadow

/// `--shadow-raised` from `DESIGN.md` §Shadow Vocabulary: `0 16px 42px rgb(0 0 0 / 32%)`.
/// The Tonal-First Rule: only for content that genuinely floats over another surface
/// (the local-file transport bar over the live frame).
enum UzumeAppShadow {
    static let raisedColor = Color.black.opacity(0.32)
    static let raisedRadius: CGFloat = 21   // a 42 px blur is a 21 pt radius
    static let raisedY: CGFloat = 16
}
