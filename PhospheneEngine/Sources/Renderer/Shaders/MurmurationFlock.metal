// MurmurationFlock.metal — Phase MM emergent starling-flock engine.
//
// GPU boids (Reynolds separation / alignment / cohesion) over grid-found
// neighbours + a soft global "roost" attractor + per-bird banking, simulated
// in 3D and projected to screen. The dense, morphing shape and the core→edge
// density gradient are EMERGENT (cohesion + separation + 3D projection), not a
// parametric envelope. See docs/presets/MURMURATION_DESIGN.md.
//
// Grounding: Robert Hodgin (GPU boids murmuration), Rama Hoetzlein (3-level
// flocking + global roost attractor), McGill biomechanics (≈7 topological
// neighbours, orientation-wave dark bands). Spatial-hash idiom mirrors
// FerrofluidParticles.metal (reset → bin(atomic) → consume, one encoder,
// memoryBarrier between dependent passes).
//
// MM.2 scope: the SILENCE BASELINE — a cohesive, density-graded, gently
// drifting mass. No audio coupling yet (the roost target drifts procedurally
// and the noise term sits at a low "critical" level). Audio drives the roost /
// orientation-wave / breathing in MM.3.
//
// This file is concatenated into the single engine-library compilation unit
// (alphabetical order, after Common.metal) — FeatureVector/helpers from
// Common.metal are visible here. Field names must be snake_case (FA #72); a
// syntax error here breaks the whole engine library.

#include <metal_stdlib>
using namespace metal;

// MARK: - Per-bird state (mirror of Swift MurmurationFlockGeometry.Bird, 48 bytes)

struct MurmurationBird {
    packed_float3 position;   // world-space, grid covers [-worldHalfSpan, +worldHalfSpan]^3
    float         seed;       // per-bird random [0,1] (stable)
    packed_float3 velocity;   // world units / second
    float         bank;       // smoothed banking amount [0,1] → orientation-wave darkening
    float         speedRnd;   // per-bird speed preference [0,1]
    float         neighborCount; // local neighbour count (edge detection for L4)
    float         pad0;
    float         pad1;
};

// MARK: - Flock parameters (mirror of Swift FlockParams, 144 bytes)

struct FlockParams {
    uint  particleCount;
    uint  gridSide;
    uint  cellCapacity;
    float dt;

    float time;
    float worldHalfSpan;
    float maxSpeed;
    float minSpeed;

    float maxForce;
    float cohesionRadius;
    float separationRadius;
    float alignmentRadius;

    float cohesionWeight;
    float separationWeight;
    float alignmentWeight;
    float roostWeight;

    float roostFar;           // distance-scaled containment (anti-fragmentation leash)
    float bankingRate;
    uint  neighborCap;
    float wanderWeight;

    float4 roostTarget;       // xyz = global flock centroid + slow drift bias (CPU-computed)

    // ── MM.3 audio coupling (all inert at zero audio → silence baseline) ──
    float4 flockAxis;         // xyz = unit elongation/wave axis, w = elongation [0, ~0.72]
    float4 drive;             // x = turnGain, y = beatValue, z = propDir (±1), w = waveWidth
    float  midEdgeGain;       // L4 mid edge-flutter amplitude (edge-weighted noise)
    float  flockExtent;       // nominal half-extent normalising the wave bird-coordinate
    float  audioPad0;
    float  audioPad1;
};

// MARK: - Hash helpers

inline float mf_hash11(float n) {
    return fract(sin(n) * 43758.5453123);
}

// 3D value hash → [-1,1]^3, used for per-bird wander.
inline float3 mf_hash33(float3 p) {
    float3 q = float3(dot(p, float3(127.1, 311.7, 74.7)),
                      dot(p, float3(269.5, 183.3, 246.1)),
                      dot(p, float3(113.5, 271.9, 124.6)));
    return -1.0 + 2.0 * fract(sin(q) * 43758.5453123);
}

// MARK: - Grid addressing

