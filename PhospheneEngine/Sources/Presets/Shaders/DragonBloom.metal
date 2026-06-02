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
    // L2 (D-137): 6 instances = 3 stems × {original, vertical-axis mirror}. The
    // raw tumbling strands are NOT bilaterally symmetric, and the source's
    // per_pixel warp does not symmetrise them (verified empirically). The
    // reference unmistakably reads as a bilaterally-symmetric petal bloom, so we
    // GUARANTEE it the Spike-2-validated way: mirror the brush about the vertical
    // axis (reflect the projected x). The per_pixel warp keeps the feathered
    // texture rich (symmetric FORM, non-identical TEXTURE — the FA #48 mitigation
    // Matt confirmed reads as symmetric). The mirror also doubles the petals.
    int  strand = int(iid % 3);                         // 0=drums, 1=bass, 2=vocals
    bool mirror = iid >= 3;

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

    oz = fabs(oz) - 2.0;                                // source z fold
    float x = ox * kStrandFov / oz + 0.5;
    x = (x - 0.5) * 0.75 + 0.5;                         // source horizontal squish (4:3)
    float y = oy * kStrandFov / oz + 0.5;
    if (mirror) { x = 1.0 - x; }                        // L2: vertical-axis mirror → bilateral symmetry

    // ── L5: warm fiery per-stem palette (D-137) ───────────────────────────────
    // Replaces source.milk's R/G/B-dominant wave colours with warm hues so the
    // bloom reads fiery — the reference's defining trait. Per-stem identity:
    // drums = orange, bass = ember-red, vocals = gold. valence + spectral_centroid
    // shift overall warmth (hotter on bright/positive music). The L3 chromatic
    // transfer bleeds the warm (R-heavy) cores partly toward green → the
    // reference's "warm fiery with green accents" read. The source's `sin(sp)`
    // glow striping is preserved as a brightness modulation along the strand.
    float3 warmHue = (dom == 0) ? float3(1.00, 0.42, 0.12)   // drums  — fiery orange
                   : (dom == 1) ? float3(0.95, 0.20, 0.06)   // bass   — ember red
                                : float3(1.00, 0.74, 0.20);  // vocals — gold
    float warmth = clamp(0.80 + 0.40 * f.valence + 0.30 * (f.spectral_centroid - 0.5), 0.45, 1.35);
    float glow   = 0.55 + 0.45 * sin(sp);                    // source bright striping → [0.1, 1.0]
    float3 col   = warmHue * glow * warmth;
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

    // L2 (D-137): the warp is now computed fully PER-PIXEL in mvWarpPerVertex
    // (the faithful source.milk per_pixel 5-fold petal zoom + concentric
    // rotation). The only per-frame value the engine still needs is the decay,
    // which the compose pass consumes. The Spike-1 per-frame zoom/rot/q-channel
    // routing is retired (it drove the now-removed ring warp). Decay = source
    // fDecay; keep aligned with DragonBloom.json `decay` (both 0.945) so the
    // compose blend Σ(1−d)·d^n = 1 holds.
    pf.zoom  = 1.0;
    pf.rot   = 0.0;
    pf.decay = kMVWarpBaseDecay;
    pf.q1 = 0.0; pf.q2 = 0.0; pf.q3 = 0.0; pf.q4 = 0.0;
    pf.q5 = 0.0; pf.q6 = 0.0; pf.q7 = 0.0; pf.q8 = 0.0;
    return pf;
}

float2 mvWarpPerVertex(
    float2 uv, float rad, float ang,
    thread const MVWarpPerFrame& pf,
    constant FeatureVector& f,
    constant StemFeatures& stems
) {
    // ── L2: source.milk per_pixel warp (D-137) ────────────────────────────────
    // Faithful port of the preset's per-pixel feedback warp — the layer that
    // folds the tumbling strands into the bilaterally-symmetric PETAL bloom.
    // Verbatim from source.milk per_pixel_1..8:
    //   it   = 0.3*sin(time*0.2)
    //   rot  = 0.02*sin((rad*0.5 + it)*20)          // concentric rotation rings
    //   mod  = sin(ang*5)^5                          // sharp 5-LOBE angular fn
    //   zoom = (1 + |0.01*mod|) * min(1.05, max(1, max(bass,treb)))
    // The 5-fold angular zoom is what pulls the feedback outward into a small
    // number of distinct petals (Spike-1's uniform zoom could only fuzz a ring);
    // because `zoom` depends on ang only through sin(ang·5)^5 it is symmetric
    // across the axes → the petal form is bilaterally symmetric. The audio
    // multiplier is faithful to source; on Phosphene's AGC scale bass/treble
    // rarely exceed 1, so it sits ≈1 — the warp is FORM, the strands (L1) carry
    // the audio (one primitive per layer). pf is unused here (its per-frame
    // decay is consumed by the compose pass); the warp is fully per-pixel.
    float t    = f.time;
    float it   = 0.3 * sin(t * 0.2);
    float rotA = 0.02 * sin((rad * 0.5 + it) * 20.0);
    float md   = sin(ang * 5.0);
    md = md * md * md * md * md;                        // ^5
    float zoom = 1.0 + fabs(0.01 * md);
    zoom *= min(1.05, max(1.0, max(f.bass, f.treble)));

    float2 centre = float2(0.5, 0.5);
    float2 p      = uv - centre;
    // zoom > 1 ⇒ sample inward ⇒ accumulated content flows outward (Milkdrop
    // convention; same idiom as the retired base-zoom path).
    float2 zp = p / max(zoom, 0.001);
    float  c  = cos(rotA);
    float  s  = sin(rotA);
    return float2(c * zp.x - s * zp.y, s * zp.x + c * zp.y) + centre;
}
