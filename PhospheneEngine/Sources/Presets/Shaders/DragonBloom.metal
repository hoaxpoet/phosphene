// DragonBloom.metal — Spike 1 of the Dragon Bloom Milkdrop uplift.
//
// Faithful uplift of `$$$ Royal - Mashup (220)` (cream-of-crop Dancer/Petals/).
// See docs/presets/DRAGON_BLOOM_PLAN.md and docs/VISUAL_REFERENCES/dragon_bloom/.
//
// Spike 1 — the minimal version (§6 / §7 step 1):
//   · direct + mv_warp skeleton (the Milkdrop "waveform-into-feedback" pattern).
//   · Fragment draws the live waveform buffer as a polar curve (nWaveMode=7 analog).
//   · mv_warp accumulates feathered trails via decay + per-vertex warp.
//   · NO bilateral symmetry yet (Spike 2 adds the mirror fold + anti-clipart jitter).
//   · NO palette polish yet (Spike 2/3) — fixed warm fiery base color.
//   · Audio routing per §4:
//       - Bloom shape          ← waveform buffer (slot 2)              — the form IS the music
//       - Bloom expand/contract← bass_att_rel/bass_dev → zoom + warp amp — breathing with energy
//       - Feather flow speed   ← mid_att_rel → mvWarpPerVertex magnitude — streams thicken with mids
//       - Per-beat pulse       ← beat_composite → brightness accent      — Layer-4 accent only
//
// Gate (Matt-eyeball): "the bloom is dancing to this song."
// Not certified; not yet evaluated against the §12 fidelity rubric.

// ── Constants (Spike 1 tuning) ────────────────────────────────────────────────

// Waveform curve geometry.
constant float kBloomCentreX     = 0.5;
constant float kBloomCentreY     = 0.5;
constant float kBaseRadius       = 0.28;   // radius of the un-modulated waveform ring
constant float kWaveDisplaceUV   = 0.12;   // peak radial offset from a |sample|=1
constant float kCurveThicknessUV = 0.0040; // anti-aliased thickness of the drawn curve
constant float kCurveHaloUV      = 0.0140; // soft outer halo for bloom feeding

// Target RMS that `waveformRMS()` normalises the raw PCM input to. Tuned to
// match a typical LF AVAudioEngine steady-state RMS so LF audio takes minimal
// boost while quieter process-tap audio scales up to the same effective
// reference (Matt's 2026-06-01 Spotify report). 0.5 floor / 6.0 ceiling on
// the scale factor prevents extreme amplification at edge cases.
constant float kWaveTargetRMS    = 0.25;

// Background — kept near-black so the feedback accumulator dominates the read.
constant float3 kBackgroundColor = float3(0.006, 0.004, 0.012);

// Bloom brush — warm fiery (matches the references' palette register).
// Spike 1 keeps this fixed; later spikes drive it from valence/centroid.
constant float3 kBloomColorHot   = float3(1.00, 0.58, 0.18);  // warm amber/orange
constant float3 kBloomColorEdge  = float3(0.85, 0.20, 0.08);  // deeper red on the halo

// MV-warp baseline (matches source.milk fDecay=0.95, fWarp=0.01).
constant float kMVWarpBaseDecay  = 0.945;
constant float kMVWarpBaseZoom   = 1.0010;  // slow outward bleed → trails spread radially
constant float kMVWarpZoomGain   = 0.0140;  // bass_dev → +zoom (Milkdrop fWarp range)
constant float kMVWarpFeatherAmp = 0.0080;  // mid_att_rel → per-vertex tangential displacement
constant float kMVWarpRotGain    = 0.0020;  // slow swirl from mid_att_rel

// ── Helpers ───────────────────────────────────────────────────────────────────

