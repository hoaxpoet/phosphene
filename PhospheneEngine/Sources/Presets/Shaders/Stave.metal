// Stave.metal — the ruled field the traces are plotted on.
//
// Stave's subject — the two beaded traces, the beat verticals, and the stem tint wash — is
// drawn by `StaveTrace` from CPU history rings (see `Renderer/Shaders/StaveTrace.metal` for
// those four passes). This file is ONLY the backdrop, and every term in it is
// audio-INDEPENDENT by design: the ground, the horizon haze, the cloud texture, the star
// sparkles, and the static horizontal rules.
//
// That split is deliberate. The horizontals are "the stave" and are static (L6); the sparkles
// are non-reactive texture (D3); the haze and cloud are the room. None of them needs state or
// a driver, so none of them belongs on the CPU side — and keeping them here means the whole
// audio-independent field is one function that can be read and reasoned about at once.
//
// Read off the reference set:
//   `01_macro_dotted_traces_on_grid.png` — the composition. A HORIZON: hazy atmosphere in the
//        upper half, traces inhabiting a band across the lower-middle, near-black beneath.
//        The field is ruled in BOTH axes — warm/orange horizontals, violet verticals — and
//        star sparkles are scattered through the whole frame.
//   `03_palette_field_hue_drift.png` — the FIELD carries the colour and the traces stay cool.
//        This file paints the field in a near-neutral warm-grey; the hue arrives from the
//        `stave_tint` multiply wash, which is the D-216 stem channel.
//   `04_specular_star_sparkle_field.png` — 4-point star flares with soft halos in BOTH warm
//        and cool hues, plus soft out-of-focus blobs and a faint cloud texture behind.
//        ⚠ CORRECTED DURING CURATION: the sparkles are SCATTERED, not locked to grid
//        intersections. An earlier reading of the macro frame claimed they sat on grid
//        crossings and the crop refutes it. Do not place sparkles at grid nodes.
//
// Silence (D-037): every term here is procedural and audio-independent, so the field, haze,
// rules and sparkles persist and drift at `totalStemEnergy == 0`. The frame is never black.
// L5 — there is no autonomous TRACE motion; a quiet passage flatlines the traces and that is
// the design. The atmosphere's very slow drift is the source's own character, not a
// substitute for musical response.

// MARK: - Field noise

static inline float stave_hash(float2 p) {
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
}

static inline float2 stave_hash2(float2 p) {
    return float2(stave_hash(p), stave_hash(p + 41.7));
}

static inline float stave_value_noise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(stave_hash(i), stave_hash(i + float2(1.0, 0.0)), f.x),
               mix(stave_hash(i + float2(0.0, 1.0)), stave_hash(i + float2(1.0, 1.0)), f.x), f.y);
}

/// Five octaves with an inter-octave rotation — above the SHADER_CRAFT >=4-octave floor, and
/// the rotation keeps the cloud from showing its lattice at the coarse scales the haze uses.
static inline float stave_fbm(float2 p) {
    float v = 0.0;
    float a = 0.5;
    float2x2 rot = float2x2(0.80, 0.60, -0.60, 0.80);
    for (int i = 0; i < 5; ++i) {
        v += a * stave_value_noise(p);
        p = rot * p * 2.03;
        a *= 0.5;
    }
    return v;
}

// MARK: - Sparkles

