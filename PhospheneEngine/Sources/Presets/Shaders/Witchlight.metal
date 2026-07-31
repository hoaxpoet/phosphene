// Witchlight.metal — the deep-space backdrop the ribbon hangs in.
//
// Witchlight's subject — the beaded luminous stroke, its thread, its star suppression and
// its head flare — is drawn by `WitchlightStroke` from CPU-simulated geometry (see
// `Renderer/Shaders/Witchlight.metal` for those four passes). This file is ONLY the
// backdrop: three parallax star layers, one soft violet nebular bloom, and nothing else.
//
// It is drawn first, as the particle-mode preset triangle, and then occluded/lit by the
// ribbon — the same role `filigree_ground_fragment` and `murmuration_sky_fragment` play.
//
// Read off the reference set:
//   `07` — the field is genuinely near-black between stars (not lifted grey), the stars are
//          dense and mostly sub-pixel to ~2 px, and their brightness varies over a wide
//          range. Star DENSITY is high; star SIZE is small. Getting this backwards gives a
//          sparse field of fat dots, which reads as a screensaver.
//   `06` — the bloom is one broad, soft, low-contrast violet-blue emission lobe with no
//          hard edge, offset from centre. Explicitly NOT the reference's green H-alpha
//          structure or dust lanes: one lobe, very low spatial frequency.
//   `00` — the register: the bloom sits off to one side and the figure hangs in the dark
//          beside it rather than on top of it.
//
// Audio (one primitive per layer, FA #67):
//   star parallax depth ← `spectral_centroid`, mapped against the MEASURED 0.04–0.21 band
//                          (WITCHLIGHT_DESIGN §2.2). A `centroid × N` mapping would move
//                          less than one step across a whole track — the BUG-027 / CR.1.1
//                          trap, now measured a third time.
//   bloom hue           ← `valence` (range 1.91 on the live capture), a 30 s+ driver.
//
// Silence (D-037): every term here is procedural and audio-independent in its base level,
// so the field and the bloom persist at `totalStemEnergy == 0` and the frame is never black.

// MARK: - Star layers

/// One parallax star layer. Cell-hashed so density is uniform and cheap: one candidate
/// star per cell, most of them dim.
///
/// `cells` sets density (higher = denser); `depth` scales the parallax offset so nearer
/// layers slide faster. Brightness is `pow`-skewed so the field is mostly faint pinpoints
/// with a few bright ones, which is what `07` actually looks like.
static inline float3 witchlight_star_layer(float2 uv, float cells, float2 drift, float sizeScale) {
    float2 p = uv * cells + drift;
    float2 cell = floor(p);
    float2 local = fract(p);

    float2 jitter = hash_f01_2x(cell);
    float bright = hash_f01_2(cell + 17.3);
    // Only a fraction of cells carry a star at all — an even one-per-cell grid reads as a
    // lattice at low densities.
    if (bright < 0.68) { return float3(0.0); }

    float mag = pow((bright - 0.68) / 0.32, 2.6);          // few bright, many faint
    // `d` is in CELL units — one cell is 1/`cells` of the frame, so the falloff constants
    // set star size as a fraction of a cell and stay resolution-independent. (Multiplying
    // by `cells` here was a unit error that put every star ~200× too small: the field
    // rendered empty at every density.)
    float2 d = local - jitter;
    float r = length(d);
    // Sub-pixel-to-2px core with a very tight halo. `sizeScale` keeps far layers smaller.
    float core = exp(-r * r * 260.0 / (sizeScale * sizeScale));
    float glow = exp(-r * r * 34.0 / (sizeScale * sizeScale)) * 0.22;

    // Stars are not white: hash a small blue↔amber temperature spread (`07`).
    float temperature = hash_f01_2(cell + 91.7);
    float3 tint = mix(float3(0.72, 0.80, 1.00), float3(1.00, 0.90, 0.76), temperature);
    return tint * (core + glow) * mag;
}

// MARK: - Nebular bloom

