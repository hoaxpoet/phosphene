# Spectral Cartograph Overhaul — Handoff Prompt

Use this as the agent prompt for the next session. Self-contained: assumes no memory of prior context.

---

## Why this matters

Phosphene's beat-tracking pipeline (DSP.2 S7 + S8) just landed. To sign it off
rigorously we need a **diagnostic preset that visually shows ground truth
alongside the live signal**, so the user can verify beat-lock without
interpretation. Volumetric Lithograph and the other "aesthetic" presets are
load-bearing visual content but can't be used for sign-off — their visual
pulse density tracks broadband bass+drums energy, not the beat grid, so a
visible "lock" between visuals and music can't be distinguished from the
preset just looking the way it always does.

`SpectralCartograph` is the existing diagnostic preset. It already plots the
live `FeatureVector.beat_phase01` value as a scrolling trace in its
bottom-right (BR) panel. After this overhaul it will also (a) carry an
unambiguous centered "beat orb" that flashes white at each beat-phase
zero-crossing and (b) overlay vertical tick marks at the **cached BeatGrid's
beat timestamps** on the BR panel's `beat_phase01` trace — so the user can
see at a glance whether the trace's downward zero-crossings line up with
ground truth. They should. If they do, S7's `LiveBeatDriftTracker` is
delivering. If they slip, that's a regression to chase.

This is the canonical visual sign-off surface for any future audio-path
change. After it lands, the user re-records `docs/quality_reel.mp4` on a
Spotify Lossless playlist (Blue in Green / Love Rehab / Mountains / Pyramid
Song / Money) using Spectral Cartograph as the active preset, and S7+S8 are
fully ✅.

## What's already in place (HEAD `92aa3da1` on `origin/main`)

- DSP.2 S7 (`LiveBeatDriftTracker`) and S8 (BeatThisModel fixes) shipped.
  Numerical equivalence with PyTorch reference verified on `love_rehab.m4a`
  (max sigmoid 0.9999 vs ref 0.9999, 59 beats detected vs 59 in ground truth).
- `MIRPipeline.setBeatGrid(_:)` setter wires the cached `BeatGrid` from
  `StemCache` into `LiveBeatDriftTracker` on track change. Source of truth
  for "what beat times should the BR panel's tick marks land on."
- `BeatThisActivationDumper` CLI + `Scripts/dump_beatthis_activations.py`
  layer-diff harness shipped — not directly relevant here but useful if any
  numerical regression surfaces.
- `MIRPipeline.elapsedSeconds: Float` (track-relative since the existing
  `mir.reset()` on track change in `VisualizerEngine+Capture.swift:127`) is
  the playback clock available to the shader.
- `SpectralHistoryBuffer` at `buffer(5)` already carries 480-sample trails
  for `valence`, `arousal`, `beat_phase01`, `bass_dev`, `vocals_pitch_norm`
  + write head + samples_valid (16 KB UMA Float32). Add to it; don't replace.
- `PhospheneEngine/Sources/Presets/Shaders/SpectralCartograph.metal` is the
  preset source. 278 lines, well-structured, four `drawXxx` helpers + entry
  point. Read it first.

## What to build

### Layout

Same 4-panel grid (TL/TR/BL/BR) as today, but each panel gains a top header
strip and the four panels visually share a centered orb overlaid across
their intersection.

**Panel headers** (white text, ~10 % of panel height, top-aligned):

- TL: `FFT SPECTRUM`
- TR: `BAND DEVIATION`
- BL: `VALENCE / AROUSAL`
- BR: `BEAT PHASE / BASS DEV / PITCH`

**Centered beat orb**: at viewport `(0.5, 0.5)`, radius 0.22 in screen-height
units. Fill brightness driven by `pow(1.0 - beat_phase01, 3.0)` — bright at
beat onset, fades through the cycle. Plus a **sharp white ring flash** when
`beat_phase01 < 0.04` (unmistakable sub-frame "this is the beat" visual).
Color: amber, matching the existing `kBeatPhaseClr` constant
`float3(1.0, 0.784, 0.341)`.

