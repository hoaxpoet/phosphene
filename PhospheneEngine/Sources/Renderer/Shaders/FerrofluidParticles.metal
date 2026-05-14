// FerrofluidParticles.metal — Phase 1 height-field bake for V.9 Session 4.5b.
//
// First compute kernel for the Ferrofluid Ocean particle-motion increment.
// Phase 1 produces a 512×512 r16Float height texture from 2048 particle
// positions using Quilez's polynomial smooth-min (Robert Leitl's
// `height-map.frag.glsl` technique, adopted verbatim per Failed Approach
// #65 — adopt working reference components, don't argue them away).
//
// References:
//   - Robert Leitl, "Ferrofluid" — https://robert-leitl.medium.com/ferrofluid-7fd5cb55bc8d
//   - Inigo Quilez, smooth-min — https://iquilezles.org/articles/smin/
//   - Inigo Quilez, `almostIdentity` — https://iquilezles.org/articles/functions/
//
// Phase 1 dispatches this kernel exactly once per preset apply (particles
// are static). Phase 2 will dispatch every frame as the SPH-lite particle
// update moves the particles.
//
// Output convention: each texel stores the spike-field height contribution
// at the world-XZ point mapped from the texel's UV. Range [0, 1]. The
// FerrofluidOcean `sceneSDF` then samples this and multiplies by the
// audio-routed `fo_spike_strength` (bass_energy_dev) to produce the final
// spike height in world units.

#include <metal_stdlib>
using namespace metal;

// ─── Uniform struct (mirror of Swift `FerrofluidParticles.BakeUniforms`) ───

struct FerrofluidBakeUniforms {
    float2 worldOriginXZ;       // world XZ corresponding to texture (0,0)
    float  worldSpan;           // world-unit width = height of the patch
    float  smoothMinW;          // Quilez polynomial smooth-min weight
    float  spikeBaseRadius;     // tent base radius in world units
    float  apexSmoothK;         // `almostIdentity` smoothing parameter
    uint   particleCount;       // active particle count (≤ 2048)
    uint   _pad0;               // 16-byte align
};

// ─── almostIdentity (Inigo Quilez) ─────────────────────────────────────────

/// Rounds values near zero. Below `m`, the function smoothly transitions
/// from `n` (apex) toward the identity. Used to soften the peak tips of
/// the spike cones after the smooth-min has produced a sharp local min.
///
/// Reference: https://iquilezles.org/articles/functions/ — `almostIdentity`.
static inline float almostIdentity(float x, float m, float n) {
    if (x > m) { return x; }
    float a = 2.0 * n - m;
    float b = 2.0 * m - 3.0 * n;
    float t = x / m;
    return (a * t + b) * t * t + n;
}

// ─── Polynomial smooth-min (Inigo Quilez) ──────────────────────────────────

/// Quadratic polynomial smooth-min: blends two distances into a single
/// distance that is C¹-continuous everywhere. `k` controls the blend
/// radius — small `k` (≪ 1) approaches `min(a, b)` (sharp); larger `k`
/// produces a softer transition between the two domains.
///
/// This is the formula in Robert Leitl's `height-map.frag.glsl`:
///
///     h = smoothstep(-1, 1, (a - b) / k);
///     m = mix(a, b, h) - h * (1 - h) * (k / (1 + 3 * k));
///
/// Reference: https://iquilezles.org/articles/smin/ — section
/// "polynomial smooth min".
static inline float poly_smin(float a, float b, float k) {
    float h = smoothstep(-1.0, 1.0, (a - b) / k);
    return mix(a, b, h) - h * (1.0 - h) * (k / (1.0 + 3.0 * k));
}

// ─── Bake kernel ───────────────────────────────────────────────────────────

/// One thread per output texel. Iterates all particles, accumulates a
/// smooth-min of distances, then converts the distance into a tent-shaped
/// height contribution falling from 1 at the particle to 0 at
/// `spikeBaseRadius`. Apex-smoothed via `almostIdentity` for ferrofluid
/// peak character (vs. perfect cones).
kernel void ferrofluid_height_bake(
    constant float2*                particles [[buffer(0)]],
    constant FerrofluidBakeUniforms& u         [[buffer(1)]],
    texture2d<float, access::write> heightTex [[texture(0)]],
    uint2                           gid       [[thread_position_in_grid]])
{
    uint w = heightTex.get_width();
    uint h = heightTex.get_height();
    if (gid.x >= w || gid.y >= h) { return; }

    // Texel UV → world XZ. UV (0.5, 0.5) is texel center within [0, 1].
    float2 uv = (float2(gid) + 0.5) / float2(w, h);
    float2 pXZ = u.worldOriginXZ + uv * u.worldSpan;

    // **Hard min over all particles (Phase 1 static-particle path).** Leitl's
    // `poly_smin` iteratively combined over N particles accumulates smoothing
    // as `O(w × log N)`; at w=0.02 / N=6000 the effective smoothing band is
    // ~0.17 wu, larger than the 0.15 spike base radius — neighbour peaks
    // bleed into each other and the valleys between them are lifted, so the
    // visual reads as merged ridges instead of distinct peaks (Matt's
    // 2026-05-14 beat-heavy review). Phase A's `voronoi_smooth` doesn't
    // suffer this because it only blends over 9 neighbour cells — bounded
    // smoothing band of ~0.017 wu, much smaller than the spike radius.
    //
    // For Phase 1's static particles, hard `min()` is the correct match to
    // Phase A's discrete-peak character. Phase 2 will need soft-min to
    // handle sub-frame motion discontinuities, but Leitl's actual recipe
    // uses a spatial-hash + nearest-K soft-min (not naïve all-pairs); that
    // bounded-K soft-min is the Phase 2 work. `smoothMinW` / `apexSmoothK`
    // are no longer consumed by the kernel but are retained on the Swift
    // side for Phase 2 reuse.
    float res = 1e6;
    for (uint i = 0; i < u.particleCount; i++) {
        float d = length(pXZ - particles[i]);
        res = min(res, d);
    }
    (void)u.smoothMinW;
    (void)u.apexSmoothK;

    // Tent-shaped height: 1 at the particle (res = 0), 0 at the spike base
    // radius. Negative output (when res > base) is clamped to 0 — gives
    // pure dark trough between non-touching peaks. (At "medium density"
    // with peaks touching base-to-base, the troughs only emerge where
    // particles are sparse, e.g. the patch edge after clamp-to-zero.)
    float height = max(0.0, 1.0 - res / u.spikeBaseRadius);
    heightTex.write(float4(height, 0.0, 0.0, 0.0), gid);
}
