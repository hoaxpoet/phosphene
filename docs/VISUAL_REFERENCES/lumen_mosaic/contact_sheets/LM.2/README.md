# Lumen Mosaic — LM.2 Contact Sheet

Captured 2026-05-09 via `RENDER_VISUAL=1 swift test --package-path PhospheneEngine --filter "PresetVisualReview"`. Output is from
`PresetVisualReviewTests.renderPresetVisualReview` with `LumenPatternEngine`
wired into the deferred ray-march path at fragment slot 8 (LM.2 task 8).

## Fixtures

| File | FeatureVector | What it verifies |
|---|---|---|
| `Lumen_Mosaic_silence.png` | All-zero FV, all-zero stems | D-019 silence fallback — non-black, mood-tinted ambient cream. |
| `Lumen_Mosaic_mid.png` | bands @ 0.50, neutral mood | All four agents on the 0.5-band FV fallback path, no warm/cool mood bias. |
| `Lumen_Mosaic_beat.png` | bass=0.80, bassRel=0.60, bassDev=0.60, beatBass=1.0 | Drums + bass FV-fallback agents fire; brightest contribution shifts toward drums (upper-left) + bass (centre-low). |
| `Lumen_Mosaic_hv_ha_mood.png` | bands @ 0.55, valence=+0.6, arousal=+0.6 | Warm-shifted palette (Decision E.1); arousal saturates the warm/cool axis. |
| `Lumen_Mosaic_lv_la_mood.png` | bands @ 0.45, valence=−0.5, arousal=−0.4 | Cool-shifted palette; pair with HV-HA to verify visible mood difference. |

The harness pre-warms `LumenPatternEngine` per fixture: one tick at `dt=5.0`
saturates the 5 s low-pass on valence/arousal in a single step, then 30 ticks
at `dt=1/60` advance the drift Lissajous to a representative phase.

## Known harness limitations

- **No IBL bound** (`iblManager: nil` in `renderDeferredRayMarchFrame`). The
  `matID == 1` lighting path normally adds `irradiance × kLumenIBLFloor (0.05)
  × ao` on top of `albedo × kLumenEmissionGain (4.0)`. Without IBL the
  irradiance sample reads as zero, so the per-cell relief + frost normal
  perturbation in the G-buffer doesn't translate into visible per-cell
  luminance — adjacent cells produce identical lit colour. **The cell
  quantization is still present in the G-buffer**, it's just not rendered
  visibly until production binds the IBL textures or LM.4 pattern bursts
  introduce high-frequency spatial content that interacts with cell
  boundaries.
- **No bloom + no ACES**. The harness skips `PostProcessChain`. The 4×
  emission gain pushes the central bright spot near 1.0 in linear space —
  bloom would normally bleed it across cell ridges and ACES would tone-map
  the highlight roll-off. The harness output is therefore a useful
  programmatic check for "agents on / mood applied" but not the final
  shipped look.
- **No noise textures bound**. Doesn't matter for `matID == 1` (the
  emission path doesn't sample noise).

## What the sheet does demonstrate

- Silence is non-black and mood-tinted (D-019 ✓).
- Mood-coupled palette shift between HV-HA and LV-LA is visible (Decision
  E.1 ✓).
- Beat fixture reads as brighter than mid/silence with the bright region
  weighted toward drums + bass agent positions (audio routing wired).
- The 4-light analytical sum at slot 8 is reaching the GPU and modulating
  albedo per fixture (slot 8 binding ✓).

## What it doesn't demonstrate (deferred)

- **Cell quantization** is invisible without IBL — confirm in production via
  `RENDER_VISUAL=1` against a real session, or wait until LM.4 pattern
  bursts make per-cell variation legible.
- **Beat-locked dance motion** — single-frame stills can't capture the
  figure-8 trajectory. The `LumenPatternEngineTests` `Beat-locked dance`
  suite verifies the motion math; M7 review needs a 16 s capture against a
  known-BPM track to confirm peak-on-beat readability.
- **Final tone-mapped + bloomed look** — needs production app run, not
  harness.

## M7 review checklist (for Matt)

1. Open a real session with Lumen Mosaic forced via `⌘[` / `⌘]` cycling.
2. Verify silence fallback at session start (panel non-black, mood-tinted).
3. Watch a HV-HA-mood track (e.g. an upbeat electronic mix) and confirm
   warm palette shift over ~5 s smoothing window.
4. Watch a LV-LA-mood track (e.g. slow ballad) and confirm cool palette
   shift.
5. **The dance**: play the 120 BPM calibration track, record a 16 s capture,
   confirm visible peak-on-beat agent motion.
6. Performance: `dashboard PERF card` shows `recentMaxFrameMs ≤ 14 ms`,
   QUALITY row hidden (governor in `full`).

If any of items 2 / 3 / 4 / 5 fail in production, escalate before LM.3.
