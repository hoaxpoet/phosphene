// Membrane — A luminous drumskin stretched across the screen.
//
// The metaphor, restated precisely because every iteration has been about
// this: a taut translucent sheet lit from within. It is always visible.
// Bass pushes into it like a slow hand. Beats strike it with outward-
// propagating ripples. Hi-hats tickle it with fine surface stippling.
// Between strikes the sheet recovers, breathing slowly.
//
// Audio routing is deliberately sparse so the surface has time to recover
// between events:
//   * breath    — always-on FBM, gives life in silence
//   * bass_att  — slow broad undulation, the "hand pressing in"
//   * beat_bass — ONE shockwave per strike, aspect-correct circle
// That is all. Earlier iterations coupled treble to a fast-evolving FBM
// "goose-bump" term, which evolved at ~0.8 Hz regardless of the beat and
// produced whole-surface shimmer that drowned out the actual rhythm. It
// read as constant off-rhythm blinking and has been removed.
//
// Color is a stable position-driven field: three FBM-only thickness
// fields blended with time-drifting weights. It is NOT audio-modulated,
// so the color structure you see at rest is the same structure you see
// while music plays — the music only DEFORMS it via lighting.

// ── Noise primitives ─────────────────────────────────────────────

float mb_hash2(float2 p) {
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
}

float mb_hash3(float3 p) {
    return fract(sin(dot(p, float3(127.1, 311.7, 74.7))) * 43758.5453);
}

float mb_vnoise3(float3 p) {
    float3 i = floor(p);
    float3 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float n000 = mb_hash3(i);
    float n100 = mb_hash3(i + float3(1.0, 0.0, 0.0));
    float n010 = mb_hash3(i + float3(0.0, 1.0, 0.0));
    float n110 = mb_hash3(i + float3(1.0, 1.0, 0.0));
    float n001 = mb_hash3(i + float3(0.0, 0.0, 1.0));
    float n101 = mb_hash3(i + float3(1.0, 0.0, 1.0));
    float n011 = mb_hash3(i + float3(0.0, 1.0, 1.0));
    float n111 = mb_hash3(i + float3(1.0, 1.0, 1.0));
    float nxy0 = mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y);
    float nxy1 = mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y);
    return mix(nxy0, nxy1, f.z);
}

float mb_fbm3(float3 p) {
    float v = 0.0;
    float amp = 0.5;
    for (int i = 0; i < 4; i++) {
        v += amp * mb_vnoise3(p);
        p *= 2.03;
        amp *= 0.5;
    }
    return v;
}

// ── Aspect-corrected space ──────────────────────────────────────
//
// UV space is 0..1 × 0..1 regardless of window shape. On a 16:9 window,
// a circle in UV (length(uv - c) == r) renders as a horizontally
// stretched ellipse. To draw an actual circle, work in a space where
// x is scaled by the window aspect ratio.

float2 mb_asp_space(float2 uv, float aspect) {
    return float2((uv.x - 0.5) * aspect, uv.y - 0.5);
}

// ── Shockwave ring ───────────────────────────────────────────────
//
// The exponentially-decaying beat pulse is the implicit timer. At the
// moment of the strike pulse = 1.0, and the ring sits at radius 0. As
// the pulse decays, -log(pulse) grows and the ring expands outward.
// No frame-to-frame state is required: the ring is always perfectly
// phase-locked to the beat pulse, regardless of framerate.
//
// Distance is computed in aspect-corrected space so the ring is an
// actual circle on screen, not an ellipse.

float membrane_ring(float2 asp, float2 impactAsp, float pulse,
                    float speed, float ageScale, float thicknessBase) {
    if (pulse < 0.05) return 0.0;                          // higher threshold
    float age = -log(max(pulse, 0.01)) * ageScale;
    float radius = age * speed;
    float thickness = thicknessBase + age * 0.08;
    float d = length(asp - impactAsp);
    float body = exp(-pow((d - radius) / thickness, 2.0));
    return max(body * (1.0 - age * 0.9), 0.0);
}

// ── Total displacement ──────────────────────────────────────────

float membrane_D(float2 uv, float2 asp, float t,
                 constant FeatureVector& features,
                 float2 impactAsp) {

    // Always-on breath — the surface is never dead.
    float breath = mb_fbm3(float3(uv * 1.8, t * 0.16)) - 0.5;

    // Bass as a slow hand pressing into the sheet. Crossed sines with
    // audio-modulated phase make the pressure "wander" organically.
    // Only bass_att couples — no raw bass (spiky) and no FFT bins.
    float wave = sin(uv.x * 2.7 + t * 0.33 + features.bass_att * 2.2)
               * cos(uv.y * 2.3 - t * 0.27 + features.bass_att * 1.7);

    // Hi-hat goose-bumps: fine FBM scaled by treble_att only. This is
    // the only treble coupling; the rest of the treble energy is
    // invisible, the way it should be on a drumskin.
    float goose = (mb_fbm3(float3(uv * 10.0, t * 0.8)) - 0.5)
                * features.treb_att;

    // ONE shockwave ring from bass beats. (The mid-beat ring from the
    // previous iteration made strikes feel continuous — removed.)
    float ring = membrane_ring(asp, impactAsp, features.beat_bass,
                               1.10, 0.20, 0.045);

    float raw = breath * 0.40
              + wave * (0.08 + features.bass_att * 0.40)
              + goose * 0.35
              + ring * 0.55;

    // Edge tension: the drumskin is anchored at the frame boundary.
    // Displacement is free in the interior and forced smoothly to zero
    // at the edges. This is the single strongest cue that what you are
    // looking at is a stretched sheet, not a free-floating color field.
    float2 edgeDist = min(uv, 1.0 - uv);
    float edgeFactor = saturate(min(edgeDist.x, edgeDist.y) * 3.0);
    edgeFactor = edgeFactor * edgeFactor * (3.0 - 2.0 * edgeFactor);
    return raw * edgeFactor;
}

