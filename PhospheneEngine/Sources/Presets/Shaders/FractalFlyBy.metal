// FractalFlyBy.metal — FD.1 maquette: Mandelbox distance estimator + a
// self-similar scale traversal, rendered through the shared ray_march G-buffer path.
//
// CONCEPT — REFRAMED TO A FLY-THROUGH (Matt, 2026-07-23, after the 3rd live M7).
// An endless cinematic FLIGHT THROUGH an enclosed Mandelbox cathedral-world:
// travelling between and past towering recursive architecture, corridors opening
// into further corridors. The identity trait is the sensation of unending
// TRAVEL through an infinite, self-elaborating fractal interior.
//
// The original concept was a FALL *into* the fractal. Three live tests said the
// mechanic does not deliver that: a scale traversal converges on a fixed target, so
// it reads as approaching a place, not dropping through a world. Matt's call was
// to stop fighting the geometry and adopt what it is genuinely good at — which is
// also what the cited reference (Horsthuis) actually does: he flies through these
// structures, he does not drop down them. The mechanic is unchanged; the target
// moved to match it.
//
// ENCLOSED (Matt's pick): `scene_backdrop: "dark"` renders miss rays as a
// near-black void, so openings read as darkness receding rather than an exit to a
// sky. The gallery IBL env still supplies ambient + reflections — backdrop and
// environment are deliberately decoupled.
//
// REFERENCES (docs/VISUAL_REFERENCES/fractal_fly_by/, inherited by the
// FD supersession of PG.3):
//   01_macro_fan_vault.jpg  (HERO) — cathedral-scale chambers/ribs, the macro read
//   02_meso_muqarnas.jpg           — nested self-similar cells (meso, 2nd iteration)
//   03_micro_geode.jpg             — micro sub-chambers + crystalline character
//   06_palette_stained_glass_light.jpg — jewel palette / mood-tinted IBL target
// Anti-reference: a flat 2D Mandelbrot-zoom look (no 3D depth or lighting), and
// over-iterated mush with no readable architecture.
//
// THE DISTANCE ESTIMATOR IS PORTED, NOT DERIVED (FA #73). Source: Syntopia's
// Fragmentarium, Examples/Historical 3D Fractals/Mandelbox.frag — the
// Rrrola (Jan Kadlec) optimised form of Tom Lowe's Mandelbox. The box fold,
// sphere fold, the `p.w` running-derivative and the final distance expression
// are reproduced verbatim; only the syntax is MSL and the orbit trap is
// unconditional (Fragmentarium gates it on ColorIterations).
//
// AUDIO (FD.1, both heroes wired):
//   HERO #1 — TRAVEL SPEED follows the music's ENERGY, via accumulatedAudioTime
//     (sceneParamsA.x, the engine's running sum of energy x dt): fast when loud,
//     a near-stationary drift in silence (§A5), monotonic, zero CPU state. It is
//     the animation time base, not a declared audio_route (VolumetricLithograph
//     precedent — the QG.1 fixtures don't carry it; QG.1.1 boundary).
//   HERO #2 — fold-open on the bass swell, via f.bass_att_rel (D-026 deviation
//     primitive, soft-saturated) widening the box-fold LIMIT so the chamber
//     unfolds into a bigger one. Only the box-fold clamp bound moves — no scale
//     constant recompute, no per-pixel pow.
// The camera is STATIC (cameraDollySpeed defaults 0), so the travel is purely the
// in-shader scale-zoom; no collision with the preset-agnostic camera dolly.
// FD.2 = look pass (materials, thin-film, god-rays, fog, jewel palette); FD.3 =
// secondary audio + structural-boundary tuning + cert. Palette here is a single
// maquette material (monochrome-ish orbit-trap gold) — the jewel HDR is FD.2.

#include <metal_stdlib>
using namespace metal;

// MARK: - Mandelbox parameters