/// One scattered 4-point star flare with a soft halo. Cell-hashed so density is uniform and
/// cheap: one candidate per cell, most cells empty.
///
/// `cells` sets density. The jitter is what keeps them SCATTERED rather than nodal — an
/// unjittered one-per-cell placement is exactly the grid-intersection anti-reference the `04`
/// annotation warns about.
static inline float3 stave_sparkle_layer(float2 uv, float aspect, float cells, float t, float sizeScale) {
    float2 p = float2(uv.x * aspect, uv.y) * cells;
    float2 cell = floor(p);
    float2 local = fract(p);

    // Sparser than the first pass (0.86), which read as falling snow rather than as the
    // reference's scattered star flares — `04` has relatively few, relatively large flares.
    float pick = stave_hash(cell + 3.1);
    if (pick < 0.90) { return float3(0.0); }

    float2 jitter = stave_hash2(cell + 7.7);
    float2 d = local - jitter;
    // Very slow twinkle, well below the D-157 flash budget — a phase offset per cell so the
    // field never pulses in unison.
    float phase = stave_hash(cell + 19.3) * 6.2831853;
    float twinkle = 0.62 + 0.38 * sin(t * 0.55 + phase);

    float r = length(float2(d.x, d.y));
    float core = exp(-r * r * 900.0 / (sizeScale * sizeScale));
    // The 4-point flare: two thin orthogonal bars, which is what makes these read as star
    // flares rather than as dots (`04`).
    float bar = exp(-d.x * d.x * 2600.0 / sizeScale) * exp(-d.y * d.y * 90.0 / sizeScale)
              + exp(-d.y * d.y * 2600.0 / sizeScale) * exp(-d.x * d.x * 90.0 / sizeScale);
    float halo = exp(-r * r * 120.0 / (sizeScale * sizeScale)) * 0.16;

    // Both warm and cool, per `04` — not a monochrome sparkle field.
    float warmth = stave_hash(cell + 53.9);
    float3 tint = mix(float3(0.62, 0.80, 1.0), float3(1.0, 0.80, 0.52), warmth);
    // The cross bars carry more weight than the first pass gave them (0.34): it is the FLARE,
    // not the dot, that makes these read as stars rather than as confetti (`04`).
    return tint * (core + bar * 0.58 + halo) * twinkle;
}

// MARK: - Field fragment