// ── Fragment entry point ────────────────────────────────────────

fragment float4 membrane_fragment(
    VertexOut in [[stage_in]],
    constant FeatureVector& features [[buffer(0)]],
    constant float* fftMagnitudes [[buffer(1)]],
    constant float* waveformData [[buffer(2)]]
) {
    float2 uv = in.uv;
    float t = features.time;
    float aspect = max(features.aspect_ratio, 0.01);
    float2 asp = mb_asp_space(uv, aspect);

    // ── Shockwave impact point ──────────────────────────────────
    // Single wandering impact position, steered slowly by mood.
    // Converted to aspect space for the ring distance calc.
    float2 impactUV = float2(
        0.5 + 0.28 * sin(t * 0.237 + features.arousal * 1.6),
        0.5 + 0.28 * cos(t * 0.183 + features.valence * 1.3)
    );
    float2 impactAsp = mb_asp_space(impactUV, aspect);

    // ── Displacement and surface normal ─────────────────────────
    float D  = membrane_D(uv,                    asp,                           t, features, impactAsp);
    float eps = 0.004;
    float2 aspX = asp + float2(eps * aspect, 0.0);
    float2 aspY = asp + float2(0.0,          eps);
    float Dx = membrane_D(uv + float2(eps, 0.0), aspX, t, features, impactAsp);
    float Dy = membrane_D(uv + float2(0.0, eps), aspY, t, features, impactAsp);

    float dDdx = (Dx - D) * 28.0;
    float dDdy = (Dy - D) * 28.0;
    float3 N = normalize(float3(-dDdx, -dDdy, 1.0));

    // View + directional light.
    float3 V = float3(0.0, 0.0, 1.0);
    float NdotV = saturate(dot(N, V));
    float fresnel = pow(1.0 - NdotV, 3.0);

    float3 L = normalize(float3(-0.45 + features.arousal * 0.20,
                                -0.55,
                                 0.80));
    float NdotL = saturate(dot(N, L));
    float diffuse = NdotL * 0.5 + 0.5;   // wrapped — surface always visible

    // ── Color field: pure FBM, no linear sweeps ────────────────
    // All three thickness fields are FBM-only. There are no `uv.x * k`
    // terms anywhere in the color calculation, so there are no visible
    // diagonal bands. The coordinates drift slowly in time and pick up
    // a tiny amount of D so deformations nudge local hue but do not
    // rearrange the overall structure.

    float absD = abs(D);

    float3 p1 = float3(uv * 1.6 + t * 0.030, t * 0.020);
    float3 p2 = float3(uv * 2.4 + t * 0.022, t * 0.015 + 3.1);
    float3 p3 = float3(uv * 3.8 + t * 0.045, t * 0.012 + 7.7);

    float thick1 = mb_fbm3(p1) * 3.0 + D * 0.35;
    float thick2 = mb_fbm3(p2) * 2.6 + D * 0.25;
    float thick3 = mb_fbm3(p3) * 2.2 + D * 0.20;

    float3 band1 = hsv2rgb(float3(fract(thick1),        1.0, 1.0));
    float3 band2 = hsv2rgb(float3(fract(thick2 + 0.33), 1.0, 1.0));
    float3 band3 = hsv2rgb(float3(fract(thick3 + 0.66), 1.0, 1.0));

    float w1 = 0.40 + 0.18 * sin(t * 0.23);
    float w2 = 0.35 + 0.18 * sin(t * 0.17 + 2.1);
    float w3 = 0.30 + 0.18 * sin(t * 0.29 + 4.2);
    float wSum = w1 + w2 + w3;
    float3 filmColor = (band1 * w1 + band2 * w2 + band3 * w3) / wSum;

    // Saturation boost so the hue stays pure after weighted averaging.
    float maxC = max(filmColor.r, max(filmColor.g, filmColor.b));
    float minC = min(filmColor.r, min(filmColor.g, filmColor.b));
    if (maxC > 0.001) {
        filmColor = mix(float3((maxC + minC) * 0.5), filmColor, 1.30);
        filmColor = saturate(filmColor);
    }

    // ── Surface lighting ────────────────────────────────────────
    float innerGlow = saturate(absD * 1.5);
    float shade = 0.40 + diffuse * 0.50 + innerGlow * 0.45;
    float3 color = filmColor * shade;

    // Fresnel rim — sampled from another thickness so edges are lit
    // with a contrasting hue, suggesting light bleeding through.
    float3 rimColor = hsv2rgb(float3(fract(thick1 + 0.5), 1.0, 1.0));
    color += rimColor * fresnel * 0.45;

    // Specular — sharp highlights on crests.
    float3 H = normalize(L + V);
    float NdotH = saturate(dot(N, H));
    float specK = pow(NdotH, 48.0);
    color += float3(1.0) * specK * 0.55;

    // Shockwave color flash along the current ring — makes the strike
    // unmistakable without being gratuitous.
    float flash = membrane_ring(asp, impactAsp, features.beat_bass,
                                1.10, 0.20, 0.045) * features.beat_bass;
    float3 flashColor = hsv2rgb(float3(fract(thick2 + 0.2), 1.0, 1.0));
    color += flashColor * flash * 0.75;

    // Soft vignette at the drumskin frame.
    float vig = 1.0 - smoothstep(0.55, 1.15, length(asp));
    color *= 0.55 + vig * 0.45;

    color = min(color, float3(1.0));

    // Alpha blends each frame with the warped history — 0.55 keeps the
    // current state clear while leaving a soft trail.
    return float4(color, 0.55);
}