/// One broad violet lobe, offset from centre, modulated by 8 octaves of fbm so it has
/// internal structure without ever acquiring an edge (`06`).
static inline float3 witchlight_bloom(float2 uv, float aspect, float t, float hueShift) {
    float2 p = float2((uv.x - 0.5) * aspect, uv.y - 0.5);
    // Off-centre, drifting extremely slowly — the lobe should never read as "moving".
    float2 centre = float2(0.30 + 0.03 * sin(t * 0.013), -0.06 + 0.025 * cos(t * 0.011));
    float2 d = p - centre;
    d.y *= 1.35;                                            // slightly ovoid, not a disc

    float r = length(d);
    // Tight enough that the lobe occupies roughly a third of the frame and the corners are
    // genuinely black (`07`: the ground between stars is NOT lifted grey). A broad lobe
    // washes the whole field violet and the star layers disappear into it.
    float body = exp(-r * r * 26.0);
    // Low-frequency structure only: the fbm is sampled at a large scale so the lobe stays
    // one soft mass rather than becoming cloud detail.
    float structure = fbm8(float3(d * 1.5, t * 0.008), 0.62) * 0.5 + 0.5;
    float warp = warped_fbm(float3(d * 0.9 + 4.1, t * 0.005)) * 0.5 + 0.5;
    float lobe = body * mix(0.55, 1.0, structure) * mix(0.75, 1.0, warp);

    // Violet → indigo, with a cool teal foot in the shadows (`06`'s hue family). `valence`
    // slides the family a little; it never leaves violet-indigo.
    float3 core = float3(0.42, 0.24, 0.86);
    float3 edge = float3(0.10, 0.16, 0.40);
    float3 foot = float3(0.06, 0.16, 0.22);
    float3 hue = mix(edge, core, smoothstep(0.0, 0.55, lobe));
    hue = mix(hue, foot, smoothstep(0.30, 0.02, lobe) * 0.45);
    // Hue slide from valence: positive → warmer violet, negative → colder indigo.
    hue.r *= 1.0 + 0.22 * hueShift;
    hue.b *= 1.0 - 0.10 * hueShift;

    return hue * lobe * 0.30;
}

// MARK: - Ground

fragment float4 witchlight_sky_fragment(
    VertexOut in [[stage_in]],
    constant FeatureVector& features [[buffer(0)]],
    constant float* fftMagnitudes [[buffer(1)]],
    constant float* waveformData [[buffer(2)]],
    constant StemFeatures& stems [[buffer(3)]]
) {
    float2 uv = in.uv;
    float aspect = features.aspect_ratio > 0.05 ? features.aspect_ratio : (16.0 / 9.0);
    float t = features.time;

    // Brightness, read against the MEASURED band — never `centroid × N` (§2.2).
    float brightness = smoothstep(0.04, 0.21, features.spectral_centroid);

    // Three depth layers. Depth separation is what makes the field read as space rather
    // than as wallpaper; brightness opens the separation up (busier tracks travel faster
    // through the field) without ever stopping it.
    float rate = 0.0035 + 0.0110 * brightness;
    float2 uvA = float2((uv.x - 0.5) * aspect + 0.5, uv.y);
    float3 stars =
          witchlight_star_layer(uvA, 190.0, float2(t * rate * 0.28, t * rate * 0.10), 1.00) * 0.55
        + witchlight_star_layer(uvA, 120.0, float2(t * rate * 0.62, t * rate * 0.22), 1.35) * 0.80
        + witchlight_star_layer(uvA,  64.0, float2(t * rate * 1.20, t * rate * 0.42), 1.85) * 1.00;
    // `07` is DENSE but still reads mostly black — the field is a scatter of pinpoints,
    // not a lit texture. Overshooting here also drives the §12.7 pale-tone share up.
    stars *= 0.95;

    // Bloom hue from valence (measured range 1.91 live; ±1 is the working span).
    float hueShift = clamp(features.valence, -1.0, 1.0);
    float3 bloom = witchlight_bloom(uv, aspect, t, hueShift);

    // A true near-black ground (`07`: the space between stars is NOT lifted grey), with a
    // barely-there vignette so the corners fall away from the subject.
    float2 c = float2((uv.x - 0.5) * aspect, uv.y - 0.5);
    float vignette = 1.0 - 0.30 * smoothstep(0.35, 1.05, length(c));
    float3 ground = float3(0.008, 0.008, 0.016);

    float3 rgb = (ground + bloom + stars) * vignette;
    return float4(rgb, 1.0);
}
