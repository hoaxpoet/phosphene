// Starburst.metal — Murmuration sky: vivid sunrise/sunset seen from below.
//
// Looking up into the sky where birds fly. Rich color — peach, amber,
// rose, lavender, deep blue. Clouds drift slowly. The sky is the canvas;
// the birds are dark calligraphy written on it.
//
// Vocals routing (Increment 3.5.2):
//   vocals_energy subtly shifts the sky toward warmer amber/rose hues.
//   Primary vocal response is density compression in the particle kernel.
//   This is a secondary, optional coloration effect (~10% shift max).

float sky_hash(float2 p) {
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
}

float sky_noise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float n = i.x + i.y * 157.0;
    return mix(
        mix(sky_hash(n), sky_hash(n + 1.0), f.x),
        mix(sky_hash(n + 157.0), sky_hash(n + 158.0), f.x),
        f.y
    );
}

float sky_fbm(float2 p, int octaves) {
    float val = 0.0;
    float amp = 0.5;
    float freq = 1.0;
    for (int i = 0; i < octaves; i++) {
        val += amp * sky_noise(p * freq);
        freq *= 2.0;
        amp *= 0.5;
    }
    return val;
}

fragment float4 starburst_fragment(
    VertexOut in [[stage_in]],
    constant FeatureVector& features [[buffer(0)]],
    constant float* fftMagnitudes [[buffer(1)]],
    constant float* waveformData [[buffer(2)]],
    constant StemFeatures& stems [[buffer(3)]]
) {
    float2 uv = in.uv;
    float t = features.time;
    float warmth = features.spectral_centroid;

    // Vocal presence shifts the sky subtly warmer (amber/rose toward the horizon).
    // This is intentionally gentle — max 10% shift — so it doesn't dominate
    // the spectral centroid-driven warmth. Smoothed to avoid abrupt changes.
    float vocalWarmth = stems.vocals_energy * 0.10;
    float totalWarmth = clamp(warmth + vocalWarmth, 0.0, 1.0);

    // ── SUNSET/SUNRISE SKY GRADIENT ──────────────────────────────
    // Looking upward. Screen bottom = horizon (brightest, warmest).
    // Screen top = zenith (deeper blue/indigo).
    // The gradient is rich and colorful — this is the canvas.

    float y = uv.y;  // 0 = top (zenith), 1 = bottom (horizon).

    // Zenith: deep blue to indigo, shifts with warmth.
    float3 zenith = mix(
        float3(0.08, 0.06, 0.22),   // Cool: deep indigo
        float3(0.12, 0.08, 0.18),   // Warm: softer violet
        totalWarmth
    );

    // Mid-sky: lavender to rose.
    float3 midSky = mix(
        float3(0.20, 0.15, 0.35),   // Cool: lavender
        float3(0.35, 0.18, 0.25),   // Warm: dusty rose
        totalWarmth
    );

    // Low sky: pink to peach.
    float3 lowSky = mix(
        float3(0.40, 0.22, 0.35),   // Cool: mauve-pink
        float3(0.55, 0.30, 0.18),   // Warm: peach-amber
        totalWarmth
    );

    // Horizon: brightest — amber to gold.
    float3 horizon = mix(
        float3(0.50, 0.30, 0.35),   // Cool: warm pink
        float3(0.70, 0.40, 0.15),   // Warm: golden amber
        totalWarmth
    );

    // Multi-stop gradient.
    float3 sky = zenith;
    sky = mix(sky, midSky, smoothstep(0.0, 0.35, y));
    sky = mix(sky, lowSky, smoothstep(0.25, 0.60, y));
    sky = mix(sky, horizon, smoothstep(0.55, 0.95, y));

    // ── CLOUDS ───────────────────────────────────────────────────
    // Wispy, scattered clouds catching the last light.
    // Slow drift from bass_att.
    float2 cloudUV1 = uv * 2.5 + float2(t * 0.012 + features.bass_att * 0.03, t * 0.005);
    float2 cloudUV2 = uv * 1.2 + float2(t * 0.008, t * 0.003) + float2(3.7, 1.2);

    float cloud1 = sky_fbm(cloudUV1, 5);
    float cloud2 = sky_fbm(cloudUV2, 4);

    // Wispy shapes — higher threshold for less coverage.
    float cloudMask1 = smoothstep(0.50, 0.70, cloud1) * 0.35;
    float cloudMask2 = smoothstep(0.48, 0.68, cloud2) * 0.25;
    float cloudMask = (cloudMask1 + cloudMask2);

    // Clouds near horizon are brighter (catching sunlight).
    // Clouds high up are more transparent.
    cloudMask *= smoothstep(0.05, 0.4, y);

    // Cloud color: bright, catching sunset light.
    float3 cloudColor = mix(
        float3(0.45, 0.35, 0.50),   // Cool: pinkish grey
        float3(0.65, 0.45, 0.25),   // Warm: lit amber
        totalWarmth
    );
    // Cloud edges are brighter (silver lining effect).
    float cloudEdge = smoothstep(0.02, 0.08, cloudMask) * (1.0 - smoothstep(0.15, 0.30, cloudMask));
    cloudColor += float3(0.15, 0.12, 0.08) * cloudEdge;

    sky = mix(sky, cloudColor, cloudMask);

    // ── SUBTLE GLOW near horizon ─────────────────────────────────
    // A warm band of light where the sun would be (below the horizon).
    float horizonGlow = exp(-(1.0 - y) * (1.0 - y) / 0.02) * 0.15;
    float3 glowColor = mix(float3(0.5, 0.3, 0.3), float3(0.7, 0.5, 0.2), totalWarmth);
    sky += glowColor * horizonGlow;

    sky = min(sky, float3(1.0));
    return float4(sky, 1.0);
}
