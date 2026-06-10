// SkeinPaletteLibraryTests — curation gates for the Skein.5.3 palette library.
//
// Every candidate must keep the painting readable: four well-separated stem colours that stay
// separable from each other AND from the cream ground at the rendered-display level, across the
// FULL Skein.5 mood-tint swing (the tint is applied at lay time — a palette that collides when
// warmed is a palette that collides on every happy song). Plus the project colour rules: the
// pale-tone ceiling and the fixed role grammar (drums = darkest ink).

import Testing
import Foundation
import simd
@testable import Presets

// MARK: - Helpers

/// Display sRGB → linear (the SkeinState init decode, FA #71).
private func toLinear(_ col: SIMD3<Float>) -> SIMD3<Float> {
    SkeinState.srgbToLinear(col)
}

/// Linear → display sRGB encode (what the `.bgra8Unorm_srgb` canvas store does).
private func toDisplay(_ col: SIMD3<Float>) -> SIMD3<Float> {
    func encode(_ val: Float) -> Float {
        val <= 0.0031308 ? val * 12.92 : 1.055 * pow(val, 1.0 / 2.4) - 0.055
    }
    return SIMD3(encode(col.x), encode(col.y), encode(col.z))
}

/// The classifier-style display distance (sum of absolute channel deltas, byte scale) — the
/// same metric family the colour-separation gates classify rendered pixels with.
private func displayDistance(_ lhs: SIMD3<Float>, _ rhs: SIMD3<Float>) -> Float {
    (abs(lhs.x - rhs.x) + abs(lhs.y - rhs.y) + abs(lhs.z - rhs.z)) * 255.0
}

// MARK: - Gates

@Test("Every library palette stays separable (incl. vs cream) across the full mood-tint swing")
func paletteLibrary_separableUnderMoodTint() {
    let creamDisplay = toDisplay(SkeinPaletteLibrary.canvasCreamLinear)
    // The rendered-pixel classifiers treat sum-distance < ~90 as "same colour"; require a
    // comfortable margin above that for every pair, at every tint extreme.
    let margin: Float = 100
    for entry in SkeinPaletteLibrary.candidates {
        #expect(entry.colors.count == 4, "\(entry.name): a palette is one colour per stem (4).")
        for valence: Float in [-1, -0.5, 0, 0.5, 1] {
            // EXACT production transform: display → linear (init decode) → mood tint at lay
            // time → display (canvas sRGB store).
            var swatches = entry.colors.map { toDisplay(SkeinState.moodTint(toLinear($0), valence: valence)) }
            swatches.append(creamDisplay)   // the ground is the fifth "colour"
            for i in 0..<swatches.count {
                for j in (i + 1)..<swatches.count {
                    let dist = displayDistance(swatches[i], swatches[j])
                    #expect(dist >= margin,
                            "\(entry.name) @ valence \(valence): swatches \(i)/\(j) collide (display distance \(dist) < \(margin)) — illegible under mood tint.")
                }
            }
        }
    }
}

@Test("Library palettes obey the pale ceiling and the role grammar (drums = darkest ink)")
func paletteLibrary_paleCeilingAndRoleGrammar() {
    for entry in SkeinPaletteLibrary.candidates {
        for (idx, col) in entry.colors.enumerated() {
            #expect(min(col.x, min(col.y, col.z)) <= 0.65,
                    "\(entry.name)[\(idx)]: pale colour (min channel \(min(col.x, min(col.y, col.z))) > 0.65) — the pale-tone ceiling forbids pale paint inks.")
        }
        func luma(_ col: SIMD3<Float>) -> Float { col.x * 0.2126 + col.y * 0.7152 + col.z * 0.0722 }
        let drums = luma(entry.colors[0])
        for idx in 1..<4 {
            #expect(drums < luma(entry.colors[idx]),
                    "\(entry.name): drums (idx 0, luma \(drums)) must be the darkest ink — idx \(idx) is darker (\(luma(entry.colors[idx]))). The role grammar keeps every palette readable.")
        }
    }
}

@Test("The library's first entry is the shipped Full Fathom Five default")
func paletteLibrary_defaultIsFathom() {
    let fathom = SkeinPaletteLibrary.candidates[0]
    #expect(fathom.name == "fathom")
    #expect(fathom.colors == SkeinState.defaultPalette,
            "The library's `fathom` entry must stay byte-equal to SkeinState.defaultPalette — it IS the shipped default.")
}
