# Nimbus — volumetric luminous-body preset

**Working name:** *Nimbus* (a nimbus is both a rain-bearing cloud and the luminous halo around a radiant body — single word, house style, captures the gaseous-and-glowing duality). Provisional; your call.
**Lineage:** the first volumetric preset. No Phosphene preset currently *composes* the V.2 Volume tree (`Clouds` / `ParticipatingMedia` / `HenyeyGreenstein` / `Caustics` / `LightShafts`) — the utilities ship and compile but have no production consumer. Nimbus is the proof that a single coherent gaseous body can carry a preset at fidelity.
**Family:** `volumetric` (new family) — or fold under an existing abstract family; see §8.

---

## 0. Verdict

**Feasible as a preset increment plus ONE bounded engine touch — a baked Perlin-Worley 3D noise texture (Matt-approved). No new render paradigm. Tier 2 (M3+) only.**

> **Direction reset (2026-06-04).** NB.1/NB.2 shipped a Perlin-FBM single-scatter march that rendered a soft, structureless blob (Matt: "falls far short of the references"). Root cause, researched and sourced: Perlin noise *cannot* make billows — the cauliflower structure needs **Worley / Perlin-Worley** noise — and the 3D depth/glow needs the **Beer-Powder + cone-self-shadow** lighting model, not a single ad-hoc key. The fix is to port the canonical **Horizon: Zero Dawn / "Nubis"** volumetric-cloud technique (working code available) rather than keep hand-rolling. The creative concept was also re-grounded: Nimbus is *a glowing ball of cool gas in a void that moves with the music* — no storm, no lightning, no "alive" narrative, no per-beat response. §1 is rewritten to that reality; §7 reflects the port-based build.

Nimbus is a **single-pass 2D direct-fragment volumetric ray-march**: the fragment shader marches a view ray through a procedural density field and composites single-scatter lighting against a dark void. Architecturally it is an ordinary `direct` preset (like Aurora Veil, which ships `passes: []`) — the V.2 Volume utilities are already injected into every preset's shader by the shared preamble (`PresetLoader+Preamble.swift`). Density is a **baked Perlin-Worley 3D texture** (billows) shaped by an analytic envelope; lighting is the ported **HZD / "Nubis"** recipe — **Beer-Powder × Henyey-Greenstein × a short cone self-shadow march**. There is no second paradigm — no particle pass, no mesh, no feedback. **D-029 is satisfied trivially: `direct` only.**

The spine, and why it fits Phosphene's first principle:

> **Continuous energy blooms and flows the gas (primary). Nothing fires on the beat.**
> The body's size, brightness, and flow rate rise and fall with broadband energy deviation — a continuous swell with gas-like momentum, zero detection delay. The activity lives entirely in the continuous flow of the gas; there is no per-beat response (FA #4 / FA #33). This is the continuous-energy-primary policy made literal in a volume.

Everything else is deliberately thin: **Energy** blooms-and-flows it (continuous), **Mood** colours it (valence cool↔warm) and sets its flow agitation (arousal) — and that is all (§1.3). What was cut is the discipline — no per-beat ember, no section reorganisation, no per-stem roles, no pitch→hue, no camera/time drift in v1. One body, one void; energy and mood.

---

## 1. Creative architecture

**Nimbus is a single coherent mass of glowing cool gas, suspended in a black void, that moves with the music.** It is exactly what the reference packet shows — ink blooming in water, lit smoke folding (`01` / `02` / `03`): a dense brighter core, billowing / cauliflower structure, soft wisps feathering into the dark, lit so it glows from within. Nothing beyond that — **no storm, no spark, no creature, no narrative.** The appeal is the appeal of any good abstract visualizer (Milkdrop, a plasma shader, a lava lamp wired to sound): a beautiful luminous volume whose motion is married to the music. Its job in Phosphene is the soft, deep, **atmospheric** preset — the volumetric counterweight to the geometric ones (webs, mosaics, mirrored fluid). That is the whole concept; the discipline is to add nothing the reference images don't show.

