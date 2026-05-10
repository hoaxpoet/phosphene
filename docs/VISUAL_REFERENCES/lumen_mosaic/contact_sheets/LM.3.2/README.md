# Lumen Mosaic — LM.3.2 Contact Sheet ✅ M7 PASS

**Status: ✅ M7 PASS 2026-05-10** — real-music session `2026-05-10T15-44-27Z`. Matt 2026-05-10: "Awesome. Finally. The movement of the color in the cells is looking good. I'd like to see more color variation track to track, but this can be adjusted later. I'd consider this a 'pass.'"

**Carry-forward (2026-05-10)**: track-to-track colour variation could be wider. Tuning levers: `kSeedMagnitudeD` 0.50 → 0.65 (per-track phase-rotation magnitude); `kSeedMagnitudeA` 0.20 → 0.30 (per-track hue-shift magnitude); `moodHueSpread` 0.40 → 0.55 (cell-to-cell hue spread within a track). Scheduled for LM.6 fidelity polish or earlier as a tuning pass — see `docs/ENGINEERING_PLAN.md` LM.3.2 Carry-forward section.

---

Captured 2026-05-10 (LM.3.2 calibration round 8 — beat envelope removed) via `RENDER_VISUAL=1 swift test --package-path PhospheneEngine --filter "PresetVisualReviewTests/renderPresetVisualReview"`.

**Round 8 (2026-05-10) — beat envelope removed.** Real-music session review (Matt 2026-05-10, session `2026-05-10T14-48-52Z`): "the 'pulse off' state... happens more frequently than I would expect, in the spaces between beats. I think this state is unnecessary. I would rather the 'pulse off' state be the previous state before the next beat." Round 6 dimmed cells between beats to produce a "fade in / fade out like a light turning on/off" cycle; in production the dark gap between beats was visually dominant rather than rhythmic. Round 8 removes the envelope entirely — cells hold their previous state until the next beat advances the palette step. The per-beat colour change is the only rhythm-coupled visual signal, plus the bar-pulse +30 % brightness flash on each downbeat (preserved). The `lm_cell_envelope` helper and `kBeatDecayEnd / kBeatAttackStart` constants are deleted; the `pulse_off` / `pulse_anticipate` demo fixtures are retired.

**Round 7 (2026-05-10) — frost diffusion in sceneMaterial.** Matt's review of round 6: "Why is there a dot in every colored cell? This looks odd. Also the colors in v2 and v3 look particularly washed out — too much frosting?" Two diagnoses:

1. **Dots in every cell**: round 5/6 drove frost scatter from the SDF relief geometry's central-differences normal. The relief produced sub-pixel normal noise (Voronoi f1/f2 transitions, fbm8 frost peaks, rgba8Snorm normal quantization) that the normal-driven frost-scatter term amplified into per-pixel white spots. The procedural sparkle hash at scale 80 also aliased with the cell scale (cells ~36 px wide at 1080p, hash period ~13 px → ~3 sparkles per cell at fixed offsets).
2. **v2 / v3 washed**: the round-5 `frostiness × 1.5` saturated quickly so any normal deviation pulled cells toward white, and the `edgeSheen × 0.40` rim added more white at cell edges. Combined, the average panel saturation dropped — most visible at v2 / v3.

Round 7 fixes:

- **`kReliefAmplitude = 0` and `kFrostAmplitude = 0`** in LumenMosaic.metal sceneSDF — the panel's geometric normal is now a clean flat `(0, 0, -1)` per pixel; no more sub-pixel relief noise.
- **Frost diffusion moved to sceneMaterial**, driven by the Voronoi `f2 - f1` cell-edge distance (a large-scale, smooth signal) rather than by the normal. `frostiness = 1 - smoothstep(0, kFrostBlendWidth = 0.04, f2 - f1)`. Mixed into albedo via `mix(cell_hue, white, frostiness × kFrostStrength = 0.60)`. Cell centres stay fully vivid, cell boundaries get a clean white halo. **No per-pixel dots**.
- **matID == 1 lighting path simplified back to round-4 baseline**: `albedo × kLumenEmissionGain + ambient`. Frost scatter, procedural sparkle, and Fresnel edge sheen are removed (they were the dot sources, and with a flat normal the Fresnel/normal-driven terms collapse to zero anyway). The frosted-glass character is fully baked into albedo by sceneMaterial.

**Round 6 (2026-05-10) — beat envelope.** Matt's review of round 5: "the colors turn on and off, which means they quickly fade in and fade out, like a light being turned on and off. So the 'on' must be triggered milliseconds before the beat in order for the color to land on the beat." Round 5 was rendering cells at static brightness — the discrete palette-step advance was correct, but the colours snapped instantly rather than fading like a light bulb being switched on/off. Round 6 wires `f.beat_phase01` into a per-cell envelope that fades cells in toward the beat (anticipation window) and out after, with **75 ms anticipation lead-in at 120 BPM** so the colour visibly lands ON the beat rather than after.

