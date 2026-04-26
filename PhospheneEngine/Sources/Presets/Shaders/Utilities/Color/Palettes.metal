// Palettes.metal — IQ cosine palette system and gradient helpers.
//
// Inigo Quilez cosine palette: a + b * cos(2π(c * t + d))
// The four float3 parameters encode a bias, amplitude, frequency, and phase
// for each RGB channel independently, producing smooth periodic colour cycles.
//
// Reference: https://iquilezles.org/articles/palettes/
//            SHADER_CRAFT.md §11.2
//
// NOTE: This file supersedes the legacy `palette()` in ShaderUtilities.metal
// (deleted in Increment V.3, D-062). All call sites continue to work unchanged
// because this file loads before ShaderUtilities in the preamble (D-062(d)).
//
// DO NOT add #include <metal_stdlib> or using namespace metal.

// Source: SHADER_CRAFT.md §11.2 — Palettes

// ─── Canonical IQ cosine palette ─────────────────────────────────────────────

/// Inigo Quilez cosine palette: `a + b * cos(2π * (c*t + d))`.
///
/// - `t`  = normalised time/position value, any range.
/// - `a`  = bias (centre of oscillation).
/// - `b`  = amplitude (half the swing).
/// - `c`  = frequency (oscillations per unit t).
/// - `d`  = phase offset (shifts the colour cycle).
///
/// Output: each channel ∈ [a − b, a + b]. Clamp to [0, 1] at the call site
/// if HDR output is not desired.
static inline float3 palette(float t, float3 a, float3 b, float3 c, float3 d) {
    return a + b * cos(6.28318530718 * (c * t + d));
}

// ─── Named IQ presets ────────────────────────────────────────────────────────
// Vectors chosen from the IQ palette generator for the most-used moods.
// Each wraps the 4-vector form with baked constants. SHADER_CRAFT.md §11.2.

/// Warm sunset: deep orange → gold → pink cycle.
/// (a, b, c, d) from IQ palette generator for warm/energetic moods.
static inline float3 palette_warm(float t) {
    return palette(t,
        float3(0.5, 0.4, 0.3),
        float3(0.5, 0.4, 0.3),
        float3(1.0, 1.0, 1.0),
        float3(0.00, 0.10, 0.20));
}

/// Cool arctic: icy blue → teal → pale violet cycle.
/// Suited to ambient/dreamy moods with negative arousal.
static inline float3 palette_cool(float t) {
    return palette(t,
        float3(0.3, 0.4, 0.5),
        float3(0.3, 0.4, 0.4),
        float3(1.0, 1.0, 1.0),
        float3(0.50, 0.65, 0.80));
}

/// Neon electric: hot pink → cyan → acid green cycle.
/// Suited to high-arousal, high-valence electronic tracks.
static inline float3 palette_neon(float t) {
    return palette(t,
        float3(0.5, 0.5, 0.5),
        float3(0.5, 0.5, 0.5),
        float3(1.0, 1.0, 1.0),
        float3(0.00, 0.33, 0.67));
}

/// Pastel dust: muted lavender → sage → peach cycle.
/// Suited to low-energy, high-valence tracks.
static inline float3 palette_pastel(float t) {
    return palette(t,
        float3(0.6, 0.5, 0.6),
        float3(0.2, 0.2, 0.2),
        float3(1.0, 1.0, 1.0),
        float3(0.10, 0.40, 0.65));
}

// ─── Piecewise linear gradients ──────────────────────────────────────────────

/// Two-stop linear gradient. `t` ∈ [0, 1].
static inline float3 gradient_2(float t, float3 c0, float3 c1) {
    return mix(c0, c1, saturate(t));
}

/// Three-stop linear gradient. `t` ∈ [0, 1].
/// Remap to [0, 0.5] for c0→c1 and [0.5, 1] for c1→c2.
static inline float3 gradient_3(float t, float3 c0, float3 c1, float3 c2) {
    t = saturate(t);
    return t < 0.5
        ? mix(c0, c1, t * 2.0)
        : mix(c1, c2, (t - 0.5) * 2.0);
}

/// Five-stop linear gradient. `t` ∈ [0, 1].
static inline float3 gradient_5(float t,
                                 float3 c0, float3 c1, float3 c2,
                                 float3 c3, float3 c4)
{
    t = saturate(t) * 4.0;   // map to [0, 4]
    if (t < 1.0) return mix(c0, c1, t);
    if (t < 2.0) return mix(c1, c2, t - 1.0);
    if (t < 3.0) return mix(c2, c3, t - 2.0);
    return mix(c3, c4, t - 3.0);
}

// ─── 1D LUT sample ───────────────────────────────────────────────────────────

/// Sample a 1D colour LUT encoded as a texture2d strip (1 × N or N × 1).
///
/// `lut_tex` must be a 1D strip: sample at V = 0.5 (centre row) with U = t.
/// Texture-binding plumbing is out of scope for V.3; callers supply the
/// texture reference directly from their fragment function signature.
///
/// `t` ∈ [0, 1].  Returns the LUT colour at that normalised position.
static inline float3 lut_sample(texture2d<float> lut_tex, sampler samp, float t) {
    return lut_tex.sample(samp, float2(saturate(t), 0.5)).rgb;
}
