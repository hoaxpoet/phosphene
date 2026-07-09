# Ricercar — contrapuntal visual-music painting preset

**Working name:** Ricercar (Baroque antecedent of the fugue; Italian *ricercare*, "to seek out" — the contrapuntal lineage plus the generative, searching quality of the canvas). Provisional; alternatives in §9. Runners-up: **Stretto** (overlapping voice-entries in tight imitation), **Cantus** (the singing line).

**Lineage:** Visual music / abstract animation — Oskar Fischinger, the Whitneys, Len Lye, Norman McLaren; the "color organ" tradition of translating music to abstract colour and motion. Ricercar adopts the *spirit and technique* (music painting itself in abstract colour and line), **not** the literal imagery of the 1940 *Fantasia* segment (§2). Showcased with Bach, Toccata & Fugue in D minor, BWV 565 (Stokowski orchestral transcription = the *Fantasia* performance), but built as a reusable preset.

**Family:** painterly / generative (sibling of [Skein](SKEIN_DESIGN.md); see §9).

---

## CONCEPT — REVISED 2026-06-29 (Matt; supersedes the original abstract-voices / flowing-substrate framing below)

After the Ricercar.2 substrate spike, Matt redirected the concept. The original frame — "abstract weaving voices on a flowing colour-field substrate" — was wrong: a *passive* flowing field reads as slick wallpaper, not art (the spike's smooth-blob and ribbon attempts both confirmed it). The locked concept:

**Ricercar is the orchestra painting itself. Each orchestral section has a distinct painterly IDENTITY — colour + weight + texture + material — and the painting is built in sync with the music. Identity is the soul; sync rides on top.** In the spirit of *Fantasia* (art emerging, the music as the invisible painter), elegant and luminous — NOT a depicted artist, NOT Skein's chaotic Pollock drip.

**Built on Skein's painterly mark engine** (D-142 / D-143 / D-149 — the marks-on-top mv_warp canvas with per-mark colour, viscosity/texture, weight, and wet/dry sheen, *proven* to read as paint and M7-loved). Ricercar is the **elegant / luminous sibling of Skein**: the same proven painterly marks, but a *graceful composing painter* (sweeping, composed strokes building a picture) instead of chaotic drip, and a *luminous Fantasia jewel-palette on a light canvas* instead of Skein's earthy drip. It is **not** a new painterly technique (FA #73 — reuse the working reference, don't reinvent).

### The per-section painterly identity — THE design center (Matt, 2026-06-29: "colour, weight, texture, and other qualities per section of the orchestra, then the ability to sync")

"Section" is driven by frequency **REGISTER** — the engine cannot separate instruments (§6, the load-bearing constraint); register-archetypes stand in for orchestral sections (basses live low, flutes live high — register correlates with section). It evokes the orchestra; it does not transcribe it.

| Section (register) | Colour | Weight | Texture / material | Gesture |
|---|---|---|---|---|
| **Basses · cellos · organ pedal** (sub / low) | deep indigo → blue-black | heaviest — broad, slow | dense, matte, smeared (gloopy) | grave, sustained, pooling |
| **Brass — horns · trombones · tuba** (low-mid) | burnished gold / bronze | heavy but burnished | smooth, **metallic gloss** | grand, declamatory arcs |
| **Violas · clarinets · bassoons** (mid) | warm amber / russet | medium | soft-grained, warm matte | flowing, connective, lyrical |
| **Violins · oboes** (high-mid) | scarlet / rose | medium-light | crisp but singing, slight gloss | agile, soaring melodic lines |
| **Flutes · piccolo · harp · bells** (high) | cool cyan / silver-white | feather-light — fine | crisp, **sparkling**, translucent, glinting | quick, darting, shimmering |

Each section differs on **every** axis — colour, weight, texture, gloss, gesture — so the listener reads brass-vs-flutes from the *material*, not just the hue. Skein already varies colour + viscosity + weight + gloss per stem, so these axes are demonstrated-achievable. **Five sections approved (Matt) — richer than the legibility-3 fallback; they stay distinguishable because they differ by weight/texture, not only colour.**

### Sync — the second layer
Each section's marks wake and intensify on its register's **continuous energy** (deviation primitives, D-026 — primary driver); per-band **onsets** flick its accents (Layer 4). The painting builds in step with who is playing. The §3.2 audio-routing table still holds, re-pointed from "voice lines" to "section marks."

### What this revision SUPERSEDES vs RETAINS
- **Superseded:** §1.1 abstract weaving "voices" → per-section painterly **marks** with full material identity. §1.4 flowing colour-field **substrate** (curl-noise flow + decay-to-ground) → **ABANDONED**; the canvas is Skein-style (held / lightly-decaying), painted by section-marks, no passive field (the Ricercar.2 substrate spike code is superseded — git history retains it). §0 / §4 **Filigree compute-agent voices + the Ricercar.3.x integration bridge → likely UNNEEDED** (section-marks use Skein's marks-on-top overlay, not compute-agents — which removes the only engine touch; re-confirm at the build increment).
- **Retained:** §2 reference lock, §3 musical contract / three-act arc, §3.2 audio routing (one-primitive-per-layer, FA #67), §5 audio primitives (all exist), §6 honest constraints (no instrument separation — load-bearing), §8 acceptance, §10 failed approaches.

Everything below predates this revision — read it through the lens above.

---

## IFC.6 — the drive-layer swap: REAL instrument-family capture (2026-07-07, D-177)

R.3 shipped three HAND-FED sections (closed-form `f(time)`, no audio). IFC.6 replaces the hand-feed with the real instrument-family capture (StemFeatures floats 48–55, the preview-clip PANNs sweep sampled by playback position): **each section paints only while its family sounds above its own running mean.** This resolves Matt's Ricercar hold ("unless there is instrument separation, I will hold") — the sections are now driven by actual detected instrument families, not a register proxy alone.

**Section mapping (Matt's IFC.6 product call).** The capture is TIMBRE-family-based (strings / brass / woodwinds / percussion), not register-based — so the painterly sections became the families. **Five sections:**

| Section | Family driver | Colour | Weight / material | Canvas band |
|---|---|---|---|---|
| **Low-strings** | `strings_activity_dev` × low-register frac | deep indigo | heaviest, broad, gloopy/smeared | low |
| **Brass** | `brass_activity_dev` | burnished gold | heavy but GLOSSY (tight edge) | low-mid |
| **Woodwinds** | `woodwinds_activity_dev` | warm russet | medium, soft-grained matte | centre |
| **High-strings** | `strings_activity_dev` × high-register frac | scarlet / rose | medium-light, crisp singing | high-mid |
| **Percussion** | `percussion_activity_dev` | cool teal glint | SPARKLE (flecks on hits, not a weaving line) | scattered |

- **Strings split low/high (the 5th section)** — PANNs is family-level (can't split cello vs violin), so the split is REGISTER-based: partition the strings dev by the 3-band `bass`/`treble` balance so the two register sections **trade** (they sum to the family dev, never double — FA #67). The register ratio is a position mask; gating stays on the strings dev (FA #31). Matt chose 5 (richer) over 4 knowing the split is a proxy.
- **Percussion = sparkle** (Matt's call) — percussion is transient (hits, not a sustained line), so it paints as bright teal flecks on `percussion_activity_dev` spikes, not a weaving stroke. Teal because a light silver-white would vanish on the cream canvas (the reference "bells sparkle" colour reads on light).

**Measured drive constants (IFC.6 dumper corpus — Sym5 / Gran Partita / Clarinet Concerto, NOT guessed).** Per-family dev p99 at `devGain` 2.0: strings 0.45, brass 0.89, woodwinds 0.37, percussion 0.05; the near-zero leader-flap (the IFC.5 finding) lives below the pooled dev p75 ≈ 0.012.
- **Wake floor = 0.04** — kills the flap (real family entries sit ≥ 0.05).
- **Per-section saturation = each family's own dev p99** (strings-split 0.30 partitioned, brass 0.85, woodwinds 0.35, percussion 0.20) — a characteristic strong entry paints FULL regardless of the family's natural loudness (soft-saturate vs p99, not vs 1.0). This normalizes the VISUAL response despite genuinely different per-family dynamic ranges.
- **`devGain` stays 2.0** — confirmed, not changed: brass (the loud, peaky family) p99 0.89 already sits at the band-primitive target (~0.85), and the families' different ranges CANNOT be normalized by a single global gain (lifting woodwinds would clip brass past 1.0). Per-section saturation in the shader is the right normalizer, not the gain.

**Ceilings designed around (IFC.5 §3/§13).** Family-level only (not oboe-vs-clarinet); sustained winds over strings read as strings; buried families approximate (drive off each family's OWN dev); brass absolute over-calls (that's why the design drives off `dev`). The preset is forgiving/evocative, not a transcription. **Layer-5a alignment (accepted):** the family series is the 30 s preview sampled by playback position and CLAMPS past 30 s (family drive freezes on the last window). For a held-canvas painting that BUILDS this is acceptable — a small phase error reads as a small offset, and after 30 s the composition holds with the last-active families. Live-tap PANNs (Layer 5b) is the mitigation, deferred/optional.

**Persistence (IFC.6).** The per-window series is now persisted to `PersistentStemCache` (schema v6) so a disk-cache hit on a local orchestral file replays with its family activity (was in-memory only in IFC.4).

**Wiring.** Shader-only in the preset — the marks VERTEX reads live `StemFeatures` at buffer(1) (already bound by `drawSceneGeometryOverlay`), computes the five activations, flat-passes them to the fragment; no renderer change. The live sampling/install path (IFC.4) is unchanged.

**Status: IFC.6 FAILED live M7 (2026-07-07, Matt, on Beethoven Pastorale local file).** Feedback: "lines do not appear in sync — there is a lag; painting is either a fat line or speckles; boring." **Root cause (diagnosed from the session artifacts `2026-07-07T19-57-59Z`, NOT guessed):**

1. **The lag is structural + the motion was never audio-coupled.** (a) Instrument-family capture is a ~2–4 s-latency signal by construction — a 2 s PANNs window + the smoothing EMA — so a section can't "wake" until seconds after the instrument enters. It answers *which family plays this passage*, never *what happens this beat* (a hard floor, not a tuning knob). (b) Worse, the stroke sweeps on a fixed `f.time` clock; the family signal only *gates* whether it paints. So the motion is music-independent and the paint flickers on/off with a 2–4 s lag → "not in sync, lag." This inverts the Audio Data Hierarchy and Ricercar's own §3.2 (continuous energy should "wake AND steer"). The `stems.csv` family data itself is rich + correct (strings dev 0.59, woodwinds 0.84, trading across the whole 10-min movement, matching the offline dumper) — the capture works; the *consumption* is broken.
2. **Visual poverty.** The mark engine only ever produces one swept capsule per section (the "fat line") + hash-dot sparkles (the "speckles"). It stripped Skein down to almost nothing — no audio-modulated painter clock, no onset bursts, no layered splatter. FA #73: Skein (the sibling, M7-loved) already delivers all of this and Ricercar discarded it.

**Rebuild direction (Matt: "re-wire + enrich", 2026-07-07):** reuse SKEIN's proven painter engine — the CPU-side **audio-modulated painter clock** (`painterTau`, faster on busy passages = the zero-lag motion sync) and the **onset-burst splatter** (beat accents on `*_energy_dev` rising edges) — so motion/rhythm come from the zero-lag continuous-energy + beat signals (felt sync). Instrument-family capture is demoted to **identity only**: it selects the pour/burst **colour + material** (slow, lag-tolerant — colour identity lagging a beat reads fine; motion lagging does not; and Skein freezes colour per-segment so it never recolours mid-stroke). Net: Ricercar becomes Skein's engine recoloured by instrument family. Validate with `RicercarSubstrateTest` fed the REAL failed-session feature stream (not synthetic — FA #27) + contact sheets BEFORE the next M7. **Decided (Matt, 2026-07-07): ONE painter, family-coloured** — a single evolving Skein-grade pour whose colour/material is the currently-dominant instrument family (strings→violet, brass→gold, woodwinds→russet, percussion→teal accents), beat-driven splatter accents, on the light canvas. Lowest-risk: reuse Skein's engine wholesale, swap ONLY the colour source (dominant-stem → dominant-family). 2–3 concurrent painters (counterpoint) is the deferred follow-up if the single painter reads as too simple.

**RW STATUS: code-complete, pending live M7 (2026-07-07, branch `claude/ricercar-rework`).** Built as three increments: **RW.1** — `SkeinState.colorFromFamily` mode (pour/burst colour ← dominant-family D-026 dev argmax over StemFeatures 48–55; flow/motion stay on zero-lag stem energy; Skein byte-identical, `SkeinCanvasHoldTest` 25/25 green). **RW.2** — Ricercar reuses Skein's shader via a new PresetLoader **shader-reuse pass** (a JSON with no sibling `.metal` but an explicit `shader_file` compiles that shared `.metal` — one shader backing many presets, no duplication; Ricercar.json → `shader_file: Skein.metal`, `fragment: skein_fragment`), the app creates the painter state for Ricercar in family mode with a fixed family palette, and the dead `ricercar_*` mark shader (Ricercar.metal) is deleted. App builds; `RicercarSubstrateTest` (reuse + family-colour lock) + preset-count (27) green; lint 0. **RW REJECTED live M7 (2026-07-08):** "just Skein with different tuning — I want Fantasia, this is another version of Skein." Third rejection.

---

## FANTASIA REBUILD — the corrected paradigm (2026-07-08, Matt: "build the flowing/luminous renderer")

**The through-line of all three failures: paint-marks-on-a-flat-canvas was the wrong MEDIUM.** R.2 (flowing field → "slick wallpaper"), IFC.6 (thin capsule marks → lag + boring), RW (Skein drip recoloured → "just Skein"). Every attempt used opaque paint on a flat canvas. **Fantasia is not that** — the curated references (finally read as IMAGES, not annotations, 2026-07-08) are:
- **`01_macro_weaving_lines.jpg`** — clean, **glowing luminous RIBBONS** weaving/crossing gracefully across a soft gradient (the voices). Not paint strokes — glowing light-lines with soft halos.
- **`02_meso_flowing_colour_masses.jpg`** — soft, luminous, **flowing/merging colour MASSES** (ink-in-water billowing, bleeding, dimensional), family-coloured, on a clean light ground (the living substrate).

The 2026-06-29 pivot onto "Skein's marks engine" walked AWAY from these references, and I followed it twice without holding my output next to the images (violating my own checklist rule — mid-session side-by-side vs the named references). **Lesson: when the output doesn't match the reference IMAGE, the fix is not tuning — check the paradigm against the image.**

**The corrected concept (Matt confirmed 2026-07-08):** a **luminous flowing-colour + glowing-ribbons renderer** — NOT the marks family.
1. **Flowing colour masses** = a real GPU **fluid dye simulation** (ink-in-water): family-coloured dye splatted from the sections as they play, advected + billowing + merging + dissipating. This is what gives the ref-02 look that curl-noise-advection alone (R.2) could not.
2. **Glowing weaving ribbons** = smooth curve SDFs with **additive glow/bloom** (ref 01), one per family, luminous, undulating in sync with the zero-lag energy.
3. **Soft, HDR, luminous** throughout — light, not pigment.

**Grounded technique (FA #64/#73 — port the canonical prior art, don't guess):**
- **Fluid dye sim → port [Pavel Dobryakov's WebGL Fluid Simulation](https://github.com/PavelDoGreat/WebGL-Fluid-Simulation)** (16k★, **MIT**, based on Jos Stam "Real-Time Fluid Dynamics for Games"). Passes (ping-pong, Metal compute): advect velocity → curl → **vorticity confinement** (the billowing) → divergence → **pressure Jacobi** (~20–40 iters, incompressible) → gradient-subtract; dye: advect + dissipate + **splat** family colour at section sources. Sim grid ~256²–512² (cheap at 60 fps on M2). This is NEW infra for Phosphene (no fluid sim exists — a genuine renderer paradigm, heavier than a preset tweak).
- **Glowing ribbons →** quadratic-Bezier / sine-path **SDF + additive glow** (colour fading with distance; IQ distance functions), overlaid additively + bloom.

**Plan (my commitment — no more "code-complete, go test live"):**
1. Port the fluid dye sim to Metal compute; build the ribbon glow overlay. **Hand-injected splats / hand-animated ribbons, NO audio yet.**
2. **Render against `01`/`02` early and show Matt frames BEFORE any audio wiring or live test.** The look must clear Matt's eye against the references first.
3. Only then wire music + family capture (family → which colours bloom + which ribbons brighten; zero-lag energy → flow vigour + ribbon undulation + splat force; beats → accents).

**Honest risk:** 0/3 on Ricercar, authored blind; the fluid sim is a substantial from-scratch compute build. De-risked by: a canonical MIT reference to port (not guessing), and rendering against the exact references before any fidelity claim. **This is the next focused increment (RICERCAR-FL), executed methodically with early renders — not rushed.**

**FL status.** **FL.0** ✅ paradigm correction (doc). **FL.1** ✅ Stam kernels in `RicercarFluid.metal`. **FL.2** ✅ `RicercarFluidGeometry` conformer + render gate; renders the ink-in-water look (baked-in fixes: fresh pressure solve each frame, texels/frame velocities ~1–3, small vorticity). **FL.3 ✅ code-complete, pending Matt's eye (2026-07-08):** glowing weaving ribbons (ref 01) — four two-sine-path SDFs, one per family, saturated core + wide soft halo, emissive-over + small additive so cores read as light over dark dye, hand-animated — plus the ref-02 look refinement: sources moved to the top billowing DOWNWARD (ink-drop), overlapping pulses so all hues share the frame, alternating outward lean (wet-into-wet merging), vorticity 0.4→0.8 (teardrops → rolling billows, checked against the dye-tearing mode), sim 480×270, and **density-gradient self-shading** in the display (the Beer-Lambert cover saturates inside a mass → flat sheets; shading shows the roll structure — ref 02's dimensionality). Three render rounds, each judged side-by-side against 01/02. Contact sheets: `/tmp/ricercar_fluid_diag/ricercar_masses_contact_sheet.png` (vs 02) + `ricercar_combined_contact_sheet.png` (vs 01+02); 60 s coverage equilibrates (0.435 → 0.457, no wash-out creep). **The gate is Matt's eye vs the two references, not the green tests.** Open product questions for Matt: ribbon count (4 = one per family; ref 01 shows 3 — percussion could drop to sparkle-accents instead of a ribbon at FL.4), ribbon↔mass relation (currently floating above, threading through the upper masses), mass density/ground tone. **FL.5 ✅ pulled forward (2026-07-08, Matt: “merge and push so i can test”):** Ricercar.json → `passes: [feedback, particles]` + `ricercar_ground_fragment` backdrop (new `Presets/Shaders/Ricercar.metal`), `ParticleGeometryRegistry` + app `makeRicercarGeometry`/`resolveParticleGeometry` (Mitosis mirror); the RW Skein-reuse sidecar is gone and the RW painter wiring is unreachable (cleanup = FL.6). Ricercar in the app now IS the FL.3 hand-animated fluid+ribbons look.

**FL.4 ✅ code-complete, pending live M7 (2026-07-08, Matt cleared the FL.3 look from frames → “proceed”).** Audio wired with the discipline that killed Ricercar 3×:
- **Identity ← family capture** (`*ActivityDev`, StemFeatures 48–55, ~2–4 s latency, lag-tolerant): which family blooms + which of the four ribbons brightens. Per-family soft-saturation vs the IFC.6-measured working points (strings 0.30 / woodwinds 0.35 / brass 0.85 / percussion 0.20) so a characteristic entry paints full regardless of each family's natural loudness.
- **Motion ← zero-lag `bass/mid/trebDev` + `beatComposite`**: global flow vigour (splat force scale), per-beat inflow impulse (bounded ≪ base), and per-ribbon undulation amplitude on the ribbon's own register band (FA #67 — voices weave independently, no shared-beat pumping). Family capture NEVER drives motion (the IFC.6 "lag" failure).
- **Silence-inert:** all-zero features → drive is a no-op, FL.3 look renders byte-identical (gate 0.435/0.457 unchanged).
- GPU contract: `FluidConfig` +8 floats (`rbLevel0–3`, `rbUndulate0–3`; individual floats, no float4 alignment trap). Live path already feeds it (`RenderPipeline+Draw` → `particles.update`, IFC family fields preserved across live stem pushes) — no app change.
- **Validation (honest):** the render test proves the ROUTING fires (a leading family brightens its own ribbon; bounded) + a synthetic-stream contact sheet previews the response shape (`/tmp/ricercar_fluid_diag/ricercar_fl4_audio_contact_sheet.png`). No captured session CSV was available to replay (FA #27), so **audio-musical FEEL is NOT verified — that gate is Matt's live M7** on a track with a cached family series (an orchestral/local file). Tuning constants (surge/force/undulation gains, 0.32 brightness floor) are first-pass, expected to move under Matt's ear.

**FL.6→FL.9 REJECTED; FL.10 = the particle flow-field replaced the fluid medium entirely (2026-07-08).** Everything above (FL.1–FL.5 fluid dye + FL.4 ribbon audio) is **SUPERSEDED** — the fluid-dye medium was itself the wrong paradigm. Rejected: **FL.8** fluid blooms ("soft blobs that grow and fade — pretty basic shit"; the dye field also carries an inherent ~233 ms accumulation lag + static position — it cannot move/snap with the music); **FL.9** drawn "voices" ("the ribbons are now waveforms? … basic shit"). Meta-lesson (FA #64/#73): stop inventing procedural primitives, port a proven craft technique.

**FL.10 — audio-reactive glowing particle flow-field** (Robert Hodgin *Magnetosphere* + the curl-noise glowing-particle standard). `RicercarFlowGeometry` + `Renderer/Shaders/RicercarFlow.metal` **replace** `RicercarFluidGeometry`/`RicercarFluid.metal` (git-mv preserves history) as a `ParticleGeometry` sibling (Physarum/Mitosis contract). Thousands of light particles advect through **curl-noise turbulence + audio force fields** and deposit as **additive glowing sprites** into an **HDR `rgba16Float` light-trail** that decays each frame — the deposit-and-fade trail IS the weaving ribbon of light — tonemapped luminous over a **DEEP/dark ground** (T&F spirit; refs 01/02 are loose mood only, their LIGHT ground misled FL.1–FL.9). Zero-lag band-deviation energy → flow speed + turbulence; `beatComposite` → brightness flare + small random kick (NOT a radial impulse — that made a kaleidoscope; beats accent, never lead — Layer 4 / FA #67); instrument-family capture (StemFeatures 48–55) → per-particle colour identity (lag-tolerant). Removed the dead RW Skein-family-mode app wiring + `ricercarFamilyPalette` (closes the old FL.6 cleanup; `SkeinState.colorFromFamily` stays as an engine feature). Backdrop ground → deep indigo.

**Validation = `RicercarFluidVideoHarness` on real audio** (Beethoven Symphony 7 Allegro through the production FFT→MIR + PANNs family capture). Data-path bugs found + fixed via the harness (not tuning): uninitialised `.private` trail → NaN-in-R/B → pure-green field (clear at init); un-normalised curl gradient → brightness blow-out (normalise the flow to a unit direction); toroidal `fract` wrap → both-seam double-deposit → white edges/corners (wrap in a ±0.07 off-screen margin); centre-radial beat impulse → symmetric starburst (→ random-dir kick + flare). Sync report **INTENSITY r ≈ +0.6** (the glowing light tracks the music's energy); PANNs family capture fires.

**Aesthetic direction — Matt's call (2026-07-08):** shown the full "flowing curtain of light" vs sparse "distinct weaving ribbons" on the real-audio video, Matt chose **sparse weaving ribbons over open dark space** (ref 01 spirit). Tuned there (~1200 bright long-lived particles, dark ground, decay 0.95). **STATUS: ✅ M7 PASSED — Matt live, 2026-07-08: "Fucking brilliant. I love it."** (the first Ricercar concept to clear his eye after R.2/IFC.6/RW = 0/3; the paradigm — glowing particle flow-field over deep space, not paint-on-canvas — was the unlock). **NOT yet certified** — certification is a separate gate (Gate 6 §8: silence-non-black, determinism golden-hash, flash-safety, the `certified: true` flip that arms the rubric + flash gates — cert ≠ flag-flip, per the Nacre lesson). Optional follow-ups (Matt's call, not required): longer/smoother arcs (lower turbulence) if streaks read too curly; loosen/tighten the family vertical zones (teal high / violet mid / gold low).

### FL.11 — beat-locked sync from the cached grid (2026-07-08; Matt: "we can still optimize the sync")

Diagnosed from the live session `2026-07-09T02-11-28Z` (instrument-first, before touching code): the flow field's beat accent read the **live `beatComposite`**, which on a real session is **saturated** — pinned near 1.0, firing on **~95% of frames** → no rhythmic information at all (the FL.10 beat "flare" was effectively always-on). Meanwhile the **cached `BeatGrid`** was cleanly locked the entire session: `beatPhase01` a proper per-beat 0→1 ramp, `lock_state=2`, drift only **±~20 ms** at 143 BPM, `is_downbeat`/`barPhase01` cycling, `pulseAmp01` gating — sitting **unused**. (The session also showed **bass energy + family capture were already dynamic and correct** — the *only* sync gap was the dead beat signal. Two secondary findings, both Matt's environment not the code: the tap was logged **red at −29 dBFS** with **treble essentially absent** — output routing / Normalize / low volume — and went silent at ~2:14:40.)

**Fix (all fields already on `FeatureVector` — zero plumbing):** re-point the beat accent onto the grid — a per-beat pulse from `beatPhase01` (`pow(1−phase, 5)`, sharp on the beat, decaying across it), a stronger accent on the downbeat (`pow(1−barPhase01, 6)`), gated by `pulseAmp01`. It drives (a) a **display-level brightness bloom** (`tone *= 1 + beat·0.20` — crisp because it's applied AFTER the trail, so the decay doesn't smear it; smooth/bounded → flash-safe at the ~2.4 Hz beat rate), (b) a **small on-beat flow surge** (motion sync, no flash risk), and (c) the existing deposit flare + random kick. The saturated `beatComposite` is **retired** from the beat path; continuous `bassDev` energy stays the primary flow driver (beats accent, never lead — Audio Data Hierarchy Layer 4; the FBS D-153→D-158 precedent). **★ Reusable lesson: on a live session the raw `beatComposite`/onset signals are saturated and carry no rhythm — beat-locked visual accents MUST read the cached-grid `beatPhase01`/`barPhase01`/`pulseAmp01`.**

**Validation:** unit test (`test_beatPulse_tracksGridPhase`) proves the pulse blooms on the grid beat (0.92), is quiet mid-beat (0.04), silent at silence (0.00). The video harness gained an **opt-in fixed-BPM grid** (`RICERCAR_BPM`) so a render demonstrates the pulsing — on Beethoven 7 @143.2 the frame-brightness spikes land every ~12.6 frames (the beat cadence) with the downbeats punching harder; INTENSITY r=+0.60 (energy sync preserved). CAVEAT: the fixed harness grid has the right *cadence* but not the onset-calibrated *phase* — the live app's real cached grid is what aligns the pulse to the actual downbeats. **STATUS: superseded by FL.12/FL.13 below (the global beat pulse was removed).**

### FL.12 — coordinated global motion, then FL.13 — per-colour motion from separated stems (2026-07-09)

**FL.11 beat live read (Matt):** *"the colored lines move erratically at once — no coordination, no motion in the same direction — reads like a bunch of things happening at once."* Root cause: each particle sampled the curl field at a **per-particle seed offset** (`+seed*17`), so adjacent lines moved in different directions. **FL.12** removed the seed offset (neighbours sample the same field → coherent currents) + added a shared global drift → the field flowed together.

**FL.12 live read (Matt):** *"flowing the same direction now, BUT the beat makes the lines PAUSE — herky-jerky, motion DISRUPTED not smoothed. If stems are truly separated, each color would behave differently. This is not the way."* Two fixes, and a **measured genre constraint** that shaped them: the PANNs instrument-family capture is **~dead on rock** (Nirvana: strings/brass/woodwinds ≈ 0, only percussion) while the real-time **band-stems (drums/bass/vocals/other) are alive + independent** (devs to 3×) — and the reverse on orchestral. So no single separation differentiates colours cross-genre. Matt chose **HYBRID** (AskUserQuestion).

**FL.13 (head `3a11bfa`, pushed origin + primary checkout `claude/ricercar-rework`):**
1. **Beat REMOVED from the visual** (motion pump + brightness bloom) — a global beat read as herky-jerky. The grid-beat env is still computed + unit-tested (`test_beatPulse_tracksGridPhase`) for a possible future *non-disruptive* accent, but drives nothing now.
2. **Per-colour motion:** each colour has its OWN drift current (own slowly-turning direction, own speed) driven by its own **HYBRID activity env = max(mapped band-stem dev, instrument-family dev)**, warmup-gated, soft-saturated, smoothed ~0.3 s → continuous smooth motion, each colour differentiating on ANY genre. Mapping: strings←(vocals|strings), brass←(bass|brass), woodwinds←(other|woodwinds), percussion←(drums|percussion). The same env drives each colour's brightness. Harness (Beethoven→family path): distinct swirling per-colour currents over dark space, INTENSITY r=+0.69. **STATUS: code-complete, pending Matt's live look on the band-stem (rock) path — which the headless harness can't produce (no Open-Unmix).**

**FL.14 — staccato vs legato LINE CHARACTER (code-complete, pending Matt's live look).** Matt (on Beethoven): staccato/percussive → shorter, choppier lines; strings/sustained → longer, flowing. **Mechanism = per-family particle LIFE** (the cheapest candidate; no new texture/pass). Each colour reads ITS stem's **`AttackRatio`** (baseline ~1.0, sharp peaks ~3.0) via FL.13's colour→stem hybrid (strings←vocals, brass←bass, woodwinds←other, percussion←drums), smoothed ~0.3 s + warmup-gated → a per-family articulation env 0..1. In the shader respawn, `life = mix(16 s legato, 0.75 s staccato, art) × per-particle spread`, **recomputed each frame from the CURRENT env** (so a section turning staccato shortens lines immediately, not after a stale seeded life runs out). Legato → long-lived particles trace long continuous ribbons; staccato → constant respawn turnover reads as short, choppy, restless segments.

**Why life, and why it's safe:** the trail is a single shared-decay texture, so per-colour trail *decay* is impossible — but line **continuity** is governed by how often a particle teleports (respawns to a fresh position, breaking its ribbon). Life controls that. Crucially only the respawn cadence changes; the per-frame MOTION integration (drift + swirl) is byte-identical, so this **cannot** reintroduce the FL.12 herky-jerky (which came from disrupting motion). AttackRatio is a real-time band-stem signal alive on ALL genres → no family fallback needed.

**Signal confirmed (no plumb):** `StemFeatures.{vocals,bass,other,drums}AttackRatio` exist and are populated on the same struct the geometry already consumes; dynamic in the real session (0.31→3.0, baseline ~1.0). **Validation:** `test_articulation_shortensStaccatoLines` — staccato art=1.00 / legato art=0.00, mean particle age **0.38 s (staccato) vs 7.64 s (legato)** (~20× shorter lines); `test_articulation_contactSheet` (RICERCAR_VISUAL=1) renders the side-by-side still (LEFT choppy-dense short strokes / RIGHT long flowing arcs — clearly distinct). Beethoven video harness: no regression, INTENSITY r=**+0.69** (unchanged from FL.13). **Articulation is live-only** — the headless harness can't produce Open-Unmix band-stems (AttackRatio 0 → all-legato = the intact FL.13 field).

**FL.14.1 — recalibration after the first live miss (2026-07-09, session `2026-07-09T19-35-13Z`: "it all looks legato").** Instrumented the session `stems.csv` (root cause measured, not guessed): real AttackRatio is **baseline ~1.0 with brief, sparse spikes** (only ~4 % of frames > 1.5; contiguous clusters < 0.5 s) — and the shipped pipeline (instantaneous `smoothstep(1.05, 2.2)` → 0.3 s symmetric EMA → linear life) collapsed that to a mean articulation env of **0.05** → mean particle life **15.2 s = legato everywhere**. The mechanism was correct; the calibration wasn't. Three fixes (mechanism unchanged): (1) map `smoothstep(1.0, 1.6)` — the real discriminating band; (2) envelope → **fast-attack (τ0.08 s) / slow-release (τ1.5 s) peak-hold** so a burst-dense staccato passage builds and *holds* a high env while legato decays to 0 (the crux — turns sparse transients into a passage-level signal); (3) life interpolates **geometrically** `16·(0.75/16)^art` (life is a timescale — linear left art≈0.5 at ~8 s, still flowing; geometric puts it at ~3.5 s). ★ Verified in simulation on the real session stream *before* shipping: legato sections art≈0.01 → life ~15.7 s; staccato sections art 0.5–0.75 → life 1.6–3.4 s (5–8× ratio, sustained per passage). Regression guard `test_articulation_peakHoldSurvivesSparseBursts` (a 20 %-duty burst stream → art 0.75/life 0.75 s vs flat baseline legato — the exact case the old EMA smoothed to ~0). ★★ LESSON (a [[project_deviation_primitive_real_range]] echo): calibrate against the REAL signal distribution — a "baseline 1.0, peaks 3.0" story hides that the signal is baseline-with-sparse-spikes, and a symmetric smoother of an instantaneous map erases sparse transients; a peak-hold envelope is how sparse per-note events become a section-level character. **Still pending Matt's live eye. Open secondary concern: on orchestral tutti the four band-stems move together (energies ~0.27–0.30 each), so staccato reads at the SECTION level (all colours choppy together), not as one identifiable "strings" line — the FL.13 orchestral stem→family limit; surfaced for Matt's call.**

---

## 0. Verdict

**Feasible today with no new audio/feature primitives and one bounded, audited engine touch.** Ricercar is assembled from two already-certified stacks:

- **Skein's canvas-hold mv_warp** (D-142 / D-143 / D-149): a feedback canvas that accumulates colour, marks-on-top overlay geometry, per-track FNV-1a seed (`lumenTrackSeedHash`). Ricercar reuses this with one deliberate fork from Skein — instead of identity warp + no decay (Skein's permanent drip record), Ricercar uses a **gentle curl-noise flow warp + slow decay** so held colour advects, merges, and breathes (§1.4).
- **Filigree's compute-agent trails** (PHYS.x, certified): N agents that move, steer, and deposit pigment into a ping-ponged trail texture (~0.66 ms/frame @1080p). Ricercar uses a small set (≤8) as its contrapuntal **voices**.

### The one integration — AUDITED, scope confirmed (2026-06-29)

Each stack is certified separately. Ricercar needs the agent layer to deposit into the mv_warp canvas so voice-trails join the flowing field. A pre-design audit (the analogue of the Skein.ENGINE.1 config audit, D-142) read the actual renderer and resolved this to **(B) a bounded engine touch — NOT pure config**:

- Skein's mv_warp canvas (`MVWarpState` ping-pong) and Filigree's agent trail (`PhysarumGeometry`'s private `r16Float` pair) are **isolated texture memories**.
- The render loop assumes particle-mode presets draw **straight to the drawable** and *skips feedback-texture allocation entirely* when `particles != nil` ([`RenderPipeline+Draw.swift`](../../PhospheneEngine/Sources/Renderer/RenderPipeline+Draw.swift) ~line 113, the CLEAN.4.4 comment). So agents cannot deposit into the warp canvas today — there is no shared texture.
- Registry confirms: composing feedback canvas + agent deposit = **Missing** ([RENDER_CAPABILITY_REGISTRY.md](../ENGINE/RENDER_CAPABILITY_REGISTRY.md)).

**The fix is small and named** (~60 lines, zero shader/kernel changes):
- `ParticleGeometry` protocol gains `rendersToFeedbackTexture: Bool` (`false` for Murmuration, `true` for Filigree-as-voice).
- `RenderPipeline+Draw.swift` routes particle render → the current feedback texture (instead of the drawable) when `mvWarpActive && rendersToFeedbackTexture`, then falls through to the existing `.mvWarp` warp/compose/blit.
- `PhysarumGeometry` sets the flag.

This lands as its own infra increment, **Ricercar.3.x**, surfaced to Matt before proceeding (per protocol). The alternative — Filigree re-writing its agents to output to a user-managed texture — is the wrong direction (violates the `PhysarumGeometry`-sibling design, FILIGREE_DESIGN §11) and is rejected.

> **Correction note (vs the original pitch):** the pitch's "zero new engine surfaces for V1" / "one open question to confirm" is **falsified** — the integration is *confirmed needed*, not open. It is bounded and scoped, not an open-ended gamble. Everything downstream of the bridge is pure preset config.

### The spine (against Phosphene's first principle)

> Continuous register energy raises and steers the voices (**primary**). Onsets announce entries and flick accents (**accent**).

Each orchestral register is a *voice* — an independent line of colour that wakes when its register sings, weaves a path while it sustains, and fades when it falls silent. The number of voices weaving at any instant tracks how many registers are sounding. This is the continuous-energy-primary / onset-accent policy (CLAUDE.md §Audio Data Hierarchy) made into counterpoint.

Three axes: **who** is playing (register → orchestral section → colour identity), **when / how much** (energy deviation steers; onsets announce), **what character** (spectral centroid → line crispness; mood → palette).

### The honest caveat (see §6)

Phosphene cannot separate individual orchestral instruments — Open-Unmix yields only vocals/drums/bass/other, all of which collapse to "other" on an orchestral recording. Ricercar therefore **does not transcribe instruments**. It evokes counterpoint through register-banded voice-agents and onset-driven entries. On the target piece this reads true because register density and voice count move together. It is an evocation, not a transcription, and the design never claims otherwise.

---

## 1. Creative architecture — "the orchestra paints itself"

The goal is a canvas a listener can read as counterpoint: watch a low voice enter and weave, hear a second line answer in a brighter register and see a second colour braid in, feel the coda's full chords as every voice converges into one massed gesture. Abstract, painterly, flowing — Fischinger's visual music, not a literal *Fantasia* redraw. **Generative but stable per play** (Matt, 2026-06-29): the same recording always paints the same painting (per-track FNV-1a seed — the Skein/Lumen-Mosaic identity), so it can be tuned and certified; two recordings paint visibly different paintings.

### 1.0 Visual music, grounded — the tradition Ricercar simulates

Cite this section in Ricercar.N sessions rather than reaching for memory.

1. **The line is the voice — counterpoint is the subject.** *Fantasia*'s Bach opener works because it gives the music's own layered, interweaving lines a visual body ("animated lines, shapes and cloud formations," "lacy figures cometing through space, a sky-writing cipher tracing patterns"). Fischinger's prior abstract films are built from discrete moving elements each tied to a musical line, not one undifferentiated field. → Ricercar's headline subject is a small set of independent lines (the **voices**, §1.1), each owned by a register; the flowing colour substrate (§1.4) is the ground they're drawn on.
2. **Colour is identity, assigned — not arbitrary.** In the color-organ tradition (Rimington, Scriabin's *Prometheus*, Fischinger's Lumigraph) a stable music→hue mapping is what lets the eye track a part. → Ricercar binds register → orchestral section → a stable colour family (§1.2). Low = dark heavy voices, high = bright voices, mid = warm middle. The eye learns the code in seconds.
3. **Abstraction over depiction.** Fischinger quit *Fantasia* because Disney pushed his rigorous abstraction toward representational clouds and landscapes. Matt's direction (2026-06-29) is *inspired-by / new abstraction* — closer to Fischinger's original intent than the released film. → No literal orchestra silhouettes, no recognisable clouds/comets; the vocabulary is pure colour, line, flow, accent (§2 anti-references).

Sources: §11.

### 1.1 The voices are the band (the musical role)

**Musical-role sentence** (mandatory, PRESET_SESSION_CHECKLIST Part 2):

> Each orchestral register is a contrapuntal voice — when continuous energy rises in that register (a part entering or sustaining), an independent, register-coloured line of paint wakes, weaves a path whose motion is steered by that register's energy deviation, and persists into the flowing canvas; as more registers sound, more lines braid together, so the listener watches the orchestra's voices enter, interweave, and converge exactly as a fugue stacks its subject.

This names specific musical features (per-register continuous energy, entries/sustains, accumulation of independent lines) and the specific visual behaviour paired with each. It is the spine; if a later increment can't trace a behaviour back to it, the behaviour is wrong.

Three **voice-lanes** (Matt's "by register — orchestral sections"), each a horizontal region, each owning a colour family and 1–2 agent voices:

| Lane | Band (driver) | Section it stands for | Colour family | Canvas region |
|---|---|---|---|---|
| **LOW** | bass / `bassDev` (sub-bass + low-bass refine) | basses, cellos, contrabassoon, organ pedal | deep indigo → midnight blue → violet | lower third |
| **MID** | mid / `midDev` (low-mid + mid-high refine) | violas, horns, bassoons, tenor register | amber → gold → copper | central band |
| **HIGH** | treble / `trebDev` (high-mid + high refine) | violins, flutes, oboes, piccolo | cyan → bright white-gold → cool bright | upper third |

Three lanes (not six) keeps counterpoint legible — the eye can track three braided colours, not six. The 6-band fields refine *vertical position* within a lane; gating is on the 3-band deviation primitives (`bassDev`/`midDev`/`trebDev`), **never** on absolute 6-band energy (FA #31). Each lane's hue jitters within its family (seeded) so two simultaneous voices in one lane stay distinguishable as the same section.

### 1.2 The three-axis mapping

| Axis | Musical input | Visual consequence |
|---|---|---|
| **Who** (which voice) | register → orchestral section | which colour family that line carries, and which lane it lives in |
| **When / how much** | per-register energy deviation (primary) + per-register onset (accent) | deviation wakes & steers the line; onset announces an entry (brief flare) and flicks splatter accents |
| **Character** | spectral centroid, attack sharpness | line crispness / texture: bright → fine, crisp filament; dark → soft, broad, smeared wash |

**Who → colour.** Register owns colour; a line's colour says which section is singing. Bass-heavy music → indigo-dominant canvas; soaring violins → high cyan/gold lines lead. The canvas's colour balance at any instant mirrors the registral balance of the music; its colour history over the piece mirrors the arrangement. Palette is open and tunable — the binding rule is **legibility**: one stable, well-separated colour family per lane, dark-low / warm-mid / bright-high so the eye reads register as vertical colour at a glance.

**When → emission (the spine).** Two channels, mirroring Skein's primary/accent split:
- **Voice channel (PRIMARY):** while a lane's energy deviation is positive (its register sounds above its running mean), that lane's agent(s) are awake — moving, steering, depositing a continuous line of the lane's colour into the canvas. Steering and speed scale with deviation magnitude. Driven by deviation (D-026), never absolute level.
- **Entry / accent channel (ACCENT):** a per-lane onset (`beatBass`/`beatMid`/`beatTreble`) marks a voice entry — a brief bright flare and a quickening at the head of that lane's line. `beatComposite` drives sparse global splatter accents. Accents punctuate; they never carry primary motion (Layer 4 / FA #4).

**Character → crispness.** Spectral centroid sets line texture: bright/airy → thin, fast, finely-dispersing filaments (delicate, slightly translucent so the ground reads through); dark/heavy → broad, slow, smeared washes (opaque, gloopy). A bright fugue subject in the violins looks different from the same subject growled in the basses.

### 1.3 Slow global modulators

**Mood.** Valence → palette warmth/saturation (high → warmer, more saturated; low → cooler, restrained); arousal → overall vigour, how eagerly voices weave, how much the substrate swirls. Smooth valence/arousal **in preset state, never through `setFeatures`** (the Skein/FA #25 convention).

**Structure / three-act feel.** Section boundaries + arousal envelope drive a slow density-and-convergence arc (§3): sparse and gestural when the music is free and thin (the toccata), accumulating and interweaving as voices stack (the fugue), massed and convergent at full tutti (the coda). On arbitrary tracks this rides the engine's existing section/arousal signals; on the target piece it lands as the natural Toccata→Fugue→Coda shape.

### 1.4 The canvas as a flowing colour field (how Ricercar differs from Skein)

Skein's canvas is a permanent record (identity warp, no decay — paint lands and never moves). Ricercar's canvas is a **flowing field** (gentle curl-noise flow warp + slow decay ≈ 0.93–0.96 — colour advects, merges wet-into-wet, slowly breathes out). This is the deliberate aesthetic fork that makes Ricercar painterly visual-music rather than a second drip record (**Matt confirmed, 2026-06-29**):

- Deposited voice-colour is carried by a slow, **divergence-free** flow field (curl noise → swirl without sources/sinks; seeded per track, speed scaled by arousal), so two crossing lines bleed and braid like wet pigment, with the drifting, merging quality of Fischinger's colour masses.
- Slow decay → the canvas is a moving present with a fading memory, not an ever-filling archive — "masses of colour flowing and merging," not a Pollock that only gets denser.
- The voices stay legible on top because they are freshly, opaquely deposited each frame and the ground is their slowly-dissolving wake.

### 1.5 Silence and track change

**Silence:** all lane deviations fall quiet → voices stop emitting and drift to rest; flow field slows; the colour field keeps breathing and slowly dissolves. A paint-on-light-ground preset is bright by construction, so silence-non-black (D-037) is satisfied with no collapse choreography.

**Track change:** canvas and voices reset; the per-track FNV-1a seed re-seeds flow field, lane hue-jitter, agent start positions; a fresh painting begins behind a brief fade-through-ground. Reuse Skein's reset hooks (`resetAccumulatedAudioTime`, per-preset `State.reset`).

---

## 2. Reference decomposition — what we take from *Fantasia*, what we leave

Matt's direction is *inspired-by / new abstraction*, so the 1940 segment is a spiritual reference, not a trait-match target. A curated `docs/VISUAL_REFERENCES/ricercar/` set is assembled before Ricercar.2 — its job is to anchor the abstract-visual-music idiom (Fischinger studies, color-organ stills, abstract-animation frames), with the *Fantasia* Bach segment annotated as inspiration with explicit disregard-these-properties notes.

**Take (the idiom):**
- Independent moving lines each tied to a musical part ("lacy figures cometing," "sky-writing cipher tracing patterns").
- Colour-as-identity; flowing, merging colour masses as the ground.
- Accents as sprays/bursts ("sprays of falling stars") punctuating, not dominating.
- The free→contrapuntal→massed dramatic arc made visual.

**Leave (anti-references — Ricercar must NOT look like these):**
- Literal orchestra silhouettes / the blue-and-gold live-action opening (the faithful-homage path Matt declined).
- Representational depiction — recognisable clouds, landscapes, comets, stars-as-objects.
- Kaleidoscopic symmetry, neon-particle-fountain, clean polka-dot, single-reactive-blob (shared anti-reference list with Skein/Arachne).

---

## 3. Musical contract

### 3.1 The three-act arc (showcased on BWV 565, generalised for any track)

| Act (BWV 565) | What the music does | What the canvas does |
|---|---|---|
| **I — Toccata** (free, improvisatory) | famous descending mordent; dissonant flourishes, broken-chord arpeggios, huge scalar runs over long pedal notes; hands alternating; few simultaneous lines | sparse, high-contrast; one or two bold gestural lines sweep the near-empty ground; arpeggio runs read as fast rising/falling filament cascades; the held pedal is a slow LOW-lane indigo wash beneath |
| **II — Fugue** (counterpoint accumulates) | subject enters voice by voice (exposition D–G–D–G); 3–4 lines interweave; free-fantasia episodes between entries; full 4-voice texture only at the climactic cadences | the heart of the preset: voices enter one lane at a time, each register-coloured; lines braid and bleed in the flowing field; density grows with each entry; episodes thin to fewer voices; cadences flare all lanes at once |
| **III — Coda** (free + full chords) | fugue cadences deceptively in B♭; toccata-style free material returns with full slow chords; grand close | voices converge into massed full-canvas chordal gestures and splatter-washes; motion slows and broadens; the field reaches its richest, then settles on the final cadence |

**Generalisation.** Ricercar does not require a fugue. The arc rides the engine's arousal envelope, section boundaries (`StructuralPrediction`), and textural density = how many lanes carry positive deviation at once. Contrapuntal/layered music lights up multiple lanes and reads richly; sparse music lights few lanes and reads as a quieter painting. It shines on counterpoint and degrades gracefully elsewhere — the honest reusability story behind Matt's "reusable visualizer, tuned to this piece" choice.

### 3.2 Audio routing (one primitive per visual layer — D-026 deviation-normalised; FA #67)

| Visual layer | Single audio primitive | Channel / timescale |
|---|---|---|
| LOW voice wake & steer | `bassDev` | primary / continuous |
| MID voice wake & steer | `midDev` | primary / continuous |
| HIGH voice wake & steer | `trebDev` | primary / continuous |
| Voice vertical position within lane | that lane's 6-band split | character (position only, not gating) |
| Substrate flow speed / swirl | broadband energy deviation + arousal | slow global |
| Substrate decay / breath | arousal | slow global |
| Voice-entry flare | per-lane onset (`beatBass`/`beatMid`/`beatTreble`) | accent (spawn) |
| Global splatter accents | `beatComposite` | accent (per-beat) |
| Line crispness / texture | `spectralCentroid` | character |
| Flare / spray tightness | per-band attack sharpness | character |
| Colour family per lane | register identity | structural |
| Palette warmth / saturation | valence / arousal (smoothed in state) | slow global |
| Density / convergence (3-act) | section boundary + arousal + active-lane count | slow global |
| Voice melodic contour (OPTIONAL, Phase 2) | exposed chroma / melodic-salience pitch (§5) | character |

Every row is a single driving primitive at a single timescale; no two layers share a primitive at the same timescale (the FA #67 audit). Primary motion is continuous deviation; onsets and beats are accents only (Layer 4).

---

## 4. Rendering architecture

A single paradigm, precedented twice over. Per-frame, three stacked layers:

1. **Substrate (flowing colour field).** mv_warp canvas with a gentle curl-noise flow warp (per-vertex displacement; curl noise = divergence-free → swirl without sources/sinks) and slow decay (≈0.93–0.96). Skein's canvas-hold machinery with the warp set to a flow field instead of identity and decay turned partly on. Per-track FNV-1a seed drives the flow field. **Pure preset config of the mv_warp path** (the D-142 config audit applies to this layer).
2. **Voices (the counterpoint).** A small compute-agent set ported from Filigree's trail-agent loop: each lane owns 1–2 agents (cap ~6–8 total). An agent is awake when its lane's `*Dev` is positive; it moves (base wander + steering from its lane's deviation, vertical bias from the 6-band split) and deposits its lane-colour into the substrate canvas so its trail joins the flowing field. Filigree's sense-steer-deposit loop with (a) far fewer agents, (b) agent colour bound to lane, (c) wake/sleep gated by lane deviation. **Port the loop; do not re-derive (FA #73).** The deposit-into-mv_warp-canvas integration is the **Ricercar.3.x** bridge (§0).
3. **Accents (marks-on-top).** Skein's marks-on-top overlay: per-lane onset → brief entry flare at that line's head; `beatComposite` → sparse splatter-sprays. Display-only flares can also live in the comp fragment (Skein's slot-6 preset-buffer adornment path) so they glint without baking into the canvas.

### Draft JSON sidecar (`PhospheneEngine/Sources/Presets/Shaders/Ricercar.json` — values to be tuned)

```json
{
  "name": "Ricercar",
  "family": "painterly",
  "description": "Contrapuntal visual-music painting: each orchestral register is a weaving voice of colour on a flowing field.",
  "author": "Matt",
  "passes": ["direct", "mv_warp"],
  "beat_source": "composite",
  "base_zoom": 0.0,
  "base_rot": 0.0,
  "decay": 0.94,
  "beat_zoom": 0.01,
  "beat_rot": 0.004,
  "beat_sensitivity": 1.0,
  "visual_density": 0.55,
  "motion_intensity": 0.5,
  "color_temperature_range": [0.25, 0.85],
  "fatigue_risk": "low",
  "section_suitability": ["ambient", "buildup", "peak", "bridge", "comedown"],
  "marks": { "...": "entry-flare + splatter overlay config, per Skein.ENGINE.1.1" },
  "certified": false,
  "rubric_profile": "lightweight"
}
```

The compute-agent voices are a render-path branch (like Filigree's particles pass), not expressible purely in the sidecar; `passes` may need to gain the agent/particles path via the Ricercar.3.x bridge. Claude Code wires the agents in the renderer alongside the mv_warp path.

---

## 5. Engine prerequisites

**V1 (Ricercar.1–.7):** no new audio/feature primitives; **one bounded rendering bridge** (Ricercar.3.x, §0). Every audio input the V1 needs already exists and is certified-in-use: 3-band + deviation primitives (`bassDev`/`midDev`/`trebDev`), 6-band, per-band onsets (`beatBass`/`beatMid`/`beatTreble`/`beatComposite`), `beatPhase01`/`barPhase01`, `spectralCentroid`, valence/arousal, the canvas-hold mv_warp + flow-warp + marks-on-top stack (Skein), the compute-agent trail loop (Filigree), and the per-track FNV-1a seed. This clears the session checklist's three-part bar: iconic subject deliverable at fidelity (both constituent stacks certified), clear musical role (§1.1), infrastructure-feasible (no missing primitive; the lone integration is bounded, scoped, and lands early as its own increment).

**Phase 2 (optional, deferred — name it, don't gold-plate V1):** expose pitch to the GPU. `ChromaExtractor` (12-bin, Krumhansl-Schmuckler) is computed but consumed only by the mood classifier — not in `FeatureVector`, not on the GPU. A discrete increment could surface a chroma vector (or a melodic-salience pitch per lane) to the preset, letting each voice trace its register's actual melodic contour (pitch → vertical position) and optionally shade hue by pitch-class. Product framing: "the lines would sing the tune, not just rise and fall with their register's loudness." Matt did not select the pitch/color-organ mapping, so this stays optional and out of V1; flag it as the obvious first enhancement if register-only voices read as too generic.

---

## 6. Known limitations & honest constraints

- **No instrument separation (headline constraint).** Open-Unmix yields vocals/drums/bass/other; an orchestral recording collapses into "other." Ricercar uses frequency **register**, not stems, as its proxy for "which section." It cannot distinguish an oboe from a flute in the same register. Stated, not hidden.
- **Counterpoint is evoked, not transcribed.** Real-time polyphonic voice-separation on arbitrary audio is unsolved; Ricercar does not attempt it. Voice count = active-lane count = textural density, which correlates with the number of sounding parts on real counterpoint but is not a transcription. On BWV 565 this reads true; never describe the design as "following the fugue's voices" in the score-following sense.
- **Cold-start phase (CLAUDE.md contract).** Beat phase may be wrong in the first ~3 s. V1 primary motion is on continuous deviation (frame-1 reliable), so voices wake correctly from the first phrase; entry flares are ungated beat accents (acceptable — a small phase error reads as a small offset).
- **Aesthetic risk = the Skein.3-equivalent.** The real risk is making the weaving lines read as painterly orchestral voices, not "neon spaghetti" or "particle soup." Iteration concentrates here; phase it so a still frame is judged early (§7), judged against the curated reference idiom, never self-assessment.

---

## 7. Phased implementation — Claude Code handoff

House-style increment IDs (Ricercar.N), small commits (`[Ricercar.N] <component>: <desc>`), each ending with the standard Increment Completion Protocol (closeout + `Scripts/closeout_evidence.sh` block, `RENDER_VISUAL=1` contact sheet for visual increments, ENGINEERING_PLAN + RENDER_CAPABILITY_REGISTRY updates, local main commit; push only on Matt's explicit approval). Infra patches land in their own `.x` increment.

- **Ricercar.1 — reference lock (gating, doc-only).** Curate `docs/VISUAL_REFERENCES/ricercar/` (visual-music / Fischinger / color-organ idiom; *Fantasia* Bach segment annotated inspiration, disregard representational traits), README with trait-trustability + §2 anti-references. Per D-064 no later session prompt is written until this exists. *(This design doc + the references README scaffold + plan/registry rows are the Ricercar.1 deliverables.)*
- **Ricercar.2 — substrate spike.** Flowing colour field: mv_warp canvas + curl-noise flow warp + slow decay, seeded per track, hand-fed colour (no audio). Gate-before-the-gate: if it doesn't read as flowing, merging painterly colour, stop and re-tune before adding voices.
- **Ricercar.3.x — integration bridge (infra).** Land the particle-to-feedback-texture routing (§0): `ParticleGeometry.rendersToFeedbackTexture` + the `RenderPipeline+Draw.swift` reroute + `PhysarumGeometry` opt-in. Golden-locked (every other mv_warp/particle preset byte-identical). Surface scope to Matt before proceeding.
- **Ricercar.3 — one voice.** Port one Filigree-class agent depositing a register-coloured line into the substrate, hard-coded motion. Does a single weaving line read as a voice on the flowing ground? Contact sheet.
- **Ricercar.4 — three lanes + audio routing.** Three lanes wired to `bassDev`/`midDev`/`trebDev` (wake/steer), 6-band vertical bias, per-lane onset entry-flares, `beatComposite` splatters, centroid→crispness (the §3.2 table). Counterpoint first appears here — expect the highest aesthetic iteration.
- **Ricercar.5 — mood + three-act arc.** Valence/arousal palette + density/convergence arc on section/arousal signals; verify the Toccata→Fugue→Coda shape on the BWV 565 fixture.
- **Ricercar.6 — silence, track-change, polish.** Rest behaviour, fade-through-ground reset, governor hooks (cap agents + splatter count under budget), soak test.
- **Ricercar.7 — certification.** Acceptance invariants (§8), determinism golden-hash gate, then Matt M7 on live music across ≥5 tracks + the BWV 565 local file.
- **Ricercar.8 (optional) — pitch contour.** The §5 Phase-2 chroma/salience exposure, only if register-only voices read as too generic.

Build the production-grade temporal test alongside the audio increments (the `AuroraVeilMVWarpAccumulationTest` / `SkeinCanvasHoldTest` pattern) — no shader-alone shortcuts for a feedback+agent preset.

---

## 8. Acceptance criteria (Gate 6 preview)

- **Silence-non-black (D-037):** trivially passes (light ground + colour).
- **Counterpoint legibility (headline):** on a contrapuntal fixture, ≥3 distinct register-coloured lines simultaneously trackable by eye during the dense passage; on a sparse fixture, visibly fewer. Active-lane count tracks textural density (assert from `features.csv` lane-deviation columns).
- **Determinism:** same track + seed → dHash-stable final field across two runs (a headline property, as for Skein).
- **Beat/entry ratio:** entry-flare + splatter density on a beat-heavy fixture measurably exceeds a steady fixture.
- **Anti-reference rejection:** must not read as neon-spaghetti / particle-fountain / kaleidoscopic-symmetric / single-reactive-blob (M7 manual until the automated anti-reference gate lands).
- **Performance:** 60 fps at 1080p incl. M1 (light: one mv_warp + ≤8 agents + scissored marks; orders of magnitude lighter than Filigree's 262k agents).
- **M7:** Matt, live, real music ≥5 tracks + the BWV 565 local file — the counterpoint-must-read perceptual gate. Non-negotiable.

---

## 9. Open decisions for Matt

| # | Decision | Recommendation | Status |
|---|---|---|---|
| Name | Ricercar / Stretto / Cantus | **Ricercar** (lineage + "to seek out"); Stretto more legible if wanted | open |
| Family | painterly vs new visual-music family | **painterly** (Skein sibling — Orchestrator variety/fatigue accounting) | open |
| Lanes | three vs more | **three** (low/mid/high) for legible counterpoint; Phase-2 pitch is the better path to "more voices" | open |
| Substrate fork | flowing field vs Skein's frozen record | **flowing field** — **CONFIRMED Matt 2026-06-29** | ✅ resolved |
| Phase-2 pitch contour | now vs later | **later** — ship register-only voices first | open |
| Visible "conductor" locus | faint glints where voices enter, off by default | **try in Ricercar.6 behind a flag** | open |

### One-line feasibility summary for the queue

Ricercar is buildable now with **no new audio/feature primitives** and **one bounded, audited engine bridge** (Ricercar.3.x, ~60 lines) — it's Skein's canvas-hold mv_warp (reconfigured to a flowing field) carrying a small set of Filigree-class agent "voices," one per orchestral register, woken and steered by the 3-band deviation primitives, with onset entry-flares and beat splatters as accents. A single paradigm precedented twice (Skein + Filigree), lighter than either, with clean silence and determinism stories. The real work and risk are in Ricercar.4 — making the braided register-lines read as orchestral counterpoint, not coloured spaghetti.

---

## 10. Failed approaches this design must respect

- **FA #4 / Layer 4** — never drive primary voice motion from raw live onsets (jitter; feedback amplifies it). Voices wake/steer on continuous deviation; onsets only announce and accent.
- **FA #31** — no absolute thresholds on AGC-normalised energy. Lane gating is on `bassDev`/`midDev`/`trebDev`, not on `bass`/`mid`/`treble` levels.
- **FA #67** — one primitive per visual layer per timescale (the §3.2 table is the audit).
- **FA #64 / #73** — ground in the references; port Filigree's agent loop and Skein's canvas-hold recipe rather than re-deriving. "I cited it in the design doc" is not using it — read both presets' code/design before writing Ricercar.3/.4.
- **Reusable-infrastructure / structure-as-substitute discipline** — keep the concept tight; if a defence of keeping a deleted concept invokes "reusable infrastructure," it's wrong.

---

## 11. Sources

**Source material & music**
- *Fantasia* (1940) — Wikipedia: https://en.wikipedia.org/wiki/Fantasia_(1940_film)
- "Bach's Toccata and Fugue: The Fantasia opener that drove Disney to abstraction" — YourClassical/MPR: https://www.yourclassical.org/story/2015/02/27/bach-toccata-fugue-fantasia
- The Walt Disney Family Museum, "Fantasia in Eight Parts: Toccata and Fugue in D minor": https://www.waltdisney.org/blog/fantasia-eight-parts-toccata-and-fugue-d-minor
- Toccata and Fugue in D minor, BWV 565 — Wikipedia: https://en.wikipedia.org/wiki/Toccata_and_Fugue_in_D_minor,_BWV_565
- Netherlands Bach Society (All of Bach), BWV 565: https://www.bachvereniging.nl/en/bwv/bwv-565
- J. S. Bach / Stokowski, Toccata and Fugue — American Symphony Orchestra programme note: https://americansymphony.org/concert-notes/j-s-bach-leopold-stokowski-toccata-and-fugue-in-d-minor/

**Visual-music lineage**
- Oskar Fischinger — Wikipedia: https://en.wikipedia.org/wiki/Oskar_Fischinger
- Visual music / color organ tradition (Rimington, Scriabin *Prometheus*, the Whitneys, Len Lye, Norman McLaren) — Wikipedia: https://en.wikipedia.org/wiki/Visual_music

**Engine grounding (in-repo)**
- [SKEIN_DESIGN.md](SKEIN_DESIGN.md) — canvas-hold mv_warp, marks-on-top, per-track seed, primary/accent split.
- [FILIGREE_DESIGN.md](FILIGREE_DESIGN.md) — compute-agent sense-steer-deposit trail loop (the voice stack to port).
- [RENDER_CAPABILITY_REGISTRY.md](../ENGINE/RENDER_CAPABILITY_REGISTRY.md) — feedback / mv_warp / flow-advection / compute-agent capability statuses; the feedback-canvas + agent-deposit bridge (§0).
- [ARCHITECTURE.md](../ARCHITECTURE.md) §Key Types / §Audio Analysis Tuning — FeatureVector fields, deviation primitives (D-026), chroma extractor (computed, not yet on GPU).
- CLAUDE.md §Audio Data Hierarchy, §Cold-Start Phase Contract, Failed Approaches #4/#31/#64/#67/#73.
</content>
</invoke>
