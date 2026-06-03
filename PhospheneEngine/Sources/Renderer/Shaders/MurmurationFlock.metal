// MurmurationFlock.metal — Phase MM emergent starling-flock engine.
//
// MM.6 REBUILD: a faithful port of Rama Hoetzlein's **Flock2** orientation-based
// social-flocking model (github.com/ramakarl/Flock2, MIT; J. Theoretical Biology
// 2024). This REPLACES the MM.2/MM.3 force-based boids substrate (summed
// separation/alignment/cohesion + roost attractor + injected curl turning-wave),
// which was a hand-derived — and worse — version of this published model and
// fragmented the flock under real audio at the MM.3 M7 live review (FA #4
// inverted; FA #73 "don't rebuild what's already been built").
//
// The Flock2 difference: neighbour influence is a **desire to TURN** (an
// orientation target in the bird's body frame: yaw ψ + pitch θ), NOT a summed
// force vector. Each bird carries a body **quaternion** and a scalar speed; the
// four social rules (avoidance / alignment / cohesion / peripheral-boundary)
// write a heading `target`, a reaction-rate-limited control loop rolls + steers
// the body toward it, and a dynamic-stability term keeps the body tracking its
// velocity. Banking (roll) is derived from the yaw error — birds roll INTO
// turns — so the travelling dark "orientation bands" of a real murmuration
// EMERGE from alignment+avoidance coupling rather than being injected. This is
// also why it is stable under perturbation (orientation nudges cannot fling
// birds the way added forces do).
//
// Ported from the Flock2 source (read, not re-derived — FA #70):
//   • findNeighborsTopological  (flock_kernels.cu) → mf topological gather below
//   • advanceOrientationHoetzlein(flock_kernels.cu) → mf_boids controller below
//   • quaternion.cuh (libmin)   → the mf_q* helpers (verbatim conventions)
// Coefficient RATIOS are the source defaults (app_flock.cpp): align 0.40,
// cohesion 0.001, avoid-angular 0.01, boundary 0.40, pitch_decay 0.95, fov 240°,
// 7 topological neighbours. The sim runs in Phosphene's COMPACT world (not
// literal metres); the heading controller is angle-based and scale-invariant, so
// only the speeds/radii/reaction-time are mapped to the compact world (ratios
// kept). The aerodynamic Newton model (lift/drag/thrust/gravity in m/s²) is
// replaced by a simplified speed model (climb-slows / dive-speeds + clamp) per
// the MM.6 porting brief — literal 9.8 gravity does not fit a ±2 world and the
// faithful kinematic turn + reaction lag + dynamic-stability realign (all ported
// verbatim) are what produce the look, not the Newton balance.
//
// MM.6 audio coupling re-expresses the MM.3 musical brain as gentle biases on
// the TURN-DESIRES (never forces): L1 bass → anchor drift + a guide-segment
// elongation (comma/ribbon); L2 drums → a synchronised yaw bias swept across the
// flock axis (intensifies the EMERGENT orientation wave); L4 mid → edge-bird
// turn jitter (feathered-edge shimmer); L5 vocals → cohesion/boundary tightening
// (breathing). All terms vanish at zero audio → the silence baseline is exact.
//
// Grid binning idiom mirrors FerrofluidParticles.metal (reset → bin(atomic) →
// consume, one encoder, memoryBarrier between dependent passes).
//
// This file is concatenated into the single engine-library compilation unit
// (alphabetical order, after Common.metal). Helper names are `mf_`-prefixed to
// avoid collisions; a syntax error here breaks the whole engine library. The
// `FlockParams` / `MurmurationBird` structs are private (uploaded via setBytes),
// so camelCase fields are fine — they are NOT Common.metal mirrors (FA #72
// applies only to FeatureVector/StemFeatures/SceneUniforms).

#include <metal_stdlib>
using namespace metal;

// MARK: - Per-bird state (mirror of Swift MurmurationFlockGeometry.Bird, 64 bytes)

struct MurmurationBird {
    float4        orient;        // body orientation quaternion (16B, 16-aligned first)
    packed_float3 position;      // compact-world position
    float         seed;          // per-bird random [0,1] (stable)
    packed_float3 velocity;      // world units / second (direction × speed)
    float         neighborCount; // r_nbrs: radius+FOV neighbour count (edge detect + density)
    packed_float3 target;        // persistent heading desire (deg): x=roll y=pitch z=yaw
    float         speedRnd;      // per-bird speed preference [0,1]
};

