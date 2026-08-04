// FractalTree.metal — Fractal tree mesh shader preset (Increment 3.2b).
//
// A recursive binary tree with 63 branches across 6 depth levels (0–5).
// Each of 63 mesh-shader threads computes one branch's geometry using an
// iterative ancestry traversal (no MSL recursion).
//
// AUDIO ROUTING — FTR.2 → FTR.3f, every round rebuilt after a live rejection.
// Five visual layers, five distinct primitives (FA #67), every coefficient sized
// against its primitive's MEASURED span on a real capture:
//
//   arousal            → GROWTH: trunk, thickness, brightness and the canopy floor.
//                        The only slow signal in the vector (0.52 turns/s) and the
//                        only thing continuous geometry is allowed to read.
//   spectral_density   → SECTION LIFT on the branch COUNT only (DYN.1). Registers a
//                        distorted guitar or a chorus on a limited master, where RMS
//                        is flat and arousal has already saturated.
//   beat_mid           → THE TIPS: how many fine branches exist and how far each one
//                        reaches. Strongest sync signal measured (+0.237).
//   spectral_flux      → branch spread angle (20°–34°)
//   tonal_phase_fifths → hue, with a per-depth offset so every level has its own colour
//   pulse_amp01        → silence gate (a gate, not a route — "is anything playing")
//
// THE ONE STRUCTURAL RULE, learned the hard way three times: CONTINUOUS GEOMETRY READS
// ONLY SLOW SIGNALS. Trunk length and thickness slide visibly, so anything faster than
// ~1 turn/s on them reads as the tree bouncing rather than growing. `bass_rel` (5.88/s)
// and raw `spectral_density` (5.59/s) each produced that complaint from Matt verbatim.
// Fast signals go to the QUANTISED branch count, where a change reads as growth.
//
// WHAT MATT ASKED FOR: *"the tree was growing with the music and the tiny branches were
// following the melody … you have told me this was an illusion, not how it was
// programmed, but this is what I am looking for the preset to do."* The original
// illusion came from a single global count truncating a breadth-first branch list.
// That mechanism is kept and split: growth sets the canopy floor, the tips cross the
// depth-5 boundary at 31, and the smallest branches appear and disappear at the edge.
//
// REMOVED, and staying removed: the `fract(t * 0.006)` wall clock (out-drove the music
// 18.6 : 1); three layers sharing `bass_att`; `tip_shimmer` on `treb_att` (+0.002 of a
// promised +0.12); the global `beat_bass` flash and both the per-beat and per-bar tap
// systems (Matt rejected beat-driven activity twice); and an asymmetric-decay tap that
// was really just a permanently lower threshold, which lit too much of the canopy.
//
// NOT here: `StemFeatures` is unreachable from the object/mesh stages until FTR.4 binds
// buffer(3) there (the FRAGMENT stage is already bound by `drawWithMeshShader`).
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
    /// THE TIPS, 0…1 from `beat_mid` through a soft knee. Drives how many fine
    /// branches exist AND how far each one reaches — one gesture, two coupled terms.
    float melody;
    float aspect_ratio;
    uint  branch_count;   // 15–61: how many branches to render this frame
};

// MARK: - Hash

