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

// MV-warp baseline — faithful to source.milk fDecay=0.950. Stability/fill come
// from the inward baseline zoom (0.99951, in mvWarpPerVertex) + the warp transfer
// + video-echo mirror, NOT from inflating decay. Must match DragonBloom.json decay
// + the compose-pass decay.
constant float kMVWarpBaseDecay  = 0.950;
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

constant int   kStrandSamples = 1536;    // points per strand. Source uses 512, but the
                                         // spiral frequency (sp = sample·1286) is badly
                                         // under-sampled at 512 → the line strip aliases into
                                         // a moire "pixelated" pattern (Matt M7). 1536 (3×)
                                         // resolves the spiral into smooth feathered strands.
constant float kStrandSP      = 6.28 * 8.0 * 8.0 * 4.0;   // 1285.76 — source `sample*6.28*8*8*4`
constant float kStrandVol     = 0.2;     // source's final `vol = .2`
constant float kStrandFov     = 0.5;     // source's `fov = .5`
// CUSTOM-wave alpha = per_point a × modVol (butterchurn drawCustomWaveform path).
// fWaveAlpha=4.100 is the BUILT-IN waveform alpha (per_frame sets wave_a=0, so the
// built-in waveform is off) — it does NOT apply to the custom waves. The custom-wave
// per-point a (0.5+(oz+2)*0.25) is the literal alpha; no extra brightness scale.
// Audio boost: butterchurn feeds its analyser 6×-boosted audio (the recorded tap is
// ~−18 dB — reference README). bModWaveAlphaByVolume's 0.71/1.30 bounds assume that
// boosted scale, so Phosphene's raw stem energies must be boosted the same 6× before
// the volume ramp — otherwise quiet real stems gate the waves to ~0.
constant float kAudioBoost    = 6.0;

// ── D-137 music-response uplift ───────────────────────────────────────────────
// Tumble speed scale on energy-weighted time (accumulated_audio_time ≈ 9% of
// wall-clock; ×11 ≈ the prior wall-clock tumble speed on average, but now pausing
// at silence and quickening with energy — FA #33).
constant float kTumbleRate    = 11.0;
// Per-arm transient flare gain — each strand brightens on its instrument's
// deviation (D-026). Accent on top of the continuous volume ramp; kept modest so
// continuous energy stays the primary driver (Audio Data Hierarchy).
constant float kStrandFlare   = 0.60;

struct DragonStrandVertexOut {
    float4 position [[position]];
    float4 color;                 // rgb (HDR, may exceed 1) + additive weight in .a
    float  pointSize [[point_size]];
};

// Strand length `mod`, faithful to source: `mod = if(below(band_att,1.8), band_att+.2, 2)`
// — grows with the instrument's energy, capped at 2. Phosphene drives it per-stem
// (the D-137 uplift; each arm tracks its instrument). The stem energy (~0..0.7) is
// scaled to a Milkdrop band_att-like range (~0..2) so the faithful formula applies;
// deviation (D-026) adds transient liveliness.
static float strandModFromStem(float energy, float energyDev) {
    float bandAtt = (energy + 0.5 * max(0.0, energyDev)) * 3.0;   // → ~Milkdrop band_att scale
    return (bandAtt < 1.8) ? (bandAtt + 0.2) : 2.0;
}

