# Lumen Mosaic — LM.3.2 Contact Sheet

Captured 2026-05-09 (LM.3.2 calibrated build) via `RENDER_VISUAL=1 swift test --package-path PhospheneEngine --filter "PresetVisualReviewTests/renderPresetVisualReview"`.

**Calibration follow-up applied 2026-05-09 after Matt's first review of LM.3.2:** the original LM.3.2 contact sheet showed every fixture looking the same. Two fixes:

1. **Cell density `kCellDensity` 30 → 15** (~60 cells across visible frame → ~30 cells across). Matt 2026-05-09: "the camera can zoom in a little, 50 → 30 cells across". Each cell now reads as a discrete stained-glass tile rather than confetti.
2. **Palette endpoints widened so HV-HA and LV-LA produce genuinely different palettes**, not just permutations of the same colour wheel. The original LM.3 endpoints (`kPaletteACool = (0.50, 0.50, 0.55)`, `kPaletteAWarm = (0.55, 0.45, 0.45)` — diff ≤ 0.10 per channel) only rotated which cell got which colour, not which colours appeared. New endpoints:
   - `kPaletteACool = (0.25, 0.50, 0.75)` — strong blue base
   - `kPaletteAWarm = (0.75, 0.50, 0.25)` — strong red base
   - `kPaletteBVivid = (0.65, 0.65, 0.65)` — pushed past LM.3's 0.55 to avoid pastel midpoints
   - `kPaletteBSubdued = (0.40, 0.45, 0.55)` — saturated even at low arousal
   - `kPaletteDComplementary = (0.00, 0.50, 1.00)` — wide phase spread
   - `kPaletteDAnalogous = (0.00, 0.05, 0.15)` — narrow → analogous

Net result on the contact sheet: HV-HA reads warm (yellow / orange / magenta / red dominant); LV-LA reads cool (cyan / teal / green / pink dominant); silence + mid + beat at neutral mood show the balanced rainbow palette.

LM.3.2 supersedes LM.3 + LM.3.1. Both prior approaches were rejected after live-session capture against real audio:

- **LM.3** (continuous palette cycling driven by `accumulated_audio_time`) — cells did not visibly cycle in production. Spotify's volume normalisation pulls mid + treble bands toward zero (BUG-012); `accumulated_audio_time` advanced ~0.045 / sec instead of the expected ~0.5 / sec, so `accumulated_audio_time × kCellHueRate` was effectively static for entire songs.
- **LM.3.1** (agent-position-driven static-light field as backlight character) — Matt's 2026-05-09 review: "fixed-color cells with brightness modulation; the bright pools dominated the visual story." The four agent positions painted four bright lobes that read as the visual subject; the cells underneath felt static.

LM.3.2 fully replaces both with a **band-routed beat-driven dance**: cells advance their palette index discretely on each beat, with the band (bass / mid / treble) chosen per-cell by hash. Brightness is uniform across the panel — the visual story is colour change, not brightness change.

## Architecture (LM.3.2 / Decision D.5)

Each cell hashes `cell_id ^ trackSeedHash` and falls into one of four teams:

| Team | Share | Counter | Behaviour |
|---|---|---|---|
| Bass | 30 % | `lumen.bassCounter` (rising-edge of `f.beatBass`) | advances palette step on each bass beat |
| Mid | 35 % | `lumen.midCounter` (rising-edge of `f.beatMid`) | advances palette step on each mid beat — the typical melody carrier |
| Treble | 25 % | `lumen.trebleCounter` (rising-edge of `f.beatTreble`) | advances palette step on each treble beat |
| Static | 10 % | none | holds its base palette colour for the whole track; rotated per-track via XOR with the track-seed hash |

Each cell also draws a `period ∈ {1, 2, 4, 8}` from another hash bucket (Pareto: ≈37.5 % period 1, 25 % period 2, 25 % period 4, 12.5 % period 8). The shader does `step = floor(team_counter / period)`. Fast cells (period 1) advance every team beat; slow cells (period 8) hold their step for many beats. Aggregate density target ~50–60 % of cells visibly stepping in any given second of energetic music.

`barCounter` advances on `f.barPhase01` wrap (every downbeat) or every 4 bass beats when no BeatGrid is installed. The current build does not yet route `barCounter` directly into the shader — the bar pulse uses `f.bar_phase01 ^ 8` for a smooth +30 % brightness flash at the very end of each bar, collapsing to a no-op when no grid is present.

Brightness is uniform with hash jitter: `intensity = 0.85 + 0.15 × (hash >> 16 & 0xFF) / 255`. The four LumenLightAgent positions / intensities are still ticked CPU-side for ABI continuity but unused by the shader.

## Fixtures

