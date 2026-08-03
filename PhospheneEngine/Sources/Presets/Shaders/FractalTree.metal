// FractalTree.metal — Fractal tree mesh shader preset (Increment 3.2b).
//
// A recursive binary tree with 63 branches across 6 depth levels (0–5).
// Each of 63 mesh-shader threads computes one branch's geometry using an
// iterative ancestry traversal (no MSL recursion).
//
// AUDIO ROUTING — rebuilt at FTR.2 (D-212). Five visual layers, five distinct
// primitives (FA #67), every coefficient sized against its primitive's measured
// p05→p95 span on real captures rather than a notional 0→1:
//
//   bass_dev           → canopy reach: branch count + trunk length + thickness,
//                        as ONE coupled gesture through a single derived scalar
//   spectral_flux      → branch spread angle (20°–34°)
//   tonal_phase_fifths → leaf hue along the amber→green arc (no wall clock)
//   arousal            → global brightness envelope (the section-scale arc)
//   beat_bass          → beat accent, knee-gated so it fires rather than glows
//
// The routing this replaced had three layers on `bass_att`, two coefficients
// sized against nothing, and a `fract(t * 0.006)` wall clock out-driving the
// music 18.6 : 1 in the hue line. Measurements: FTR.2 closeout + D-212.
//
// NOT here, deliberately: per-branch activation is FTR.3, and `StemFeatures` is
// unreachable from the object/mesh stages until FTR.4 binds buffer(3) there.
//
// Geometry: each branch is a screen-aligned quad (4 vertices, 2 triangles).
//   Total: 63 × 4 = 252 vertices ≤ 256, 63 × 2 = 126 primitives ≤ 512.
//
// M1/M2 fallback: fractal_tree_fallback_vertex + fractal_tree_fragment renders
//   a tinted full-screen gradient using the same color math.

// MARK: - Payload

/// Audio data passed from the object shader to the mesh shader via [[payload]].
struct FractalPayload {
    /// CANOPY REACH — the single derived scalar for "how big is the tree", 0…1.
    /// Branch count, trunk length and thickness all read THIS, so they move as one
    /// coupled gesture rather than three layers racing on one primitive (the FA #67
    /// collision D-212 measured).
    float reach;
    /// BRANCH SPREAD, radians — how wide the canopy opens. From `spectral_flux`.
    float spread;
    /// Beat position, 0 at the last beat rising to 1 at the next — the envelope
    /// clock for per-branch activation.
    float beat_phase;
    /// 0 before the first note and across sustained silence, 1 while music plays.
    /// Gates the taps so cold-start cannot fire them wrong-phase.
    float pulse_amp;
    /// Which beat we are on. Re-seeds the hash each beat so a DIFFERENT handful of
    /// branches taps every time.
    uint  beat_seed;
    float aspect_ratio;
    uint  branch_count;   // 15–61: how many branches to render this frame
};

// MARK: - Hash

/// Integer avalanche hash (lowbias32). Used to pick which branches tap on a given
/// beat. Stateless and reproducible: the same (branch, beat) pair always agrees,
/// which is what lets a stateless shader hold a per-branch envelope at all.
static inline uint fractal_hash(uint x)
{
    x ^= x >> 16; x *= 0x7feb352du;
    x ^= x >> 15; x *= 0x846ca68bu;
    x ^= x >> 16;
    return x;
}

// MARK: - Object Shader

