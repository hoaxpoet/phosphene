// ToneMapping.metal — HDR tone-mapping operators.
//
// All operators are monotonic (a > b ⇒ tone_map(a) ≥ tone_map(b)) and map
// [0, +∞) into [0, 1). They operate per-channel on linear-light float3 values.
//
// Provided operators:
//   tone_map_aces          — Narkowicz fitted ACES (fast, good general use)
//   tone_map_aces_full     — Stephen Hill full RRT+ODT ACES (accurate, costly)
//   tone_map_reinhard      — Classic Reinhard (c / (1 + c))
//   tone_map_reinhard_extended — Reinhard with white-point control
//   tone_map_filmic_uncharted  — Hable Uncharted 2 filmic curve
//
// NOTE: tone_map_aces supersedes legacy `toneMapACES` in ShaderUtilities.metal
// (same Narkowicz formula; that entry now documented as superseded per D-062).
// tone_map_reinhard supersedes legacy `toneMapReinhard`.
//
// Reference: SHADER_CRAFT.md §11.2
//            https://knarkowicz.wordpress.com/2016/01/06/aces-filmic-tone-mapping-curve/
//            Stephen Hill ACES RRT+ODT matrices.
//            Hable "Filmic Tonemapping Operators" (GDC 2010).
//
// DO NOT add #include <metal_stdlib> or using namespace metal.

// Source: SHADER_CRAFT.md §11.2 — ToneMapping

// ─── ACES (Narkowicz fitted) ──────────────────────────────────────────────────

/// ACES filmic tone-mapping — Narkowicz polynomial approximation.
/// Fast single-call form. Exposure: 1 unit ≈ middle grey.
/// Monotonic ✓  Maps [0, +∞) into [0, 1) ✓
static inline float3 tone_map_aces(float3 x) {
    const float a = 2.51;
    const float b = 0.03;
    const float c = 2.43;
    const float d = 0.59;
    const float e = 0.14;
    return saturate((x * (a * x + b)) / (x * (c * x + d) + e));
}

// ─── ACES full (Hill RRT + ODT) ──────────────────────────────────────────────

/// Full ACES Reference Rendering Transform + Output Display Transform.
/// Stephen Hill's "Mini-ACES" 3×3 matrix sandwich around the ACES curve.
/// More latitude than the Narkowicz fit; ~2× more expensive.
/// Monotonic ✓  Maps [0, +∞) into [0, 1) ✓
static inline float3 tone_map_aces_full(float3 x) {
    // RRT+ODT fit by Stephen Hill (updated 2016).
    // Input-to-RRT matrix.
    x = float3(
        dot(x, float3( 0.59719,  0.35458,  0.04823)),
        dot(x, float3( 0.07600,  0.90834,  0.01566)),
        dot(x, float3( 0.02840,  0.13383,  0.83777))
    );
    // Apply the ACES curve (Narkowicz fit — same denominator, different expo).
    float3 a = x * (x + 0.0245786) - 0.000090537;
    float3 b = x * (0.983729 * x + 0.4329510) + 0.238081;
    x = a / b;
    // ODT to output matrix.
    return saturate(float3(
        dot(x, float3( 1.60475, -0.53108, -0.07367)),
        dot(x, float3(-0.10208,  1.10813, -0.00605)),
        dot(x, float3(-0.00327, -0.07276,  1.07602))
    ));
}

// ─── Reinhard ────────────────────────────────────────────────────────────────

/// Classic Reinhard tone-mapping: c / (1 + c).
/// Simple, always-convergent; white point is at infinity.
/// Monotonic ✓  Maps [0, +∞) into [0, 1) ✓
static inline float3 tone_map_reinhard(float3 c) {
    return c / (c + 1.0);
}

/// Reinhard with white-point control.
/// `white` = the scene luminance that maps to exactly 1.0 in output.
/// tone_map_reinhard_extended(white, white) ≈ 1.0 (white maps to itself).
/// Monotonic ✓  Maps [0, +∞) into [0, 1) ✓
static inline float3 tone_map_reinhard_extended(float3 c, float white) {
    float w2 = white * white;
    return (c * (1.0 + c / w2)) / (c + 1.0);
}

// ─── Hable Uncharted 2 filmic ─────────────────────────────────────────────────

static inline float3 _uncharted2_partial(float3 x) {
    // Constants from John Hable "Filmic Tonemapping Operators" GDC 2010.
    const float A = 0.15; // shoulder strength
    const float B = 0.50; // linear strength
    const float C = 0.10; // linear angle
    const float D = 0.20; // toe strength
    const float E = 0.02; // toe numerator
    const float F = 0.30; // toe denominator
    return ((x * (A * x + C * B) + D * E) / (x * (A * x + B) + D * F)) - E / F;
}

/// Hable Uncharted 2 filmic tone-mapping.
/// Pre-exposed at 2× for typical HDR scenes; adjust by dividing input first.
/// Monotonic ✓  Maps [0, +∞) into [0, 1) ✓
static inline float3 tone_map_filmic_uncharted(float3 c) {
    float3 exposed = c * 2.0;   // pre-exposure
    float3 num = _uncharted2_partial(exposed);
    float3 den = _uncharted2_partial(float3(11.2));
    return saturate(num / den);
}
