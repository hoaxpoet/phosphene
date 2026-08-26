// FerrofluidOcean.metal — V.9 Session 1–4.5 layered authoring.
//
// Macro layer of the V.9 redirect (D-124): a fixed-camera, ocean-portion-scale
// view of a body of liquid whose surface is replaced by ferrofluid material.
// Gerstner swell drives macro body motion (audible up/down/back/forth even at
// silence); Rosensweig spike-field rides on top, emerging from the swell when
// `stems.bass_energy_dev > 0` and collapsing entirely at silence.
//
// Session 1 implemented:
//   1. Gerstner-wave macro displacement field (4 superposed waves; arousal-baseline
//      + drums_energy_dev accent amplitude).
//   2. Rosensweig hex-tile spike-field SDF per SHADER_CRAFT §4.6 (bass_energy_dev
//      → spike height).
//   3. Composition: spike field rides on top of Gerstner base height.
//   4. Placeholder sceneMaterial (matID == 0, single-light Cook-Torrance path).
//
// Session 2–3 added: material (mat_ferrofluid + thinfilm_rgb), §5.8 stage-rig
// lighting (D-125: slot-9 buffer + matID == 2 dispatch).
//
// Session 4 added three material detail layers (Cassie-Baxter droplets, meso
// domain warp, matID == 2 micro-normal). Session 4 M7 review (2026-05-13)
// rejected all three as decoration without load-bearing musical role per
// Failed Approach #62. Session 4.5 Phase 0 (this revision) reverts all three;
// the surface returns to pure-mirror substrate with Gerstner swell + Rosensweig
// spikes only. The matID == 2 thin-film thickness modulation from Session 4
// Phase B is preserved (subtle, in-vision, was not flagged at M7).
//
// Sessions 5 adds: final tuning + M7 cert review + golden-hash regen.
//
// Pipeline: ray_march → post_process. The ray_march preamble forward-declares
// `sceneSDF` and `sceneMaterial` and the renderer's `raymarch_gbuffer_fragment`
// drives them. No custom fragment function here.
//
// Audio data hierarchy compliance (CLAUDE.md):
//   - Continuous: Gerstner swell amplitude (arousal) is the slow PRIMARY body.
//   - Beat:       Rosensweig spike height punches on the steady first-note-
//                 anchored, cached-tempo beat pulse (pulse_phase01/pulse_amp01,
//                 FBS Stage 1 / D-153). Grid-PHASE-locked timing — allowed per
//                 the hierarchy; NOT Layer-4 onset pulses (beat_bass etc. are
//                 never consumed here — they fire ~97 % of frames, BUG-038).
//   - One primitive per layer (FA #67): swell×arousal (slow), spikes×pulse
//                 (per-beat), aurora×drums_energy_dev_smoothed (hit envelope).
//   - No absolute-threshold patterns on raw f.bass / stems.bass_energy (D-026).

// MARK: - Constants

constant float FO_TWO_PI = 6.28318530718;

// Crossfade threshold for D-019 silence fallback (FeatureVector proxy → stem
// routing transition). totalStemEnergy < 0.02 → fully on proxies; > 0.06 → fully
// on stems.
constant float FO_STEM_WARMUP_LO = 0.02;
constant float FO_STEM_WARMUP_HI = 0.06;

// MARK: - Audio routing helpers

// D-019 crossfade: proxy ↔ stem.
static inline float fo_stem_warmup_blend(constant StemFeatures& stems) {
    float total = stems.vocals_energy + stems.drums_energy
                + stems.bass_energy   + stems.other_energy;
    return smoothstep(FO_STEM_WARMUP_LO, FO_STEM_WARMUP_HI, total);
}