**Above the orb**: small BPM number from cached `BeatGrid.bpm` (or "—" in
reactive mode where no grid is installed). **Below the orb**: lock state
text — `UNLOCKED` / `LOCKING` / `LOCKED` — from
`LiveBeatDriftTracker.LockState`.

**Orb does NOT cut into panels.** Panels render normally; the orb draws on
top of the 4-corner intersection, which is mostly background-colored
already. No carving / no masking — keep it simple.

### Procedural bitmap font

No font-atlas textures, no bundle resources, no string parsing at runtime.
3×5 capital alphabet plus space, `/`, `•`, `:`, `-`, digits 0–9. ~40 glyphs
total. Encode each as a `uint16` constant (15 bits used, one bit per pixel,
row-major). Total constant data ≈ 80 bytes.

```c
// Example (this is the letter F):
//   ███
//   █..
//   ██.
//   █..
//   █..
constant uint16_t glyph_F = 0b111100100110100100;  // row-major 3×5, lower 15 bits
```

Implement two helpers in `SpectralCartograph.metal`:

```c
// Returns whether the given pixel (in glyph-local UV) is "on" for this glyph.
bool glyphPixel(uint16_t glyph, int x, int y);   // x in [0..2], y in [0..4]

// Draws one character at panel-local origin with given scale and color.
// Composites onto outColor in-place (or returns the character's contribution
// as a float [0,1] and lets the caller composite).
float drawCharAt(float2 uv, uint16_t glyph, float2 origin, float scale);
```

Each panel header is then a hardcoded sequence:

```c
static inline float3 drawHeaderTL(float2 uv) {
    float a = 0.0;
    float2 origin = float2(kHeaderPad, kHeaderTop);
    a = max(a, drawCharAt(uv, glyph_F, origin + float2(0 * kCharStride, 0), kCharScale));
    a = max(a, drawCharAt(uv, glyph_F, origin + float2(1 * kCharStride, 0), kCharScale));
    a = max(a, drawCharAt(uv, glyph_T, origin + float2(2 * kCharStride, 0), kCharScale));
    // … space, then SPECTRUM …
    return float3(a) * kHeaderColor;  // white text
}
```

Verbose but readable. Inline all 4 headers. ~150 lines total.

### BR panel: cached-grid tick overlay

The load-bearing methodological piece. Today the BR panel's top sub-row
(when `uv.y < 1/3`) shows the live `beat_phase01` trace; the trace ramps
0→1 across each beat. After this overhaul, the same row also draws **thin
vertical white ticks at the cached BeatGrid's beat timestamps within the
visible 8-second window**. If S7's drift tracker is locked, the trace's
downward zero-crossings (where it snaps from ≈1 back to 0 at a new beat)
land on the ticks. If not, they slip.

Wiring required (Swift side):

1. Add a small UMA buffer carrying the `relativeBeatTimes` for the next ≈16
   cached beats (8 s window × max ~2 BPS = 16 beats). Each entry is the
   beat's time relative to the current playback head, in seconds. Negative
   = beat already passed (still draw if within visible window). The shader
   maps these to UV-x positions via the same age-mapping the trace already
   uses (`x = 1 - age / kHistLen`).
2. Update the buffer once per frame from
   `MIRPipeline.elapsedSeconds + LiveBeatDriftTracker.drift` against
   `BeatGrid.beats`. Either extend `SpectralHistoryBuffer` (preferred — it's
   already at `buffer(5)` and is a SC-only consumer), or add a new
   `buffer(7)` binding. Pick the cleaner option after reading
   `SpectralHistoryBuffer.swift`.
3. Reset the buffer on track change (`SpectralHistoryBuffer.reset()` is
   already called there; add the new field to that reset).
4. When no `BeatGrid` is installed (reactive mode → no grid yet, or
   `LiveBeatDriftTracker.hasGrid == false`), fill with a sentinel value
   (e.g. `Float.infinity`) so the shader skips drawing ticks.