fragment float4 stave_field_fragment(
    VertexOut in [[stage_in]],
    constant FeatureVector& features [[buffer(0)]],
    constant float* fftMagnitudes [[buffer(1)]],
    constant float* waveformData [[buffer(2)]],
    constant StemFeatures& stems [[buffer(3)]]
) {
    float2 uv = in.uv;
    float aspect = features.aspect_ratio > 0.05 ? features.aspect_ratio : (16.0 / 9.0);
    float t = features.time;

    // ⚠ `fullscreen_vertex` emits TEXTURE-space uv (`out.uv.y = 1.0 - out.uv.y`), so uv.y = 0
    // is the TOP of the frame. `sky` restores the intuitive axis — 1 at the top, 0 at the
    // bottom — and matches the NDC the geometry pass plots in (`sky = (ndcY + 1) * 0.5`).
    // Getting this wrong renders the whole field UPSIDE DOWN, which is exactly what the first
    // pass did: measured band luma ran 0.112 (top) -> 0.286 (bottom) against the reference's
    // 0.175 -> 0.103. The horizon was pointing at the floor and nothing else showed it,
    // because a haze gradient is plausible in either direction.
    float sky = 1.0 - uv.y;

    // --- Ground. A horizon, per `01`: hazy above, near-black beneath. The traces' band sits
    //     at y = -0.10 NDC (sky 0.45), which is where the ground is darkest so the beads
    //     have contrast to read against.
    //     Levels are MEASURED against the reference, not chosen: `01_macro` and `02_meso`
    //     sit at mean luma 0.156-0.179 with 15-28 % of pixels genuinely dark (< 0.10) and
    //     under 1.5 % pale. A first pass at these terms rendered mean luma 0.30 with
    //     **0.0 %** dark pixels and 33.8 % pale on Bohemian Rhapsody — a tan wash that
    //     failed the SHADER_CRAFT <=30 % pale-tone floor outright. The ground is a deep
    //     blue-black and the brightness belongs to the traces and the sparkles.
    float3 deep = float3(0.012, 0.014, 0.026);
    float3 upper = float3(0.062, 0.068, 0.098);
    float horizon = smoothstep(-0.10, 1.05, sky);
    // Cubed, not squared: a squared ramp still lifts the lower third off black, and `01`
    // is emphatic that the field beneath the traces is near-black.
    float3 col = mix(deep, upper, horizon * horizon * horizon);

    // --- Cloud texture behind everything (`04`: "a faint cloud texture behind"). Drifts very
    //     slowly on the render clock; audio-independent, so it is alive at silence.
    float cloud = stave_fbm(float2(uv.x * aspect * 2.6, sky * 1.9) + float2(t * 0.011, t * 0.004));
    col += float3(0.028, 0.031, 0.044) * cloud * horizon * horizon;

    // --- Haze lobe. One broad, soft, low-contrast emission in the upper field with no hard
    //     edge — the atmosphere the traces hang under.
    float2 hazeCentre = float2(0.38, 0.80);
    float2 hd = float2((uv.x - hazeCentre.x) * aspect, (sky - hazeCentre.y) * 1.6);
    float haze = exp(-dot(hd, hd) * 1.35);
    float hazeWarp = stave_fbm(float2(uv.x * aspect * 1.5, sky * 1.2) - float2(t * 0.006, 0.0));
    col += float3(0.042, 0.046, 0.064) * haze * (0.55 + 0.65 * hazeWarp);

    // --- Horizontal rules: the STAVE, and static (L6). This is the literal reading of the
    //     preset's name and it is source-faithful — `01` shows a field ruled in both axes,
    //     with the horizontals warm against the violet verticals. Static means static: they
    //     do not move, breathe or react. The verticals (the beat) are the only ruled axis
    //     that carries music, which is the whole point of the name.
    const int kStaveLines = 5;
    float rules = 0.0;
    for (int i = 0; i < kStaveLines; ++i) {
        // Clustered around the traces' band rather than spread over the whole frame, so
        // they read as a stave the traces are written on. The band centre is NDC -0.10
        // (`StaveTrace.bandCentre`), i.e. sky 0.45, and the five rules straddle it.
        float y = 0.45 + (float(i) - 2.0) * 0.088;
        float d = abs(sky - y);
        rules += exp(-d * d * 260000.0);
    }
    // Faded toward the frame edges so the ruling does not terminate in a hard line.
    float ruleFade = smoothstep(0.0, 0.16, uv.x) * smoothstep(1.0, 0.84, uv.x);
    // Dim: in `01` the horizontals are faint enough that the traces cross them without
    // competing. A first pass drew them at 2.5x this and they read as a table.
    col += float3(0.052, 0.038, 0.026) * rules * ruleFade;

    // --- Sparkles, scattered through the whole frame (`04`, and NOT at grid nodes). Two
    //     layers at different densities and sizes so they carry depth rather than sitting on
    //     one plane. Non-reactive by decision D3: the preset already carries four
    //     well-separated audio layers, and a fifth route on a diffuse field element is where
    //     the "fighting itself" failure (FA #67) starts.
    //     Brightened against the first pass: on a genuinely dark ground the sparkles are the
    //     frame's brightest element after the beads, which is what `01` and `04` show.
    col += stave_sparkle_layer(float2(uv.x, sky), aspect, 13.0, t, 1.00) * 1.25;
    col += stave_sparkle_layer(float2(uv.x, sky), aspect, 26.0, t + 51.0, 0.62) * 0.65;

    // --- Soft out-of-focus blobs (`04`), a couple of very low-frequency lobes that give the
    //     field a sense of depth behind the sparkles.
    float blob = stave_fbm(float2(uv.x * aspect * 0.9, sky * 0.8) + float2(t * 0.004, t * 0.002));
    col += float3(0.018, 0.021, 0.032) * smoothstep(0.62, 0.95, blob);

    // Tone-map rather than clamp. The sparkle layers sum a core + two cross bars + a halo and
    // then get a layer weight, so a cell whose jitter lands under the sample point can reach
    // ~2.9 — which clipped a channel to 255 and tripped the non-HDR white-clip acceptance
    // gate. `1 - exp(-x)` is bounded below 1 by construction, keeps the flare cores reading as
    // the frame's brightest element, and leaves the field's mid-tones essentially where they
    // were (0.20 -> 0.18) rather than crushing them the way a hard clamp would.
    col = 1.0 - exp(-col);

    // D-037: never black. The ground floor above already guarantees this, but the clamp makes
    // it explicit and survives any future edit to the gradient.
    col = max(col, float3(0.012, 0.014, 0.022));
    return float4(col, 1.0);
}
