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

> **Motion character — RISING, CURLING SMOKE (Matt's call, NB.3.5, 2026-06-05).** The first NB.4/NB.5 live tests exposed that the motion model was wrong: the gas only *translated* along a fixed slow linear vector — no swirl, no rise, billows never forming/dissolving — so it read as a static blob that slides (Matt: "smoke/cloud means how they move — curling, rising, drifting, with trails"). The chosen character is **rising, curling smoke** (vs drifting cloud / blooming ink): the mass rises, curls into vortices as it rises, and the billows form and dissolve in place. **Motion references** (Matt-provided — the temporal contract the still packet can't carry; a photograph shows what the frame resembles, not how it moves): *"Smoke Effect Overlay Background Video Footage"* (youtube `d_ZAU0535MM`) and *"4K Smoke Effect: Dynamic Moving Dust Cloud Background Video"* (youtube `f0AMzO12Igc`), both Channel Art Background — classic rising-plume smoke-overlay footage (billowing, curling, dissolving upward on black). The NB.3.5 model: vertical domain rise + a height/time helical twist (curl) + an organic low-freq swirl warp + faster-churning fine detail, all on the `flowT` bloom clock (so it rises/curls faster with energy, drifts at silence). **Deferred — literal trails/wake:** a travelling puff leaving a tapering tail needs *temporal persistence* (a feedback pass), which Nimbus is stateless-by-design against (FA #32); without it the rising body elongates/wisps upward (a tapering rising column) but does not leave a lingering screen-trail. Revisit as an explicit architecture decision if the rising-column read isn't enough.

### 1.3 How it answers the music

> **MODEL REVISED — NB.5 (2026-06-05, D-141). The original "nothing on the beat" premise is RETIRED.** NB.4 shipped the energy-only bloom below; the first real-music test (the *Atlas* / Battles session, a relentless 136-BPM track) showed it **too subtle**, and on bass-dominated music structurally broken: the bloom averaged three bands and, with mid (0.04) / treble (0.004) near-silent, the two dead bands vetoed it — the body sat near floor-size all session while the beat (beatComposite fired > 0.5 on 53 % of frames, grid locked) went unanswered. Matt's call: *wrong model — drive from the beat, per stem.* FA #4 still holds — beat is an **accent**, not the primary motion driver — and Nimbus honours it: the slow energy bloom is still the underlying swell; the beat lobes ride on top. (Nimbus has no feedback loop to amplify jitter, the onset pulse is zero-delay, and a gas heave with a soft decay is forgiving of ±80 ms — so a prominent beat-punch is safe here.)

**The band plays the body.** One coherent gaseous mass that HEAVES with the full band — each stem pushes a soft, blended bulge of the *single* envelope (a star-convex deformation that cannot fragment into separate blobs — §1.4). Three timescales:

| Driver | Timescale | What you see |
|---|---|---|
| **Beat — the stems** (NB.5, the hero): each stem's energy **deviation** (D-026), through a fast-attack / slow-release follower. Drums = `max(beatBass, beatComposite)` onset pulse (zero-delay, frame 1) → `drumsEnergyDev`; bass/lead/other = their stem deviation. | per-beat — the hero | **Drums punch + brighten the WHOLE body** (the kick is the spine of the beat). **Bass heaves it DOWN**, **lead/"vocals" flares it UP**, **other swells it to the SIDE** — the body lurches richly with the band, always one cloud. |
| **Energy — the swell** (NB.4): mean of the four stem **energies** (robust; never floored by a dead band — the NB.4 bug), fast-attack / slow-release follower → `bloom`. | continuous — slow | the mass's overall **size** + **brightness** + gas **flow rate** rise and fall with the music's overall energy; settles small/dim/slow at the silence floor (non-black, D-037). |
| **Mood + energy** — valence + arousal smoothed in state ~4 s (FA #25); NB.6 built, **NB.10 amended (D-142)** | very slow | **colour** cool↔warm ← *warmth* = valence **+ energy** (arousal + the bloom swell), so an energetic track reads hot even at neutral/low valence (Matt M7 r1: B.O.B.); arousal → **flow agitation** (lazy/smooth ↔ churning/torn). The bright core keeps its mood hue — no white-wash. |

**Still cut:** section-boundary reorganisation; pitch→hue; camera / time-of-day drift. The discipline is now *the band plays the body (beat, per stem) + energy swells it + mood colours it*.

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

- **NimbusState** (Swift, 32-byte `NimbusStateGPU` at fragment buffer(6)) — the slow energy `bloom` follower + the gas `flowPhase` accumulator (Double) + **four NB.5 stem followers**: `kickPunch` (drums, fast), `bassLobe` / `vocalsLobe` / `otherLobe` (fast-attack/slow-release). Mood smoothers land at NB.6. **No ember list, no reorganisation state** — those channels are cut (§1.3).
- **No GPU-persistent textures.** Nimbus is stateless frame-to-frame on the GPU — the body is recomputed each frame; only CPU-side scalars persist.
- **Reset** — on track change / segment boundary, reset all followers + flow phase so the body settles into the new track.

### 5.4 Audio routing (one primitive per visual layer — deviation-normalised, D-026)

| Visual layer | Single audio primitive | Driver |
|---|---|---|
| Whole-body punch + brightness pop | `kickPunch` ← `max(beatBass, beatComposite)` onset pulse → `drumsEnergyDev` (D-019 warmup blend) | **Beat — drums (NB.5, hero)** |
| Downward heave | `bassLobe` ← `bassEnergyDev` | Beat — bass (NB.5) |
| Upward flare | `vocalsLobe` ← `vocalsEnergyDev` | Beat — lead/"vocals" (NB.5) |
| Sideways swell | `otherLobe` ← `otherEnergyDev` | Beat — other (NB.5) |
| Body size + luminosity + flow rate (slow swell) | `bloom` ← mean of the four stem **energies** (FV bass proxy at warmup) | Energy — slow (NB.4) |
| Body colour (cool↔warm) | **warmth = valence + energy** (energy = arousal + bloom swell) — smoothed in state | Mood + energy — slow global (NB.6, **NB.10 D-142**) |
| Flow agitation (smooth↔torn) | arousal (smoothed in state) | Mood — slow global (NB.6) |

Each layer reads ONE primitive at ONE timescale (FA #67). The four stem lobes are different primitives driving different *spatial regions* of the single body — distinct musical information, not the same signal encoded twice — so they enrich rather than fight. The beat lobes all add into one star-convex envelope deformation: the body lurches per-stem but never fragments (§1.4). **`bloom` no longer uses the 3-band `(bass+mid+treble)` average** — that floored on bass-dominated music (NB.4 / Atlas session); the mean of the four stem energies is the robust replacement.

> **NB.5 reactivity fixes (2026-06-05, second Atlas live test).** Two bugs the live test exposed, both root-caused in the session: **(1) Cold-start freeze (~20 s).** On a cache-hit track the stems are a **constant snapshot** for ~10 s (the live per-frame analyzer hasn't converged) — and because that snapshot carries energy, the old energy-based warmup gate (`smoothstep(totalStemEnergy)`) flipped onto it immediately and **froze** the kick / lobes / bloom on constant values. Fix: gate on **time since track start** (a self-tracked `trackTime` in `NimbusState`, reset on track change — not `features.trackElapsedS`, which the FFO toggle can pin to 100), driving the kick + bloom from the **live FeatureVector beat** (which pulses from frame 1) until the live stems converge (~9–13 s), then crossing over; the directional lobes are `×stemMix`-gated so they ramp in at convergence rather than freezing on the constant snapshot. **(2) Lobes barely fired ("uniform, no direction").** The stem-deviation smoothstep window `[0.30, 1.10]` was mis-calibrated: the deviations sit at ~0.3–0.4 mean and cross 0.8 on only **1–3 % of frames**, so the lobes almost never fired. Fix: window `[0.12, 0.55]` (fires on the real distribution) + bigger heave amplitudes (`kNimbusLobeBulge` 0.30→0.42, `kNimbusKickBulge` 0.20→0.26, `kNimbusKickBright` 0.55→0.72). Regression-locked by `NimbusBloomFollowerTest.test_coldStartGate`. **All values are starting points — Matt's live ear/eye sets the finals.**

### 5.5 Why direct-fragment (not a staged volume pass)

A dedicated volume *pass* (render-to-volume-texture, then composite) is the textbook approach, but it is unnecessary here and would cost more: Nimbus marches a *single* body with single-scatter lighting, which fits comfortably in one fragment program reading the pre-injected `Clouds` / `ParticipatingMedia` / `HG` utilities. Staying direct-fragment keeps Nimbus an ordinary `direct` preset (no `Package.swift` / pipeline changes, byte-identical compile path to every other preset) and keeps the whole thing in one auditable shader. The cost is paid in march steps, which the half-res + MetalFX lever (§6) covers on Tier 2. **Decision: direct-fragment single-pass; half-res internal march + MetalFX Temporal as the headroom mechanism.** (Revisit only if NB.8 shows the single-pass march can't hit 7 ms even at half-res — then a staged down-res volume pass is the documented fallback.)

### 5.6 Diagnostic / debug views

- **Density-only** view (no lighting) — confirm the body has a centre of mass + silhouette + negative space, not uniform fog. *(The load-bearing guard for the whole preset.)*
- **Step-count heatmap** — march cost per fragment (perf + early-out validation).
- **Energy `bloom` / flow scalar trace** — the energy follower and flow rate over time.
- **Silence-floor capture** — confirm dim, small, slowly-drifting body + haze, non-black.

### 5.7 Acceptance criteria (Gate 6 preview)

> **NB.9 gate map (2026-06-05).** Each criterion below now cites its automated gate (or notes M7-manual). The **Energy primacy** bullet was rewritten — the original "no `beat_*` is read — nothing fires on the beat" was the pre-NB.5 contract; D-141 reversed it (the beat now drives the body as a *bounded accent*). All gates pass; the open gate is M7.

- **Silence-non-black** (D-037): silence fixture renders a dim, small, slowly-drifting body + haze, measurably non-black; no collapse to pure black. *Gate: `NimbusBloomFollowerTest.test_renderTracksBloom` (silence mean luma > 0.003) + `test_followerAsymmetry` (settles, never collapses).*
- **Energy primacy + beat as bounded accent (D-141)**: `bloom` (size + brightness) and flow rate track the continuous broadband energy — the *primary* driver (the silence→energy frame is bigger + brighter). The beat rides **on top** as a bounded accent: the whole-body kick punch (`kNimbusKickBulge` 0.26 / `kNimbusKickBright` 0.72) + the per-stem directional lobes — FA #4 honoured (accent, never the primary motion driver; safe on Nimbus — no feedback loop, zero-delay pulse, soft-decay heave). The **shader reads no raw `beat_*` field** (source-verified: it reads only `aspect_ratio` from `FeatureVector`; the kick reaches it as `kickPunch`, a bounded CPU-follower output at slot 6). *Gate: `test_renderTracksBloom` (bloom→size/bright) + `PresetAcceptanceTests` invariant 3 (Nimbus included; beat-vs-continuous response bounded) + source inspection.*
- **Body coherence**: a single connected mass occupying a minority of the frame, negative space preserved — does NOT match `05_anti_uniform_fog` (the single worst outcome, §1.4). *Gate: `test_bodyCoherenceNegativeSpace` — at the absolute worst case (full bloom + max kick + all three lobes) coverage 0.668 < 0.80 ceiling AND corner/centre 0.082 < 0.30 (dark corners = real negative space) + `test_stemLobes` "one mass holds" (every per-stem fixture stays a present, non-fragmented body).*
- **Flow is alive**: the gas visibly churns/folds at all times, including at the silence floor (does NOT read as a static or sedate blob). *Gate: `test_followerAsymmetry` (flowPhase advances monotonically even at the silence floor — the gas clock never freezes).*
- **Mood travel**: high- vs low-valence → visibly warm vs cool bodies; high vs low arousal → visibly different flow agitation. *Gate: `test_moodTravel` — valence R/B 0.71→1.79 (warm > cool × 1.3) AND arousal calm↔wild MSD 84.3 (the agitation route carries signal).*
- **Anti-reference rejection**: must not read as uniform fog / solid-surface blob / literal sky / oil-slick rainbow. *M7 judgement (no automated anti-reference dHash gate — Missing engine capability, same as Arachne / Skein). Artifact: the `RENDER_VISUAL=1` contact sheet renders the body beside the 3 TRUST refs + 2 AVOID anti-refs — the render clearly rejects both the flat fog and the opaque cumulus.*
- **Performance**: Tier 2, 60 fps @ 1080p — full-frame p95 ≤ 16 ms, per-preset GPU ≤ 7 ms, drops (>32 ms) ≤ 1 % (§6). *Gate: `NimbusBudgetProbeTests` worst-case (the shipped half-res path: p50 **2.56 ms**, max 3.6 ms — within the 7 ms ceiling) + the M6 rubric on `complexity_cost.tier2` = 4.0. Full-res worst-case is 7.88 ms, which is why NB.8 ships the half-res path (§6.7).*
- **M7**: Matt, live, on real music across ≥5 tracks + a local file — the body-must-bloom-and-flow / glow-must-read perceptual gate. **Non-negotiable, non-bypassable — the open gate.**

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

### 6.4 NB.4 Energy bloom measurement (2026-06-05)

NB.4 added the Energy coupling — a CPU-side fast-attack/slow-release follower
(`NimbusState`) → `bloom`, flushed to a 16-byte `NimbusStateGPU` at fragment
buffer(6). The shader consumes `bloom` for body extent (uniform `bodyScale`
inflation), luminosity (`bright` scale on the back-key + ambient), and
`flowPhase` for the gas drift (replacing wall-clock `features.time`), plus the
non-black haze floor. The probe primes the follower to the steady-mid converged
bloom (~0.5 → `bodyScale` ≈ 0.98 ≈ the NB.3 body size) so this number is
directly comparable to §6.3. Same harness/fixture (`NimbusBudgetProbeTests`,
`NIMBUS_BUDGET=1`, the slot-6 buffer now bound for parity — FA #66):

| Variant | min | **p50** | mean | p95 | max |
|---|---|---|---|---|---|
| **Full 1920×1080 — NB.4 steady-mid (shipped)** | 2.64 | **2.66** | 2.67 | 2.72 | 3.03 |
| Half 960×540 — NB.4 (march only) | 0.79 | 0.92 | 0.93 | 1.06 | 1.62 |

(All ms. Dev Mac mini, Apple Silicon.)

**Finding.** p50 = **2.66 ms @ 1080p — 0.38× the 7 ms Tier-2 ceiling, WITHIN**,
~4.3 ms headroom for NB.6 (mood). The Energy follower is **CPU-side and adds no
GPU cost**; the shader's added work is a handful of multiplies (`bodyScale`,
`bright`, the haze term), negligible against the march. The number sits within
run-to-run thermal variance of §6.3's 3.27 ms (the steady-mid body at bloom ~0.5
is ~0.98× the NB.3 size). **Worst case is full bloom** (`bodyScale` 1.16 →
body projected area ~1.35× → ~3.6 ms estimated), still ~0.51× the ceiling. No
perf action at NB.4; the half-res + MetalFX lever (§6) remains untapped reserve.

### 6.5 NB.5 stem beat-lobes measurement (2026-06-05)

NB.5 added the per-stem envelope heave: the `nimbus_envelope` now applies a
star-convex bulge (`rr / (1 + kick + Σ lobe·cos²)`) — evaluated on every march
AND cone-shadow sample (~7× per in-body step). Same harness/fixture (steady-mid,
slot-6 bound; lobes at zero on the probe — the baseline body):

| Variant | min | **p50** | mean | p95 | max |
|---|---|---|---|---|---|
| **Full 1920×1080 — NB.5 (shipped)** | 3.65 | **3.74** | 3.88 | 4.38 | 5.02 |

(All ms. Dev Mac mini, Apple Silicon. `NimbusBudgetProbeTests`, `NIMBUS_BUDGET=1`.)

**Finding.** p50 = **3.74 ms @ 1080p — 0.53× the 7 ms ceiling, WITHIN**, ~3.3 ms
headroom for NB.6 (mood). The ~+0.5 ms over NB.3.3's 3.27 ms is the per-step
envelope deformation (3 dot + 3 mul-add + a divide). **Perf lesson:** the first
cut used `pow(cos, 1.5)` for the lobe falloff and the budget **doubled to 5.15 ms**
— a general `pow()` evaluated ~7× per sample is brutal, and the GPU *predicates*
(does not skip) the `if`-guard around it, so the cost is paid even when no lobe
is active. `sqrt` (cos^1.5 = c·√c) cut it to 4.58 ms; **cos² (pure mul-adds)** to
3.74 ms. Rule: in a per-march-step function, never use `pow()`/transcendentals
for a falloff — use a polynomial (cos², smoothstep). The bound grows by the live
bulge (~+44 % on a max simultaneous heave) so the active-lobe worst case is a
little higher, still well under budget. NB.8 sets `complexity_cost.tier2` from
this profile; the half-res + MetalFX lever remains untapped reserve.

### 6.6 NB.3.4/.5 smoke qualities (texture + motion) measurement (2026-06-05)

NB.3.4 (crisper texture: a 2-octave fractal Worley detail cascade + interior
cauliflower carve + tighter lump/crevice contrast) and NB.3.5 (rising/curling
smoke motion: vertical rise + helical twist + a 2-octave organic swirl warp +
faster-churning detail + bigger base billows) were authored after the NB.5 live
test exposed that the body read as a static blurry blob (Matt). Same harness:

| Variant | p50 | notes |
|---|---|---|
| Naïve (full cascade + swirl in the shadow march, 96 steps) | **20.3 ms** | 2.9× OVER — the cone self-shadow paid the full ~7-sample density 6× per in-body step |
| **Shipped (cheap shadow + 64 steps + 2-oct cascade + 10% smaller blob)** | **3.78 ms** | 0.54× the ceiling, WITHIN (~5.7 ms full-bloom worst case) |

**Perf lessons (durable, reusable).** Getting from 20 ms → 3.78 ms was three
moves, biggest first: **(1) a cheap shadow density** — the cone self-shadow runs
~6× per in-body sample and only needs the COARSE density (lit top vs shadowed
underside), so `nimbus_density_shadow` is the base billow only (1 sample) vs the
lit path's ~7; this was the dominant win. **(2) Don't over-step** — 96→64; a
march resolves detail only up to ~Nyquist of its step count, so the scale-7.6
detail octave just *aliased* at 64 steps (dropped it: cheaper AND less noisy).
**(3) Smaller on-screen body** (Matt-directed, focal 1.44→1.30, ~10% smaller →
~19% fewer body-pixels do the expensive march). General rule for a volumetric
march: the self-shadow march is the cost centre — give it a cheap density; match
step count to the finest octave you actually keep; on-screen area is a linear
budget lever. NB.8 sets `complexity_cost.tier2` from this profile; the half-res +
MetalFX lever remains the untapped reserve.

### 6.7 NB.8 perf tranche — half-res path + worst-case profile (2026-06-05)

The 2nd Atlas live session exposed that §6.1–6.6 all **under-measured**: they
primed the budget probe to the *steady-mid* body, but the live cost is dominated
by the body **swelling to fill the frame** at full energy. Live `frame_gpu_ms`:
**mean 6.84 ms, max 14.53 ms, 56 % of frames over the 7 ms ceiling.** The probe
was corrected to prime the WORST case (full bloom + max kick + max lobes):

| Variant (worst-case body) | p50 | max |
|---|---|---|
| Full 1920×1080 (the live problem) | **7.64 ms** | 9.1 ms (probe) / 14.5 ms (live) |
| **Half 960×540 march (the NB.8 fix)** | **2.57 ms** | 3.35 ms |

**The lever (implemented): a half-resolution direct-render path.** The §5.5 /
README "half-res march + MetalFX Temporal" reserve was never wired (no MetalFX in
the codebase, and MetalFX Temporal needs motion vectors a procedural volume
lacks). NB.8 instead renders Nimbus's fragment to a `0.5×` offscreen texture and
**bilinearly upscales** to the drawable (`feedback_blit` + the linear-clamp
sampler) — ~4× cheaper (the soft gas tolerates the upscale; the freed budget went
back into march quality). Opt-in per-preset via `RenderPipeline.setDirectRenderScale(0.5)`
(every other preset stays full-res); `drawDirect` branches on it (the shared
binding contract lives in `encodePresetVisualization`). Worst-case is now ~2.6 ms
march + ~0.3 ms upscale ≈ **3 ms (p50) … 3.6 ms (max), well under the 7 ms
ceiling.** `complexity_cost.tier2` set to **4.0** (was 6.0 provisional); `tier1 =
9.0` keeps the Orchestrator excluding Nimbus on M1/M2. **Durable rule:** a
volumetric preset's budget must be measured at its WORST on-screen body (full
swell), not the steady state — the steady-mid prime under-measured by ~4×.

### 6.8 NB.8 beat-sync tightening (2026-06-05)

The same session: "beat could be tighter." Diagnosis (grid locked 83 %,
`beatPhase01` clean): the kick fired off the *onset pulse*, which lags the beat
~80–120 ms (detection + follower). Fix: drive the kick from the **predicted grid
beat** — an anticipatory pulse `smoothstep(0.82, 1.0, beatPhase01)` that rises in
the last ~18 % of each beat and peaks ON it; the zero-delay onset (`max(beatBass,
beatComposite)`) is the fallback when the grid isn't locked. The kick no longer
needs the stem path (the directional lobes carry per-instrument response), so it
also needs no warmup gate. A live-feel refinement — Matt's ear is the gate.

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
- **NB.4 — Energy: bloom + flow + silence floor. ✅ DONE 2026-06-05 (pending Matt's live manual-validation sign-off on the musical feel).** `NimbusState` (Swift, `@unchecked Sendable` + NSLock) runs a fast-attack (~150 ms) / slow-release (~400 ms) follower over `(bass_att_rel+mid_att_rel+treb_att_rel)/3` (D-026) → `bloom`, flushed to a 16-byte `NimbusStateGPU` at fragment buffer(6); `flowPhase` accumulated in `Double` (long-accumulator rule) at a bloom-modulated rate. The shader consumes `bloom` for body extent (uniform `bodyScale` inflation, +45 % floor→peak), luminosity (`bright` scale on the back-key + ambient, +80 % floor→peak) and `flowPhase` for the gas drift (1×→3.5×, replacing wall-clock `features.time`). Silence floor = the NB.3 backlit look, smaller/dimmer/slower over a faint non-black cool haze (D-037 — a settle, not a collapse). **No beat, no mood** (verified by source inspection — the shader reads no `beat_*` and no valence/arousal). Wired live (`setDirectPresetFragmentBuffer` + `setMeshPresetTick`); `reset()` on preset apply + track change. Tests: `NimbusBloomFollowerTest` (multi-frame follower attack/release feel + render-tracks-bloom through the live direct dispatch path), `PresetVisualReviewTests` (silence/mid/energy fixtures), `NimbusBudgetProbeTests` (slot-6 bound). Budget §6.4 (p50 2.66 ms). Gate: ✅ the contact sheet shows the body blooms bigger/brighter/faster with energy and settles small/dim/slow (non-black) at silence; backlit NB.3 look preserved across the range. **Matt's live ear/eye sign-off on "feels married to the music" is the remaining gate (non-bypassable).**
- ~~**NB.5 — Pulse (embers).**~~ **CUT** (2026-06-04) — superseded by the line below.
- **NB.5 — Beat: stem lobes (the band plays the body). ✅ DONE 2026-06-05 (pending Matt's live manual-validation sign-off).** Reverses the "nothing on the beat" premise (D-141) after the Atlas session showed the energy-only bloom too subtle + floored on bass-dominated music. `NimbusState` gains four stem followers (`kickPunch` ← `max(beatBass,beatComposite)`→`drumsEnergyDev`; `bassLobe`/`vocalsLobe`/`otherLobe` ← stem `…EnergyDev`); `NimbusStateGPU` grows 16→32 bytes. The shader heaves the *single* envelope per stem (`rr/(1 + kick + Σ lobe·cos²)` — star-convex, cannot fragment): drums punch + brighten the whole body, bass heaves DOWN, lead flares UP, other swells to the SIDE. `bloom` re-sourced to mean stem energy (fixes the 3-band floor). Tests: `NimbusBloomFollowerTest.test_stemLobes` (each stem heaves the right way + one mass holds, through the live direct path), budget §6.5 (p50 3.74 ms; perf lesson: cos², never `pow()`, in a per-step falloff). Gate: ✅ the per-stem contact sheet shows directional heaves on one coherent mass. **Matt's live ear/eye sign-off is the remaining gate (non-bypassable — does the body feel like it's playing with the band?).**
- **NB.6 — Mood. ✅ DONE 2026-06-05 (pending Matt's live sign-off).** `NimbusState` smooths `valence` + `arousal` ~4 s (FA #25 — from the FeatureVector, never written back; D-024), stored in the former GPU pad floats (`NimbusStateGPU` stays 32 bytes). Shader: **valence → body colour** `moodTint = mix(indigo, gold, valence01)` applied at composite to every body pixel (+ the ambient fill + the haze halo warm with it, so the whole mass shifts cool↔warm, D-022 propagation); **arousal → flow agitation** `agitation = mix(0.65, 1.55, arousal01)` drives the detail-erosion strength (calm = smoother lobes, energetic = more torn/fraying edges) — it replaced the compile-time `kNimbusTurbulence`. Verified: `NimbusBloomFollowerTest.test_moodTravel` (cool R/B 0.71 → warm R/B 1.79, a 2.5× shift) + the cool/warm/calm/wild contact strip. The two NB.4/NB.5 deferrals (per-track-distinct gas seed + PresetSessionReplay) are still deferred — fold into NB.9 if wanted, or leave as v2 (neither blocks cert).
- ~~**NB.7 — Page.**~~ **CUT** — no section reorganisation in v1 (§1.3).
- **NB.8 — performance tranche. ✅ DONE 2026-06-05 (pending Matt's live sign-off on the half-res look + beat-sync).** The 2nd Atlas live session showed the body swelling to fill the frame costs **mean 6.84 / max 14.5 ms, 56 % of frames over the 7 ms ceiling** (every prior probe under-measured by priming the steady-mid body, not the swell). Fix: a **half-resolution direct-render path** — Nimbus's fragment renders to a 0.5× offscreen texture + bilinear upscale (`feedback_blit`); ~4× cheaper → worst-case ~3 ms (the MetalFX reserve was never wired and Temporal needs motion vectors a procedural volume lacks, so a simple upscale substitutes). Opt-in via `setDirectRenderScale(0.5)` (engine `drawDirect` + `encodePresetVisualization`/`halfResTarget` in `RenderPipeline+DirectDraw.swift`); other presets unaffected. `complexity_cost.tier2` 6.0→**4.0** from the corrected worst-case profile; `tier1 = 9.0` keeps the M1/M2 exclusion. **Beat-sync** tightened (anticipatory predicted-beat kick, §6.8). Budget §6.7/§6.8. Tests: `NimbusBloomFollowerTest.test_halfResUpscale` (half-res + upscale renders a valid image), worst-case `NimbusBudgetProbeTests`, AV.2.2a slot-6 guard updated for the `encodePresetVisualization` refactor.
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
