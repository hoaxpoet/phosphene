// DriftMotes.metal — Sky backdrop for the Drift Motes preset (post-DM.3.2).
//
// Three layered elements compose the backdrop, all rendered into the same
// fragment (no new render pass — D-029 keeps the pass set
// `["feedback", "particles"]`):
//
//   1. **3-stop muted-psychedelic gradient** (DM.3.2). Top, mid, and
//      bottom stops are each derived from the current paletteCycle base
//      hue with small offsets — sky shares the palette territory motes
//      are spawning into. Mood (valence) shifts the whole gradient
//      ±0.04 hue. Replaces the pre-DM.3.2 fixed warm-amber gradient
//      that read as "drab" per Matt's M7 review.
//   2. **Complementary floor fog** (DM.3.2). Fog hue is `baseHue + 0.5`
//      — opposite side of the colour wheel, maximising sky/floor
//      contrast. A burnt-amber palette region gets deep-teal fog; a
//      faded-plum region gets yellow-gold fog. Replaces the pre-DM.3.2
//      fixed cool blue-gray fog.
//   3. **Cycle + pitch + beat reactive shaft** (DM.3.2). Shaft colour
//      drifts continuously with paletteCycle (slow base) + vocal pitch
//      (faster, 1-octave wrap) + drum beat (brief hue rotation +
//      brightness lift on each kick). Replaces the pre-DM.3.2 constant
//      warm-gold shaft.
//
// Audio coupling beyond mood/pitch/beat:
// `f.mid_att_rel` continues to modulate shaft brightness from DM.2 — the
// "shaft breathes with vocal energy" reading is preserved.
//
// See `docs/presets/DRIFT_MOTES_PALETTE_DESIGN.md` for the full palette
// spec and the M7 findings that drove DM.3.2.

// Empirical fog tuning. Anticipated to shift in DM.3 (emission rate
// scaling will redistribute density) and during M7 contact-sheet review
// against `01_atmosphere_dust_motes_light_shaft.jpg`.
constexpr constant float kFogTintAmplifier    = 3.5f;
constexpr constant float kFogDensityNormalize = 0.05f;

// dm_palette_region_hue + dm_pitch_hue_offset are duplicated here from
// `ParticlesDriftMotes.metal` because preset shaders compile in their OWN
// translation unit (with `PresetLoader+Preamble.swift`'s preamble), separate
// from the engine library. Symbols don't cross. Both copies must stay in
// sync with the spec at `docs/presets/DRIFT_MOTES_PALETTE_DESIGN.md §1` —
// any change to the 6 palette region hues, the smoothstep blend, or the
// 1-octave pitch wrap MUST be applied to both files.

constant float kPaletteRegionHues[6] = {
    0.08f, 0.95f, 0.78f, 0.50f, 0.15f, 0.02f
};

inline float dm_palette_region_hue(float cycle) {
    float regionFloat = cycle * 6.0;
    int regionIdx = int(regionFloat) % 6;
    int nextIdx = (regionIdx + 1) % 6;
    float regionFrac = regionFloat - float(int(regionFloat));
    float blend = smoothstep(0.5, 1.0, regionFrac);
    float h0 = kPaletteRegionHues[regionIdx];
    float h1 = kPaletteRegionHues[nextIdx];
    float dh = h1 - h0;
    if (dh > 0.5) dh -= 1.0;
    if (dh < -0.5) dh += 1.0;
    return fract(h0 + dh * blend);
}

inline float dm_pitch_hue_offset(float pitchHz, float confidence) {
    if (confidence < 0.3) {
        return 0.0;
    }
    float safePitch = max(pitchHz, 80.0);
    float octaveFrac = fract(log2(safePitch / 110.0));
    return (octaveFrac - 0.5) * 0.20;
}

