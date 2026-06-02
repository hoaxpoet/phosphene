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

    // ── Bilateral mirror fold (Spike 2) ──────────────────────────────────────
    // Fold the silhouette source about the VERTICAL axis (abs on the x
    // component) so the left and right halves sample the SAME part of the
    // waveform → the bloom is bilaterally symmetric, matching the reference
    // (`01_target.png`, which mirrors left↔right about a vertical centre line).
    //
    // We fold ONLY the angle used to draw the waveform curve — i.e. the bloom
    // SILHOUETTE. The rich feathered TEXTURE that keeps this out of FA #48
    // ("flat mirrored clipart", the Arachne anti-reference) comes from the
    // mv_warp accumulator, whose tangential-swirl field has rotational
    // handedness (`(-p.y, p.x)`) and therefore accumulates DIFFERENTLY on the
    // two halves even though each fresh brush stroke is mirror-symmetric.
    // Net read: symmetric FORM, non-identical (rich) TEXTURE. Per the plan §5
    // and the reference README: "Mirror a feedback-warped field, never flat
    // geometry." The folded curve is the brush; the warped accumulator is the
    // field. (If a future render reads as clipart, add per-side hash jitter
    // here per FA #44 — the warp handedness is the primary anti-clipart source.)
    float  angFold = atan2(pRel.y, abs(pRel.x));    // [-PI/2, PI/2] — right-half angle, mirrored to left

    // ── Audio drivers ─────────────────────────────────────────────────────────
    // Signal selection is empirically grounded: each driver was chosen by
    // measuring its frame-to-frame stddev across both a real LF session
    // (Atlas, the one that "danced") and a real Spotify session (the one that
    // looked muted), per the 2026-06-02 BUG-025 A/B diagnosis. Only signals
    // that are *alive on both paths* drive motion. The earlier Spike-1 routing
    // drove feather flow from `mid_att_rel` (stddev ≈ 0.01 on this music →
    // feathers frozen) and breathing from `max(0, bass_att_rel)` (clamping the
    // signed signal to zero → no breathing). Both were dead. See the
    // (layer × primitive × timescale) table at the top of mvWarpPerFrame.
    //
    //   bass_rel SIGNED  — stddev 0.20 (Spotify) / 0.22 (LF): the strongest
    //                      path-consistent continuous driver. Signed so the
    //                      bloom contracts below-average and expands above.
    //   bass (Layer-1)   — stddev 0.10 / 0.11: continuous loudness / presence.
    //   spectralFlux     — stddev 0.22 / 0.15: spectral-change → feather flow.
    //   beatComposite    — stddev 0.25 / 0.37: the per-beat accent.
    //   mid / treble     — stddev < 0.02 on bass-dominant music; kept only as a
    //                      tiny additive term so mid-rich tracks still register,
    //                      never as a primary driver.
    float bassAbs    = f.bass;                       // [0, ~1] — continuous loudness
    float midAbs     = f.mid;                        // [0, ~1] — usually tiny
    float bassRel    = f.bass_rel;                   // [-1, ~0.6] SIGNED — alive on both paths
    float flux       = f.spectral_flux;              // [0, 1] — spectral change
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

    // Map the FOLDED vertical-sweep angle [-PI/2, PI/2] across the full
    // waveform [0, 1]: bottom of screen (angFold → -PI/2) samples frame 0, top
    // (angFold → +PI/2) samples the last frame. Because angFold is built from
    // abs(pRel.x), the left half mirrors the right — the curve, and therefore
    // the bloom silhouette, is bilaterally symmetric.
    constexpr int kFrames = WAVEFORM_CAPACITY / 2;
    float angNorm  = (angFold + M_PI_F * 0.5) / M_PI_F;   // [0, 1] across the vertical sweep
    float frameF   = angNorm * float(kFrames - 1);
    float wave     = sampleWaveformMono(wv, frameF) * waveAmpScale;

    // Radius — the bloom *breathes* with the low end.
    //   · Continuous bass (Layer 1) sets a gentle baseline swell.
    //   · SIGNED bass_rel is the breathing (stddev ≈ 0.21 on both paths — the
    //     alive signal). It sits structurally negative because the bass band
    //     is a fraction of the AGC total-energy average it's normalised
    //     against, so it averages ≈ −0.5 on real music regardless of path. We
    //     RECENTER by +0.5 so the bloom rests at base radius at typical bass,
    //     expands on bass hits (bass_rel → 0 or positive), and draws in during
    //     bass lulls (bass_rel → −1). Without the recenter the bloom would sit
    //     permanently contracted. The 0.060 gain gives clearly visible travel
    //     (≈ ±0.03 UV typical, more on hits) against the 0.28 base radius.
    float breathe    = (bassRel + 0.5) * 0.060;       // recentered SIGNED breathing
    float liveRadius = kBaseRadius
                     + wave    * kWaveDisplaceUV      // the music's waveform shape
                     + bassAbs * 0.020                // continuous baseline swell
                     + breathe;                       // alive on both paths
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
    // Bounded and deliberately small. mv_warp feedback AMPLIFIES per-beat
    // brightness flashes (a bright beat frame smears forward through the
    // accumulator), so this is exactly the "beat amplified by feedback"
    // failure FA #4 guards. Primary motion lives in the continuous drivers
    // (bass_rel breathing + flux feather flow + bass brightness); the beat is
    // a 0.15 shimmer on top, never the dominant driver.
    float beatBoost  = 1.0 + beatPulse * 0.15;

    // ── Brightness lift ───────────────────────────────────────────────────────
    // PRIMARY: continuous f.bass (Layer 1 — non-zero whenever music is playing,
    // stddev ≈ 0.10 on both paths). A small spectralFlux term adds shimmer on
    // spectral changes; a tiny mid term so mid-rich tracks register. The 0.30
    // floor keeps the bloom visible at silence so the warp accumulator always
    // has material to smear into the bloom shape. bass_rel is deliberately NOT
    // used here — it drives the radius breathing (one primitive per layer,
    // per feedback_audio_layer_one_primitive); routing it into brightness too
    // would encode the same bass event through two channels at one timescale.
    float energyLift = 0.30
                     + bassAbs * 0.55                // continuous bass — primary
                     + flux    * 0.20                // spectral-change shimmer
                     + midAbs  * 0.30;               // mid (tiny on bass-dominant music)

    float3 bloomCol  = brushCol * bloomMask * energyLift * beatBoost;

    // ── Composite onto near-black background ─────────────────────────────────
    // Soft vignette so the corners feed less material into the warp pass —
    // keeps the feathered halo loosely concentric without forcing geometry.
    float vignette   = 1.0 - smoothstep(0.45, 0.95, r);
    float3 final     = kBackgroundColor + bloomCol * vignette;

    final = min(final, float3(1.0));
    return float4(final, 1.0);
}

