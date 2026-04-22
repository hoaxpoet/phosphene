// Gossamer.metal — v3 — bioluminescent web as sonic resonator (Increment 3.5.6).
//
// v3 geometry overhaul — fixes the symmetry problem in v2:
//   · 17 explicitly-defined spoke angles, NOT formula-derived.
//     Spacing ranges 0.27–0.77 rad (avg 21°). One wide open sector (lower-right,
//     0.77 rad gap) where no anchor point exists — like a real web in a corner.
//     Tight cluster near -2.82→-2.15 rad simulates three close ceiling anchors.
//   · Hub at (0.465, 0.32) — upper portion of screen. Hub proximity to top edge
//     clips spiral rings into asymmetric arcs naturally: upper threads are short
//     (only ~0.32 UV to the screen edge), lower threads extend to full radius.
//   · Elliptical stretch removed — asymmetry comes from geometry, not distortion.
//   · kWebRadius expanded to 0.44 so lower spiral rings are full and lush.
//
// All v2 audio improvements retained: bass-primary brightness driver, beat flash,
// standing-wave tremor at 0.018 UV, tight halos (σ=6/4px), wave amplitude/sat
// floors, anchor fade for spokes beyond the capture zone.
//
// Entry point: gossamer_fragment
// Buffer layout: same as v1/v2 (see GossamerState.swift).
// D-026 deviation-first. D-019 warmup. D-037 invariants met.

// ── GPU wave types ─────────────────────────────────────────────────────────────

struct WaveGPU {
    float age;
    float hue;
    float saturation;
    float amplitude;
};

struct GossamerGPU {
    uint  wave_count;
    uint  _pad0, _pad1, _pad2;
    WaveGPU waves[32];
};

// ── Constants ─────────────────────────────────────────────────────────────────

constant float kWebRadius   = 0.44;   // outer capture zone (UV)
constant float kHubRadius   = 0.050;  // free zone near hub — no spiral threads
constant float kSpiralTurns = 7.0;
constant float kWaveSpeed   = 0.12;   // UV/sec — must match GossamerState.waveSpeed
constant float kMaxWaveLife = 6.0;    // seconds — must match GossamerState.maxWaveLifetime

// ── Explicit spoke angles ──────────────────────────────────────────────────────
//
// 17 angles in radians. 0 = right (+X), π/2 = down (+Y in UV space).
// Hub is at (0.465, 0.32) — upper-centre. Spokes radiate from there.
//
// Design: web built at a ceiling/wall junction.
//   • Upper-left cluster (-2.82, -2.48, -2.15): three tight ceiling anchors.
//   • Left wall (-1.78, -1.42, -1.08): regular wall anchors.
//   • Right-of-centre (-0.72 … 0.58): mixed upper-right anchors.
//   • OPEN SECTOR 0.58 → 1.35 (0.77 rad): lower-right has no surface to anchor.
//   • Lower arc (1.35 … 2.95): threads hang toward lower-left anchor.
//
// The irregular gaps (min 0.27, max 0.77 rad) produce visible clustering and
// absence — the web is a product of its anchoring, not a compass rose.

constant int   kSpokeCount   = 17;
constant float kSpokeAngles[17] = {
    -2.82f, -2.48f, -2.15f,   // upper-left cluster (tight, 0.34/0.33 rad)
    -1.78f, -1.42f, -1.08f,   // left wall (0.37/0.36/0.34 rad)
    -0.72f, -0.38f, -0.08f,   // right-of-centre (0.34/0.30 rad)
     0.25f,  0.58f,            // right side (0.33/0.33 rad)
    //                         ← gap: 0.77 rad, lower-right open sector
     1.35f,  1.65f,  1.92f,   // lower-left (0.30/0.27 rad — tight cluster)
     2.28f,  2.62f,  2.95f    // lower anchor threads (0.36/0.34/0.33 rad)
};

// ── Spoke geometry ────────────────────────────────────────────────────────────

static float gossamerSpokeDist(float2 pRel, float angle) {
    float2 d = float2(cos(angle), sin(angle));
    return abs(pRel.x * d.y - pRel.y * d.x);
}

static float gossamerNearestSpokeDist(float2 pRel) {
    float minD = 1e6;
    for (int i = 0; i < kSpokeCount; i++) {
        minD = min(minD, gossamerSpokeDist(pRel, kSpokeAngles[i]));
    }
    return minD;
}