// Spike-field strength: constant baseline + bass-deviation modulation.
//
// **Round 65 (2026-05-18) — reactivated.** Matt's 2026-05-18T13-37-57Z
// review identified that the per-beat reactivity Matt was reading as
// "off" was actually the SWELL responding to drums, not the spikes. With
// round 65 removing the drums coupling from `fo_swell_scale`, the
// substrate becomes a slow atmospheric layer — and the per-beat motion
// previously carried by the swell moves to the spike heights. The
// "competing motions" problem from rounds 60/61 was about the swell and
// spikes BOTH being beat-reactive at similar magnitudes; with only the
// spikes carrying the beat now, there's no competition.
//
// Formula: round-60's continuous form, `1.0 + 0.35 × clamp(bass_dev, 0, 1)`.
//
// At silence (`bass_energy_dev = 0`): returns 1.0 → full constant lattice.
// At typical music peak (`bass_dev` ~0.5): returns 1.175 → 17.5 % taller.
// At strong transient (`bass_dev` ≥ 1.0): returns 1.35 → 35 % taller.
//
// **Earlier history (preserved for the lessons):** Rounds 56/60/61 each
// tried audio-coupled spike heights while the swell was ALSO beat-
// reactive; results read as "competing" or "artifact." Round 63 reverted
// to pure constant 1.0. Round 65 reactivates with the swell drums-
// coupling REMOVED so there's no competing motion. This is the correct
// pairing: slow swell + bass-reactive spikes, instead of bass-reactive
// swell + constant or beat-locked spikes.
// CSP.3 (2026-05-27) — Ferrofluid Ocean spike-height cold-start fix.
//
// Three corrections relative to CSP.2 (which was reverted after Matt's M7):
//
// 1. CROSSFADE TIMING — extended to 0.5 → 14 s (was 0.5 → 8 s in CSP.2).
//    The session diagnostic at 2026-05-27T15-18-55Z showed live per-frame
//    stem analysis arrives at ~13–15 s in real sessions, not the 5–8 s
//    CSP.2 assumed. Extending the window so the crossfade hands off
//    *to* live stems, not *before* them, removes the visible transition
//    at ~15 s that Matt observed as "rhythm and sync fall apart."
//
// 2. COLD-START PROXY — `features.bass_att` (smoothed continuous bass),
//    not `features.bass_dev` (deviation primitive). The deviation primitive
//    fires only above the AGC average — on typical music with AGC bass
//    clustering in [0.1, 0.3], `bass_dev ≈ 0` for ~99 % of frames, so it
//    delivered no per-frame motion. `bass_att` is continuous and varies
//    with the bass content of the live mix; matches the SHAPE of what
//    the warm-state isolated stem signal does.
//
// 3. ONE-SIDED BASELINE — cached proportion *above* 0.25 boosts the
//    spike baseline up to +25 %; *below* 0.25 leaves the baseline at 1.0
//    (no penalty). CSP.2's symmetric formula gave sub-default baselines
//    on sparse-bass tracks (Royals → "inert and broken"). The one-sided
//    form means bass-heavy tracks get visibly more posture, sparse
//    tracks look exactly like today.
//
// Per-frame coefficient (0.35) preserved verbatim from pre-CSP behaviour.
//
// **Toggle off-path.** When `MIRPipeline.ffoColdStartFixEnabled` is false:
// the app layer writes `track_elapsed_s = 100.0` AND `cached_bass_proportion
// = 0.15` (the pivot), collapsing the Layer-1 BASELINE boost to 0. Since FBS
// Stage 1 (D-153) the Layer-2 per-frame source is the beat pulse in BOTH
// toggle arms — the toggle no longer restores the historical `f.bass` spike
// drive (that term was the "frozen spikes" root cause and is retired).
// A/B verifiable from `features.csv` trailing columns (`track_elapsed_s`,
// `cached_bass_proportion`, `pulse_phase01`, `pulse_amp01`).

constant float FO_SPIKE_COLD_START_FADE_START_S = 0.5;
constant float FO_SPIKE_COLD_START_FADE_END_S   = 14.0;
// CSP.3.1 (2026-05-27): pivot lowered from 0.25 → 0.15. Session
// 2026-05-27T19-38-32Z measured Get Lucky's cached_bass_proportion at
// 0.248 and Superstition's at 0.176 — both at-or-below the original 0.25
// pivot, so Layer 1 contributed zero on the tracks Matt actually plays.
// Lowering to 0.15 puts both above the threshold (Get Lucky gets ~3 %,
// Superstition ~1 %). Smaller than the design "Visible (± 25 %)" magnitude
// because real-world proportions don't reach the formula's max; the
// scale was tuned for theoretical max proportion = 1.0 which doesn't
// occur in practice.
constant float FO_SPIKE_BASELINE_PIVOT          = 0.15;
constant float FO_SPIKE_BASELINE_RANGE          = 0.25;   // ±25 % per Matt approval 2026-05-27

// D-157 — per-beat spatial punch mask (Matt's option B, 2026-06-10).
// The pixel-level forensics convicted the GLOBAL punch: the whole spike field
// leaping each beat swung the entire frame's mean luminance 6–84 per beat
// (ablation: pulse-off = 0 flash steps, aurora/light unchanged) — geometry-as-
// rhythm read as luminance-as-strobe. The fix keeps the punch but gives it a
// FOOTPRINT: each beat, only smoothly-bounded REGIONS of the ocean punch
// (~⅓ of the field, re-drawn per beat from `pulse_beat_index`), so local beat
// motion stays strong while the global frame luminance stays steady.
//
// Mask = smooth value noise over xz (patch scale ~2.5 wu, smoothstep-banded)
// with the beat index shifting the noise domain — continuous in space (no SDF
// discontinuities; the wide transition bounds the added height-field gradient
// so the Lipschitz /6 budget holds — see the cap note below).
static inline float fo_hash21(float2 p) {
    float3 q = fract(float3(p.xyx) * 0.1031);
    q += dot(q, q.yzx + 33.33);
    return fract((q.x + q.y) * q.z);
}