// ── L1: Spectral strand brush (the UPLIFT — D-137) ─────────────────────────────
//
// Faithful transcription of source.milk's three custom waveforms
// (`wave_0/1/2_per_point*`) — the tumbling 3-D spectral helix-strands that ARE
// the bloom's petals — UPLIFTED to drive each strand by a real separated STEM
// instead of an FFT band:
//   strand 0 ← DRUMS   (was mid_att,  source wave_0 rotation rates, red-dominant)
//   strand 1 ← BASS    (was bass_att, source wave_1 rotation rates, green-dominant)
//   strand 2 ← VOCALS  (was treb_att, source wave_2 rotation rates, blue-dominant)
// `other` is reserved for palette tint (L5). Each strand is one line strip of
// kStrandSamples points (instance_id = strand, vertex_id = sample), drawn
// additively into the mv_warp scene texture; the existing feedback then feathers
// them into the warm bloom. HDR (>1) colour is intentional — additive glow,
// tonemapped downstream.
//
// per_point recipe (source.milk, verbatim math): a vertical line oy=sample·mod
// with a tight helix (ox,oz) of frequency sp wound around it, tapered by
// sin(sample·π), rotated in 3-D by time-varying angles, perspective-projected
// (x=ox·fov/oz, with the 0.75 horizontal squish), with oz=abs(oz)−2 (the fold
// that yields the bilateral symmetry). vol is the source's final constant 0.2.

