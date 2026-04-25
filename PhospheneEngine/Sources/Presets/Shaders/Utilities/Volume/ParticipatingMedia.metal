// ParticipatingMedia.metal — Ray-march integration for participating media (V.2 Part B).
//
// Provides step-based volumetric integration (front-to-back and back-to-front),
// heterogeneous density evaluation via noise fields, and single-scattering approximation.
//
// Usage pattern (front-to-back):
//   VolumeSample s = vol_sample_zero();
//   for (int i = 0; i < steps; i++) {
//       float3 pos = ro + rd * (tMin + (tMax - tMin) * (float(i) + 0.5) / float(steps));
//       float  den = vol_density_fbm(pos, scale, octaves);
//       s = vol_accumulate(s, pos, rd, den, stepLen, lightDir, lightColor, sigma);
//       if (s.transmittance < 0.01) break;
//   }
//   float3 color = s.color + background * s.transmittance;

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"

// ─── Volume Sample State ──────────────────────────────────────────────────────

/// Accumulated state during front-to-back volume integration.
struct VolumeSample {
    float3 color;         // accumulated scattered color
    float  transmittance; // remaining transmittance (1 = clear, 0 = opaque)
};

/// Return a zeroed VolumeSample (start of integration).
static inline VolumeSample vol_sample_zero() {
    VolumeSample s;
    s.color = float3(0.0);
    s.transmittance = 1.0;
    return s;
}

// ─── Density Fields ───────────────────────────────────────────────────────────

/// Constant-density medium. Simple but useful for ground truth comparisons.
static inline float vol_density_constant(float density) {
    return density;
}

/// Exponential height fog. Density falls off exponentially above y=0.
/// scale = overall density, falloff = decay rate per unit height.
static inline float vol_density_height_fog(float3 p, float scale, float falloff) {
    return scale * exp(-max(p.y, 0.0) * falloff);
}

/// Sphere-shaped density cloud. Smooth falloff at radius r from centre c.
static inline float vol_density_sphere(float3 p, float3 c, float r) {
    float d = length(p - c);
    return max(0.0, 1.0 - d / r);
}

/// fBM-textured heterogeneous density. Uses Noise utility perlin3d.
/// scale = world-space frequency of the noise, octaves = 1..4.
static inline float vol_density_fbm(float3 p, float scale, int octaves) {
    float3 q = p * scale;
    float den = 0.0, amp = 1.0, freq = 1.0, norm = 0.0;
    for (int i = 0; i < octaves; i++) {
        den  += perlin3d(q * freq) * amp;
        norm += amp;
        amp  *= 0.5;
        freq *= 2.0;
    }
    return max(0.0, den / norm);   // normalise and clamp to [0, ∞)
}

/// Wispy cloud density: fBM with coverage threshold and sharp falloff.
/// coverage ∈ [0,1]: 0 = no clouds, 1 = overcast.
static inline float vol_density_cloud(float3 p, float scale, float coverage) {
    float base = vol_density_fbm(p, scale, 4);
    return max(0.0, base - (1.0 - coverage)) * (1.0 / coverage);
}

// ─── Single-Scattering Approximation ─────────────────────────────────────────

/// Approximate in-scattered radiance at point p toward rd.
/// Assumes a single distant light with direction lightDir and color lightColor.
/// Uses Beer-Lambert along a shadow ray of length shadowDist.
static inline float3 vol_inscatter(
    float3 p, float3 rd, float3 lightDir, float3 lightColor,
    float density, float sigma, float shadowDist,
    float phase
) {
    float shadow = hg_transmittance(density, shadowDist, sigma);
    return lightColor * phase * density * sigma * shadow;
}

// ─── Front-to-Back Accumulation ───────────────────────────────────────────────

/// Accumulate one step of front-to-back volume integration.
/// Adds inscattered light weighted by transmittance, then decrements transmittance.
static inline VolumeSample vol_accumulate(
    VolumeSample s,
    float3 pos, float3 rd,
    float density, float stepLen,
    float3 lightDir, float3 lightColor,
    float sigma
) {
    if (density < 1e-5) return s;

    float cosTheta = dot(rd, lightDir);
    float phase    = hg_phase(cosTheta, 0.5);
    float stepTau  = density * sigma * stepLen;
    float stepT    = exp(-stepTau);

    float3 scatter = vol_inscatter(pos, rd, lightDir, lightColor,
                                   density, sigma, stepLen * 4.0, phase);

    s.color        += scatter * s.transmittance * (1.0 - stepT);
    s.transmittance *= stepT;
    return s;
}

/// Simple fog composite: blend foreground color with vol sample result.
static inline float3 vol_composite(VolumeSample s, float3 background) {
    return s.color + background * s.transmittance;
}

// ─── Audio-Reactive Density Helpers ──────────────────────────────────────────

/// fBM density field modulated by audio time (animated noise field).
/// t = accumulatedAudioTime for music-locked animation without free-running sin.
static inline float vol_density_animated(float3 p, float scale, float t, float bassRel) {
    float3 q = p * scale + float3(0.0, -t * 0.1, 0.0);
    float base = vol_density_fbm(q, 1.0, 3);
    return base * (0.5 + 0.5 * max(0.0, bassRel));
}

#pragma clang diagnostic pop
