// Gossamer.metal — Bioluminescent web as sonic resonator (Increment 3.5.6, Arachnid Trilogy).
//
// Paradigm: direct-fragment scene + mv_warp temporal feedback (D-029 compatible composition).
// The scene fragment draws a static hero web via SDF; mv_warp integrates color-wave trails
// across frames so waves leave visible decaying echoes on the strands.
//
// Motion systems (five simultaneous layers):
//   1. Propagating color waves  — radial Gaussian rings, vocal/energy driven (existing)
//   2. Hub breathing            — UV rescaled around hub with above-average bass
//   3. Transverse strand vibration — beat_phase01-locked plucked-string oscillation
//   4. Intersection dewdrops    — sparkle nodes at radial × spiral crossings, treble driven
//   5. Slow hue drift           — whole-web palette cycles over accumulated song energy
//
// Scene fragment entry point: gossamer_fragment
// Buffer bindings (matches renderSceneToTexture + directPresetFragmentBuffer):
//   buffer(0) = FeatureVector  (preamble struct, 192 bytes)
//   buffer(1) = FFT magnitudes (unused — declared for binding completeness)
//   buffer(2) = waveform data  (unused — declared for binding completeness)
//   buffer(3) = StemFeatures   (preamble struct, 256 bytes)
//   buffer(6) = GossamerGPU    (wave pool, 528 bytes; see GossamerState.swift)
//
// The mv_warp pass provides temporal feedback via mvWarpPerFrame + mvWarpPerVertex.
// decay 0.955: waves leave visible trails over ~20 frames; zoom 0.010 gives audible
// bass breath; mid_att_rel drives slow web rotation and per-vertex radial wobble.
//
// D-026 deviation-first: all audio drivers use *_rel / *_dev / *_att_rel primitives.
// D-019 warmup: stems blend in via smoothstep(0.02, 0.06, totalStemEnergy).
// D-037 acceptance: background gradient + seeded waves guarantee non-black at silence.

// ── Web types ──────────────────────────────────────────────────────────────────

/// GPU-side wave descriptor — 16 bytes, matches WaveGPU in GossamerState.swift.
struct WaveGPU {
    float age;          // currentTime - birthTime (seconds)
    float hue;          // 0..1
    float saturation;   // 0..1
    float amplitude;    // 0..1
};

/// Wave pool header + data — 528 bytes, matches GossamerState.waveBuffer layout.
struct GossamerGPU {
    uint  wave_count;   // number of active waves (0..32)
    uint  _pad0;
    uint  _pad1;
    uint  _pad2;
    WaveGPU waves[32];
};

// ── Constants ─────────────────────────────────────────────────────────────────

constant int   kRadialCount  = 12;
constant float kWebRadius    = 0.42;    // UV hub→rim (hub at 0.5,0.5)
constant float kSpiralTurns  = 8.0;    // full turns of capture spiral
constant float kWaveSpeed    = 0.12;   // UV/sec; must match GossamerState.waveSpeed
constant float kMaxWaveLife  = 6.0;    // seconds; must match GossamerState.maxWaveLifetime

// ── Web geometry helpers ───────────────────────────────────────────────────────

/// Angular distance to the nearest radial (0 = on a radial, 0.5 = midway between).
/// Returns distance in UV units from the nearest radial spoke.
static float radialDistUV(float2 p, float2 hub, float r) {
    float2 pRel  = p - hub;
    float  theta = atan2(pRel.y, pRel.x);
    float  step  = 2.0 * M_PI_F / float(kRadialCount);
    // Normalized angle within one step, folded to [0, 0.5].
    float  norm  = fract((theta + 2.0 * M_PI_F) / step);
    float  fold  = abs(norm - 0.5);         // 0 = on spoke, 0.5 = midway
    return fold * step * r;                  // UV distance from nearest spoke
}