// Scale 2.7 sits in the "navigable architecture" band (2.0-3.0); Scale 3.0 is
// the perfect-Menger degenerate case and reads as rigid boxes, Scale < 2 closes
// the interior corridors the fly-through needs. MinRad2 0.25 is the Fragmentarium
// default across essentially every published Mandelbox preset.
constant float FFB_SCALE    = 2.7f;
constant float FFB_MIN_RAD2 = 0.25f;

// Iteration cap. NOT animated, ever — the fold morph is the continuous fold-limit
// parameter (an integer count change pops the whole structure in one frame).
// Locked at 8 (RMPERF.1 budget): the FD.1 contact sheets showed cap 8 is visually
// near-identical to cap 10 (full recursive architecture) while cap 6 collapses the
// self-elaboration; cap 8 + the RMPERF.1 preamble fits Tier-2 with headroom.
constant int   FFB_ITERS    = 8;

// Fold-open (HERO #2): the bass swell widens the box-fold limit, opening the
// current chamber into a larger one — the "breakthrough" on the drop. Kept in a
// narrow band around the canonical 1.0 so the distance estimate stays valid (no
// holes); driven by f.bass_att_rel in sceneSDF. Only the box-fold clamp bound
// moves — the sphere fold, scale, and all precomputed scale constants are
// untouched, so this costs one extra clamp bound per iteration, no per-pixel pow.
constant float FFB_FOLD_BASE  = 1.0f;
constant float FFB_FOLD_RANGE = 0.18f;   // sweep-validated Lipschitz-safe interval

// Motion-coherence detail fade (§A8 / BUG-071). World-space distances from the
// camera between which the high-frequency material response rolls off, so far
// sub-pixel fractal detail stops aliasing into shimmer under travel. Tuned
// against the camera at z=-2.9 with the fractal spanning roughly 1–6 units out.
constant float FFB_DETAIL_NEAR = 2.2f;
constant float FFB_DETAIL_FAR  = 6.5f;

// Travel rate: phase per unit accumulatedAudioTime (BUG-071). 0.12 gave <1
// octave in a 78 s session — the motion was barely perceptible. accumulatedAudioTime
// advances ~0.1/s on a loud track, so 0.45 ≈ one self-similar octave per ~22 s.
// Shared by ffb_travelPhase and scenePrevPosition — they MUST agree or the motion
// vectors point at the wrong place and MetalFX smears.
constant float FFB_TRAVEL_RATE = 0.45f;

// Vertical radians per rendered pixel: 2·tan(fov/2) / renderHeight, with
// fov 48° and renderHeight = 1080 × render_scale 0.65 ≈ 702. Sets the fractal
// LOD cutoff (see ffb_invFootprint).
constant float FFB_RADIANS_PER_PIXEL = 0.00127f;

// Thin-film iridescent fold rims. DISABLED at BUG-071 round 5: the effect is
// view-dependent colour, i.e. high-frequency chroma BY CONSTRUCTION, on exactly
// the thin ridge geometry that already aliases worst. It is a "strongly
// preferred", not mandatory, trait — correctness first. Re-enable only after
// verifying a phase-0 frame stays speckle-free.
constant bool FFB_THINFILM_ENABLED = false;

// Rrrola's precomputed constants (Fragmentarium `init()`): folding the
// /MinRad2 into the scale vector is what makes the sphere fold a single
// clamp(max(...)) with no branch.
//
// These live in function scope, not the `constant` address space: MSL requires
// `constant` initializers to be compile-time constant expressions, and fabs()/
// pow() calls do not qualify (the shader silently fails to compile and the
// preset is dropped — Failed Approach #44). As locals over literal inputs the
// compiler folds them anyway, so there is no per-invocation cost.
#define FFB_SCALE_VEC      (float4(FFB_SCALE, FFB_SCALE, FFB_SCALE, fabs(FFB_SCALE)) / FFB_MIN_RAD2)
#define FFB_ABS_SCALE_M1   (fabs(FFB_SCALE - 1.0f))
#define FFB_ABS_SCALE_POW  (pow(fabs(FFB_SCALE), float(1 - FFB_ITERS)))

// MARK: - Distance estimator (ported — see header)

