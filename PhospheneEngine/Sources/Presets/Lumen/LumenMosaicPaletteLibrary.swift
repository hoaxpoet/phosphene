// LumenMosaicPaletteLibrary — Curated 18-palette library for Lumen Mosaic
// cell colour (Increment LM.4.7, D-LM-palette-library).
//
// The Orchestrator selects one palette **per song** via a Gaussian-weighted
// draw over mood-space distance, with the immediately previous song's
// palette excluded from the candidate set. Within a song, cells sample
// uniformly from the drawn palette's 12 entries (cellHash % 12). Hex
// anchors come from `docs/VISUAL_REFERENCES/lumen_mosaic/palette_library/`
// (authoritative design intent); the implementation here is the source of
// truth for the linear-RGB values that ship.
//
// References:
//   D-LM-palette-library (DECISIONS.md) — selection model + library architecture.
//   D-LM-cream-rescission (DECISIONS.md) — pale-tone-share ≤ 0.30 compositional rule.
//   docs/SHADER_CRAFT.md §12.7 — pale-tone-share ceiling.
//   docs/VISUAL_REFERENCES/lumen_mosaic/palette_library/ — HTML design artifacts.

import Foundation
import simd

// MARK: - LumenPalette

/// One curated 12-colour palette plus its mood-space anchor.
///
/// `colors` are in **linear RGB** (the sRGB hex values in the design
/// artifacts are converted at table-construction time). `moodAnchor.x` is
/// valence ∈ `[-1, +1]`, `moodAnchor.y` is arousal ∈ `[-1, +1]`.
public struct LumenPalette: Sendable, Hashable {
    public let name: String
    public let colors: [SIMD3<Float>]
    public let moodAnchor: SIMD2<Float>

    public init(name: String, colors: [SIMD3<Float>], moodAnchor: SIMD2<Float>) {
        self.name = name
        self.colors = colors
        self.moodAnchor = moodAnchor
    }
}

// MARK: - LumenMosaicPaletteLibrary

/// Static catalogue of the 18 Lumen Mosaic palettes plus the per-song
/// mood-biased selection algorithm.
public enum LumenMosaicPaletteLibrary {

    /// Gaussian kernel width in normalised mood-space units. Variety-leaning
    /// default — even an extreme-quadrant track has non-zero probability of
    /// drawing any palette. Tighter values (~0.20) make selection
    /// mood-dominant; looser (~0.50) make mood a soft bias.
    public static let kSigma: Float = 0.35

    /// Anti-repeat window size. The last `kAntiRepeatWindow` drawn palette
    /// indices are excluded from the candidate set on every draw. Started
    /// at 1 (just-drawn palette) per the original D-LM-palette-library
    /// rule; widened to 3 at the 2026-05-18 M7 amendment after Matt's
    /// real-music session showed within-quadrant clustering — two
    /// consecutive tracks with similar preview-clip moods could pull
    /// two *different* palettes from the same 4–5-palette neighborhood
    /// and read as "the preset didn't change much." With 18 palettes
    /// in the library, excluding the last 3 still leaves 15 mood-
    /// weighted candidates per draw. Documented at D-LM-palette-library.
    public static let kAntiRepeatWindow: Int = 3