static inline float fo_punch_mask(float2 xz, float beatIndex) {
    // Shift the noise domain per beat — a different region wakes each beat.
    float2 domain = xz * (1.0 / 2.5) + float2(beatIndex * 7.31, beatIndex * 3.17);
    float2 cell = floor(domain);
    float2 frac2 = fract(domain);
    float2 u = frac2 * frac2 * (3.0 - 2.0 * frac2);
    float n = mix(mix(fo_hash21(cell), fo_hash21(cell + float2(1, 0)), u.x),
                  mix(fo_hash21(cell + float2(0, 1)), fo_hash21(cell + float2(1, 1)), u.x),
                  u.y);
    // ~⅓ of the field active, wide smooth band (transition ≈ half a patch)
    // so the strength field stays gentle in space.
    return smoothstep(0.55, 0.80, n);
}

static inline float fo_spike_strength(float2 xz,
                                      constant FeatureVector& f,
                                      constant StemFeatures& stems) {
    // Layer 1 — one-sided baseline. Proportion above the pivot boosts
    // height; proportion at or below leaves baseline at 1.0.
    float proportion = clamp(stems.cached_bass_proportion, 0.0, 1.0);
    float aboveThreshold = max(proportion - FO_SPIKE_BASELINE_PIVOT, 0.0);
    // Scale `aboveThreshold` (range [0, 0.75]) → [0, 0.25] by * (1/3).
    // Pivot 0.25 → 0; theoretical max 1.0 → +0.25.
    float baseline = 1.0 + clamp(aboveThreshold * (FO_SPIKE_BASELINE_RANGE / (1.0 - FO_SPIKE_BASELINE_PIVOT)),
                                 0.0, FO_SPIKE_BASELINE_RANGE);

    // Layer 2 — FBS Stage 1 (D-153, 2026-06-09): the steady first-note-
    // anchored beat pulse. REPLACES the CSP.3.2/3.3 `0.8 × clamp(f.bass)`
    // term — the FBS diagnosis: `f.bass` is the auto-levelled (AGC) bass,
    // held near-constant by design, so the spikes barely moved (motion std
    // 0.09 on bass-light tracks = Matt's "frozen"), and its frame-to-frame
    // noise was the residual sparkle after the BUG-038 light fix.
    //
    // `pulse_phase01` is anchored to the track's first NOTE (= the downbeat;
    // Matt's correction, verified in FBS Stage 0), ticks at the cached-grid
    // tempo (reliable to ~1 %), and is NEVER drift-corrected — a steady
    // pulse that is wrong-by-a-hair beats a wandering pulse that is
    // right-on-average. `pulse_amp01` gates it: 0 before the first note and
    // across sustained silence (no punching into a silent room), 1 while
    // music plays. Stage 2 will scale punch height by live energy.
    //
    // Envelope: rise over the first 8 % of the pulse cycle, decay to 0 by
    // 85 %, rest until the next pulse. SLOW PULSE since D-154 (Matt,
    // 2026-06-10): the cycle is FOUR beats (~1.9 s at 128 BPM), so this reads
    // as a gentle oceanic heave at a musical rate — the Stage-1 live verdict
    // showed a per-beat punch from an arbitrary phase (gapless streaming
    // switches) reads as a robotic metronome ignoring the music.
    //
    // Headroom: the swing is capped so spike strength stays ≤ 1.62, under
    // the CSP.3.5 Lipschitz-divisor (/6) safe ceiling of 1.64 — punch peaks
    // every beat must not re-introduce the gray-tip artifact class.
    //
    // This is grid-PHASE-locked motion (Audio Data Hierarchy: the stable
    // beat-grid phase may drive timing), NOT Layer-4 onset-pulse motion —
    // no beat_bass/beat_mid/beat_composite onset signals are consumed (those
    // fire on ~97 % of frames on real sessions; BUG-038 root cause).
    // NOTE: this envelope's SHAPE is load-bearing for the FBS.S3 handoff
    // (D-156): `BeatPulseClock.envelope` mirrors it (attack end 0.20, decay
    // end 0.85) — the CPU swaps the pulse's phase source only while both
    // envelopes are < 0.15, bounding the visible seam. Change one, change both.
    //
    // Attack 0.20 of the cycle (FBS.S3.1, 2026-06-10): at per-beat rate the
    // original 0.08 attack spanned ~37 ms = 1–2 frames — a near-single-frame
    // spike-height (and reflected-light) step that read as FLASHING on every
    // handed-off track in Matt's session 2026-06-10T17-21-49Z (8–10 such
    // steps/min on the flashing tracks; ZERO on Money, the one track that
    // never handed off and drew no flashing complaint). 0.20 ≈ 100 ms at
    // 120 BPM: still a punch, never a frame-strobe.
    float ph     = clamp(f.pulse_phase01, 0.0, 1.0);
    float amp    = clamp(f.pulse_amp01, 0.0, 1.0);
    float attack = smoothstep(0.0, 0.20, ph);
    float decay  = 1.0 - smoothstep(0.20, 0.85, ph);
    float env    = attack * decay;
    // D-157 cap 1.62 → 1.55: the spatial mask adds a height-field gradient
    // term (≈ h·|∇mask|·head ≈ 0.3 at the chosen patch/transition scale);
    // trimming the peak keeps the worst-case gradient inside the CSP.3.5
    // Lipschitz /6 budget. Verified by the forensics white-pixel metric.
    //
    // D-158 (FBS.S5, Matt's S4 read): the BRIDGE heave is GLOBAL again —
    // under D-157's regional mask the slow opening heave was not visible
    // ("the slow opening heave was not visible with regional coverage").
    // `pulse_regional_blend01` is 0 during the bridge (mask collapses to
    // 1.0 = whole-ocean heave), ramping to 1 over one 4-beat span after the
    // handoff so the per-beat punches become regional without a coverage
    // cliff. Worst-case strength is unchanged (blend ≤ 1 scales the mask
    // gradient term DOWN, and the 1.55 peak cap holds in both regimes).
    // The global per-beat strobe cannot return: regional blend is 1 by the
    // time the per-beat live phase drives the envelope (the strobe was a
    // POST-handoff phenomenon; the bridge's ~380 ms quarter-cycle attack at
    // 4-beat rate drew no flash complaint on bridge-only Money in S3).
    float head   = min(0.7, 1.55 - baseline);
    float blend  = clamp(f.pulse_regional_blend01, 0.0, 1.0);
    float mask   = mix(1.0, fo_punch_mask(xz, f.pulse_beat_index), blend);
    // FBS Stage 2 — punch HEIGHT from passage loudness (kickoff §Stage 2:
    // loud → tall, soft → small, a floor so every beat registers while music
    // plays; `pulse_amp01` already zeroes the punch at true silence). Input
    // is the CPU-smoothed total stem energy (symmetric τ 2.5 s) — the
    // signal measured to survive the AGC on real sessions (So What's
    // bass+piano intro 0.33–0.35 vs 0.8–1.5 with the band in; Love Rehab /
    // Pyramid open ≥ 1.1 so strong openings keep full height). Mapping:
    // smoothstep over [0.25, 1.0] → height scale [0.30, 1.0]. So What's
    // intro lands ≈ 0.37 (gentle pulse), its band sections ≈ 1.0. Scale ≤ 1
    // only REDUCES the punch — the 1.55 Lipschitz peak cap holds.
    float loud   = smoothstep(0.25, 1.0, stems.total_energy_smoothed);
    float height = mix(0.30, 1.0, loud);
    return baseline + head * amp * env * mask * height;
}

