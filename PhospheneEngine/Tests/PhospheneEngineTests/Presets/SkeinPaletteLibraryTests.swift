// SkeinPaletteLibraryTests — curation gates for the Skein.5.3/5.3b palette library.
//
// Every candidate must keep the painting readable: four well-separated stem inks that stay
// separable from each other AND from THIS ENTRY'S GROUND (Skein.5.3b: the ground is part of
// the palette — light and dark grounds) at the rendered-display level, across the FULL
// Skein.5 mood-tint swing (the tint is applied at lay time — a palette that collides when
// warmed is a palette that collides on every happy song). Plus the project colour rules and
// the role grammar (drums = the starkest structural ink vs the ground).

import Testing
import Foundation
import Metal
import simd
@testable import Presets

// MARK: - Helpers

/// Display sRGB → linear (the SkeinState init decode, FA #71).
private func toLinear(_ col: SIMD3<Float>) -> SIMD3<Float> {
    SkeinState.srgbToLinear(col)
}

/// Linear → display sRGB encode (what the `.bgra8Unorm_srgb` canvas store does).
private func toDisplay(_ col: SIMD3<Float>) -> SIMD3<Float> {
    SkeinState.linearToSRGB(col)
}

/// The classifier-style display distance (sum of absolute channel deltas, byte scale) — the
/// same metric family the colour-separation gates classify rendered pixels with.
private func displayDistance(_ lhs: SIMD3<Float>, _ rhs: SIMD3<Float>) -> Float {
    (abs(lhs.x - rhs.x) + abs(lhs.y - rhs.y) + abs(lhs.z - rhs.z)) * 255.0
}

private func luma(_ col: SIMD3<Float>) -> Float {
    col.x * 0.2126 + col.y * 0.7152 + col.z * 0.0722
}

// MARK: - Gates

@Test("Every library palette stays separable — inks vs inks AND vs its own ground — across the full mood-tint swing")
func paletteLibrary_separableUnderMoodTint() {
    // The rendered-pixel classifiers treat sum-distance < ~90 as "same colour"; require a
    // comfortable margin above that for every pair, at every tint extreme. The GROUND is not
    // tinted (it is cleared, not laid), so compare tinted inks against the untinted ground.
    let margin: Float = 100
    for entry in SkeinPaletteLibrary.candidates {
        #expect(entry.colors.count == 4, "\(entry.name): a palette is one ink per stem (4).")
        for valence: Float in [-1, -0.5, 0, 0.5, 1] {
            // EXACT production transform: display → linear (init decode) → mood tint at lay
            // time → display (canvas sRGB store).
            var swatches = entry.colors.map { toDisplay(SkeinState.moodTint(toLinear($0), valence: valence)) }
            swatches.append(entry.ground)   // this entry's ground is the fifth "colour"
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

@Test("Grounds are decisively light or dark; at most one pale highlight ink; role grammar (drums = starkest vs ground)")
func paletteLibrary_groundsPaleAndRoleGrammar() {
    var sawLight = false, sawDark = false
    for entry in SkeinPaletteLibrary.candidates {
        // Ground: decisively light (luma > 0.55) or dark (luma < 0.30) — no mid-grey mush
        // (a mid ground halves the contrast budget for both pale and dark inks).
        let groundLuma = luma(entry.ground)
        #expect(groundLuma > 0.55 || groundLuma < 0.30,
                "\(entry.name): ground luma \(groundLuma) is mid-grey — pick a side.")
        if groundLuma > 0.55 { sawLight = true } else { sawDark = true }

        // Pale inks (min channel > 0.65): at most ONE per palette — the structural highlight
        // (Pollock's whites). The separability gate already guarantees it clears the ground.
        let paleCount = entry.colors.filter { min($0.x, min($0.y, $0.z)) > 0.65 }.count
        #expect(paleCount <= 1,
                "\(entry.name): \(paleCount) pale inks — at most one structural-highlight ink (pale-tone ceiling).")

        // Role grammar: drums carries the HIGHEST contrast vs the ground (black on light
        // grounds, bone on dark) — the structural ink that keeps "who leads" readable.
        let drumsContrast = displayDistance(entry.colors[0], entry.ground)
        for idx in 1..<4 {
            #expect(drumsContrast >= displayDistance(entry.colors[idx], entry.ground),
                    "\(entry.name): ink \(idx) out-contrasts drums vs the ground — drums must be the starkest structural ink.")
        }
    }
    // The library spans both ground families (Matt: "a light background and a dark background").
    #expect(sawLight && sawDark, "The library must offer light AND dark grounds.")
}

@Test("The library's first entry is the shipped Full Fathom Five default")
func paletteLibrary_defaultIsFathom() {
    let fathom = SkeinPaletteLibrary.candidates[0]
    #expect(fathom.name == "fathom")
    #expect(fathom.colors == SkeinState.defaultPalette,
            "The library's `fathom` entry must stay byte-equal to SkeinState.defaultPalette — it IS the shipped default.")
    let groundDelta = displayDistance(fathom.ground, SkeinPaletteLibrary.creamGroundDisplay)
    #expect(groundDelta < 1.0, "fathom's ground must be the classic cream (Δ \(groundDelta)).")
}

@Test("Library mode: the track seed picks palette + ground, reseed re-picks per track; explicit palettes stay pinned")
func paletteLibrary_pickerDeterminismAndReseed() {
    // Picker is a pure deterministic function of the track seed and covers the library.
    let count = UInt32(SkeinPaletteLibrary.candidates.count)
    for seed: UInt32 in 0..<(count * 2) {
        #expect(SkeinPaletteLibrary.entry(forTrackSeed: seed).name
                    == SkeinPaletteLibrary.candidates[Int(seed % count)].name,
                "Picker must be seed % libraryCount — deterministic, same song → same palette (§5.7).")
    }

    guard let device = MTLCreateSystemDefaultDevice() else { return }
    // LIBRARY MODE (no explicit palette — the live app's path): init picks by seed; reseed
    // (the §1.5 track change) re-picks palette AND ground from the new track's identity.
    guard let state = SkeinState(device: device, seed: 0) else {
        Issue.record("SkeinState alloc failed"); return
    }
    #expect(state.palette == SkeinPaletteLibrary.candidates[0].colors,
            "Seed 0 must paint in fathom (the pre-library behaviour, byte-identical).")
    state.reseed(1)
    #expect(state.palette == SkeinPaletteLibrary.candidates[1].colors,
            "A track change (reseed) must re-pick the new track's palette in library mode.")
    #expect(state.ground == SkeinPaletteLibrary.candidates[1].ground,
            "The GROUND travels with the palette (Skein.5.3b).")
    state.reseed(0)
    #expect(state.palette == SkeinPaletteLibrary.candidates[0].colors,
            "Re-picking is deterministic — back to seed 0 is back to fathom.")

    // EXPLICIT MODE (test fixtures / contact-sheet candidates): palette + cream ground pinned.
    guard let pinned = SkeinState(device: device, seed: 0, palette: SkeinState.defaultPalette) else {
        Issue.record("SkeinState alloc failed"); return
    }
    pinned.reseed(3)
    #expect(pinned.palette == SkeinState.defaultPalette,
            "An explicit init palette must survive reseed — fixtures stay pinned.")
    #expect(pinned.ground == SkeinPaletteLibrary.creamGroundDisplay,
            "Explicit mode keeps the classic cream ground — fixtures stay pinned.")
}
