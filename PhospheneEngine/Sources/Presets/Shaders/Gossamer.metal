// Gossamer.metal — Bioluminescent web as sonic resonator (Increment 3.5.6, Arachnid Trilogy).
//
// Paradigm: direct-fragment scene + mv_warp temporal feedback (D-029 compatible composition).
// The scene fragment draws a static hero web via SDF; mv_warp integrates color-wave trails
// across frames so waves leave visible decaying echoes on the strands.
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
// Decay 0.955 leaves visible-but-not-overwhelming trails; waves compound over ~20 frames.
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

    // ── Strand tautness from bass (D-026 deviation-first) ───────────────────
    // FV fallback: bass_att_rel; stem path: bass_energy_rel.
    float bassRel    = mix(f.bass_att_rel, stems.bass_energy_rel, stemMix);
    float tautness   = mix(0.4, 1.0, saturate(0.5 + bassRel * 0.5));

    // ── Web geometry ─────────────────────────────────────────────────────────
    float rimMask    = r < kWebRadius ? 1.0 : 0.0;

    // Strand width tapers from hub (wider) to rim (narrower).
    float taper      = r / kWebRadius;
    float radWidth   = mix(0.0045, 0.0020, taper);
    float spirWidth  = mix(0.0030, 0.0015, taper);

    float rDist      = radialDistUV(uv, hub, r);
    float sDist      = spiralDistUV(uv, hub, r);

    float radCov     = smoothstep(radWidth + 0.0008, radWidth - 0.0008, rDist) * rimMask;
    float spirCov    = smoothstep(spirWidth + 0.0006, spirWidth - 0.0006, sDist) * rimMask;
    float strandCov  = max(radCov, spirCov);

    // Hub cap: small filled disc at center.
    float hubCap     = smoothstep(0.012, 0.008, r);
    strandCov        = max(strandCov, hubCap);

    // ── Drum tremor accent (D-037 invariant 3: ≤ 2× continuous + 1.0) ───────
    // Max 3% intensity boost per hit; drums are accent only, not a driver.
    float drumPulse  = max(f.beat_bass, max(f.beat_mid, f.beat_composite));
    float tremor     = drumPulse * 0.03;

    // ── Base strand emissive (resting brightness) ────────────────────────────
    // Warm near hub, cool at rim; tautness multiplier dims the web when bass is slack.
    float3 nearColor = float3(0.80, 0.72, 0.60);
    float3 rimColor  = float3(0.38, 0.43, 0.52);
    float3 baseStrand = mix(nearColor, rimColor, taper) * tautness * (0.55 + tremor);

    // ── Propagating color waves ───────────────────────────────────────────────
    // Each wave is a thin ring traveling outward from the hub at kWaveSpeed.
    // The wave colors the strands it passes; off-strand pixels get nothing.
    float3 waveContrib = float3(0.0);

    for (uint i = 0; i < gState.wave_count; i++) {
        WaveGPU w = gState.waves[i];
        if (w.age <= 0.0 || w.age >= kMaxWaveLife) continue;

        float waveRadius = w.age * kWaveSpeed;
        float dr         = abs(r - waveRadius);
        float thickness  = 0.016;    // wave ring half-width in UV units
        float ring       = smoothstep(thickness, 0.0, dr);

        // Fade: rises in 10% of lifetime, falls from 70% to 100%.
        float lifeFrac   = w.age / kMaxWaveLife;
        float fade       = smoothstep(0.0, 0.10, lifeFrac)
                         * smoothstep(1.0, 0.70, lifeFrac);

        // Hue → RGB via hsv2rgb (from ShaderUtilities preamble).
        float3 waveColor = hsv2rgb(float3(w.hue, w.saturation, w.amplitude));
        waveContrib += waveColor * ring * fade * strandCov;
    }

    // ── Background gradient (valence/arousal-tinted dark sky) ────────────────
    // Mirrors Arachne's background for trilogy visual consistency.
    float  gv      = saturate(f.valence * 0.5 + 0.5);     // 0=tense, 1=joyful
    float  ga      = saturate(f.arousal * 0.5 + 0.5);     // 0=calm, 1=energetic
    float3 bgLow   = mix(float3(0.01, 0.01, 0.03),        // tense-calm (deep indigo)
                         float3(0.02, 0.04, 0.01),        // tense-energetic (dark green)
                         ga);
    float3 bgHigh  = mix(float3(0.01, 0.02, 0.06),        // joyful-calm (navy)
                         float3(0.04, 0.02, 0.05),        // joyful-energetic (plum)
                         ga);
    // Vertical gradient: 0.0 = top, 1.0 = bottom.
    float3 bgColor = mix(bgLow, bgHigh, uv.y);
    bgColor        = mix(bgLow, bgColor, gv);

    // ── Composite ────────────────────────────────────────────────────────────
    float3 strandResult = strandCov * (baseStrand + waveContrib);
    float3 finalColor   = strandResult + bgColor;

    // Clamp to keep non-HDR path below white-clip (D-037 invariant 2).
    finalColor = min(finalColor, float3(0.95));

    return float4(finalColor, 1.0);
}

// ── MV-Warp functions ─────────────────────────────────────────────────────────
// Both functions are required by the preamble forward declarations (D-027).
// Gossamer's warp is deliberately gentle — the web is at rest; waves are the
// animated element. Aggressive warp would fight the wave ring rendering.
//
// decay 0.955: waves leave visible trails decaying over ~20 frames at 60fps.
// baseZoom from bass_att_rel: ~0.1% radial breath — perceptible but not distracting.

MVWarpPerFrame mvWarpPerFrame(
    constant FeatureVector& f,
    constant StemFeatures&  stems,
    constant SceneUniforms& s
) {
    MVWarpPerFrame pf;
    // Hub-centred: no translation, no rotation.
    pf.cx   = 0.0;  pf.cy = 0.0;
    pf.dx   = 0.0;  pf.dy = 0.0;
    pf.sx   = 1.0;  pf.sy = 1.0;
    pf.rot  = 0.0;
    pf.warp = 0.0;

    // Gentle radial breath keyed to bass_att_rel (D-026).
    // 0.001 UV/beat: nearly imperceptible zoom in the hub area.
    pf.zoom  = 1.0 + f.bass_att_rel * 0.001;
    pf.decay = 0.955;

    // q-variables: pass bass_att_rel to mvWarpPerVertex for spatially-varying wobble.
    pf.q1 = f.bass_att_rel;
    pf.q2 = 0.0; pf.q3 = 0.0; pf.q4 = 0.0;
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

    // Radial zoom centred on hub — inner vertices barely move, outer wobble slightly.
    float zoomAmt = 1.0 / max(pf.zoom, 0.001);
    float2 zoomed = p * zoomAmt + centre;

    // Tiny radial wobble proportional to distance from hub (outer strands wobble more).
    // This gives the sense of strand tension without disturbing the wave rings.
    float wobble  = pf.q1 * rad * 0.002;    // q1 = bass_att_rel
    float2 displaced = zoomed + p * wobble;

    return displaced;
}