// Swell amplitude scale — slow energy-driven drift only (round 65, 2026-05-18).
//
// **History:** Pre-round-65 the formula added `0.3 × drums_energy_dev` as a
// per-beat crest emphasis. Matt's 2026-05-18T13-37-57Z review identified
// this as the visible "substrate tied to bass" effect: swell amplitude
// pumped 0.70 → 0.91 on each drum hit (~25 % wave-height jump per beat).
// He preferred deactivating the substrate's beat reactivity and moving the
// per-beat response to the spike heights instead.
//
// Round 65 removes the drums term. The swell becomes purely atmospheric —
// amplitude drifts slowly with `arousal` (the broad energy curve of the
// music) but doesn't pulse per beat. The spike-height response (see
// `fo_spike_strength`) is reactivated in the same round to carry the
// beat reactivity that the swell used to.
//
//   silent + neutral arousal  → 0.4 (gentle calm-body breathing)
//   peak arousal              → 0.4 + 0.6 = 1.0 (sustained)
//
// Trade-off: silence-to-music transition no longer has the drum-driven
// "swell ramps up on first hit" character. Acceptable — arousal smoothing
// rises over a few seconds when music starts, so the swell amplitude
// still builds appropriately, just smoothly instead of beat-driven.
static inline float fo_swell_scale(constant FeatureVector& f,
                                   constant StemFeatures& stems) {
    (void)stems;
    return 0.4 + 0.6 * smoothstep(-0.5, 0.5, f.arousal);
}