    /// All 18 palettes in the canonical order documented at
    /// `D-LM-palette-library`. The order is load-bearing: tests reference
    /// palettes by index and the regression-harness fixture binds index 0
    /// (Autumnal) as its deterministic palette.
    public static let all: [LumenPalette] = [
        // 1. Autumnal — burning maple / oxblood / mossy bottle-green / copper.
        //    Saturated harvest; neutral mood anchor (mid valence, mid arousal).
        Self.makePalette(
            name: "Autumnal",
            hex: ["C73E1D", "E87D14", "D9A11D", "B86A00",
                  "781421", "A8203F", "1E6B3D", "6B7F1E",
                  "B36835", "DC4A23", "5C2D14", "E0AC2B"],
            valence: 0.0,
            arousal: 0.0),

        // 2. Refn Glow — sodium-vapour neon over hard noir (Drive / Neon Demon).
        //    Charged + dark; moderate-high valence, high arousal.
        Self.makePalette(
            name: "Refn Glow",
            hex: ["FF1493", "FF4081", "B7090F", "1E90FF",
                  "FF9500", "B4FF00", "0040FF", "C724B1",
                  "DC143C", "FFEE00", "00D9D9", "6A0DAD"],
            valence: 0.3,
            arousal: 0.6),

        // 3. Glacier — saturated ice; crevasse blues, aurora veils, sodium accent.
        //    Cold + alert; low valence, high arousal.
        Self.makePalette(
            name: "Glacier",
            hex: ["2EB7B0", "0B3D91", "50C878", "00E5FF",
                  "007FFF", "1F1A8F", "C71585", "4B0082",
                  "00D9D9", "3B7BAA", "1E3A5C", "FFAA00"],
            valence: -0.5,
            arousal: 0.6),

        // 4. Art Deco — Chrysler Building / Gatsby smoking room. Brass + onyx
        //    anchor; emerald, sapphire, ruby, jade. Neutral with subtle warmth.
        Self.makePalette(
            name: "Art Deco",
            hex: ["B5A642", "15151E", "046307", "0F52BA",
                  "9B111E", "00A86B", "501818", "1B4E5C",
                  "5C6A78", "884F1F", "E34234", "4B0082"],
            valence: 0.1,
            arousal: 0.0),

        // 5. Abyssal Bioluminescence — Mariana-trench dark + electric jewel glows.
        //    Two near-black anchors; low valence, high arousal.
        Self.makePalette(
            name: "Abyssal Bioluminescence",
            hex: ["03062B", "00FFE0", "6A0DAD", "39FF14",
                  "00BFFF", "FF1493", "8A2BE2", "6E0E0E",
                  "7FFFD4", "FFD700", "000033", "1E90FF"],
            valence: -0.7,
            arousal: 0.5),

        // 6. Kintsugi — gold-on-black-cracked-porcelain; sumi-ink + indigo base,
        //    gold seam + saffron accents. Melancholy / contemplative.
        Self.makePalette(
            name: "Kintsugi",
            hex: ["14182B", "1E3A8A", "D4AF37", "8B1A1A",
                  "EC5800", "8B3A3A", "43B3AE", "5F7A3E",
                  "5D1451", "F4C430", "26619C", "E34234"],
            valence: -0.4,
            arousal: -0.5),

        // 7. Carnival — Día de Muertos altar / papel picado. Max saturation,
        //    zero apology. High valence + high arousal.
        Self.makePalette(
            name: "Carnival",
            hex: ["FF8C00", "FF1493", "8B00FF", "00CED1",
                  "0047AB", "BFFF00", "C8102E", "FF00FF",
                  "00A86B", "FFA500", "DC143C", "1F1A8F"],
            valence: 0.8,
            arousal: 0.7),

        // 8. Holi — Indian spring festival gulal pigments. Pink–turmeric–
        //    vermilion–Krishna-blue. High valence + high arousal.
        Self.makePalette(
            name: "Holi",
            hex: ["FF0E84", "FF5A8B", "FF1F8F", "E8A317",
                  "F4900C", "FFD800", "E34234", "1E59C9",
                  "FF7518", "95C11F", "8E44AD", "1B998B"],
            valence: 0.7,
            arousal: 0.7),

        // 9. Geode — gemstone cross-sections. Citrine, amethyst, peridot, malachite.
        //    Cold-bright mineral; low-moderate valence, moderate arousal.
        Self.makePalette(
            name: "Geode",
            hex: ["9966CC", "E3CF09", "DC526F", "04A777",
                  "B4C424", "733635", "2A52BE", "B5651D",
                  "C13B26", "4A5859", "5C4033", "5BC8AF"],
            valence: -0.3,
            arousal: 0.4),

        // 10. Rothko Chapel — late-period oxblood + aubergine meditation.
        //     Low-value high-chroma; low valence + low arousal.
        Self.makePalette(
            name: "Rothko Chapel",
            hex: ["5C0A0A", "4E1C49", "5B3256", "B47A2C",
                  "722F37", "800020", "C54B8C", "B0561C",
                  "B22222", "2B1A2E", "B7410E", "C9A227"],
            valence: -0.6,
            arousal: -0.6),

        // 11. Tropical Aviary — scarlet macaw / quetzal / Morpho butterfly.
        //     Biological-extreme primaries; high valence + high arousal.
        Self.makePalette(
            name: "Tropical Aviary",
            hex: ["FF2400", "FF8000", "FFD300", "007FFF",
                  "009E60", "FF5F1F", "FF4F8B", "7FFF00",
                  "1560BD", "C71F37", "FF6A4D", "DE2F8F"],
            valence: 0.6,
            arousal: 0.6),

        // 12. Persian Miniature — Safavid manuscript painting. Lapis ground,
        //     malachite, vermilion, saffron, gold leaf. High valence, low arousal.
        Self.makePalette(
            name: "Persian Miniature",
            hex: ["1F3F94", "008B8B", "0BDA51", "E34234",
                  "D70040", "F4C430", "D4AF37", "B22222",
                  "93C572", "283593", "6E1F84", "2E5728"],
            valence: 0.4,
            arousal: -0.4),

        // 13. Ukiyo-e — Edo woodblock. Prussian blue, willow green, susuki gold,
        //     sakura cerise. Moderate-high valence, low arousal.
        Self.makePalette(
            name: "Ukiyo-e",
            hex: ["003153", "E34234", "1A237E", "5D8233",
                  "8E4585", "DE3163", "CC7722", "2B2B2B",
                  "007D8C", "8B4513", "BFA350", "EC5800"],
            valence: 0.3,
            arousal: -0.4),

        // 14. Cathedral Lights — Chartres / Sainte-Chapelle stained-glass.
        //     Jewel-tone ground with cream / honey / ivory highlights — the
        //     cream-rescission proof point (pale-share ≈ 16.7 %). Low valence,
        //     low arousal (solemn).
        Self.makePalette(
            name: "Cathedral Lights",
            hex: ["1B2C7A", "8B0816", "0E5C36", "5B2C6F",
                  "C8901B", "C42E45", "5B7F2E", "F2DEAC",
                  "E8B95B", "EDE4D1", "87B4D9", "1A1410"],
            valence: -0.3,
            arousal: -0.6),

        // 15. Cycladic — Greek island whitewash + cobalt + bougainvillea.
        //     Pale-rich at the structural-highlight register (~16.7 %).
        //     High valence, low arousal.
        Self.makePalette(
            name: "Cycladic",
            hex: ["F8F4EB", "0F4C81", "DA0D6D", "1B8FB5",
                  "C95B3A", "003D8E", "6B7F1E", "E8D3A3",
                  "E83A7A", "E0F2EE", "F2D03B", "2B2A28"],
            valence: 0.6,
            arousal: -0.5),

        // 16. Ming Porcelain — Jingdezhen kilns 14th–18th c. Porcelain + pale
        //     celadon ground; underglaze cobalt + sang-de-boeuf. Pale-rich
        //     (~16.7 %). High valence, low arousal.
        Self.makePalette(
            name: "Ming Porcelain",
            hex: ["F5EFE0", "1B3A8A", "6E0E18", "6CA37F",
                  "DC668E", "E3B824", "B5331C", "4E2C50",
                  "C77F6A", "2E8B57", "D7E4D0", "1F1611"],
            valence: 0.5,
            arousal: -0.6),

        // 17. Tenebrism — Caravaggio late 1590s. Black ground + dramatic warm
        //     light. Candle flame, vermilion robe, lapis drapery. Low valence,
        //     low arousal.
        Self.makePalette(
            name: "Tenebrism",
            hex: ["0A0907", "C03220", "E8B324", "1A3F94",
                  "D49475", "6F1A1E", "A67B2F", "2D4F3E",
                  "8C0817", "E2C285", "1A1612", "C29039"],
            valence: -0.7,
            arousal: -0.6),

        // 18. Obsidian — volcanic geology. Obsidian glass + basalt + ash
        //     anchors; magma orange + sulfur yellow + cinder red + a single
        //     snowmelt highlight. Low valence, high arousal.
        Self.makePalette(
            name: "Obsidian",
            hex: ["0E0B14", "F73E12", "E8D31C", "3B3833",
                  "6F8C3F", "94251A", "686157", "C9A338",
                  "1E9CB5", "F9A11B", "C7DCE2", "1C2538"],
            valence: -0.5,
            arousal: 0.7)
    ]