constant int   kStrandSamples = 512;     // points per strand (source uses 512)
constant float kStrandSP      = 6.28 * 8.0 * 8.0 * 4.0;   // 1285.76 — source `sample*6.28*8*8*4`
constant float kStrandVol     = 0.2;     // source's final `vol = .2`
constant float kStrandFov     = 0.5;     // source's `fov = .5`

struct DragonStrandVertexOut {
    float4 position [[position]];
    float4 color;                 // rgb (HDR, may exceed 1) + additive weight in .a
    float  pointSize [[point_size]];
};

// Map a stem's energy + deviation to the source's `mod` stretch (range ≈ [0.4, 2.0],
// matching source's `mod = if(below(band,1.8), band+.2, 2)`). Driven from the
// deviation primitive (D-026) for liveliness plus the absolute energy so a
// playing-but-steady instrument still stretches.
static float strandModFromStem(float energy, float energyDev) {
    return 0.40 + 1.40 * clamp(energy + 0.60 * max(0.0, energyDev), 0.0, 1.15);
}

vertex DragonStrandVertexOut dragon_bloom_strand_vertex(
    uint                    vid   [[vertex_id]],
    uint                    iid   [[instance_id]],
    constant FeatureVector& f     [[buffer(0)]],
    constant StemFeatures&  stems [[buffer(1)]]
) {
    float s = float(vid) / float(kStrandSamples - 1);   // sample ∈ [0, 1]
    float t = f.time;
    int   strand = int(iid);                            // 0=drums, 1=bass, 2=vocals

    // Per-strand: stem drive, source rotation rates, dominant colour channel.
    float  stemE, stemD;
    float3 ang;                                         // (xang, yang, zang)
    int    dom;                                         // dominant colour channel index
    if (strand == 0) {                                  // DRUMS  → source wave_0
        stemE = stems.drums_energy;  stemD = stems.drums_energy_dev;
        ang   = float3(t * 0.672, t * -1.351, t * -0.401);
        dom   = 0;
    } else if (strand == 1) {                           // BASS   → source wave_1
        stemE = stems.bass_energy;   stemD = stems.bass_energy_dev;
        ang   = float3(t * -0.321, t * 1.531, t * -0.101);
        dom   = 1;
    } else {                                            // VOCALS → source wave_2
        stemE = stems.vocals_energy; stemD = stems.vocals_energy_dev;
        ang   = float3(t * 0.221, t * -0.411, t * 1.201);
        dom   = 2;
    }
    float modK = strandModFromStem(stemE, stemD);

    // ── per_point geometry (source.milk verbatim) ───────────────────────────
    float sp  = s * kStrandSP;
    float env = sin(s * M_PI_F);                        // sin(sample·π) end taper
    float ox  = 0.5 * sin(sp) * env * kStrandVol;
    float oy  = s * modK;
    float oz  = 0.5 * cos(sp) * env * kStrandVol;

    float cz = cos(ang.z), sz = sin(ang.z);
    float cy = cos(ang.y), sy = sin(ang.y);
    float cx = cos(ang.x), sx = sin(ang.x);
    float mx, my, mz;
    mx = ox * cz - oy * sz; my = ox * sz + oy * cz; ox = mx; oy = my;        // rot Z
    mx = ox * cy + oz * sy; mz = -ox * sy + oz * cy; ox = mx; oz = mz;       // rot Y
    my = oy * cx - oz * sx; mz = oy * sx + oz * cx; oy = my; oz = mz;        // rot X

    oz = fabs(oz) - 2.0;                                // the fold → bilateral symmetry
    float x = ox * kStrandFov / oz + 0.5;
    x = (x - 0.5) * 0.75 + 0.5;                         // source horizontal squish (4:3)
    float y = oy * kStrandFov / oz + 0.5;

    // ── per_point colour (source.milk): dominant channel = 1+sin(sp) (HDR),
    //    the other two = 0.5±0.5·sin/cos(sample·1.57). Alpha from depth. ──────
    float bright = 1.0 + sin(sp);                       // [0, 2] — HDR glow channel
    float cS = 0.5 + 0.5 * sin(s * 1.5708);
    float cC = 0.5 + 0.5 * cos(s * 1.5708);
    float3 col = (dom == 0) ? float3(bright, cC, cS)
               : (dom == 1) ? float3(cS, bright, cC)
                            : float3(cC, cS, bright);
    float alpha = 0.5 + (oz + 2.0) * 0.25;

    DragonStrandVertexOut o;
    // Screen (x,y)∈[0,1] → clip. Flip Y: Milkdrop is bottom-up, the scene texture
    // is top-left origin (sampled by mv_warp as uv). Verified against the live
    // butterchurn oracle.
    o.position  = float4(x * 2.0 - 1.0, 1.0 - y * 2.0, 0.0, 1.0);
    o.color     = float4(col, alpha);
    o.pointSize = 1.5;
    return o;
}

