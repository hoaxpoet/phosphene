// HenyeyGreenstein.metal — Phase function utilities for participating media (V.2 Part B).
//
// The Henyey-Greenstein phase function models directional scattering of light
// through fog, smoke, clouds, and other participating media.
//
// g = 0      → isotropic (scatter equally in all directions)
// g = +0.5   → forward-scattering (light bends toward viewer — milky haze)
// g = -0.5   → back-scattering (light bends away — volumetric glow)
// g ∈ (-1,1), singularity-free for all view angles.
//
// Usage:
//   float phase = hg_phase(dot(rd, lightDir), 0.5);
//   float3 scatter = lightColor * phase * density;

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"

// ─── Henyey-Greenstein Phase Function ────────────────────────────────────────

/// Standard Henyey-Greenstein phase function.
/// cosTheta = dot(ray direction, light direction). g ∈ (-1, 1).
/// Returns probability density for scattering at this angle.
/// Normalised so that integrating over sphere gives 4π.
static inline float hg_phase(float cosTheta, float g) {
    float g2 = g * g;
    float denom = 1.0 + g2 - 2.0 * g * cosTheta;
    return (1.0 - g2) / (4.0 * 3.14159265 * pow(max(denom, 1e-5), 1.5));
}

/// Schlick approximation to Henyey-Greenstein — cheaper, no pow().
/// k ≈ 1.55g − 0.55g³ remaps g to Schlick's k parameter for close match.
/// Suitable when g is fixed (not audio-driven) and cycles/frame matter.
static inline float hg_schlick(float cosTheta, float g) {
    float k = 1.55 * g - 0.55 * g * g * g;
    float d = 1.0 - k * cosTheta;
    return (1.0 - k * k) / (4.0 * 3.14159265 * max(d * d, 1e-5));
}

/// Dual-lobe phase function: weighted blend of two HG lobes.
/// Useful for cloud-like scattering with both forward and back scatter.
/// w = forward-lobe weight [0,1]; (1-w) = back-lobe weight.
static inline float hg_dual_lobe(float cosTheta, float gForward, float gBack, float w) {
    return w * hg_phase(cosTheta, gForward) + (1.0 - w) * hg_phase(cosTheta, gBack);
}

/// Mie-like phase: forward spike (g=0.8) + isotropic (g=0) blend.
/// Good approximation for water droplets, thin smoke rings.
static inline float hg_mie(float cosTheta) {
    return hg_dual_lobe(cosTheta, 0.8, 0.0, 0.8);
}

// ─── Beer-Lambert Transmittance ───────────────────────────────────────────────

/// Exponential transmittance: fraction of light reaching viewer after
/// traveling through density `d` over distance `t`.
/// sigma = extinction coefficient (absorption + scattering).
static inline float hg_transmittance(float density, float t, float sigma) {
    return exp(-density * t * sigma);
}

/// Accumulated Beer-Lambert over N march steps, each with density `d` and step `dt`.
/// Returns transmittance (1 = fully transparent, 0 = opaque).
static inline float hg_transmittance_stepped(float density, float dt, float sigma, int steps) {
    return exp(-density * dt * sigma * float(steps));
}

// ─── Audio-Reactive Phase Helpers ─────────────────────────────────────────────

/// Phase function with audio-driven anisotropy.
/// bassRel drives g from isotropic (g=0) toward forward-scatter (g=0.7).
/// Useful for bass-pulse "thickening" of fog / volumetric hazes.
static inline float hg_phase_audio(float cosTheta, float bassRel) {
    float g = clamp(bassRel * 0.5 + 0.3, 0.0, 0.85);
    return hg_phase(cosTheta, g);
}

#pragma clang diagnostic pop