    // MARK: - Selection

    /// Draw a palette index for the current track via mood-biased weighted
    /// sampling, excluding any palette in `recentPaletteIndices`.
    ///
    /// - Parameters:
    ///   - mood: Per-track `(valence, arousal)` in normalised `[-1, +1]`.
    ///   - recentPaletteIndices: The last `≤ kAntiRepeatWindow` drawn
    ///     palette indices, oldest → newest. Empty for the first song of
    ///     a session. Every index in this array is removed from the
    ///     candidate set so the next N songs cannot share a palette with
    ///     each other. Window-size policy lives at the call site; this
    ///     function honours whatever exclusion set the caller provides.
    ///   - trackSeed: 64-bit deterministic seed (FNV-1a of `title|artist`
    ///     produced upstream at the track-change site). Drives the
    ///     inverse-CDF draw.
    /// - Returns: Index into `all` in `[0, 17]`.
    ///
    /// Determinism contract: same `(mood, recentPaletteIndices, trackSeed)`
    /// triple always returns the same index — load-bearing for session
    /// replay reproducibility and the regression-test suite.
    public static func selectPalette(
        mood: SIMD2<Float>,
        recentPaletteIndices: [Int],
        trackSeed: UInt64
    ) -> Int {
        let library = all
        let exclude = Set(recentPaletteIndices)
        let twoSigmaSq = 2 * kSigma * kSigma

        var weights: [Float] = []
        var indices: [Int] = []
        weights.reserveCapacity(library.count)
        indices.reserveCapacity(library.count)

        var totalWeight: Float = 0
        for (idx, palette) in library.enumerated() where !exclude.contains(idx) {
            let delta = mood - palette.moodAnchor
            let distSq = delta.x * delta.x + delta.y * delta.y
            let weight = expf(-distSq / twoSigmaSq)
            weights.append(weight)
            indices.append(idx)
            totalWeight += weight
        }

        // Defensive: every library entry is excluded (caller passed all 18
        // indices). Mathematically impossible under `kAntiRepeatWindow ≤ 17`,
        // but guard against future window growth or test-fixture abuse.
        // Return the oldest entry of the recent window as a deterministic
        // fallback.
        if indices.isEmpty {
            return recentPaletteIndices.first ?? 0
        }

        // Defensive: if all weights underflow to zero (mathematically impossible
        // with finite mood + non-zero sigma but a guard against future tuning),
        // fall back to a uniform draw across the candidate set.
        if totalWeight <= 0 {
            var prng = Mulberry32(seed: UInt32(truncatingIfNeeded: trackSeed ^ (trackSeed >> 32)))
            let uniform = prng.nextUniform()
            let pick = min(Int(uniform * Float(indices.count)), indices.count - 1)
            return indices[pick]
        }

        var prng = Mulberry32(seed: UInt32(truncatingIfNeeded: trackSeed ^ (trackSeed >> 32)))
        let target = prng.nextUniform() * totalWeight
        var cumulative: Float = 0
        for (i, weight) in weights.enumerated() {
            cumulative += weight
            if target <= cumulative { return indices[i] }
        }
        return indices.last ?? 0   // unreachable under non-zero total weight
    }