/// Rrrola-optimised Mandelbox distance estimator. `orbitTrap` returns the
/// per-axis closest approach across the iteration, which is what makes the
/// colour follow the geometry rather than sit on it as a flat ramp (§A2
/// "the single biggest look lever").
/// `invFootprint` = 1 / (world-space size of one pixel at this sample), in the
/// DE's own space. The Rrrola derivative `p.w` is how much the fold has
/// magnified space by iteration i, so a feature created at iteration i has size
/// ~1/p.w. Once that drops below a pixel the iteration is producing detail the
/// frame CANNOT resolve — it only aliases. Stopping there is standard fractal
/// LOD (the cone-trace/mip idea applied to a distance estimator): full detail up
/// close, progressively fewer folds with distance, and — critically — a bounded
/// on-screen detail density instead of one that explodes at the wide end of the
/// zoom cycle (BUG-071 round 4: playback STARTS at zoom=1, the most
/// detail-crammed point, which is why the opening frames were a garbled mess).
static inline float ffb_mandelboxDE(float3 pos, float foldLimit, float invFootprint,
                                    thread float4& orbitTrap, thread float& trapLevel) {
    float4 p  = float4(pos, 1.0f);
    float4 p0 = p;
    orbitTrap = float4(1e10f);
    trapLevel = 0.0f;          // recursion level of the closest approach

    for (int i = 0; i < FFB_ITERS; i++) {
        if (p.w > invFootprint) { break; }   // finer than a pixel — stop (LOD)
        p.xyz = clamp(p.xyz, -foldLimit, foldLimit) * 2.0f - p.xyz; // box fold (HERO #2)
        float r2 = dot(p.xyz, p.xyz);
        // Record the LEVEL at which the orbit came closest. This is the surface's
        // recursion depth — piecewise-constant over large patches of structure, so
        // it drives bold colour BLOCKING (whole folds sharing a hue) instead of the
        // per-pixel hue thrash that made the trap-driven palette speckle.
        // INTEGER level, deliberately. A fractional blend was tried to soften the
        // block boundaries and made things worse: `r2` varies per pixel, so the
        // fractional part reinstated exactly the per-pixel hue variation the
        // blocking exists to remove. The boundaries between colour blocks are real
        // structural edges (fold generations), not noise.
        if (r2 < orbitTrap.w) { trapLevel = float(i); }
        orbitTrap = min(orbitTrap, fabs(float4(p.xyz, r2)));
        p *= clamp(max(FFB_MIN_RAD2 / r2, FFB_MIN_RAD2), 0.0f, 1.0f); // sphere fold
        p  = p * FFB_SCALE_VEC + p0;
        if (r2 > 1000.0f) { break; }
    }
    return (length(p.xyz) - FFB_ABS_SCALE_M1) / p.w - FFB_ABS_SCALE_POW;
}

/// World-space size of one pixel at `p`, expressed in the DE's space.
///
/// footprint_p = distance-from-camera × radians-per-pixel; the DE samples
/// q = (p + c)/zoom, so a p-space length maps to q-space by dividing by zoom.
/// The per-pixel angle uses the preset's fov and its RENDER height (display
/// height × render_scale) — a constant here rather than a new uniform lane
/// (lightingParams is full); it only sets the LOD threshold, so a modest
/// mismatch on a differently-sized display shifts the cutoff slightly and
/// nothing more.
static inline float ffb_invFootprint(float3 p, constant SceneUniforms& s, float zoom) {
    float dist = max(length(p - s.cameraOriginAndFov.xyz), 1e-4f);
    // cameraRight.w = real radians per rendered pixel (FLY.5). Falls back to the
    // 1080p constant only if the engine hasn't published it.
    float radPerPx = (s.cameraRight.w > 1e-7f) ? s.cameraRight.w : FFB_RADIANS_PER_PIXEL;
    float footprintP = dist * radPerPx;
    float footprintQ = max(footprintP / max(zoom, 1e-4f), 1e-6f);
    return 1.0f / footprintQ;
}

// MARK: - Travel

