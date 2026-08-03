// FractalTree.metal — Fractal tree mesh shader preset (Increment 3.2b).
//
// A recursive binary tree with 63 branches across 6 depth levels (0–5).
// Each of 63 mesh-shader threads computes one branch's geometry using an
// iterative ancestry traversal (no MSL recursion).  Audio drives:
//
//   bass_att      → trunk length + branch count visible (growing tree effect)
//   mid_att       → branch spread angle (wider canopy = denser mid energy)
//   spectral_centroid → leaf hue shift (dark greens → golden-green)
//   beat_bass     → flash brightness on beat pulse
//   treb_att      → leaf tip shimmer intensity
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
    /// collision D-212 measured). Derived from `bass_dev` once, in the object shader.
    float reach;
    /// BRANCH SPREAD, radians — how wide the canopy opens. Derived from
    /// `spectral_flux` in the object shader.
    float spread;
    float treb_att;
    float beat_bass;
    float spectral_centroid;
    float time;
    float aspect_ratio;
    uint  branch_count;   // 7–60: how many branches to render this frame
};

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
        // ── CANOPY REACH ← bass_dev (D-026 deviation primitive) ──────────────────
        //
        // MEASURED, not assumed. `bass_dev = max(0, bassRel)` where `bassRel` is the
        // band's deviation from its own running EMA — so it is an UPWARD-transient
        // signal, zero on 66–89 % of frames because most frames are not transients.
        // Its p05→p95 span across the four measured sources (Hummer 2026-08-03T20-05-13Z
        // plus the three route_coverage fixtures):
        //
        //     Hummer 0 → 0.153   love_rehab 0 → 0.255
        //     so_what 0 → 0.575  there_there 0 → 0.104     (p99 reaches 1.06; max 2.59)
        //
        // Every other bass primitive was measured and rejected: `bass_att` (shipped)
        // has std 0.013 on love_rehab and 0.017 on there_there — nearly constant, which
        // is why the shipped tree does not move; `bass_att_rel` is smoother but spans
        // only ±0.05 on the same two tracks. `bass_dev` is the ONLY bass primitive with
        // real dynamic range on all four sources.
        //
        // SOFT-KNEE, not a linear gain. `bd / (bd + k)` is asymptotic: it never reaches
        // 1, so the canopy can never flat-top (the shipped preset pinned at 63 branches),
        // and the ~3× spikes FA #73 warns about compress instead of clipping. k = 0.12
        // is sized against the measured p95 BAND [0.104, 0.575] rather than any single
        // track, so each source uses a useful slice of the range:
        //
        //     bd 0.10 → 0.46    bd 0.15 → 0.56 (Hummer p95)    bd 0.26 → 0.68
        //     bd 0.58 → 0.83 (so_what p95)     bd 1.06 → 0.90  bd 2.59 → 0.96
        //
        // At silence bass_dev is 0 → reach 0 → the sparse 7-branch tree the reference
        // README asks for ("trunk plus the first two generations"), never black (D-037).
        float bd    = max(f.bass_dev, 0.0f);
        float reach = bd / (bd + 0.12f);

        // One gesture, three coupled terms. 7 at rest → 60 at the asymptote; the ceiling
        // is unreachable by construction, so a chorus cannot sit pinned at maximum.
        uint count = 7u + (uint)(reach * 56.0f);

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

        payload->reach             = reach;
        payload->spread            = spread;
        payload->branch_count      = min(count, 63u);
        payload->treb_att          = f.treb_att;
        payload->beat_bass         = f.beat_bass;
        payload->spectral_centroid = f.spectral_centroid;
        payload->time              = f.time;
        payload->aspect_ratio      = max(f.aspect_ratio, 0.1f);
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

    // Audio-driven tree parameters.
    //
    // Trunk length and thickness read the SAME `reach` scalar the branch count does —
    // "how big is the tree" is one gesture expressed through three coupled geometry
    // terms, not three routes competing. Spans widened against the measured drive:
    // trunk 0.36–0.62 (shipped 0.40–0.62 but on a near-constant primitive), thickness
    // 0.038–0.058, a 53 % swing against the shipped 11.7 %.
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

    float2 branch_start = pos;
    float2 branch_end   = pos + dir * seg_len;

    // Depth metadata for the fragment shader.
    float depth_norm = float(leaf_depth) / 5.0f;    // 0 = trunk … 1 = deepest leaf
    float is_leaf    = float(leaf_depth == 5 ? 1 : 0);

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

    MeshVertex v;
    v.normal = float3(depth_norm, 0.0f, is_leaf);

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
    float is_leaf      = in.normal.z;    // 1 if depth == 5, else 0
    float along_branch = in.uv.x;        // 0 = branch base, 1 = branch tip
    float across_width = in.uv.y;        // 0 and 1 = edges, 0.5 = centre

    float beat     = f.beat_bass;
    float mid_att  = f.mid_att;
    float treb_att = f.treb_att;

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

    // ── Brightness ───────────────────────────────────────────────────────
    // Base value rises from trunk to tip, boosted by mid energy.
    float val_base = mix(0.22f, 0.60f, depth_norm);
    float val      = val_base
                   + mid_att  * 0.18f
                   + treb_att * 0.12f * is_leaf;   // tip shimmer on treble

    // Beat flash: short-lived brightness spike, amplified at leaf tips.
    val += beat * (0.25f + 0.25f * depth_norm);
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