// Sample the stereo PCM waveform at a fractional frame index, returning mono [-1, 1].
// Buffer is 2048 floats arranged as 1024 stereo frames (idx*2 = L, idx*2+1 = R) —
// see Waveform.metal for the same convention.
static float sampleWaveformMono(constant float* wv, float frameF) {
    constexpr int kFrames = WAVEFORM_CAPACITY / 2;   // 1024
    int frame0 = clamp(int(frameF), 0, kFrames - 2);
    int frame1 = frame0 + 1;
    float t = fract(frameF);
    float s0 = (wv[frame0 * 2] + wv[frame0 * 2 + 1]) * 0.5;
    float s1 = (wv[frame1 * 2] + wv[frame1 * 2 + 1]) * 0.5;
    return mix(s0, s1, t);
}

// Estimate the waveform buffer's RMS amplitude for this frame.
// The waveform is RAW PCM (NOT AGC-normalised) so its peak amplitude varies
// 5×+ across input paths: LF AVAudioEngine ≈ 0.6 peaks; process-tap on
// Spotify with normalize-off ≈ 0.15 peaks (FA #30); other taps anywhere in
// between. Without this normalisation the polar bloom shape (driven by raw
// waveform value) collapses to a nearly-circular ring on quiet inputs — even
// when the AGC-normalised bands say music is clearly playing. Matt's
// 2026-06-01 Spotify report ("reactive for 20 s then looks like silence") is
// this failure mode, manifesting after AGC convergence ate the deviation
// primitives that were masking the issue during cold-start.
//
// Sampling 64 of 1024 stereo frames (stride 16) is sufficient — the buffer
// is a contiguous slab and reads coalesce across fragments. Same answer for
// every fragment in this draw call, so the cost is one per-pixel division
// added to the existing curve math; perceptually free on Apple Silicon.
static float waveformRMS(constant float* wv) {
    constexpr int kSamples = 64;
    constexpr int kStride  = 16;            // 64 × 16 = 1024 stereo frames
    float sumSq = 0.0;
    for (int i = 0; i < kSamples; i++) {
        int idx = i * kStride;
        float lr = (wv[idx * 2] + wv[idx * 2 + 1]) * 0.5;
        sumSq += lr * lr;
    }
    return sqrt(sumSq / float(kSamples));
}

// ── Scene fragment ────────────────────────────────────────────────────────────
//
// Draws ONE frame of the polar waveform curve. The feedback bloom is built up
// across frames by the mv_warp accumulator — this fragment renders only the
// "fresh brush stroke" on a near-black background. The feathered, breathing
// shape is the *integral* of these strokes through mv_warp, not this output.