/// The travel is a *scale* traversal, not a translation.
///
/// A Mandelbox is a bounded object, so translating a camera downward through it
/// necessarily exits it — there is no infinite corridor to fall down. What the
/// object does have is self-similarity under scaling by |Scale|: the structure
/// at zoom z and at zoom z*|Scale| are the same structure. So driving
/// zoom = |Scale|^fract(phase) sweeps one full octave of the fractal.
///
/// DIRECTION (BUG-071): to travel INTO the world, features must GROW/rush past as
/// the phase advances. That means sampling `(p + c) / zoom` (magnify a shrinking
/// neighbourhood) with zoom increasing — NOT `(p + c) * zoom`, which collapses
/// every feature toward a vanishing point (a recede; the live M7 "camera moving
/// out"). The DE distance is then DE(q) * zoom (dp = zoom·dq).
static inline float ffb_travelZoom(float phase) {
    return pow(fabs(FFB_SCALE), fract(phase));
}

/// Off-axis viewing offset, applied in camera space so it rides the scale (the
/// self-similar octave wrap stays seamless). A pure on-axis traversal rams the
/// Mandelbox's central sphere dead-centre; this views it off to the side, down a
/// corridor, so it reads as travelling past structure rather than into a disc.
constant float3 FFB_TRAVEL_OFFSET = float3(0.30f, 0.16f, 0.0f);

/// Point in FRACTAL space the traversal moves toward (BUG-071, second finding).
///
/// A scale traversal converges on whatever point stays fixed as zoom grows. The
/// naive `(p+c)/zoom` converges on the fractal's ORIGIN — which for a Mandelbox
/// is the smooth box/sphere core with no detail at small scales, so the travel runs
/// out of structure and presses against a featureless wall. A true endless fall
/// must target a point on the fractal's BOUNDARY, where folded detail persists at
/// every scale (the same reason a Mandelbrot zoom targets a boundary point, never
/// the middle of the cardioid).
constant float3 FFB_ZOOM_TARGET = float3(0.92f, 0.64f, 0.42f);

/// Forward-travel sample map (BUG-071): the neighbourhood around FFB_ZOOM_TARGET shrinks
/// as zoom grows, so that boundary detail magnifies and rushes past.
/// `ffb_mandelboxDE(q,…) * zoom` restores the p-space distance.
static inline float3 ffb_travelSample(float3 p, float zoom) {
    return FFB_ZOOM_TARGET + (p + FFB_TRAVEL_OFFSET) / zoom;
}

// MARK: - Audio → travel + fold (HERO routing)

/// HERO #1 — travel speed follows the music's ENERGY. `accumulatedAudioTime`
/// (sceneParamsA.x) is the engine's running sum of energy × dt: it advances fast
/// when loud and crawls when quiet, so the flight speeds up on peaks and slows to a
/// near-stationary drift in silence (§A5) — for free, monotonic (never reverses),
/// with zero CPU state. This IS the arousal→velocity hero, driven off the more
/// literal energy envelope rather than the mood axis.
static inline float ffb_travelPhase(constant SceneUniforms& s) {
    return s.sceneParamsA.x * FFB_TRAVEL_RATE;
}

/// HERO #2 — the fold opens on a bass swell. `bass_att_rel` is the D-026
/// deviation primitive (never an absolute threshold on the AGC value, FA #31);
/// it spikes to ~3× on real music, so soft-saturate it into [0,1] and widen the
/// box-fold limit within the Lipschitz-safe band. A larger limit unfolds the
/// current chamber into a bigger one — the "breakthrough" on the drop.
static inline float ffb_foldLimit(constant FeatureVector& f) {
    float swell = 1.0f - exp(-max(0.0f, f.bass_att_rel) * 1.6f);   // soft-saturate → [0,1)
    return FFB_FOLD_BASE + FFB_FOLD_RANGE * swell;
}

// MARK: - Scene SDF

