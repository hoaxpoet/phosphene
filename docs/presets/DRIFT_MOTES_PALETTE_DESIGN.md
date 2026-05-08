# Drift Motes — Palette pass design (DM.3.2)

## Why this exists

Matt's M7 review of session `2026-05-08T22-01-07Z` returned three findings:

1. **No dust particles after a few seconds.** ✅ Fixed in DM.3.1 (spawn-Y geometry).
2. **Couldn't detect music reactivity.** Downstream of #1; with particles back, DM.3's emission-rate scaling and dispersion shock are visible.
3. **Color palette is SO DRAB.** Wants vibrancy and psychedelia.

This document specifies the DM.3.2 palette pass that addresses #3.

## Direction (Matt 2026-05-08)

- **Permission to be creative / unrealistic.** Particles can be different colors that contrast with light + background. Don't anchor to "atmospheric dust" reference image realism.
- **Sustained visual interest for 30+ seconds.** Static palette + drifting motion isn't enough. Scene must *evolve* over the segment duration.
- **Multiple presets per song.** Drift Motes will be ONE segment of a multi-preset playback session, not the whole-song visual. Typical segment 30–60 s.

## Spec — "Spectrum Shaft"

The shaft becomes a chromatic prism. Each mote is a single coloured frequency. The whole scene cycles slowly through palette territories so any 30 s viewing reads as a journey, and consecutive segments at different song positions land in distinct territories.

### §1. Palette territories — muted-psychedelic / 60s-poster

Six base hue regions, each ~10 s of a 60 s cycle:

| region | base hue (HSV [0, 1]) | feel |
|---|---|---|
| 0 | 0.08 — burnt amber | ochre, terracotta, rust |
| 1 | 0.95 — dusty rose | faded pink, mauve, peach pearl |
| 2 | 0.78 — faded plum | washed-out violet, dusty grape, mulberry |
| 3 | 0.50 — deep teal | sage, faded turquoise, slate-green |
| 4 | 0.15 — mustard | ochre, olive, dijon |
| 5 | 0.02 — burgundy | wine, oxblood, dried rose |

Saturation **base** 0.45–0.65 (muted, earthy), **pop motes** 0.85–1.0 (high-sat accents, ~8 % of emissions).
Value **base** 0.65–0.80, **pop motes** 0.85–1.0.

Region transitions are **smooth-blended** in the last half of each region — `smoothstep(0.5, 1.0, regionFrac)` cross-fades the base hue toward the next region. No hard cuts.

### §2. Cycle driver

`paletteCycle = fract(f.accumulated_audio_time / 60.0)`.

