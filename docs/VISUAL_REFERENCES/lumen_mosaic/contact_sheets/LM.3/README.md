# Lumen Mosaic — LM.3 Contact Sheet

Captured 2026-05-09 via `RENDER_VISUAL=1 swift test --package-path PhospheneEngine --filter "PresetVisualReview"`. First contact sheet under the LM.3 design pivot — per-cell colour identity from procedural palette + drop-the-cream-baseline + mood-driven palette parameters.

## What changed vs LM.2

LM.2 produced cream blobs because the cell-quantization sampled a smooth analytical light field (cells got nearly identical colours) and the mood-tint formula always pulled toward a cream baseline. LM.3 retired both:

1. **Cell colour now from a procedural palette keyed on cell hash + audio time + mood.** Each cell has its own deterministic colour from `palette()` — adjacent cells with adjacent hashes can land on opposite sides of the hue wheel. No smooth field, no near-identical neighbours.
2. **Cream baseline retired.** Palette parameters interpolate between cool/warm and subdued/vivid endpoints chosen to stay saturated even at low arousal.
3. **Cells cycle over `accumulated_audio_time`.** During energetic playback the per-cell palette phase advances and cells visibly cycle through hues. At silence the cycle freezes and cells hold their colours.
4. **Per-track palette seed.** Two tracks at the same mood get different palette character via a per-track perturbation derived from `hash(title + artist)`.

## Fixtures

| File | FeatureVector / state | What it verifies |
|---|---|---|
| `Lumen_Mosaic_silence.png` | All-zero FV, all-zero stems, no track seed | Cells visibly distinct, vivid colours at silence — D-019 silence fallback no longer collapses to cream. |
| `Lumen_Mosaic_mid.png` | bands @ 0.50, neutral mood | Same neutral palette at moderate energy. |
| `Lumen_Mosaic_beat.png` | bass=0.80, bassRel=0.60, bassDev=0.60, beatBass=1.0 | Drums + bass FV-fallback agents fire; cell intensity comes through. |
| `Lumen_Mosaic_hv_ha_mood.png` | bands @ 0.55, valence=+0.6, arousal=+0.6 | Palette character shifts warm — more pinks / oranges / yellows. |
| `Lumen_Mosaic_lv_la_mood.png` | bands @ 0.45, valence=−0.5, arousal=−0.4 | Palette character shifts cool — more cyans / teals / pale violets. |

## What the sheet now demonstrates

- **Cell quantization paints visibly.** Each cell carries its own colour. The smooth-blob LM.2 failure mode is gone.
- **Vivid throughout.** No cream haze, no pastel pull. Saturated channels at every fixture.
- **Mood-coupled palette character shift.** HV-HA frame leans warm / pink-orange; LV-LA frame leans cool / cyan-teal.
- **Silence stays vibrant.** The all-zero fixture produces a vivid coloured cell field, not a faded grey or cream.

## What it does not show (still deferred)

- **Per-track seed variation.** The harness doesn't call `setTrackSeed(_:)`, so all fixtures render at zero perturbation. Real session captures will show different palette character across tracks via the FNV-1a hash of `title + artist` wired in `VisualizerEngine+Stems.swift`.
- **Cells cycling through palette over time.** Single-frame stills can't show the time evolution. Real session captures across 5–10 second windows are the load-bearing review (the `kCellHueRate = 0.15` constant is the master tuning knob — full hue cycle every ~7 seconds of energetic music).
- **Production tone-mapping.** The harness still skips `PostProcessChain` (no bloom, no ACES), so the rendered PNGs are linear pre-tone-map values. Production with bloom + ACES will produce smoother highlight roll-off and visible bleed across cell ridges. The LM.2-era harness limitation about IBL is no longer load-bearing — the cells paint correctly without IBL because their colour comes from the palette, not from light-field sampling.

## Tuning knobs (M7 review surface)

The most likely things you'll want to dial:

- **`kCellHueRate` (LumenMosaic.metal:~115)** — how fast cells cycle through the palette during energetic music. Default 0.15 → ~7 s per full cycle. Increase if cycles feel too slow; decrease if cells feel busy / strobe-y.
- **`kSilenceIntensity` (LumenMosaic.metal:~107)** — silence floor brightness. Default 0.55. Raise to make silence brighter, lower for quieter rest.
- **`kPaletteACool / kPaletteAWarm / kPaletteBSubdued / kPaletteBVivid / kPaletteCUnison / kPaletteCOffset / kPaletteDComplementary / kPaletteDAnalogous`** — IQ palette endpoints. Tune individually for warmer / cooler / more contrasty / more analogous palette characters across the mood plane.
- **`kSeedMagnitudeA / B / C / D` (LumenMosaic.metal:~140)** — per-track perturbation magnitudes. Larger values → more visible track-to-track palette difference. Default conservative; expect to tune up if real-session captures don't feel distinct enough across tracks.
- **`kCellDensity` (LumenMosaic.metal:~80)** — cells across the panel. Default 30 → ~50 cells across the visible frame. Larger = smaller, more numerous cells.

## Real session review checklist

1. Play a varied playlist (energetic + ballad + instrumental) and confirm: each track has visibly different palette character.
2. Watch a single track for 30 seconds: cells should visibly cycle through hues during energetic passages, hold during silent / breakdown moments.
3. Force HV-HA and LV-LA tracks back-to-back: palette character should shift over the 5 s mood smoothing window.
4. Pause the music in the middle of a track: cells should freeze at their current colours, not fade to anything.
5. **Vivid throughout?** No frame should have a dominant cream / pastel ratio. If it does, escalate before LM.4.