float sceneSDF(float3 p,
               constant FeatureVector& f,
               constant SceneUniforms& s,
               constant StemFeatures& stems,
               texture2d<float> ferrofluidHeight) {
    (void)stems;
    (void)ferrofluidHeight;   // slot-10; Ferrofluid Ocean only.

    float phase = ffb_travelPhase(s);
    float zoom  = ffb_travelZoom(phase);               // HERO #1 (energy → speed)
    float3 q    = ffb_travelSample(p, zoom);           // off-axis, wrap-preserving
    // A bounding-sphere early-out was tried here and REMOVED: measured at
    // iteration caps 8 and 10 across enclosed and open compositions it changed
    // nothing (8.19 vs 8.01 ms p95), because the cost is not missed rays creeping
    // to the far plane — it is grazing rays crawling near the surface, which an
    // open composition has more of. Do not re-add it without a measurement.
    float4 trap;
    float lvl;
    return ffb_mandelboxDE(q, ffb_foldLimit(f), ffb_invFootprint(p, s, zoom), trap, lvl) * zoom;   // HERO #2 (bass → fold)
}

// MARK: - MetalFX motion vectors (MFX.1)

/// Where the surface point at `worldPos` was one frame ago.
///
/// This is what makes temporal AA safe for this preset: the traversal is an
/// analytic similarity transform, so the previous-frame position is a CLOSED
/// FORM rather than an estimate. A fractal feature sits at a fixed point `q` in
/// fractal space; the sample map is `q = T + (p + c)/zoom`, so inverting for the
/// previous frame's zoom gives
///
///     p_prev = (p + c) · (zoom_prev / zoom) − c
///
/// Only the zoom differs between frames (the camera is static and the fold morph
/// is a slow continuous deformation MetalFX's rejection handles), so the ratio is
/// the entire motion. `lightingParams.z` carries the previous frame's
/// accumulated audio time — see RenderPipeline+RayMarch.
float3 scenePrevPosition(float3 worldPos,
                         constant FeatureVector& f,
                         constant SceneUniforms& s,
                         constant StemFeatures& stems) {
    (void)f;
    (void)stems;
    float zoomNow  = ffb_travelZoom(ffb_travelPhase(s));
    float zoomPrev = ffb_travelZoom(s.lightingParams.z * FFB_TRAVEL_RATE);
    float ratio    = (zoomNow > 1e-6f) ? (zoomPrev / zoomNow) : 1.0f;
    return (worldPos + FFB_TRAVEL_OFFSET) * ratio - FFB_TRAVEL_OFFSET;
}

// MARK: - Jewel palette (FD.2 look pass)

/// Backlit-stained-glass jewel range (ref 06_palette_stained_glass_light.jpg:
/// cobalt / teal / emerald / amber / crimson against black). IQ cosine palette —
/// the biggest look lever over the FD.1 monochrome-gold maquette. Deliberately
/// LESS than a full hue cycle (freq 0.85, not 1.0) so neighbouring folds read as
/// related cathedral jewels rather than a garish full-rainbow wash; driven by the
/// orbit trap so colour tracks depth into the structure, like leadlight cells.
static inline float3 ffb_jewel(float t) {
    return palette(t,
                   // BUG-071 round 5: the floor MUST stay above zero. This was
                   // 0.50 ± 0.55, i.e. a range of [-0.05, 1.05] — a large part of
                   // the palette clamped to BLACK. With a fast hue that was hidden
                   // (every region averaged bright+dark); once the hue slowed to
                   // track structure, whole regions landed on the dark phase and
                   // went dead black — the "super dark" live report. 0.58 ± 0.30
                   // spans [0.28, 0.88]: saturated, never black.
                   float3(0.52f, 0.50f, 0.56f),   // midtone — floor stays lit
                   float3(0.46f, 0.46f, 0.46f),   // amplitude — saturation without black
                   float3(0.85f, 0.85f, 0.85f),   // < one hue cycle → cohesive range
                   float3(0.00f, 0.33f, 0.67f));  // phase → cobalt→teal→amber→crimson
}

// MARK: - Scene Material

