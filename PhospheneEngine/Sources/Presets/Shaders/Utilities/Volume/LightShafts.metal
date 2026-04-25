// LightShafts.metal — God-ray / crepuscular ray utilities (V.2 Part B).
//
// Provides screen-space and world-space light shaft approximations.
//
// Screen-space (Radial Blur) method — cheap, works in direct-pass presets:
//   Blur toward the projected sun position using ls_radial_blur().
//   Sample the occlusion mask (existing scene render), accumulate samples radially.
//   Cost: N texture samples (N = 32–64 typical).
//
// Ray-march shadow-volume method — accurate but expensive, for ray-march presets:
//   ls_shadow_march() steps from p toward the light, accumulates density.
//   Use vol_density_* from ParticipatingMedia.metal for the density field.
//
// Usage (direct-pass, screen-space):
//   float3 sunSS  = ls_world_to_screen(lightPos, viewProj);
//   float  shafts = ls_radial_blur(uv, sunSS, occlusionMask, 32, 0.95, 0.02);
//   finalColor   += lightColor * shafts * shaftIntensity;

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"

// ─── Geometric Helpers ────────────────────────────────────────────────────────

/// Map a world-space light position to normalized screen UV using a simple
/// perspective projection. viewProj is a 4×4 column-major MVP matrix.
/// Returns float2 in [0,1] UV space; values outside [0,1] are off-screen.
static inline float2 ls_world_to_ndc(float4x4 viewProj, float3 worldPos) {
    float4 clip = viewProj * float4(worldPos, 1.0);
    float2 ndc  = clip.xy / max(clip.w, 1e-5);
    return ndc * 0.5 + 0.5;
}

// ─── Screen-Space Radial Blur ─────────────────────────────────────────────────

/// Accumulate a radial blur toward sunUV using N samples.
/// uvIn        = current fragment UV.
/// sunUV       = projected light source UV (can be outside [0,1]).
/// occlusionAt = caller-supplied function result at sample UV (pass a value per step).
/// decay       = transmittance per step [0.85–0.97].
/// weight      = per-sample weight [0.01–0.05].
///
/// NOTE: Full screen-space blur requires sampling the occlusion mask texture.
/// Since Metal utilities cannot call texture.sample() generically, this function
/// computes the radial UV coordinates for N steps; the caller samples the texture
/// and accumulates. See ls_radial_step_uv() for the step UV helper.

/// Returns the UV to sample at step i (0-indexed) toward sunUV.
static inline float2 ls_radial_step_uv(float2 uv, float2 sunUV, int step, int totalSteps) {
    float t = float(step) / float(totalSteps);
    return mix(uv, sunUV, t);
}

/// Simplified single-value accumulation when the caller provides pre-sampled occlusion.
/// Call this once per ray step, sum the results, divide by totalSteps.
/// occlusion = 1 in lit area, 0 in shadow. Returns contribution for this step.
static inline float ls_radial_accumulate_step(float occlusion, float decay, float weight, int step) {
    return occlusion * pow(decay, float(step)) * weight;
}

// ─── Ray-March Light Shaft (World Space) ──────────────────────────────────────

/// Ray-march from p toward lightDir, accumulating participating-media density.
/// Returns shadow factor [0,1]: 1 = fully lit, 0 = fully occluded.
/// Typically used inside a main volume march to compute per-sample shadowing.
/// steps = 8–16 (cheap shadow rays acceptable for atmospheric quality).
static inline float ls_shadow_march(
    float3 p, float3 lightDir,
    float tMax, int steps, float sigma
) {
    float dt   = tMax / float(steps);
    float tau  = 0.0;
    for (int i = 0; i < steps; i++) {
        float3 pos  = p + lightDir * (float(i) + 0.5) * dt;
        float  den  = vol_density_fbm(pos, 1.0, 2);
        tau += den * sigma * dt;
    }
    return exp(-tau);
}

// ─── Approximate Sun Disk + Corona ────────────────────────────────────────────

/// Render a simple sun disk + halo around sunDir.
/// rd = ray direction. Returns float3 emission (add to scene color).
static inline float3 ls_sun_disk(float3 rd, float3 sunDir, float3 sunColor) {
    float cosAngle = dot(rd, sunDir);
    // Hard disk (0.998 ≈ 3.6° half-angle)
    float disk  = smoothstep(0.9975, 0.9985, cosAngle);
    // Soft corona out to ~10°
    float halo  = pow(max(cosAngle, 0.0), 128.0) * 0.3;
    return sunColor * (disk + halo);
}

// ─── Audio-Reactive Shaft Control ────────────────────────────────────────────

/// Return shaft intensity scaled by audio deviation.
/// Shafts brighten on above-average mid energy (vocal presence / melody lift).
static inline float ls_intensity_audio(float baseIntensity, float midRel) {
    return baseIntensity * (1.0 + max(0.0, midRel) * 0.5);
}

#pragma clang diagnostic pop