// MARK: - Gerstner macro displacement
//
// Preset-level per `mat_ocean` (§4.14) convention. 4 superposed waves; Session 4
// may extend to 6. **Round 58 (2026-05-17): time source switched from
// `accumulated_audio_time` to `features.time`** (monotonic wall-clock) so
// macro swell undulation is visible at human timescales. The
// `accumulated_audio_time` clock advances at ~7-9 % wall-clock and made
// wave periods 60-196 s — practically static. Failed Approach #33's
// "no free-running sin(time)" prohibition applies to motion the viewer
// expects to land with the music (primary motion in active visual
// subjects). Macro ocean swell is ambient/atmospheric — exactly the
// category #33's scope clause EXCLUDES ("dust mote drift, slow mood
// gradients, accumulated_audio_time-driven palette cycling, sky-band
// low-frequency fbm4 modulation"). The swell is a permanent ambient
// property of the body of liquid; its rolling motion is not music-
// reactive (the AMPLITUDE is, via fo_swell_scale).
//
// Per-wave parameters: direction, wavelength, base amplitude, speed.

struct FOGerstnerWave {
    float2 dir;        // unit direction in xz
    float wavelength;  // metres between successive crests
    float amplitude;   // base (pre-audio-scale) amplitude
    float speed;       // angular speed scalar applied to t
};

// Wave parameter table — ported from the (now-disabled) mesh-path Gerstner
// in `FerrofluidMesh.metal` per round 59 (2026-05-18). Matt's
// 2026-05-18T00-53-39Z review: "The effect of deep ocean waves is lost."
// The previous SDF-path parameters (wavelengths 0.8-4.0 wu, max amplitude
// sum 0.34 wu) produced surface ripples, not ocean swell. The mesh-path
// parameters used while the mesh path was active (wavelengths 6-12 wu,
// max amplitude sum 0.60 wu) gave deep-ocean swell that Matt approved.
// Round 59 ports those parameters here so the SDF path produces the same
// swell character.
//
// Wave speeds: derived from a 6-bar-per-cycle target at 120 BPM ≈ 12 s/cycle
// → angular speed 2π/12 ≈ 0.52 rad/s for the longest wavelength. Shorter
// waves get proportionally faster speeds. The mesh-path used tempo-locked
// phase (musicBars / 6) — the SDF path uses fixed wall-clock speeds since
// the tempo signal isn't trivially available here. Periods land at 8-15 s
// (real ocean swell range).
static inline FOGerstnerWave fo_wave(int i) {
    FOGerstnerWave w;
    switch (i) {
        default:
        case 0:
            // Primary: toward camera (+Z), longest wavelength, dominant amplitude.
            w.dir        = float2(0.0, 1.0);
            w.wavelength = 12.0;
            w.amplitude  = 0.20;
            w.speed      = 0.52;       // ≈ 12.1 s/cycle
            break;
        case 1:
            // Slight right-toward-camera offset (~17° from primary).
            w.dir        = float2(0.2873, 0.9579);
            w.wavelength = 8.0;
            w.amplitude  = 0.16;
            w.speed      = 0.64;       // ≈ 9.8 s/cycle
            break;
        case 2:
            // Slight left-toward-camera offset (~22° from primary).
            w.dir        = float2(-0.3939, 0.9191);
            w.wavelength = 10.0;
            w.amplitude  = 0.14;
            w.speed      = 0.57;       // ≈ 11.0 s/cycle
            break;
        case 3:
            // More perpendicular, shorter wavelength — surface chop.
            w.dir        = float2(0.8321, 0.5547);
            w.wavelength = 6.0;
            w.amplitude  = 0.10;
            w.speed      = 0.85;       // ≈ 7.4 s/cycle
            break;
    }
    return w;
}

// Tessendorf horizontal-sway parameter (round 62, 2026-05-18). 0 = pure
// sinusoidal Y displacement; 1 = maximum circular orbit. Mirror of the
// mesh-path `kGerstnerSteepness` value, deferred when porting Gerstner
// parameters in round 59. 0.3 gives visible crest-rolling without wave-tip
// fold-over even at constructive peak of all 4 waves.
constant float kSwellSteepness = 0.3;

