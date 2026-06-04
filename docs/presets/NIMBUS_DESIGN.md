# Nimbus — volumetric luminous-body preset

**Working name:** *Nimbus* (a nimbus is both a rain-bearing cloud and the luminous halo around a radiant body — single word, house style, captures the gaseous-and-glowing duality). Provisional; your call.
**Lineage:** the first volumetric preset. No Phosphene preset currently *composes* the V.2 Volume tree (`Clouds` / `ParticipatingMedia` / `HenyeyGreenstein` / `Caustics` / `LightShafts`) — the utilities ship and compile but have no production consumer. Nimbus is the proof that a single coherent gaseous body can carry a preset at fidelity.
**Family:** `volumetric` (new family) — or fold under an existing abstract family; see §8.

---

## 0. Verdict

**Feasible today as a pure preset increment. No engine changes. No new render paradigm. Tier 2 (M3+) only.**

Nimbus is a **single-pass 2D direct-fragment volumetric ray-march**: the fragment shader marches a view ray through a procedural density field and composites emission + single-scatter against a dark void. Architecturally it is an ordinary `direct` preset (like Aurora Veil, which ships `passes: []`) — the V.2 Volume utilities are already injected into every preset's shader by the shared preamble (`PresetLoader+Preamble.swift`), so Nimbus *consumes* existing machinery rather than adding any. Density is FBM + `voronoi_smooth`; lighting is single-scatter Henyey-Greenstein with a small light set. There is no second paradigm — no particle pass, no mesh, no feedback. **D-029 is satisfied trivially: `direct` only.**

The spine, and why it fits Phosphene's first principle:

> **Continuous energy breathes the body (primary). Beats ignite embers inside it (accent).**
> The body's mass and luminosity rise and fall with broadband energy deviation — a continuous swell, zero detection delay. Beat onsets are *accents only*: a single internal ember flare, never the primary motion. This is the continuous-energy-primary / beat-onset-accent policy made literal in a volume.

Everything else hangs off **four channels separated by timescale** (§1.2): **Breath** (continuous), **Pulse** (transient), **Mood** (very slow), **Page** (rare). The discipline of the design is *what was cut* — no per-stem roles, no pitch→hue, no spectral-centroid channel, no camera/time drift in v1. One body, one void, four clocks.

---

## 1. Creative architecture — "lighting the music"

The goal is a single luminous gaseous body a listener can *read*: see the music swell in the body's breath, feel each beat as a spark struck inside it, watch its colour temperature drift with the mood, and — rarely — see it reorganise at a section change. Not a reactive fog that twitches per-frame; a body that *behaves*, like a member of the band who happens to be made of light and gas.

### 1.1 The body is a member of the band

There is one coherent volumetric body suspended in a cosmic void. It is not a field of fog filling the frame — it is a *thing*, with a centre of mass, a silhouette, and an interior. The performance is in how it breathes and ignites:

- **Breath (the baseline gesture):** the body inhales and exhales with broadband energy. Loud sustained passages → a larger, denser, brighter body; sparse passages → a smaller, dimmer, more transparent one. Continuous, zero-delay, driven by energy **deviation** (D-026), never absolute level.
- **Ignition (the accent):** on a beat onset, a single ember kindles deep inside the body and flares outward through the medium — the volume self-illuminating from within for a moment, then settling. One ember per onset. This is the accent layer; it must never become the primary motion (FA #33 — onset has jitter; the breath, not the spark, carries the rhythm).
- **Temperature (the slow colour of mood):** valence sets the body's colour temperature (warm/gold high, cool/indigo low); arousal sets internal turbulence (placid vs roiling). Both smoothed in preset state — never written through `setFeatures` (FA #25).
- **Reorganisation (the rare structural beat):** at a *predicted* section boundary, the body performs one slow reorganisation — a single re-form of its mass, not a per-section thrash. Rare by design.
- **Rest:** at silence the body does not vanish to black. It settles to a dim, slow, held breath with a faint surrounding haze — the performer inhaling, waiting (D-037, and the §1.5 floor).

### 1.2 The four channels (separated by timescale)

The whole audio-reactive design is exactly four channels, deliberately separated by *how fast they move* so they never smear into each other:

| Channel | Timescale | Musical input | Visual consequence |
|---|---|---|---|
| **Breath** | continuous | broadband attenuated energy **deviation** (D-026) | body mass / extent + overall luminosity |
| **Pulse** | transient | beat onset | one internal ember flare per onset (accent only) |
| **Mood** | very slow | valence, arousal (smoothed in state) | valence → colour temperature; arousal → internal turbulence |
| **Page** | rare | predicted section boundary (`StructuralPrediction`) | one slow reorganisation of the body's mass |

**Cut for v1** (named so the boundary is explicit, not forgotten): per-stem colour roles; vocals-pitch → hue; a spectral-centroid character channel; any camera move or time-of-day drift. These are V2 candidates (§8). The four-channel discipline *is* the design — adding a fifth before the four read cleanly is the failure mode.

### 1.3 Slow global modulators

- **Mood.** Valence → colour temperature along the palette axis (cool indigo/violet baseline ↔ warm gold/amber peak); arousal → turbulence amplitude in the density field + ember vigour. Smoothed in state (FA #25). Matches the house restrained-baseline ↔ saturated-peak convention (vigour/saturation tracks arousal; warmth tracks valence).
- **Structure.** On `StructuralPrediction` boundaries: one slow mass reorganisation (the body redistributes — a new silhouette settling over ~1–2 s), not a hard cut. Rare; the body should feel continuous within a section.

### 1.4 The body as a single coherent mass — the idea to protect

This is the idea worth protecting, and the thing every increment must defend: **Nimbus is one body, not a fog.** The temptation in volumetric work is to fill the frame with uniform participating media and call it atmospheric — that is the `05_anti_uniform_fog` failure, and it reads as a dead screensaver. Nimbus must always have:

- a **centre of mass** and a legible **silhouette** against the void;
- **negative space** — the cosmic dark is half the image; the body sits *in* it, never fills it;
- **internal structure** — billows, filaments, density variation, so the eye reads volume and depth, not a flat card of haze.

The void is not black-because-empty; it is the negative space that makes the luminous body read. Pure black is the silence-*calibration* reference only, not the steady-playback ground (the steady ground carries a faint haze — §1.5).

### 1.5 Silence and track change

- **Silence:** energy-deviation goes quiet → Breath settles to a dim held floor (slow, shallow density oscillation), Pulse stops kindling embers, turbulence eases. A faint haze remains around the body. `accumulated_audio_time` pauses so any slow drift pauses with it. **Not black** (D-037): the body is still there, dim and breathing slowly — the performer at rest, not gone. This is a *settle*, not a collapse (contrast Ferrofluid's full-silence collapse — Nimbus's silence is the body holding a dim breath, which is both simpler and truer to "a luminous thing that quiets but doesn't die").
- **Track change:** reset internal phase/turbulence/ember accumulators and re-seed the density field from the new track's identity; a brief settle into the new body rather than an instant pop. Reset hooks already exist (`resetAccumulatedAudioTime`, per-preset `State.reset`).

---

## 2. Reference trait matrix (Gate 1)

Locked against the curated set in `docs/VISUAL_REFERENCES/nimbus/` (11 files, one per slot; `CheckVisualReferences` green). Hero: `08_lighting_internal_glow.jpg` (backlit luminous body). Macro anchor: `01_macro_coherent_body.jpg`.

| Trait class | Traits |
|---|---|
| **Macro composition** | One coherent body with a clear centre of mass and silhouette, suspended in a large dark void; the body occupies a *minority* of the frame (negative space dominates); no frame-filling fog. |
| **Meso structure** | Billows and lobes at the body scale; filaments and tendrils peeling off the mass; internal density variation reading as depth, not a flat card. |
| **Micro detail** | Fine wisp feathering at the body's edges; soft fractal turbulence in the interior; edges that dissolve into the void rather than hard-cutting. |
| **Material** | Participating medium: light scatters *through* it (forward-scatter glow when backlit), denser cores occlude, thin edges are translucent; emissive when an ember is lit. |
| **Lighting** | Internal/backlit glow is the signature — the body lit from within or behind so it reads as luminous gas (hero `08`); soft self-shadowing through the denser mass (`08_lighting_self_shadow`); no hard directional studio key. |
| **Motion** | Slow continuous breathing (mass + luminosity); brief internal ember flares on beats; rare whole-body reorganisation; **no fast global drift** of the body in v1. |
| **Audio-reactive** | Breath ← broadband energy deviation (primary, continuous); Pulse ← onset (accent); colour temperature ← valence; turbulence ← arousal; reorganisation ← structural prediction. (Four channels, §1.2.) |
| **Failure modes** | (a) **Uniform fog** — frame-filling, no centre of mass, no negative space (`05_anti_uniform_fog`); the single worst outcome. (b) **Solid surface** — the body reads as an opaque cotton-ball/cumulus blob with a hard lit surface, not a translucent medium (`05_anti_solid_surface`). (c) **Literal sky** — looks like a photographed daytime cloud/sky rather than a luminous body in a void (`05_anti_literal_sky`). (d) **Oil-slick rainbow** — over-saturated iridescent colour banding instead of one coherent mood temperature (`05_anti_oilslick_rainbow`). (e) **Beat-twitch** — embers/Pulse dominating so the body strobes per-beat instead of breathing (fix: Breath primary, Pulse a bounded accent). |
| **Anti-references** (author before coding) | Uniform/flat fog; opaque solid-surface cloud; literal photographed sky; oil-slick/iridescent rainbow banding. (All four present in the folder as `05_anti_*`.) |

---

## 3. Renderer capability audit (Gate 2)

| Required primitive | Registry status | Source / note |
|---|---|---|
| Volumetric density field (FBM + voronoi) | **Supported** | `Utilities/Volume/Clouds.metal` (+ `Utilities/Noise/` fbm, `voronoi_smooth`), injected via the shared preamble. |
| Participating-media march (absorption + in-scatter) | **Supported** | `Utilities/Volume/ParticipatingMedia.metal`. |
| Phase function (forward/back scatter for backlit glow) | **Supported** | `Utilities/Volume/HenyeyGreenstein.metal`. |
| Direct-fragment preset (no extra passes) | **Supported** | Standard compile path; Aurora Veil ships `passes: []`. |
| Per-preset Swift state (breath/turbulence/ember accumulators, seed) | **Supported** | `ArachneState` / `GossamerState` pattern. |
| Continuous band energy (instant + attenuated) | **Supported** | `BandEnergyProcessor` → FeatureVector. Primary driver (Breath). |
| AGC deviation primitives (`xRel` / `xDev` / `xAttRel`) | **Supported** | FeatureVector D-026 fields, MV-1. Required style. |
| Onset pulses | **Supported** | `BeatDetector` → OnsetPulses. Accent-only → Pulse / ember. |
| Mood (valence / arousal) | **Supported** | `MoodClassifier` → `setMood`; smooth in state (FA #25). |
| Structural prediction (section boundary) | **Supported** | `StructuralAnalyzer` / `NoveltyDetector` → `StructuralPrediction`. |
| `accumulated_audio_time` (pauses at silence) | **Supported** | FeatureVector field. |
| Track-change reset hook | **Supported** | `resetAccumulatedAudioTime`, per-preset `State.reset`. |
| MetalFX Temporal upscaling (half-res march → full-res) | **Supported (audit at NB.8)** | Headroom lever for the Tier-2 budget (§6); confirm wired, not just planned, at the perf tranche (Arachne V.8.1 precedent). |

**Nothing Nimbus needs is in the "Missing" column.** The volume utilities exist and are pre-injected; no preset has *composed* them yet, so the only real unknown is performance (§6), not capability.

### 3.1 Confirmed primitive signatures (NB.1 audit — 2026-06-04)

Folded from the NB.1 engine audit; the design decisions in §1/§5 are **unchanged** — only the real names/params Nimbus composes are recorded here:

- **Detail noise:** `fbm4(float3 p, float H = 0.5)` (Noise/FBM.metal), output ≈ [-1, 1]. `fbm8` is the hero workhorse but its own header flags it *"avoid inside inner ray-march loops"* — so the per-step density uses **`fbm4`** (4 octaves, inside the §1 "~4–5 octaves" range). `perlin3d(float3 p)` underlies both.
- **Cellular carve:** `voronoi_3d_f1(float3 p, float scale)` (Texture/Voronoi.metal) — F1 distance, **3D**. The `voronoi_smooth` named in §5.2 is **2D-only** (`voronoi_smooth(float2 p, float scale, float k)`, the IQ C¹ soft-min); there is no smooth-3D variant. The 3D body therefore carves with `voronoi_3d_f1`; a 2D `voronoi_smooth` projection stays available to NB.2 if smoother cell boundaries are wanted. (The decision — "carve cellular voids" — is unchanged; only the function name is reconciled.)
- **Scattering:** `hg_phase(float cosTheta, float g)` + `hg_transmittance(float density, float t, float sigma)` (Volume/HenyeyGreenstein.metal); `struct VolumeSample{float3 color; float transmittance;}` + `vol_sample_zero()` (ParticipatingMedia.metal). The convenience accumulator `vol_accumulate(...)` hardcodes `hg_phase(·, 0.5)` internally — to hold the §5.2 `g ≈ 0.4`, NB.1 composes `hg_phase(·, 0.4)` in a self-written front-to-back loop rather than calling `vol_accumulate`.
- **Self-shadow:** the only existing single-tap helper (`vol_inscatter` → `hg_transmittance` on *local* density) is not directional; NB.1 takes §5.2's first option — a short secondary light-march — but over the **analytic envelope only** (no fbm/voronoi in the shadow taps) so the dense core self-shadows for the 3D read at low cost. Billow-level self-shadow is deferred to NB.2/NB.3.
- **Tonemap:** `toneMapACES(float3)` (ShaderUtilities legacy alias; canonical `tone_map_aces`).
- **Entry / discovery:** `fragment float4 nimbus_fragment(VertexOut in [[stage_in]], constant FeatureVector& features [[buffer(0)]], …)`, declared via the sidecar's `fragment_function`. `direct` presets are bundle-auto-discovered (no registry / engine wiring). Every Volume / Noise / Texture / Color utility is preamble-injected and reachable from a `direct` fragment — confirmed.

No engine gap was found and no §1/§5 decision is altered by this fold.

---

## 4. Gap report (Gate 3)

| Delta | Classification | Notes |
|---|---|---|
| **No preset has exercised the V.2 Volume tree in production** | **Nice-to-have infra; core preset code** | The utilities compile and inject, but Nimbus is the first consumer — expect to discover rough edges (param ranges, performance cliffs) in NB.1–NB.3. Preset authoring, not an engine gap. |
| **Volumetric march cost on Tier 1** | **Blocking for Tier 1 → resolved by exclusion** | A march cannot honour the Tier-1 5 ms / *no-volumetric-clouds* ceiling (SHADER_CRAFT §9.3). Resolution: **Nimbus is Tier 2 only** (§6); `complexity_cost.tier1` set above budget so the Orchestrator drops it on M1/M2. No Tier-1 fallback in v1. |
| **Internal-glow lighting recipe** | **Core preset code** | The signature backlit-glow look (hero `08`) is authored in the shader (light set + HG phase + emission), not an engine addition. Highest aesthetic risk lives here (NB.3). |
| **Ember kindling / flare** | **Core preset code** | Onset-triggered internal emission animated in shader + state. No engine change. |
| **Per-preset state, reset, mood smoothing** | **Not needed** (already supported) | Established patterns. |

**No Blocking gaps for the Tier-2 build.** Classification verdict: *buildable today as a pure preset increment.* The only "blocking" item is Tier-1 feasibility, and the design resolves it by *excluding* Tier 1 rather than starving the march into the uniform-fog failure.

---

## 5. Rendering architecture contract (Gate 4)

### 5.1 Paradigm and the D-029 question

**Single paradigm: 2D direct-fragment volumetric ray-march.** The fragment shader marches a view ray through a procedural medium and composites emission + single-scatter; there is no particle render, no mesh, no feedback, no second pass. `passes: []` (or `["direct"]`), exactly like Aurora Veil. **D-029 is satisfied trivially — one paradigm.** No D-### ratification needed (unlike Skein's canvas-hold note); Nimbus introduces no new pass-combination.

### 5.2 Per-frame pass structure

```
1. SETUP            build view ray per fragment; seed = track identity;
                    read FeatureVector (Breath / Pulse / Mood / Page channels)
2. DENSITY          procedural body density along the ray:
                      • fbm4 + voronoi_3d_f1, shaped to a BOUNDED body
                        (centre of mass + falloff → silhouette, NOT a
                         frame-filling field)
                      • turbulence amplitude ← arousal (Mood)
                      • overall mass / extent ← Breath (energy deviation)
3. MARCH            single-scatter participating-media integration:
                      • absorption + in-scatter per step (Beer-Lambert + VolumeSample)
                      • hg_phase(cosθ, g≈0.4) (forward-scatter → backlit glow)
                      • internal emission term: ember(s) from Pulse, lit deep
                        in the body and flaring outward
                      • light set: 1 key + ambient (internal / backlit bias)
4. COMPOSITE        over the dark void (faint haze floor, never pure black at
                    steady state); colour temperature ← valence (Mood)
                    → ACES tonemap
```

Internal state advances CPU-side each frame (breath integrator, turbulence phase, active embers with decay, mood smoothers, seed), like `ArachneState`. Half-resolution internal march + MetalFX Temporal upscale is the budget lever (§6), validated at NB.8.

### 5.3 State model

- **NimbusState** (Swift) — breath integrator (smoothed energy-deviation), turbulence phase, active-ember list (interior position seed, age, intensity; small cap), smoothed valence / arousal, structural-reorganisation state (target silhouette + interpolation `t`), `rng_seed` (track identity).
- **No GPU-persistent textures.** Nimbus is stateless frame-to-frame on the GPU — the body is recomputed each frame; only CPU-side scalars persist. (Contrast Skein, whose canvas *is* a persistent texture.)
- **Reset** — on track change, reset breath / turbulence / embers, re-seed, settle into the new body.

### 5.4 Audio routing (one primitive per visual layer — all deviation-normalised, D-026)

| Visual layer | Single audio primitive | Channel |
|---|---|---|
| Body mass / extent | broadband energy **deviation** (`bass_att_rel` / broadband `xRel`) | Breath — primary / continuous |
| Body luminosity | same broadband deviation | Breath — primary / continuous |
| Internal ember flare | composite onset pulse | Pulse — accent |
| Colour temperature | valence (smoothed in state) | Mood — slow global |
| Internal turbulence amplitude | arousal (smoothed in state) | Mood — slow global |
| Whole-body reorganisation | `StructuralPrediction` boundary | Page — rare |

One primitive per layer; no layer reads two inputs; nothing reads an absolute level. (The `feedback_audio_layer_one_primitive` discipline, generalised.)

### 5.5 Why direct-fragment (not a staged volume pass)

A dedicated volume *pass* (render-to-volume-texture, then composite) is the textbook approach, but it is unnecessary here and would cost more: Nimbus marches a *single* body with single-scatter lighting, which fits comfortably in one fragment program reading the pre-injected `Clouds` / `ParticipatingMedia` / `HG` utilities. Staying direct-fragment keeps Nimbus an ordinary `direct` preset (no `Package.swift` / pipeline changes, byte-identical compile path to every other preset) and keeps the whole thing in one auditable shader. The cost is paid in march steps, which the half-res + MetalFX lever (§6) covers on Tier 2. **Decision: direct-fragment single-pass; half-res internal march + MetalFX Temporal as the headroom mechanism.** (Revisit only if NB.8 shows the single-pass march can't hit 7 ms even at half-res — then a staged down-res volume pass is the documented fallback.)

### 5.6 Diagnostic / debug views

- **Density-only** view (no lighting) — confirm the body has a centre of mass + silhouette + negative space, not uniform fog. *(The load-bearing guard for the whole preset.)*
- **Step-count heatmap** — march cost per fragment (perf + early-out validation).
- **Ember overlay** — active embers, age, intensity (Pulse correctness).
- **Breath / turbulence scalar trace** — Breath and Mood channel values over time.
- **Silence-floor capture** — confirm dim held breath + haze, non-black.

### 5.7 Acceptance criteria (Gate 6 preview)

- **Silence-non-black** (D-037): silence fixture renders a dim breathing body + haze, measurably non-black; no collapse to pure black.
- **Breath primacy / beat ratio**: on a beat-heavy fixture, body mass/luminosity variance is dominated by the continuous Breath signal; ember flares are bounded accents (Pulse luminosity energy < Breath energy by a set margin) — it breathes, it doesn't strobe.
- **Body coherence**: density-only view shows a single connected mass occupying a minority of the frame across typical fixtures (negative space preserved) — does NOT match `05_anti_uniform_fog`.
- **Mood travel**: high- vs low-valence fixtures produce visibly warm vs cool bodies; high vs low arousal produce visibly different turbulence.
- **Anti-reference rejection**: must not read as uniform fog / solid-surface blob / literal sky / oil-slick rainbow (manual; the automated anti-reference dHash gate is a Missing engine capability, same as Arachne / Skein — M7 judgement).
- **Performance**: Tier 2, 60 fps @ 1080p — full-frame p95 ≤ 16 ms, per-preset GPU ≤ 7 ms, drops (>32 ms) ≤ 1 % (§6).
- **M7**: Matt, live, on real music across ≥5 tracks + a local file — the body-must-breathe / glow-must-read perceptual gate. Non-negotiable, non-bypassable.

---

## 6. Performance

**Nimbus is a heavy preset and the reason it is Tier 2 (M3+) only.** Grounded in the actual ladder:

- **Budget.** Target 60 fps @ 1080p → `FrameBudgetManager` (D-057) full-frame threshold Tier 2 (M3+) 16 ms p95. SHADER_CRAFT §9.3 per-preset ceiling: Tier 2 = **7 ms/preset**. Nimbus's target: per-preset GPU ≤ 7 ms, full-frame p95 ≤ 16 ms, drops (>32 ms) ≤ 1 %.
- **The headroom lever.** A volume march at full 1080p will not fit 7 ms *if its noise is computed per step* (the original assumption). The planned mechanism was a **half-resolution internal march + MetalFX Temporal upscale** to 1080p (§5.5). **NB.1.1 update (§6.1): with `noiseVolume` texture-sampled noise the macro body fits at full res (p50 1.37 ms), so the half-res lever becomes a headroom reserve for later increments rather than a requirement.** Secondary levers remain: step-count cap with early-out on accumulated opacity; bounded body extent.
- **Degradation.** Under the FrameBudgetManager quality ladder (full → noSSGI → noBloom → reducedRayMarch → …), Nimbus uses no SSGI and no bloom, so those rungs are **no-ops**; the live rung is **reducedRayMarch** (fewer steps / lower march res). `QualityCeiling.ultra` exempts the governor.
- **Tier 1 (M1/M2): EXCLUDED.** The Tier-1 ceiling is 5 ms *and explicitly no volumetric clouds* (§9.3). A march cannot honour that, and starving it to fit produces the `05_anti_uniform_fog` failure. **Resolution: set `complexity_cost.tier1` above the Tier-1 budget so the Orchestrator (`DefaultPresetScorer`) excludes Nimbus on M1/M2.** No Tier-1 fallback in v1. `complexity_cost.tier2` is set from the measured NB.8 profile.
- **First validation.** NB.8 measures p50/p95/p99/max via `MTLCounterSet.timestampGPU` on the standard silence / steady-mid / beat-heavy fixtures (`PresetPerformanceTests`). The NB.1 macro spike carries a **budget gate**: if the macro-only body already exceeds 7 ms (Tier 2) before lighting/embers exist, stop and report — a march that can't fit at the maquette stage won't fit certified.

### 6.1 NB.1 macro-only measurement + budget resolution (2026-06-04)

Measured per-preset GPU cost of the NB.1 macro maquette (steady-mid fixture, `NimbusBudgetProbeTests`, command-buffer `gpuEndTime − gpuStartTime`, 160 frames after 40-frame warmup; 64 primary steps, 6-step envelope self-shadow):

| Variant | min | **p50** | mean | p95 | max |
|---|---|---|---|---|---|
| Full 1920×1080 — computed `fbm4`+`voronoi_3d_f1` (original) | 16.0 | 20.2 | 20.4 | 26.0 | 27.8 |
| Half 960×540 — computed (march only) | 6.0 | 7.5 | 7.8 | 10.1 | 12.6 |
| **Full 1920×1080 — `noiseVolume` texture (shipped)** | 1.3 | **1.37** | 1.42 | 1.8 | 1.9 |
| Half 960×540 — `noiseVolume` texture | 0.4 | 0.56 | 0.57 | 0.75 | 0.87 |

(All ms. Hardware: the dev Mac mini, Apple Silicon.)

**Finding (the gate fired).** With per-step *computed* noise the macro-only body was **OVER** the 7 ms ceiling: full-res p50 20.2 ms (~2.9×) and — decisively — **half-res p50 7.5 ms, already over 7 ms for the bare body**, before MetalFX upscale and before NB.2–7 add cost. So the §6 half-res+MetalFX lever could not rescue the budget on its own. **Dominant cost driver:** the per-march-step procedural noise. Diagnosis was sharpened by an experiment: removing `voronoi_3d_f1` (replacing it with a cheap perlin lobe) was a *wash* (20.4 ms) — i.e. the cost was the `fbm4` ALU (4× `perlin3d`/step), not the voronoi.

**Resolution (NB.1.1, same day — Matt directed "make the engineering call and proceed").** Replaced the per-step computed `fbm4` with samples of the preamble-provided **64³ tileable 3D FBM texture** (`noiseVolume`, `[[texture(6)]]`, already production-bound on the direct path via `RenderPipeline+Draw.bindNoiseTextures` → `TextureManager`). Two octaves of turbulence + one low-frequency octave for the billow lobes; the cheap envelope-only self-shadow is unchanged. **Result: full-res p50 1.37 ms — within the 7 ms Tier-2 ceiling at *full resolution*, ~5.6 ms of headroom for NB.2–7; half-res + MetalFX is not required for the maquette.** The look improved (smokier, more delicate fraying — closer to ref 01) as a bonus. This stays inside NB.1's mandate: `noiseVolume` is preamble-injected and production-bound, so the shader merely composes existing machinery; the only test-side change is binding the same texture in `NimbusBudgetProbeTests` + `PresetVisualReviewTests` for parity (FA #66). **Durable lesson: compute-per-step procedural noise does NOT fit Tier-2 at 1080p — budget volumetric noise as a `noiseVolume` texture sample from the start.** NB.2 is unblocked.

---

## 7. Phased implementation sketch (Gate 5)

Increment IDs in house style (`NB.N`), small commits per logical concern (`[NB.N] <component>: <desc>`), push after each increment's verification passes. **Infra patches land in their own `.x` increment before the next preset increment opens.** Full per-increment detail is in `NIMBUS_PLAN.md` (the reviewable plan); this is the sketch.

- **NB.0 — reference lock (gating).** Curated set + README + anti-references + §2 trait matrix, `CheckVisualReferences` green. *Substantially complete this session* (11 files locked; README finalised; D-139 drafted for the authored palette swatches) — NB.0 closes on your sign-off. Per D-064, no NB.1 prompt is written until NB.0 is green.
- **NB.1 — macro maquette.** A single coherent body on the void, framed to `01_macro_coherent_body`, slow time-based drift, minimal single-scatter. No audio, no detail cascade, no glow recipe, no palette. Gate-before-the-gate + budget gate (§6). Highest *feasibility* risk (does the march fit, and does one body read?).
- **NB.2 — meso/micro detail.** Billows, filaments, edge feathering, interior turbulence — to `02` / `03`. Still no audio.
- **NB.3 — lighting / internal glow.** The signature backlit-glow recipe (hero `08`) + self-shadow (`08_lighting_self_shadow`). Highest *aesthetic* risk.
- **NB.4 — Breath + silence floor.** Wire the continuous channel (energy deviation → mass + luminosity) and the dim-held-breath silence floor (D-037).
- **NB.5 — Pulse.** Onset → one internal ember flare. Accent-bounded (must not overwhelm Breath).
- **NB.6 — Mood.** Valence → colour temperature; arousal → turbulence. Smoothed in state (FA #25).
- **NB.7 — Page.** Predicted section boundary → one slow reorganisation.
- **NB.8 — performance tranche.** Half-res + MetalFX validation; step-cap / early-out; `MTLCounterSet.timestampGPU` profile; set `complexity_cost.{tier1 above-budget, tier2 measured}`.
- **NB.9 — certification.** Acceptance invariants (§5.7), golden registration, anti-reference manual check, then Matt M7.

---

## 8. Open decisions for you

Each with my recommendation — the genuine product calls, not an options dump:

1. **Name / family.** "Nimbus" vs your pick; new `volumetric` family vs folding under an existing abstract family. *Recommend:* keep *Nimbus* (the cloud/halo duality is exact) and open a `volumetric` family — it's the first of a likely lineage (the rest of the V.2 Volume tree is unused).
2. **The fifth-channel question (what stays cut).** Per-stem colour roles, pitch→hue, and a spectral-centroid character channel are all cut for v1. *Recommend:* hold the line — certify the four-channel body first. The most defensible V2 addition is a single **per-stem tint** of the body's colour (drum-heavy → cooler, vocal-led → warmer) layered *under* the valence temperature, because it deepens "member of the band" without adding a fast clock. Pitch→hue and centroid are weaker (they fight the single-mood-temperature read).
3. **Ember count / behaviour.** One ember per onset, small active cap. *Recommend:* cap low (≈4–8 concurrent), each flares-and-decays; a dense burst re-introduces the strobe failure. Tune in NB.5 against the beat-ratio criterion.
4. **Structural reorganisation strength (Page).** *Recommend:* subtle — a slow silhouette redistribution over ~1–2 s, not a new body. Page is the rarest channel; if in doubt, under-do it (a section change the listener *feels* more than *sees*).
5. **Silence-floor depth.** How dim is "dim held breath." *Recommend:* dim enough to read as resting (clearly less luminous than any musical passage) but never approaching black — calibrate against the `08` hero at the low end. The faint haze is what keeps it non-black if the body itself gets very dim.
6. **MetalFX dependency.** Nimbus's Tier-2 budget *assumes* half-res + MetalFX Temporal. *Recommend:* accept the dependency (it's the precedented lever) but make NB.8 prove it; if MetalFX isn't actually wired, NB.8 surfaces it before cert, not after.
7. **D-139 (authored palette swatches).** Already drafted this session as a scoped exception for `06_palette_*` only. *No further decision needed* unless you want to swap them for real captures (then D-139 is withdrawn).

---

### One-line feasibility summary for the queue

> Nimbus is buildable now as a **pure preset increment** — no engine changes, single `direct` paradigm (D-029 trivially satisfied), consuming the already-injected V.2 Volume utilities that no preset has yet exercised. It is **Tier 2 (M3+) only** (a volume march can't honour the Tier-1 no-volumetric-clouds ceiling, so the Orchestrator excludes it on M1/M2), and its budget leans on half-res + MetalFX Temporal, proven at NB.8. The silence story is clean (dim held breath, non-black). The real risk is split: *feasibility* at NB.1 (does the march fit 7 ms and does one body read?) and *aesthetics* at NB.3 (the internal-glow recipe).