fragment float4 dragon_bloom_strand_fragment(DragonStrandVertexOut in [[stage_in]]) {
    // Additive blend (configured engine-side: srcRGB=one, dstRGB=one): emit the
    // HDR strand colour pre-weighted by the per-point alpha so faint near-end
    // points contribute less. Glow > 1 is intentional (tonemapped downstream).
    return float4(in.color.rgb * in.color.a, in.color.a);
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

    // ── (layer × primitive × timescale) routing table ────────────────────────
    // Empirically grounded by the 2026-06-02 BUG-025 A/B liveness measurement
    // (frame-to-frame stddev, LF "Atlas" vs muted Spotify session). Each warp
    // channel reads a primitive that is alive on BOTH paths:
    //   pf.zoom  (outward bleed)   ← bass (Layer-1, stddev 0.10) + signed bass_rel
    //   pf.rot   (swirl)           ← spectralFlux (stddev 0.15–0.22)
    //   q1 feather-flow magnitude  ← spectralFlux (was mid_att_rel ≈ 0 → frozen)
    //   q3 radial-breathing impulse← signed bass_rel (was bass_dev ≈ 0 → dead)
    // The earlier Spike-1 routing read mid_att_rel + bass_dev, both ≈ 0 on
    // bass-dominant music, so the feathers never flowed and the bloom looked
    // static. See the fragment-side driver block for the same diagnosis.
    float bassAbs = f.bass;
    float bassRel = f.bass_rel;        // SIGNED — alive on both paths
    float flux    = f.spectral_flux;   // spectral change — feather flow driver

    // pf.zoom > 1 ⇒ vertex samples a slightly inward UV ⇒ trails push outward.
    // Layer-1 bass is the steady bleed; signed bass_rel modulates it ± so the
    // bloom breathes outward on bass hits and settles inward between them.
    pf.zoom  = kMVWarpBaseZoom
             + bassAbs * 0.008                       // continuous breath
             + max(0.0, bassRel) * kMVWarpZoomGain;  // extra push on above-avg bass

    // Swirl from spectral change — feathers gain rotational energy when the
    // texture of the sound shifts. Flux is alive on both paths (unlike mid).
    pf.rot   = flux * kMVWarpRotGain;

    // Decay = source.milk fDecay (0.95). VisualizerEngine also feeds the JSON
    // `decay` field to setMVWarpDecay so the compose pass matches — keep these
    // two values aligned (both 0.945 here / in DragonBloom.json).
    pf.decay = kMVWarpBaseDecay;

    // Q-channels pass per-frame audio to mvWarpPerVertex.
    pf.q1 = flux;                  // feather flow magnitude (alive on both paths)
    pf.q2 = bassAbs;               // continuous presence (reserved)
    pf.q3 = max(0.0, bassRel);     // radial breathing impulse on above-avg bass
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