inline int3 mf_cell_coord(float3 pos, float halfSpan, uint side) {
    float3 n = (pos + halfSpan) / (2.0 * halfSpan);   // → [0,1] (may fall outside)
    int3 c = int3(floor(n * float(side)));
    return clamp(c, int3(0), int3((int)side - 1));
}

inline uint mf_cell_flat(int3 c, uint side) {
    return (uint)((c.z * (int)side + c.y) * (int)side + c.x);
}

// MARK: - Kernel 1: reset cell occupancy counts

kernel void murmuration_reset_cells(
    device atomic_uint*    cellCounts [[buffer(0)]],
    constant FlockParams&  fp         [[buffer(1)]],
    uint                   gid        [[thread_position_in_grid]])
{
    uint total = fp.gridSide * fp.gridSide * fp.gridSide;
    if (gid >= total) { return; }
    atomic_store_explicit(&cellCounts[gid], 0u, memory_order_relaxed);
}

// MARK: - Kernel 2: bin each bird into its grid cell (atomic slot reserve)

kernel void murmuration_bin(
    device const MurmurationBird* birds      [[buffer(0)]],
    constant FlockParams&         fp         [[buffer(1)]],
    device atomic_uint*           cellCounts [[buffer(2)]],
    device uint*                  cellSlots  [[buffer(3)]],
    uint                          gid        [[thread_position_in_grid]])
{
    if (gid >= fp.particleCount) { return; }
    float3 pos = float3(birds[gid].position);
    int3 c = mf_cell_coord(pos, fp.worldHalfSpan, fp.gridSide);
    uint flat = mf_cell_flat(c, fp.gridSide);
    uint slot = atomic_fetch_add_explicit(&cellCounts[flat], 1u, memory_order_relaxed);
    if (slot < fp.cellCapacity) {
        cellSlots[flat * fp.cellCapacity + slot] = gid;
    }
}

// MARK: - Kernel 3: boids integrator

