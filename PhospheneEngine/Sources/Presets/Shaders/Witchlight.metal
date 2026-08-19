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
    // Falloff constants SOLVED, not chosen (WL.2-e). Lit-pixel share scales with the
    // area each star paints, which goes as 1/falloff, so taking the measured 17.15 % down
    // to the source render's 4.0 % means multiplying both constants by ~4.3. The near
    // layer was the dominant term: at `sizeScale` 1.85 the old glow reached 1/e at ~0.49 %
    // of frame width — a ~9 px halo on every one of 1300 stars, which is the milky wash
    // Matt's M7 rejected. `07` is legitimately DENSE; what it is not is fat — its stars are
    // sub-pixel to ~2 px, and that is what lets a dense field still read black.
    float core = exp(-r * r * 1120.0 / (sizeScale * sizeScale));
    float glow = exp(-r * r * 146.0 / (sizeScale * sizeScale)) * 0.22;

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
    // Tight enough that the lobe reads as a compact violet BALL offset from the subject and
    // the rest of the frame is genuinely black (`07`: the ground between stars is NOT lifted
    // grey). A broad lobe washes the whole field violet and the star layers disappear.
    //
    // WL.2-h — this constant is the single largest term in the frame's quiet-state
    // brightness. Isolating the passes measured the bloom contributing 4.75 of the 7.43 %
    // lit share, against the source's whole-frame 1.04 % when it is between events. The
    // 26.0 lobe covered roughly a third of the frame; the source's is a small ball nearer a
    // sixth of the frame WIDTH. Cutting extent rather than intensity is deliberate: it buys
    // the darkness back without desaturating the lobe, so the bloom still reads as the
    // violet emission `06` calls for instead of fading to a grey smudge.
    float body = exp(-r * r * 70.0);
    // PERF (BUG-098) — EARLY OUT BEFORE THE NOISE, which is the whole cost of this preset.
    //
    // The two calls below are ~64 Perlin evaluations per pixel (`fbm8` is 8; `warped_fbm` is
    // 7 x fbm8 = ~56 — VolumetricLithograph.metal:635 records the same figure and avoids it
    // for exactly this reason). They ran for EVERY pixel of the frame and were then multiplied
    // by `body`, a Gaussian that is essentially zero outside a ball a sixth of the frame wide.
    // At 3840x2160 that is ~530 MILLION Perlin evaluations per frame to produce black.
    //
    // Measured on Matt's session `2026-08-19T14-25-55Z`: Witchlight 273.88 ms median GPU at 4K
    // — 11.2 fps, 16x over the 16.7 ms budget — while six other presets in the same session
    // held 59-60 fps (Arachne 3.27 ms, Stave 4.94 ms, Volumetric Lithograph 16.44 ms). The cost
    // stepped straight to ~272 ms the instant the preset became active rather than ramping, so
    // it was never the trail or the beads: it is a fixed per-pixel cost.
    //
    // The branch is spatially coherent — the lobe is one compact ball, so whole tiles take the
    // same path and the GPU keeps the win. The threshold is below what 8-bit output can show:
    // `lobe <= body`, and the return is `hue * lobe * 0.24`, so body = 1e-3 caps this pixel's
    // contribution at 2.4e-4 against an 8-bit LSB of 3.9e-3 — a sixteenth of the smallest
    // representable step. Visually identical, not merely close.
    if (body < 1e-3) { return float3(0.0); }
    // Low-frequency structure only: the fbm is sampled at a large scale so the lobe stays
    // one soft mass rather than becoming cloud detail.
    float structure = fbm4(float3(d * 1.5, t * 0.008), 0.62) * 0.5 + 0.5;
    // PERF (BUG-098) — a ONE-level warp built from `fbm4`, not `warped_fbm`.
    // `warped_fbm` is 7 x fbm8 = 56 Perlin evaluations; this is 4 x fbm4 = 16, and the
    // `structure` term above went 8 -> 4. The bloom's own comment says what it needs:
    // "low-frequency structure only ... one soft mass rather than cloud detail", and this
    // term only modulates the lobe by mix(0.75, 1.0, warp) — a +/-12.5 % wobble on a soft
    // ball. Octave detail was never reaching the image.
    //
    // Exactly the remedy VolumetricLithograph applied to the same function for the same
    // reason (VL-PSY.1: `warped_fbm` inside sceneSDF measured 1120 ms/frame; see
    // VolumetricLithograph.metal:634). Its follow-up is the caution worth copying too —
    // VL-PSY.3 restored 2 octaves to 3 after Matt read the 2-octave warp as "visual quality
    // is lower", so this keeps 4 rather than cutting to the minimum that still measures fast.
    float3 wp = float3(d * 0.9 + 4.1, t * 0.005);
    float3 wq = float3(fbm4(wp), fbm4(wp + float3(5.2, 1.3, 7.1)), fbm4(wp + float3(3.1, 9.7, 2.9)));
    float warp = fbm4(wp + 4.0 * wq) * 0.5 + 0.5;
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

    return hue * lobe * 0.24;
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
    // WL.2-i — the field was effectively FROZEN, and it took Matt's M7 to name it ("the
    // background is not moving and so looks fake when the dots are drawing over it").
    //
    // `drift` is in CELL units and one cell is 1/`cells` of the frame, so the old
    // 0.0035 + 0.0110·b resolved to ~0.008 on a real track — the NEAR layer travelled
    // 0.0004 frame-widths/s (~0.16 px/s at 1080p, ~2.5 % of the frame across a whole
    // 5-minute track) and the far layer 0.013 px/s, i.e. 4 px per track. That is not slow
    // parallax, it is a still image, and a still field behind a moving stroke reads as
    // pasted-on rather than as depth.
    //
    // Sized so the NEAR layer crosses the frame in ~4 minutes at a typical centroid
    // (Matt's call: "a slow drift you notice if you look", not a sense of travelling).
    // Because drift is in cells, this is a constant fraction of the frame per second at
    // every resolution. The three layers keep their existing 0.28/0.62/1.20 multipliers,
    // which combined with their differing `cells` give ~12.7× more screen motion on the
    // near layer than the far one — that RATIO is what reads as depth.
    // WL.6 — the field drifts at a FIXED slow rate, decoupled from the music entirely.
    //
    // Matt: "the starry background is STILL moving too much, appears to be tied to the music,
    // which is probably not the right call." Both halves are right. It was `0.05 + 0.16·b`
    // (WL.5) and `0.16 + 0.50·b` before that, so a busy passage sped the whole field up —
    // which puts a second, competing音楽-driven motion behind the one thing that is supposed
    // to BE the music. The ribbon is the subject; the field is the room it hangs in, and a
    // room that reacts to the music steals the reading.
    //
    // Now a constant ~0.9 px/s on the near layer at 1080p — a full frame crossing takes ~35
    // minutes, i.e. longer than any track. Present as parallax if you watch for it, invisible
    // as motion. `spectral_centroid` no longer touches it; the star_parallax route is retired
    // from the sidecar rather than left declared-but-inert.
    float rate = 0.02;
    float2 uvA = float2((uv.x - 0.5) * aspect + 0.5, uv.y);
    float3 stars =
          witchlight_star_layer(uvA, 190.0, float2(t * rate * 0.28, t * rate * 0.10), 1.00) * 0.55
        + witchlight_star_layer(uvA, 120.0, float2(t * rate * 0.62, t * rate * 0.22), 1.35) * 0.80
        + witchlight_star_layer(uvA,  64.0, float2(t * rate * 1.20, t * rate * 0.42), 1.85) * 1.00;
    // `07` is DENSE but still reads mostly black — the field is a scatter of pinpoints,
    // not a lit texture. Overshooting here also drives the §12.7 pale-tone share up.
    //
    // WL.2-h lowers the LEVEL, not the count. The quiet frame had to come down to the
    // source's (measured 1.04 % lit between events against our 7.43 %), and dimming pushes
    // the faint majority of the field under the eye's threshold while every star is still
    // there — so the three parallax depth layers mandatory trait #5 requires survive intact,
    // and the field still reads dense when the ribbon lights it. Thinning the count instead
    // would have bought the same number and broken the trait, which is the WL.2-e lesson
    // ("reduce star SIZE/brightness before reducing count") applied a second time.
    stars *= 0.30;

    // Bloom hue from valence (measured range 1.91 live; ±1 is the working span).
    float hueShift = clamp(features.valence, -1.0, 1.0);
    float3 bloom = witchlight_bloom(uv, aspect, t, hueShift);

    // A true near-black ground (`07`: the space between stars is NOT lifted grey), with a
    // barely-there vignette so the corners fall away from the subject.
    float2 c = float2((uv.x - 0.5) * aspect, uv.y - 0.5);
    float vignette = 1.0 - 0.30 * smoothstep(0.35, 1.05, length(c));
    // UNITS BUG, found at WL.2-e by isolating the terms: neither the stars nor the bloom
    // accounted for the washed-out frame — there was a ~22-byte floor under both, and it
    // was this constant. 0.008 is dark in LINEAR space, but the drawable is sRGB, so it
    // encodes to byte ~22 (and 0.016 to ~34): a visibly lifted grey-blue, which is exactly
    // what reference `07` says the field must NOT be. The comment above claimed
    // "true near-black" while the code shipped grey. Values below are chosen so the
    // ENCODED bytes land near-black (~7/7/13), which is the space the eye and the
    // measurement both work in.
    float3 ground = float3(0.0020, 0.0020, 0.0040);

    float3 rgb = (ground + bloom + stars) * vignette;
    return float4(rgb, 1.0);
}