/// UV distance from the nearest arm of the Archimedean capture spiral.
static float spiralDistUV(float2 p, float2 hub, float r) {
    float2 pRel  = p - hub;
    float  theta = atan2(pRel.y, pRel.x);
    // Map r (0→kWebRadius) to spiral turns.
    float  spiralAngle = theta - (r / kWebRadius) * kSpiralTurns * 2.0 * M_PI_F;
    float  norm  = fract(spiralAngle / (2.0 * M_PI_F));
    float  fold  = abs(norm - 0.5);
    return fold * 2.0 * M_PI_F * r;        // approximate UV arc distance
}

// ── Scene fragment ─────────────────────────────────────────────────────────────

fragment float4 gossamer_fragment(
    VertexOut                   in      [[stage_in]],
    constant FeatureVector&     f       [[buffer(0)]],
    constant float*             fft     [[buffer(1)]],
    constant float*             wave    [[buffer(2)]],
    constant StemFeatures&      stems   [[buffer(3)]],
    constant GossamerGPU&       gState  [[buffer(6)]]
) {
    float2 uv  = in.uv;
    float2 hub = float2(0.5, 0.5);
    float  r   = length(uv - hub);

    // ── D-019 warmup: blend FV → stems as stem energy builds ─────────────────
    float totalStemEnergy = stems.vocals_energy + stems.drums_energy
                          + stems.bass_energy   + stems.other_energy;
    float stemMix = smoothstep(0.02, 0.06, totalStemEnergy);

    // ── Audio drivers (D-026 deviation-first) ────────────────────────────────
    float bassRel  = mix(f.bass_att_rel, stems.bass_energy_rel, stemMix);
    float tautness = mix(0.4, 1.0, saturate(0.5 + bassRel * 0.5));

    // ── Motion layer 2: Hub breathing ────────────────────────────────────────
    // Above-average bass (bassRel > 0) compresses the web toward the hub.
    // breatheScale in [1.0, 1.07] — strands tighten on every bass hit.
    float breatheScale = 1.0 + max(0.0, bassRel) * 0.07;
    float2 breathedUV  = hub + (uv - hub) / breatheScale;
    float  rB          = length(breathedUV - hub);
    float  rimMask     = rB < kWebRadius ? 1.0 : 0.0;

    // Strand width tapers from hub (wider) to rim (narrower).
    float taper     = rB / kWebRadius;
    float radWidth  = mix(0.0045, 0.0020, taper);
    float spirWidth = mix(0.0030, 0.0015, taper);

    // ── Motion layer 3: Transverse strand vibration ───────────────────────────
    // beat_phase01 advances exactly one 2π cycle per predicted beat interval.
    // Modulating the signed distance to each strand family makes the web oscillate
    // like a plucked string — synchronised to the beat, not a free-running sine.
    float vibPhase = f.beat_phase01 * 2.0 * M_PI_F;
    float radVib   = sin(rB * 22.0 - vibPhase)       * max(0.0, bassRel)        * 0.004;
    float spirVib  = sin(rB * 18.0 - vibPhase + 1.2) * max(0.0, f.mid_att_rel) * 0.003;

    float rDist0   = radialDistUV(breathedUV, hub, rB);
    float sDist0   = spiralDistUV(breathedUV, hub, rB);
    float rDistVib = abs(rDist0 + radVib);
    float sDistVib = abs(sDist0 + spirVib);

    float radCov  = smoothstep(radWidth + 0.0008, radWidth - 0.0008, rDistVib) * rimMask;
    float spirCov = smoothstep(spirWidth + 0.0006, spirWidth - 0.0006, sDistVib) * rimMask;

    // Two-layer bioluminescent glow: crisp strand edge + wide luminous halo.
    // Sigma in UV units — 0.022 ≈ 22px at 1080p, giving visible ambient glow between strands.
    float radHalo  = exp(-rDistVib * rDistVib / (0.022 * 0.022)) * 0.90 * rimMask;
    float spirHalo = exp(-sDistVib * sDistVib / (0.016 * 0.016)) * 0.70 * rimMask;
    float strandCov = max(max(radCov, spirCov), max(radHalo, spirHalo));

    // Hub cap: small filled disc at center.
    float hubCap = smoothstep(0.012, 0.008, r);
    strandCov    = max(strandCov, hubCap);

    // ── Motion layer 4: Intersection dewdrops ────────────────────────────────
    // At every radial × spiral crossing the strands catch light like dewdrops.
    // treble_dev boosts brightness on high-frequency transients — cymbal hits
    // cause the whole web to briefly sparkle.
    float intersection = radCov * spirCov;
    float dewGlow      = intersection * (0.4 + max(0.0, f.treb_dev) * 2.5) * 0.7 * rimMask;
    float3 dewColor    = float3(0.85, 0.95, 1.0) * dewGlow;

    // ── Drum tremor accent (D-037 invariant 3: ≤ 2× continuous + 1.0) ───────
    // Max 3% intensity boost per hit; beat is accent only.
    float drumPulse = max(f.beat_bass, max(f.beat_mid, f.beat_composite));
    float tremor    = drumPulse * 0.03;

    // ── Web breathing: per-layer audio response ───────────────────────────────
    float breathRadial = 1.0 + max(0.0, bassRel)       * 0.65;
    float breathSpiral = 1.0 + max(0.0, f.mid_att_rel) * 0.50;
    float totalCov     = radCov + spirCov;
    float wRadial      = totalCov > 0.001 ? radCov / totalCov : 0.5;
    float breathFactor = mix(breathSpiral, breathRadial, wRadial);

    // ── Motion layer 5: Slow hue drift ───────────────────────────────────────
    // accumulated_audio_time grows only while music is playing (energy-weighted).
    // * 0.025 ≈ full hue cycle every ~40 s of dense audio energy.
    // mid_att_rel adds a melodic nudge so harmonically busy passages shift hue faster.
    float hueDrift   = fract(f.accumulated_audio_time * 0.025 + f.mid_att_rel * 0.08);
    float3 driftTint = hsv2rgb(float3(hueDrift, 0.55, 0.85));

    // ── Base strand emissive (resting brightness) ────────────────────────────
    // Bioluminescent palette: bright cyan hub fades to deep blue at the rim.
    // Hue drift is blended in at 25% — palette drifts slowly, identity holds.
    float3 nearColor = float3(0.38, 0.85, 0.90);  // cyan hub
    float3 rimColor  = float3(0.14, 0.44, 0.82);  // deep blue rim
    float3 baseColor = mix(mix(nearColor, rimColor, taper), driftTint, 0.25);
    float3 baseStrand = baseColor * tautness * (1.50 + tremor) * breathFactor;

    // ── Propagating color waves ───────────────────────────────────────────────
    // Gaussian ring profile: no block artifacts, iridescent complement shimmer.
    // Wave rings travel in raw UV space (r, not rB) — they propagate through the
    // web regardless of breathing, which reads as the web resonating freely.
    float3 waveContrib    = float3(0.0);
    float  totalRingWeight = 0.0;

    constexpr float kRingSigma = 0.011;  // ring half-width in UV units

    for (uint i = 0; i < gState.wave_count; i++) {
        WaveGPU w = gState.waves[i];
        if (w.age <= 0.0 || w.age >= kMaxWaveLife) continue;

        float waveRadius = w.age * kWaveSpeed;
        float dr         = abs(r - waveRadius);
        float ring       = exp(-(dr * dr) / (kRingSigma * kRingSigma));

        // Fade: rises in 8% of lifetime, falls from 65% to 100%.
        float lifeFrac = w.age / kMaxWaveLife;
        float fade     = smoothstep(0.0, 0.08, lifeFrac) * smoothstep(1.0, 0.65, lifeFrac);

        float scaledRing = ring * fade;
        totalRingWeight += scaledRing;

        float3 waveColor = hsv2rgb(float3(w.hue, w.saturation, w.amplitude));
        float3 compColor = hsv2rgb(float3(fract(w.hue + 0.5), w.saturation * 0.45, w.amplitude * 0.30));
        waveContrib += (waveColor + compColor) * scaledRing * strandCov;
    }

    // Interference bloom: white burst where ≥2 waves overlap simultaneously.
    float interferenceBloom = saturate(totalRingWeight - 1.0) * 0.45;
    waveContrib += float3(1.0, 0.98, 0.90) * interferenceBloom * strandCov;

    // ── Background gradient (valence/arousal-tinted dark sky) ────────────────
    float  gv     = saturate(f.valence * 0.5 + 0.5);
    float  ga     = saturate(f.arousal * 0.5 + 0.5);
    float3 bgLow  = mix(float3(0.01, 0.01, 0.03), float3(0.02, 0.04, 0.01), ga);
    float3 bgHigh = mix(float3(0.01, 0.02, 0.06), float3(0.04, 0.02, 0.05), ga);
    float3 bgColor = mix(bgLow, bgHigh, uv.y);
    bgColor        = mix(bgLow, bgColor, gv);

    // ── Composite ────────────────────────────────────────────────────────────
    // dewColor has its own coverage (intersection × rimMask), sits outside strandCov.
    float3 strandResult = strandCov * (baseStrand + waveContrib) + dewColor;
    float3 finalColor   = strandResult + bgColor;

    // Clamp to keep non-HDR path below white-clip (D-037 invariant 2).
    // 0.95 linear → sRGB 249/255 on bgra8Unorm_srgb — bright but not blown out.
    finalColor = min(finalColor, float3(0.95));

    return float4(finalColor, 1.0);
}