Shader-side: in `drawFeatureGraphs` (the BR panel function), when on the
`beat_phase01` row (`row == 0`), iterate over the relativeBeatTimes,
convert each to a UV-x position, and add a thin vertical white line where
`abs(uv.x - tickX) < 0.002` — gated on the time falling within the visible
window. Don't overwrite the trace; max-blend so both are visible.

### Centered orb

Five ingredients:

1. **Background disc**: `length(uv - 0.5) < kOrbRadius` — fills with `kOrbBg`
   (very dark, e.g. `float3(0.04)`).
2. **Filled core**: same disc, brightness `pow(1.0 - beat_phase01, 3.0)`,
   tinted amber. Drawn on top of background.
3. **Beat ring**: stroke at `length(uv - 0.5) ≈ kOrbRadius`, width ~0.005.
   Stroke alpha = `smoothstep(0.04, 0.0, beat_phase01)` — full white during
   the brief sub-0.04 window at beat onset.
4. **BPM text** above orb (centered, ~3 chars tall, slightly above
   the orb's top edge): the BPM rounded to integer. Use the new font.
   Source: a new field in `FeatureVector` carrying current BPM, OR add it
   to `SpectralHistoryBuffer`'s last-2-slot scalar area. Pick whichever is
   cleaner.
5. **Lock state text** below orb (centered): `UNLOCKED` / `LOCKING` /
   `LOCKED`. Source: a small enum int, same plumbing as BPM.

The orb draws AFTER the panel content in the fragment, so it overlays on
top of any panel pixels at the 4-corner intersection. Panels still render
normally — the orb just paints over the small overlap region.

## Files to touch

- `PhospheneEngine/Sources/Presets/Shaders/SpectralCartograph.metal` — main
  work. ~300 new lines added on top of the existing 278.
- `PhospheneEngine/Sources/Shared/SpectralHistoryBuffer.swift` — extend
  with cached-grid relativeBeatTimes ring (16 entries) + BPM scalar + lock
  state scalar. Update `reset()` to clear them. Update the slot-offset
  constants used by SC.
- `PhospheneApp/VisualizerEngine+Audio.swift` (or a new helper called from
  the analysis queue): per-frame, recompute relativeBeatTimes from
  `mir.liveDriftTracker` + `mir.elapsedSeconds` + cached `BeatGrid` and
  write into the SpectralHistoryBuffer. Skip cleanly when grid is empty.
- `PhospheneApp/VisualizerEngine+Stems.swift` already calls
  `mirPipeline.setBeatGrid(...)` on track change — make sure the
  SpectralHistoryBuffer is also reset to drop stale ticks.
- `CLAUDE.md` — update the SpectralCartograph file descriptor in the Module
  Map. Document the new orb + tick overlay + per-panel labels. Adjust
  `buffer(5)` documentation if the layout shifts (or add `buffer(7)` if you
  go that route).

## Done-when

- [ ] Spectral Cartograph renders four panels each with a clear white
      header label.
- [ ] Centered amber orb pulses on every audible beat during a Spotify
      session. Bright fill + white ring flash visible at each kick.
- [ ] BPM number above orb shows non-zero value during playback (matches
      cached BeatGrid, e.g. ~125 for Love Rehab).
- [ ] Lock state below orb reaches `LOCKED` within the first 4–5 beats of
      a track and stays there.
- [ ] BR panel's `beat_phase01` trace shows vertical white ticks at the
      cached BeatGrid's beat positions; downward zero-crossings of the
      trace land on the ticks within visual tolerance (~1 frame).
- [ ] In reactive mode (no Spotify connection / ad-hoc playback), orb
      still pulses (driven by `BeatPredictor` fallback) but BR ticks are
      hidden because no cached grid.
- [ ] `swift test --filter SpectralCartograph` golden hash regen if the
      regression test fixture compares the rendered output. (Look for
      `goldenPresetHashes` in
      `Tests/.../Renderer/PresetRegressionTests.swift` — Spectral
      Cartograph's hash will need updating after this redesign.)
- [ ] `xcodebuild -scheme PhospheneApp build` clean.
- [ ] `swiftlint --strict` clean on touched files.
- [ ] CLAUDE.md Module Map updated.
- [ ] Visual review via `RENDER_VISUAL=1 swift test --filter
      PresetVisualReview` produces sensible PNGs at
      `/tmp/phosphene_visual/<ISO8601>/SpectralCartograph_*.png` (the
      preset is already in the args list per commit `c82e9218`'s S7c
      change).

## What NOT to do

- Don't introduce a font-texture-atlas resource. Procedural 3×5 bitmap
  font keeps the shader self-contained and avoids new bundle assets.
- Don't break the existing `buffer(5)` SpectralHistoryBuffer schema in a
  way that requires touching every other consumer. Either append to it
  cleanly (adding new offset constants, leaving existing ones intact) or
  introduce `buffer(7)` for the new payload.
- Don't carve panel content around the orb. The corner intersection is
  empty enough that orb-on-top is fine and far simpler.
- Don't make the orb size configurable via JSON yet. Lock to 0.22 radius
  for the first cut; we can promote to a tunable later if it doesn't
  read well at the user's resolution.
- Don't lift `withKnownIssue` on any test that wasn't passing before this
  starts. If you find a related test that was previously a lie, surface it
  separately.
- Don't use VL or any other "aesthetic" preset for sign-off after this
  lands. Spectral Cartograph IS the sign-off surface from now on.

## Reference: current SC structure

Read these files first:

- `PhospheneEngine/Sources/Presets/Shaders/SpectralCartograph.metal`
  (278 lines — the preset itself, current state)
- `PhospheneEngine/Sources/Shared/SpectralHistoryBuffer.swift`
  (the buffer at `buffer(5)`, 16 KB UMA Float32, currently 5 trails of 480
  samples + 2 scalar slots)
- `PhospheneEngine/Sources/DSP/LiveBeatDriftTracker.swift`
  (`LockState` enum lives here; `update(...)` returns
  `Result(beatPhase01, beatsUntilNext, barPhase01, lockState)`)
- `PhospheneEngine/Sources/DSP/BeatGrid.swift`
  (`beats: [Double]`, `bpm: Double`, `beatsPerBar: Int` — what to consume
  for the tick overlay)

Buffer bindings (don't break these):

```
buffer(0) = FeatureVector (192 bytes, 48 floats)
buffer(1) = FFT magnitudes (512 floats)
buffer(2) = waveform (1024 floats — bound but unused by SC v1)
buffer(3) = StemFeatures (256 bytes)
buffer(5) = SpectralHistory (16 KB UMA)
            [0..479]    valence trail
            [480..959]  arousal trail
            [960..1439] beat_phase01 history
            [1440..1919] bass_dev history
            [1920..2399] vocals_pitch_norm history
            [2400] write_head
            [2401] samples_valid
            [2402..]     ← new payload goes here OR new buffer(7)
```

## Estimated scope

Three files touched, ~400 lines added (300 MSL + ~50 Swift + ~50 docs).
About 2-3 hours of focused work. The procedural font is the slowest part
because each glyph is hand-encoded as a uint16. Suggest writing 2–3 glyphs
first, verifying alignment via `RENDER_VISUAL=1`, then mass-producing the
rest. Don't write all 40 glyphs blind.

## Commit shape

Three commits in order:

1. `[SC] Add procedural 3×5 bitmap font + per-panel labels`
2. `[SC] Add centered beat orb + BPM/lock-state readouts`
3. `[SC] Overlay cached-BeatGrid ticks on BR beat_phase01 trace; wire
    relativeBeatTimes through SpectralHistoryBuffer`

Three small commits give `git bisect` traction if any visual regression
surfaces.

## After it lands

User re-records `docs/quality_reel.mp4` on a Spotify Lossless playlist with
Pyramid Song + Money appended, using Spectral Cartograph as the active
preset throughout (or at least during the irregular-meter sections). The
reactivity ratio in `QualityReelAnalyzer`'s output report becomes a
secondary signal — the primary signal is the orb flash landing on audible
kicks AND the BR-panel trace's zero-crossings landing on the cached-grid
ticks. Both being unambiguously yes → S7 + S8 fully ✅.