// MARK: - Flock parameters (mirror of Swift FlockParams)

struct FlockParams {
    uint  particleCount;
    uint  gridSide;
    uint  cellCapacity;
    float dt;

    float time;
    float worldHalfSpan;   // grid covers [-worldHalfSpan, +worldHalfSpan]^3 (metres)
    float neighborRadius;  // metric search radius = grid cell size (= psmoothradius 10 m)
    float fovCos;          // cos(fov/2): 240° → −0.5

    float minSpeed;        // m/s (source 5)
    float maxSpeed;        // m/s (source 18)
    float reactionSpeed;   // control reaction time (ms) — rx = dt*1000/reactionSpeed
    float dynamicStability;// [0,1] fraction body re-aligns to velocity per frame

    // Faithful aerodynamic flight model (metre units; source constants).
    float mass;            // kg (source 0.08)
    float powerParam;      // 100% power, N (source 0.2173)
    float wingArea;        // m² (source 0.0224)
    float liftFactor;      // CL (source 0.5714)

    float dragFactor;      // CD (source 0.1731)
    float airDensity;      // kg/m³ (source 1.225)
    float gravityY;        // m/s² (source −9.8)
    uint  neighborCap;     // hard cap on candidates examined (perf guard)

    float avoidAmt;        // k_avoid (source 0.01)
    float alignAmt;        // k_align (source 0.40)
    float cohesionAmt;     // k_coh  (source 0.001)
    float boundaryAmt;     // k_bound (source 0.40)

    float boundaryCnt;     // r_nbrs below which a bird is "peripheral" (turns inward)
    float pitchDecay;      // target.y decay toward level (source 0.95)
    float pitchMin;        // source −40°
    float pitchMax;        // source +20°

    float boundHalfY;      // vertical band half-height about anchor.y (ground/ceiling avoid)
    float boundSoften;     // ground/ceiling detection range (m, source 20)
    float avoidGroundAmt;  // source 0.5
    float avoidCeilAmt;    // source 0.1

    float4 anchor;         // xyz = flock anchor (boundary-turn centre) + bass drift; w unused

    // ── MM.6 audio turn-desire biases (all inert at zero audio) ──
    float4 flockAxis;      // xyz = unit elongation / wave-travel axis, w = elongation [0,~0.7]
    float4 drive;          // x = waveYawDeg (gated), y = beatValue [0,1], z = propDir(±1), w = waveWidth
    float  midEdgeDeg;     // L4 edge-flutter turn-jitter amplitude (degrees)
    float  flockExtent;    // nominal half-extent normalising guide-segment + wave coord (m)
    float  framingRadius;  // horizontal soft containment radius (m)
    float  framingAmt;     // framing turn strength

    float  viewRadius;     // render: world metres mapped to clip half-extent
    float  renderYOffset;  // render: vertical recentre (the flock cruises off anchor.y)
    float  audioPad0;
    float  audioPad1;
};

// MARK: - Hash helpers

inline float mf_hash11(float n) {
    return fract(sin(n) * 43758.5453123);
}

// 3D value hash → [-1,1]^3, used for per-bird wander / edge flutter.
inline float3 mf_hash33(float3 p) {
    float3 q = float3(dot(p, float3(127.1, 311.7, 74.7)),
                      dot(p, float3(269.5, 183.3, 246.1)),
                      dot(p, float3(113.5, 271.9, 124.6)));
    return -1.0 + 2.0 * fract(sin(q) * 43758.5453123);
}

// MARK: - Quaternion helpers (ported verbatim from libmin quaternion.cuh)
//
// Conventions matter and are matched exactly: mf_qrotate(v,q) rotates vector v by
// q; mf_qmul(b,a) is the libmin Hamilton product with that arg order;
// mf_q_euler returns (roll about x, pitch about y, yaw about z) in DEGREES;
// mf_q_angleaxis takes RADIANS. The deg/rad mix in the control loop (deg `target`
// scaled by `rx` then fed to mf_q_angleaxis as radians) is the source's own
// working behaviour — ported as-is.

constant float MF_RAD2DEG = 57.29577951308232;

inline float mf_fmodulus(float x, float y) { return x - trunc(x / y) * y; }

inline float mf_circleDelta(float b, float a) {
    float d = b - a;
    d = (d > 180.0) ? d - 360.0 : ((d < -180.0) ? d + 360.0 : d);
    return d;
}