// ── Capture spiral ─────────────────────────────────────────────────────────────
// Radial ring-spacing formula: fold × kWebRadius / kSpiralTurns.
// All rings have equal radial width regardless of radius.
// Free zone r < kHubRadius and outer zone r > kWebRadius return 1e6.

static float gossamerSpiralDist(float2 pRel, float r) {
    if (r < kHubRadius || r > kWebRadius) return 1e6;
    float theta = atan2(pRel.y, pRel.x);
    float coord = theta - (r / kWebRadius) * kSpiralTurns * 2.0 * M_PI_F;
    float fold  = abs(fract(coord / (2.0 * M_PI_F)) - 0.5);
    return fold * kWebRadius / kSpiralTurns;
}

// ── Hub stabilimentum ─────────────────────────────────────────────────────────
// Tight concentric rings in the free zone — dense and dark, not a spotlight.

static float gossamerHubDist(float r) {
    if (r > kHubRadius) return 1e6;
    float coord = r / kHubRadius * 3.0;
    return abs(fract(coord) - 0.5) * kHubRadius / 3.0;
}

// ── Scene fragment ─────────────────────────────────────────────────────────────

fragment float4 gossamer_fragment(
    VertexOut               in     [[stage_in]],
    constant FeatureVector& f      [[buffer(0)]],
    constant float*         fft    [[buffer(1)]],
    constant float*         wv     [[buffer(2)]],
    constant StemFeatures&  stems  [[buffer(3)]],
    constant GossamerGPU&   gState [[buffer(6)]]
) {
    // Hub at upper portion of screen — proximity to top edge clips upper spiral
    // rings into asymmetric arcs, giving the web its natural hanging shape.
    float2 hub  = float2(0.465, 0.32);
    float2 uv   = in.uv;
    float2 pRel = uv - hub;
    float  r    = length(pRel);

    // ── D-019 warmup ─────────────────────────────────────────────────────────
    float totalStemEnergy = stems.vocals_energy + stems.drums_energy
                          + stems.bass_energy   + stems.other_energy;
    float stemMix = smoothstep(0.02, 0.06, totalStemEnergy);

    // ── Audio drivers (D-026 deviation-first) ────────────────────────────────
    float bassRel   = mix(f.bass_att_rel,   stems.bass_energy_rel,   stemMix);
    float midRel    = mix(f.mid_att_rel,    stems.vocals_energy_rel, stemMix);
    float beatPulse = max(f.beat_bass, max(f.beat_mid, f.beat_composite));

    // ── Motion: Strand tremor ─────────────────────────────────────────────────
    // Standing-wave envelope: zero at hub and rim, peak at mid-radius.
    // Amplitude 0.018 UV ≈ 19px at 1080p — clearly visible.
    float vibEnv   = sin(saturate(r / kWebRadius) * M_PI_F);
    float vibPhase = f.beat_phase01 * 2.0 * M_PI_F;
    float radVib   = vibEnv * sin(vibPhase)        * max(-1.0, bassRel) * 0.018;
    float spirVib  = vibEnv * sin(vibPhase + 0.85) * max(-1.0, midRel)  * 0.012;

    float2 tangent = r > 0.001 ? float2(-pRel.y, pRel.x) / r : float2(0.0, 1.0);
    float2 tRel    = pRel + tangent * (radVib + spirVib);
    float  rT      = length(tRel);

    // ── Web geometry distances ────────────────────────────────────────────────
    float spokeDist = gossamerNearestSpokeDist(tRel);
    float spirDist  = gossamerSpiralDist(tRel, rT);
    float hubDist   = gossamerHubDist(rT);

    float taper = saturate(rT / kWebRadius);

    // ── Anti-aliased strand coverage ─────────────────────────────────────────
    float spokeWidth = mix(0.0028, 0.0016, taper);
    float spirWidth  = 0.0015;
    float hubWidth   = 0.0012;
    float aaW        = 0.0007;

    // Spokes extend past kWebRadius with exponential fade — they're anchored.
    // The open sector on the lower-right will simply have no spoke there.
    float anchorFade = rT > kWebRadius ? exp(-(rT - kWebRadius) * 5.0) : 1.0;
    float spokeCov   = smoothstep(spokeWidth + aaW, spokeWidth - aaW, spokeDist) * anchorFade;
    float spokeHalo  = exp(-spokeDist * spokeDist / (0.006 * 0.006)) * 0.45 * anchorFade;

    float inCapture  = (rT >= kHubRadius && rT <= kWebRadius) ? 1.0 : 0.0;
    float inHub      = (rT < kHubRadius)                      ? 1.0 : 0.0;
    float spirCov    = smoothstep(spirWidth + aaW, spirWidth - aaW, spirDist) * inCapture;
    float spirHalo   = exp(-spirDist * spirDist / (0.0042 * 0.0042)) * 0.30 * inCapture;
    float hubCov     = smoothstep(hubWidth + aaW, hubWidth - aaW, hubDist) * 0.65 * inHub;

    float strandCov  = max(max(spokeCov, spirCov), max(max(spokeHalo, spirHalo), hubCov));

    // ── Beat brightness flash ─────────────────────────────────────────────────
    float beatFlash = beatPulse * 0.65;

    // ── Slow hue drift ────────────────────────────────────────────────────────
    float hueDrift  = fract(f.accumulated_audio_time * 0.020 + f.mid_att_rel * 0.05);
    float3 driftTint = hsv2rgb(float3(hueDrift, 0.48, 0.80));

    // ── Base strand color ─────────────────────────────────────────────────────
    // Bass deviation is the primary brightness driver — direct musical connection.
    float3 nearColor  = float3(0.22, 0.70, 0.88);
    float3 rimColor   = float3(0.08, 0.28, 0.70);
    float3 baseColor  = mix(mix(nearColor, rimColor, taper), driftTint, 0.18);
    float brightness  = 0.55 + bassRel * 0.45;
    float3 baseStrand = baseColor * max(0.10, brightness) * (1.0 + beatFlash);

    // ── Propagating color waves ───────────────────────────────────────────────
    float3 waveContrib = float3(0.0);

    for (uint i = 0; i < gState.wave_count; i++) {
        WaveGPU wave = gState.waves[i];
        if (wave.age <= 0.0 || wave.age >= kMaxWaveLife) continue;

        float waveRadius = wave.age * kWaveSpeed;
        float dr         = abs(rT - waveRadius);
        float ring       = exp(-(dr * dr) / (0.010 * 0.010));

        float lifeFrac   = wave.age / kMaxWaveLife;
        float fade       = smoothstep(0.0, 0.05, lifeFrac) * smoothstep(1.0, 0.60, lifeFrac);

        float wSat  = max(wave.saturation, 0.60);
        float wAmp  = max(wave.amplitude,  0.40);
        float3 wCol = hsv2rgb(float3(wave.hue, wSat, wAmp));
        waveContrib += wCol * ring * fade;
    }
    waveContrib *= strandCov;

    // ── Intersection dewdrops ─────────────────────────────────────────────────
    float intersect = spokeCov * spirCov;
    float3 dewColor = float3(0.88, 0.96, 1.0) * intersect
                    * (0.28 + max(0.0, f.treb_dev) * 1.8) * 0.55;

    // ── Background (dark night sky) ────────────────────────────────────────────
    float  gv    = saturate(f.valence * 0.5 + 0.5);
    float  ga    = saturate(f.arousal * 0.5 + 0.5);
    float3 bgLow  = mix(float3(0.004, 0.004, 0.016), float3(0.008, 0.014, 0.006), ga);
    float3 bgHigh = mix(float3(0.004, 0.008, 0.036), float3(0.014, 0.008, 0.022), ga);
    float3 bgColor = mix(bgLow, bgHigh, uv.y * gv);

    // ── Composite ─────────────────────────────────────────────────────────────
    float3 webColor   = strandCov * (baseStrand + waveContrib) + dewColor;
    float3 finalColor = webColor + bgColor;
    finalColor = min(finalColor, float3(0.95));

    return float4(finalColor, 1.0);
}

// ── MV-Warp functions ─────────────────────────────────────────────────────────
// Required by preamble forward declarations (D-027). Both must be present.

MVWarpPerFrame mvWarpPerFrame(
    constant FeatureVector& f,
    constant StemFeatures&  stems,
    constant SceneUniforms& s
) {
    MVWarpPerFrame pf;
    pf.cx = 0.0; pf.cy = 0.0;
    pf.dx = 0.0; pf.dy = 0.0;
    pf.sx = 1.0; pf.sy = 1.0;
    pf.warp = 0.0;

    pf.zoom  = 1.0 + f.bass_att_rel * 0.010 + f.mid_att_rel * 0.006;
    pf.rot   = f.mid_att_rel * 0.003;
    pf.decay = 0.955;

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

    float  zoomAmt = 1.0 / max(pf.zoom, 0.001);
    float2 zoomed  = p * zoomAmt + centre;

    float wobble = (pf.q1 * 0.012 + pf.q2 * 0.008) * rad;
    return zoomed + p * wobble;
}
