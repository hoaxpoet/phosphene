# LM.4.7 — Curated 18-palette library + per-song mood-biased selection

**Increment ID:** LM.4.7
**Status:** ⏳ Planned (paperwork landed 2026-05-18 at commits `24b65125`..`120529cb`; this prompt drives implementation)
**Authoritative decisions:** D-LM-palette-library, D-LM-cream-rescission (`docs/DECISIONS.md`)
**Related increment plan entry:** `docs/ENGINEERING_PLAN.md` Phase LM → "Increment LM.4.7"
**Bug being resolved:** BUG-014 (`docs/QUALITY/KNOWN_ISSUES.md`)

---

## The product change in one paragraph

Lumen Mosaic currently samples cell colours from the full 16M-colour RGB cube (LM.4.6 baseline) with a small per-track chromatic tint sliding the sampling window (LM.7). The result is that every track looks like a random sample from the same statistical distribution — only the aggregate mean shifts. After this increment lands, Lumen Mosaic samples cells from **one of 18 hand-authored 12-colour palettes** that the Orchestrator picks per song based on mood. A track played at low valence and low arousal is much more likely to draw Cathedral Lights or Rothko Chapel than Carnival; a high-valence high-arousal track is much more likely to draw Carnival or Holi than Tenebrism. Two songs in a row never draw the same palette. The palette change is visible at track boundaries — the panel character (the colour vocabulary the eye reads) shifts when the song shifts.

This closes the LM.4.6 "panel-aggregate is statistically identical across tracks" trade-off Matt accepted with the *"I'm giving up the fight on colors"* white flag, and replaces it with a curated, mood-aware variety register.

---

## Read these first

In this order:

1. `docs/DECISIONS.md` — D-LM-palette-library and D-LM-cream-rescission (the two new entries; search for the headings). These are the authoritative contract.
2. `docs/VISUAL_REFERENCES/lumen_mosaic/palette_library/` — README + four HTML files. The HTMLs are the **authoritative design intent** for hex anchors, named colours per palette, role groupings, and the panel-preview character each palette is supposed to produce. Open them in a browser and look at the swatches and the preview panels at the bottom of each plate.
3. `docs/ENGINEERING_PLAN.md` Phase LM → "Increment LM.4.7" — Scope, Done-when, Verify (this prompt repeats the substance; the entry is the cert-traceable artifact).
4. `docs/QUALITY/KNOWN_ISSUES.md` — BUG-014 (the trade-off this increment closes).
5. `CLAUDE.md` — top to bottom. Especially the GPU Contract pointer (slot 8 is reserved per `D-LM-buffer-slot-8`), the Visual Quality Floor pointer (pale-tone-share rule), the project DO-NOT list bullet on pale-dominant panels, and the Failed Approach entries that govern Lumen Mosaic (#33 free-running `sin(time)`, #44 Metal-builtin shadowing, #57 acoustically-impossible gate combinations — same shape applies to any new mood-thresholding logic).
6. `docs/SHADER_CRAFT.md` §12.7 — the pale-tone-share ceiling formal rule. §12.6 unaffected.

You do not need to read the full Phase LM history; the LM.4.6 + LM.6 + LM.7 entries in ENGINEERING_PLAN.md and the corresponding D-numbers are sufficient context.

---

## What the codebase already does (don't re-implement)

- **Slot-8 fragment buffer wiring** is in place per `D-LM-buffer-slot-8` (Increment LM.0). `RenderPipeline.directPresetFragmentBuffer3` setter + binding at fragment slot 8 across staged / mv_warp / direct / lighting pass. **Use this slot for the 12-colour palette payload.**
- **`LumenPatternState` Swift struct** at `PhospheneEngine/Sources/Presets/Lumen/LumenPatternEngine.swift` is the bridge type. Currently 376 B. The MSL-side struct is declared in `PhospheneEngine/Sources/Presets/PresetLoader+Preamble.swift`. Both must stay byte-for-byte consistent.
- **Track-change hook** is at `PhospheneApp/VisualizerEngine+Stems.swift:480` — already calls `lumenEngine.setTrackSeed(fromHash:)` with the FNV-1a hash of `title|artist`. This is the natural site to also call a new `lumenEngine.setPalette(_:)` after running the per-song palette selection.
- **`lm_cell_palette` MSL function** at `PhospheneEngine/Sources/Presets/Shaders/LumenMosaic.metal` (search for `lm_cell_palette`) is the function to rewrite. The LM.3.2 team/period beat-step ratchet (`lumen.bassCounter` / `lumen.midCounter` / `lumen.trebleCounter` and the Pareto-period mapping) is upstream of `lm_cell_palette` and must be preserved unchanged — only the final hash → RGB lookup changes to "hash → palette-index (mod 12) → palette[index]".
- **LM.6 cell-depth gradient + optional hot-spot** is downstream of `lm_cell_palette` in `sceneMaterial`. Preserve unchanged.
- **`LumenPaletteSpectrumTests`** is the regression suite to rewrite. The Swift mirror of `lm_cell_palette` logic also lives in this file.
- **`PresetRegressionTests`** is the golden-hash gate. The Lumen Mosaic hash will change in this increment — regen it once at the end and pin the new value.
- **The 4 `LumenLightAgent` slots** stay on the GPU buffer for ABI continuity per the LM.3.2 carry-forward; agent intensity / colour fields remain unused by the shader. Do not retire them in this increment.

---

## What this increment changes

### 1. New Swift file: `PhospheneEngine/Sources/Presets/Lumen/LumenMosaicPaletteLibrary.swift`

Public struct `LumenPalette`:

```
public struct LumenPalette: Sendable, Hashable {
    public let name: String           // "Autumnal", "Refn Glow", ...
    public let colors: [SIMD3<Float>] // exactly 12 entries; linear RGB
    public let moodAnchor: SIMD2<Float> // (valence, arousal) in [-1, +1]
}
```

Public constant `LumenMosaicPaletteLibrary.all: [LumenPalette]` — exactly 18 palettes in the order:

1. Autumnal
2. Refn Glow
3. Glacier
4. Art Deco
5. Abyssal Bioluminescence
6. Kintsugi
7. Carnival
8. Holi
9. Geode
10. Rothko Chapel
11. Tropical Aviary
12. Persian Miniature
13. Ukiyo-e
14. Cathedral Lights
15. Cycladic
16. Ming Porcelain
17. Tenebrism
18. Obsidian

Hex values are in `docs/VISUAL_REFERENCES/lumen_mosaic/palette_library/` — read each HTML's `data-palette` attribute on each plate's `.preview-grid` div to get the 12-hex-string array in palette order; convert each `RRGGBB` to a linear-RGB `SIMD3<Float>` (linear RGB means: divide each channel by 255 first to get sRGB-encoded `[0, 1]`, then apply the sRGB-to-linear transfer function — `pow((x + 0.055) / 1.055, 2.4)` for `x > 0.04045`, else `x / 12.92`. The hex values in the HTMLs are sRGB; the GPU shader's existing inputs are linear; convert so the palette is on the same colour-space footing as the rest of the engine).

**Mood anchors:** the README at `docs/VISUAL_REFERENCES/lumen_mosaic/palette_library/README.md` lists indicative groupings (high-valence high-arousal: Carnival, Holi, Tropical Aviary, Refn Glow; high-valence low-arousal: Cycladic, Ming Porcelain, Persian Miniature, Ukiyo-e; low-valence high-arousal: Abyssal Bioluminescence, Obsidian, Glacier, Geode; low-valence low-arousal: Rothko Chapel, Tenebrism, Cathedral Lights, Kintsugi; neutral: Autumnal, Art Deco). Pick concrete `(v, a)` anchor values per palette consistent with these groupings — typical magnitudes `±0.5` to `±0.7`, with neutrals near `(0, 0)`. Document each anchor with a one-line comment naming the character (`/// Rothko Chapel — late-period oxblood + aubergine meditation; low valence, low arousal.`).

Public function `LumenMosaicPaletteLibrary.selectPalette(mood:previousPaletteIndex:trackSeed:) -> Int`:

- Inputs: `mood: SIMD2<Float>` (current track's valence + arousal), `previousPaletteIndex: Int?` (the previously drawn palette index, `nil` for the first song of a session), `trackSeed: UInt64` (the FNV-1a `title|artist` hash already computed at the track-change site).
- Output: index in `[0, 17]` of the drawn palette.
- Algorithm:
  1. Build the candidate set = `all` minus the palette at `previousPaletteIndex` (if non-nil).
  2. For each candidate `i`, compute `weight_i = exp( -‖mood − anchor_i‖² / (2 × σ²) )` with file-scope `kSigma: Float = 0.35`.
  3. Normalise weights to a probability distribution.
  4. Draw via inverse-CDF sampling using a Mulberry32 PRNG seeded from `trackSeed`.
  5. Return the drawn index.
- Document: same `(track, previous-palette)` → same drawn index. Determinism is load-bearing for the test suite and for session-replay reproducibility.

### 2. Extend `LumenPatternState` to carry the per-song palette

The 12-colour palette must reach the shader as a slot-8 buffer payload. Two acceptable shapes:

- **(a) Pack into `LumenPatternState`** as a fixed-size array of 12 × `SIMD4<Float>` (alpha unused; 192 B), bringing the struct to 376 + 192 = 568 B. Update the MSL preamble declaration in `PresetLoader+Preamble.swift` to match byte-for-byte. Update the `MemoryLayout<LumenPatternState>.stride` invariants. Mirror in any test that checks the struct size.
- **(b) Bind the palette as a separate slot** — slot 9 — via a new `directPresetFragmentBuffer4` setter on `RenderPipeline`. Requires extending the GPU contract (CLAUDE.md GPU Contract section) and updating every binding site that currently binds slots 6/7/8. Heavier infrastructure work.

**Prefer (a)** unless the byte-layout migration tests force (b). The pattern of additive struct extension is established by D-099 (additive `Common.metal` struct extensions) and the slot-8 history. Document the new size + offsets in the LumenPatternState docstring; bump `// 376 bytes — LM.3.2` to the new figure; update the comment block enumerating member offsets.

Add Swift accessor `LumenPatternEngine.setPalette(_ palette: LumenPalette)` that writes the 12 colours into the buffer-backed `LumenPatternState`. Document that this is called at most once per track change.

### 3. Rewrite `lm_cell_palette` in `LumenMosaic.metal`

Replace the current `lm_hash_u32` → RGB body with:

```
// LM.4.7 — palette-table lookup
uint h = lm_hash_u32(cellHash ^ (uint(step) × 0x9E3779B9u) ^ trackSeed ^ (sectionSalt × 0xCC9E2D51u));
uint idx = h % 12u;
float3 rgb = lumen.palette[idx].rgb;   // 12-entry palette in LumenPatternState (slot 8)
return rgb;
```

Remove:
- The LM.7 `trackTint` block (raw-tint vector, mean-shift, chromatic projection, `kTintMagnitude` constant).
- Any LM.4.6-era hash → RGB direct mapping fallback code.

Preserve everything upstream of `lm_cell_palette` (team-counter ratchet, Pareto periods, cell-hash derivation, section-salt computation) and everything downstream (LM.6 depth gradient + hot-spot, brightness, bar pulse).

### 4. Wire the per-song selection at track change

At `PhospheneApp/VisualizerEngine+Stems.swift` (the existing track-change handler near line 480), after the existing `setTrackSeed(fromHash:)` call, add:

```
let mood = SIMD2<Float>(/* prepared valence, prepared arousal for this track */)
let chosen = LumenMosaicPaletteLibrary.selectPalette(
    mood: mood,
    previousPaletteIndex: lumenEngine.previousPaletteIndex,
    trackSeed: hash
)
lumenEngine.setPalette(LumenMosaicPaletteLibrary.all[chosen])
lumenEngine.previousPaletteIndex = chosen
```

`LumenPatternEngine` needs a new `var previousPaletteIndex: Int?` property (private setter is fine; expose via internal-visibility computed property if needed for tests). It resets to `nil` when the engine is re-instantiated (i.e. when Lumen Mosaic becomes active for the first time in a session); it persists across track changes within a session.

If the prepared-mood values are not available on the track-change path (e.g. live reactive mode before stems converge), fall back to `mood = SIMD2<Float>(0, 0)` — the centre of mood-space — which biases toward Autumnal / Art Deco (neutral palettes) without crashing. Document the fallback inline.

### 5. Rewrite `LumenPaletteSpectrumTests`

Retire the LM.4.6 + LM.7 test suites (uniform-RGB-cube coverage, chromatic-projection assertions). Replace with a new test suite asserting the LM.4.7 contract:

- **Suite: palette membership.** For each of the 18 palettes, mirror the shader's `lm_cell_palette` logic in Swift, sample N ≥ 1000 cell-hash inputs, and assert every output RGB is within float-epsilon of one of the 12 palette entries.
- **Suite: per-song determinism.** Same `(track, previous-palette, mood)` triple → same `selectPalette` index across repeated calls.
- **Suite: anti-repeat.** For every `(palette_i, mood)` combination, `selectPalette(mood, previousPaletteIndex: i, trackSeed: ...)` must return an index `≠ i`. Verify across the 18 palettes and a small grid of mood values.
- **Suite: mood-weighted distribution shape.** For a high-valence high-arousal mood (e.g. `(0.7, 0.7)`), Carnival / Holi / Tropical Aviary / Refn Glow appear in the drawn distribution at higher frequency than Rothko Chapel / Tenebrism / Cathedral Lights when sampled across N ≥ 10,000 distinct trackSeeds. Same in reverse for low-valence low-arousal mood. Do not assert specific frequencies (those are tuning-surface); assert relative ordering.
- **Suite: pale-tone-share gate (the LM.9 gate per D-LM-cream-rescission).** For each of the 18 palettes, sample N ≥ 1000 cell-hashes, count cells where `min(R, G, B) > 0.65`, and assert the count divided by N is ≤ 0.30. Cathedral Lights specifically is the calibration palette — its expected share is ~0.167 (2 of 12). All other palettes are well below the ceiling per the README's audit table.
- **Suite: track-change reproducibility.** A scripted sequence of track identities played in order produces a reproducible sequence of drawn palettes (locks the determinism contract for session replay).

Remove the LM.7-era `test_achromaticAlignedSeed_doesNotWash` test — the achromatic-axis wash failure mode cannot occur on the palette-table path (cells sample from a curated 12-entry table that avoids the achromatic axis by construction).

### 6. PresetRegression golden-hash regen

The `PresetRegressionTests` Lumen Mosaic golden hash currently locked at `0xF0F0C8CCCCC8F0F0` will change in this increment — the regression-harness slot-8 path is no longer equivalent to "neutral palette" because the shader now reads `lumen.palette[idx]` regardless of how `trackPaletteSeed{A,B,C,D}` is set. The regression test fixture needs an explicit palette payload (or a documented "no-palette-bound = sentinel zero-palette behaviour"). Two acceptable shapes:

- **(a)** Make the regression-harness bind a known fixed palette (e.g. Autumnal) and re-pin the golden hash to whatever the deterministic Autumnal-fed render produces.
- **(b)** Make `lm_cell_palette` detect the all-zero palette and fall through to a stable fallback (e.g. uniform-grey or a known "regression-only" colour), keeping the existing hash. Less clean — couples shader logic to test infrastructure.

**Prefer (a).** Regen the hash, update `PresetRegressionTests` to pin the new value, document the regen in the commit message.

### 7. Remove the LM.7 chromatic-projection code

- Remove `kTintMagnitude` and the LM.7 tint block from `LumenMosaic.metal`.
- Remove the LM.7 file-header paragraph and amend the file-header docstring to describe the LM.4.7 path (palette table from slot 8, indexed by hash). The existing LM.4.6 / LM.6 / file-header history can be condensed to one paragraph each.
- Remove `LMPalette.tintMagnitude` from the Swift mirror in the test file (the test file is being fully rewritten anyway; this is housekeeping).
- The `trackPaletteSeed{A,B,C,D}` fields on `LumenPatternState` and in the MSL preamble can be retired entirely now — nothing reads them after this increment. **However:** the FNV-1a track-seed hashing in `VisualizerEngine+Stems.swift` still produces a 64-bit hash that this increment's `selectPalette` consumes; only the *seed-to-state-buffer plumbing* (the four `trackPaletteSeed` floats in `LumenPatternState`) is what retires.

If retiring the four floats shifts byte offsets enough to be risky (it changes 16 bytes within LumenPatternState), leave them in place with a `// LM.7-era; unused after LM.4.7` comment and retire them in a follow-up cleanup increment. The judgement call is yours; the simpler path is "leave them, comment-only" since the only cost is 16 B of dead struct space.

---

## Done when

- [ ] `PhospheneEngine/Sources/Presets/Lumen/LumenMosaicPaletteLibrary.swift` exists with `LumenPalette` struct, the 18 named palettes in order, explicit moodAnchors per palette, and the `selectPalette(...)` weighted-draw function.
- [ ] `LumenPatternState` extended (preferred shape (a) above) to carry the 12-colour palette; Swift size + MSL preamble declaration stay byte-consistent; `MemoryLayout<LumenPatternState>.stride` invariants updated; `directPresetFragmentBuffer3` setter wires the new buffer at fragment slot 8.
- [ ] `lm_cell_palette` rewritten in `LumenMosaic.metal` to palette-table lookup (no remaining LM.7 chromatic-projection / mean-shift / `kTintMagnitude` code on the LM.4.7 path).
- [ ] Track-change handler in `PhospheneApp/VisualizerEngine+Stems.swift` calls `LumenMosaicPaletteLibrary.selectPalette(...)` with the per-track mood, the previously drawn palette index, and the FNV-1a track-seed hash; pushes the result to `lumenEngine.setPalette(...)`; updates `lumenEngine.previousPaletteIndex`.
- [ ] `LumenPatternEngine` has a `previousPaletteIndex: Int?` property + `setPalette(_:)` method; both documented.
- [ ] `LumenPaletteSpectrumTests` rewritten covering: palette membership, per-song determinism, anti-repeat, mood-weighted distribution shape, pale-tone-share gate (≤ 0.30, all 18 palettes pass), track-change reproducibility. The LM.7 `test_achromaticAlignedSeed_doesNotWash` test is removed.
- [ ] `PresetRegressionTests` Lumen Mosaic golden hash regenerated and pinned to the new value; regression-harness fixture binds an explicit palette (preferred Autumnal); rationale documented.
- [ ] `PresetLoaderCompileFailureTest` passes (15 production presets — the shader did not silent-drop on the rewrite).
- [ ] `xcodebuild -scheme PhospheneApp -destination 'platform=macOS' build` clean.
- [ ] `swift test --package-path PhospheneEngine` full suite green.
- [ ] `swiftlint lint --strict --config .swiftlint.yml` — 0 violations on touched files.
- [ ] **Matt M7 review** on a real-music multi-track session, ≥ 6 tracks spanning mood quadrants. Verification surface:
  - Each track's drawn palette reads as its named character at the panel level (Cathedral Lights = stained-glass; Refn Glow = warm-neon-shadow; Glacier = frozen-blue-on-snow; Carnival = saturated festival; Rothko Chapel = oxblood meditation; etc.).
  - The palette change at each track boundary is **visible** — when the song shifts, the panel's colour vocabulary shifts.
  - Mood-bias direction feels right (low-arousal tracks pull toward Rothko Chapel / Tenebrism / Cathedral Lights register; high-arousal tracks pull toward Carnival / Holi register; etc.) without being deterministic.
  - The anti-repeat rule is visible on a contrived two-track stretch where the two tracks have very similar mood — they should pick two different palettes, not the same palette twice.
- [ ] BUG-014 flipped to **Resolved** in `docs/QUALITY/KNOWN_ISSUES.md` with the implementation commit hash.
- [ ] `docs/RELEASE_NOTES_DEV.md` entry added for LM.4.7.

---

## Verify

Run after each logical step and at the end:

```
swift test --package-path PhospheneEngine --filter "LumenPalette|LumenPatternEngine|PresetLoaderCompileFailure|PresetRegression|PresetAcceptance|FidelityRubric"

RENDER_VISUAL=1 swift test --package-path PhospheneEngine --filter PresetVisualReview
# Produces the contact sheet. Verify per-fixture that Lumen Mosaic renders are
# the new palette-driven character, not the old uniform-random-RGB character.

xcodebuild -scheme PhospheneApp -destination 'platform=macOS' build

swiftlint lint --strict --config .swiftlint.yml
```

The Matt-review session is the load-bearing final gate. No automated test substitutes for the per-palette character read on real music.

---

## Out of scope

Do NOT touch in this increment:

- **The LM.3.2 team/period beat-step ratchet.** Cells advance their palette index on rising-edge of their assigned band's beat (`lumen.bassCounter` / `lumen.midCounter` / `lumen.trebleCounter`). Preserved exactly.
- **LM.6 cell-depth gradient + optional hot-spot.** Downstream of `lm_cell_palette` in `sceneMaterial`. Preserved exactly.
- **Cell brightness logic** (`lm_cell_intensity`, `kCellBrightnessMin/Max`, bar pulse). Preserved exactly.
- **LM.3.1 agent-position-driven backlight character.** Already retired; do not resurrect.
- **The 4 `LumenLightAgent` slots** on the GPU buffer. ABI-only; agent intensity/colour fields stay unused.
- **The pattern engine** (`LumenPatterns.swift`). Already retired at LM.4.4; the `LumenPattern` GPU struct stays for ABI continuity.
- **`LumenMosaic.json` sidecar.** No changes to `family`, `passes`, `rubric_profile`, `certified`, `stem_affinity`. Cert stays at `true`.
- **`PresetSignaling`, Orchestrator scoring, `PresetScoringContext`.** The palette selection is internal to Lumen Mosaic; it does not interact with preset-vs-preset scoring.
- **Other presets.** This is a Lumen-Mosaic-only increment.
- **CLAUDE.md, DECISIONS.md, ENGINEERING_PLAN.md, KNOWN_ISSUES.md, SHADER_CRAFT.md, VISUAL_REFERENCES/lumen_mosaic/palette_library/**. The paperwork landed 2026-05-18 (commits `24b65125`..`120529cb`); the increment plan, decisions, design artifacts are stable. Read but do not edit unless an implementation discovery forces a documented amendment (in which case → stop and report per protocol).
- **`docs/presets/LUMEN_MOSAIC_DESIGN.md`** §3 Decisions D.4 / E.3 lines. They need rewriting to reflect the library architecture, but that is a separate documentation session, not this one. Reference D-LM-palette-library inline in your LumenMosaicPaletteLibrary.swift docstring; do not edit LUMEN_MOSAIC_DESIGN.md in this increment.

---

## Stop and report instead of forging ahead when

Per CLAUDE.md Increment Completion Protocol:

- Any test fails that wasn't already a documented flake.
- The pale-tone-share gate (≤ 0.30) fails for any of the 18 palettes — this means the hex values in the design artifacts differ from what passes the gate; investigate whether the conversion (sRGB hex → linear RGB) was applied correctly, then surface to Matt before adjusting any palette values.
- The mood-weighted distribution test fails its relative-ordering assertion — `σ` may need tuning, but file the data and surface before committing a value change.
- The byte-offset migration of `LumenPatternState` cascades into changes outside Lumen-Mosaic-owned files.
- The track-change site at `VisualizerEngine+Stems.swift:480` requires re-architecture to thread the prepared mood through.
- Matt's M7 review returns negative ("the palettes don't read as their names" / "mood-fit feels wrong" / "the per-song change isn't visible" / etc.). Do not iterate without re-scoping.

The cost of pausing to confirm is low. The cost of an increment that silently re-shapes scope is high.

---

## Commit cadence

Per CLAUDE.md commit-cadence rule: multiple small commits within the increment, message format `[LM.4.7] <component>: <description>`. Suggested commit boundaries:

1. `[LM.4.7] LumenMosaicPaletteLibrary: 18 palettes + selectPalette weighted draw`
2. `[LM.4.7] LumenPatternState: extend with 12-colour palette payload (slot 8)`
3. `[LM.4.7] LumenMosaic.metal: palette-table lookup replaces LM.4.6 hash→RGB`
4. `[LM.4.7] VisualizerEngine+Stems: per-song palette selection at track change`
5. `[LM.4.7] LumenPaletteSpectrumTests: rewrite for palette-library contract`
6. `[LM.4.7] PresetRegression: regen Lumen Mosaic golden hash (Autumnal fixture)`
7. `[LM.4.7] KNOWN_ISSUES + RELEASE_NOTES: close BUG-014`

Adjust boundaries based on how the work actually decomposes — but each commit should leave the repo in a buildable, testable state. Do not commit a half-broken shader; do not commit struct-size changes without the matching Swift and MSL updates in the same commit.

Push to remote only after Matt's explicit "yes, push" in chat. Local main commits stay local until then.

---

## Closeout report (at end of increment)

Per CLAUDE.md Increment Completion Protocol:

1. **Files changed** — concrete paths, new vs edited.
2. **Tests run** — suites, pass/fail counts, pre-existing flakes called out.
3. **Visual harness output** — contact-sheet PNG paths from `RENDER_VISUAL=1` runs. Optionally attach key frames.
4. **Documentation updates** — should be small in this increment (KNOWN_ISSUES.md BUG-014 closure + RELEASE_NOTES_DEV.md entry only).
5. **Capability registry updates** — `docs/ENGINE/RENDER_CAPABILITY_REGISTRY.md` if any GPU contract surface changed (preferred shape (a) above does not change the contract).
6. **Engineering plan updates** — flip Increment LM.4.7 status from ⏳ to ✅ in `docs/ENGINEERING_PLAN.md`.
7. **Known risks and follow-ups** — anything deferred (e.g. retiring the four `trackPaletteSeed` floats from `LumenPatternState` if you left them as dead weight).
8. **Git status** — branch, commit hashes, clean tree confirmation.

---

## Project context inherited from CLAUDE.md

Reinforcing rules that apply here even though they're not Lumen-Mosaic-specific:

- D-026: prefer deviation primitives (`bass_rel`, `bass_dev`) over absolute thresholds. Doesn't apply to palette selection (it's not audio-thresholding), but applies to any new audio-coupling you might be tempted to add — don't add any in this increment.
- Failed Approach #44: do not shadow Metal built-in type names (`half`, `ushort`, `uchar`, `packed_float3`) with local variable names. Silent shader drop, no stderr.
- Failed Approach #57: trigger conditions on real audio primitives, not on intuitive-sounding-but-acoustically-impossible combinations. Doesn't apply here directly but is the shape of bug to avoid when wiring the mood-input fallback.
- SwiftLint `file_length: 400` is relaxed for `.metal` files; do not split LumenMosaic.metal to fit the lint warning.
- Linear-RGB everywhere on the GPU side; sRGB-to-linear conversion happens at the palette-import boundary.
- `LumenPatternState` size changes ripple to `MemoryLayout` asserts in `CommonLayoutTest` (or equivalent). Update those in the same commit as the struct change.

---

## Why this matters

Lumen Mosaic is Phosphene's first certified preset and the load-bearing test case for the palette-driven preset architecture. Getting LM.4.7 right is also a forward investment — D-LM-palette-library and D-LM-cream-rescission establish the rules for any future palette-driven preset Phosphene ships, and the LM.9 pale-tone-share gate will be inherited by those presets' cert sweeps. Matt's *"I'm giving up the fight on colors"* verdict on LM.4.6 is the bar this increment has to clear — it should change to something like *"the palettes work."*

Treat the Matt M7 review as the load-bearing gate. Automated tests prove the pipeline is correct; they don't prove the palettes read as their names. Listen to real music; watch real panels; iterate on σ / moodAnchor values only after a real-music session, not before.