// Compute full 3D Gerstner displacement (x sway + y height + z sway) at
// world xz; t is `features.time` (wall-clock seconds, monotonic — set in
// sceneSDF after round 58). swellScale multiplies every wave's amplitude.
//
// Returns the surface displacement vector that the un-displaced point
// `(xz.x, 0, xz.y)` undergoes — i.e., the surface point IS at
// `(xz.x + disp.x, disp.y, xz.y + disp.z)`. To find the surface height
// at a fixed world-XZ position p, the inverse-mapping is needed; for
// height-field SDF rendering, the forward-Euler approximation
// `spike_sample_pos = p.xz - disp.xz` is accurate at small steepness
// (the 0.3 value here is well within the linear-approximation regime).
//
// Tessendorf reference: J. Tessendorf, "Simulating Ocean Water," 2001,
// §3.3 "Simple Sum-of-Sinusoids" with the displacement orbit term.
static inline float3 fo_gerstner_swell(float2 xz, float t, float swellScale) {
    float3 disp = float3(0.0);
    for (int i = 0; i < 4; i++) {
        FOGerstnerWave w = fo_wave(i);
        float k     = FO_TWO_PI / max(w.wavelength, 0.001);
        float phase = dot(w.dir, xz) * k - w.speed * t;
        float A     = w.amplitude * swellScale;
        float cosP  = cos(phase);
        float sinP  = sin(phase);
        // Vertical sine displacement (height of crest).
        disp.y += A * sinP;
        // Horizontal sway in the wave's propagation direction. Crests
        // move forward and back relative to their travel — the visible
        // "rolling" character of ocean swell.
        disp.x += kSwellSteepness * A * w.dir.x * cosP;
        disp.z += kSwellSteepness * A * w.dir.y * cosP;
    }
    return disp;
}

// MARK: - Rosensweig spike field
//
// SHADER_CRAFT §4.6 recipe. fieldStrength routed from stems.bass_energy_dev
// (via fo_spike_strength). Session 4.5 rescue: meso domain warp dropped per
// Failed Approach #62; per-cell temporal sin oscillation dropped (Failed
// Approach #33 echo — free-running sin adds motion the music isn't driving;
// the t parameter is consequently absent from this function).
//
// **Session 4.5 final geometry — smooth Voronoi (after desk research).**
// History: I iterated six times on this function trying to eliminate a
// per-cell "dot pattern" in the rendered surface. Each fix was a guess that
// got tested and falsified. Matt eventually pointed out that ferrofluid
// rendering is a solved problem and I should do desk research instead of
// guessing. The desk research found Robert Leitl's audio-reactive WebGL
// ferrofluid project — the closest published reference to Phosphene's use
// case — which builds its height field from Inigo Quilez's **smooth
// Voronoi**. Smooth Voronoi blends distances to all neighbor cells via
// exponential weighting, producing a C¹-continuous height field with no
// boundary normal flips. That's the structural fix for the dot pattern,
// which was rooted in the hard `min()` discontinuity at every cell edge
// in regular Voronoi.
//
// **Session 4.5b Phase 1 (V.9 particle-motion increment): texture-backed.**
// The geometric source moved from inline `voronoi_smooth` to a sample of
// the 512×512 r16Float height texture baked by `ferrofluid_height_bake`
// (`Renderer/Shaders/FerrofluidParticles.metal`). Phase 1 places 2048
// particles at the XZ coordinates a `voronoi_smooth` cell-center pass
// would emit (rectangular int-cell grid + per-cell `voronoi_cell_offset`
// hash; mirrored CPU-side in `FerrofluidParticles.swift`), so the baked
// texture's spike topology is the structural equivalent of the Phase A
// inline path. Phase 2 will add SPH-lite particle motion + audio forces
// so the peaks drift, cluster, and scatter with the music; the sampling
// path here is unchanged across both phases.
//
// References (full set):
//   - Robert Leitl, Ferrofluid Web Experiment:
//     https://robert-leitl.medium.com/ferrofluid-7fd5cb55bc8d
//   - Inigo Quilez, Smooth Voronoi:
//     https://iquilezles.org/articles/smoothvoronoi/
//   - Inigo Quilez, polynomial smooth-min:
//     https://iquilezles.org/articles/smin/
//   - Rosensweig instability video (geometry reference):
//     https://www.youtube.com/watch?v=39oyuJLQt_E
//   - User-supplied still references (hex-pack pointed pyramids)
//
// Texture mapping: the height texture covers the world-XZ rectangle
// [worldOriginX, worldOriginX + worldSpan] × [worldOriginZ, worldOriginZ +
// worldSpan] = [-10, 10] × [-8, 12]. The Phase A inline math is preserved
// as `fo_ferrofluid_field_inline` (below) for diagnostic use; production
// sceneSDF samples via `fo_ferrofluid_field_sampled`.

// World-XZ patch constants — kept in sync with
// `FerrofluidParticles.swift::worldOriginX/Z/Span` via
// `FerrofluidParticlesTests.test_swiftMetalConstantsMatch`.
constant float FO_HEIGHT_WORLD_ORIGIN_X = -10.0;
constant float FO_HEIGHT_WORLD_ORIGIN_Z =  -8.0;
constant float FO_HEIGHT_WORLD_SPAN     =  20.0;

