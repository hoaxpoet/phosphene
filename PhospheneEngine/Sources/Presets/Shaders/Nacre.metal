// Nacre.metal — faithful port of the Milkdrop/butterchurn builtin
// `$$$ Royal - Mashup (431)` (projectM cream-of-crop legends; the iridescent
// "jello-mirror" refractive cell-field). See docs/presets/NACRE_PLAN.md +
// docs/VISUAL_REFERENCES/nacre/ (source_shaders.txt = the literal port artifact).
//
// Character (faithful to (431)): a molten iridescent-metal / oil-on-water field —
// gold-green viscous base, reaction-diffusion crinkle, chromatic-fringed refractive
// rims, a bright pulsing central core, on a near-black ground; the field breathes +
// slowly roams and the palette rotates (green→teal→violet→red) on a slow time bed.
// A DIFFERENT register from Dragon Bloom ((220)) despite the shared author/name.
//
// ── Render loop (RenderPipeline+Nacre.swift, the D-138 structure ported wholesale,
//    FA #70) ──────────────────────────────────────────────────────────────────────
//   warp(prev) → composeTexture   (custom feedback warp; bakes its own 0.9 decay,
//                                   inline unsharp, treble grain, palette-tinted core
//                                   seed, slight desat — replaces the waveform draw)
//   comp(compose) → drawable       (the signature look; DISPLAY-ONLY, never fed back —
//                                   radial-pulse emboss rims → chromatic-dispersion
//                                   filaments + sine-cell field + slow colour roam)
//   swap warpTexture ↔ composeTexture
//
// The functions are looked up by name by PresetLoader.makeWarpPipelines when the
// preset's fragment_function prefix is `nacre`:
//   · nacre_fragment          — near-black placeholder (loader needs a fragment_function;
//                               the seed lives in the warp, so this is unused at draw time)
//   · nacre_warp_fragment     — the custom feedback warp (unsharp + decay + grain + seed)
//   · nacre_comp_fragment      — the signature look (display-only)
// Every OTHER preset's library lacks `nacre_*` symbols → falls back to the shared
// mvWarp_* defaults (gating is structural; PresetRegression confirms byte-identity).
//
// SceneUniforms / MVWarpPerFrame / WarpVertexOut / VertexOut / fullscreen_vertex /
// FeatureVector / StemFeatures / warpSampler come from the mvWarp preamble + Common.metal.
//
// ── INCREMENT STATUS ──────────────────────────────────────────────────────────
// NACRE.2b (THIS FILE): the FAITHFUL BASE — port (431)'s warp + comp + seed verbatim.
//   Faithful audio (all inherited from the source): mid→zoom breath, bass-onset→field
//   kick, treble→grain. The 3 greenlit 2026 UPLIFTS (stem-instrument routing, real
//   thin-film iridescence, smooth-Voronoi cells) are deferred to NACRE.3+ — AFTER
//   Matt's live M7 confirms the faithful base reads as (431) (kickoff §7; FA #65 —
//   do not subtract from / pre-empt the reference before it's proven).

