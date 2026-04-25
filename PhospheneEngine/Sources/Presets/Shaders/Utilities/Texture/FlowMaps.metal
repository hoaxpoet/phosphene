// FlowMaps.metal — Flow map and advection utilities (V.2 Part C).
//
// Flow maps encode per-pixel velocity fields (dx, dy) stored in RG texture channels.
// Sampling along a flow map gives temporally stable animated texture distortion
// without visible seams — used for water, lava, plasma, and cloth simulation.
//
// These utilities provide:
//   flow_sample_offset  — compute distorted UV at a given time phase
//   flow_blend          — dual-phase blend to hide the repeating cycle
//   flow_curl_advect    — advect a UV by a curl-noise velocity field (no texture needed)
//   flow_noise_velocity — compute per-pixel velocity from noise gradient (no texture)
//
// Usage (texture-based, 2 samples + blend):
//   float2 uv0 = flow_sample_offset(uv, flowVelocity, phase);
//   float2 uv1 = flow_sample_offset(uv, flowVelocity, phase + 0.5);
//   float  w   = flow_blend_weight(phase);
//   float3 col = texture.sample(s, uv0) * w + texture.sample(s, uv1) * (1.0-w);
//
// Usage (procedural, no texture):
//   float2 vel = flow_noise_velocity(uv, scale, t);
//   float2 distortedUV = uv + vel * strength;

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"

// ─── Texture-Based Flow Sampling ─────────────────────────────────────────────

/// Compute distorted UV by advecting along velocity field.
/// uv       = base UV. velocity = flow direction + speed (world-units/s).
/// phase    = animation phase ∈ [0,1] (caller cycles this with fract(t/period)).
/// strength = displacement amplitude.
static inline float2 flow_sample_offset(float2 uv, float2 velocity, float phase, float strength) {
    return uv + velocity * (phase - 0.5) * strength;
}

/// Blend weight for dual-phase flow sampling.
/// Returns smooth weight for phase A; weight for phase B = 1.0 - result.
/// Crossfades around phase 0 and 0.5 to hide the seam.
static inline float flow_blend_weight(float phase) {
    float cycle = fract(phase);
    return 1.0 - smoothstep(0.4, 0.6, cycle);
}

// ─── Curl-Noise Advection (Procedural) ───────────────────────────────────────

/// Compute a curl-noise velocity field at UV position p.
/// Uses finite differences on a 3D perlin field (p.xy + time slice) to get curl.
/// Returns float2 velocity in UV space.
static inline float2 flow_curl_velocity(float2 p, float scale, float t) {
    float eps = 0.01;
    float3 q  = float3(p * scale, t * 0.1);
    // Curl in 2D from 3D noise: dNz/dy, -dNz/dx
    float n0 = perlin3d(q + float3(0, eps, 0));
    float n1 = perlin3d(q - float3(0, eps, 0));
    float n2 = perlin3d(q + float3(eps, 0, 0));
    float n3 = perlin3d(q - float3(eps, 0, 0));
    float curlX =  (n0 - n1) / (2.0 * eps);
    float curlY = -(n2 - n3) / (2.0 * eps);
    return float2(curlX, curlY);
}

/// Advect UV by curl-noise velocity field over a time step dt.
/// Integrates with Euler step for simplicity (RK2 for higher fidelity).
static inline float2 flow_curl_advect(float2 uv, float scale, float t, float dt, float strength) {
    float2 vel = flow_curl_velocity(uv, scale, t);
    return uv + vel * dt * strength;
}

// ─── Noise Gradient Velocity ──────────────────────────────────────────────────

/// Estimate the 2D gradient of a noise field at p.
/// Returns float2 that can be used as a velocity / flow direction.
/// Useful for anisotropic texture distortion aligned to noise ridges.
static inline float2 flow_noise_velocity(float2 p, float scale, float t) {
    float eps = 0.005;
    float3 q  = float3(p * scale, t * 0.05);
    float dx = perlin3d(q + float3(eps, 0, 0)) - perlin3d(q - float3(eps, 0, 0));
    float dy = perlin3d(q + float3(0, eps, 0)) - perlin3d(q - float3(0, eps, 0));
    return float2(dx, dy) / (2.0 * eps);
}

// ─── Audio-Reactive Flow ──────────────────────────────────────────────────────

/// Flow-mapped UV distortion driven by audio.
/// bassRel controls flow speed (surge on transients), midRel controls turbulence.
/// t = accumulatedAudioTime. Returns distorted UV.
static inline float2 flow_audio(float2 uv, float scale, float t, float bassRel, float midRel) {
    float speed     = 0.3 + max(0.0, bassRel) * 0.4;
    float turbulence = 0.5 + max(0.0, midRel) * 0.5;
    return flow_curl_advect(uv, scale * turbulence, t, speed, 0.08);
}

// ─── Layered Flow Blend ───────────────────────────────────────────────────────

/// Combine two flow-advected noise layers for richer water / lava appearance.
/// Returns float [0,1] pattern value.
static inline float flow_layered(float2 uv, float scale, float t) {
    float2 a = flow_curl_advect(uv,         scale,       t,       1.0, 0.12);
    float2 b = flow_curl_advect(uv + 0.5,   scale * 1.7, t + 3.7, 1.0, 0.10);
    float na = perlin3d(float3(a * scale, t * 0.1)) * 0.5 + 0.5;
    float nb = perlin3d(float3(b * scale, t * 0.1)) * 0.5 + 0.5;
    return (na + nb) * 0.5;
}

#pragma clang diagnostic pop