static inline float fo_ferrofluid_field_sampled(float3 p,
                                                float fieldStrength,
                                                texture2d<float> heightTex) {
    if (fieldStrength <= 0.0) return 0.0;
    // Function-scope `constexpr sampler` so the declaration is only emitted
    // for presets that actually call this helper (Ferrofluid Ocean only).
    // Declaring the sampler at file/preamble scope tripped `-Werror` on the
    // other ray-march presets that include the preamble but never use it
    // (`-Wunused-const-variable`).
    constexpr sampler heightSamp(coord::normalized,
                                 filter::linear,
                                 address::clamp_to_zero);
    // World XZ → UV. Outside [0, 1] the sampler's clamp-to-zero address
    // mode returns 0 → spike lattice terminates cleanly at the patch edge.
    float u = (p.x - FO_HEIGHT_WORLD_ORIGIN_X) / FO_HEIGHT_WORLD_SPAN;
    float v = (p.z - FO_HEIGHT_WORLD_ORIGIN_Z) / FO_HEIGHT_WORLD_SPAN;
    float spike = heightTex.sample(heightSamp, float2(u, v)).r;
    // Round 50 (2026-05-16): height multiplier 0.15 → 0.63 to land aspect
    // ratio at ~3.7:1 (= reference-faithful needle character). With
    // spikeBaseRadius = 0.17 wu and constant fieldStrength = 1.0, peak
    // height = 1.0 × 0.984 × 0.63 ≈ 0.62 wu / radius 0.17 wu ≈ 3.7:1
    // aspect. Tall enough that the cone body dominates the rounded apex
    // (the rounded apex was previously dominating because it WAS the
    // whole shape). See `fo_spike_strength` docstring for the constant-
    // field premise + FerrofluidParticles.swift::spikeBaseRadius for the
    // radius-vs-height trade-off discussion.
    return spike * fieldStrength * 0.63;
}

// Phase A inline fallback. Retained for diagnostic comparison + the case
// where no height texture is bound (`heightTex.get_width() == 1` ⇒ the
// 1×1 placeholder, returns 0 ⇒ no spikes). Not called from sceneSDF
// today; future increments may A/B between paths via a feature flag.
static inline float fo_ferrofluid_field_inline(float3 p, float fieldStrength) {
    if (fieldStrength <= 0.0) return 0.0;
    constexpr float kVoronoiScale   = 4.0;
    constexpr float kVoronoiSmoothK = 32.0;
    constexpr float kSpikeRadius    = 0.6;
    float smoothD = voronoi_smooth(p.xz, kVoronoiScale, kVoronoiSmoothK);
    float spike   = max(0.0, 1.0 - smoothD / kSpikeRadius);
    return spike * fieldStrength * 0.15;
}

// MARK: - sceneSDF
//
// Composes Gerstner swell (base height) with Rosensweig spike field (riding on
// top). Returns signed distance to the surface from world point p.
//
// Independence contract (D-124(d)): swell amplitude (arousal + drums) and
// spike height (bass) are routed from disjoint primitives. Both states —
// calm-body-with-spikes and agitated-body-without-spikes — are reachable.
//
// Surface is opaque; everything below is solid. No transmission, no walls,
// no contained dish — the surface extends to the camera's far plane.

