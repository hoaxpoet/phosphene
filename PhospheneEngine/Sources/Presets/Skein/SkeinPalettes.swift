// SkeinPalettes — the curated per-stem palette library (Skein.5.3).
//
// Skein paints each track in ONE palette (chosen per track, never mid-painting — the line's
// job is "show who leads", and a stem changing colour mid-canvas breaks that read). The
// library gives the canvas variety across a playlist while the ROLE GRAMMAR stays fixed in
// every palette, so the painting stays readable in any of them:
//
//   [0] drums  — the darkest ink (the skeletal flicks)
//   [1] bass   — the deep, heavy, saturated weight
//   [2] vocals — the warm bright lead
//   [3] other  — the contrast accent (cool or vivid)
//
// Rules every entry must pass (regression-locked by `paletteLibrary_separableUnderMoodTint`):
//   • One stable, well-separated colour per stem — separable from each other AND from the
//     cream ground (linear 0.66/0.60/0.50) at the rendered-display level, INCLUDING under the
//     full Skein.5 mood-tint swing (±18 % warm/cool + saturation scale, D-152) — the tint is
//     applied at lay time, so a palette that collides when warmed is a palette that collides
//     on a happy song.
//   • Dark colours must survive the sRGB round-trip legibly (the Skein.3 charcoal lesson,
//     FA #71 — `SkeinState` decodes display → linear at init; these entries are DISPLAY sRGB).
//   • No pale-dominant entries (CLAUDE.md pale-tone ceiling); vivid by project register.
//
// Colours are DISPLAY-space sRGB (what the viewer sees on the canvas), like
// `SkeinState.defaultPalette`. The default remains Full Fathom Five (`fathom`).

import simd

// MARK: - SkeinPaletteLibrary

/// The curated palette candidates for Skein (Skein.5.3). Selection mechanism (deterministic
/// per-track / mood-matched) is wired by the picker once the curation is signed off.
public enum SkeinPaletteLibrary {

    /// One curated palette: a name and four DISPLAY-sRGB colours in stem order
    /// [drums, bass, vocals, other].
    public struct Entry: Sendable {
        public let name: String
        /// Short product-level character note (shown on contact sheets / in docs).
        public let character: String
        public let colors: [SIMD3<Float>]
    }

    /// The candidates, dark/moody → bright/vivid. `fathom` is the shipped Skein.3 default.
    public static let candidates: [Entry] = [
        Entry(name: "fathom",
              character: "the Full Fathom Five default — charcoal, oxblood, ochre gold, teal",
              colors: [SIMD3(0.12, 0.13, 0.18), SIMD3(0.62, 0.13, 0.16),
                       SIMD3(0.90, 0.62, 0.16), SIMD3(0.12, 0.58, 0.55)]),
        Entry(name: "nocturne",
              character: "dark and moody — ink blue-black, deep violet, moonlit gold, ice blue",
              colors: [SIMD3(0.07, 0.08, 0.14), SIMD3(0.30, 0.16, 0.58),
                       SIMD3(0.85, 0.70, 0.32), SIMD3(0.32, 0.62, 0.80)]),
        Entry(name: "terra",
              character: "earthy and warm — dark umber, rust, sun gold, sage",
              colors: [SIMD3(0.16, 0.11, 0.08), SIMD3(0.58, 0.24, 0.10),
                       SIMD3(0.93, 0.68, 0.22), SIMD3(0.34, 0.54, 0.40)]),
        Entry(name: "jewel",
              character: "rich jewel tones — deep violet, crimson, saffron, emerald",
              colors: [SIMD3(0.28, 0.10, 0.45), SIMD3(0.82, 0.10, 0.30),
                       SIMD3(0.97, 0.72, 0.15), SIMD3(0.05, 0.62, 0.45)]),
        Entry(name: "inkpop",
              character: "ink plus pop — near-black, cobalt, hot orange, magenta",
              colors: [SIMD3(0.08, 0.09, 0.12), SIMD3(0.10, 0.32, 0.75),
                       SIMD3(0.95, 0.55, 0.10), SIMD3(0.80, 0.14, 0.50)]),
        Entry(name: "electric",
              character: "vivid synthetic — violet charcoal, magenta, acid orange, cyan",
              colors: [SIMD3(0.13, 0.09, 0.20), SIMD3(0.78, 0.10, 0.48),
                       SIMD3(0.96, 0.62, 0.08), SIMD3(0.08, 0.66, 0.85)])
    ]

    /// The canvas ground in LINEAR space (must mirror `kSkeinCanvasCream` in Skein.metal) —
    /// every palette colour must stay separable from it too.
    public static let canvasCreamLinear = SIMD3<Float>(0.66, 0.60, 0.50)
}