// MARK: - NacreUniforms (CPU-computed per frame; matches NacreUniforms in Swift)
//
// Bound at fragment buffer(1) of BOTH the warp and comp passes (the FM pattern).
// Carries the (431) builtins those shaders reference: time (palette + grain scroll +
// radial-pulse phase), the treble grain gate, the feedback texel size + aspect (comp
// sobel offsets + cell scale), and the fixed per-load randoms + slow colour roam.
// 112 bytes — see NacreUniforms in RenderPipeline+Nacre.swift for the byte layout.
struct NacreUniforms {
    float  time;         // features.time — palette rotation, grain scroll, radial-pulse phase
    float  trebleGrain;  // max(0, trebleDev) — gates the warp grain (faithful treb_att route)
    float  coreEnergy;   // STEADY total energy — gates the warp's core SEED (faithful modwavealphabyvolume)
    float  hueShift;     // TONAL.3 R2: the FULL palette phase (seconds) — harmony position (consonance-gated) + demoted clock drift
    float2 texel;        // (1/feedbackW, 1/feedbackH) — comp luminance-sobel offsets (texsize.zw)
    float  barPush;      // NACRE.4: downbeat envelope → display-stage camera push (connection as visible motion)
    float  spin;         // NACRE.3: energy → continuous warp rotation (rad/frame; turning ← music)
    float4 aspect;       // (aspectx, aspecty, 1/aspectx, 1/aspecty) — comp cell aspect
    float4 randPreset;   // fixed per-load random vec4 (the comp's tint + dz scale character)
    float4 slowRoamSin;  // [0.5+0.5 sin(t·{slow})] — comp slow colour roam (subtractive)
    float4 roamCos;      // [0.5+0.5 cos(t·{slow})] — comp slow colour roam (subtractive)
    float4 tonal;        // TONAL.3 (D-178): x=palette desaturate (consonance-gated). y,z,w spare (y reserved for the deferred tension→dispersion route)
};

// MARK: - Constants

// Feedback warp. (431): zoom 1.009 (slight zoom-in), in-warp decay 0.9, unsharp 0.3.
constant float kNacreDecay      = 0.88;    // (431) warp `ret = ret*0.9` (baked); trimmed 0.90→0.88 to
                                           // shorten the feedback TRAILS (the "smeary" half) — shorter
                                           // persistence = shorter streaks. The grain sustains the field.
constant float kNacreUnsharp    = 0.25;    // (431) warp `ret + (ret - blur)*0.3`. Governs cell contrast;
                                           // too high → fine flecks, too low → washed/structureless
constant float kNacreBlurSpread = 5.0;     // unsharp blur radius (texels). WIDE = big smooth cells; the
                                           // source's 3-level pyramid is wide — a narrow blur shatters cells
constant float kNacreBaseZoom   = 1.004;   // (431) baseVals.zoom was 1.009 — halved to TAME the radial
                                           // advection smear (the warp drags everything outward ~0.9%/frame
                                           // at 1.009 → a ~9% radial streak over the decay window; the
                                           // "stretchy/smeary" Matt flagged as present from the base). The
                                           // comp's time-driven radial pulse keeps the expanding character.
constant float kNacreZoomGain    = 0.030;  // mid continuous energy → zoom pump (source `zoom += .1*rg`)
constant float kNacreRotAmp     = 0.020;   // slow roam rotation (source `rot += .01*(...)` sines)
constant float kNacreRoamAmp    = 0.010;   // slow centre roam (source `cx/cy += .21*(...)` sines, scaled down)
constant float kNacreDriftAmp   = 0.002;   // slow translation (source `dx/dy += .003*(...)` sines) —
                                           // halved to reduce the directional smear component
constant float kNacreBassKick   = 0.011;   // bass onset → dx/dy positional jolt (source dx/dy_residual ~.016/.012)

// Palette-coloured SEED (replaces the (431) waveform draw — wave_a 0.001 + wave_r/g/b,
// whose role is to inject fresh palette-coloured content across the frame each frame so
// the field carries the rotating hue and never starves to black under the 0.9 decay).
// A FAINT full-frame wash (colours the whole field the current palette) + a brighter
// central core (the luminous "light through the lenses"). Kept faint so the feedback
// sits mostly DARK (near-black ground; the comp builds the bright cells/rims on top).
constant float  kNacreCoreTight = 18.0;    // luminous core spot — tight enough that a sustained-loud
                                           // section can't flood the frame (it accumulates ~10× via decay)
constant float  kNacreCoreBase  = 0.10;    // central core glow (the "light through the lenses")
// Downbeat camera push (NACRE.4, comp): the music connection as VISIBLE MOTION — the field
// magnifies ~5 % on the downbeat (a forward surge), settling over the bar. Display-stage
// (scales the steady feedback at sample time → no smear). Feel knob.
constant float  kNacrePush      = 0.05;

