// Gossamer.metal — v2 — bioluminescent web as sonic resonator (Increment 3.5.6).
//
// Fundamental design fixes from first-session diagnostics:
//   · Web geometry overhauled: 16 hash-jittered spokes, real hub (no bright disc),
//     proper radial ring-spacing so all rings equally visible, free zone near hub.
//   · Spokes extend to screen edges — the web is always anchored to something.
//   · Slight elliptical stretch + off-center hub for organic asymmetry.
//   · Music responsiveness made visceral: beat flash +65%, bass brightness is the
//     primary visual driver (0.55 + bassRel × 0.45), tremor amplitude 0.018 UV
//     (~19px at 1080p, vs. previous 4px which was invisible).
//   · Wave amplitude and saturation floored so rings are always coloured.
//   · Halos tightened from σ=22px to σ=6px — crisp strands, not a glowing fog.
//
// Entry point: gossamer_fragment
// Buffer layout: same as v1 (see file header in GossamerState.swift).
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

constant int   kRadialCount = 16;     // more spokes = more organic density
constant float kWebRadius   = 0.42;   // outer capture zone (UV)
constant float kHubRadius   = 0.055;  // free zone: no spiral threads within this
constant float kSpiralTurns = 8.0;
constant float kWaveSpeed   = 0.12;   // UV/sec — must match GossamerState.waveSpeed
constant float kMaxWaveLife = 6.0;    // seconds — must match GossamerState.maxWaveLifetime

// ── Hash-jittered spoke angles ─────────────────────────────────────────────────
// Each spoke has a fixed pseudo-random angular offset of ±11% of the equal step,
// giving an organic look without changing frame to frame.

static float gossamerSpokeAngle(int i) {
    uint h  = uint(i) * 2654435761u;
    h = h ^ (h >> 16);
    h = h * 2246822519u;
    h = h ^ (h >> 13);
    float step   = 2.0 * M_PI_F / float(kRadialCount);
    float jitter = (float(h & 0xFFu) / 255.0 - 0.5) * 0.22 * step;  // ±11%
    return float(i) * step + jitter;
}

// Perpendicular distance from pRel to the infinite radial line at spoke i.
static float gossamerSpokeDist(float2 pRel, int i) {
    float a  = gossamerSpokeAngle(i);
    float2 d = float2(cos(a), sin(a));
    return abs(pRel.x * d.y - pRel.y * d.x);
}

// Nearest radial spoke distance.
static float gossamerNearestSpokeDist(float2 pRel) {
    float minD = 1e6;
    for (int i = 0; i < kRadialCount; i++) {
        minD = min(minD, gossamerSpokeDist(pRel, i));
    }
    return minD;
}

// ── Capture spiral ─────────────────────────────────────────────────────────────
// Uses RADIAL distance to the nearest ring (not arc distance), so all rings
// have equal visual weight regardless of radius.  Free zone for r < kHubRadius.

static float gossamerSpiralDist(float2 pRel, float r) {
    if (r < kHubRadius || r > kWebRadius) return 1e6;
    float theta    = atan2(pRel.y, pRel.x);
    float coord    = theta - (r / kWebRadius) * kSpiralTurns * 2.0 * M_PI_F;
    float fold     = abs(fract(coord / (2.0 * M_PI_F)) - 0.5);
    // Radial ring spacing = kWebRadius / kSpiralTurns — constant, ring-independent.
    return fold * kWebRadius / kSpiralTurns;
}

// ── Hub stabilimentum ─────────────────────────────────────────────────────────
// Tight concentric rings in the free zone replace the old bright-disc hubCap.
// The web-creator lives here; it should be dense and dark, not a spotlight.

