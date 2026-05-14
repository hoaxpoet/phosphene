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

// ─── Per-particle state (mirror of Swift `FerrofluidParticles.Particle`) ───

/// 16-byte particle struct: position + velocity, both world-XZ. Phase 2b
/// extended from a bare `float2` position. Velocity is in world units per
/// second; Phase 2b's update kernel integrates `pos += vel × dt` per frame.
struct FerrofluidParticle {
    float2 position;
    float2 velocity;
};

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

/// Per-frame update uniforms (mirror of Swift `UpdateUniforms`).
/// Phase 2c extended for force model + spatial-hash neighbour lookup.
struct FerrofluidUpdateUniforms {
    float dt;                       // seconds since previous update
    uint  particleCount;            // active particle count
    float accumulatedAudioTime;     // energy-paused time axis
    float arousal;                  // [-1, 1] global force magnitude scale

    float bassEnergyDev;            // pressure radius scale
    float drumsEnergyDevSmoothed;   // radial impulse magnitude (150 ms τ)
    float otherEnergyDev;           // tangential rotation rate
    float pressureBaseRadius;       // baseline inter-particle repulsion range

    float2 worldOriginXZ;           // shared with bake uniforms
    float  worldSpan;
    uint   cellGridSide;

    uint cellSlotCapacity;
    uint gridColumns;               // canonical-position grid X count (80)
    uint gridRows;                  // canonical-position grid Z count (75)
    uint _pad0;
};

// ─── Canonical-position helper (mirror of Swift `canonicalInitialPosition`) ───

