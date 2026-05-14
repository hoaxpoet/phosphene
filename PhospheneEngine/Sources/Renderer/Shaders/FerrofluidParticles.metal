// FerrofluidParticles.metal — Phase 2a height-field bake for V.9 Session 4.5b.
//
// Three kernels chain to produce the height texture from moving (or static)
// particles. Replaces Phase 1's single-kernel hard-min-over-N approach,
// which was a dead end for Phase 2 motion (the soft-min smoothing band of
// poly_smin accumulates as O(w × log N), exceeding the spike base radius at
// N=6000 and causing peaks to merge into ridges).
//
// The new chain mirrors Leitl's spatial-hash recipe (his WebGL ferrofluid
// uses a sort+offset chain; Apple Silicon's atomic primitives let us
// achieve the same effect more directly):
//
//   ferrofluid_reset_cell_counts  — one thread per cell zeroes the
//                                   spatial-hash occupancy counter.
//   ferrofluid_bin_particles      — one thread per particle atomically
//                                   reserves a slot in its cell and
//                                   writes its index there.
//   ferrofluid_height_bake        — one thread per texel reads the 3×3
//                                   neighbour cells around its world XZ,
//                                   soft-mins the distances to the
//                                   bounded (~9-18) neighbour particles,
//                                   applies the linear cone.
//
// Bounded-K soft-min keeps the smoothing band constant regardless of
// total particle count, matching Phase A `voronoi_smooth`'s 9-neighbour
// pattern. Phase 1's hard-min over all N would not survive Phase 2 motion
// (sub-frame distance discontinuities at particle transitions).
//
// References:
//   - Robert Leitl, "Ferrofluid" — https://robert-leitl.medium.com/ferrofluid-7fd5cb55bc8d
//   - Inigo Quilez, smooth-min — https://iquilezles.org/articles/smin/

#include <metal_stdlib>
using namespace metal;

// ─── Uniform struct (mirror of Swift `FerrofluidParticles.BakeUniforms`) ───

struct FerrofluidBakeUniforms {
    float2 worldOriginXZ;       // world XZ corresponding to texture (0,0)
    float  worldSpan;           // world-unit width = height of the patch
    float  smoothMinW;          // Quilez polynomial smooth-min weight
    float  spikeBaseRadius;     // tent base radius in world units
    float  apexSmoothK;         // `almostIdentity` smoothing parameter (currently unused; reserved)
    uint   particleCount;       // active particle count
    uint   cellGridSide;        // spatial-hash grid side length (e.g. 64)
    uint   cellSlotCapacity;    // particles-per-cell upper bound (e.g. 16)
    uint   _pad0;
    uint   _pad1;
};

// ─── Polynomial smooth-min (Inigo Quilez) ──────────────────────────────────

/// Quadratic polynomial smooth-min. With bounded neighbour counts (~9-18
/// after spatial-hash lookup), `w × log(K)` smoothing-band-accumulation
/// stays small enough that even tight `w` (~0.02) produces discrete peaks.
/// Reference: https://iquilezles.org/articles/smin/
static inline float poly_smin(float a, float b, float k) {
    float h = smoothstep(-1.0, 1.0, (a - b) / k);
    return mix(a, b, h) - h * (1.0 - h) * (k / (1.0 + 3.0 * k));
}

// ─── Cell index helpers ────────────────────────────────────────────────────

/// World XZ → cell coordinate (uint2 within [0, cellGridSide)). Clamped at
/// boundary; out-of-patch positions map to the nearest edge cell.
static inline uint2 fo_cell_coord(float2 xz, constant FerrofluidBakeUniforms& u) {
    float2 normalized = (xz - u.worldOriginXZ) / u.worldSpan;       // [0,1] inside patch
    int gx = int(floor(normalized.x * float(u.cellGridSide)));
    int gy = int(floor(normalized.y * float(u.cellGridSide)));
    gx = clamp(gx, 0, int(u.cellGridSide) - 1);
    gy = clamp(gy, 0, int(u.cellGridSide) - 1);
    return uint2(uint(gx), uint(gy));
}