fragment float4 dragon_bloom_fragment(
    VertexOut               in     [[stage_in]],
    constant FeatureVector& f      [[buffer(0)]],
    constant float*         fft    [[buffer(1)]],   // slot 1 — 512 magnitudes (unused Spike 1)
    constant float*         wv     [[buffer(2)]],   // slot 2 — 2048 samples (1024 stereo frames)
    constant StemFeatures&  stems  [[buffer(3)]]    // unused Spike 1 (D-019 warmup not relevant)
) {
    float2 uv    = in.uv;
    float2 pRel  = uv - float2(kBloomCentreX, kBloomCentreY);
    float  r     = length(pRel);
    float  ang   = atan2(pRel.y, pRel.x);           // [-PI, PI]

    // ── Audio drivers ─────────────────────────────────────────────────────────
    // PRIMARY (Audio Data Hierarchy Layer 1 — continuous energy bands, the
    // bedrock — silence → playing must produce visible motion):
    //   f.bass / f.mid (absolute, AGC-normalised)
    // SECONDARY (D-026 deviation primitives — add inter-track-normalised dynamic
    // variation on top, kicks above average only):
    //   f.bass_att_rel / f.bass_dev / f.mid_att_rel
    // ACCENT (Layer 4 — onset pulses, capped so they never dominate):
    //   max(beat_composite, beat_bass, beat_mid)
    float bassAbs    = f.bass;                       // [0, ~1] — continuous loudness
    float midAbs     = f.mid;                        // [0, ~1] — continuous loudness
    float bassEnergy = max(0.0, f.bass_att_rel);     // [0, ~1] — above-average attack
    float bassKick   = f.bass_dev;                   // [0, ~1] — above-average bass only
    float midFlow    = max(0.0, f.mid_att_rel);      // [0, ~1] — above-average mid attack
    float beatPulse  = max(f.beat_composite, max(f.beat_bass, f.beat_mid));

    // ── Polar waveform curve (nWaveMode=7 analog) ────────────────────────────
    // Map screen angle → waveform sample index → radial offset around kBaseRadius.
    // The bloom *silhouette* is this curve. The bloom *texture* is what mv_warp
    // builds from accumulating thousands of these strokes through warp+decay.
    //
    // Per-frame waveform amplitude normalisation: bring the raw PCM amplitude
    // (slot 2) to a consistent reference RMS so the polar curve deflects
    // equally across audio paths (LF AVAudioEngine vs. process-tap on
    // Spotify/Apple Music — see `waveformRMS` block above). Gated on
    // `musicPresent` (derived from AGC-normalised bands) so the boost only
    // kicks in when there's real audio — at true silence we leave the noise
    // floor alone instead of amplifying it 6×.
    float waveRMS      = waveformRMS(wv);
    float musicPresent = saturate((bassAbs + midAbs + max(0.0, f.treble)) * 1.5 - 0.10);
    float waveAmpScale = mix(1.0, clamp(kWaveTargetRMS / max(0.02, waveRMS), 0.5, 6.0), musicPresent);

    constexpr int kFrames = WAVEFORM_CAPACITY / 2;
    float angNorm  = (ang + M_PI_F) / (2.0 * M_PI_F);   // [0, 1)
    float frameF   = angNorm * float(kFrames - 1);
    float wave     = sampleWaveformMono(wv, frameF) * waveAmpScale;

    // Radius grows with bass — bloom *breathes* with the low end. Continuous
    // bass (Layer 1) drives the steady-state breath; bass_att_rel (above-average)
    // adds an extra swell on transients.
    float liveRadius = kBaseRadius
                     + wave * kWaveDisplaceUV
                     + bassAbs    * 0.030             // continuous breath
                     + bassEnergy * 0.020;            // transient swell
    float dr         = abs(r - liveRadius);

    // Anti-aliased curve coverage + soft halo (the halo is what the warp pass
    // gets to smear — without it the bloom looks like a thin line, not a feathered
    // form).
    float aaW       = 0.0010;
    float curveCov  = smoothstep(kCurveThicknessUV + aaW, kCurveThicknessUV - aaW, dr);
    float curveHalo = exp(-(dr * dr) / (kCurveHaloUV * kCurveHaloUV)) * 0.55;
    float bloomMask = max(curveCov, curveHalo);

    // ── Colour: fixed warm brush (NO palette polish in Spike 1) ──────────────
    // The curve is hot near its centre, deeper red on the halo wings. This is
    // the "brush" loaded into the mv_warp accumulator each frame; the final
    // visible colour comes from accumulating thousands of these brushes through
    // the warp + decay chain.
    float edgeMix    = smoothstep(0.0, kCurveHaloUV, dr);
    float3 brushCol  = mix(kBloomColorHot, kBloomColorEdge, edgeMix);

    // ── Per-beat pulse (Layer-4 accent only) ─────────────────────────────────
    // Bounded; never the dominant motion driver (Audio Data Hierarchy §4 / FA #4).
    float beatBoost  = 1.0 + beatPulse * 0.40;

    // ── Brightness lift ───────────────────────────────────────────────────────
    // PRIMARY: continuous f.bass / f.mid (Layer 1 — non-zero whenever music is
    // playing, even at AGC-average levels). SECONDARY: above-average deviation
    // primitives for dynamic variation. The 0.30 floor keeps the bloom visible
    // at silence (so the warp accumulator has material to smear into the bloom
    // shape across a quiet section without going completely dark).
    float energyLift = 0.30
                     + bassAbs    * 0.45             // continuous bass — primary
                     + midAbs     * 0.30             // continuous mid  — primary
                     + midFlow    * 0.35             // above-average mid attack
                     + bassEnergy * 0.25;            // above-average bass attack

    float3 bloomCol  = brushCol * bloomMask * energyLift * beatBoost;

    // ── Composite onto near-black background ─────────────────────────────────
    // Soft vignette so the corners feed less material into the warp pass —
    // keeps the feathered halo loosely concentric without forcing geometry.
    float vignette   = 1.0 - smoothstep(0.45, 0.95, r);
    float3 final     = kBackgroundColor + bloomCol * vignette;

    final = min(final, float3(1.0));
    return float4(final, 1.0);
}