vertex DragonStrandVertexOut dragon_bloom_strand_vertex(
    uint                    vid   [[vertex_id]],
    uint                    iid   [[instance_id]],
    constant FeatureVector& f     [[buffer(0)]],
    constant StemFeatures&  stems [[buffer(1)]]
) {
    float s = float(vid) / float(kStrandSamples - 1);   // sample ∈ [0, 1]
    // Tumble on ENERGY-WEIGHTED time, not wall-clock (FA #33: free-running sin(time)
    // motion reads mechanical / disconnected from the music). accumulated_audio_time
    // advances with audio energy (≈9% of wall-clock at steady state) and PAUSES at
    // silence — so the bloom tumbles faster through energetic passages and stills
    // when the track drops out. ×kTumbleRate restores a wall-clock-comparable speed
    // on average while keeping the energy coupling.
    float t = f.accumulated_audio_time * kTumbleRate;
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

    // Per-strand: stem drive + source rotation rates (wave_0/1/2_per_point xang/yang/zang).
    float  stemE, stemD;
    float3 ang;                                         // (xang, yang, zang)
    if (strand == 0) {                                  // DRUMS  → source wave_0
        stemE = stems.drums_energy;  stemD = stems.drums_energy_dev;
        ang   = float3(t * 0.672, t * -1.351, t * -0.401);
    } else if (strand == 1) {                           // BASS   → source wave_1
        stemE = stems.bass_energy;   stemD = stems.bass_energy_dev;
        ang   = float3(t * -0.321, t * 1.531, t * -0.101);
    } else {                                            // VOCALS → source wave_2
        stemE = stems.vocals_energy; stemD = stems.vocals_energy_dev;
        ang   = float3(t * 0.221, t * -0.411, t * 1.201);
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

    // ── FAITHFUL per-strand colour (source.milk wave_*_per_point39..42) ────────
    // The three waves are NOT white — each injects an R/G/B-DOMINANT colour. The
    // dominant channel is `1+sin(sp)` (range [0,2], HDR); the other two are
    // 0.5±0.5·sin/cos(sample·1.57). These coloured injections + the warp transfer
    // + the comp invert are what produce the reference's CYCLING warm palette
    // (the whole field rotates through hues over time — green/orange/red/magenta).
    //   wave_0 (drums) : r=1+sin(sp), g=0.5+0.5cos(s·1.57), b=0.5+0.5sin(s·1.57)
    //   wave_1 (bass)  : g=1+sin(sp), r=0.5+0.5sin,         b=0.5+0.5cos
    //   wave_2 (vocals): b=1+sin(sp), g=0.5+0.5sin,         r=0.5+0.5cos
    float sc  = s * 1.57;                       // source sample*1.57 (≈ π/2)
    float hi  = 1.0 + sin(sp);                  // dominant channel, [0, 2]
    float los = 0.5 + 0.5 * sin(sc);
    float loc = 0.5 + 0.5 * cos(sc);
    float3 col = (strand == 0) ? float3(hi,  loc, los)    // wave_0 red-dominant
               : (strand == 1) ? float3(los, hi,  loc)    // wave_1 green-dominant
                               : float3(loc, los, hi);     // wave_2 blue-dominant
    // FAITHFUL additive weight (butterchurn customwave path), no invented knobs:
    //   per_point a   = 0.5 + (oz+2)*0.25            (source wave_*_per_point42)
    //   modVol        = clamp((vol·6 − 0.71)/(1.30−0.71), 0, 1)   (bModWaveAlphaByVolume
    //                   with fModWaveAlphaStart/End, on 6×-boosted audio — see kAudioBoost)
    //   alpha         = fWaveAlpha(4.1) × a × modVol
    // Drawn additively (SRC_ALPHA,ONE) into the float scene. `vol` is the per-stem
    // energy (the D-137 uplift — each arm's volume is its instrument's energy).
    float pointA = 0.5 + (oz + 2.0) * 0.25;
    float modVol = clamp((stemE * kAudioBoost - 0.71) / (1.30 - 0.71), 0.0, 1.0);
    // Per-arm TRANSIENT FLARE (D-137 uplift): each arm brightens on its own
    // instrument's transient (deviation primitive, D-026) — the drums-arm flares on
    // each kick, the bass-arm on each bass hit, the vocals-arm on vocal attacks. So
    // the alpha = slow volume ramp (modVol) + a per-hit flare. With the no-decay
    // feedback the flare blooms outward and smears — a pulse you can point at. Layer
    // hierarchy: continuous energy (modVol) is primary; the dev flare is the accent.
    float flare  = 1.0 + kStrandFlare * max(0.0, stemD);
    float alpha  = clamp(pointA * modVol * flare, 0.0, 1.0);

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
    // butterchurn customwave blend (bAdditive=0) = SRC_ALPHA, ONE_MINUS_SRC_ALPHA.
    // The engine binds that blend, so emit the raw per-point colour + alpha (NOT
    // premultiplied) and let the blend composite col·a + dst·(1−a). col is the
    // per-point r/g/b (dominant channel up to 2), alpha = per_point_a·modVol.
    return float4(in.color.rgb, in.color.a);
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
    // source.milk per_pixel warp, on the 32×24 vertex mesh — which is exactly how
    // butterchurn/Milkdrop compute it (`warpUVs` per mesh vertex, interpolated). It
    // was briefly moved to a per-FRAGMENT recompute for sharper petals, but that
    // diverges from the source's mesh AND costs trig per pixel; the mesh is faithful
    // and cheaper, and the strands (drawn full-res on top) carry the fine detail.
    //   per_pixel_1: it   = 0.3*sin(time*0.2)
    //   per_pixel_3: rot  = 0.02*sin((rad*0.5 + it)*20)     // concentric rotation
    //   per_pixel_4-6: mod = sin(ang*5)^5; zoom = (1+|0.01*mod|)*0.99951 (inward base)
    // The 0.99951 inward baseline is load-bearing for stability (FA: prevents the
    // field draining off-edge / white-collapse). The source's audio-zoom term
    // (per_pixel_8) is reformulated as BREATHING: the whole bloom expands on loud
    // bass and settles when it thins — the primary continuous response (D-137).
    float t    = f.time;
    float it   = 0.3 * sin(t * 0.2);
    float rotA = 0.02 * sin((rad * 0.5 + it) * 20.0);
    float md   = sin(ang * 5.0);
    md = md * md * md * md * md;                              // ^5
    float z    = (1.0 + fabs(0.01 * md)) * 0.99951;
    z *= clamp(1.0 + 0.06 * (f.bass * 6.0 - 1.0), 0.97, 1.07);  // breathing (bass, 6×-boosted)

    float2 centre = float2(0.5, 0.5);
    float2 p      = uv - centre;
    float2 zp     = p / max(z, 0.001);
    float  c      = cos(rotA);
    float  sn     = sin(rotA);
    return float2(c * zp.x - sn * zp.y, sn * zp.x + c * zp.y) + centre;
}
