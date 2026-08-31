// ColorSpaces.metal — Colour space conversion functions.
//
// All conversions operate in linear-light float3 values (no sRGB gamma applied
// here — presets work in linear HDR throughout). Callers are responsible for
// any gamma encode/decode at output boundaries.
//
// Conversions provided:
//   RGB ↔ HSV  — hue/saturation/value for artist-friendly colour control
//   RGB ↔ Lab  — perceptually uniform CIE L*a*b* via XYZ (D65 illuminant)
//   RGB ↔ Oklab — Björn Ottosson's perceptually uniform LCh replacement
//
// Reference: SHADER_CRAFT.md §11.2
//            https://bottosson.github.io/posts/oklab/
//            CIE D65 standard illuminant matrices.
//
// DO NOT add #include <metal_stdlib> or using namespace metal.

// Source: SHADER_CRAFT.md §11.2 — ColourSpaces

// ─── RGB ↔ HSV ────────────────────────────────────────────────────────────────

/// Linear RGB → HSV.
/// Input:  RGB each in [0, 1].
/// Output: H ∈ [0, 1) (hue), S ∈ [0, 1] (saturation), V ∈ [0, 1] (value).
static inline float3 rgb_to_hsv(float3 c) {
    float4 K = float4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    float4 p = c.g < c.b
        ? float4(c.b, c.g, K.w, K.z)
        : float4(c.g, c.b, K.x, K.y);
    float4 q = c.r < p.x
        ? float4(p.x, p.y, p.w, c.r)
        : float4(c.r, p.y, p.z, p.x);
    float d = q.x - min(q.w, q.y);
    float e = 1.0e-10;
    return float3(abs(q.z + (q.w - q.y) / (6.0 * d + e)),
                  d / (q.x + e),
                  q.x);
}

/// HSV → linear RGB.
/// Input:  H ∈ [0, 1), S ∈ [0, 1], V ∈ [0, 1].
/// Output: RGB each in [0, 1].
static inline float3 hsv_to_rgb(float3 c) {
    float3 p = abs(fract(c.xxx + float3(1.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
    return c.z * mix(float3(1.0), clamp(p - 1.0, 0.0, 1.0), c.y);
}

// ─── RGB ↔ CIE Lab (D65) ──────────────────────────────────────────────────────
// Intermediate XYZ uses D65 illuminant. Matrices from the standard.
// Linear RGB is assumed; no sRGB decoding step.

constant float3 kD65_W = float3(0.95047, 1.00000, 1.08883);  // D65 white point in XYZ

static inline float3 _linear_rgb_to_xyz(float3 c) {
    // sRGB (D65) to XYZ matrix (IEC 61966-2-1).
    return float3(
        dot(c, float3(0.4124564, 0.3575761, 0.1804375)),
        dot(c, float3(0.2126729, 0.7151522, 0.0721750)),
        dot(c, float3(0.0193339, 0.1191920, 0.9503041))
    );
}

static inline float3 _xyz_to_linear_rgb(float3 xyz) {
    // XYZ to sRGB (D65) matrix (inverse of above).
    return float3(
        dot(xyz, float3( 3.2404542, -1.5371385, -0.4985314)),
        dot(xyz, float3(-0.9692660,  1.8760108,  0.0415560)),
        dot(xyz, float3( 0.0556434, -0.2040259,  1.0572252))
    );
}

static inline float _lab_f(float t) {
    // CIE standard f(t) for XYZ → Lab.
    float delta = 6.0 / 29.0;
    return t > (delta * delta * delta)
        ? pow(t, 1.0 / 3.0)
        : t / (3.0 * delta * delta) + 4.0 / 29.0;
}

static inline float _lab_f_inv(float t) {
    float delta = 6.0 / 29.0;
    return t > delta
        ? t * t * t
        : 3.0 * delta * delta * (t - 4.0 / 29.0);
}

/// Linear RGB → CIE L*a*b* (D65 illuminant).
/// Output: L ∈ [0, 100], a* and b* ∈ [−128, +127].
static inline float3 rgb_to_lab(float3 c) {
    float3 xyz = _linear_rgb_to_xyz(c);
    float3 n   = xyz / kD65_W;
    float fx = _lab_f(n.x);
    float fy = _lab_f(n.y);
    float fz = _lab_f(n.z);
    return float3(
        116.0 * fy - 16.0,          // L*
        500.0 * (fx - fy),          // a*
        200.0 * (fy - fz)           // b*
    );
}

/// CIE L*a*b* → linear RGB (D65 illuminant).
/// Input: L ∈ [0, 100], a* and b* ∈ [−128, +127].
static inline float3 lab_to_rgb(float3 lab) {
    float fy = (lab.x + 16.0) / 116.0;
    float fx = lab.y / 500.0 + fy;
    float fz = fy - lab.z / 200.0;
    float3 xyz = float3(
        _lab_f_inv(fx),
        _lab_f_inv(fy),
        _lab_f_inv(fz)
    ) * kD65_W;
    return _xyz_to_linear_rgb(xyz);
}

// ─── RGB ↔ Oklab ─────────────────────────────────────────────────────────────
// Björn Ottosson's Oklab: perceptually uniform LCh replacement.
// Linear-light RGB input/output; no sRGB gamma involved.
// Reference: https://bottosson.github.io/posts/oklab/

static inline float3 rgb_to_oklab(float3 c) {
    // Step 1: linear RGB → LMS via M1.
    float3 lms = float3(
        dot(c, float3(0.4122214708, 0.5363325363, 0.0514459929)),
        dot(c, float3(0.2119034982, 0.6806995451, 0.1073969566)),
        dot(c, float3(0.0883024619, 0.2817188376, 0.6299787005))
    );
    // Step 2: cube root (perceptual non-linearity).
    float3 lms_ = pow(max(lms, float3(0.0)), float3(1.0 / 3.0));
    // Step 3: LMS_ → Lab via M2.
    return float3(
        dot(lms_, float3( 0.2104542553, 0.7936177850, -0.0040720468)),
        dot(lms_, float3( 1.9779984951, -2.4285922050, 0.4505937099)),
        dot(lms_, float3( 0.0259040371, 0.7827717662, -0.8086757660))
    );
}

/// Oklab → linear RGB.
/// Input: L ∈ [0, 1], a and b ∈ [−0.5, +0.5] approximately.
static inline float3 oklab_to_rgb(float3 lab) {
    // Step 1: Lab → LMS_ via M2 inverse.
    float3 lms_ = float3(
        dot(lab, float3(1.0000000000,  0.3963377774,  0.2158037573)),
        dot(lab, float3(1.0000000000, -0.1055613458, -0.0638541728)),
        dot(lab, float3(1.0000000000, -0.0894841775, -1.2914855480))
    );
    // Step 2: cube (inverse non-linearity).
    float3 lms = lms_ * lms_ * lms_;
    // Step 3: LMS → linear RGB via M1 inverse.
    return float3(
        dot(lms, float3( 4.0767416621, -3.3077115913,  0.2309699292)),
        dot(lms, float3(-1.2684380046,  2.6097574011, -0.3413193965)),
        dot(lms, float3(-0.0041960863, -0.7034186147,  1.7076147010))
    );
}