/// 2D cell coordinate → flat index into the cell count / slot buffers.
static inline uint fo_cell_flat(uint2 cell, uint gridSide) {
    return cell.y * gridSide + cell.x;
}

// ─── Reset kernel: zero per-cell occupancy counters ────────────────────────

kernel void ferrofluid_reset_cell_counts(
    device atomic_uint*              cellCounts [[buffer(0)]],
    constant FerrofluidBakeUniforms& u          [[buffer(1)]],
    uint                             gid        [[thread_position_in_grid]])
{
    uint total = u.cellGridSide * u.cellGridSide;
    if (gid >= total) { return; }
    atomic_store_explicit(&cellCounts[gid], 0u, memory_order_relaxed);
}

// ─── Bin kernel: each particle reserves a slot in its cell ─────────────────

kernel void ferrofluid_bin_particles(
    constant float2*                 particles  [[buffer(0)]],
    constant FerrofluidBakeUniforms& u          [[buffer(1)]],
    device atomic_uint*              cellCounts [[buffer(2)]],
    device uint*                     cellSlots  [[buffer(3)]],
    uint                             gid        [[thread_position_in_grid]])
{
    if (gid >= u.particleCount) { return; }
    float2 pXZ = particles[gid];
    uint2  cell = fo_cell_coord(pXZ, u);
    uint   flat = fo_cell_flat(cell, u.cellGridSide);
    // Reserve the next slot. Overflow (cell already at capacity) is
    // silently dropped — undercounted cells are visually identical to
    // sparser regions and the slot capacity is sized 8-16× equilibrium
    // density for Phase 2 motion headroom.
    uint slot = atomic_fetch_add_explicit(&cellCounts[flat], 1u, memory_order_relaxed);
    if (slot < u.cellSlotCapacity) {
        cellSlots[flat * u.cellSlotCapacity + slot] = gid;
    }
}

// ─── Bake kernel: per-texel 3×3 cell lookup + bounded-K soft-min ───────────

kernel void ferrofluid_height_bake(
    constant float2*                 particles  [[buffer(0)]],
    constant FerrofluidBakeUniforms& u          [[buffer(1)]],
    constant uint*                   cellCounts [[buffer(2)]],
    constant uint*                   cellSlots  [[buffer(3)]],
    texture2d<float, access::write>  heightTex  [[texture(0)]],
    uint2                            gid        [[thread_position_in_grid]])
{
    uint w = heightTex.get_width();
    uint h = heightTex.get_height();
    if (gid.x >= w || gid.y >= h) { return; }

    // Texel UV → world XZ. UV (0.5, 0.5) is texel center within [0, 1].
    float2 uv = (float2(gid) + 0.5) / float2(w, h);
    float2 pXZ = u.worldOriginXZ + uv * u.worldSpan;

    // Locate the centre cell, then loop 3×3 neighbours.
    uint2 centre = fo_cell_coord(pXZ, u);
    int side = int(u.cellGridSide);
    int cap = int(u.cellSlotCapacity);

    // Seed `res` large; soft-min collapses toward the nearest particle's
    // distance. Bounded-K (typical 1-18 particles) keeps smoothing-band
    // accumulation small.
    float res = 1e6;
    for (int dy = -1; dy <= 1; dy++) {
        int cy = int(centre.y) + dy;
        if (cy < 0 || cy >= side) { continue; }
        for (int dx = -1; dx <= 1; dx++) {
            int cx = int(centre.x) + dx;
            if (cx < 0 || cx >= side) { continue; }
            uint flat = uint(cy) * u.cellGridSide + uint(cx);
            uint count = min(cellCounts[flat], u.cellSlotCapacity);
            for (uint i = 0; i < count; i++) {
                uint particleIdx = cellSlots[flat * u.cellSlotCapacity + i];
                float d = length(pXZ - particles[particleIdx]);
                res = poly_smin(res, d, u.smoothMinW);
            }
        }
    }

    // Linear cone: 1 at the particle (res = 0), 0 at `spikeBaseRadius`.
    // Negative output (when res > base) is clamped to 0.
    float height = max(0.0, 1.0 - res / u.spikeBaseRadius);
    heightTex.write(float4(height, 0.0, 0.0, 0.0), gid);
}