| File | FeatureVector / state | What it verifies |
|---|---|---|
| `Lumen_Mosaic_silence.png` | All-zero FV, all-zero stems, no track seed, no rising edges | Cells visibly distinct + vivid + uniform brightness — silence rests with each cell on its base palette colour. |
| `Lumen_Mosaic_mid.png` | bands @ 0.50, neutral mood, no rising edges | Same neutral palette at moderate energy (no rising edges in steady FV → no step advance). |
| `Lumen_Mosaic_beat.png` | bass=0.80, bassRel=0.60, bassDev=0.60, beatBass=1.0 | Bass-team cells (~30 % of panel) advance one palette step on the rising-edge of `f.beatBass`. Mid + treble teams hold. |
| `Lumen_Mosaic_hv_ha_mood.png` | bands @ 0.55, valence=+0.6, arousal=+0.6 | Palette character shifts warm — more pinks / oranges / yellows; per-cell identities preserved. |
| `Lumen_Mosaic_lv_la_mood.png` | bands @ 0.45, valence=−0.5, arousal=−0.4 | Palette character shifts cool — more cyans / teals / pale violets. |

## What the sheet now demonstrates

- **Vivid uniformly-bright panel.** Cells carry distinct colours; brightness is flat across the panel (hash jitter is small). The LM.3.1 spotlit-blob failure mode is gone.
- **Mood-coupled palette character shift.** HV-HA frame leans warm; LV-LA frame leans cool. Per-cell identities preserved across both moods (you can identify "the same cell" in both fixtures by its position).
- **Beat-driven step at first bass-rising-edge.** The `beat` fixture differs from `mid`: ~30 % of cells (the bass team) have advanced one palette step. The other ~70 % (mid + treble + static teams) are unchanged from the `mid` fixture.

## What single-frame stills cannot show

The dance is fundamentally a *time* phenomenon — the contact sheet can only confirm correct hash assignment + correct one-step advance. The load-bearing review is real-session capture across multi-second windows.

- **Cells advancing on each successive beat.** Need a video of a 4–8 second clip on a steady-tempo track (Love Rehab @ 125 BPM ideal) to verify ~3–5 cell-team advances per second feel right.
- **50–60 % cells changing per second target.** Three teams firing at independent beats (bass / mid / treble may not all align) plus Pareto-distributed periods means the *aggregate* dance density is the metric Matt cares about. Verify against a real-music capture.
- **Per-track seed differentiation.** The harness doesn't call `setTrackSeed(_:)`. Verify in production: track 1 vs. track 2 should look visibly different even at identical mood (the seeds shift palette parameters by ±0.20–0.50 — bumped from LM.3's ±0.05–0.20).
- **Bar pulse.** The +30 % brightness flash at end-of-bar requires a non-zero `f.bar_phase01`. Test fixtures pass 0; production sessions with installed BeatGrid will show the pulse.

## Tuning knobs (M7 review surface)

- **`kPaletteStepSize` (LumenMosaic.metal:~165)** — palette advance per team-counter step. Default 0.137 (≈ 1/φ²) — adjacent steps land far apart on the palette wheel. Decrease for subtler step-to-step transitions; increase for harsher jumps.
- **`kBarPulseMagnitude` (LumenMosaic.metal:~155)** — bar-pulse brightness boost. Default 0.30. Lower for subtler downbeat emphasis.
- **`kBarPulseShape` (LumenMosaic.metal:~156)** — bar-pulse curve sharpness. Default 8.0 — only the last ~8 % of the bar phase visibly flashes.
- **`kBassTeamCutoff / kMidTeamCutoff / kTrebleTeamCutoff` (LumenMosaic.metal:~170)** — team distribution percentages. Default 30 / 65 / 90. Adjust to bias the dance toward a particular band (e.g. raise mid cutoff for melody-led tracks).
- **`beatTriggerHigh` / `beatDebounceSeconds` (LumenPatternEngine.swift:~440)** — rising-edge threshold + debounce. Defaults 0.5 / 0.08 s.
- **`kSeedMagnitudeA / B / C / D` (LumenMosaic.metal:~195)** — per-track palette perturbation magnitudes. LM.3.2 bumped these from LM.3 (was 0.05 / 0.05 / 0.10 / 0.20; now 0.20 / 0.20 / 0.30 / 0.50). If track-to-track variation is still subtle in real captures, push the `D` magnitude higher (0.50 → 0.65).
- **`kCellIntensityBase / Jitter` (LumenMosaic.metal:~145)** — uniform-brightness baseline + hash jitter. Default 0.85 / 0.15 → cells span [0.85, 1.00]. Reduce jitter to 0 for perfectly flat brightness; raise to spread further.

## Real session review checklist

1. Play a varied playlist (energetic + ballad + instrumental). Each track should have visibly different palette character.
2. Watch a single track for 8 seconds during a steady passage: count cell colour changes per second. ~50–60 % of cells should change at least once during the 8-second window. If the dance feels muddy / chaotic, lower the team cutoffs (move more cells to "static"). If it feels too sparse, lower periods (cap to 4 instead of 8).
3. Force a kick-heavy track: bass-team cells should advance most prominently. Force a melody-led track (typical pop): mid-team cells should advance most prominently.
4. Force HV-HA and LV-LA tracks back-to-back: palette character should shift over the 5 s mood smoothing window. Per-cell *positions* identifiable across both tracks (same Voronoi seed).
5. Pause the music in the middle of a track: cells should freeze at their current step (counters stop advancing because no rising edges arrive).
6. **Vivid throughout?** No frame should have a dominant cream / pastel ratio. If it does, escalate before LM.4.