Envelope shape: `max(post-beat decay, anticipation fade-in)`:
- phase ∈ `[0, 0.20]` → fade out (1.0 → 0.0)
- phase ∈ `(0.20, 0.85)` → dark (0.0)
- phase ∈ `[0.85, 1.0]` → fade in (0.0 → 1.0); peak at phase wrap = beat moment

Static-team cells (10 % of panel) skip the envelope and hold at peak brightness — the always-on visual anchor that keeps the panel from going fully dark between beats. Frost sparkle stays constant across the cycle (correct — frost is the surface character of the glass itself, independent of the backlight). Two new fixtures `pulse_off` (phase = 0.5) and `pulse_anticipate` (phase = 0.92) demonstrate the cycle.

**Round 5 (2026-05-10) — frosted-glass surface character.** Matt's review of round 4: "Remember that the glass itself is frosted, so any colors, even fully saturated ones, will appear 'frosted.' And I would ultimately like the surface of the glass to be more photorealistic." Round 4 was rendering cells as flat painted polygons — the matID == 1 path returned `albedo × emission_gain + ambient` with no surface lighting. Round 5 adds three surface terms on top of the saturated HSV emission so the panel reads as actual frosted stained glass:

1. **Frost scatter** — at cell ridges where the SDF relief gradient is steep, the G-buffer normal tilts strongly away from camera-flat. Albedo mixes with white proportional to `1 - NdotV` so cell centres stay vivid (flat normal → 100 % saturated colour) while cell edges bleed toward white (steep normal → frost diffusion). This is the "fully saturated colours appear frosted" cue.
2. **Procedural sparkle** — hash-driven white pinpoints distributed across the panel surface, *independent of light direction*. Real frosted glass scatters AMBIENT light off thousands of fine surface irregularities rather than reflecting a point source, so a directional Cook-Torrance specular would produce a bright hotspot wherever the camera-light reflection lands (round 5 v1 had this — `D ≈ 39` at `NdotH = 1` with roughness 0.30). The hash-field replacement is uniform across the panel.
3. **Fresnel edge sheen** — Schlick rim at oblique normals (cell-ridge silhouettes), white-tinted, exponent 3 for soft frost-glass falloff (vs. exponent 5 for sharp dielectric).

**Round 4 (2026-05-10) — HSV palette + reduced emission gain.** Matt's review of round 3 output: "Why predominantly pastels?" Diagnosis: the V.3 IQ cosine palette form `palette(t, a, b, c, d) = a + b * cos(2π * (c*t + d))` is structurally pastel-prone — with `a ≈ 0.5` and per-channel `c` rates desynchronising the three cosines, most cells land at mid-saturation mid-tones (pure jewel hues require all three channels to hit specific extremes simultaneously, which rarely happens). Compounding this in the harness: `kLumenEmissionGain = 4.0` in `RayMarch.metal` was multiplying the saturated channels above 1.0, where the harness's float→Unorm conversion clipped them — destroying saturation (e.g. vivid red `(0.9, 0.13, 0.13) × 4 = (3.6, 0.52, 0.52)` clips to `(1.0, 0.52, 0.52)` which reads pinkish-pastel rather than red). Production with PostProcessChain ACES tonemap would handle this gracefully but the M7-prep harness output (no tonemap) was misleading.

Round 4 fixes:

1. **Switch `lm_cell_palette` to HSV-driven**: every cell now gets a saturated hue from the colour wheel by construction. Hue = `moodHueCentre + perCellHue + step × kPaletteStepSize + trackHueShift`. Saturation = `mix(0.85, 0.98, arousal)` with small seedB perturbation `±0.05`. Value = `mix(0.85, 1.00, arousal)` with small seedC perturbation `±0.03`. Saturation floor 0.78 ensures even adverse seed combos stay vivid.
2. **`kLumenEmissionGain` 4.0 → 1.0**: HSV palette is already vivid; no need to lift channels into HDR range. Production output now uniformly bright (no bloom kick on individual cells). Bloom not engaging is correct for the stained-glass jewel-tone aesthetic — every cell is uniformly vivid rather than a few cells being "extra bright."
3. **Mood hue bias**: cool mood pulls hue centre toward blue (~0.65), warm mood toward red-orange (~0.02). LV-LA frame visibly clusters around blues + teals + violets; HV-HA frame clusters around oranges + yellows + reds.

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