    // MARK: - Private helpers

    /// Construct one palette by converting sRGB hex to linear RGB.
    /// `hex` must contain exactly 12 entries; precondition trip indicates a
    /// table-authoring bug and should fail loudly in debug builds.
    private static func makePalette(
        name: String,
        hex: [String],
        valence: Float,
        arousal: Float
    ) -> LumenPalette {
        precondition(hex.count == 12, "LumenPalette \(name) needs exactly 12 hex entries")
        let colors = hex.map { linearRGB(fromHex: $0) }
        return LumenPalette(
            name: name,
            colors: colors,
            moodAnchor: SIMD2<Float>(valence, arousal))
    }

    /// Parse an `RRGGBB` (or `#RRGGBB`) string into linear RGB.
    /// sRGB → linear transfer follows the IEC 61966-2-1 piecewise formula.
    private static func linearRGB(fromHex raw: String) -> SIMD3<Float> {
        var hex = raw
        if hex.hasPrefix("#") { hex.removeFirst() }
        precondition(hex.count == 6, "Expected 6-digit hex, got '\(raw)'")
        let value = UInt32(hex, radix: 16) ?? 0
        let red = Float((value >> 16) & 0xFF) / 255.0
        let green = Float((value >> 8) & 0xFF) / 255.0
        let blue = Float(value & 0xFF) / 255.0
        return SIMD3<Float>(srgbToLinear(red), srgbToLinear(green), srgbToLinear(blue))
    }

    /// IEC 61966-2-1 sRGB-to-linear transfer for one channel.
    private static func srgbToLinear(_ channel: Float) -> Float {
        if channel <= 0.04045 { return channel / 12.92 }
        return powf((channel + 0.055) / 1.055, 2.4)
    }
}

// MARK: - Mulberry32 PRNG (file-private)

/// Deterministic 32-bit PRNG. Same generator the test mirror uses; kept
/// file-private so the regression-locked algorithm is the only Mulberry32
/// reachable from the public API.
private struct Mulberry32 {
    var state: UInt32

    init(seed: UInt32) { self.state = seed }

    mutating func nextUInt32() -> UInt32 {
        state = state &+ 0x6D2B79F5
        var z = state
        z = (z ^ (z >> 15)) &* (z | 1)
        z ^= z &+ ((z ^ (z >> 7)) &* (z | 61))
        return z ^ (z >> 14)
    }

    mutating func nextUniform() -> Float {
        // 24-bit precision in [0, 1).
        return Float(nextUInt32() >> 8) * (1.0 / Float(1 << 24))
    }
}
