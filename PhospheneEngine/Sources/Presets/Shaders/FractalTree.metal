// FractalTree.metal — Fractal tree mesh shader preset (Increment 3.2b).
//
// A recursive binary tree with 63 branches across 6 depth levels (0–5).
// Each of 63 mesh-shader threads computes one branch's geometry using an
// iterative ancestry traversal (no MSL recursion).
//
// AUDIO ROUTING — FTR.2 → FTR.3c, each round rebuilt after a live rejection.
// Six visual layers, six distinct primitives (FA #67), every coefficient sized
// against its primitive's measured p05→p95 span on a real capture:
//
//   bass_rel           → GROWTH: the tree's structure, count + trunk + thickness
//                        as one coupled gesture
//   mid_rel            → THE MELODY: how many fine tips exist, and how far each
//                        individual one reaches. The hero route.
//   spectral_flux      → branch spread angle (20°–34°)
//   tonal_phase_fifths → hue, with a per-depth offset so every branch level
//                        carries its own colour
//   arousal            → global brightness envelope (the section-scale arc)
//   pulse_amp01        → silence gate (a gate, not a route — "is anything playing")
//
// WHAT MATT ASKED FOR, in his words: *"the tree was growing with the music and the
// tiny branches were following the melody … you have told me this was an illusion,
// not how it was programmed, but this is what I am looking for the preset to do."*
// The original illusion came from a single global count truncating a breadth-first
// branch list. That mechanism is kept and split — energy grows the structure,
// mid_rel moves the tips — so the effect is now produced deliberately.
//
// REMOVED, and staying removed: the `fract(t * 0.006)` wall clock (out-drove the
// music 18.6 : 1); three layers sharing `bass_att`; `tip_shimmer` on `treb_att`
// (+0.002 of a promised +0.12); the global `beat_bass` flash and the per-beat and
// per-bar tap systems that replaced it — Matt rejected beat-driven activity twice.
//
// NOT here: `StemFeatures` is unreachable from the object/mesh stages until FTR.4
// binds buffer(3) there (the FRAGMENT stage is already bound by drawWithMeshShader).
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
    /// THE MELODIC LINE, 0…1 from `mid_rel`. Drives how far out the canopy reaches
    /// AND how much each individual fine branch extends — one gesture, two coupled
    /// terms, the way canopy reach couples count/length/thickness.
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

        // DEPTH TIERS ARE THE POINT, so the live range is sized against them rather than
        // against branch count as a number. A tier appears only above a threshold count:
        // d3 > 7, d4 > 15, d5 > 31. FTR.3 mapped 7 + reach·56 and Matt lost the deep
        // tiers — measured on session 2026-08-03T23-16-22Z, d5 showed on 23 % of frames
        // against the old preset's 38 %, and he said so directly: *"I never see beyond
        // three levels of branches."*
        //
        // Because leaf hue is keyed to DEPTH (below), losing tiers also loses colour —
        // half his "less colourful" complaint is really this regression, not the palette.
        //
        // ── GROWTH (energy) + MELODIC TIPS (mid_high) ────────────────────────────
        //
        // Matt, 2026-08-04: *"it previously looked like the tree was growing with the
        // music and the tiny branches were following the melody … you have told me this
        // was an illusion, not how it was programmed, but this is what I am looking for
        // the preset to do."*
        //
        // So build the illusion on purpose. The original effect came from ONE mechanism:
        // a global count truncating a breadth-first branch list, so the highest indices —
        // which are exactly the smallest, deepest branches — appeared and disappeared at
        // the edge in sequence. Nothing about it was per-branch or melodic; it just read
        // that way. The count is therefore split in two, keeping the mechanism and giving
        // each half the driver its perceived behaviour implies:
        //
        //   BASE  ← bass_rel, the growth. Slow, continuous, the tree's structure.
        //   TIPS  ← mid_high, the melody. Fast, wiggly, only the outermost branches.
        //
        // WHY A MID-BAND DEVIATION AND NOT A PITCH SIGNAL. The obvious choice was a
        // harmonic axis, measured and rejected: `tonal_phase_thirds` jumps a median
        // 18.6 % of the circle per update and only 28 % of its steps are smooth glides,
        // so branches keyed to it flicker at random — the "haphazard" failure again.
        // The mid band glides and changes direction 5–17 times a second across the four
        // measured sources, which is the rate a melodic line actually moves. It is also
        // the band a melody or vocal occupies, so it rises and falls WITH the tune even
        // though it carries no pitch.
        //
        // `mid_rel`, NOT `mid_high`. The first attempt mapped `(mid_high - 0.005)/0.042`
        // — an absolute threshold on an AGC-normalised value, which is FA #31 verbatim,
        // and the gate caught it. Measured raw spans vary TWENTY-FOLD across tracks
        // (midHigh p05→p95: 0.0040 on love_rehab, 0.0765 on so_what), so any fixed
        // mapping is inert on one track and saturated on another — exactly the failure
        // FA #31 describes. `mid_rel` is the D-026 deviation form: signed, continuous,
        // centred on the band's own running average, so a logistic self-centres per
        // track the same way canopy reach does with `bass_rel`.
        //
        // k = 60 sized against the measured half-spans (~0.03 typical): it puts p05→p95
        // at 0.28→0.95 on Cherub Rock, 0.30→0.71 on love_rehab, 0.24→0.93 on
        // there_there, and soft-saturates so_what's 9× wider swing instead of clipping.
        float melody = 1.0f / (1.0f + exp(-f.mid_rel * 60.0f));

        // SIZED TO STRADDLE THE d5 BOUNDARY, which is where the effect actually lives.
        // A tier appears only above a threshold count, and d5 — the smallest branches —
        // starts at 31. The original preset Matt liked sat at p50 23 with d5 present on
        // just 8 % of frames, so the deepest tier was CONSTANTLY crossing in and out;
        // that crossing is what he read as the tiny branches following the tune.
        //
        // A first pass at this put p50 at 39 and d5 at 94 %, and measured beautifully
        // while destroying the effect: with the tips always present there is nothing
        // left to appear or disappear. These coefficients put p50 at 23–30 and d5 at
        // 21–36 % across the four sources — the tier is in play, not parked.
        uint  base   = (uint)((4.0f + reach * 18.0f) * amp);
        uint  tips   = (uint)(melody * 20.0f * amp);
        uint  count  = min(7u + base + tips, 63u);

        // THE BEAT-LOCKED TAPS ARE GONE. FTR.3 hash-selected a subset of branches per
        // bar and ran an attack/decay envelope on each. Matt rejected it twice — first
        // *"much too active with drums"*, then, once slowed to the bar, it simply was not
        // what he was describing. He never asked for a beat response; he asked for growth
        // and for the fine branches to follow the melody. A per-beat mechanism cannot
        // deliver either, so it is removed rather than re-tuned (D-212's rule: a route
        // that is not the effect gets deleted, not turned down).

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
    // Every branch gets its own THRESHOLD on the melodic line rather than its own
    // envelope on a clock. As `mid_high` rises, branches with a low threshold extend
    // first and high-threshold ones follow; as it falls they retract in reverse. The
    // canopy therefore sweeps in and out as a moving front instead of pulsing in
    // lockstep — which is what makes individual small branches look like they are
    // tracking a line rather than obeying a metronome.
    //
    // Stateless and reproducible: a branch's threshold is a pure hash of its index, so
    // the same branch always responds at the same point on the line and the pattern is
    // stable rather than random frame to frame. That stability is the difference
    // between "following" and the "haphazard" Matt rejected.
    //
    // Thresholds are packed into the lower 0.85 of the range so the top of a melodic
    // swell recruits essentially the whole canopy.
    float slot = float(fractal_hash(bid * 2654435761u) & 1023u) * (1.0f / 1023.0f);
    float tap  = smoothstep(slot * 0.85f, slot * 0.85f + 0.25f, payload.melody);

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