| File | FeatureVector / track seed | What it verifies |
|---|---|---|
| `Lumen_Mosaic_silence.png` | All-zero FV, all-zero stems, no track seed, no rising edges | Cells visibly distinct + vivid + uniform brightness — silence rests with each cell on its base palette colour. |
| `Lumen_Mosaic_mid.png` | bands @ 0.50, neutral mood, no rising edges | Same neutral palette at moderate energy (no rising edges in steady FV → no step advance). |
| `Lumen_Mosaic_beat.png` | bass=0.80, bassRel=0.60, bassDev=0.60, beatBass=1.0 | Bass-team cells (~30 % of panel) advance one palette step on the rising-edge of `f.beatBass`. Mid + treble teams hold. |
| `Lumen_Mosaic_hv_ha_mood.png` | bands @ 0.55, valence=+0.6, arousal=+0.6, no seed | Palette character shifts warm — more red / orange / yellow / magenta; per-cell identities preserved. |
| `Lumen_Mosaic_lv_la_mood.png` | bands @ 0.45, valence=−0.5, arousal=−0.4, no seed | Palette character shifts cool — more cyan / teal / green / pink. |
| `Lumen_Mosaic_track_v1.png` | mid energy, neutral mood, **track seed (+1, +1, +1, +1)** | Per-track variety @ extreme corner — yellow-dominant track palette. |
| `Lumen_Mosaic_track_v2.png` | mid energy, neutral mood, **track seed (−1, −1, −1, −1)** | Per-track variety @ extreme corner — magenta + cyan + blue track palette. |
| `Lumen_Mosaic_track_v3.png` | mid energy, neutral mood, **track seed (+1, −1, +1, −1)** | Per-track variety @ extreme corner — red + magenta + yellow track palette. |
| `Lumen_Mosaic_track_v4.png` | mid energy, neutral mood, **track seed (−1, +1, −1, +1)** | Per-track variety @ extreme corner — green + cyan + yellow track palette. |

**Per-track variety mechanism (new in LM.3.2 calibration round 3 — 2026-05-09).** Real-music sessions distribute FNV-1a 64-bit `title|artist` hashes uniformly across the 4D seed cube; `setTrackSeed(fromHash:)` maps each 16-bit half to `[-1, +1]`. Most real tracks land between corners, producing blends of the four `track_v*` characters above. The four extremal corners on this contact sheet bracket the visual range — a real session should never look further from neutral than these four reference points. The track variants share ONE neutral mood (no valence / arousal bias); two tracks at the same mood now produce visibly different palette character via the per-channel hue-shift `(sA, sB, −(sA+sB)/2)` perturbation on `a` (offset) and `(sC, sD, −(sC+sD)/2)` perturbation on `d` (phase). Earlier LM.3.2 implementations applied these as scalar shifts (uniform across all three channels) which only changed brightness or rotated phase — same colour set across all tracks.

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
- **HSV palette knobs (LumenMosaic.metal `lm_cell_palette`)** — round 4 (2026-05-10) replaced the V.3 IQ palette with a direct HSV computation. Tunable inline: hue = `moodHueCentre + (cell_t - 0.5) × 0.40 + step × kPaletteStepSize + (seedA × 0.30 + seedD × 0.50)`. Wider `cell_t` spread → more visible cell-to-cell hue variation per frame; narrower → tighter palette character. `moodHueCentre` interpolates `mix(0.65, 0.02, warm)` — the (0.65, 0.02) endpoints are the cool→warm hue centres on the colour wheel; tweak to bias session character. The `seedA × 0.30` and `seedD × 0.50` magnitudes drive per-track hue rotation. Saturation `mix(0.85, 0.98, arousal) ± 0.05 × seedB` and value `mix(0.85, 1.00, arousal) ± 0.03 × seedC` — both floored high so cells never go pastel.
- **Legacy IQ palette knobs (LumenMosaic.metal — UNUSED at round 4)** — `kPaletteACool/AWarm/BSubdued/BVivid/CUnison/COffset/DComplementary/DAnalogous` and `kSeedMagnitudeA/B/C/D` were the IQ palette parameter knobs through rounds 1–3. Round 4 retains them on the file for ABI continuity / round-5+ revisits but the HSV palette path doesn't read them. They can be deleted in a future cleanup if HSV stays through M7.
- **`kCellIntensityBase / Jitter` (LumenMosaic.metal:~145)** — uniform-brightness baseline + hash jitter. Default 0.85 / 0.15 → cells span [0.85, 1.00]. Reduce jitter to 0 for perfectly flat brightness; raise to spread further.

## Real session review checklist

1. Play a varied playlist (energetic + ballad + instrumental). Each track should have visibly different palette character.
2. Watch a single track for 8 seconds during a steady passage: count cell colour changes per second. ~50–60 % of cells should change at least once during the 8-second window. If the dance feels muddy / chaotic, lower the team cutoffs (move more cells to "static"). If it feels too sparse, lower periods (cap to 4 instead of 8).
3. Force a kick-heavy track: bass-team cells should advance most prominently. Force a melody-led track (typical pop): mid-team cells should advance most prominently.
4. Force HV-HA and LV-LA tracks back-to-back: palette character should shift over the 5 s mood smoothing window. Per-cell *positions* identifiable across both tracks (same Voronoi seed).
5. Pause the music in the middle of a track: cells should freeze at their current step (counters stop advancing because no rising edges arrive).
6. **Vivid throughout?** No frame should have a dominant cream / pastel ratio. If it does, escalate before LM.4.
