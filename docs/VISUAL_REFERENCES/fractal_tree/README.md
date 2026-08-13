# Visual References — Fractal Tree

**Family:** fractal
**Render pipeline:** `["mesh_shader"]` — object → mesh → fragment via `MeshGenerator.draw`; flat HSV, no lighting, no G-buffer
**Rubric:** lightweight — stylized 2D graphic (exempt from full detail-cascade + material-count requirements)
**Last curated:** 2026-08-03 by Matt (FTR.1 / D-212)

> **Read this before the checklist trips you up.** The painterly reference set that used to live here — 14 images of bark, translucent foliage, golden-hour light and autumn palettes — **moved to `../goldengrove/`** when the V.10 uplift was cancelled at D-212. It described a preset Fractal Tree is deliberately not becoming. Do not go looking for it here and do not port it back.
>
> **There is currently no curated image set for this preset, and FTR.2 was built without one.** `PRESET_SESSION_CHECKLIST.md` Part 1 §1 offers two routes — curate first, or escalate to Matt. It was escalated and **Matt resolved it on 2026-08-03: build without reference images, live review at M7 (FTR.5).** The stylization contract and the five anti-references below were the visual authority for the FTR.2 routing rebuild; the look verdict is deferred to that live review. Do not add image files here under version control — LFS.2 untracked them deliberately to stop the Git-LFS bill.

## Reference images

| File | Annotation (what to learn from this image) |
|---|---|
| *(none yet)* | Curation pending — FTR.2 prerequisite. |

### What a reference set here would need to show

The register is **flat, graphic, diagrammatic** — closer to a botanical plate, a Milkdrop line-figure, or a plotter drawing than to a photograph of a tree. Slots worth filling, in priority order:

1. **Graphic branch-fan silhouette** — a recursive tree read as *line and shape*, not as surface. The whole subject in one flat value range.
2. **Asymmetric L-system parameter card** — branching angle and proportional reduction, same role as the old `02_macro_branching_params.jpg`. This one trait survives the redirect: **branching angle ∈ [15°, 25°], proportional reduction ∈ [0.62, 0.68]** matched the crown form we want and the current shader sits at 22° / 0.62.
3. **Flat-colour palette anchor** — a limited palette that stays legible when branches overlap at 60 % alpha.
4. **Anti-reference: bilateral symmetry** — the retired `14_anti_reference.png` (`symmetric-fractal-tree.png`) is still exactly right for this preset. Perfect mirror symmetry, uniform thickness, identical sub-trees. Triggers Failed Approach #44.
5. **Anti-reference: accidental realism** — anything with rendered bark, volumetric light, or foliage mass. That is Goldengrove's job; here it is a failure.

## Stylization contract

What DOES matter for this preset (substitute for the full rubric):

