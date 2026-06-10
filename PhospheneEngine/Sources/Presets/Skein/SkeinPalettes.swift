// SkeinPalettes — the curated per-stem palette library (Skein.5.3 / 5.3b).
//
// Skein paints each track in ONE palette (chosen per track, never mid-painting). Skein.5.3b
// (Matt's round-1 curation feedback): every palette is ANCHORED ON A NAMED abstract-
// expressionist work — not invented hue sets — and the CANVAS GROUND is part of the palette
// (light AND dark grounds; *Blue Poles* is the canonical dark-ground drip painting).
//
// The ROLE GRAMMAR stays fixed so the painting reads the same in every palette:
//
//   [0] drums  — the starkest structural ink vs the ground (black on light, bone on dark)
//   [1] bass   — the deep, heavy, saturated weight
//   [2] vocals — the bright lead
//   [3] other  — the accent
//
// Rules every entry must pass (regression-locked by `SkeinPaletteLibraryTests`):
//   • Inks separable from each other AND from THIS entry's ground at the rendered-display
//     level, across the full Skein.5 mood-tint swing (D-152 — tint applies at lay time).
//   • drums carries the highest contrast vs the ground (the structural-ink grammar).
//   • Grounds are decisively light (luma > 0.55) or dark (luma < 0.30) — no mid-grey mush.
//   • At most ONE pale ink per palette (a structural highlight — Pollock's whites), and dark
//     colours must survive the sRGB round-trip legibly (FA #71).
//
// Colours + grounds are DISPLAY-space sRGB. The default remains Full Fathom Five (`fathom`).

import simd

// MARK: - SkeinPaletteLibrary

/// The curated palette candidates for Skein (Skein.5.3b — pending Matt's re-curation).
public enum SkeinPaletteLibrary {

    /// One curated palette: a name, the named reference work it is anchored on, the canvas
    /// GROUND, and four DISPLAY-sRGB inks in stem order [drums, bass, vocals, other].
    public struct Entry: Sendable {
        public let name: String
        /// The named reference work/painter this palette is drawn from (the anchor).
        public let anchor: String
        /// The canvas ground (display sRGB) — cleared at track start, part of the palette.
        public let ground: SIMD3<Float>
        public let colors: [SIMD3<Float>]
    }

    /// The candidates — three light grounds, three dark. `fathom` is the shipped default and
    /// MUST stay at index 0 (seed 0 → fathom keeps every no-palette fixture byte-identical).
    public static let candidates: [Entry] = [
        Entry(name: "fathom",
              anchor: "Pollock — Full Fathom Five (1947)",
              ground: creamGroundDisplay,
              colors: [SIMD3(0.12, 0.13, 0.18), SIMD3(0.62, 0.13, 0.16),
                       SIMD3(0.90, 0.62, 0.16), SIMD3(0.12, 0.58, 0.55)]),
        Entry(name: "autumn",
              anchor: "Pollock — Autumn Rhythm, Number 30 (1950)",
              ground: SIMD3(0.75, 0.68, 0.54),                       // raw linen (deep enough for bone to read)
              colors: [SIMD3(0.07, 0.07, 0.07),                       // black enamel
                       SIMD3(0.38, 0.25, 0.14),                       // umber
                       SIMD3(0.94, 0.91, 0.82),                       // bone white (the highlight ink)
                       SIMD3(0.30, 0.42, 0.45)]),                     // slate teal hint
        Entry(name: "convergence",
              anchor: "Pollock — Convergence (1952)",
              ground: SIMD3(0.84, 0.83, 0.79),                       // grey-white
              colors: [SIMD3(0.06, 0.06, 0.07),                       // black
                       SIMD3(0.80, 0.13, 0.10),                       // cadmium red
                       SIMD3(0.94, 0.78, 0.14),                       // cadmium yellow
                       SIMD3(0.16, 0.36, 0.76)]),                     // cobalt blue
        Entry(name: "poles",
              anchor: "Pollock — Blue Poles (1952)",
              ground: SIMD3(0.10, 0.10, 0.16),                       // deep indigo-black
              colors: [SIMD3(0.90, 0.86, 0.74),                       // bone white tangle
                       SIMD3(0.25, 0.38, 0.82),                       // ultramarine (the poles)
                       SIMD3(0.93, 0.49, 0.12),                       // cadmium orange
                       SIMD3(0.55, 0.60, 0.70)]),                     // aluminum smoke (the silver paint)
        Entry(name: "nocturne",
              anchor: "all-cool nocturne register — no warm hue anywhere",
              ground: SIMD3(0.07, 0.09, 0.13),                       // night slate
              colors: [SIMD3(0.86, 0.90, 0.94),                       // silver white
                       SIMD3(0.20, 0.30, 0.70),                       // ultramarine depth
                       SIMD3(0.45, 0.78, 0.88),                       // ice cyan
                       SIMD3(0.55, 0.42, 0.85)]),                     // cold violet
        Entry(name: "ember",
              anchor: "Rothko — Four Darks in Red (1958) register",
              ground: SIMD3(0.13, 0.07, 0.08),                       // maroon black
              colors: [SIMD3(0.88, 0.80, 0.66),                       // parchment
                       SIMD3(0.66, 0.10, 0.12),                       // deep crimson
                       SIMD3(0.91, 0.45, 0.12),                       // ember orange
                       SIMD3(0.56, 0.44, 0.52)])                      // smoke mauve
    ]

    /// The classic cream ground in LINEAR space (mirrors `kSkeinCanvasCream` in Skein.metal —
    /// the pre-5.3b fixed ground, still the explicit-mode default for every test fixture).
    public static let canvasCreamLinear = SIMD3<Float>(0.66, 0.60, 0.50)

    /// The cream ground in display space (fathom's `ground`).
    public static let creamGroundDisplay: SIMD3<Float> = SkeinState.linearToSRGB(canvasCreamLinear)

    /// The per-track picker (Matt's choice 2026-06-10: "per-track, fixed"): the SAME track
    /// identity that seeds the painter trajectory picks the palette, deterministically — the
    /// same song always paints the same painting in the same colours (§5.7), and a playlist
    /// rotates the library naturally. Seed 0 (every no-palette test fixture) → `fathom`.
    public static func entry(forTrackSeed seed: UInt32) -> Entry {
        candidates[Int(seed % UInt32(candidates.count))]
    }
}