void sceneMaterial(float3 p,
                   int matID,
                   constant FeatureVector& f,
                   constant SceneUniforms& s,
                   constant StemFeatures& stems,
                   thread float3& albedo,
                   thread float& roughness,
                   thread float& metallic,
                   thread int& outMatID,
                   constant LumenPatternState& lumen) {
    (void)matID;
    (void)stems;
    (void)lumen;      // slot-8; Lumen Mosaic only.

    // The orbit trap is recomputed here because sceneSDF and sceneMaterial are
    // separate entry points off the shared preamble with no channel between
    // them (VolumetricLithograph duplicates its kickPulse for the same reason).
    // Travel phase + fold limit MUST match sceneSDF exactly or the colour
    // detaches from the geometry.
    float phase = ffb_travelPhase(s);
    float zoom  = ffb_travelZoom(phase);
    float3 q    = ffb_travelSample(p, zoom);
    float4 trap;
    float trapLevel;
    ffb_mandelboxDE(q, ffb_foldLimit(f), ffb_invFootprint(p, s, zoom), trap, trapLevel);

    // Jewel hue follows depth into the structure (trap.w = closest approach to the
    // origin sphere), the same driver that varied cleanly in FD.1 — plus a small
    // per-fold offset so adjacent cells differ without the whole frame going one
    // colour (the v1 over-saturation failure).
    // NO fract() here (BUG-071 round 2 — the visible "glitchy" rainbow fringing).
    // `palette()` is a cosine, already periodic AND continuous in t. Pre-wrapping
    // with fract() introduced a hard hue discontinuity at every integer crossing
    // (the cycle frequency is 0.85, so the wrap does NOT line up), which on dense
    // fractal detail put a rainbow contour seam on every surface and edge — and a
    // discontinuity is infinite-frequency, so it aliased and shimmered by
    // construction. Feeding t straight in is smooth everywhere.
    // HUE DRIVER — smooth-and-wide, not fast-and-narrow (BUG-071 round 7).
    //
    // Two failures bracket this. Driving hue FAST off the orbit trap cycles the
    // palette several times within a few pixels: neighbouring pixels get
    // unrelated hues and the frame fills with rainbow speckle no AA can fix.
    // Driving it SLOW off the trap fixes the speckle but confines the whole
    // frame to a narrow arc of the wheel — every surface an adjacent hue, which
    // is exactly the muddy, un-psychedelic look Matt reported.
    //
    // The resolution: get the WIDE hue span from quantities that vary smoothly
    // and at LARGE scale, so distant parts of the frame land on genuinely
    // different (even complementary) hues while neighbouring pixels stay close.
    //   * viewDist  — a depth gradient: near and far read as different colours,
    //                 which also gives the depth cue the flat mud was missing.
    //   * phase     — the travel phase, identical for every pixel, so the whole
    //                 world cycles slowly through the wheel as you fly.
    //   * trap      — a small structural term so folds still tint apart.
    // RECURSION LEVEL is the primary hue driver. Depth was tried and failed: on a
    // wall-facing view every pixel sits at nearly the same distance, so the frame
    // collapsed to one hue (the magenta-monochrome round). Level varies with
    // STRUCTURE — each fold generation gets its own hue — so the frame carries
    // several distinct, widely-separated colours at once (the complementary
    // contrast that reads as psychedelic) while neighbouring pixels on the same
    // fold stay the same colour (no speckle).
    float hue = trapLevel * 0.155f          // fold generation → bold colour blocks
              + phase * 0.42f               // slow global cycling as you travel
              + trap.w * 0.08f;             // gentle within-fold variation
    float3 jewel = ffb_jewel(hue);

    // ── Motion-coherence detail fade (§A8; BUG-071) ──────────────────────────
    // A Mandelbox has unbounded fine detail. Beyond ~a pixel of footprint it
    // cannot be resolved, so at distance it ALIASES into shimmer under travel
    // (the live "deeply glitchy / pixelated"). There is no temporal AA here
    // (MetalFX is unwired), so the mitigation is to stop *producing* detail the
    // frame cannot hold: with distance, roll the high-frequency material response
    // off toward a smooth, rougher, less-metallic surface. `detail` = 1 near,
    // → 0 far. Cheap (one length + smoothstep), and it is what keeps the flight
    // legible instead of boiling.
    float viewDist = length(p - s.cameraOriginAndFov.xyz);
    float detail   = 1.0f - smoothstep(FFB_DETAIL_NEAR, FFB_DETAIL_FAR, viewDist);

    // ── Three materials via matID, dispatched by orbit-trap REGION (§A2 detail
    //    cascade / ≥3 materials). The SHADED jewelled stone (matID 0) is dominant
    //    so the 3D form/AO/depth from FD.1 is preserved; thin-film iridescence
    //    rides the fold ridges; only the DEEPEST recesses self-illuminate (a glow
    //    accent, not a flood — v1 flooded emission and read flat). ──
    float cavity = 1.0f - smoothstep(0.0f, 0.045f, trap.w);  // deepest tiny pockets only
    float ridge  = 1.0f - smoothstep(0.0f, 0.03f, trap.y);   // 1 = right on a fold plane

    if (cavity > 0.85f) {
        // matID 1 — emission-dominated: the deep recesses glow like backlit glass
        // out of the dark (feeds the bloom bright-pass). Threshold kept TIGHT so a
        // large smooth face (e.g. the central sphere) can never go fully emissive
        // and flash the frame bright (D-157 flash safety).
        outMatID  = 1;
        // Vary the emissive hue across cavities (deep-cavity trap.w clusters near
        // one colour → uniform-blue polka-dots) so the recesses read as DIFFERENT
        // coloured votives — the stained-glass mix, not one blue repeated.
        // Slowed to match the surface hue (BUG-071 round 5). This site was left
        // at 3.1/2.0 — FASTER than the 1.3 that caused the speckle — so the deep
        // recesses kept rainbow-speckling after round 4 fixed only the surface.
        float3 glow = ffb_jewel(trap.z * 0.35f + trap.x * 0.20f + 0.4f);
        albedo    = glow * (0.62f + 0.35f * cavity);         // brighter votives (tiny pockets → flash-safe)
        roughness = 0.5f;
        metallic  = 0.0f;
    } else if (FFB_THINFILM_ENABLED && ridge > 0.75f && detail > 0.55f) {
        // matID 3 — metallic thin-film: iridescent shimmer on the fold edges
        // (§A2 "thin-film on fold edges" — the psychedelic signature).
        // BUG-071: the view-dependent iridescence is the single worst aliasing
        // source under travel (rainbow rims on every sub-pixel edge). Confined
        // to NEAR ridges only (`detail > 0.55`) and a tighter ridge band, so it
        // reads as a highlight on close structure instead of frame-wide rainbow
        // noise; roughened further to widen the highlight lobe.
        outMatID  = 3;
        albedo    = mix(float3(0.02f), jewel * 0.30f, 0.5f); // dark metal base under the film
        roughness = 0.52f;                                   // wider lobe → less sparkle aliasing
        metallic  = 0.75f;
    } else {
        // matID 0 — polished jewelled stone (chrome/marble ref 04/08): the
        // DOMINANT, shaded material that carries depth. Saturated, brighter than
        // FD.1's near-black, but still lit by Cook-Torrance so form reads.
        // BUG-071: roll roughness up and metallic down with distance — sharp
        // specular on sub-pixel far detail is what boils under motion.
        outMatID  = 0;
        albedo    = jewel * 1.15f;                            // brighter, more saturated stone
        roughness = mix(0.22f, 0.55f, clamp(trap.x * 2.0f, 0.0f, 1.0f));
        // Partial roll-off only: pushing far surfaces to fully rough + non-metallic
        // killed the shimmer but washed them to a pale grey crust under the key +
        // fill. Keep enough specular character to stay jewelled, enough roll-off to
        // stop the sub-pixel sparkle.
        roughness = mix(0.62f, roughness, detail);
        metallic  = 0.42f * mix(0.55f, 1.0f, detail);
    }
}