// Warp grain (the reaction-diffusion churn; source warp noise term, treble-gated).
// SIGNED ±; the [0,1] clamp rectifies the positive half into the churn texture. LOW
// FREQUENCY (kNacreGrainFreq) so it seeds LARGE-scale brightness variation across the
// frame (→ big organic cells everywhere), not a fine high-freq crinkle (→ oil-slick
// flecks; NACRE.2b iteration 1). Smooth value-noise, not a per-pixel hash.
constant float  kNacreGrainAmp  = 0.11;
constant float  kNacreGrainFreq = 5.5;     // grain blobs across the frame — sets the cell scale
constant float  kNacreDesat     = 0.20;    // source warp `mix(ret, luma, 0.2)`

// MARK: - Palette (source per-frame eqs: wave_r/g/b = .85 + .25*sin(k*t + φ))
// The slow green→teal→violet→red rotation. Faithful: tints the SEED (accumulates in
// the feedback), NOT the display (hue-strobing the display is an anti-reference).
static inline float3 nacrePalette(float t) {
    return float3(0.85 + 0.25 * sin(0.437 * t + 1.0),
                  0.85 + 0.25 * sin(0.544 * t + 2.0),
                  0.85 + 0.25 * sin(0.751 * t + 3.0));
}

// Cheap hash + smooth value noise for the warp grain (the source samples a low-freq
// noise texture; inline noise is the portable equivalent — no extra texture binding on
// the warp pass). Value noise (interpolated) gives SMOOTH large-scale blobs at low
// frequency, vs a raw per-pixel hash which is fine and shatters the cells.
static inline float nacreHash(float2 p) {
    return fract(sin(dot(p, float2(12.9898, 78.233))) * 43758.5453);
}