static float gossamerHubDist(float r) {
    if (r > kHubRadius) return 1e6;
    float coord = r / kHubRadius * 3.0;   // 3 tight rings within hub radius
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
    // Hub offset + elliptical stretch for organic asymmetry.
    // The slight horizontal stretch reads as a web suspended between lateral anchors.
    float2 hub  = float2(0.502, 0.511);
    float2 uv   = in.uv;
    float2 pRel = float2((uv.x - hub.x) / 1.10, (uv.y - hub.y) / 0.94);
    float  r    = length(pRel);

    // ── D-019 warmup ─────────────────────────────────────────────────────────
    float totalStemEnergy = stems.vocals_energy + stems.drums_energy
                          + stems.bass_energy   + stems.other_energy;
    float stemMix = smoothstep(0.02, 0.06, totalStemEnergy);

    // ── Audio drivers (D-026 deviation-first) ────────────────────────────────
    float bassRel   = mix(f.bass_att_rel,   stems.bass_energy_rel,   stemMix);
    float midRel    = mix(f.mid_att_rel,    stems.vocals_energy_rel, stemMix);
    float beatPulse = max(f.beat_bass, max(f.beat_mid, f.beat_composite));

    // ── Motion layer 3: Strand tremor ────────────────────────────────────────
    // Single half-wave standing wave across the web, beat-phase locked.
    // Envelope = sin(π × r/R): zero at hub and rim, maximum at midpoint.
    // Amplitude 0.018 UV ≈ 19px at 1080p — clearly visible at screen distance.
    float vibEnv    = sin(saturate(r / kWebRadius) * M_PI_F);
    float vibPhase  = f.beat_phase01 * 2.0 * M_PI_F;
    float radVib    = vibEnv * sin(vibPhase)        * max(-1.0, bassRel) * 0.018;
    float spirVib   = vibEnv * sin(vibPhase + 0.85) * max(-1.0, midRel)  * 0.012;

    // Tangential displacement: strands sway perpendicular to the radial direction.
    float2 tangent  = r > 0.001 ? float2(-pRel.y, pRel.x) / r : float2(0.0, 1.0);
    float2 tRel     = pRel + tangent * (radVib + spirVib);
    float  rT       = length(tRel);

    // ── Web geometry distances ────────────────────────────────────────────────
    float spokeDist = gossamerNearestSpokeDist(tRel);
    float spirDist  = gossamerSpiralDist(tRel, rT);
    float hubDist   = gossamerHubDist(rT);

    float taper     = saturate(rT / kWebRadius);

    // ── Anti-aliased strand coverage ─────────────────────────────────────────
    float spokeWidth = mix(0.0028, 0.0016, taper);  // tapers toward rim
    float spirWidth  = 0.0015;                        // consistently thin spiral
    float hubWidth   = 0.0012;                        // tight hub rings
    float aaW        = 0.0007;

    // Radial spokes: no rim clipping — they extend to screen edges (anchors).
    // Beyond kWebRadius: exponential fade (characteristic length ~0.20 UV).
    float anchorFade = rT > kWebRadius ? exp(-(rT - kWebRadius) * 5.0) : 1.0;
    float spokeCov   = smoothstep(spokeWidth + aaW, spokeWidth - aaW, spokeDist) * anchorFade;
    float spokeHalo  = exp(-spokeDist * spokeDist / (0.006 * 0.006)) * 0.45 * anchorFade;

    // Spiral and hub rings: only in their respective zones.
    float inCapture  = (rT >= kHubRadius && rT <= kWebRadius) ? 1.0 : 0.0;
    float inHub      = (rT < kHubRadius)                      ? 1.0 : 0.0;
    float spirCov    = smoothstep(spirWidth + aaW, spirWidth - aaW, spirDist) * inCapture;
    float spirHalo   = exp(-spirDist  * spirDist  / (0.0042 * 0.0042)) * 0.30 * inCapture;
    float hubCov     = smoothstep(hubWidth + aaW, hubWidth - aaW, hubDist) * 0.65 * inHub;

    float strandCov  = max(max(spokeCov, spirCov), max(max(spokeHalo, spirHalo), hubCov));

    // ── Beat brightness flash ─────────────────────────────────────────────────
    // Whole-web brightness surges on each beat — the web resonates with the music.
    float beatFlash  = beatPulse * 0.65;

    // ── Motion layer 5: Slow hue drift ───────────────────────────────────────
    float hueDrift   = fract(f.accumulated_audio_time * 0.020 + f.mid_att_rel * 0.05);
    float3 driftTint = hsv2rgb(float3(hueDrift, 0.48, 0.80));

    // ── Base strand color ─────────────────────────────────────────────────────
    // PRIMARY DRIVER: bass energy deviation.
    // When bass is above average (bassRel > 0) the web is bright.
    // When bass is below average (bassRel < 0, sparse music) it dims.
    // This makes the musical connection direct and continuous — no threshold.
    float3 nearColor  = float3(0.22, 0.70, 0.88);
    float3 rimColor   = float3(0.08, 0.28, 0.70);
    float3 baseColor  = mix(mix(nearColor, rimColor, taper), driftTint, 0.18);
    float brightness  = 0.55 + bassRel * 0.45;   // 0.10..1.00 over bassRel −1..1
    float3 baseStrand = baseColor * max(0.10, brightness) * (1.0 + beatFlash);

    // ── Propagating color waves ───────────────────────────────────────────────
    // Waves are only visible on strands (waveContrib × strandCov below).
    // Amplitude and saturation are floored so waves always have visible colour.
    float3 waveContrib = float3(0.0);

    for (uint i = 0; i < gState.wave_count; i++) {
        WaveGPU w = gState.waves[i];
        if (w.age <= 0.0 || w.age >= kMaxWaveLife) continue;

        float waveRadius = w.age * kWaveSpeed;
        float dr         = abs(rT - waveRadius);
        float ring       = exp(-(dr * dr) / (0.010 * 0.010));

        float lifeFrac   = w.age / kMaxWaveLife;
        float fade       = smoothstep(0.0, 0.05, lifeFrac) * smoothstep(1.0, 0.60, lifeFrac);

        float wSat       = max(w.saturation, 0.60);  // floor: waves always coloured
        float wAmp       = max(w.amplitude,  0.40);  // floor: waves always bright
        float3 wCol      = hsv2rgb(float3(w.hue, wSat, wAmp));
        waveContrib     += wCol * ring * fade;
    }
    waveContrib *= strandCov;

    // ── Intersection dewdrops ─────────────────────────────────────────────────
    float intersect  = spokeCov * spirCov;
    float3 dewColor  = float3(0.88, 0.96, 1.0) * intersect
                     * (0.28 + max(0.0, f.treb_dev) * 1.8) * 0.55;

    // ── Background (dark night sky, valence/arousal tinted) ──────────────────
    float  gv     = saturate(f.valence * 0.5 + 0.5);
    float  ga     = saturate(f.arousal * 0.5 + 0.5);
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

    // Bass breath + mid rotation accumulate over mv_warp frames.
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

    // Outer strands ripple more than inner hub (rad scales with distance from centre).
    float wobble   = (pf.q1 * 0.012 + pf.q2 * 0.008) * rad;
    return zoomed + p * wobble;
}