// Rotate vector v by quaternion op (op.xyz = vector part, op.w = scalar).
inline float3 mf_qrotate(float3 v, float4 op) {
    float3 u = op.xyz;
    float3 q = u * (2.0 * dot(u, v));
    q += v * (op.w * op.w - dot(u, u));
    q += cross(u, v) * (2.0 * op.w);
    return q;
}

// Hamilton product, libmin arg order quat_mult(b, a).
inline float4 mf_qmul(float4 b, float4 a) {
    return float4(
        a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y,   // x
        a.w * b.y + a.y * b.w + a.z * b.x - a.x * b.z,   // y
        a.w * b.z + a.z * b.w + a.x * b.y - a.y * b.x,   // z
        a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z);  // w
}

inline float4 mf_qnorm(float4 a) {
    float n = dot(a, a);
    return (n > 1e-12) ? a * rsqrt(n) : float4(0.0, 0.0, 0.0, 1.0);
}

inline float4 mf_q_angleaxis(float angRad, float3 axis) {
    float h = angRad * 0.5;
    return float4(sin(h) * axis.x, sin(h) * axis.y, sin(h) * axis.z, cos(h));
}

inline float3 mf_q_euler(float4 op) {
    float test = op.x * op.y + op.z * op.w;
    float3 v;
    if (test > 0.4999) {
        v = float3(0.0, M_PI_F * 0.5, -2.0 * atan2(op.x, op.w));
    } else if (test < -0.4999) {
        v = float3(0.0, -M_PI_F * 0.5, 2.0 * atan2(op.x, op.w));
    } else {
        v.x = atan2(2.0 * (op.x * op.w - op.y * op.z), 1.0 - 2.0 * (op.x * op.x + op.z * op.z));
        v.y = asin(clamp(2.0 * test, -1.0, 1.0));
        v.z = atan2(2.0 * (op.x * op.z - op.y * op.w), 1.0 - 2.0 * (op.y * op.y + op.z * op.z));
    }
    return v * MF_RAD2DEG;
}

inline float4 mf_qinv(float4 op) {
    float n = rsqrt(max(dot(op, op), 1e-12));
    return float4(-op.x * n, -op.y * n, -op.z * n, op.w * n);
}

