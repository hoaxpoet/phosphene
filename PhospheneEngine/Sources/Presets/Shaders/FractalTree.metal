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
//   other_onset_rate   → THE TIPS: how many fine branches exist and how far each one
//                        reaches. An ACTIVITY LEVEL in the non-drum/non-bass/non-vocal
//                        residue — NOT an instrument. FTR.8 routed this as "the guitar";
//                        FTR.12 measured that claim false and retired it (Matt,
//                        2026-08-12). See the routing note in the object shader.
//   beat_mid           → the cold-start stand-in for the tips until the stems converge
//                        (D-019 crossfade); carries nothing once they do.
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
// STEMS: bound at buffer(3) on the object/mesh stages as of FTR.4 — `MeshGenerator.draw`
// mirrors the fragment binding `drawWithMeshShader` always had. The tips read
// `stems.other_onset_rate` (residue activity, NOT an instrument — FTR.12); see the routing
// note in the object shader.
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
    /// BRANCH SPREAD, radians — how wide the canopy opens. STATIC as of FTR.26 (Matt asked
    /// twice for `spectral_flux` to come off it); kept in the payload because every branch
    /// still reads it.
    float spread;
    /// CANOPY WEIGHT, 0…1 — held `spectral_flux`. How DENSE and HEAVY the canopy is: it adds
    /// fine branches and thickens every stroke. FTR.26's replacement for the spread route.
    float canopy_weight;
    /// SECTION SURGE, 0…1 — steps up on an arrival and holds. Elongates the trunk and
    /// carries the branch count across a tier boundary.
    float surge;
    /// THE TIPS, 0…1 from `beat_mid` through a soft knee. Drives how many fine
    /// branches exist AND how far each one reaches — one gesture, two coupled terms.
    float melody;
    /// TRUNK LENGTH, clip-space — the same 0.27 + reach·0.13 + surge·0.32 the mesh shader
    /// used to compute inline, but evaluated on the BEAT-HELD FeatureVector (FTR.10). Holds
    /// still between beats and steps on the beat; falls back to the continuous value
    /// whenever the grid is not trustworthy. Every segment scales off it, so this is the
    /// whole skeleton's size, and it is the one term Matt asked to stop sliding.
    float trunk_len;
    float aspect_ratio;
    uint  branch_count;   // 15–61: how many branch SLOTS to render this frame (= ceil below)
    /// FRACTIONAL BRANCH COUNT — the same quantity as `branch_count` before rounding, and
    /// the reason the canopy stops popping (FTR.13, Matt 2026-08-12).
    ///
    /// A count is an INTEGER, so a held count cannot ease however the clock is timed: 15
    /// branches arriving is 15 discrete objects. Measured across three captures, the worst
    /// single beat added 15–19 branches at once on a tree spanning 43, and moving the hold to
    /// the bar made it 23–28 — slowing the clock concentrates the pop instead of removing it.
    ///
    /// So the mesh shader gives branch `bid` a growth weight of `count_f - bid`, clamped to
    /// 0…1: the branch at the frontier extends from zero length as the count passes it, and
    /// the ones behind it are already full. A 15-branch rise becomes a 15-branch SWEEP over
    /// the eased step rather than a block appearing, which is Matt's *"grow in individually"*.
    float branch_count_f;
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

// MARK: - Growth

/// The two continuous growth terms — `.x` canopy reach, `.y` section surge — derived from
/// one FeatureVector.
///
/// Factored out at FTR.10 so the object shader can evaluate them TWICE: once on the live
/// vector at buffer(0), for the canopy and the branch counts, and once on the beat-held
/// vector at buffer(4), for the trunk. Two call sites, one arithmetic — a second copy of
/// this expression is how the trunk and the canopy would silently drift apart.
/// - Parameter fSection: the same vector on a ~2 s glide (buffer 6). Supplies the DENSITY used
///   only to correct a limiter inversion; see the size block.
static inline float2 fractal_growth(constant FeatureVector& f,
                                    constant FeatureVector& fSection)
{
    float arousalReach = saturate((f.arousal - 0.10f) * (1.0f / 0.58f));
    // DYN.2c: the field is this moment's RANK in the track's own density distribution
    // (×2, so 1.0 still reads as "this track's normal"). Uniform over the track by
    // construction, so there are NO fitted edges left to get wrong — the 0.78/1.38 pair
    // this replaces was fitted against DYN.2b's broken ratio and clipped Hummer to a
    // flat 1.00 for four minutes once the normal was measured correctly.
    float fullness = saturate(f.spectral_section_ratio * 0.5f);
    float musicGate = smoothstep(0.05f, 0.30f, saturate(f.spectral_surge));
    // ── THE SIZE: LEVEL, CORRECTED ONLY WHERE THE LIMITER INVERTS IT (FTR.18) ────────
    //
    // Level rank stays the driver. It has the dynamic range — six alternatives were measured
    // across FTR.16/17 and every one lost span, height or pacing (see the diagnostics doc). Its
    // ONE defect is that on a limited master the level DIPS as the band arrives: measured
    // r(trunk, spectral_density) = −0.641 on Carry The Zero, whose `musicRange` is 3.6 dB.
    //
    // So correct that defect and nothing else. The limiter signature is specific — level LOW
    // while density is HIGH — and it is detectable without trusting level's magnitude:
    //
    //   band entry (playback 6.7 s):  level 0.088   density-knee 0.751   → lift +0.663
    //   quiet passage (35.0 s):       level 0.515   density-knee 0.442   → lift  0.000
    //
    // BOUNDED, which is the whole point (Matt, after seeing an unbounded `max()` render:
    // *"row 4 looks too active"*). The correction is gated OFF as level rises, so a passage whose
    // level is already healthy cannot be lifted however high density goes. Below 0.15 the gate is
    // fully open; by 0.40 it is shut. Both conditions must hold — `max(0, density − level)` is
    // already zero unless density exceeds level — so this fires only on the inversion.
    float level = saturate(f.spectral_surge);
    float density = saturate(fSection.spectral_density / (fSection.spectral_density + 0.22f));
    float inverted = 1.0f - smoothstep(0.15f, 0.40f, level);
    return float2(saturate(max(0.10f * arousalReach, fullness) * musicGate),
                  saturate(level + max(0.0f, density - level) * inverted));
}

