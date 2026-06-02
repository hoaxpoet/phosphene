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
    // L1 (D-137): the bloom is now the three additive spectral STRANDS drawn on
    // top of this pass (`dragon_bloom_strand_vertex`, wired via setSceneGeometry)
    // — each strand driven by a stem (drums/bass/vocals). This fullscreen fragment
    // just lays a near-black ground with a soft corner vignette so the mv_warp
    // accumulator has a quiet base and the strands read against it.
    //
    // The Spike-1/2 polar ring + the D-136 bilateral fold are RETIRED here: the
    // strands carry their own bilateral symmetry (the `oz = abs(oz)` fold in the
    // per-point math), so the fragment no longer draws or folds a waveform curve.
    // `fft`/`wv`/`stems`/`f` stay bound for later layers (L5 palette).
    float2 uv       = in.uv;
    float  r        = length(uv - float2(kBloomCentreX, kBloomCentreY));
    float  vignette = 1.0 - smoothstep(0.55, 1.05, r);
    return float4(kBackgroundColor * vignette, 1.0);
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
// Per-point additive brightness scale. The mv_warp compose weights each frame's
// scene by (1−decay) and accumulates over the decay window to ≈1× at steady
// state, and the dense helix piles many points per pixel near the centre — so
// the raw `1+sin(sp)` colour (up to 2) saturates to white without a strong dim.
// 0.13 keeps the accumulated bloom below clip while still reading as glow.
constant float kStrandBrightness = 0.13;

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
    // bModWaveAlphaByVolume analog (source.milk =1): each strand's alpha scales
    // with ITS instrument's energy, so a quiet/absent instrument fades its strand
    // (musical — each arm tracks its stem) and at silence the strands don't pile
    // densely at the shared centre and clip to white.
    float volGate = clamp(stemE * 1.6, 0.0, 1.0);
    float alpha = (0.5 + (oz + 2.0) * 0.25) * volGate;

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
    // strand colour pre-weighted by the per-point alpha (faint near-end points
    // contribute less) and the global dim that keeps feedback accumulation below
    // clip. The colour ratios (dominant `1+sin(sp)` channel) survive the scale,
    // so the per-strand hue identity is preserved.
    float w = in.color.a * kStrandBrightness;
    return float4(in.color.rgb * w, w);
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