- Anchored to `accumulated_audio_time` (energy-gated audio time, pauses at silence per the existing FA #33 substitute) so the cycle doesn't advance during paused / silent passages — the field stays in its current palette region while music is absent.
- 60 s base period. Each 30 s preset segment sees ~3 regions; consecutive segments land in different territories.
- **Beat advancement deferred to a later tweak.** The user's "60 s for now, but remember multiple presets per song" leaves this open. First implementation runs at base rate; if cycle feels too uniform on energetic tracks we can add `paletteCycle += beatPulse × 0.005` later.

### §3. Mood bias

`valence` and `arousal` modulate the cycle's appearance without changing its rate:

- **Hue shift:** `+0.04 × valence` — warm valence pushes hue toward red end (+0.04), cool toward green-blue end (−0.04). Shift is small enough that it nudges within a region rather than crossing into the next.
- **Saturation modulator:** `+0.10 × max(0, arousal)` — high arousal pushes base saturation from 0.55 → 0.65 (more vivid).
- **Value modulator:** `+0.05 × max(0, arousal)` — high arousal lightly brightens base value.

### §4. Per-particle palette (kernel emission-time)

At respawn time in `motes_update`:

```msl
float baseHue = dm_palette_region_hue(paletteCycle);  // smooth-blended region hue
float moodHueShift = 0.04 * f.valence;
float jitter = (dm_hash_f01(particleId * 4.71) - 0.5) * 0.20;  // ±0.10 per-particle spread

// Vocal pitch shifts hue when stems are warm. 1-octave wrap so adjacent
// semitones produce visibly distinct shifts (currently dm_pitch_hue is
// 4-octave wrap — too gentle for visible per-mote chromatic spread).
float pitchShift = dm_pitch_hue_offset(stems.vocals_pitch_hz,
                                       stems.vocals_pitch_confidence);

float popRoll = dm_hash_f01(particleId * 2.71);
bool isPop = popRoll < 0.08;  // 8 % of emissions are pop motes

float h = fract(baseHue + moodHueShift + jitter + pitchShift);
float s = isPop ? 0.95 : (0.55 + 0.10 * max(0.0, f.arousal));
float v = isPop ? 0.95 : (0.75 + 0.05 * max(0.0, f.arousal));

float3 rgb = hsv2rgb(float3(h, s, v));
```

The D-019 stem-warmup blend retires here. Cold-stems no longer fall back to per-particle hash around warm amber — they fall back to per-particle hash around the **current paletteCycle region**, so the field is chromatic from frame 0 even at silence, just biased toward whatever region the cycle is in. (At pure silence, `accumulated_audio_time` doesn't advance, so the cycle stays put — but the field's palette is rich.)

### §5. Sky gradient (sky fragment)

Pre-DM.3.2 sky was `mix(top, bottom, uv.y)` with both stops warm-amber. Replace with a **3-stop gradient**:

```msl
float3 topCol  = hsv2rgb(float3(baseHue,           0.30, 0.10));  // deep, low-sat
float3 midCol  = hsv2rgb(float3(baseHue + 0.05,    0.45, 0.18));  // shifted hue, higher sat
float3 botCol  = hsv2rgb(float3(baseHue - 0.05,    0.20, 0.06));  // darker, opposite shift
```

Mood applies the same `valence × 0.04` hue shift as particles, so sky and motes share a coherent palette territory at any moment.

### §6. Shaft — alive, not static

Pre-DM.3.2 shaft colour was constant `(1.00, 0.78, 0.45)` warm-gold. Replace with **cycle-driven base hue + vocal-pitch drift + beat impulse**:

```msl
float shaftBaseHue = dm_palette_region_hue(paletteCycle) + 0.08;  // shaft is brighter "next-step" of palette
float shaftPitchShift = 0.5 * dm_pitch_hue_offset(stems.vocals_pitch_hz,
                                                   stems.vocals_pitch_confidence);
float shaftBeatHueShift = 0.05 * stems.drums_beat;  // brief +0.05 on beat envelope
float shaftHue = fract(shaftBaseHue + shaftPitchShift + shaftBeatHueShift);

float shaftBeatBrightness = 1.0 + 0.30 * stems.drums_beat;
float3 shaftColor = hsv2rgb(float3(shaftHue, 0.60, 0.85)) * shaftBeatBrightness;
```

- Shaft colour drifts continuously with paletteCycle (slow base) + vocal pitch (fast).
- Each kick adds a brief brightness lift AND a small hue rotation, so beats register chromatically not just photometrically.
- Saturation 0.60 keeps the shaft "lit, not glowing-saturated" — fits the muted-psychedelic palette territory.

### §7. Floor fog

Pre-DM.3.2 fog colour was constant `(0.18, 0.20, 0.24)` cool blue-gray. Update to **complementary to base hue** so the lower band of the frame contrasts the sky/motes:

```msl
float fogHue = fract(baseHue + 0.5);  // opposite side of colour wheel
float3 fogColor = hsv2rgb(float3(fogHue, 0.20, 0.28));
```

A burnt-amber palette region (hue 0.08) gets a deep-teal floor fog (hue 0.58). A faded-plum region (0.78) gets a yellow-gold floor (0.28). The complementary pairing maximises sky/floor contrast and gives the scene compositional depth without competing with mote chromaticity.

## Helper functions to add

`dm_palette_region_hue(cycle)` — smooth-blended hue across the 6 regions:

```msl
inline float dm_palette_region_hue(float cycle) {
    constexpr constant float kRegionHues[6] = {0.08, 0.95, 0.78, 0.50, 0.15, 0.02};
    float regionFloat = cycle * 6.0;
    int regionIdx = int(regionFloat) % 6;
    int nextIdx = (regionIdx + 1) % 6;
    float regionFrac = regionFloat - float(regionIdx);
    float blend = smoothstep(0.5, 1.0, regionFrac);
    // Hue interpolation: take shortest path around the colour wheel.
    float h0 = kRegionHues[regionIdx];
    float h1 = kRegionHues[nextIdx];
    float dh = h1 - h0;
    if (dh > 0.5) dh -= 1.0;
    if (dh < -0.5) dh += 1.0;
    return fract(h0 + dh * blend);
}
```

`dm_pitch_hue_offset(pitchHz, confidence)` — 1-octave wrap, returns hue offset in [-0.10, +0.10]:

```msl
inline float dm_pitch_hue_offset(float pitchHz, float confidence) {
    if (confidence < 0.3) return 0.0;
    float safePitch = max(pitchHz, 80.0);
    float octaveFrac = fract(log2(safePitch / 110.0));  // 1-octave wrap
    return (octaveFrac - 0.5) * 0.20;
}
```

(The existing `dm_pitch_hue` (4-octave wrap, returns absolute hue) stays as the canonical helper for *other* particle presets that want pitch as a direct hue source. Drift Motes from DM.3.2 onward uses pitch as a relative offset.)

## What this retires from the kernel

- The D-019 stem-warmup blend (`smoothstep(0.02, 0.06, totalStemEnergy)`) at the emission branch. Cold and warm stems both now use the paletteCycle as the base; vocal pitch is a small offset on top.
- The hard-coded warm-amber base hue 0.08 for cold-stems. Replaced by paletteCycle.
- The constant warm-gold shaft colour and constant cool-blue-gray fog. Both are now palette-region-driven.

D-019 grep on `ParticlesDriftMotes.metal` will return zero hits after DM.3.2. Add a note in the file header that the D-019 blend was retired here for design reasons (palette territory bias replaces stem-warmup as the cold-state behaviour).

## What stays the same

- Spawn geometry from DM.3.1 (`x ∈ [3.64, 5.04]`, `y ∈ [3.64, 3.94]`).
- Kernel motion: wind + curl turbulence + dispersion shock.
- Emission rate scaling from DM.3 (`f.mid_att_rel` lifetime divisor).
- Sprite render: additive blend, Gaussian falloff, shaft-proximity brightness modulation.
- Particle count (800), lifetime range (5–9 s), bounds (±8, ±8, ±4).

## Verification plan

- Existing DriftMotes tests must remain green: `RespawnDeterminism` (within-life invariance — colour bit-identical across non-respawning frames), `AudioCouplingTest`, `Visibility`, `NonFlock`. The respawn determinism test asserts colour stability per particle within life; with the cycle being slow (60 s) and the kernel reading `accumulated_audio_time` at emission time only, colour stays bit-identical post-spawn for any single particle's life. Test passes by construction.
- New regression-lock for the palette cycle: verify `dm_palette_region_hue` is well-formed across the cycle (no hue discontinuities, smooth interpolation, full 6-region coverage). One small synthesis test.
- Drift Motes regression hash WILL drift. Sky fragment outputs change colour structurally. Regenerate.
- `swift test --filter DriftMotes` should run in under 5 s total.

## Out of scope

- Trails (no — Matt's call). Sprite render stays additive on overwriting sky fragment.
- Multiple shafts (no — Matt's call). One shaft.
- Beat-driven cycle advancement. Deferred — first iteration runs at base rate. Add later if needed.
- Stem-routing palette (different stems → different hues). Considered but redundant given mood bias + per-particle vocal-pitch shift cover the same musicality goal.
- `DriftMotes.json` `certified` flag flip. Stays `false` pending Matt's M7 re-review of the palette pass.

## Carry-forward to DM.4

- DM.4 is wind × `f.bass_att_rel`, valence-tinted backdrop, anticipatory shaft pulse on `f.beat_phase01`, structural-flag scatter.
- The valence-tinted backdrop was originally specced as a separate DM.4 reactivity; DM.3.2 now covers it via the paletteCycle + mood bias. **DM.4 backdrop reactivity is therefore subsumed.** DM.4 scope shrinks to the other three items.
- Beat-driven palette-cycle advancement could fold into DM.4's anticipatory shaft pulse work — both are beat-phase reactivities. Decide at DM.4 spec time.