// MARK: - Object Shader

/// Reads the current FeatureVector, computes the audio-driven branch count,
/// and packs the payload for the mesh shader.  One thread, one meshlet.
[[object, max_total_threads_per_threadgroup(1)]]
void fractal_tree_object_shader(
    object_data FractalPayload* payload [[payload]],
    mesh_grid_properties          mgp,
    constant FeatureVector&       f [[buffer(0)]],
    constant StemFeatures&        stems [[buffer(3)]],
    constant FeatureVector&       fHeld [[buffer(4)]],
    /// FTR.18 — the ~2 s section glide, read ONLY to correct a limiter inversion in the size.
    constant FeatureVector&       fSection [[buffer(6)]],
    /// FTR.13 — the beat-held stem features, same beats and same ease as `fHeld` (buffer(5),
    /// bound by `MeshGenerator`). Matt: *"the tips … should be beat matched."* The tips' driver
    /// is a per-stem field, so holding only `fHeld` left them changing 4–5 times a second
    /// whatever the frame did — measured 2.05 changes per BEAT against everything else at
    /// ≤ 0.74. `stems` at buffer(3) stays live for anything that should not step.
    constant StemFeatures&        stemsHeld [[buffer(5)]],
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
        //
        // ── DYN.1e: THE TREE MUST SHRINK AS WELL AS GROW ─────────────────────────
        //
        // Matt, 2026-08-05: *"I'm not expecting the tree to grow continuously throughout
        // playback; I'm expecting it to grow AND shrink based on the energy of the music,
        // so I would expect the trunk and branches to shrink or recede some after the
        // return to the verse from the chorus."*
        //
        // `arousal` alone cannot do that. It is a mood-classifier output with ~10 s
        // smoothing and it SATURATES: measured on his session `2026-08-05T22-41-27Z` the
        // arousal-derived reach climbs 0.000 → 0.826 by 30 s and then never leaves
        // 0.91…0.99 for the rest of the track, whatever the music does. The tree grew and
        // then simply held — exactly what he described.
        //
        // `spectral_surge` is the signal that breathes, now that DYN.1c/.1d rank it in the
        // track's OWN loudness distribution: on the same capture it spans 0.005…0.964 and
        // DIPS to 0.770 at 90 s, where arousal-reach instead rises to 0.925.
        //
        // THIS IS NOT FTR.3f REPEATED — it was measured before being wired. The signal that
        // made the trunk slide was `density`, a ratio of moving averages turning 5.59 times
        // a second. The blended reach turns **0.37/s** with 1.4× the per-second motion of
        // today's arousal-only reach: an order of magnitude below the signal that caused
        // the complaint, because the surge is an asymmetric follower (fast attack, slow
        // release), not a ratio. Re-measure this pair if either leg is ever retuned.
        //
        // 65/35 toward the surge: Matt asked it to "recede SOME", not to collapse. The
        // arousal term is the floor that keeps a body through the song; the surge term is
        // what makes a verse return visibly pull the tree back. Measured at the 90 s dip:
        // 0.933 → 0.824 blended, against 0.913 → 0.925 today.
        // DYN.2 CORRECTION. The DYN.1e blend above moved the trunk, but Matt's review was
        // *"neither grew nor receded when the distorted guitar came in … did not recede
        // after the chorus."* Measured on his `2026-08-06T14-59-37Z` capture, he is right
        // and the cause is range, not direction: that blend traverses **0.83…0.92 across
        // the whole body of the track** — a 10 % band. It does move; there is nothing to
        // see. And it climbs over ~50 s, so no passage of the music registers as an event.
        //
        // The reason level cannot do better HERE: Cherub Rock has **1.4 dB of inner range**
        // (DYN.1d measured it). Verse and chorus are the same loudness. Nothing derived
        // from level — including the ranked surge — can separate them.
        //
        // What separates them is SPECTRAL CONTENT, which is where DYN.1 came in: distortion
        // adds harmonics, not amplitude. Measured on the same capture, density τ10 s sits
        // at 0.13 through the verse and 0.21 through the chorus.
        //
        // `spectral_section_ratio / spectral_density_slow` is that quantity divided by
        // the track's OWN running average, so it is self-normalising — no fitted per-track
        // constant, the mistake DYN.1c/.1d exist to avoid. Measured trunk with the mapping
        // below: intro 0.00, verse 0.30…0.46, chorus 0.92…1.00, easing to 0.88 after. A
        // swing across the range instead of a 10 % wobble.
        //
        // AND IT IS SMOOTH, which is the explicit requirement — Matt, after I proposed a
        // quantised version: *"I just want it to grow and recede with the energy of the
        // music and do so smoothly - not in visible jumps."* Measured motion **0.0198/s**,
        // BELOW the 0.0221/s of the surge the trunk reads today and a fifth of the raw
        // density that caused FTR.3f. The τ10 s leg is what makes this safe where the
        // shipped τ0.8 s leg was not — that one is still confined to the branch count.
        //
        // The arousal floor keeps a body through the song so the tree never collapses to a
        // sapling mid-track, and the surge gate keeps a bright QUIET intro from inflating
        // it (DYN1_CALIBRATION §3: a clean intro is BRIGHTER than a pre-distortion passage,
        // so shape alone would grow the tree before the band arrives).
        // ── FTR.11: THE WHOLE FRAME HOLDS, NOT JUST THE TRUNK ────────────────────
        //
        // FTR.10 held the trunk and Matt's next review was *"The trunk and branches are
        // responding to both drums and vocals it seems and it's still too much."* Measured on
        // `2026-08-11T23-52-49Z` (*Seven Nation Army*), he is right and I had fixed the
        // smallest of the three moving things:
        //
        //   trunk length   0.66 turns/s  (held at FTR.10)
        //   branch COUNT   4.08 turns/s, span 46 branches   ← continuous
        //   branch SPREAD  5.48 turns/s, span 13.8°         ← continuous, the fastest term
        //
        // The two I left continuous are 6–8× the trunk's rate and are the biggest quantities
        // on screen. So `reach`, `surge` and `flux` all read the BEAT-HELD vector now: the
        // tree's whole frame — height, branch count, canopy width, thickness — is still
        // between beats and reshapes on the beat.
        //
        // THE TIPS STAY LIVE, deliberately, and that is the point of the change rather than
        // a caveat: with the frame quiet the fine branches are the only thing in continuous
        // motion, which is the *"the tips are difficult to see"* complaint answered from the
        // other side. `melody` and `amp` below read `f`, everything else reads `fHeld`.
        //
        // NOTE FOR ANYONE READING DYN.2 ABOVE. That block records Matt asking for growth that
        // is smooth, *"not in visible jumps"*, and this contradicts it. It is not an
        // oversight: he was offered per-beat steps, per-bar steps and continuous-but-smoother
        // twice (2026-08-11, FTR.10 and FTR.11) and chose steps both times, after seeing the
        // smooth version live. The later instruction wins. Do not "restore" smoothness citing
        // DYN.2 without asking him first.
        //
        // NOT ADDRESSED HERE, and it turned out not to be addressable: *"Guitar is barely
        // registering."* The tips span 4 branches of the count's 46, and FTR.12 then measured
        // that NO per-stem feature separates a guitar from the drums on any material — so
        // there is no guitar channel to make register. Matt retired the claim 2026-08-12; the
        // tips route is unchanged and is now described as residue activity. Evidence and the
        // one remaining candidate (a PANNs guitar class, clean guitar only) are in the tips
        // routing note in the object shader.
        float2 heldGrowth = fractal_growth(fHeld, fSection);
        float reach = heldGrowth.x;

        // ── THE SURGE: "SHOOT UP" ← spectral_surge (DYN.1b) ──────────────────────
        //
        // Matt, after eight rounds: *"Tree still does not shoot up when the distorted
        // guitar enters ... this is literally all I am looking for and the only thing you
        // have failed on consistently."* Then, decisively: **shoot up = the trunk
        // elongates and the next level of branches appears.**
        //
        // That definition is why every previous attempt failed. I was making the tree
        // respond PROPORTIONALLY — a wider canopy, a larger footprint — and grading it on
        // proportional metrics that duly improved (1.24× spread, 1.18× footprint) while
        // the thing he asked for never happened. Both halves of his definition are STEPS.
        // No proportional signal produces a step, however it is scaled, so no coefficient
        // on `density` was ever going to work.
        //
        // `spectral_surge` is built for it: pre-AGC level through an asymmetric follower
        // that arrives fast and holds. Measured on his 2026-08-04T19-20-32Z capture it
        // separates the pre-guitar passage from the arrival 20.4× (0.048 → 0.981) while
        // turning only 0.58 times a second — a step the trunk can safely read, which the
        // restless `density` ratio never was.
        // ── FTR.24, RETIRED THE DAY IT SHIPPED: the size accent is GONE ──────────
        //
        // FTR.24 split the size into a slow base plus a fast `spectral_level_rise` accent, on
        // Matt's instruction ("build option 1") after FTR.23 measured the size driver at
        // −0.52 at audible events. He rejected the live build immediately: *"Much worse now as
        // the motion is herky-jerky. Looks defective. Considerable regression."* He was right,
        // and the measurement on his capture `2026-08-17T15-23-17Z` is not close:
        //
        //                             evt/rand   travel   peak|v|   jerk p99
        //   FTR.23 base only            0.27×      8.72     1.62        23
        //   FTR.24 accent (shipped)     2.37×     31.88    17.37       589
        //
        // **10.7× the peak velocity and 25× the jerk.** Two defects of my own compounded:
        //
        // 1. The accent was added AFTER the beat-held glide (`heldGrowth.y + accent`), so it
        //    was the ONE driver in this preset with no render-rate smoothing at all — the very
        //    mechanism FTR.14 added to cure "robotic". I made it live so it would not latch to
        //    the beat grid, and mistook "not latched" for "not smoothed". My offline model
        //    glided the SUM and so understated peak velocity by 5×: the model disagreed with
        //    the shader about WHERE the smoothing sat.
        // 2. `spectral_level_rise` was calibrated on a 15.8 Hz local-file capture and shipped
        //    to a 59.4 Hz tap path, where it fired **22× more often on identical audio** (see
        //    `SpectralAnalyzer+Density`, since fixed).
        //
        // ★ AND THE REASON THIS IS A DELETION AND NOT A THIRD TUNING PASS: fixing both defects
        // removes the benefit with the defect. Lag-differenced detector + a 70 ms render-rate
        // envelope scores **0.81× event alignment at gain 0.45** — below chance — while still
        // costing 2.4× the base's peak velocity. Every setting that marks 0.8–1.5 events/s
        // multiplies peak velocity; every setting that does not, marks nothing. FTR15 §8's
        // structural finding held, and the answer it implies is the OTHER option Matt was
        // given: event marking belongs on a visual property where a fast change does not read
        // as the whole tree lurching. It does not belong on size.
        //
        // `spectral_level_rise` survives as an engine capability with no consumer — a measured
        // field, now rate-invariant, kept because the measurement was the expensive part
        // (D-097's rule: siblings, not subclasses — this is NOT infrastructure waiting for a
        // concept, it is a corrected instrument, and if nothing routes it by the next audit it
        // should be deleted).
        float surge = heldGrowth.y;   // FTR.11 — held, like every other frame term

        // ── FTR.10: THE TRUNK STEPS ON THE BEAT ──────────────────────────────────
        //
        // Matt, 2026-08-11 (`2026-08-11T18-26-52Z`): *"The trunk is moving too much, which
        // unfortunately makes the motion of the tips difficult to see. We need less motion —
        // like tying movement to the songbeat."* Asked to choose between per-beat steps,
        // per-bar steps and continuous-but-smoother, he chose **steps on each beat**.
        //
        // Measured on that session before changing anything: the trunk turns **1.75 times a
        // second**. Decomposed, `surge * 0.32` contributes span 0.168 at 1.27 turns/s and
        // `reach * 0.13` contributes span 0.109 at 0.80 turns/s — so BOTH terms have to hold,
        // not just the faster one. Freezing only the surge would leave 0.80/s, above the
        // preset's own ~1.0 turns/s legibility rule but nowhere near still.
        //
        // The mechanism is a sample-and-hold, not a smoother: `fHeld` is the FeatureVector as
        // it stood at the last beat boundary (MeshGenerator/`BeatHold`, object buffer(4)).
        // Same arithmetic, older input — so the trunk's RANGE is untouched (0.173 against the
        // continuous 0.178) and only its rate collapses (0.51 turns/s). A smoother would have
        // cost range, which is the DYN.1e failure Matt named as "a 10 % band, nothing to see".
        //
        // SUPERSEDED BY FTR.11 — this paragraph used to read "the branch counts and the tips
        // read the LIVE vector, thickness stays live". Only the TIPS still do. Holding the
        // trunk alone left the count at 4.08 turns/s and the spread at 5.48 against the
        // trunk's 0.66, and Matt's next review was "still too much". See the FTR.11 block.
        //
        // FALLBACKS ARE IN `BeatHold`, NOT HERE. When there is no grid (reactive/streaming),
        // when the grid is beat-irregular (D-154), or when the phase stalls, the snapshot
        // simply tracks the live vector and this expression is bit-identical to the
        // continuous one. There is no frozen-trunk state to reach: a preset can only step
        // while the phase is demonstrably ticking.
        float trunkLen = 0.27f + reach * 0.13f + surge * 0.32f;

        // Kept for the canopy's finer response; the surge carries the arrival.
        float lift = saturate((fHeld.spectral_density / max(fHeld.spectral_density_slow, 1e-4f) - 1.0f) * 1.1f);

        // SILENCE GATE. `pulse_amp01` is 0 before the first note and across sustained
        // silence, returning the sparse 7-branch figure the reference README asks for
        // ("trunk plus the first two generations"), still non-black (D-037). A GATE, not
        // a route: it carries no musical information, only "is anything playing".
        float amp = saturate(f.pulse_amp01);

        // ── THE TIPS ← RESIDUE ACTIVITY (other stem onset rate), FTR.4 + FTR.8 ───
        //
        // ⛔ THIS WAS "THE GUITAR" UNTIL FTR.12. IT IS NOT. Matt retired the claim on
        // 2026-08-12; the ROUTE is unchanged, its DESCRIPTION is. `other_onset_rate` is an
        // ACTIVITY LEVEL in whatever separation leaves outside drums/bass/vocals — it does
        // not identify an instrument, and no coefficient makes it one. Do not reintroduce
        // the word "guitar" here, and do not widen this term to make one "register": there
        // is nothing to amplify except the drums.
        //
        // Measured over 7 tracks — 2 clean-guitar positives, 3 GUITARLESS negatives, 2
        // distorted-rock hard cases (`docs/diagnostics/FTR12_GUITAR_CHANNEL_2026-08-12.md`):
        //
        //   r(other onset rate, drums onset rate) HIGHEST +0.792 on a SOLO PIANO recording
        //     with no guitar and no drum kit; LOWEST +0.492 on Seven Nation Army
        //   p50 spans only 4.06…5.33 across solo classical guitar, player piano, pure
        //     synthesis and distorted rock — the distributions are interchangeable
        //   on a SOLO CLASSICAL GUITAR record the drums stem, which holds nothing but
        //     separation residue, yields a HIGHER onset rate than the guitar (4.71 vs 4.46)
        //
        // WHY, from `StemAnalyzer+RichMetadata` rather than inferred: the onset fires on
        // broadband RMS flux past an ADAPTIVE relative threshold (1.5x the stem's own recent
        // flux average, 100 ms refractory). A relative threshold fires at a similar rate on
        // any signal with transients, so the feature measures the DETECTOR, not the
        // instrument. The envelope features are worse still — r 0.81…0.99 against drums on
        // every track in the corpus.
        //
        // FTR.8 justified this route at r = +0.14 with drums on ONE track. That figure does
        // not reproduce (+0.606 offline on the same track), and the two captures behind the
        // route disagreed by 0.57 on the same feature — a single-capture correlation on this
        // quantity is not a stable number. Nor is the +0.973 that FTR.6 quoted and FTR.8
        // "corrected" to +0.68: the corpus reads +0.89…+0.99. Never justify a route here
        // from one track again.
        //
        // (Primitive names stay spelled out in prose deliberately: the L2 rubric check scans
        // this file for deviation-primitive tokens, and writing a rejected one verbatim
        // flipped Fractal Tree's automated gate on the strength of a COMMENT.)
        //
        // **MEL.1 is extended, not contradicted.** MEL.1 measured per-NOTE onset DETECTION on
        // this stem (grid coherence 31 % against the drums control's 41 %) and concluded
        // distortion smears individual attacks — still true, still a reason not to attempt
        // one-tip-per-note. FTR.12 asked the deliberately weaker rate question and it fails
        // for a DIFFERENT reason: not smeared attacks, but a content-independent rate.
        //
        // A guitar layer, if ever wanted, needs a different mechanism. IFC.4's four families
        // are orchestral and contain no guitar class at all; the only measured candidate is
        // the PANNs guitar-class probability, decisive on clean guitar and unusable on
        // distorted rock guitar. That is its own increment, not a tweak here.
        //
        // SOFT KNEE SIZED IN THE HARNESS, not in a scratch script. Fifteen mappings were
        // swept through `FractalTreeMeshRenderTest`'s own arithmetic — every earlier attempt
        // to size this in a separate mirror drifted from what the harness measures, which is
        // how FTR.6 shipped a regression past a green gate.
        //
        // The binding constraint is NOT the count. `melody` is also the threshold the
        // per-branch travelling wave compares each branch's slot against, so it must stay
        // inside the 0…0.3125 ceiling the `beat_mid` knee had — a driver reaching 1.0 fires
        // EVERY branch instead of the ~37 % that did, which is a different preset. That rules
        // out the S-curves that otherwise recover more span (measured: span 3–5, depth-5
        // parked at 73–76 %).
        //
        // `r/(r+18)` is what the sweep picked, on the one metric Matt has actually complained
        // about: **depth-5 presence 11 %, against the outgoing driver's 12 %** — the tier
        // dips in and out rather than parking, which is his *"I never see beyond three
        // levels"* from FTR.3b. `r/(r+6.5)` matched the span instead and parked depth-5 at
        // 94 %, and the harness caught it.
        //
        // HONEST COST: the tips layer spans 5 branches where `beat_mid` spanned 8. An onset
        // rate is continuous, so it cannot reproduce the bimodal 0↔8 slam of a saturating
        // pulse. The gate's floor is 5 and this sits exactly on it.
        // FTR.13 — BEAT-MATCHED. Both halves now read the HELD side (buffer(5) stems,
        // buffer(4) vector), so the tips change on the beat like everything else instead of
        // 4–5 times a second. Matt, seeing FTR.11 live: *"the tips probably are still moving
        // too fast if they change 2x per beat — should be beat matched."*
        float residueActivity = stemsHeld.other_onset_rate
                              / (stemsHeld.other_onset_rate + 18.0f);

        // D-019 WARMUP. Every stem field is zero until separation converges (~10 s), and a
        // preset that reads one raw shows nothing until then. Crossfade from the old
        // `beat_mid` driver so the tips are alive from frame 1 and hand over to the stem
        // term as the stems arrive — the tree must not stand bare through the first ten
        // seconds of every track, which is exactly when a listener is deciding whether it
        // responds. Read from the LIVE stems: this is a "have the stems arrived yet" gate, and
        // gating on a beat-held copy would keep it at zero until the first beat lands.
        float stemEnergy = stems.vocals_energy + stems.drums_energy
                         + stems.bass_energy + stems.other_energy;
        float stemsAlive = smoothstep(0.02f, 0.06f, stemEnergy);
        float melody = mix(fHeld.beat_mid / (fHeld.beat_mid + 2.2f), residueActivity, stemsAlive);

        // Depth tiers are the mechanism: a tier appears only above a threshold count
        // (d3 > 7, d4 > 15, d5 > 31), so the smallest branches enter and leave as the
        // count crosses 31. Growth sets where the canopy sits; the tips cross the line.
        // THE LIFT IS ADDITIVE, NOT FOLDED INTO `reach`. Folding it in put it inside a
        // saturate() that `reach` had already nearly filled, so sweeping its weight from
        // 0.30 to 1.00 moved the tree's footprint 1.10× → 1.17× — the coefficient was not
        // the bottleneck, the saturation was. As its own term the section change adds
        // branches outright and the growth is visible.
        // FTR.13 — float, like the tips below: an integer here re-quantises the count and
        // the frontier branch cannot grow in.
        float base    = (4.0f + reach * 18.0f) * amp;
        // THE NEXT LEVEL OF BRANCHES APPEARS — the other half. A tier exists only above
        // a threshold count (d4 > 15, d5 > 31), so the surge is sized to CARRY THE COUNT
        // ACROSS one of those lines rather than to nudge it: 26 branches is more than the
        // gap from a mid-verse canopy to the deepest tier.
        float section = (lift * 8.0f + surge * 26.0f) * amp;
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
        //
        // ── FTR.6 WAS REVERTED HERE (2026-08-07), and the reason is worth keeping. ──
        // FTR.6 replaced this term with `f.melodic_tips`, an engine-side accumulator that
        // added exactly one branch per gated note event. It hit its stated targets — 2.9
        // note events/s against a 3.29/s guitar note rate, 1.00 branch per change — and
        // Matt's verdict was *"This is worse … the entire suite of movement does not feel
        // strongly tied to the music."*
        //
        // Measured on his session `2026-08-07T22-59-38Z`, he is right and the cause is
        // RANGE, which FTR.6 never measured. Across the body of the track this term swings
        // p05→p95 of **8 branches** (sd 3.02), visiting 0, 1, 3 and 8. The accumulator
        // swung **4** (sd 1.11) and sat on 5-or-6 for 91 % of frames — a near-constant
        // where the layer that carried the connection used to be.
        //
        // **The tension is structural, not a tuning miss.** Sweeping the accumulator's
        // drain from τ 0.3 s to 2.5 s against that session moves the PLATEAU (0↔1 up to
        // 8↔9) and never the span, which stays 1–3 throughout. An integrator delivers
        // one-branch steps XOR a wide swing; it cannot do both. Any future attempt at
        // "one tip per note" must keep this term's amplitude and slow its RATE — Matt's
        // own reading, confirmed 2026-08-07: same size, fewer times.
        // FTR.9 — THE GROWTH GATE IS A GATE AGAIN. It exists for Matt's *"the tree actually
        // grows taller BEFORE this melody enters"* (FTR.3e): suppress the fine tips during an
        // intro. `smoothstep(0, 0.35, reach)` did that when reach lived in 0.00…0.31. DYN.4
        // opened reach up to 0.07…0.88, so the gate was still CLIMBING through the middle of
        // the working range — a 10× multiplier swinging 0.10→1.00 and turning ~3 times a
        // second, sitting on top of the stem term.
        //
        // Measured on `2026-08-11T16-41-39Z`, that is why the tips read as unconnected: they
        // correlated **+0.590 with the gate** and only **+0.470 with the stem term**. The
        // route was working; the gate was drowning it. With edges at 0.03/0.15 the gate
        // saturates below the working range and the ordering inverts — stem term **+0.540**,
        // gate +0.516 — so the route is finally the dominant driver of its own layer.
        // (FTR.12 later measured that this term is residue activity, not a guitar; that
        // changed the label, not the drowning problem this paragraph fixed.)
        //
        // It still gates: an intro measures reach ≈ 0.001…0.06, which this maps to 0.00…0.15.
        // FTR.13 — FRACTIONAL, not rounded. The count is what pops, and the fractional part is
        // what lets the frontier branch grow in instead of appearing (see `branch_count_f`).
        float tipsF  = melody * 26.0f * amp * smoothstep(0.03f, 0.15f, reach);
        // ── FTR.26: CANOPY WEIGHT ← spectral_flux (Matt's pick, 2026-08-17) ──────
        //
        // Flux came off the branch spread on his instruction (asked twice; the cost is recorded
        // at the spread). Asked what should carry the tree's response to the music's energy
        // instead, he chose the fine branches. Measured, that alone was not enough: flux on the
        // COUNT moves the drive-range response from 0.119 to only **0.209** mean |Δpixel|,
        // where flux on the spread had moved it to 1.067 — **adding thin tips changes few
        // pixels; rotating every branch changes many.** I had told him the count would keep the
        // preset's responsiveness gate green, and that was wrong.
        //
        // So the same primitive also drives branch THICKNESS, which is the channel that moves
        // ink without moving positions: together they reach **0.662** and clear the 0.5 floor.
        // The pair is deliberately ONE GESTURE — "the canopy gets denser and heavier" — which
        // is why it is not the FA #67 collision it resembles. This preset already establishes
        // that pattern in the opposite direction: `reach` drives count, trunk length AND
        // thickness precisely "so they move as one coupled gesture rather than three layers
        // racing on one primitive". Flux now does the same across two of the three.
        //
        // HELD (`fHeld`), like the spread route it replaces, and that is what makes it legal on
        // continuous geometry. This preset's structural rule is that trunk length and thickness
        // read ONLY slow signals — anything past ~1 turn/s there "reads as the tree bouncing
        // rather than growing". Raw flux is the fastest term in the vector (5.48 turns/s at
        // FTR.11), but through FTR.23's continuous glide it turns **0.21 times a second** at a
        // 1-pixel epsilon, five times inside the rule. Reading `f` here instead of `fHeld`
        // would put a 5/s signal on the tree's thickness, which is the complaint Matt has
        // already made twice.
        float fluxWeight = saturate((fHeld.spectral_flux - 0.10f) / 0.85f);
        float countF = min(7.0f + base + section + tipsF + fluxWeight * 10.0f * amp, 63.0f);
        uint  count  = min((uint)ceil(countF), 63u);

        // ── BRANCH SPREAD — STATIC (Matt, 2026-08-17, asked twice) ───────────────
        //
        // It ran off `spectral_flux` from D-212 through FTR.25. Flux was the right choice for
        // the reason recorded then: the only broadband primitive with a comparable span on
        // every source (p05→p95 0.477…0.666), and musically apt — flux rises when the spectrum
        // CHANGES, so the canopy opened on chord and texture changes rather than on loudness.
        //
        // Matt asked for it removed on 2026-08-17 to free flux for the size term. Measurement
        // then ruled flux out for size (FTR.23) and FTR.24/25 solved event marking with a
        // different primitive entirely, so the trade the instruction was making no longer
        // exists — I raised exactly that, with the cost below, and he reaffirmed. His call,
        // recorded as his call.
        //
        // ⚠ WHAT IT COSTS, MEASURED, because this is a large number and someone will wonder:
        // the drive-range response falls from **1.067 to 0.119** mean |Δpixel| p05→p95, i.e.
        // **the canopy spread was carrying ~89 % of everything this preset visibly does across
        // its own energy range.** Everything else on that axis — arousal growth, the density
        // branch count, the bass_dev tone — sums to almost nothing by comparison. That is a
        // finding about the preset, not about flux: the angle of the canopy is its loudest
        // visual channel by an order of magnitude.
        //
        // 0.44 rad ≈ 25° is the midpoint of the range flux drove (20°…34°), so the canopy keeps
        // the shape he has been reviewing and simply stops breathing with the spectrum.
        // Deliberately a CONSTANT and not a substitute route: the honest state of this layer is
        // "no primitive", and inventing one to keep a number up would be the move FTR.2 killed
        // when it deleted this preset's dead routes from the sidecar manifest.
        float spread = 0.44f;   // ≈ 25°, the midpoint of the retired flux range

        // Only geometry terms travel in the payload. The fragment stage reads its own
        // primitives straight from `f` at buffer(0), so forwarding them here would just
        // be a second, staler copy.
        payload->melody       = melody * amp;
        payload->reach        = reach;
        payload->surge        = surge;
        payload->trunk_len    = trunkLen;
        payload->spread       = spread;
        payload->canopy_weight = fluxWeight;
        payload->branch_count   = min(count, 63u);
        payload->branch_count_f = countF;
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

    // THE TRUNK ELONGATES — half of Matt's definition of "shoot up". The trunk was
    // barred from every fast signal because `bass_rel` and raw `density` made it bounce;
    // the surge is different in kind, not degree: it steps and holds (0.58 turns/s), so
    // it lengthens the trunk once at the arrival instead of sliding it constantly.
    // THE RESTING TREE IS DELIBERATELY SHORT, and that is load-bearing rather than
    // taste. At the previous sizing the tree already reached 66 % up the frame at rest,
    // so a trunk that lengthened 1.67× measured as a 1.06× height change — the growth
    // was going off-screen. A thing cannot visibly shoot up if it is already near the
    // ceiling; headroom IS the effect. Rest ≈ 40 % of frame height, surge ≈ 85 %.
    // 0.27 at rest, not 0.22: the shorter tree tripped the D-037 silence gate (mean luma
    // 0.0027 against a 0.004 floor). Headroom for the surge still matters more than size
    // at rest, so the constant is raised only as far as legibility needs.
    // FTR.10 — the expression moved to the object shader so it can be evaluated on the
    // BEAT-HELD FeatureVector: same 0.27 + reach·0.13 + surge·0.32, sampled on the beat and
    // held between beats. See the FTR.10 block there.
    float base_len = payload.trunk_len;
    float ang_base = payload.spread;                    // 20°–34°, from spectral_flux

    float2 pos     = float2(0.0f, -0.90f);  // tree root (bottom-centre, clip space)
    float2 dir     = float2(0.0f,  1.0f);   // initial direction: straight up
    float  seg_len = base_len;
    // FTR.26 — the canopy-weight half of the flux gesture. 0.026 is sized to clear the
    // preset's own drive-range floor (0.5 mean |Δpixel| p05→p95): count-only reached 0.209,
    // count plus this reaches 0.662. Thickness is the strong pixel channel because it changes
    // INK without changing any position — the property that makes it safe here and the reason
    // the branch count alone could not carry this route.
    float  thick   = 0.038f + payload.reach * 0.020f + payload.canopy_weight * 0.026f;

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

    // ── FTR.13: BRANCHES GROW IN, THEY DO NOT POP ────────────────────────────
    //
    // Matt's M7 on FTR.11 was that the canopy reads robotic and stuttering, and the measured
    // cause is that a branch count is an INTEGER: the worst single beat added 15–19 branches at
    // once on a tree spanning 43 (three captures), and holding on the BAR instead made it
    // 23–28 — slowing the clock concentrates the pop rather than removing it. His call:
    // *"grow in individually."*
    //
    // Stateless mechanism, no per-branch memory needed: the count arrives FRACTIONAL, so a
    // branch's growth is just how far the count has passed its own index. Branch 40 is absent
    // at count 40.0, half-grown at 40.5, full at 41.0 and beyond. A rise from 40 to 55 is then
    // a fifteen-branch sweep spread across the eased step instead of a block appearing, and
    // the frontier of the canopy is always the branch mid-extension.
    //
    // LENGTH ONLY, not thickness: a real branch extends from its parent joint at its own
    // gauge. Scaling thickness too would make new growth read as a fading ghost rather than a
    // shoot, and the joint is where the eye expects the motion to start.
    float grow = saturate(payload.branch_count_f - float(bid));
    seg_len *= grow * grow * (3.0f - 2.0f * grow);   // smoothstep: no kink at either end

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
    // ── ENERGY ← bass_dev: the LAYER-1 ROUTE THIS PRESET NEVER HAD (FTR.20) ──────────
    //
    // Matt's M7, 2026-08-16: *"Does not carry the energy of the music, feel blunted."*
    //
    // He is describing a missing layer, not a mistuned one. Before this the preset read
    // `arousal`, `spectral_surge`, `spectral_density`, `spectral_flux`, `section_ratio`,
    // `tonal_phase_fifths`, `beat_mid`, `pulse_amp01`, `melodic_tips` — slow spectral
    // statistics, a mood estimate and beat clocks. **Not one continuous energy band, and not one
    // deviation primitive.** CLAUDE.md's audio hierarchy calls continuous energy *the default
    // primary driver* and says visuals built on it "feel locked to the music"; this one had none.
    // Measured on his capture, the only tonal route (arousal) crosses its own median **0.11
    // times a second** and moves brightness by a 0.90…1.24 multiplier, while `bass_dev` crosses
    // **3.75 times a second** — 34x livelier — and was unused.
    //
    // SOFT-SATURATED AGAINST THE REAL DISTRIBUTION, not against 1.0. `bass_dev` reads p50 ~0.00,
    // p95 0.19, p99 0.63-0.78 and peaks at 1.5-1.7 on real music, so a linear read would clip
    // constantly (FA #73 / the deviation-range note). `d/(d+0.12)` gives p50 0.07, p95 0.61 and
    // never pins on any capture measured.
    //
    // WEIGHTED ONTO SATURATION, NOT BRIGHTNESS, and that is deliberate on two counts: saturation
    // had ZERO audio coupling (it was a pure function of depth), and a large luminance swing at
    // 3.75 crossings/s is the flash risk D-157 guards — and adjacent to the global `beat_bass`
    // flash Matt rejected twice and FTR.3 removed. Colour INTENSITY carries energy without
    // strobing; brightness takes only a small share.
    float energy = saturate(f.bass_dev / (f.bass_dev + 0.12f));

    // THE RESTING BASE COMES DOWN TO MAKE ROOM, and that is a deliberate look change rather
    // than a free win. At the old 0.96 leaf base the energy term had 0.04 of headroom and
    // clipped on 47 % of frames — inert, the DYN.1e "band Matt could not see" failure, caught by
    // measuring before shipping. Dropping the base to 0.74 buys a 0.196 span at the leaf tier
    // with 1.2 % clipping. The tree therefore rests slightly less vivid and DEEPENS with the
    // music, which is the whole point of the route.
    float sat = saturate(mix(0.33f, 0.74f, depth_norm) + energy * 0.32f);

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
    // Raised from 0.22/0.60. The resting tree is now SHORT by design (headroom for the
    // surge), so it covers ~25 % less of the frame than before — and mean-frame luma is
    // what D-037 measures. A smaller figure has to be a brighter one to stay legible.
    float val_base = mix(0.34f, 0.74f, depth_norm);
    // 0.84 floor, not 0.72. The shorter resting tree (headroom for the surge) put the
    // silence frame at mean luma 0.0034 against D-037's 0.004 — dimming it a further 28 %
    // at silence made a smaller tree invisible. The FLOOR is raised rather than the gate
    // lowered: D-037 is a legibility requirement, not a number to tune past.
    // FTR.20 — a small share of the energy reaches brightness too, so an accent reads as the
    // tree lifting rather than only deepening in colour. Kept to 0.12 so the luminance swing
    // stays well inside the flash budget: +8.6 % of luminance at p95, +11.3 % at the peak.
    float val      = val_base * (0.90f + arousal * 0.34f + energy * 0.20f);

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

    // ── FTR.25: THE EVENT ACCENT, ON LIGHT ONLY ──────────────────────────
    //
    // Matt, after FTR.24a reverted the same accent from the tree's SIZE: *"Try the colour/tip
    // flicker approach."* The measurement that sent it here is worth restating, because it is
    // what makes this a different mechanism rather than another pass at the same one:
    //
    //   FTR.24 put `spectral_level_rise` on SIZE. Marking 0.8–1.5 events/s multiplied the
    //   tree's peak velocity 10.7× (*"herky-jerky … looks defective"*), and every calmer
    //   setting scored BELOW CHANCE on event alignment. On a scale property the two goals are
    //   anti-correlated, because scale is what every other element is drawn relative to.
    //
    // Brightness has no such coupling: nothing is positioned relative to it, so an 80 ms lift
    // costs exactly ZERO peak velocity. That is not an argument, it is a property of the
    // pipeline — this term is in the fragment stage, downstream of every vertex, and
    // `FractalTreeMeshRenderTest` asserts the canopy WIDTH is unchanged between accent 0 and 1
    // while the luma moves. If that assertion ever fails, this term has leaked into geometry.
    //
    // WEIGHTED TO THE TIPS, `depth_norm²`, WHICH IS THE LOAD-BEARING PART. A GLOBAL flash was
    // already tried and removed at FTR.3: it lifts every pixel, so no individual branch can
    // read against it (D-157), and Matt has twice asked for less beat-driven activity. Squared
    // depth leaves the trunk and inner branches untouched — the frame's mean luminance barely
    // moves while the canopy edge flickers, which is both the safe form and the legible one.
    //
    // Floret is the counter-case to check this against: its drum sparkle was REMOVED because
    // bright points camouflage into a bright field. This canopy is sparse and dark, which is
    // the condition where points DO read — the opposite regime, and the reason the same idea
    // is worth trying here after failing there.
    //
    // BRIGHTER AND WHITER TOGETHER — one gesture, which is why this does not break FA #67
    // even though `sat` already carries `energy`. A spark is not "a brightness change plus a
    // saturation change"; desaturating toward white IS how a small bright thing reads as a
    // spark rather than as a slightly lighter leaf. Measured, brightness alone was not enough:
    // on an identical frame it moved the lit pixels +5 % and the brightest tips 0.739 → 0.809,
    // which is at the threshold of visibility, and no gain fixed it — `depth²` weighting held
    // the whole-frame effect to +6 % even at gain 1.20. Adding the desaturation doubles the
    // pixel delta (0.079 → 0.166 mean |Δpixel|) for the same flash budget.
    //
    // WEIGHTED LINEARLY IN DEPTH, not squared. Squared was the first cut and it attenuated the
    // mid-canopy — where most lit pixels actually are — to nothing. Linear still leaves the
    // trunk at exactly zero (`depth_norm` is 0 there), which is the property that matters: this
    // is not a frame lift.
    //
    // Sized against the flash budget the FTR.20 comment above measures itself against: mean
    // frame luminance +10.6 % at FULL accent, and full accent is a 0.20 s transient at
    // ~0.4 events/s, so nothing sustains. The brightest tips go 0.739 → 0.903 and no pixel
    // clips. `FractalTreeMeshRenderTest` gates all three: geometry unchanged, lit pixels
    // visibly brighter, frame lift bounded.
    //
    // `spectral_level_rise` is rate-invariant as of BUG-089 — the defect that made FTR.24
    // behave differently on Matt's playback path than on the capture it was tuned against. On
    // both paths it now fires ~0.40 times a second, on events rather than between them.
    float landed = saturate(f.spectral_level_rise);
    float spark  = landed * depth_norm;
    val += spark * 0.55f;
    sat  = saturate(sat - spark * 0.45f);
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