### 1.1 What it looks like (grounded in the reference packet)

- A **single coherent body** of luminous cool gas, roughly centred, occupying a *minority* of the frame — the black void is dominant negative space (`01`). Never frame-filling fog (`05_anti_uniform_fog`).
- A **denser, brighter core** falling off to soft **feathered wisps** that dissolve into the void with no hard cutoff (`03`); never an opaque cotton-ball (`05_anti_solid_surface`).
- **Billowing / cauliflower internal structure** with self-shadowed depth (`02`), so the eye reads a 3D volume, not a flat card of haze.
- **Lit from within / behind** so it reads as luminous gas — bright scattering rim, shadowed core (hero `08`).
- **Cool indigo at rest**, warming toward gold as the mood lifts (the `06` palette axis). Never full-spectrum (`05_anti_oilslick_rainbow`).

### 1.2 How it moves

The interesting motion *is the gas itself*: **constant, rich, organic flow** — billows rolling and folding, wisps curling — like the ink-in-water and smoke the references are photos of. It is never still: fine wisps flow continuously, larger billows reorganise over a second or two. This is the motion that has to be mesmerising with the sound off. The music does not bolt extra motion onto a static body — it **shapes this flow.**

### 1.3 How it answers the music

Two drivers, **nothing on the beat** — the activity lives in the continuous gas flow, never in discrete hits (FA #33, FA #4):

| Driver | Timescale | What you see |
|---|---|---|
| **Energy** — smoothed broadband energy vs the track's own baseline (`(bass_att_rel + mid_att_rel + treb_att_rel)/3`, D-026), run through a **fast-attack / slow-release follower** (~150 ms / ~400 ms) for gas-like momentum | continuous — the hero | the mass **blooms** — bigger (~+45 %) and brighter (~+80 %) — and the gas **flows faster and richer** (churn rate ~1×→3.5×). One signal, read as one physical event. |
| **Mood** — valence + arousal, smoothed in state ~4 s (FA #25) | very slow | valence → **colour** cool↔warm (indigo↔gold); arousal → **flow agitation** (lazy/smooth ↔ churning/torn). |

**Cut from v1, deliberately:** anything on the beat (no ember / pulse — the "too much activity" failure); section-boundary reorganisation; per-stem colour roles; pitch→hue; camera / time-of-day drift. The discipline is *energy blooms-and-flows it, mood colours it* — nothing else lands until that reads. (These are V2 candidates, §8.)

### 1.4 The body as a single coherent mass — the idea to protect

This is the idea worth protecting, and the thing every increment must defend: **Nimbus is one body, not a fog.** The temptation in volumetric work is to fill the frame with uniform participating media and call it atmospheric — that is the `05_anti_uniform_fog` failure, and it reads as a dead screensaver. Nimbus must always have:

- a **centre of mass** and a legible **silhouette** against the void;
- **negative space** — the cosmic dark is half the image; the body sits *in* it, never fills it;
- **internal structure** — billows, filaments, density variation, so the eye reads volume and depth, not a flat card of haze.

The void is not black-because-empty; it is the negative space that makes the luminous body read. Pure black is the silence-*calibration* reference only, not the steady-playback ground (the steady ground carries a faint haze — §1.5).

### 1.5 Silence and track change

- **Silence:** energy falls → the mass settles to a **small, dim, slowly-drifting floor** with a faint surrounding haze; the gas flow eases to its slowest drift. `accumulated_audio_time` pauses so the flow pauses with it. **Not black** (D-037): the body is still there, dim and drifting. A *settle*, not a collapse (contrast Ferrofluid's full-silence collapse — Nimbus quiets but doesn't die).
- **Track change:** reset the energy follower / flow phase and re-seed the gas from the new track's identity; a brief settle into the new body rather than an instant pop. Reset hooks already exist (`resetAccumulatedAudioTime`, per-preset `State.reset`).

---

## 2. Reference trait matrix (Gate 1)

Locked against the curated set in `docs/VISUAL_REFERENCES/nimbus/` (11 files, one per slot; `CheckVisualReferences` green). Hero: `08_lighting_internal_glow.jpg` (backlit luminous body). Macro anchor: `01_macro_coherent_body.jpg`.

| Trait class | Traits |
|---|---|
| **Macro composition** | One coherent body with a clear centre of mass and silhouette, suspended in a large dark void; the body occupies a *minority* of the frame (negative space dominates); no frame-filling fog. |
| **Meso structure** | Billows and lobes at the body scale; filaments and tendrils peeling off the mass; internal density variation reading as depth, not a flat card. |
| **Micro detail** | Fine wisp feathering at the body's edges; soft fractal turbulence in the interior; edges that dissolve into the void rather than hard-cutting. |
| **Material** | Participating medium: light scatters *through* it (forward-scatter glow when backlit), denser cores occlude, thin edges are translucent. |
| **Lighting** | Internal/backlit glow is the signature — the body lit from within or behind so it reads as luminous gas (hero `08`); soft self-shadowing through the denser mass (`08_lighting_self_shadow`); no hard directional studio key. |
| **Motion** | Constant rich **gaseous flow** (billows folding, wisps curling) — mesmerising with the sound off; the mass **blooms** (size + luminosity) and the flow speeds up with energy. **No** per-beat events, **no** whole-body reorganisation, **no** fast global drift in v1. |
| **Audio-reactive** | Energy (broadband deviation, D-026, momentum-smoothed) → **bloom** (size + brightness) + **flow rate** — primary, continuous. Valence → **colour** cool↔warm. Arousal → **flow agitation**. **Nothing on the beat.** (§1.3.) |
| **Failure modes** | (a) **Uniform fog** — frame-filling, no centre of mass, no negative space (`05_anti_uniform_fog`); the single worst outcome. (b) **Solid surface** — the body reads as an opaque cotton-ball/cumulus blob with a hard lit surface, not a translucent medium (`05_anti_solid_surface`). (c) **Literal sky** — looks like a photographed daytime cloud/sky rather than a luminous body in a void (`05_anti_literal_sky`). (d) **Oil-slick rainbow** — over-saturated iridescent colour banding instead of one coherent mood temperature (`05_anti_oilslick_rainbow`). (e) **Beat-twitch** — *any* per-beat response, making the body strobe instead of flow; v1 reads nothing on the beat by design. (f) **Sedate blob** — flow too slow/static so it's boring; the gas must visibly churn at all times. |
| **Anti-references** (author before coding) | Uniform/flat fog; opaque solid-surface cloud; literal photographed sky; oil-slick/iridescent rainbow banding. (All four present in the folder as `05_anti_*`.) |

---

## 3. Renderer capability audit (Gate 2)

| Required primitive | Registry status | Source / note |
|---|---|---|
| Volumetric density field (FBM + voronoi) | **Supported** | `Utilities/Volume/Clouds.metal` (+ `Utilities/Noise/` fbm, `voronoi_smooth`), injected via the shared preamble. |
| Participating-media march (absorption + in-scatter) | **Supported** | `Utilities/Volume/ParticipatingMedia.metal`. |
| Phase function (forward/back scatter for backlit glow) | **Supported** | `Utilities/Volume/HenyeyGreenstein.metal`. |
| Direct-fragment preset (no extra passes) | **Supported** | Standard compile path; Aurora Veil ships `passes: []`. |
| Per-preset Swift state (energy follower → `bloom`, flow phase, mood smoothers, seed) | **Supported** | `ArachneState` / `GossamerState` pattern. |
| Continuous band energy (instant + attenuated) | **Supported** | `BandEnergyProcessor` → FeatureVector. Primary driver (Breath). |
| AGC deviation primitives (`xRel` / `xDev` / `xAttRel`) | **Supported** | FeatureVector D-026 fields, MV-1. Required style. |
| Onset pulses | **Supported (unused in v1)** | `BeatDetector` → OnsetPulses. Nimbus reads no beat field — nothing on the beat (§1.3). |
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
| ~~**Ember kindling / flare**~~ | **CUT (§1.3)** | No per-beat response in v1. Removed from the concept. |
| **Per-preset state, reset, mood smoothing** | **Not needed** (already supported) | Established patterns. |

**No Blocking gaps for the Tier-2 build.** Classification verdict: *buildable today as a pure preset increment.* The only "blocking" item is Tier-1 feasibility, and the design resolves it by *excluding* Tier 1 rather than starving the march into the uniform-fog failure.

---

## 5. Rendering architecture contract (Gate 4)

### 5.1 Paradigm and the D-029 question

**Single paradigm: 2D direct-fragment volumetric ray-march.** The fragment shader marches a view ray through a procedural medium and composites emission + single-scatter; there is no particle render, no mesh, no feedback, no second pass. `passes: []` (or `["direct"]`), exactly like Aurora Veil. **D-029 is satisfied trivially — one paradigm.** No D-### ratification needed (unlike Skein's canvas-hold note); Nimbus introduces no new pass-combination.

### 5.2 Per-frame pass structure

```
1. SETUP            build view ray per fragment; seed = track identity;
                    read FeatureVector (Energy + Mood — nothing on the beat)
2. DENSITY          procedural body density along the ray:
                      • Perlin-Worley base (billows) + Worley detail erosion,
                        SAMPLED from the baked 3D texture (never computed per
                        step — §6.1), shaped to a BOUNDED body by the analytic
                        envelope (centre of mass + falloff → silhouette)
                      • flow: the noise domain advects continuously (the gas
                        churn); rate ← Energy bloom, agitation ← arousal (Mood)
                      • overall mass / extent ← Energy bloom
3. MARCH            single-scatter participating-media integration — the HZD /
                    "Nubis" cloud recipe, ported (not hand-rolled):
                      • absorption + in-scatter per step (Beer-Lambert)
                      • Beer-Powder term (bright core / dark edge) × hg_phase
                        (forward-scatter → backlit glow)
                      • cone light-march (~6 steps toward the key) for self-
                        shadowed billow depth — the 3D lump read
                      • brightness ← Energy bloom
4. COMPOSITE        over the dark void (faint haze floor, never pure black at
                    steady state); body colour cool↔warm ← valence (Mood)
                    → ACES tonemap
```

Internal state advances CPU-side each frame (energy follower → bloom, flow phase, mood smoothers, seed), like `ArachneState`. Half-resolution internal march + MetalFX Temporal upscale is the budget reserve (§6), validated at NB.8.

> **NB.3.3 (2026-06-05) — the glow is BACKLIT, never emission.** Lighting is and stays the backlit forward-scatter model above: light scatters *through* the thin edges (the silver-lining rim) while the dense core self-shadows. An NB.3.3 exploration that added an internal **emission** term (an "egg-shaped radiant body" / "incandescent" glow source) was tried and **reverted** — it diverges from the reference packet, which shows a BACKLIT cool body (`08` = a light source *behind/within* the medium, read via scattering *through* it), not an internally-emissive one. Close glow gaps with the back-key / forward-scatter (`kNimbusPhaseG`) / self-shadow-contrast levers — do **not** re-add emission. (Failed-Approach class: adding a mechanic the references don't show — cf. CLAUDE.md FA #62/#63.)

### 5.3 State model

- **NimbusState** (Swift) — energy follower (fast-attack/slow-release → `bloom`), flow phase (accumulated churn time), smoothed valence / arousal, `rng_seed` (track identity). **No ember list, no reorganisation state** — those channels are cut (§1.3).
- **No GPU-persistent textures.** Nimbus is stateless frame-to-frame on the GPU — the body is recomputed each frame; only CPU-side scalars persist. (Contrast Skein, whose canvas *is* a persistent texture.)
- **Reset** — on track change, reset the follower / flow phase, re-seed, settle into the new body.

### 5.4 Audio routing (one primitive per visual layer — all deviation-normalised, D-026)

| Visual layer | Single audio primitive | Driver |
|---|---|---|
| Body mass / extent | `bloom` ← broadband energy deviation `(bass_att_rel+mid_att_rel+treb_att_rel)/3`, fast-attack/slow-release follower | Energy — primary / continuous |
| Body luminosity | same `bloom` | Energy — primary / continuous |
| Gas flow rate (churn) | same `bloom` | Energy — primary / continuous |
| Body colour (cool↔warm) | valence (smoothed in state) | Mood — slow global |
| Flow agitation (smooth↔torn) | arousal (smoothed in state) | Mood — slow global |

The three Energy-driven layers all read one signal (`bloom`) so they move as one physical event; the two Mood layers crawl. **No layer reads the beat.** (The `feedback_audio_layer_one_primitive` discipline, generalised.)

### 5.5 Why direct-fragment (not a staged volume pass)

A dedicated volume *pass* (render-to-volume-texture, then composite) is the textbook approach, but it is unnecessary here and would cost more: Nimbus marches a *single* body with single-scatter lighting, which fits comfortably in one fragment program reading the pre-injected `Clouds` / `ParticipatingMedia` / `HG` utilities. Staying direct-fragment keeps Nimbus an ordinary `direct` preset (no `Package.swift` / pipeline changes, byte-identical compile path to every other preset) and keeps the whole thing in one auditable shader. The cost is paid in march steps, which the half-res + MetalFX lever (§6) covers on Tier 2. **Decision: direct-fragment single-pass; half-res internal march + MetalFX Temporal as the headroom mechanism.** (Revisit only if NB.8 shows the single-pass march can't hit 7 ms even at half-res — then a staged down-res volume pass is the documented fallback.)

### 5.6 Diagnostic / debug views

- **Density-only** view (no lighting) — confirm the body has a centre of mass + silhouette + negative space, not uniform fog. *(The load-bearing guard for the whole preset.)*
- **Step-count heatmap** — march cost per fragment (perf + early-out validation).
- **Energy `bloom` / flow scalar trace** — the energy follower and flow rate over time.
- **Silence-floor capture** — confirm dim, small, slowly-drifting body + haze, non-black.

### 5.7 Acceptance criteria (Gate 6 preview)

- **Silence-non-black** (D-037): silence fixture renders a dim, small, slowly-drifting body + haze, measurably non-black; no collapse to pure black.
- **Energy primacy**: `bloom` (size + brightness) and flow rate visibly track the continuous broadband energy; **no `beat_*` field is read** — nothing fires on the beat (verify by source inspection + a beat-heavy fixture showing no per-beat strobe).
- **Body coherence**: density-only view shows a single connected mass occupying a minority of the frame across typical fixtures (negative space preserved) — does NOT match `05_anti_uniform_fog`.
- **Flow is alive**: the gas visibly churns/folds at all times, including at the silence floor (does NOT read as a static or sedate blob).
- **Mood travel**: high- vs low-valence fixtures produce visibly warm vs cool bodies; high vs low arousal produce visibly different flow agitation.
- **Anti-reference rejection**: must not read as uniform fog / solid-surface blob / literal sky / oil-slick rainbow (manual; the automated anti-reference dHash gate is a Missing engine capability, same as Arachne / Skein — M7 judgement).
- **Performance**: Tier 2, 60 fps @ 1080p — full-frame p95 ≤ 16 ms, per-preset GPU ≤ 7 ms, drops (>32 ms) ≤ 1 % (§6).
- **M7**: Matt, live, on real music across ≥5 tracks + a local file — the body-must-bloom-and-flow / glow-must-read perceptual gate. Non-negotiable, non-bypassable.

---

## 6. Performance

**Nimbus is a heavy preset and the reason it is Tier 2 (M3+) only.** Grounded in the actual ladder:

- **Budget.** Target 60 fps @ 1080p → `FrameBudgetManager` (D-057) full-frame threshold Tier 2 (M3+) 16 ms p95. SHADER_CRAFT §9.3 per-preset ceiling: Tier 2 = **7 ms/preset**. Nimbus's target: per-preset GPU ≤ 7 ms, full-frame p95 ≤ 16 ms, drops (>32 ms) ≤ 1 %.
- **The headroom lever.** A volume march at full 1080p will not fit 7 ms *if its noise is computed per step* (the original assumption). The planned mechanism was a **half-resolution internal march + MetalFX Temporal upscale** to 1080p (§5.5). **NB.1.1 update (§6.1): with `noiseVolume` texture-sampled noise the macro body fits at full res (p50 1.37 ms), so the half-res lever becomes a headroom reserve for later increments rather than a requirement.** Secondary levers remain: step-count cap with early-out on accumulated opacity; bounded body extent.
- **Degradation.** Under the FrameBudgetManager quality ladder (full → noSSGI → noBloom → reducedRayMarch → …), Nimbus uses no SSGI and no bloom, so those rungs are **no-ops**; the live rung is **reducedRayMarch** (fewer steps / lower march res). `QualityCeiling.ultra` exempts the governor.
- **Tier 1 (M1/M2): EXCLUDED.** The Tier-1 ceiling is 5 ms *and explicitly no volumetric clouds* (§9.3). A march cannot honour that, and starving it to fit produces the `05_anti_uniform_fog` failure. **Resolution: set `complexity_cost.tier1` above the Tier-1 budget so the Orchestrator (`DefaultPresetScorer`) excludes Nimbus on M1/M2.** No Tier-1 fallback in v1. `complexity_cost.tier2` is set from the measured NB.8 profile.
- **First validation.** NB.8 measures p50/p95/p99/max via `MTLCounterSet.timestampGPU` on the standard silence / steady-mid / energy-heavy fixtures (`PresetPerformanceTests`). The new budget unknown is the **NB.3 cone self-shadow** (a ~6-step light-march that samples the density each step); re-measure once it lands and apply the half-res + MetalFX reserve if it exceeds the 7 ms Tier-2 ceiling.

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

### 6.2 NB.2 macro+meso+micro measurement (2026-06-04)

The meso/micro detail cascade (NB.2) added body-scale billow lobes, domain-warped micro filaments + edge feathering, and the `kNimbusTurbulence` interior-roil knob — raising the per-step sample count from **3 → 6** `noiseVolume` samples (2 lobe octaves + 1 mid turbulence + 2 domain-warp taps + 1 warped fine octave), all texture-sampled (no computed noise, §6.1 rule held). Same harness/fixture as §6.1:

| Variant | min | **p50** | mean | p95 | max |
|---|---|---|---|---|---|
| **Full 1920×1080 — NB.2 macro+meso+micro (shipped)** | 1.56 | **1.65** | 1.71 | 2.10 | 2.29 |
| Half 960×540 — NB.2 (march only) | 0.58 | 0.73 | 0.74 | 0.86 | 1.04 |

(All ms. Hardware: the dev Mac mini, Apple Silicon. `NimbusBudgetProbeTests`, `NIMBUS_BUDGET=1`.)

**Finding.** Doubling the per-step sample count (3 → 6) cost only **+0.28 ms** (p50 1.37 → 1.65 ms) — the envelope early-out keeps most march steps outside the body (where they pay zero noise cost) and `noiseVolume` taps are near-free vs the retired `fbm4` ALU. **macro+meso+micro p50 = 1.65 ms @ 1080p, 0.24× the 7 ms Tier-2 ceiling, well under the NB.2 ≤ ~3 ms target — ~5.35 ms headroom preserved for NB.3 (lighting) → NB.7 (page).** The half-res-march + MetalFX lever (§6) remains an untapped reserve. **Durable lesson reinforced (§6.1): the cost of detail is the per-step ALU, not the sample count — add octaves freely as `noiseVolume` taps.**

### 6.3 NB.3 lighting + NB.3.3 fidelity-uplift measurement (2026-06-05)

NB.3.2 added the detail-aware **cone self-shadow** (a ~6-step secondary light-march sampling density per step — the budget unknown §6/§6.2 flagged). NB.3.3 then closed the three reference-packet fidelity gaps (Matt-directed, reference-aligned, **backlit model only — no emission**): coverage-gated interior billow contrast (ref 02), a radial denser core (ref 01), +15% on-screen size (focal zoom 1.25→1.44), and the forward-scatter silver-lining glow + brightness lift (ref 08). Same harness/fixture as §6.1/§6.2:

| Variant | min | **p50** | mean | p95 | max |
|---|---|---|---|---|---|
| **Full 1920×1080 — NB.3.3 (shipped)** | 3.20 | **3.27** | 3.41 | 3.88 | 4.15 |
| Half 960×540 — NB.3.3 (march only) | 0.96 | 1.07 | 1.09 | 1.36 | 1.54 |

(All ms. Dev Mac mini, Apple Silicon. `NimbusBudgetProbeTests`, `NIMBUS_BUDGET=1`.)

**Finding.** p50 = **3.27 ms @ 1080p — 0.47× the 7 ms Tier-2 ceiling, WITHIN**, ~3.7 ms headroom for NB.4 (energy) → NB.6 (mood). The rise from NB.2's 1.65 ms is dominated by (a) the NB.3.2 cone self-shadow (the flagged unknown — now measured and comfortably affordable) and (b) the +15% focal zoom putting more body-pixels on screen, each paying the full march. The half-res + MetalFX lever (§6) remains untapped reserve. **No perf action needed at NB.3.3; NB.8 sets `complexity_cost.tier2` from this profile.**

---

## 7. Phased implementation sketch (Gate 5)

Increment IDs in house style (`NB.N`), small commits per logical concern (`[NB.N] <component>: <desc>`), push after each increment's verification passes. **Infra patches land in their own `.x` increment before the next preset increment opens.** Full per-increment detail is in `NIMBUS_PLAN.md` (the reviewable plan); this is the sketch.

- **NB.0 — reference lock.** ✅ Done. Reference framing re-grounded 2026-06-04 — the packet *is* the target (§1), not trait-fragments to disregard.
- **NB.1 — macro maquette.** ✅ Shipped (single coherent body; budget resolved via `noiseVolume`). *Look superseded by the NB.3 cloud-port — Perlin-FBM cannot make billows (§0 Direction reset).*
- **NB.2 — meso/micro detail.** ✅ Shipped (Perlin-FBM detail cascade). *Look superseded by NB.3; the test/prod noise-set parity, debug views, budget probe, and `kNimbusTurbulence` knob it built are all reused below.*
- **NB.3 — the look (cloud-port + fidelity uplift). ✅ DONE 2026-06-05 (Matt-approved on the contact sheet).** Replaced the density + lighting with the ported HZD / "Nubis" technique:
  - **NB.3.0 (infra):** bake a Perlin-Worley 3D texture in `TextureManager` (the one engine touch), auto-bound via `bindTextures` (test paths already get the full set, NB.2 Task 1).
  - **NB.3.1:** density from Perlin-Worley billows + Worley detail erosion, shaped to a bounded body by the envelope. Verify billows in the density-only view.
  - **NB.3.2:** Beer-Powder × HG × ~6-step cone self-shadow march → luminous backlit billows. Verify against the packet.
  - **NB.3.3 — fidelity uplift (Matt-directed, reference-aligned, backlit model only — NO emission):** closed the three reference gaps — coverage-gated interior billow contrast (ref 02, soft rim ref 03), radial denser core for substance (ref 01), +15% on-screen size (focal zoom 1.25→1.44), forward-scatter silver-lining glow + brightness (ref 08). An egg-core / internal-emission / "incandescent" exploration was **reverted** as a divergence from the references (§5.2 note). Budget §6.3.
  - Gate: ✅ matches the reference packet (cool gaseous body, billows, glow, feathered edges) at budget — Matt-approved on the render-vs-packet contact sheet 2026-06-05.
- **NB.4 — Energy: bloom + flow + silence floor.** `NimbusState` energy follower → `bloom` → size + brightness + flow rate; the dim/small/slow silence floor (D-037).
- ~~**NB.5 — Pulse.**~~ **CUT** — nothing on the beat (§1.3).
- **NB.6 — Mood.** Valence → colour cool↔warm; arousal → flow agitation. Smoothed in state (FA #25).
- ~~**NB.7 — Page.**~~ **CUT** — no section reorganisation in v1 (§1.3).
- **NB.8 — performance tranche.** Re-measure with the cone-shadow cost (the new budget unknown); step-cap / early-out; half-res + MetalFX if needed; set `complexity_cost.{tier1 above-budget, tier2 measured}`.
- **NB.9 — certification.** Acceptance invariants (§5.7), golden registration, anti-reference manual check, then Matt M7.

---

## 8. Open decisions for you

Each with my recommendation — the genuine product calls, not an options dump:

1. **Name / family.** "Nimbus" vs your pick; new `volumetric` family vs folding under an existing abstract family. *Recommend:* keep *Nimbus* (the cloud/halo duality is exact) and open a `volumetric` family — it's the first of a likely lineage (the rest of the V.2 Volume tree is unused).
2. **What stays cut (RESOLVED 2026-06-04).** v1 is *energy blooms-and-flows it, mood colours it* — and nothing else (§1.3). Cut: anything on the beat, section reorganisation, per-stem roles, pitch→hue, spectral-centroid, camera/time drift. The discipline is to certify that thin body first. The most defensible V2 addition, if any, is a single **per-stem tint** under the valence colour (drum-heavy → cooler, vocal-led → warmer) — no fast clock added; revisit only post-cert.
3. ~~**Ember count / behaviour.**~~ **CUT** — no per-beat ember (Matt, 2026-06-04: per-beat response is "too much activity"). The activity lives in the continuous gas flow, not discrete hits.
4. ~~**Structural reorganisation strength (Page).**~~ **CUT** — no section reorganisation in v1; it's not in the reference packet and adds a behaviour the concept doesn't need.
5. **Silence-floor depth.** How dim is "dim held breath." *Recommend:* dim enough to read as resting (clearly less luminous than any musical passage) but never approaching black — calibrate against the `08` hero at the low end. The faint haze is what keeps it non-black if the body itself gets very dim.
6. **MetalFX dependency.** Nimbus's Tier-2 budget *assumes* half-res + MetalFX Temporal. *Recommend:* accept the dependency (it's the precedented lever) but make NB.8 prove it; if MetalFX isn't actually wired, NB.8 surfaces it before cert, not after.
7. **D-139 (authored palette swatches).** Already drafted this session as a scoped exception for `06_palette_*` only. *No further decision needed* unless you want to swap them for real captures (then D-139 is withdrawn).

---

### One-line feasibility summary for the queue

> Nimbus is buildable now as a **pure preset increment** — no engine changes, single `direct` paradigm (D-029 trivially satisfied), consuming the already-injected V.2 Volume utilities that no preset has yet exercised. It is **Tier 2 (M3+) only** (a volume march can't honour the Tier-1 no-volumetric-clouds ceiling, so the Orchestrator excludes it on M1/M2), and its budget leans on half-res + MetalFX Temporal, proven at NB.8. The silence story is clean (dim held breath, non-black). The real risk is split: *feasibility* at NB.1 (does the march fit 7 ms and does one body read?) and *aesthetics* at NB.3 (the internal-glow recipe).