/// Reads the current FeatureVector, computes the audio-driven branch count,
/// and packs the payload for the mesh shader.  One thread, one meshlet.
[[object, max_total_threads_per_threadgroup(1)]]
void fractal_tree_object_shader(
    object_data FractalPayload* payload [[payload]],
    mesh_grid_properties          mgp,
    constant FeatureVector&       f [[buffer(0)]],
    uint tid [[thread_index_in_threadgroup]])
{
    // Always dispatch exactly one mesh threadgroup (all 63 branches in one meshlet).
    mgp.set_threadgroups_per_grid(uint3(1, 1, 1));

    if (tid == 0) {
        // ── CANOPY REACH ← bass_rel (D-026 deviation primitive) ──────────────────
        //
        // THE CANOPY IS A CANVAS, NOT THE RHYTHM. FTR.2 drove this from `bass_dev` and
        // it broke the preset — Matt, live: *"either too excited or completely inert …
        // the movement is haphazard; fingers are not really visible."* Measured on his
        // session 2026-08-03T22-54-06Z, that is exactly what the numbers say:
        //
        //                        changes on   avg jump   sits at minimum
        //     bass_att (before)   11.7 %       1.9         1.6 %
        //     bass_dev (FTR.2)     4.2 %      21.5        82.0 %
        //
        // `bass_dev = max(0, bassRel)` is an upward-TRANSIENT signal — zero on 66–89 %
        // of frames — so the tree sat at its 7-branch floor four frames in five and then
        // slammed 21 branches at once. The effect Matt values ("fingers tapping to the
        // beat") was branches appearing ONE OR TWO AT A TIME at the truncation edge; a
        // transient driver cannot produce it, by construction.
        //
        // `bass_rel` is the same D-026 family WITHOUT the `max(0, …)` clamp, so it is
        // continuous and centred on the band's own running EMA. Through a logistic it
        // holds the canopy mid-range and drifting on all four sources, never collapsing
        // to the floor (measured floor time: 0.4–4.4 %, against bass_dev's 66–82 %).
        //
        // The count now only has to keep a believable tree on screen. The RHYTHM is
        // carried by per-branch activation below — which is the deliberate version of
        // the effect FTR.2 deleted, and the reason this route can afford to be calm.
        float reach = 1.0f / (1.0f + exp(-f.bass_rel * 3.0f));

        // SILENCE GATE. `bass_rel` is a deviation from the band's OWN running average,
        // so at silence both collapse to 0 and the logistic sits at exactly 0.5 — a
        // half-grown tree standing in a silent room. `pulse_amp01` is 0 before the first
        // note and across sustained silence, so scaling by it returns the sparse
        // 7-branch figure the reference README asks for ("trunk plus the first two
        // generations"), still non-black (D-037). This is a GATE, not a route: it
        // carries no musical information, it only answers "is anything playing".
        float amp = saturate(f.pulse_amp01);

        // 7 at silence → 14/22/41 at the measured p05/p50/p95 of Hummer → 63 only if
        // bass_rel reaches ~2, which is past p99. The taps need branches to land on,
        // so the canopy stays present rather than collapsing between transients.
        uint count = 7u + (uint)(reach * 56.0f * amp);

        // ── PER-BRANCH ACTIVATION (HERO) ← beat_phase01 + pulse_beat_index ────────
        //
        // Option A per D-212: each beat, hash-select a bounded subset of branches and
        // run an attack/decay envelope on each. Stateless — the hash of (branch, beat)
        // is reproducible, which is what lets a shader with no frame-to-frame memory
        // hold a per-branch envelope at all.
        //
        // `pulse_*` is a 4-beat cycle (D-153), so the beat index within the pulse is
        // `pulse_phase01 × 4`; combining gives a counter that advances once per beat
        // and re-seeds the selection so a DIFFERENT handful taps each time.
        //
        // Cold-start: `pulse_amp01` is 0 before the first note and across sustained
        // silence. Gating on it is how this preset implements its own suppression —
        // the Cold-Start Phase Contract is explicit that presets needing it do it
        // themselves, and that automated phase derivation is retired, not to be retried.
        uint beat_seed = (uint)(f.pulse_beat_index * 4.0f + f.pulse_phase01 * 4.0f);

        // ── BRANCH SPREAD ← spectral_flux ────────────────────────────────────────
        //
        // Replaces `mid_att`, which delivered 0.42° of a promised 7° (D-212). The
        // cause was a coefficient written as if the band swings 0→1: `mid_att` means
        // 0.056 post-AGC on this material and spans 0.007 on love_rehab.
        //
        // `spectral_flux` is the only broadband primitive measured with a comparable
        // span on every source — p05→p95 of 0.555 (Hummer), 0.666, 0.539, 0.477. It
        // is also the right MUSICAL choice: flux rises when the spectrum CHANGES, so
        // the canopy opens on chord and texture changes rather than on loudness, which
        // the canopy-reach route already carries.
        //
        // Sized against the measured p05 floor, not against 0: flux never approaches
        // zero on real music (p05 0.070–0.378), so mapping [0.10, 0.95] onto the full
        // spread range uses the range the music actually occupies. 20°→34° is double
        // the shipped 22°→29° nominal, and ~33× the swing actually delivered.
        float flux   = saturate((f.spectral_flux - 0.10f) / 0.85f);
        float spread = 0.35f + flux * 0.24f;   // 20° … 34°

        // Only geometry terms travel in the payload. The fragment stage reads its own
        // primitives straight from `f` at buffer(0), so forwarding them here would just
        // be a second, staler copy.
        payload->beat_phase   = saturate(f.beat_phase01);
        payload->pulse_amp    = saturate(f.pulse_amp01);
        payload->beat_seed    = beat_seed;
        payload->reach        = reach;
        payload->spread       = spread;
        payload->branch_count = min(count, 63u);
        payload->aspect_ratio = max(f.aspect_ratio, 0.1f);
    }
}