// ── MV-Warp functions ─────────────────────────────────────────────────────────
// Both functions are required by the preamble forward declarations (D-027).
//
// decay 0.955: wave echoes persist ~20 frames at 60fps.
// zoom 0.010: ~1% radial breath per above-average bass hit — clearly visible.
// rot from mid_att_rel: slow hub rotation locked to melodic energy.
// Per-vertex wobble 0.012+0.008: outer strands ripple visibly on bass+mid hits.

MVWarpPerFrame mvWarpPerFrame(
    constant FeatureVector& f,
    constant StemFeatures&  stems,
    constant SceneUniforms& s
) {
    MVWarpPerFrame pf;
    pf.cx   = 0.0;  pf.cy = 0.0;
    pf.dx   = 0.0;  pf.dy = 0.0;
    pf.sx   = 1.0;  pf.sy = 1.0;
    pf.warp = 0.0;

    // Bass-driven radial breath + mid-driven slow rotation.
    pf.zoom  = 1.0 + f.bass_att_rel * 0.010 + f.mid_att_rel * 0.006;
    pf.rot   = f.mid_att_rel * 0.003;
    pf.decay = 0.955;

    // q1 = bass_att_rel, q2 = mid_att_rel: passed to per-vertex wobble.
    pf.q1 = f.bass_att_rel;
    pf.q2 = f.mid_att_rel;
    pf.q3 = 0.0; pf.q4 = 0.0;
    pf.q5 = 0.0; pf.q6 = 0.0; pf.q7 = 0.0; pf.q8 = 0.0;
    return pf;
}

float2 mvWarpPerVertex(
    float2 uv, float rad, float ang,
    thread const MVWarpPerFrame& pf,
    constant FeatureVector& f,
    constant StemFeatures& stems
) {
    float2 centre = float2(0.5, 0.5);
    float2 p      = uv - centre;

    float zoomAmt = 1.0 / max(pf.zoom, 0.001);
    float2 zoomed = p * zoomAmt + centre;

    // Radial wobble: outer strands ripple more, inner hub remains stable.
    // Bass pumps radially; mid adds angular twist — combined they read as
    // the web resonating under acoustic excitation.
    float wobble     = (pf.q1 * 0.012 + pf.q2 * 0.008) * rad;
    float2 displaced = zoomed + p * wobble;

    return displaced;
}