inline float4 mf_q_fromto(float3 from, float3 to, float frac) {
    float3 cx = cross(from, to);
    float cl = length(cx);
    if (cl < 1e-6) { return float4(0.0, 0.0, 0.0, 1.0); }   // parallel → identity
    float3 axis = cx / cl;
    float ang = acos(clamp(dot(from, to), -1.0, 1.0)) * frac;
    return mf_qnorm(mf_q_angleaxis(ang, axis));
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

// MARK: - Kernel 3: orientation-flocking integrator (Hoetzlein, ported)
//
// One kernel fuses findNeighborsTopological + advanceOrientationHoetzlein: gather
// the ~7 nearest topological neighbours within the FOV, run the four heading
// rules, reaction-rate-limit the control loop, integrate the simplified flight
// model, and re-align the body to velocity. Fusing avoids storing ave_pos/
// ave_vel in the bird struct (they are consumed immediately).

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
    float4 orient = b.orient;
    float3 target = float3(b.target);

    float speed = length(vel);
    float3 diri = (speed > 1e-6) ? vel / speed : mf_qrotate(float3(1, 0, 0), orient);

    // ── Topological neighbour gather (findNeighborsTopological) ──
    const int K = 7;
    float sortD[K + 1];
    int   sortJ[K + 1];
    int   sortNum = 0;
    int   rNbrs = 0;                 // boundary count: ALL within radius+FOV
    float3 avePos = float3(0.0);
    float3 aveVel = float3(0.0);
    int   nearJ = -1;
    float nearD = 1e9;

    float rad = fp.neighborRadius;
    float rad2 = rad * rad;
    int3 c = mf_cell_coord(pos, fp.worldHalfSpan, fp.gridSide);
    uint examined = 0u;

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
                    float dsq = dot(d, d);
                    if (dsq >= rad2 || dsq < 1e-10) { continue; }
                    float dist = sqrt(dsq);
                    float3 dir = d / dist;
                    if (dot(diri, dir) <= fp.fovCos) { continue; }   // outside forward FOV

                    rNbrs++;                                          // boundary neighbour

                    // Insertion-sort into the K nearest (topological selection).
                    int k = 0;
                    while (k < sortNum && dist > sortD[k]) { k++; }
                    if (k < K) {
                        int top = min(sortNum, K - 1);
                        for (int m = top; m > k; m--) {
                            sortD[m] = sortD[m - 1];
                            sortJ[m] = sortJ[m - 1];
                        }
                        sortD[k] = dist;
                        sortJ[k] = (int)j;
                        if (sortNum < K) { sortNum++; }
                    }
                    if (dist < nearD) { nearD = dist; nearJ = (int)j; }
                }
                if (examined >= fp.neighborCap) { break; }
            }
            if (examined >= fp.neighborCap) { break; }
        }
        if (examined >= fp.neighborCap) { break; }
    }

    for (int k = 0; k < sortNum; k++) {
        float3 pj = float3(birds[sortJ[k]].position);
        avePos += pj;
        aveVel += float3(birds[sortJ[k]].velocity);
    }
    if (sortNum > 0) {
        avePos *= (1.0 / float(sortNum));
        aveVel *= (1.0 / float(sortNum));
    }

    // ── Heading rules (advanceOrientationHoetzlein) — write the `target` ──
    float4 ctrlq = mf_qinv(orient);   // world → body frame

    if (rNbrs > 0) {
        // Rule 1. Avoidance (nearest neighbour, turn away). 1/dist² softening is
        // expressed relative to the neighbour radius so it matches the source's
        // metre-calibrated `max(1, dist²)` shape in the compact world.
        if (nearJ != -1) {
            float3 pj = float3(birds[nearJ].position);
            float3 dirj = pj - pos;
            float dist = max(length(dirj), 1e-5);
            float3 bf = mf_qrotate(dirj / dist, ctrlq);
            float yaw = atan2(bf.z, bf.x) * MF_RAD2DEG;
            float pitch = asin(clamp(bf.y, -1.0, 1.0)) * MF_RAD2DEG;
            float dn = max(1.0, (dist / rad) * (dist / rad) * 64.0);
            target.z -= yaw * fp.avoidAmt / dn;
            target.y -= pitch * fp.avoidAmt / dn;
        }
        // Rule 2. Alignment (match average neighbour heading).
        {
            float3 bf = mf_qrotate(normalize(aveVel), ctrlq);
            float yaw = atan2(bf.z, bf.x) * MF_RAD2DEG;
            float pitch = asin(clamp(bf.y, -1.0, 1.0)) * MF_RAD2DEG;
            target.z += yaw * fp.alignAmt;
            target.y += pitch * fp.alignAmt;
        }
        // Rule 3. Cohesion (steer toward neighbour centroid).
        {
            float3 toC = avePos - pos;
            if (dot(toC, toC) > 1e-10) {
                float3 bf = mf_qrotate(normalize(toC), ctrlq);
                float yaw = atan2(bf.z, bf.x) * MF_RAD2DEG;
                float pitch = asin(clamp(bf.y, -1.0, 1.0)) * MF_RAD2DEG;
                target.z += yaw * fp.cohesionAmt;
                target.y += pitch * fp.cohesionAmt;
            }
        }
        // Rule 4. Peripheral boundary (Hoetzlein 2023) — edge birds (few
        // neighbours) turn toward the flock centre, strength (B−nᵢ)/B. This gives
        // the cohesive, feathered edge (no roost-attractor force). The OVERALL
        // size/shape (and the L1 elongation) are set by the elliptical
        // containment term below; this term just keeps the periphery turning in.
        if (fp.boundaryCnt > 0.0 && float(rNbrs) < fp.boundaryCnt) {
            float3 toCtr = fp.anchor.xyz - pos;
            if (dot(toCtr, toCtr) > 1e-10) {
                float3 bf = mf_qrotate(normalize(toCtr), ctrlq);
                float yaw = atan2(bf.z, bf.x) * MF_RAD2DEG;
                float pitch = asin(clamp(bf.y, -1.0, 1.0)) * MF_RAD2DEG;
                float dd = (fp.boundaryCnt - float(rNbrs)) / fp.boundaryCnt;
                target.z += yaw * fp.boundaryAmt * dd;
                target.y += pitch * fp.boundaryAmt * dd;
            }
        }
    }

    // ── Elliptical soft containment — the flock SHAPE + SIZE controller ──
    // The peripheral-boundary term keeps the flock cohesive, but the angle-based
    // controller has no length scale, so the flock would drift ballistically and
    // its size would be set only by the initial spread. This term gives it one:
    // an ALWAYS-ON gentle horizontal turn-toward-centre whose strength grows with
    // the normalised elliptical radius, so the flock equilibrates to an ellipse
    // (the orbit where inward turn balances forward flight). It is the single
    // knob that frames the flock (static camera, design §9), sets its size, and —
    // by warping the ellipse — produces the audio SHAPE moves without any force
    // (porting decision #4; FA #4):
    //   • L1 elongation stretches the ellipse along the flock axis → comma/ribbon
    //   • L5 vocals breath shrinks framingRadius (CPU) → the mass contracts
    //   • L1 drift moves anchor → the framed centre translates (bounded)
    // The vertical is contained separately by the faithful ground/ceiling band.
    {
        float3 d = fp.anchor.xyz - pos;
        d.y = 0.0;                                       // horizontal only
        float dlen = length(d);
        if (dlen > 1e-4) {
            float3 axis = fp.flockAxis.xyz;
            float along = dot(d, axis);
            float3 perp = d - axis * along;
            // ELLIPTICAL containment: both the soft spring AND the steep
            // boundary wall use a normalised radius whose along-axis extent is
            // stretched by the elongation, so the flock can extend further along
            // the axis (comma/ribbon) before the wall stops it. The restoring
            // DIRECTION is also warped to pull birds back harder perpendicular to
            // the axis, flattening the sides. Both shape the flock at any size and
            // collapse to a circle at zero elongation.
            float stretch = 1.0 + 3.0 * fp.flockAxis.w;  // along-axis extent allowed
            float alongN = along / (fp.framingRadius * stretch);
            float perpN  = length(perp) / max(fp.framingRadius, 1e-3);
            float rNell  = sqrt(alongN * alongN + perpN * perpN);  // elliptical radius
            // Restoring DIRECTION is straight toward the centre (stable); the
            // ellipse comes from the anisotropic STRENGTH (rNell) alone — birds
            // displaced along the axis sit at a smaller rNell, so they feel less
            // pull and the flock extends along the axis (comma/ribbon). Shrinking
            // framingRadius (L5 vocals breath) raises rNell → tightens at any size.
            float3 bf = mf_qrotate(d / dlen, ctrlq);
            float yaw = atan2(bf.z, bf.x) * MF_RAD2DEG;
            float pitch = asin(clamp(bf.y, -1.0, 1.0)) * MF_RAD2DEG;
            float s = rNell * 0.30 + max(0.0, rNell - 1.0) * 5.0;
            target.z += yaw * fp.framingAmt * s;
            target.y += pitch * fp.framingAmt * s;

            // Elongation spread: under bass, gently steer birds OUTWARD along the
            // axis (toward the ellipse ends), fading to zero as they approach the
            // wall (rNell→1) so they fill the stretched ellipse into a ribbon
            // rather than orbiting past it. The perpendicular pull above keeps the
            // sides tight → a comma/ribbon, not a bigger blob.
            if (fp.flockAxis.w > 1e-3 && abs(along) > 1e-3) {
                float3 outDir = axis * sign(along);             // away from centre, along axis
                float3 bo = mf_qrotate(outDir, ctrlq);
                float yawO = atan2(bo.z, bo.x) * MF_RAD2DEG;
                float pitchO = asin(clamp(bo.y, -1.0, 1.0)) * MF_RAD2DEG;
                float spread = fp.flockAxis.w * max(0.0, 1.0 - rNell);
                target.z += yawO * fp.framingAmt * spread * 1.2;
                target.y += pitchO * fp.framingAmt * spread * 1.2;
            }
        }
    }

    // ── Bar-anchored maneuver (the musicality rethink) — a GLOBAL turn ──
    // Once per bar the flock executes one coordinated heading-swing: a gentle YAW
    // bias that sweeps across the flock axis as the bar plays (barSweep =
    // barPhase01, 0→1), direction alternating each bar (the weaving zigzag; net
    // translation cancels over two bars). The band of birds the front is passing
    // turns together → they bank → the dark orientation wave EMERGES and travels
    // across the mass (the McGill mechanism — we do NOT inject it). Yawing (a real
    // turn) is the point: the flock maneuvers musically and the wave falls out.
    // Amplitude (drive.x) is energy-gated + drum-modulated on the CPU, so calm
    // bars barely move and intense bars sweep hard (§3.1 master lever).
    {
        float manAmp = fp.drive.x;
        if (manAmp > 1e-5) {
            float3 axis = fp.flockAxis.xyz;
            float3 toCtr = pos - fp.anchor.xyz;
            float coord = 0.5 + 0.5 * tanh(dot(toCtr, axis) / max(fp.flockExtent, 1e-3));
            float dir       = fp.drive.z;
            float birdCoord = (dir > 0.0) ? coord : (1.0 - coord);
            float front     = fp.drive.y;                       // barPhase01 sweep
            float width     = max(fp.drive.w, 1e-3);
            float infl      = max(0.0, 1.0 - abs(front - birdCoord) / width);
            target.z += manAmp * infl * dir;                    // coordinated yaw → bank emerges
        }
    }

    // ── Ground / ceiling avoidance (faithful — Flock2 vertical containment) ──
    // A pitch-toward-level bias as a bird nears the floor / ceiling of a band
    // about anchor.y. Combined with the real aero (lift slightly under gravity at
    // the thrust-limited cruise → the flock rides the lower band, undulating —
    // the "thin wide level sheet" reference form). Source mechanism; amounts
    // scaled for the 60 fps step (the deg bias is decayed same-frame by
    // pitch_decay below, so it is larger than the 200 fps source value).
    {
        float floorDist = pos.y - (fp.anchor.y - fp.boundHalfY);
        if (floorDist < fp.boundSoften) {
            float t = (fp.boundSoften - floorDist) / max(fp.boundSoften, 1e-3);
            target.y += t * fp.avoidGroundAmt;            // pitch up away from floor
        }
        float ceilDist = (fp.anchor.y + fp.boundHalfY) - pos.y;
        if (ceilDist < fp.boundSoften) {
            float t = (fp.boundSoften - ceilDist) / max(fp.boundSoften, 1e-3);
            target.y -= t * fp.avoidCeilAmt;              // pitch down away from ceiling
        }
        // L5 vocals breath (audioPad0): active vertical SPREAD — pitch birds away
        // from the band centre so the mass dilates in Y on a vocal swell (then
        // settles as the breath releases). Bounded by the ceiling/ground above.
        if (fp.audioPad0 > 1e-4) {
            float dy = pos.y - fp.anchor.y;
            target.y += sign(dy) * fp.audioPad0 * 12.0;
        }
    }

    // ── Control loop (reaction-rate-limited) ──
    float3 fwd = mf_qrotate(float3(1, 0, 0), orient);
    float3 up = mf_qrotate(float3(0, 1, 0), orient);
    float3 right = mf_qrotate(float3(0, 0, 1), orient);

    float3 vaxis = (speed > 1e-6) ? vel / speed : fwd;
    float3 angs = mf_q_euler(orient);

    // Target corrections (verbatim): roll target is derived from the YAW error —
    // this is what makes birds bank INTO their turns (and the emergent dark band).
    angs.z = mf_fmodulus(angs.z, 180.0);
    target.z = mf_fmodulus(target.z, 180.0);
    target.x = mf_circleDelta(target.z, angs.z) * 0.5;   // bank emerges from the (maneuver-driven) yaw error
    target.y *= fp.pitchDecay;
    target.y = clamp(target.y, fp.pitchMin, fp.pitchMax);
    if (abs(target.y) < 1e-4) { target.y = 0.0; }

    float3 angAccel;
    angAccel.x = target.x - angs.x;
    angAccel.y = target.y - angs.y;
    angAccel.z = mf_circleDelta(target.z, angs.z);

    float rx = fp.dt * 1000.0 / max(fp.reactionSpeed, 1.0);
    // Roll: rotate the BODY about its forward axis.
    float4 cq = mf_q_angleaxis(angAccel.x * rx, fwd);
    orient = mf_qnorm(mf_qmul(orient, cq));
    // Yaw + pitch: rotate the VELOCITY direction (torque about up / right).
    cq = mf_q_angleaxis(angAccel.z * rx, up * -1.0);
    vaxis = normalize(mf_qrotate(vaxis, cq));
    cq = mf_q_angleaxis(angAccel.y * rx, right);
    vaxis = normalize(mf_qrotate(vaxis, cq));

    // ── Faithful aerodynamic flight model (Newton, metre units — ported) ──
    // power-as-speed-governor (source): below min speed, boost thrust; above
    // max, cut it. fwd/up are the START-of-frame body axes (matching the source —
    // the aero is evaluated before the roll update propagates).
    float power = 1.0;
    if (speed < fp.minSpeed) { power = fp.minSpeed / max(speed, 1e-5); }
    else if (speed > fp.maxSpeed) { power = fp.maxSpeed / max(speed, 1e-5); }

    vel = vaxis * speed;                       // steered direction, magnitude preserved

    float airflow = speed;                     // wind = 0
    float dynP = 0.5 * fp.airDensity * airflow * airflow;
    float lift = dynP * fp.liftFactor * fp.wingArea;
    float3 force = up * lift;                                       // lift along body up
    force += vaxis * (dynP * (-fp.dragFactor) * fp.wingArea);       // drag opposes motion
    force += fwd * (power * fp.powerParam);                         // thrust along body fwd
    force += float3(0.0, fp.gravityY, 0.0) * fp.mass;              // gravity

    float3 accel = force / fp.mass;
    pos += vel * fp.dt;
    vel += accel * fp.dt;

    // ── Dynamic stability — re-align the body forward axis to velocity ──
    // (Directional stability; preserves the roll/bank set by the control input,
    // which is the orientation-wave cue. dynamicStability < the source's 0.8 so
    // banking persists longer in the 60 fps step.)
    float3 vdir = normalize(vel);
    float3 fwdNow = mf_qrotate(float3(1, 0, 0), orient);
    float4 sq = mf_q_fromto(fwdNow, vdir, fp.dynamicStability);
    if (!isnan(sq.x)) {
        orient = mf_qnorm(mf_qmul(orient, sq));
    }

    // Safety net: a bird that escapes the grid domain (should not happen — the
    // boundary term frames the flock) is pulled back so binning stays valid.
    float lim = fp.worldHalfSpan * 0.98;
    pos = clamp(pos, float3(-lim), float3(lim));

    b.orient = orient;
    b.position = packed_float3(pos);
    b.velocity = packed_float3(vel);
    b.target = packed_float3(target);
    b.neighborCount = float(rNbrs);
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

    // Orthographic-ish projection: camera at +z looking toward −z; higher z =
    // nearer. Static wide camera (design §9) — the flock's own drift is the ONLY
    // motion, so the projection is fixed (does NOT follow the anchor in X/Z, so
    // bass drift is visible). The metre-space sim is mapped to clip by viewRadius
    // (so the flock fills the frame at any count); the vertical recentre absorbs
    // the cruise-altitude offset (the flock rides the lower aero band).
    float3 p = float3(b.position) - float3(0.0, fp.renderYOffset, 0.0);
    float viewRadius = max(fp.viewRadius, 1e-3);
    float zNorm = clamp(p.z / viewRadius, -1.0, 1.0);   // −1 far … +1 near
    float persp = 1.0 + 0.18 * zNorm;
    out.position = float4(p.x / viewRadius * persp,
                          p.y / viewRadius * persp,
                          0.0, 1.0);

    float depthFade = 0.6 + 0.4 * (zNorm * 0.5 + 0.5);                 // [0.6,1.0]

    // Local density (neighbour count) drives the core-dark / edge-feathered
    // contrast that is the references' signature.
    float densityT = clamp(b.neighborCount / max(fp.boundaryCnt, 1.0), 0.0, 1.0);

    float baseSize = 2.2 + 1.0 * (zNorm * 0.5 + 0.5) + 0.8 * densityT;
    out.pointSize = max(baseSize, 1.0);

    // EMERGENT orientation-wave darkening — the McGill mechanism, computed
    // faithfully: the dark bands are birds turning more WING AREA toward the
    // viewer. A starling's wing plane is the body x–z plane, so its broad face
    // points along body-UP; the area presented to the camera (which looks along
    // +z) is |up.z|. Level birds (up ≈ +y) show an edge → light; banked birds
    // tilt up toward the camera → broad wing → dark. A coordinated turning band
    // rolls together → a darker band rolls across the mass (the L2 drum bias
    // makes one roll on the beat). No injected darkening channel.
    float3 up = mf_qrotate(float3(0, 1, 0), b.orient);
    float bankDark = clamp(abs(up.z) * 1.6, 0.0, 1.0);

    out.shade = clamp(0.55 + 0.45 * densityT + 0.25 * bankDark, 0.0, 1.0);
    out.alpha = clamp((0.28 + 0.66 * densityT) * depthFade + 0.18 * bankDark, 0.0, 0.98);
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