/// Reproduces `FerrofluidParticles.canonicalInitialPosition(forIndex:)` on
/// the GPU side so each particle can be sprung back toward its equilibrium
/// XZ during silence. Port of `voronoi_cell_offset` from
/// `Presets/Shaders/Utilities/Texture/Voronoi.metal`, integer-width safe.
static inline float2 fo_canonical_position(uint i, constant FerrofluidUpdateUniforms& u) {
    uint cols = u.gridColumns;
    uint rows = u.gridRows;
    uint row = i / cols;
    uint col = i - row * cols;
    int  cx  = int(col);
    int  cy  = int(row);
    int  qx  = cx * 1453 + cy * 2971;
    int  qy  = cx * 3539 + cy * 1117;
    int  hx  = (qx ^ (qx >> 9)) * 0x45D9F3B;
    int  hy  = (qy ^ (qy >> 9)) * 0x45D9F3B;
    float2 hashOffset = float2(float(hx & 0xFFFF), float(hy & 0xFFFF)) / 65535.0;
    float scaledX = float(col) + hashOffset.x;
    float scaledZ = float(row) + hashOffset.y;
    float normX   = scaledX / float(cols);
    float normZ   = scaledZ / float(rows);
    return u.worldOriginXZ + float2(normX, normZ) * u.worldSpan;
}

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
    constant FerrofluidParticle*     particles  [[buffer(0)]],
    constant FerrofluidBakeUniforms& u          [[buffer(1)]],
    device atomic_uint*              cellCounts [[buffer(2)]],
    device uint*                     cellSlots  [[buffer(3)]],
    uint                             gid        [[thread_position_in_grid]])
{
    if (gid >= u.particleCount) { return; }
    float2 pXZ = particles[gid].position;
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

// ─── Particle update kernel (Phase 2c: force model + semi-implicit Euler) ─

/// Per-particle force-and-integrate. Reads the spatial-hash buffers
/// populated by the most recent bake pass to find neighbours within 3×3
/// cells for pressure computation. Force model:
///
///   F_pressure     — SPH-lite outward repulsion from neighbours within
///                    `pressureBaseRadius × (1 + bass_energy_dev × bassCoef)`.
///                    `bass_energy_dev` is the only audio-modulated radius;
///                    other forces use fixed scales.
///   F_equilibrium  — Spring back toward the particle's canonical voronoi-
///                    cell-centre XZ. Provides the silence-state restoring
///                    force so when audio energy drops to zero, particles
///                    settle to canonical positions per the V.9 4.5b spec.
///   F_rotation     — Tangential force around patch centre, scaled by
///                    `other_energy_dev`. Per Failed Approach #33, NOT
///                    sourced from `sin(time × constant)` — the
///                    energy-paused `accumulated_audio_time` axis is read
///                    only as a smooth time argument (currently unused;
///                    reserved for future Phase 3 audio variants).
///   F_drums        — Radial-outward impulse scaled by the 150 ms-smoothed
///                    `drums_energy_dev`. Smoothed → no edge triggering;
///                    satisfies `check_drums_beat_intensity.sh`.
///   F_damping      — Viscous drag `-cv` prevents runaway acceleration.
///   F_total       *= `0.5 + max(0, arousal) × 0.5` (arousal global scale,
///                    never zero so silent-state damping still applies).
kernel void ferrofluid_particle_update(
    device FerrofluidParticle*           particles  [[buffer(0)]],
    constant FerrofluidUpdateUniforms& u            [[buffer(1)]],
    constant uint*                       cellCounts [[buffer(2)]],
    constant uint*                       cellSlots  [[buffer(3)]],
    uint                                 gid        [[thread_position_in_grid]])
{
    if (gid >= u.particleCount) { return; }
    FerrofluidParticle p = particles[gid];

    // Per-particle equilibrium (silence rest position).
    float2 canonical = fo_canonical_position(gid, u);

    // Patch-centre relative geometry (drums / rotation forces).
    float2 patchCentre = u.worldOriginXZ + u.worldSpan * 0.5;
    float2 fromCentre  = p.position - patchCentre;
    float  radius      = max(length(fromCentre), 1e-4);
    float2 radial      = fromCentre / radius;
    float2 tangent     = float2(-radial.y, radial.x);    // CCW perpendicular

    // ── F_pressure: SPH-lite outward repulsion from neighbours ──
    // Gated by `bass_energy_dev` — at silence (bass = 0) pressure is
    // zero everywhere, satisfying the V.9 4.5b "silence: particles
    // settle to low-energy equilibrium" spec. Radius is fixed at the
    // baseline (1.2 × particle spacing) so the pressure region stays
    // localized regardless of bass; bass scales the **force magnitude**.
    float2 pressureForce = float2(0.0, 0.0);
    float  pressureRadius = u.pressureBaseRadius;
    // Map current position to spatial-hash cell.
    float2 normalized = (p.position - u.worldOriginXZ) / u.worldSpan;
    int gx = clamp(int(floor(normalized.x * float(u.cellGridSide))),
                   0, int(u.cellGridSide) - 1);
    int gy = clamp(int(floor(normalized.y * float(u.cellGridSide))),
                   0, int(u.cellGridSide) - 1);
    int side = int(u.cellGridSide);
    for (int dy = -1; dy <= 1; dy++) {
        int cy = gy + dy;
        if (cy < 0 || cy >= side) { continue; }
        for (int dx = -1; dx <= 1; dx++) {
            int cx = gx + dx;
            if (cx < 0 || cx >= side) { continue; }
            uint flat = uint(cy) * u.cellGridSide + uint(cx);
            uint count = min(cellCounts[flat], u.cellSlotCapacity);
            for (uint k = 0; k < count; k++) {
                uint otherIdx = cellSlots[flat * u.cellSlotCapacity + k];
                if (otherIdx == gid) { continue; }
                float2 toMe = p.position - particles[otherIdx].position;
                float  dist = length(toMe);
                if (dist > 1e-4 && dist < pressureRadius) {
                    float falloff = (pressureRadius - dist) / pressureRadius;
                    pressureForce += (toMe / dist) * (falloff * falloff) * 6.0;
                }
            }
        }
    }
    pressureForce *= u.bassEnergyDev;

    // ── F_equilibrium: spring back to canonical (silence rest) ──
    float2 equilibriumForce = (canonical - p.position) * 4.0;

    // ── F_rotation: tangential drift around patch centre ──
    // Angular velocity proportional to `other_energy_dev`. Tangent ×
    // radius keeps angular velocity constant across the patch (all
    // particles rotate at same ω regardless of radius from centre).
    float angularVelocity = u.otherEnergyDev * 0.5;     // rad/s at full energy
    float2 rotationForce = tangent * angularVelocity * radius * 1.0;

    // ── F_drums: radial outward shock impulse ──
    float2 drumsForce = radial * u.drumsEnergyDevSmoothed * 3.5;

    // ── F_damping: viscous drag ──
    float2 dampingForce = p.velocity * -3.5;

    // Sum + arousal scale (never reach zero so silence still damps).
    float2 totalForce = pressureForce + equilibriumForce + rotationForce + drumsForce + dampingForce;
    float arousalScale = 0.6 + max(0.0, u.arousal) * 0.5;
    totalForce *= arousalScale;

    // Semi-implicit Euler — update velocity first, then advance position
    // using the new velocity. More stable than forward Euler for spring
    // systems with damping.
    p.velocity += totalForce * u.dt;
    p.position += p.velocity * u.dt;

    particles[gid] = p;
}

// ─── Bake kernel: per-texel 3×3 cell lookup + bounded-K soft-min ───────────

kernel void ferrofluid_height_bake(
    constant FerrofluidParticle*     particles  [[buffer(0)]],
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
                float d = length(pXZ - particles[particleIdx].position);
                res = poly_smin(res, d, u.smoothMinW);
            }
        }
    }

    // Linear cone: 1 at the particle (res = 0), 0 at `spikeBaseRadius`.
    // Negative output (when res > base) is clamped to 0.
    float height = max(0.0, 1.0 - res / u.spikeBaseRadius);
    // V.9 Session 4.5c Phase 1 round 4: squared profile (`h² `). Squaring
    // pulls valley heights toward zero faster than the linear cone — at
    // midpoint between adjacent particles, raw height ≈ 0.17 → squared
    // ≈ 0.030 (~3% of peak). Apex slope at res=0 is steeper (`-2/R` vs
    // `-1/R` linear), making spike tips read more pointed. Combined with
    // `smoothMinW = 0.005` (tightened from 0.02 in this same round), the
    // bake produces near-discrete-spike topology with near-pitch-black
    // valleys per `04_specular_razor_highlights.jpg`. Linear cone profile
    // preserved on the inline diagnostic path (`fo_ferrofluid_field_inline`
    // in `FerrofluidOcean.metal`) for A/B comparison.
    height *= height;
    heightTex.write(float4(height, 0.0, 0.0, 0.0), gid);
}