// ── MV-Warp functions (D-027) ─────────────────────────────────────────────────
// Both required by the preamble forward declarations.

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

    // Continuous outward bleed; gentle additional swell on bass deviation.
    // pf.zoom > 1 ⇒ vertex samples a slightly inward UV ⇒ trails push outward.
    // Layer-1 absolute bass keeps the warp breathing even at AGC-average levels
    // (the bedrock of the Audio Data Hierarchy); deviation primitives add the
    // above-average dynamic on top.
    float bassAbs    = f.bass;
    float bassEnergy = max(0.0, f.bass_att_rel);
    float bassKick   = f.bass_dev;
    pf.zoom  = kMVWarpBaseZoom
             + bassAbs    * 0.008                    // continuous breath
             + bassEnergy * kMVWarpZoomGain          // above-average attack
             + bassKick   * 0.008;                   // above-average kick

    // Slow swirl driven by mid energy — adds rotational energy to the feathers.
    // Layer-1 absolute mid + deviation primitive together.
    float midAbs     = f.mid;
    float midFlow    = max(0.0, f.mid_att_rel);
    pf.rot   = (midAbs * 0.5 + midFlow) * kMVWarpRotGain;

    // Decay = source.milk fDecay (0.95). VisualizerEngine also feeds the JSON
    // `decay` field to setMVWarpDecay so the compose pass matches — keep these
    // two values aligned (both 0.945 here / in DragonBloom.json).
    pf.decay = kMVWarpBaseDecay;

    // Q-channels pass per-frame audio to mvWarpPerVertex.
    pf.q1 = midFlow;       // feather flow magnitude
    pf.q2 = bassEnergy;    // radial breathing
    pf.q3 = bassKick;      // above-average bass impulse
    pf.q4 = 0.0; pf.q5 = 0.0; pf.q6 = 0.0; pf.q7 = 0.0; pf.q8 = 0.0;
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

    // ── Base zoom (outward bleed) ────────────────────────────────────────────
    // Same idiom as Gossamer.metal — invert pf.zoom so >1 = trails push outward.
    float  zoomAmt = 1.0 / max(pf.zoom, 0.001);
    float2 zoomed  = p * zoomAmt;

    // ── Base rotation (slow swirl) ───────────────────────────────────────────
    float c = cos(pf.rot);
    float s = sin(pf.rot);
    float2 rotated = float2(c * zoomed.x - s * zoomed.y,
                            s * zoomed.x + c * zoomed.y);

    // ── Per-vertex feather displacement (the "motion vectors" in the source) ─
    // Two-component motion field:
    //   (a) tangential flow — the feather streams curve sideways, scaled by radius
    //       so the centre stays calm and the edges fan out.
    //   (b) radial breathing — pushes vertices outward on bass kicks.
    // Magnitudes stay small (sub-1% UV per frame) — the rich motion comes from
    // *accumulating* these displacements across the decay window, not from any
    // one frame being dramatic.
    float2 tangent = (rad > 0.001) ? float2(-p.y, p.x) / max(rad, 0.001) * 0.5
                                   : float2(0.0, 0.0);
    float  flowMag = pf.q1 * kMVWarpFeatherAmp * rad;
    float  breathe = pf.q3 * 0.006 * rad;

    float2 feather = tangent * flowMag + normalize(p + float2(1e-5)) * breathe;

    return rotated + centre + feather;
}
