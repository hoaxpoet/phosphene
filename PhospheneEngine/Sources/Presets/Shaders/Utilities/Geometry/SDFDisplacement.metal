// SDFDisplacement.metal — Lipschitz-safe SDF displacement utilities (V.2 Part A).
//
// Displacement adds surface detail by perturbing the SDF: f(p) = sdf(p) + d(p).
// Problem: if |∇d| > 0, the gradient |∇f| > 1, breaking sphere tracing.
//
// Lipschitz constraint: the SDF must have |∇f| ≤ 1 for sphere tracing to be
// valid. Adding displacement d with gradient magnitude L gives |∇f| ≤ 1 + L.
//
// Fix: scale the displaced SDF by 1/(1 + L) so the bound returns to 1.
//   For noise with amplitude A and frequency F: L ≈ A * F * C
//   (C ≈ 1 for Perlin, 2 for Worley). A safe conservative bound is L = A * F.
//
// IMPORTANT: the Lipschitz-safe functions below take pre-evaluated displacement
// values (not function pointers). Evaluate the displacement yourself — with
// fbm8, perlin3d, worley3d, etc. — and pass the float result. This keeps the
// API compatible with Metal fragment shaders (no function pointers).
//
// Reference: Keinert et al. "Enhanced Sphere Tracing" (2014).

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"

// ─── Core Lipschitz-safe Helpers ─────────────────────────────────────────────

/// Apply pre-evaluated displacement `disp` to `baseSDF` with Lipschitz safety.
///
/// `maxGradientMag` is the maximum |∇disp| you can bound analytically.
/// For Perlin noise with amplitude A and frequency F: maxGradientMag ≈ A * F.
/// Result is a valid lower-bound SDF with Lipschitz constant ≤ 1.
static inline float displace_lipschitz_safe(float baseSDF, float disp,
                                             float maxGradientMag) {
    float safeScale = 1.0 / (1.0 + maxGradientMag);
    return (baseSDF + disp) * safeScale;
}

/// Convenience: clamp displacement to [-maxAmplitude, maxAmplitude] before
/// applying. Prevents runaway values from broken noise at extreme coordinates.
static inline float displace_clamped(float baseSDF, float disp,
                                     float maxAmplitude, float maxGradientMag) {
    float clampedDisp = clamp(disp, -maxAmplitude, maxAmplitude);
    return displace_lipschitz_safe(baseSDF, clampedDisp, maxGradientMag);
}

// ─── Noise-based Displacement (unsafe — caller controls Lipschitz) ────────────
// These functions use Perlin noise from the V.1 preamble (perlin3d).
// They are NOT Lipschitz-safe by default; wrap with displace_lipschitz_safe.
// Provided for convenience when authoring displacement in sceneSDF.

/// Evaluate perlin3d(p * frequency) * amplitude. Pass to displace_lipschitz_safe.
static inline float displacement_noise(float3 p, float frequency, float amplitude) {
    return perlin3d(p * frequency) * amplitude;
}

/// FBM (8-octave) displacement. Richer than single-octave Perlin.
/// maxGradientMag estimate ≈ amplitude * frequency * 2 (fbm compounds gradients).
static inline float displacement_fbm(float3 p, float frequency, float amplitude) {
    return fbm8(p * frequency) * amplitude;
}

/// Worley-based displacement for cracked / cellular surface detail.
/// maxGradientMag estimate ≈ amplitude * frequency.
static inline float displacement_worley(float3 p, float frequency, float amplitude) {
    return worley3d(p * frequency).x * amplitude;
}

// ─── Convenience: Noise + Lipschitz Combined ─────────────────────────────────
// These are the most common patterns in one call.

/// Perlin displacement, Lipschitz-safe. Conservative for frequency ≤ 4.
/// Internally: perlin3d(p * frequency) * amplitude, then scale by 1/(1 + A*F).
static inline float displace_perlin(float3 p, float baseSDF,
                                    float frequency, float amplitude) {
    float disp = perlin3d(p * frequency) * amplitude;
    return displace_lipschitz_safe(baseSDF, disp, amplitude * frequency);
}

/// FBM displacement, Lipschitz-safe. maxGradientMag scaled by 2 for fBM.
static inline float displace_fbm(float3 p, float baseSDF,
                                  float frequency, float amplitude) {
    float disp = fbm8(p * frequency) * amplitude;
    return displace_lipschitz_safe(baseSDF, disp, amplitude * frequency * 2.0);
}

// ─── Height-field Displacement ────────────────────────────────────────────────

/// Displace a surface by a height value along the surface normal direction.
/// `normalDir` = the surface normal (unit vector) at p.
/// `height` = signed height offset (positive = outward, negative = inward).
/// `scale` = overall multiplier.
/// NOTE: This is geometrically correct only near-perpendicular incidence;
/// grazing rays may overstep. Use conservative scale 0.5 for steep normals.
static inline float displace_height(float3 p, float baseSDF,
                                    float3 normalDir, float height, float scale) {
    float disp = dot(normalDir, float3(1.0)) * height * scale;
    return baseSDF + disp;
}

// ─── Anisotropic Displacement ─────────────────────────────────────────────────

/// Displace in a given world-space direction. Useful for directional stretch
/// or material grain (e.g., wood fiber direction).
/// `direction` = unit vector of displacement axis.
/// `magnitude` = scale of displacement along that axis.
static inline float displace_anisotropic(float3 p, float baseSDF,
                                          float3 direction, float magnitude) {
    float projLen = dot(p, direction);
    float disp    = sin(projLen * 6.28318) * magnitude * 0.5;
    return displace_lipschitz_safe(baseSDF, disp, magnitude * 3.14159);
}

// ─── Audio-reactive Displacement ─────────────────────────────────────────────
// Convenience helpers for preset authoring; use deviation primitives (D-026).

/// Beat-anticipation displacement: ramps up before each predicted beat.
/// `beatPhase01` = FeatureVector.beat_phase01 (0 at beat, 1 approaching next).
/// `amplitude` = maximum displacement. `warmup` = smoothstep start (0.75–0.90).
static inline float displace_beat_anticipation(float3 p, float baseSDF,
                                                float beatPhase01,
                                                float amplitude, float warmup) {
    float ramp = smoothstep(warmup, 1.0, beatPhase01) * amplitude;
    float disp = perlin3d(p * 3.0) * ramp;
    return displace_lipschitz_safe(baseSDF, disp, amplitude * 3.0);
}

/// Energy-driven breathing displacement using bass deviation (D-026).
/// `bassAttRel` = FeatureVector.bass_att_rel (centred around 0, range ±0.5).
/// Expands/contracts surface proportional to energy above running average.
static inline float displace_energy_breath(float3 p, float baseSDF,
                                            float bassAttRel, float amplitude) {
    float energy = max(0.0, bassAttRel) * 2.0;   // only expand, not contract
    float disp   = perlin3d(p * 2.0) * energy * amplitude;
    return displace_lipschitz_safe(baseSDF, disp, amplitude * energy * 2.0 + 0.001);
}

#pragma clang diagnostic pop