// MARK: - Mesh Shader

/// 64 threads (one per branch slot; slot 63 is idle).
/// Each thread computes its branch's world-space geometry via iterative
/// ancestry traversal and writes 4 vertices + 6 indices.
/// Thread 0 also sets the primitive count.
[[mesh, max_total_threads_per_threadgroup(64)]]
void fractal_tree_mesh_shader(
    object_data const FractalPayload&                          payload [[payload]],
    mesh<MeshVertex, MeshPrimitive, 252, 126, topology::triangle> m,
    uint lid [[thread_index_in_threadgroup]])
{
    const uint MAX_BRANCHES = 63u;

    // Thread 0: announce how many primitives (triangles) will be produced.
    if (lid == 0) {
        m.set_primitive_count(payload.branch_count * 2u);
    }

    // Threads 64+ are padding — do nothing.
    if (lid >= MAX_BRANCHES) return;

    uint bid = lid;   // branch index 0–62

    // ------------------------------------------------------------------
    // Iterative ancestry traversal
    //
    // Binary tree layout: branch i has parent (i-1)/2.
    // Odd index  = left child (counterclockwise turn).
    // Even index = right child (clockwise turn).
    //
    // We build the path from the branch back to root, then replay it
    // forwards to accumulate the branch's world-space start & direction.
    // ------------------------------------------------------------------
    uint leaf_path[6];
    int  leaf_depth = 0;
    {
        uint cur = bid;
        while (cur > 0u && leaf_depth < 6) {
            leaf_path[leaf_depth++] = cur;
            cur = (cur - 1u) / 2u;
        }
    }

    // ── THIS BRANCH'S TAP ─────────────────────────────────────────────────────────
    //
    // Hash-select: ~32 % of branches fire on any given beat. Bounded footprint by
    // design (D-157) — the whole canopy never lights at once, which is what keeps
    // global luminance steady while individual branches move. Re-seeded per beat, so
    // the pattern is different every time and reads as fingers rather than a pulse.
    uint  h      = fractal_hash(bid * 1973u + payload.beat_seed * 9277u);
    float pick   = float(h & 1023u) * (1.0f / 1023.0f);
    float chosen = step(pick, 0.32f);

    // Attack/decay over the beat. Fast in (7 % of the beat), slower out (to 80 %) —
    // a tap, not a throb. Multiplying by pulse_amp gates the whole thing at cold start.
    float p   = payload.beat_phase;
    float env = smoothstep(0.0f, 0.07f, p) * (1.0f - smoothstep(0.07f, 0.80f, p));
    float tap = chosen * env * payload.pulse_amp;

    float base_len = 0.36f + payload.reach * 0.26f;
    float ang_base = payload.spread;                    // 20°–34°, from spectral_flux

    float2 pos     = float2(0.0f, -0.90f);  // tree root (bottom-centre, clip space)
    float2 dir     = float2(0.0f,  1.0f);   // initial direction: straight up
    float  seg_len = base_len;
    float  thick   = 0.038f + payload.reach * 0.020f;

    // Replay ancestors from root toward this branch.
    for (int k = leaf_depth - 1; k >= 0; k--) {
        pos     += dir * seg_len;
        seg_len *= 0.62f;
        thick   *= 0.62f;

        bool  is_left = (leaf_path[k] % 2u == 1u);
        float angle   = ang_base * (is_left ? 1.0f : -1.0f);

        // 2-D rotation: counterclockwise for left, clockwise for right.
        float ca = cos(angle), sa = sin(angle);
        float2 new_dir = float2(dir.x * ca - dir.y * sa,
                                dir.x * sa + dir.y * ca);
        dir = normalize(new_dir);
    }

    // THE TAP, in geometry. The branch flicks outward along its own direction — this
    // is the motion, and it is deliberately per-branch: neighbouring branches sit
    // still while this one moves, which is what makes it read as fingers rather than
    // as the whole tree breathing. Scaled by depth so the trunk barely stirs and the
    // fine tips travel most, exactly as a hand taps from the fingertips.
    float depth_norm = float(leaf_depth) / 5.0f;    // 0 = trunk … 1 = deepest leaf
    float is_leaf    = float(leaf_depth == 5 ? 1 : 0);
    seg_len *= 1.0f + tap * (0.10f + 0.34f * depth_norm);

    float2 branch_start = pos;
    float2 branch_end   = pos + dir * seg_len;

    // ------------------------------------------------------------------
    // Perpendicular vector for branch width.
    // Aspect-corrected so branches look uniformly thick at all orientations:
    //   x scaled by 1/aspect keeps horizontal width equal to vertical width
    //   in pixel space when aspect_ratio = screenWidth / screenHeight.
    // ------------------------------------------------------------------
    float aspect     = payload.aspect_ratio;
    float2 perp_dir  = float2(-dir.y, dir.x);  // unit perpendicular (90° CCW)
    float2 perp_clip = float2(perp_dir.x / aspect, perp_dir.y) * thick;

    // ------------------------------------------------------------------
    // Write 4 vertices for this branch.
    //   v0: base + perp  (uv = 0,0)
    //   v1: base – perp  (uv = 0,1)
    //   v2: tip  + perp  (uv = 1,0)
    //   v3: tip  – perp  (uv = 1,1)
    // normal.x = depth_norm, normal.y = 0, normal.z = is_leaf
    // ------------------------------------------------------------------
    uint base_vert = bid * 4u;

    // normal.y carries this branch's tap to the fragment stage — the only free channel
    // in MeshVertex, and the reason activation can be per-branch at all.
    MeshVertex v;
    v.normal = float3(depth_norm, tap, is_leaf);

    v.uv       = float2(0.0f, 0.0f);
    v.position = float4(branch_start + perp_clip, 0.0f, 1.0f);
    m.set_vertex(base_vert + 0u, v);

    v.uv       = float2(0.0f, 1.0f);
    v.position = float4(branch_start - perp_clip, 0.0f, 1.0f);
    m.set_vertex(base_vert + 1u, v);

    v.uv       = float2(1.0f, 0.0f);
    v.position = float4(branch_end + perp_clip, 0.0f, 1.0f);
    m.set_vertex(base_vert + 2u, v);

    v.uv       = float2(1.0f, 1.0f);
    v.position = float4(branch_end - perp_clip, 0.0f, 1.0f);
    m.set_vertex(base_vert + 3u, v);

    // ------------------------------------------------------------------
    // Write 6 indices (2 triangles) for this branch.
    //   Triangle 0: v0, v2, v1  (base-right → tip-right → base-left)  CCW ✓
    //   Triangle 1: v1, v2, v3  (base-left  → tip-right → tip-left)   CCW ✓
    // ------------------------------------------------------------------
    uint base_idx = bid * 6u;

    m.set_index(base_idx + 0u, base_vert + 0u);
    m.set_index(base_idx + 1u, base_vert + 2u);
    m.set_index(base_idx + 2u, base_vert + 1u);

    m.set_index(base_idx + 3u, base_vert + 1u);
    m.set_index(base_idx + 4u, base_vert + 2u);
    m.set_index(base_idx + 5u, base_vert + 3u);
}