static inline float nacreValueNoise(float2 p) {
    float2 i = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);   // smoothstep interpolation
    float a = nacreHash(i);
    float b = nacreHash(i + float2(1.0, 0.0));
    float c = nacreHash(i + float2(0.0, 1.0));
    float d = nacreHash(i + float2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

constant float3 kLuma = float3(0.32, 0.49, 0.29);   // (431) uses this exact luma weight

// MARK: - Scene fragment (loader placeholder; unused in the Nacre draw branch)
//
// PresetLoader.makeDirectPrimaryPipeline needs a `fragment_function` to build the
// direct pipeline, but the Nacre branch never renders it (the seed is folded into the
// warp). Near-black, like fata_morgana_fragment.
fragment float4 nacre_fragment(VertexOut in [[stage_in]]) {
    return float4(0.0, 0.0, 0.0, 1.0);
}

// MARK: - MV-Warp mesh functions (the per-vertex feedback transform)
//
// Source advection is GENTLE: zoom 1.009 + slow roam (rot/cx/cy/dx/dy sines) + a
// bass-onset translation kick. (The dense mv_x/mv_y 25.6/9.6 grid has mv_a 0 → it is
// the HIDDEN Milkdrop debug-vector overlay; it does NOT advect the image. The plan §4
// "dense motion-vector field advects the feedback" was a misread — verified against
// Milkdrop mv_* semantics, FA #73.) Per-pixel eqs: none.

MVWarpPerFrame mvWarpPerFrame(
    constant FeatureVector& f,
    constant StemFeatures&  stems,
    constant SceneUniforms& s
) {
    MVWarpPerFrame pf;
    float t = f.time;
    // In-warp decay is baked in nacre_warp_fragment; the compose pass is not used on
    // the Nacre branch. pf.decay is informational only.
    pf.decay = kNacreDecay;
    // Mid-band continuous energy → zoom pump (PRIMARY motion; Audio Data Hierarchy).
    // SOFT-SATURATED (tanh) + from the ATTACK-SMOOTHED band (`mid_att_rel`, not the
    // instantaneous `mid_rel`): real-music deviations spike to ~3× (bassDev peak 3.34,
    // session 22-23-55Z), so an un-saturated gain on the raw deviation jerked ~3× harder
    // than tuned and the instantaneous band jolted on every transient. tanh caps the spike
    // to ~1; the att band gives a pump-and-settle envelope — restoring the source's
    // `rg = max(.77*rg, …)` zoom EMA the first port dropped (Matt M7: "jerky, a touch too
    // much"; project_deviation_primitive_real_range — soft-saturate vs p99, never vs 1.0).
    pf.zoom = kNacreBaseZoom + kNacreZoomGain * tanh(max(0.0, f.mid_att_rel));
    // Slow bounded roam (faithful (431) rot/cx/cy/dx/dy sines) — alive at silence.
    pf.rot = kNacreRotAmp * (0.6 * sin(0.381 * t) + 0.4 * sin(0.579 * t));
    pf.cx  = kNacreRoamAmp * (0.6 * sin(0.374 * t) + 0.4 * sin(0.294 * t));
    pf.cy  = kNacreRoamAmp * (0.6 * sin(0.393 * t) + 0.4 * sin(0.223 * t));
    // Slow drift + bass-onset positional kick (source dx/dy_residual = .016*sin(7t),
    // .012*sin(9t) latched on a bass threshold-crossing, decaying ~.96/frame). Driven off
    // the SOFT-SATURATED, ATTACK-SMOOTHED bass band so the lurch SWELLS-and-settles (gentle
    // sway) instead of the instantaneous 6%-of-frame jerk the first port produced on a hard
    // bass hit — the source's threshold-decay envelope, restored. Layer 4 (bounded).
    float kick = kNacreBassKick * tanh(max(0.0, f.bass_att_rel));
    pf.dx = kNacreDriftAmp * (0.6 * sin(0.234 * t) + 0.4 * sin(0.277 * t)) + kick * sin(7.0 * t);
    pf.dy = kNacreDriftAmp * (0.6 * sin(0.284 * t) + 0.4 * sin(0.247 * t)) + kick * sin(9.0 * t);
    pf.warp = 0.0;   // source warp 0.00054 — negligible, omitted (ponytail: a value that never matters)
    pf.sx = 1.0; pf.sy = 1.0;
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
    float2 centre = float2(0.5 + pf.cx, 0.5 + pf.cy);
    float2 p      = uv - centre;
    // Zoom IN (content magnifies / flows outward): sample prev at a contracted radius.
    p = p / max(pf.zoom, 0.001);
    // Slow rotation about the roaming centre.
    float c = cos(pf.rot), sn = sin(pf.rot);
    float2 rp = float2(c * p.x - sn * p.y, sn * p.x + c * p.y) + centre;
    // Translation (slow drift + bass kick).
    return rp + float2(pf.dx, pf.dy);
}

// MARK: - Custom WARP fragment (the feedback transfer — the reaction-diffusion churn)
//
// Verbatim transcription of (431)'s WARP shader body (source_shaders.txt §WARP),
// with the seed folded in (see the file header). Order, faithful to the source:
//   ret = main(uv)                                              // warped prev feedback
//   ret = ret + (ret - blur)*0.3                                // unsharp-mask sharpen
//   ret = ret * 0.9                                             // baked decay
//   ret = ret + grain*(clamp(treb-1,0,1)*0.4 + 0.3)            // treble-gated churn noise
//   ret = ret + palette-tinted central core seed               // (== the wave_a 0.001 draw)
//   ret = mix(ret, luma(ret), 0.2)                             // slight desaturate
//
// The blur pyramid (source samples blur1/2/3 weighted 0.3/0.4/0.3) is approximated by
// a single inline 9-tap gaussian of `prev` — the unsharp MECHANIC (edge-preserving
// feedback sharpen) is preserved; the 3 separate mip levels are a refinement deferred
// pending M7 (NACRE_PLAN §9; add a blur-of-prev target FM-style only if the field reads
// mushy). Documented deliberate simplification — ponytail: one inline tap before three
// render targets.
fragment float4 nacre_warp_fragment(
    WarpVertexOut          in   [[stage_in]],
    texture2d<float>       prev [[texture(0)]],
    constant NacreUniforms& nu  [[buffer(1)]]
) {
    float2 uv = in.warped_uv;
    // Energy-driven continuous spin (NACRE.3, turning ← music). Rotate the feedback sample
    // about centre by nu.spin rad on top of the vertex advection; because we sample the
    // already-spun `prev`, the rotation ACCUMULATES → a continuous swirl whose RATE rises with
    // the music. Display medium = motion (Matt M7: brightness was bothersome). uv-space (like
    // the vertex rotation) — the blobby molten field shows no aspect skew.
    if (nu.spin > 0.0) {
        float2 d = uv - 0.5;
        float cs = cos(nu.spin), ss = sin(nu.spin);
        uv = float2(cs * d.x - ss * d.y, ss * d.x + cs * d.y) + 0.5;
    }
    float3 c  = prev.sample(warpSampler, uv).rgb;

    // Inline gaussian blur of `prev` for the unsharp high-pass. WIDE radius
    // (kNacreBlurSpread texels) to stand in for the source's blur1/2/3 pyramid width —
    // the blur width governs cell scale (wide → big smooth membranes; narrow → flecks).
    // 3×3 separable weights 1-2-1.
    float2 s = nu.texel * kNacreBlurSpread;
    float3 blur = c * 4.0;
    blur += (prev.sample(warpSampler, uv + float2( s.x, 0)).rgb +
             prev.sample(warpSampler, uv + float2(-s.x, 0)).rgb +
             prev.sample(warpSampler, uv + float2(0,  s.y)).rgb +
             prev.sample(warpSampler, uv + float2(0, -s.y)).rgb) * 2.0;
    blur += (prev.sample(warpSampler, uv + float2( s.x,  s.y)).rgb +
             prev.sample(warpSampler, uv + float2(-s.x,  s.y)).rgb +
             prev.sample(warpSampler, uv + float2( s.x, -s.y)).rgb +
             prev.sample(warpSampler, uv + float2(-s.x, -s.y)).rgb);
    blur *= (1.0 / 16.0);

    c = c + (c - blur) * kNacreUnsharp;   // unsharp-mask sharpen
    c = c * kNacreDecay;                  // baked decay

    // Treble-gated churn grain (source: a scrolling low-freq noise, scaled by
    // clamp(treb_att-1,0,1)*0.4 + 0.3). Smooth value-noise at LOW frequency so it seeds
    // large-scale brightness blobs (→ big cells), scrolling slowly via nu.time.
    float grain = nacreValueNoise(in.uv * kNacreGrainFreq + nu.time * 0.15) - 0.5;
    float gate  = clamp(nu.trebleGrain, 0.0, 1.0) * 0.4 + 0.3;
    c += grain * kNacreGrainAmp * gate;

    // Palette-coloured central core seed (the luminous lens-light; the zoom advects it
    // outward into expanding palette-coloured rings → spreads the rotating hue across the
    // field while leaving darker gaps, so the ground stays near-black). VOLUME-GATED
    // (faithful modwavealphabyvolume + the musical role: core brightness ← overall
    // energy): faint at silence (the field is a dim iridescent churn, never flooding the
    // ground), bright with audio (the hero luminous core pulses with the music).
    float  r        = length(in.uv - 0.5);
    // STEADY warp core seed (nu.coreEnergy = total energy): faithful modwavealphabyvolume,
    // the no-smear "looks good" level. The voice DYNAMIC moved to the comp's display-stage
    // glow (it flared + smeared when it lived here, in the fed-back warp — NACRE.3).
    float  coreGate = 0.22 + 0.75 * clamp(nu.coreEnergy, 0.0, 1.0);
    float  core     = exp(-r * r * kNacreCoreTight) * kNacreCoreBase * coreGate;
    // Palette phase is now the FULL harmony-set phase (TONAL.3 round 2): `nu.hueShift` carries
    // the key's position on the wheel (holds on a vamp) plus a demoted clock drift, computed
    // CPU-side. The seed carries the palette into the feedback, so the whole field's hue is
    // positioned by the harmony. (nu.time still drives the grain scroll + radial pulse.)
    c += core * nacrePalette(nu.hueShift);

    // Slight desaturate toward luma (source warp final step). TONAL.3: the amount is
    // consonance-gated (nu.tonal.x) — atonal / percussive passages desaturate toward the
    // neutral rest state, tonal passages keep the faithful (431) 0.20.
    c = mix(c, float3(dot(c, kLuma)), nu.tonal.x);

    // Clamp to [0,1] — the source stores the feedback to an 8-bit UNORM target (butterchurn
    // clamps each frame); replicating that bounds the unsharp+grain accumulation (an
    // unclamped HDR loop blooms to white — NACRE.2b first render). The rgba16Float buffer
    // is retained for the NACRE.3 iridescence uplift's headroom; today it carries [0,1].
    return float4(clamp(c, 0.0, 1.0), 1.0);
}

// MARK: - Custom COMP fragment (the signature look — DISPLAY ONLY, never fed back)
//
// Verbatim transcription of (431)'s COMP shader body (source_shaders.txt §COMP).
// Four expanding radial-pulse layers (phase = time/18, quarter-offset) sample the
// feedback toward an alternating centre (0.51,0.55)/(0.49,0.55) → a luminance-sobel
// bump field `dz` (the emboss rims) + a max-brightness field `ret1`. Then a
// domain-warped sine-cell field at 3 chromatic dispersions (dz × {1.0,1.4,1.8}) with
// `inversesqrt` filaments → the refractive chromatic rims; combined with rand-tinted
// weights, slow colour roam, and a `ret*(1+ret)` contrast lift.
//
// Substitutions for butterchurn builtins (NACRE_PLAN §4): sampler_main → composeTexture
// (the warped feedback = `main`); texsize.zw → nu.texel; aspect → nu.aspect;
// rand_preset → nu.randPreset (fixed seed); slow_roam_sin/roam_cos → nu.slowRoamSin/
// roamCos (CPU time-driven). A custom comp FULLY REPLACES fixed-function (no
// gamma/echo/invert — D-139).
fragment float4 nacre_comp_fragment(
    VertexOut              in      [[stage_in]],
    texture2d<float>       mainTex [[texture(0)]],
    constant NacreUniforms& nu     [[buffer(1)]]
) {
    constexpr sampler m(filter::linear, address::clamp_to_edge);
    float2 uv = in.uv;
    float2 dxoff = float2(nu.texel.x, 0.0);   // texsize.z, 0
    float2 dyoff = float2(0.0, nu.texel.y);   // 0, texsize.w

    // Downbeat camera push (NACRE.4): contract the view coords on the downbeat so the whole
    // field magnifies (a gentle forward surge), settling over the bar — the music connection
    // as VISIBLE MOTION on the beat (the rhythm that read, in a non-brightness, non-invisible
    // medium). DISPLAY-stage: scales the steady feedback at sample time, never fed back → no
    // smear. nu.barPush is the sharp-attack / bar-decay envelope on the cached downbeat.
    float2 base = (uv - 0.5) * nu.aspect.xy * (1.0 - kNacrePush * nu.barPush);
    float  tph  = nu.time / 18.0;             // radial-pulse phase

    float2 dz   = float2(0.0);
    float3 ret1 = float3(0.0);

    // Four expanding radial-pulse layers (k = 0..3). Centre alternates → horizontal
    // chromatic offset; each weighted by inten = sqrt(dist)*(1-dist)*4.
    for (int k = 0; k < 4; ++k) {
        float dist  = 1.0 - fract(0.25 * float(k + 1) + tph);
        float inten = sqrt(dist) * (1.0 - dist) * 4.0;
        float2 uv_3 = base * nu.aspect.yx;                                  // (uv-0.5)*aspect.xy*aspect.yx
        float2 ctr  = (k % 2 == 0) ? float2(0.51, 0.55) : float2(0.49, 0.55);
        float2 uv3  = ctr + uv_3 * dist;
        // Luminance-sobel of the feedback × inten → the emboss bump field.
        dz.x += inten * (2.0 * dot(mainTex.sample(m, uv3 + dxoff).rgb, kLuma)
                       - 2.0 * dot(mainTex.sample(m, uv3 - dxoff).rgb, kLuma));
        dz.y += inten * (2.0 * dot(mainTex.sample(m, uv3 + dyoff).rgb, kLuma)
                       - 2.0 * dot(mainTex.sample(m, uv3 - dyoff).rgb, kLuma));
        ret1 = max(ret1, mainTex.sample(m, uv3).rgb * inten);
    }
    dz *= (0.5 + nu.randPreset.z);

    // Domain-warped sine-cell field at 3 chromatic dispersions → the refractive rims.
    float2 roff = 2.0 * (nu.randPreset.xy - 0.5);
    float2 uv1  = 4.0 * base;
    float2 s1 = sin((uv1 + dz)        + roff);
    float2 s2 = sin((uv1 + dz * 1.4)  + roff);
    float2 s3 = sin((uv1 + dz * 1.8)  + roff);
    float3 cells = float3(rsqrt(max(dot(s1, s1), 1e-4)),
                          rsqrt(max(dot(s2, s2), 1e-4)),
                          rsqrt(max(dot(s3, s3), 1e-4)));

    // Final combine (source ret_7), verbatim.
    float3 rp = nu.randPreset.xyz;
    float3 ret = (cells * ((float3(0.01) * (1.0 + rp / 2.0)) * (0.5 + nu.randPreset.y)))
                 * (((nu.randPreset.x - 0.5) * 4.0) * ret1 + (8.0 * (1.0 + rp)))
                 - (ret1.x * 0.5) + ((ret1.y + ret1.z) / 3.0);
    // Slow colour roam (source `ret -= (slow_roam_sin.wzy * roam_cos.zxy) * 0.4`).
    float3 roam = float3(nu.slowRoamSin.w, nu.slowRoamSin.z, nu.slowRoamSin.y)
                * float3(nu.roamCos.z, nu.roamCos.x, nu.roamCos.y);
    ret -= roam * 0.4;
    ret  = ret * (1.0 + ret);   // contrast lift

    // [NACRE.3: the display-stage voice GLOW and the downbeat brightness PULSE were both
    //  removed here — Matt M7: "still blindingly bright at some points". The glow added up to
    //  +0.46 at centre on the vocal peaks (session 16-14-24Z) and never registered as a
    //  connection. The energy connection lives in the warp's turning (nu.spin); the comp is
    //  back to the faithful combine + sRGB decode.]

    // sRGB round-trip cancellation (the FM fix, D-139). butterchurn writes to an
    // sRGB-NAIVE canvas (the shader value IS the display value); Phosphene's drawable is
    // .bgra8Unorm_srgb, so Metal would sRGB-ENCODE this return — lifting the near-black
    // ground to a pale grey midtone (NACRE.2b: pale-green wash). Decode here so the
    // target's encode round-trips back to the butterchurn display value, keeping the
    // ground deep black against the bright cells/rims.
    float3 v = saturate(ret);
    float3 lin = select(v / 12.92, pow((v + 0.055) / 1.055, float3(2.4)), v > 0.04045);
    return float4(lin, 1.0);
}