kernel void murmuration_boids(
    device MurmurationBird*  birds      [[buffer(0)]],
    constant FlockParams&    fp         [[buffer(1)]],
    device atomic_uint*      cellCounts [[buffer(2)]],
    device const uint*       cellSlots  [[buffer(3)]],
    uint                     gid        [[thread_position_in_grid]])
{
    if (gid >= fp.particleCount) { return; }

    MurmurationBird b = birds[gid];
    float3 pos = float3(b.position);
    float3 vel = float3(b.velocity);

    int3 c = mf_cell_coord(pos, fp.worldHalfSpan, fp.gridSide);

    float3 cohSum = float3(0.0);
    float3 alignSum = float3(0.0);
    float3 sepSum = float3(0.0);
    float cohN = 0.0;
    float alignN = 0.0;
    float neighborN = 0.0;
    uint examined = 0u;

    float cohR2 = fp.cohesionRadius * fp.cohesionRadius;
    float alignR2 = fp.alignmentRadius * fp.alignmentRadius;
    float sepR = fp.separationRadius;
    float sepR2 = sepR * sepR;

    // 3×3×3 neighbourhood (cells sized ≈ cohesion radius).
    for (int dz = -1; dz <= 1; dz++) {
        for (int dy = -1; dy <= 1; dy++) {
            for (int dx = -1; dx <= 1; dx++) {
                int3 nc = c + int3(dx, dy, dz);
                if (nc.x < 0 || nc.y < 0 || nc.z < 0 ||
                    nc.x >= (int)fp.gridSide || nc.y >= (int)fp.gridSide || nc.z >= (int)fp.gridSide) {
                    continue;
                }
                uint flat = mf_cell_flat(nc, fp.gridSide);
                uint cnt = atomic_load_explicit(&cellCounts[flat], memory_order_relaxed);
                cnt = min(cnt, fp.cellCapacity);
                for (uint s = 0u; s < cnt; s++) {
                    if (examined >= fp.neighborCap) { break; }
                    uint j = cellSlots[flat * fp.cellCapacity + s];
                    if (j == gid) { continue; }
                    examined++;
                    float3 pj = float3(birds[j].position);
                    float3 d = pj - pos;
                    float dist2 = dot(d, d);
                    if (dist2 < cohR2) {
                        cohSum += pj;
                        cohN += 1.0;
                        neighborN += 1.0;
                    }
                    if (dist2 < alignR2) {
                        alignSum += float3(birds[j].velocity);
                        alignN += 1.0;
                    }
                    if (dist2 < sepR2 && dist2 > 1e-8) {
                        float dist = sqrt(dist2);
                        // Push away, stronger as they get closer.
                        sepSum -= (d / dist) * (1.0 - dist / sepR);
                    }
                }
                if (examined >= fp.neighborCap) { break; }
            }
            if (examined >= fp.neighborCap) { break; }
        }
        if (examined >= fp.neighborCap) { break; }
    }

    float3 accel = float3(0.0);

    // Cohesion — steer toward local centroid.
    if (cohN > 0.0) {
        float3 center = cohSum / cohN;
        accel += (center - pos) * fp.cohesionWeight;
    }
    // Alignment — match local average velocity.
    if (alignN > 0.0) {
        float3 avgVel = alignSum / alignN;
        accel += (avgVel - vel) * fp.alignmentWeight;
    }
    // Separation — local repulsion (already direction-weighted).
    accel += sepSum * fp.separationWeight;

    // Global attractor toward the flock centroid (+ drift bias). Distance-scaled
    // so far birds snap back hard — this is the anti-fragmentation leash: a
    // breakaway cluster is off-centroid → pulled strongly back → re-merges. The
    // base term gives gentle drift; the far term forbids persistent splits.
    //
    // L1 elongation (MM.3): under sustained bass the point attractor becomes a
    // GUIDE SEGMENT along the flock axis (Hoetzlein's moving guide-line). Each
    // bird is pulled to the nearest point on the segment, so the mass spreads
    // into a comma/ribbon of length ∝ elongation — stable (no positive
    // feedback) and collapses back to the point attractor at zero bass.
    float3 roostCentre = fp.roostTarget.xyz;
    float  elong = fp.flockAxis.w;
    float3 roostPoint = roostCentre;
    if (elong > 1e-4) {
        float halfLen = elong * fp.flockExtent * 1.6;
        float along   = clamp(dot(pos - roostCentre, fp.flockAxis.xyz), -halfLen, halfLen);
        roostPoint    = roostCentre + fp.flockAxis.xyz * along;
    }
    float3 toRoost = roostPoint - pos;
    float roostDist = length(toRoost);
    accel += toRoost * (fp.roostWeight + fp.roostFar * roostDist);

    // Wander — low per-bird noise (the "critical noise" that keeps the flock
    // alive without destroying coordination). Slowly-varying per bird.
    float3 wander = mf_hash33(float3(b.seed * 97.0, b.seed * 53.0, floor(fp.time * 1.7) + b.seed));
    accel += wander * fp.wanderWeight;

    // ── AUDIO COUPLING (MM.3) — ports the original Particles.metal brain ──
    // onto the boids substrate. Every term vanishes at zero audio, so the MM.2
    // silence baseline is preserved exactly. Substrate (bass elongation, mid
    // edge flutter; vocals breathing is applied CPU-side to the weights) is
    // continuous; the drum turning-wave is the punctuated, energy-gated event
    // layer (§3.1 — calm passages stay near-pure-substrate). `toRoost` and
    // `roostDist` are reused from the global-attractor block above.
    float waveBankBoost = 0.0;   // L2 wave darkening (applied to bank after integrate)
    {
        float3 axis = fp.flockAxis.xyz;
        // L1 elongation is applied in the guide-segment roost block above; this
        // block carries the L2 (drum wave) and L4 (mid edge flutter) routes.

        // L2 — drum turning-wave (the original's mechanic, ported). A banking
        // impulse sweeps across the flock-axis coordinate as the beat pulse
        // decays (waveFront = 1 − beatValue), direction alternating per
        // beat-epoch (propDir). The impulse is a ROTATION about the flock axis
        // — cross(axis, pos − centre) — so it sums to zero across the mass: it
        // makes birds in the band roll/turn (banking → the dark orientation
        // band) WITHOUT translating the whole flock (the accent must never
        // become a primary motion driver — FA #4 / Audio Data Hierarchy).
        // Amplitude is `drums_energy_dev × masterGate` (CPU), so the wave only
        // emerges as the music intensifies (§3.1 master lever).
        float turnGain = fp.drive.x;
        if (turnGain > 1e-5) {
            float3 toCentre = pos - fp.roostTarget.xyz;
            float coord = 0.5 + 0.5 * tanh(dot(toCentre, axis) / max(fp.flockExtent, 1e-3));
            float propDir       = fp.drive.z;
            float birdCoord     = (propDir > 0.0) ? coord : (1.0 - coord);
            float waveFront     = 1.0 - fp.drive.y;
            float waveWidth     = max(fp.drive.w, 1e-3);
            float waveInfluence = max(0.0, 1.0 - abs(waveFront - birdCoord) / waveWidth);
            // Tangential (curl) direction about the flock axis — zero net force.
            float3 curl = cross(axis, toCentre);
            float  cl   = length(curl);
            curl = (cl > 1e-4) ? curl / cl : float3(0.0);
            accel += curl * (turnGain * waveInfluence * propDir);
            // Orientation-wave darkening: the band IS where birds present more
            // wing (McGill). Driven by the DECOUPLED darkening amplitude
            // (audioPad0), NOT the gentle curl force — so the dark band reads
            // strong while the physical roll stays small enough not to translate
            // the flock (the M7 failure was a strong force, not strong shading).
            waveBankBoost = waveInfluence * clamp(fp.audioPad0, 0.0, 1.0);
        }

        // L4 — mid edge flutter. Fast per-bird noise weighted toward edge birds
        // (low neighbour count); the dense core stays solid, the feathered edge
        // shimmers. Ported from the original's distFromCenter weighting, with
        // the boids neighbour count as the edge detector.
        float midGain = fp.midEdgeGain;
        if (midGain > 1e-5) {
            float  densityT   = clamp(neighborN / 22.0, 0.0, 1.0);
            float  edgeWeight = mix(1.0, 0.18, densityT);
            // Per-frame-varying noise (continuous fast term, NOT a held step) so
            // the edge genuinely SHIMMERS — a constant push just moves a bird in
            // a straight line (no direction change, no shimmer). The fast term
            // decorrelates frame-to-frame so edge birds jitter.
            float3 flutter = mf_hash33(float3(b.seed * 131.0 + fp.time * 47.0,
                                              b.seed * 61.0 - fp.time * 41.0,
                                              b.seed * 17.0 + fp.time * 53.0));
            accel += flutter * (midGain * edgeWeight);
        }
    }

    // Clamp force.
    float aLen = length(accel);
    if (aLen > fp.maxForce) { accel *= fp.maxForce / aLen; }

    // Integrate (semi-implicit Euler).
    float3 newVel = vel + accel * fp.dt;

    // Speed clamp — birds always keep flying (min speed), never exceed max.
    float sp = length(newVel);
    float perBirdMax = mix(fp.maxSpeed * 0.85, fp.maxSpeed, b.speedRnd);
    if (sp > perBirdMax) { newVel *= perBirdMax / sp; }
    else if (sp < fp.minSpeed && sp > 1e-5) { newVel *= fp.minSpeed / sp; }
    else if (sp <= 1e-5) { newVel = float3(1.0, 0.0, 0.0) * fp.minSpeed; }

    float3 newPos = pos + newVel * fp.dt;

    // Banking — how hard the bird is turning this frame (orientation-wave cue).
    float3 oldDir = (length(vel) > 1e-5) ? normalize(vel) : float3(1.0, 0.0, 0.0);
    float3 newDir = (length(newVel) > 1e-5) ? normalize(newVel) : oldDir;
    float turn = clamp((1.0 - dot(oldDir, newDir)) * 6.0, 0.0, 1.0);
    float bank = mix(b.bank, turn, clamp(fp.bankingRate * fp.dt, 0.0, 1.0));

    b.position = packed_float3(newPos);
    b.velocity = packed_float3(newVel);
    b.bank = bank;
    // L2 orientation-wave darkening goes to its OWN channel (pad0), written
    // fresh each frame so it stays a LOCALIZED travelling band (the persistent
    // `bank` field would smear it into whole-flock darkening). Zero when no
    // wave is active → silence baseline unchanged. The render samples it for
    // the moving dark band.
    b.pad0 = waveBankBoost;
    b.neighborCount = neighborN;
    birds[gid] = b;
}