- [x] **Color modulation:** leaf/tip hue tracks harmonic movement (`tonal_phase_fifths`), not a wall clock. ✅ FTR.2 — the `fract(t * 0.006)` term is gone; hue now swings 41.9°–87.4° on harmony alone.
- [x] **Audio coverage:** each visual layer on its own *distinct* primitive (FA #67). ✅ FTR.2 — five layers, five primitives, replacing three-layers-on-`bass_att`.
- [x] **Readability at silence:** a sparse, still, non-black tree — trunk plus the first two generations, legible and clearly alive (D-037). ✅ FTR.2 — `bass_dev` is 0 at silence → the 7-branch rest tree; mean luma 0.0046, gated in `FractalTreeMeshRenderTest`.
- [x] **Readability at peak energy:** a full canopy that still reads as a *tree*, not a solid mass. Branch count must not flat-top. ✅ FTR.2 — the soft knee `bd/(bd+0.12)` is asymptotic, so the 63 ceiling is unreachable by construction; measured max 48. Was pinned at 63 on 1.24 % of frames.

*(Every box above is an automated or measured check. The one thing no box can carry is whether it LOOKS right — that is L4, and it is Matt's live M7 call at FTR.5.)*

## Anti-references

What this preset must NOT look like:

- **Perfect bilateral symmetry** — mirror-image sub-trees at every recursion (FA #44). Break with per-branch hash jitter.
- **Uniform branch thickness** at a given depth — vary per-branch.
- **A rendered/painterly tree** — bark texture, leaf mass, volumetric light. That register belongs to Goldengrove; producing it here is the failure, not the goal.
- **A colour-cycling wallpaper** — hue drifting on a timer while the music does something else.
- **A tree that flat-tops** — visibly pinned at maximum branch count through a whole chorus.

## Audio routing notes

**Shipped routing — MEASURED, as rebuilt at FTR.2.** Five visual layers, five distinct primitives (FA #67). Swing figures are p05→p95 on four sources: session `2026-08-03T20-05-13Z` (*Hummer*, 7260 frames after warmup, chain verdict `clean`) plus the three `route_coverage` fixtures.

| Layer | Primitive | Measured swing (Hummer / love_rehab / so_what / there_there) | Was |
|---|---|---|---|
| canopy reach — branch count + trunk length + thickness, one coupled gesture | `bass_dev` | footprint +48 %; branch count 7→48, never pinned; blooms 1.91/s | three layers on `bass_att`; pinned at 63 for 1.24 % of frames |
| branch spread | `spectral_flux` | **8.97° / 10.77° / 8.23° / 7.72°** | `mid_att`, 0.42° of a promised 7° — dead |
| leaf hue | `tonal_phase_fifths` | **85.2° / 87.4° / 51.6° / 41.9°** of hue | `spectral_centroid`, 4.1° against a 76° wall clock — dead |
| global brightness | `arousal` | **+54.0 % / +14.2 % / +28.1 % / +22.8 %** | *did not exist* — the preset had no section-scale route |
| beat accent | `beat_bass` | live on 15.7–18.2 % of frames, firing 1.88–2.32/s at full amplitude | live on 99.2–100 % — read as a glow, not an accent |

**Changed at FTR.6 — the melodic tips moved off `beat_mid` onto `melodic_tips`.** Matt, after DYN.1c: *"The tips are too active. If possible, I would want only one tip per note of music."* Measured on `2026-08-07T18-53-30Z` the tips fired **7.62/s with a mean jump of 4.6 branches**, against a guitar note rate of **3.29/s**. The rate is not reachable from `beat_mid` at any coefficient — it turns 6.9 times a second, and a stateless shader has no memory of the last event — so the minimum inter-event interval moved into the engine as `MelodicNoteGate` (`FeatureVector.melodicTips`, float 53).

| Layer | Primitive | Measured (Hummer / Cherub Rock, full tracks through the real `MIRPipeline`) | Was |
|---|---|---|---|
| melodic tips — how many fine branches exist | `melodic_tips` | **2.92 / 2.87 note events per second, 1.00 branch per change**; count-changes 5.47 / 5.37 per second, down from 31.6 / 31.5 on identical audio | `beat_mid` through a soft knee — 7.62/s, mean jump 4.6 branches |
| melodic reach — how far each branch travels | `beat_mid` | unchanged; the per-branch travelling wave Matt called *"better overall and probably satisfactory"* at FTR.3e | — |

**Two things the gate does NOT fix, stated rather than implied.** (1) *Instrument separation* — Matt's *"heavily favors the drums vs. guitars"* survives it. The trigger is still mid-band, which in a rock mix is snare AND guitar (correlated **+0.973** here), and per-note guitar onsets do not survive distortion (§MEL.1: grid coherence 31 % for guitar against 41 % for the drums control). (2) *Total transition count* — a tip that appears must also disappear, so the branch count changes about **twice** per note event. That is arithmetic at equilibrium, not a tuning miss; what the gate removes is the SIZE of each change, 4.6 branches → 1.

**Changed at FTR.10 — the trunk STEPS instead of sliding.** Matt, 2026-08-11: *"The trunk is moving too much, which unfortunately makes the motion of the tips difficult to see. We need less motion — like tying movement to the songbeat."* His choice, from three offered: steps on each beat. `base_len` now reads the beat-held `FeatureVector` at object buffer(4) (`BeatHold`) instead of the live one — same `0.27 + reach·0.13 + surge·0.32`, sampled on the beat and held between beats.

| Layer | Primitive | Measured (`2026-08-11T18-26-52Z`, *Carry The Zero*, chain `clean`) | Was |
|---|---|---|---|
| trunk length — and with it the whole skeleton's scale | `spectralSectionRatio` + `spectralSurge`, **clocked by `beatPhase01`** | **0.52 turns/s, span 0.344** (hold engaged 95 % of frames) | 1.64 turns/s, span 0.348 — continuous |

**This is a temporal contract, not a new route.** The primitives are unchanged; what changed is WHEN the trunk is allowed to move. Two consequences worth keeping: the range is deliberately preserved (98.9 % of the continuous span — a smoother would have traded it away, which is the DYN.1e failure), and the branch counts, tips and thickness are deliberately NOT held, because the tips becoming visible is the whole point. And the hold is gated: no `BeatGrid`, a beat-irregular grid (D-154), a stalled phase, or the first ~4 s of a track all fall back to continuous. Fractal Tree therefore stays eligible for beat-irregular tracks rather than being excluded from them.

**Changed at FTR.11 — the WHOLE FRAME steps, not just the trunk.** Matt, after FTR.10: *"The trunk and branches are responding to both drums and vocals it seems and it's still too much."* Branch count, branch spread and thickness now read the beat-held vector alongside the trunk. Measured (SNA 124 BPM / Carry The Zero 94 BPM): frame branch count **1.88 → 0.74** and **2.30 → 0.54** turns/s; branch spread **5.48 → 1.42** and **6.26 → 1.20**; ranges intact.

**Changed at FTR.14 — the beat sets the DESTINATION, the render clock carries the MOTION** (Matt's third rejection of the stepped look, 2026-08-13: *"the tree looks like it's dancing the robot — I don't like the stepped changes"*, while adding that he *does* value the tighter sync). The visible geometry now glides toward the beat-latched target on the ~60 Hz render clock and never arrives-and-freezes. The glide runs pre-grid too, so the 6–8 s transition he objected to three times no longer exists.

**★★★ FTR.13's EASE FAILED ON ARITHMETIC, NOT TASTE: it ran on 2 SAMPLES.** BUG-087 — every `FeatureVector` field updates at ~10 Hz on the local-file path, so a 94 BPM beat carries **6.4 samples**. A 1/3-beat ease is **2.1** of them and the hold after it is **4.3 dead**. Size any temporal effect in SAMPLES, never in fractions of a beat.

**★★★ FOUR METRICS PASSED THE BUILD MATT REJECTED.** Turn rate (0.30 turns/beat — a low rate is what a freeze BUYS), step size (mean 0.75 branches — a freeze has small steps), per-frame float inequality (0.005 frozen — measured the interpolated value, not arrivals), per-frame PIXEL identity (0.95 frozen at *every* τ — a trunk crossing 0.34 clip units in 100 s is sub-pixel per frame however smooth, so a 5-second pan fails it too). `motion_gate.sh` also called FTR.13 smooth with 0 spikes. **A metric that cannot separate the known-bad build from the known-good one is not evidence, whatever it says about the new one.**

**The metric that works: 100 ms-window burstiness** — the eye integrates over ~100 ms, so measure displacement per 100 ms window, then the share of empty windows and the CV. Validated against both references on Matt's own capture *before* being trusted:

| build | empty 100 ms windows | CV | mean travel |
|---|---|---|---|
| hard hold (rejected) | **0.817** | **3.51** | 0.0032 |
| continuous (preferred) | 0.083 | 1.81 | 0.0038 |
| glide (shipping) | **0.101** | **1.64** | 0.0032 |

Gated at `empty < 0.35`; the bar sits between two measured references, not around the shipping number. τ = 1/4 beat, tempo-relative — the sweep showed 0.25→0.85 buys nothing and costs lag and amplitude.

**Changed at FTR.13 — the steps are EASED, branches GROW IN, and the tips are BEAT-MATCHED** (Matt's M7 on `2026-08-12T19-45-24Z`: *"motion reads as robotic and stuttering … it's the stepping itself that is the problem"*, and *"the tips … should be beat matched"*).

**★★ THE LESSON, and it invalidates how FTR.10/FTR.11 were graded: a turn RATE cannot tell "holds still then snaps" from "drifts."** A low turn rate is what a hard sample-and-hold BUYS — so the frame scored a calm 0.30 turns/beat while Matt watched the canopy stutter. **Measure step SIZE beside step rate.** For a branch COUNT, size is the whole story: the worst single beat added 15–19 branches at once on a tree spanning 43.

**Slowing the clock is NOT the fix, and it was measured before being built.** Matt first chose per-bar steps; moving the hold to the bar cut the rate ~2.5× but grew the mean step ~1.8× and the worst event to 23–28 branches. A slower clock CONCENTRATES the pop. He took eased-steps-on-the-beat instead.

Three mechanisms: (1) `BeatHold(easeBeats: 1/3)` — the snapshot starts moving ON the beat and arrives a third of a beat later, smoothstepped, so onset stays beat-locked and only the sharpness goes; (2) the payload carries a **fractional** branch count and each branch's LENGTH scales by `saturate(count_f − bid)`, so a 15-branch rise is a 15-branch sweep instead of a block appearing — stateless, no per-branch memory; (3) `StemFeatures` is held on the same beats at object/mesh **buffer(5)**, because the tips' driver is a per-stem field and holding only the `FeatureVector` left them at 4–5 changes/s.

Measured on the reviewed capture: tips **2.05 → 0.56** turns/beat (mean step 1.24 → 0.31 branches), frame count mean step **2.78 → 0.75** and max **15 → 11.2**, trunk max step 0.125 → 0.092. `motion_gate.sh` scores it **smooth for the first time — 0 spike frames of 95**, against 28 for the pre-FTR.11 build; the easing removed the spikes without removing the beat lock. The grow-in is visible in a still: the outermost tier renders mid-extension, shorter than the tier behind it.

**The tips gate is now TWO-SIDED and the old one is gone on purpose.** `tipTurns > 1.5`/s was ~0.9–1.0 turns/BEAT at these tempos — it required almost exactly the behaviour Matt rejected. Replaced by `> 0.15` (must not freeze — the original concern) and `≤ 1.0` (beat-matched by definition) turns/beat. Do not raise the upper bound; a tip layer moving faster than the beat is a routing decision and Matt's.

**Changed at FTR.12c — the trunk motion bar is asserted in turns per BEAT, not per second** (Matt: *"Per beat"*, 2026-08-12). A beat-held value can only change ON a beat, so a per-second bar carries the tempo: the same trunk measured 0.66/s on a 124 BPM track and 0.52/s on a 94 BPM one, but **0.32 and 0.33 per beat**. The bar is unchanged, only re-expressed — `0.6/s ÷ 1.568 beats/s` (the 94 BPM calibration track) `= 0.38/beat`. Per second is still printed for the continuously-driven rows, which are not beat-held. The turns/beat denominator is cross-checked against `grid_bpm` and the harness **refuses to measure** if the phase clock disagrees by > 10 %, because a stalled `beatPhase01` would otherwise turn this gate green for the wrong reason.

**The tips are the exception and that is the design.** They remain on the live vector, so with the frame quiet they are the only continuously-moving layer — which is *"the tips are difficult to see"* answered from the other side. A gate fails if they ever stop.

**⛔ THE GUITAR CLAIM IS RETIRED — there is no guitar channel, and there is nothing to route to (FTR.12, Matt's call 2026-08-12).** The tips still read `otherOnsetRate`; it is now correctly described as an **activity level in the non-drum/non-bass/non-vocal residue**, not as an instrument. Do not reintroduce the word "guitar" for this route, and do not widen its coefficient to make a guitar "register" — there is nothing there to amplify except the drums.

Measured across 7 tracks (`docs/diagnostics/FTR12_GUITAR_CHANNEL_2026-08-12.md`): `r(otherOnsetRate, drumsOnsetRate)` is **highest at +0.792 on a solo piano recording with no guitar and no drum kit**, lowest at +0.492 on *Seven Nation Army*, and its p50 spans just **4.06…5.33** across solo classical guitar, player piano, pure synthesis and distorted rock. On a solo-classical-guitar record the drums stem — pure separation residue — yields a **higher** onset rate than the guitar. The cause is mechanical: the feature fires on broadband RMS flux past an **adaptive** threshold, so it measures the detector, not the instrument. The envelope features are worse (r 0.81–0.99 vs drums on every track). FTR.8's justifying **+0.14** was a single-track figure and does not reproduce (+0.606 offline on the same track); the two captures behind the route disagreed by 0.57 on the same feature.

**If a guitar layer is ever wanted, it needs a different mechanism.** IFC.4's four families are orchestral and contain no guitar class at all. The only measured candidate is the PANNs guitar-class probability — decisive on clean prominent guitar (p50 0.52–0.58 vs ≤0.096 guitarless) and **not usable on distorted rock guitar** (0.07–0.09, inside the guitarless range). That would be its own increment.

**Removed at FTR.2:** tip shimmer ← `treb_att`, which delivered +0.002 of a promised +0.12. Not re-homed — that visual layer belongs to FTR.3's per-branch activation, and a dead route is deleted rather than left declared as a false manifest.

**Still to come:** per-branch activation (HERO) ← `beat_phase01` + `pulse_beat_index`, hash-selected bounded subset — FTR.3. Percussive accent ← `stems.drums_energy_dev` — FTR.4, which needs the object/mesh-stage stem binding (the *fragment* stage is already bound at buffer(3) by `drawWithMeshShader`; only the object/mesh half is missing).

**Coefficient rule:** size every coefficient against the primitive's measured p05→p95 span on a real capture, never against a notional 0→1. Applied throughout the table above — and it changed a primitive choice: D-212 named `bass_dev` for canopy reach without measuring it, and the measurement (zero on 66–89 % of frames) is what made the soft-knee `bd/(bd+0.12)` mapping necessary rather than a linear gain.

## Provenance

Curated by: Matt
Image sources: *(none yet — curation pending at FTR.2)*
Painterly predecessor set: `../goldengrove/README.md` (transferred intact at D-212)

## Cross-references

- `docs/presets/FRACTAL_TREE_REACTIVITY_REVIEW.md` — the measured review behind this redirect
- `DECISIONS.md` D-212 — keep the low-fi look; V.10 cancelled; reference set transferred
- `ENGINEERING_PLAN.md` Phase FTR — the reactivity + certification arc
- `SHADER_CRAFT.md §14` — primitive liveness rule (the rule these dead routes broke)
- `SHADER_CRAFT.md §13` Failed Approach #44 — per-instance variation
- ~~`SHADER_CRAFT.md §10.4`~~ — superseded (painterly uplift plan; cancelled at D-212)