/// Integer avalanche hash (lowbias32). Gives each branch a stable threshold on the
/// melodic line. Stateless and reproducible: a branch always responds at the same
/// point on the line, which is what makes the motion read as following, not random.
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
        // ── GROWTH ← arousal, SECTION LIFT ← spectral_density ────────────────────
        //
        // THE TRUNK READS AROUSAL AND NOTHING ELSE. The first DYN.1 build folded the
        // density lift into `reach`, which trunk length and thickness both read — and
        // Matt rejected it on sight: *"the trunk of the tree is moving up and down
        // constantly. not an improvement."* Measured, he is right and it was my
        // regression: the raw density fraction turns 5.59 times a second, the same order
        // as the `bass_rel` whose 5.88/s caused this exact complaint at FTR.3d.
        //
        // Smoothing alone cannot rescue it. Even with the legs widened to τ6 s / τ45 s the
        // RATIO still turns ~1.1/s against arousal's 0.5 — a ratio of two moving averages
        // is inherently restless. So the fix is structural rather than another coefficient:
        // continuous geometry (trunk length, thickness) reads ONLY the slow envelope, and
        // the density lift is confined to the branch COUNT, which is quantised and reads
        // as growth rather than as the trunk sliding.
        float reach = saturate((f.arousal - 0.10f) * (1.0f / 0.58f));

        // Section lift, for the COUNT only. Both legs are smoothed (τ6 s against τ45 s),
        // so this answers "denser than this track's normal" — which is what registers a
        // distorted guitar or a chorus on a limited master where RMS is flat.
        float lift = saturate((f.spectral_density / max(f.spectral_density_slow, 1e-4f) - 1.0f) * 1.1f);

        // SILENCE GATE. `pulse_amp01` is 0 before the first note and across sustained
        // silence, returning the sparse 7-branch figure the reference README asks for
        // ("trunk plus the first two generations"), still non-black (D-037). A GATE, not
        // a route: it carries no musical information, only "is anything playing".
        float amp = saturate(f.pulse_amp01);

        // ── MELODIC TIPS ← beat_mid (Matt's pick, 2026-08-04) ─────────────────────
        //
        // The previous driver, `mid_rel`, measured **+0.038** against the music moment to
        // moment — statistically nothing, and Matt's *"the tips are not in sync with the
        // music"* is that number. `beat_mid` is the strongest sync signal in the vector
        // at **+0.237**, roughly 6× better, and it is the beat in the MELODIC register
        // rather than the kick, so the tips move with guitars and vocals instead of the
        // bass line. It turns 6.9 times a second, which is why it belongs on the fine
        // tips and emphatically not on the trunk.
        // SOFT KNEE, sized on Matt's own capture. Raw `beat_mid` swings 0→1 spikily
        // (p50 0.33, p95 1.00), and driving the tips from it directly slammed 12.1
        // branches per change on Cherub Rock — close to the 21.5 of the FTR.2 build he
        // called *"too excited"*. The knee compresses the spikes without flattening the
        // signal: measured 5.1 branches per change on Cherub and 2.0 on the fixtures,
        // with the deepest tier still crossing in and out 6–8 times a second.
        float melody = f.beat_mid / (f.beat_mid + 1.8f);

        // Depth tiers are the mechanism: a tier appears only above a threshold count
        // (d3 > 7, d4 > 15, d5 > 31), so the smallest branches enter and leave as the
        // count crosses 31. Growth sets where the canopy sits; the tips cross the line.
        uint  base   = (uint)((4.0f + saturate(reach + lift * 0.30f) * 18.0f) * amp);
        // TIPS ARE GATED BY GROWTH. Matt, 2026-08-04: *"the tree actually grows taller
        // BEFORE this melody enters."* Measured on that session, he is exactly right and
        // the cause is this layer: at t=19 s the growth part sat at its minimum of 4
        // while the tips added 5 branches, taking the tree from 11 to 16 — eight seconds
        // before the band arrives at 27–29 s. The quiet intro still has beats, so
        // `beat_mid` fires through it and the tips grew a tree the music had not earned.
        //
        // Gating on the growth envelope means the fine tips can only appear once the
        // section itself has arrived. The smoothstep keeps them fully available through
        // the body of the song (reach ≥ 0.35) while suppressing them in an intro.
        uint  tips   = (uint)(melody * 26.0f * amp * smoothstep(0.0f, 0.35f, reach));
        uint  count  = min(7u + base + tips, 63u);

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
        payload->melody       = melody * amp;
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

    // ── THIS BRANCH FOLLOWING THE MELODY ──────────────────────────────────────────
    //
    // Matt called the tips "better overall and probably satisfactory" and asked for
    // further improvement if any was available. Measured first: there is no materially
    // better DRIVER in the feature set — beatTreble (+0.200), beatComposite (+0.199)
    // and spectralCentroid (+0.190) all sit within noise of beat_mid (+0.179), and
    // swapping on a +0.02 difference is a change nobody could see. So this pass changes
    // the EXPRESSION of the same signal, in three ways:
    //
    // 1. TRAVELLING WAVE. Each branch reads the line at its own point in the ROLL-OFF,
    //    not just its own threshold, so activation sweeps outward through the canopy
    //    instead of a whole tier answering at once. A melodic line moves across an
    //    instrument; it does not strike it as a block.
    // 2. ASYMMETRIC DECAY. The tap rises fast and falls slow, so tips RING rather than
    //    snap back. Same firing rate, less flicker — which is the specific risk of a
    //    driver that turns 6.9 times a second.
    // 3. DEPTH HIERARCHY. The outermost tier responds further and faster than the tier
    //    below it, so the canopy has an internal order rather than one uniform gesture.
    //
    // Stateless throughout: a branch's phase and threshold are pure hashes of its index,
    // so the pattern is stable frame to frame. That stability is the difference between
    // "following" and the "haphazard" Matt rejected at FTR.2.
    float depth_hint = float(leaf_depth) / 5.0f;
    uint  h    = fractal_hash(bid * 2654435761u);
    float slot = float(h & 1023u) * (1.0f / 1023.0f);
    float lag  = float((h >> 10) & 255u) * (1.0f / 255.0f);

    // The wave: deeper branches are read later along the line's rise, so the front
    // travels from the inner canopy outward rather than lighting everything together.
    float travel = payload.melody - lag * 0.18f * depth_hint;

    // Single threshold, as at FTR.3e — the form Matt called satisfactory.
    //
    // THE ASYMMETRIC-DECAY IDEA WAS REVERTED, and it is worth recording why rather than
    // just deleting it. `max(rise, fall * 0.62)` was meant to give a slow release, but a
    // stateless shader cannot know a branch HAS fired — so the second term was simply a
    // lower threshold, permanently active, and it lit far more of the canopy at once.
    // That is the "too active now" half of Matt's report. A real release needs per-branch
    // state, which is FTR.4/MEL territory, not a curve trick.
    float tap = smoothstep(slot * 0.85f, slot * 0.85f + 0.25f, travel);

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

    // THE MELODY, in geometry. The branch reaches out along its own direction as the
    // line rises past its threshold. Weighted hard toward depth so the trunk is almost
    // still and the finest branches travel most — Matt's words were *"the TINY branches
    // were following the melody"*, and a trunk that swings with the tune reads as the
    // whole tree lurching, not as fine detail tracking a line.
    float depth_norm = float(leaf_depth) / 5.0f;    // 0 = trunk … 1 = deepest leaf
    float is_leaf    = float(leaf_depth == 5 ? 1 : 0);
    seg_len *= 1.0f + tap * (0.02f + 0.40f * depth_norm * depth_norm);

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
    // EACH BRANCH LEVEL GETS ITS OWN HUE (Matt's call, 2026-08-03). FTR.2 mapped the
    // harmony onto a 0.28 amber→green arc because I judged that a tree "should" look
    // tree-coloured. That was my aesthetic standing in for his, and he rejected it:
    // *"they are all variations on tree colors … I liked the more psychedelic colouring
    // of the previous version."*
    //
    // What he liked swept 147°→293° — green through cyan, blue, violet — and it came
    // from the `fract(t)` wall clock D-212 correctly flagged for out-driving the music
    // 18.6 : 1. The diagnosis was right and the fix threw out the colour with it. This
    // recovers the range WITHOUT the clock: a 0.55 arc from the harmony, plus a 0.10
    // offset per depth level. Measured across the six tiers that puts colour in all
    // 12 hue families, against 4 for FTR.2 — and because the offset is keyed to depth,
    // the levels become legible AS colour, which is the other half of what he asked for
    // (*"I was able to see … the different levels of branches more easily"*).
    //
    // Harmony still moves the whole palette together, so the tree recolours with the
    // song rather than on a timer. The relationship between levels is fixed; where the
    // whole set sits is the music's to decide.
    float hue_bark  = 0.065f;
    float tonal01   = fract(f.tonal_phase_fifths * (1.0f / (2.0f * M_PI_F)) + 0.5f);
    float level     = depth_norm * 5.0f;                     // 0 = trunk … 5 = leaf tier
    float hue_leaf  = fract(0.02f + tonal01 * 0.55f + level * 0.10f);
    // The trunk stays bark; everything from the second tier up takes the full palette,
    // so the tree still reads as a tree rather than a rainbow stick.
    float hue       = mix(hue_bark, hue_leaf, smoothstep(0.0f, 0.35f, depth_norm));

    // ── Saturation ───────────────────────────────────────────────────────
    // Pushed up with the palette. A per-level hue spread only reads as distinct levels
    // if the levels are actually saturated — at 0.55 the inner tiers wash toward each
    // other and the spread is wasted. Trunk stays muted so it still reads as bark.
    float sat = mix(0.42f, 0.96f, depth_norm);

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

    // ── Per-branch melodic lift ──────────────────────────────────────────
    //
    // The brightness half of the same gesture: a branch that has reached out also
    // lights up, so the moving front is legible as light as well as shape. Weighted
    // to depth for the same reason the geometry is — the fine branches are the ones
    // meant to read.
    //
    // The global `beat_bass` flash was removed at FTR.3 and stays removed. A global
    // flash lifts every pixel, so no individual branch can read against it (D-157);
    // and Matt has now twice asked for less beat-driven activity, not more.
    val += tap * (0.06f + 0.40f * depth_norm * depth_norm);
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