// MARK: - Render: depth-projected dark point sprites

struct FlockVertexOut {
    float4 position [[position]];
    float  pointSize [[point_size]];
    float  alpha;
    float  shade;     // 0 = lightest (far), 1 = darkest (near + banking)
};

vertex FlockVertexOut murmuration_flock_vertex(
    uint                          vid   [[vertex_id]],
    device const MurmurationBird* birds [[buffer(0)]],
    constant FlockParams&         fp    [[buffer(2)]])
{
    MurmurationBird b = birds[vid];
    FlockVertexOut out;

    // Orthographic-ish projection: camera at +z looking toward −z.
    // Higher z = nearer the camera. World ±worldHalfSpan → clip via kViewScale.
    const float kViewScale = 1.3;
    float zNorm = clamp(b.position.z / fp.worldHalfSpan, -1.0, 1.0);   // −1 far … +1 near
    float persp = 1.0 + 0.18 * zNorm;                                  // mild size parallax
    out.position = float4(b.position.x * kViewScale * persp,
                          b.position.y * kViewScale * persp,
                          0.0, 1.0);

    // Aerial perspective: far birds smaller, lighter; near birds bigger, darker.
    float depthFade = 0.6 + 0.4 * (zNorm * 0.5 + 0.5);                 // [0.6,1.0]

    // Local density (neighbour count) drives the core-dark / edge-feathered
    // contrast that is the references' signature: dense-core birds render solid
    // and dark, sparse-edge birds faint and feathered.
    float densityT = clamp(b.neighborCount / 22.0, 0.0, 1.0);

    float baseSize = 2.4 + 1.0 * (zNorm * 0.5 + 0.5) + 0.8 * densityT;
    out.pointSize = max(baseSize, 1.0);

    // Banking presents more wing → darker (the emergent orientation cue); the
    // L2 drum wave adds a stronger, LOCALIZED darkening band on top (pad0).
    float bankDark = clamp(b.bank, 0.0, 1.0);
    float waveDark = clamp(b.pad0, 0.0, 1.0);
    float darken = clamp(0.15 * bankDark + 0.55 * waveDark, 0.0, 1.0);
    out.shade = clamp(0.55 + 0.45 * densityT + darken, 0.0, 1.0);
    out.alpha = clamp((0.28 + 0.66 * densityT) * depthFade + 0.10 * bankDark + 0.20 * waveDark, 0.0, 0.98);
    return out;
}

fragment float4 murmuration_flock_fragment(
    FlockVertexOut in        [[stage_in]],
    float2         pc        [[point_coord]])
{
    float2 d = pc - 0.5;
    float r = length(d) * 2.0;
    if (r > 1.0) { discard_fragment(); }
    float disk = 1.0 - smoothstep(0.55, 1.0, r);
    // Near-black silhouette; far birds lift slightly toward dusk-grey (aerial perspective).
    float3 birdColor = mix(float3(0.10, 0.10, 0.13), float3(0.015, 0.015, 0.025), in.shade);
    float a = disk * in.alpha;
    return float4(birdColor, a);
}