fragment float4 drift_motes_sky_fragment(
    VertexOut in [[stage_in]],
    constant FeatureVector& f [[buffer(0)]],
    constant StemFeatures& stems [[buffer(3)]]
) {
    float2 uv = in.uv;

    // ── DM.3.2 paletteCycle-derived base hue ─────────────────────────────
    // Same cycle the kernel uses for per-particle hue baking (60 s base
    // period anchored on accumulated_audio_time). Sky and motes share the
    // current palette region by construction, so they read as a coherent
    // chromatic territory rather than two unrelated colour systems.
    float paletteCycle = fract(f.accumulated_audio_time / 60.0);
    float baseHue      = dm_palette_region_hue(paletteCycle);
    float moodHueShift = 0.04 * f.valence;
    float skyHue       = fract(baseHue + moodHueShift);

    // Arousal nudges sky saturation/value upward (more vivid at higher
    // energy; muted at low). Matches the per-particle bias in the kernel.
    float arousalSatBoost = 0.10 * max(0.0, f.arousal);
    float arousalValBoost = 0.05 * max(0.0, f.arousal);

    // ── 1. 3-stop sky gradient (DM.3.2.1 Hendrix-vibrant retune) ─────────
    // Top: deepest hue. Mid: hue-shifted, brighter. Bottom: opposite hue
    // shift. All three at high saturation (0.55–0.70) but kept at LOW
    // value (0.15–0.30) so the backdrop reads as a deep saturated colour
    // field — not a bright wash. Motes/shaft pop against the dark
    // saturated sky like a Wes Wilson Fillmore poster: deep magenta
    // background, hot yellow lettering. The brightness contrast is
    // load-bearing for visual hierarchy; if the sky goes brighter the
    // motes get lost.
    float3 topCol = hsv2rgb(float3(skyHue,
                                    0.55 + arousalSatBoost * 0.5,
                                    0.15 + arousalValBoost * 0.5));
    float3 midCol = hsv2rgb(float3(fract(skyHue + 0.05),
                                    0.70 + arousalSatBoost,
                                    0.30 + arousalValBoost));
    float3 botCol = hsv2rgb(float3(fract(skyHue - 0.05),
                                    0.45 + arousalSatBoost * 0.5,
                                    0.10 + arousalValBoost * 0.5));
    // Two-segment blend: top→mid for upper half, mid→bottom for lower.
    float t = uv.y;
    float3 col;
    if (t < 0.5) {
        col = mix(topCol, midCol, t * 2.0);
    } else {
        col = mix(midCol, botCol, (t - 0.5) * 2.0);
    }

    // ── 2. Complementary floor fog (DM.3.2 — replaces fixed cool blue-gray)
    // Fog hue sits opposite the sky on the colour wheel, maximising the
    // sky/floor contrast. Saturation/value stay muted so the fog reads as
    // atmospheric depth, not a saturated colour wash. The existing
    // `vol_density_height_fog` density math is preserved verbatim — only
    // the colour changes.
    // DM.3.2.1: fog sat 0.20 → 0.50, value 0.28 → 0.32. The fog still
    // needs to read as atmospheric depth (not a saturated wash), but
    // pushing sat to 0.50 makes the complementary-hue contrast against
    // the sky readable. Pre-DM.3.2.1 fog was nearly grey-tinted.
    float fogHue       = fract(baseHue + 0.5);
    float3 fogPos      = float3(0.0, max(0.0, 1.0 - uv.y), 0.0);
    float  fogDensity  = vol_density_height_fog(fogPos, 12.0, 0.85);
    float  fogMask     = clamp(fogDensity * kFogDensityNormalize, 0.0, 1.0);
    float3 fogColor    = hsv2rgb(float3(fogHue, 0.50, 0.32));
    col = mix(col, col * fogColor * kFogTintAmplifier, fogMask);

    // ── 3. Shaft — atmospheric, continuous-only (DM.3.3.1) ──────────────
    //
    // The shaft is the WORLD'S LIGHT, not a music-readable element. A
    // real shaft of light through a window has constant intensity from
    // actual sunlight; per-kick brightness flashes or hue rotations
    // read as "stage light controlled by a DJ" — algorithmic, not
    // atmospheric. Music animates the PARTICLES drifting through the
    // light, not the light itself.
    //
    // DM.3.3.1 retires both per-beat shaft modulations introduced in
    // DM.3.2 / DM.3.3:
    //   - `+0.50 × stems.drums_beat` brightness lift  → REMOVED
    //   - `+0.05 × stems.drums_beat` hue rotation     → REMOVED
    //
    // What remains is purely continuous / atmospheric:
    //   - paletteCycle base hue (60 s cycle through 6 regions, slow)
    //   - vocal-pitch hue drift (continuous, gentle, ±0.05 at half-
    //     strength of the kernel's per-particle shift)
    //   - `f.mid_att_rel` continuous brightness "breath" (keeps the
    //     shaft loosely tied to music's continuous energy without
    //     claiming the beam is a percussion instrument)
    //
    // Per-beat reactivity now lives entirely on the particles:
    //   - DM.3's dispersion shock pushes motes radially on each kick
    //     (kernel-side, kxz-plane impulse with small +y lift)
    //   - DM.3.3's abundant in-beam motes brighten via the sprite
    //     fragment's `shaftLit` modulation, so the existing continuous
    //     shaft brightness propagates to per-mote brightness changes —
    //     music-sync stays readable through the particle field.
    //
    // Pitch shift uses the same dm_pitch_hue_offset as the kernel
    // (1-octave wrap, ±0.10 max), but applied at half-strength so the
    // shaft hue drifts gently rather than strobing on every semitone.
    float shaftBaseHue     = fract(baseHue + 0.08);
    float shaftPitchShift  = 0.5 * dm_pitch_hue_offset(stems.vocals_pitch_hz,
                                                        stems.vocals_pitch_confidence);
    float shaftHue         = fract(shaftBaseHue + shaftPitchShift);

    // DM.3.2.1: shaft sat 0.60 → 0.85, value 0.85 → 0.95. The beam now
    // reads as a fully-saturated lit column of colour, not a desaturated
    // light source. Hendrix-poster aesthetic — saturated everywhere,
    // brightness contrast is what creates visual hierarchy. The sky's
    // low value means the bright shaft still pops despite both being
    // at high saturation.
    float3 shaftColor = hsv2rgb(float3(shaftHue, 0.85, 0.95));

    // Sun anchor at UV (-0.15, 1.20): off-screen upper-left. Shaft axis runs
    // from the anchor through frame centre, giving the ≈30° from-vertical
    // cinematographic angle the design specifies. 32 radial samples per
    // fragment trace from `uv` toward `sunUV`; at each step we evaluate a
    // soft cone mask centred on the shaft axis and accumulate with
    // exponential decay. Decay 0.95 / weight 0.04 are tuned so the shaft
    // is clearly visible at zero audio and saturates around mid_att_rel = 1.
    float2 sunUV    = float2(-0.15, 1.20);
    float2 axisDir  = normalize(float2(0.5, 0.5) - sunUV);
    float2 perpDir  = float2(-axisDir.y, axisDir.x);
    float  shaftAccum = 0.0;
    const int kShaftSteps = 32;
    for (int i = 0; i < kShaftSteps; i++) {
        float2 sUV          = ls_radial_step_uv(uv, sunUV, i, kShaftSteps);
        float2 toSample     = sUV - sunUV;
        float  along        = max(0.0, dot(toSample, axisDir));
        float  perpFromAxis = abs(dot(toSample, perpDir));
        // Cone widens with distance from the sun (0.04 base, +0.12·along).
        float  coneHalfWidth = 0.04 + along * 0.12;
        float  occlusion     = 1.0 - smoothstep(0.0, coneHalfWidth, perpFromAxis);
        shaftAccum += ls_radial_accumulate_step(occlusion, 0.95, 0.04, i);
    }
    // Continuous melody-driven brightness only (D-026 deviation form, DM.2).
    //
    // DM.3.3.1 retired the per-kick brightness lift (`+0.50 × drums_beat`)
    // along with the per-kick hue rotation — see the §3 header comment.
    // The shaft is atmospheric; beats animate the particles, not the
    // light. The continuous `f.mid_att_rel` term is the only audio
    // reactivity remaining on shaft brightness — it reads as the beam
    // gently brightening with vocal energy ("a cloud passing"), not as
    // a percussion instrument.
    float shaftIntensity = 0.65 + 0.25 * f.mid_att_rel;
    col += shaftColor * shaftIntensity * shaftAccum;

    return float4(col, 1.0);
}