// MARK: - Fragment Shader (shared by mesh path and M1/M2 fallback)

/// Phong-ish directional lighting with depth-dependent colour.
/// Trunk: warm bark brown.  Branches: dark forest green.
/// Leaf tips: hue-shifted by spectral centroid + slow time rotation.
/// Beat pulse: brightness flash across the whole tree, strongest at tips.
fragment float4 fractal_tree_fragment(
    MeshVertex              in [[stage_in]],
    constant FeatureVector& f  [[buffer(0)]])
{
    // Per-vertex data packed into MeshVertex.normal and .uv.
    float depth_norm   = in.normal.x;    // 0 = trunk, 1 = deepest leaf level
    float tap          = in.normal.y;    // this branch's beat activation, 0…1
    float is_leaf      = in.normal.z;    // 1 if depth == 5, else 0
    float along_branch = in.uv.x;        // 0 = branch base, 1 = branch tip
    float across_width = in.uv.y;        // 0 and 1 = edges, 0.5 = centre

    // ── Hue ← tonal_phase_fifths ─────────────────────────────────────────
    //
    // THE WALL CLOCK IS GONE. The shipped line was
    //   `0.30 - centroid * 0.12 + fract(t * 0.006)`
    // in which the audio term moved 4.1° of hue while the clock term swept 76° —
    // the clock out-drove the music 18.6 : 1, so the preset was a colour-cycling
    // wallpaper with a faint audio tint (README anti-reference #4). `spectral_centroid`
    // could not have rescued it either: it spans only 0.043–0.131 post-AGC.
    //
    // `tonal_phase_fifths` is the harmonic position on the circle of fifths (D-178),
    // measured span 2.61–5.31 rad of a ±π range. Hue and phase are BOTH circular, so
    // phase → hue is wrap-correct by construction: the ±π seam maps to the seam in
    // `fract()`, and no wrap produces a discontinuity the eye reads as a glitch.
    //
    // Mapped onto 0.28 of the hue circle, NOT the whole of it. A full mapping would run
    // the canopy through cyan, blue and magenta, which is not a tree — the register here
    // is the amber → gold → green arc (0.10 … 0.38), a widened version of the shipped
    // intent (0.18 yellow-green … 0.30 deep green). The harmony traverses the whole arc;
    // it never leaves it.
    float hue_bark  = 0.065f;
    float tonal01   = fract(f.tonal_phase_fifths * (1.0f / (2.0f * M_PI_F)) + 0.5f);
    float hue_leaf  = 0.10f + tonal01 * 0.28f;
    // Weighted by depth^0.55, not depth. A linear blend gives full leaf colour only at
    // depth 5, and the depth-5 tier exists on just 21.4 % of frames (measured, and the
    // figure D-212 put at 76.4 % — the recount is in the FTR.2 closeout). Under a linear
    // blend the harmonic route is alive in the data and invisible on screen four frames
    // in five. The exponent pushes leaf colour down into the mid-depth branches that are
    // actually present, so the route reads whenever there is a canopy at all.
    float hue       = mix(hue_bark, hue_leaf, pow(depth_norm, 0.55f));

    // ── Saturation ───────────────────────────────────────────────────────
    float sat = mix(0.55f, 0.88f, depth_norm);

    // ── Brightness envelope ← arousal ────────────────────────────────────
    //
    // A NEW LAYER. The preset had no section-scale route at all: every visible term
    // moved on a per-frame or per-transient timescale, so a quiet verse and a loud
    // chorus rendered at the same brightness. `arousal` is the mood classifier's slow
    // energy estimate and is correctly slow — it rises monotonically by quarter on
    // every source measured (Hummer 0.354 → 0.508, love_rehab 0.497 → 0.602,
    // so_what 0.130 → 0.296, there_there 0.415 → 0.621).
    //
    // SIZED AGAINST THE WARM RANGE, NOT p05→p95. The raw p05 is 0.033 on Hummer, but
    // that is cold-start residue: the first 60 frames read exactly 0.000 and the mood
    // classifier is still converging well past the 10 s warmup cut. Sizing against the
    // full 0.511 span would leave the tree dim for the opening minute of every track.
    // The mapping instead centres on the measured mid-track band [0.13, 0.62].
    //
    // Removed from this line: `mid_att * 0.18` (mid_att spans 0.007 on love_rehab —
    // there was nothing to multiply) and `treb_att * 0.12 * is_leaf`, the tip-shimmer
    // route, which delivered +0.002 of a promised +0.12 (D-212). Shimmer is not
    // re-homed here: the visual layer it occupied belongs to FTR.3's per-branch
    // activation, and a dead route is removed rather than left declared.
    float arousal  = saturate((f.arousal - 0.13f) / 0.49f);
    float val_base = mix(0.22f, 0.60f, depth_norm);
    float val      = val_base * (0.72f + arousal * 0.46f);

    // ── Per-branch tap (HERO) ────────────────────────────────────────────
    //
    // Replaces the global `beat_bass` flash entirely. Two reasons, and the second is
    // the important one:
    //
    // 1. FA #67 — a global flash and per-branch activation are the same primitive at
    //    the same timescale driving two visual layers. One of them had to go.
    // 2. D-157 — a global flash lifts EVERY pixel, so the whole frame pulses and no
    //    individual branch reads. Lighting ~32 % of branches instead keeps global
    //    luminance steady while the eye tracks individual tips. That is the difference
    //    between "the tree flashes" and "fingers are tapping", which is the exact
    //    distinction Matt drew when FTR.2's version failed live.
    //
    // Brightest at the tips, where the geometric flick is also largest, so the two
    // halves of the tap reinforce rather than fight.
    val += tap * (0.16f + 0.42f * depth_norm);
    val  = saturate(val);

    float3 color = hsv2rgb(float3(fract(hue), sat, val));

    // ── Edge soft-fade ───────────────────────────────────────────────────
    // Interpolate across the branch width (uv.y = 0..1 → edge at 0 and 1).
    float edge_dist = 1.0f - abs(across_width * 2.0f - 1.0f);  // 0 at edges, 1 at centre
    float edge      = smoothstep(0.0f, 0.25f, edge_dist);

    // Subtle taper toward branch tips keeps silhouettes looking organic.
    float tip_taper = 1.0f - along_branch * along_branch * 0.25f;

    color *= edge * tip_taper;
    color  = min(color, float3(1.0f));

    return float4(color, edge);
}

// MARK: - Vertex Fallback (M1 / M2)

/// Fullscreen triangle fallback for hardware that does not support mesh shaders.
/// Outputs MeshVertex (with non-zero normal) so the fragment shader renders a
/// visible gradient rather than solid black.
vertex MeshVertex fractal_tree_fallback_vertex(uint vid [[vertex_id]])
{
    // Standard fullscreen-triangle UV pattern, remapped to [0, 1].
    float2 uv = float2(float((vid << 1u) & 2u), float(vid & 2u)) * 0.5f;

    MeshVertex out;
    out.position = float4(uv * 4.0f - 1.0f, 0.0f, 1.0f);
    out.uv       = uv;
    // Set depth_norm to 0.5 so the fragment renders a mid-canopy green,
    // and is_leaf to 0 so there's no tip shimmer on the fallback plane.
    out.normal   = float3(0.5f, 0.0f, 0.0f);
    return out;
}