float sceneSDF(float3 p,
               constant FeatureVector& f,
               constant SceneUniforms& s,
               constant StemFeatures& stems,
               texture2d<float> ferrofluidHeight) {
    (void)s;
    // Round 58 (2026-05-17): switch Gerstner time source from
    // `accumulated_audio_time` to `features.time`. The accumulated_audio_time
    // primitive advances at ~7-9 % of wall-clock (energy-weighted, pauses at
    // silence) — with Gerstner wave angular speeds 0.4-1.3 rad/s, that made
    // wall-clock wave periods 60-196 seconds (practically static at
    // session-viewing timescales). Matt's 2026-05-17T23-31-11Z review:
    // "the undulation of the ocean is no longer present." `features.time`
    // is monotonic wall-clock seconds → waves roll at their natural rates,
    // giving the body-of-liquid character the "ferrofluid ocean" framing
    // depends on. The ocean keeps breathing at silence (more ocean-like
    // than music-paused). The audio response continues to live in the
    // aurora (vocals → hue, drums → intensity, arousal → drift) and the
    // swell AMPLITUDE (arousal baseline + drums accent via
    // `fo_swell_scale`) — only the wave PROPAGATION uses real time now.
    // See `project_accumulated_audio_time_not_clock` memory for the rule.
    float t        = f.time;
    // Round 62 (2026-05-18): Gerstner now returns full 3D displacement
    // (Tessendorf sway). The horizontal X/Z components shift the spike
    // sample position so each spike rides on the wave it's part of —
    // crests carry their spikes forward, troughs carry theirs back.
    // Forward-Euler approximation: at small steepness (0.3) the inverse
    // mapping is approximately linear, so we step the spike-sample XZ
    // backward by the swell's horizontal displacement to find the
    // un-displaced source position. Accurate enough at our steepness;
    // exact form would require fixed-point iteration which isn't worth
    // the cost for this visual difference.
    float3 swellD  = fo_gerstner_swell(p.xz, t, fo_swell_scale(f, stems));
    float3 spikeP  = float3(p.x - swellD.x, p.y, p.z - swellD.z);
    float spikes   = fo_ferrofluid_field_sampled(spikeP,
                                                 fo_spike_strength(spikeP.xz, f, stems),
                                                 ferrofluidHeight);
    float surfaceY = swellD.y + spikes;
    // Round 56 (2026-05-17): Lipschitz-corrected SDF. The naive
    // `p.y - surfaceY` returns the VERTICAL distance to the surface, not the
    // true 3D minimum distance. For tall narrow cones (height 0.62 wu / base
    // radius 0.17 wu = max gradient ~3.65 at spike strength 1.0), the true
    // distance to a sloped cone side is up to 3.78× smaller than the
    // vertical distance when the ray-march sample point is laterally near a
    // cone. Without correction, the ray-march (which assumes Lipschitz-1)
    // overshoots the surface → inconsistent surface-hit positions across
    // pixels → noisy normals from central differences → banded/scooped
    // patterns (rounds 50-55) or gray pixels at tips (CSP.3.3 M7).
    //
    // CSP.3.4 → CSP.3.5 (2026-05-28) — divisor settled at /6 after iterating.
    // Round 56's `/4` was sized for spike strength 1.0 (no modulation), bounding
    // gradients up to 4. Post-CSP.3.3 spike strengths reach 1.25–1.50 in typical
    // playback (effective gradients 4.6–5.5) → /4 produced gray-tip artifacts.
    // CSP.3.4 bumped to /10 (covers gradient 10, spike strength up to 2.74) but
    // had a side effect: each ray-march step became 60 % smaller than /4, so
    // rays at oblique view angles (camera-close grazing reflections + far-corner
    // pixels) exhausted the 128-step iteration cap (PresetLoader+Preamble.swift
    // line 418) BEFORE finding the surface. Those pixels fell back to the
    // "sky/miss" path and rendered the procedural sky as white patches. CPU
    // also breached the 16.67 ms 60 fps budget (17.14 ms avg, session
    // 2026-05-28T17-50-42Z) from doing more iterations per pixel.
    //
    // CSP.3.5 /6 splits the difference: covers gradients up to 6 (spike strength
    // up to 1.64), which accommodates all typical playback worst-cases observed
    // (Money 1.36, Love Rehab regular ≤ 1.30, the cited LF session 1.52). The
    // rare f.bass-near-1.0 frames (0.1 % of playback in some sessions) may
    // produce brief gray-tip flicker, but those frames are too sparse to
    // sustain a visible artifact. Net: balances Lipschitz safety against
    // iteration reach + CPU budget.
    //
    // CSP.3.5.1 (2026-05-28) — apply the intended /6 to the operative line.
    // The CSP.3.5 commit (eaaadd9b) rewrote the comment block above to
    // describe `/10 → /6` but left the `return` line at `/10.0`; the closeout's
    // "1358/1358 pass" claim was wrong because PresetAcceptanceTests'
    // `test_readableForm_atSteadyEnergy` reproducibly fails at /10 (the
    // 128-step march budget can't converge on the spike surface at the
    // rubric's f.bass=0.5 fixture — all pixels fall through to sky/miss →
    // formComplexity = 1). The fix here is the literal missing edit.
    return (p.y - surfaceY) / 6.0;
}

// MARK: - sceneMaterial (Session 3: §5.8 stage-rig dispatch via matID == 2)
//
// Pitch-black near-mirror substrate per §4.6 ferrofluid baseline. The
// per-light Cook-Torrance evaluation + wavelength-dependent thin-film F0
// are computed in the matID == 2 branch of `raymarch_lighting_fragment`
// (RayMarch.metal) — that branch has access to the view vector, surface
// normal, AND the slot-9 stage-rig buffer (D-125) which sceneMaterial does
// not. The role of this function is to declare the material *kind* (albedo,
// roughness, metallic + matID dispatch) so the lighting pass can apply the
// right BRDF.
//
// Session 3 switches outMatID from 3 → 2 per the V.9 Session 3 prompt; the
// matID == 3 single-light thin-film branch is retained in RayMarch.metal as
// a fallback for future presets that want the iridescent material without
// the multi-light rig. The thin-film F0 helper (`rm_thinfilm_rgb`) is shared
// between the matID == 2 and matID == 3 branches.

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
    (void)p; (void)matID; (void)f; (void)s; (void)stems; (void)lumen;
    albedo    = float3(0.02, 0.03, 0.05);  // §4.6 ferrofluid base
    roughness = 0.08;                       // near-mirror
    metallic  = 1.0;
    outMatID  = 2;                          // §5.8 stage-rig dispatch (D-125)
}
