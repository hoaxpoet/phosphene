# Nacre — Preset Plan

**Status:** NACRE.1 ✅ committed (`374791d`). NACRE.2 in progress — Matt greenlit the faithful base **+ 3 uplifts** (stem-instrument routing / real iridescence + HDR / smooth-Voronoi cells) and the engine-shader approach. See **NACRE.2 — Committed scope** below.
**Target:** faithful Phosphene uplift of the Milkdrop preset `$$$ Royal - Mashup (431)` (butterchurn built-in; cream-of-the-crop legends).
**Substrate:** `direct + mv_warp` (same family as the certified Dragon Bloom / Fata Morgana).
**Scaffold:** Dragon Bloom (`DragonBloom.metal` / `.json` / `DragonBloomMVWarpAccumulationTest`). (Starburst → renamed Murmuration, no longer mv_warp.)
**References:** `docs/VISUAL_REFERENCES/nacre/` — `source_preset.json`, `source_shaders.txt` (the literal port artifact), `target_animated.gif`, three annotated stills.

> Discipline: this is a faithful port. The source shaders in `source_shaders.txt` are the thing to port, not a starting point to re-derive (FA #73 / #65). Adopt the reference's mechanics; adapt only context (audio routing → our deviation primitives, palette anchoring, scale). Render the actual `(431)` beside every Nacre iteration.

---

## NACRE.2 — Committed scope & architecture (revised 2026-06-25, post-greenlight)

> **⚠️ 2026-06-25 spec-alignment (Matt): the architecture below is SUPERSEDED on three points** by
> `docs/prompts/NACRE_2B_KICKOFF.md` §0.5 (which merges Matt's `ROYAL_MASHUP_431_KICKOFF` spec). 2a's
> choices to correct in 2b: (a) **custom `nacre_warp_fragment` + a 3-level blur pyramid on the Fata
> Morgana template** — NOT the shared decay warp / convention-only path (431's warp is custom: unsharp
> blur-pyramid + treble grain + 0.9 in-warp decay; the blur pyramid needs FM's renderer-wired
> `blurState`, so "no renderer edit" was incomplete); (b) **feedback HDR with 8-bit fallback** if it
> over-blooms; (c) **stand up a live butterchurn oracle** for per-layer comparison. The musical role,
> temporal contract, stem routing (§6), and "the look is a DISPLAY-stage comp transform" all still hold.
> **NACRE_2B_KICKOFF.md is the authoritative 2b guide.**

**Greenlit (Matt):** faithful (431) character base **+ three 2026 uplifts** (substantially exceed the 2003 original, like Dragon Bloom was "faithful + uplifted"):
1. **Stem-instrument routing** — vocals→luminous core; bass→cell swell + displacement-kick; drums→rim sparkle; harmonic *other*→refraction / iridescence shift. The doctrine win (each instrument visible); Dragon Bloom precedent.
2. **Real thin-film iridescence + HDR** — replace (431)'s 2-px chromatic-offset rims with genuine `iridescence()`/`fresnel()` (`Utilities/PBR/Fresnel.metal`, `Materials/Exotic.metal`, Ferrofluid — FA #65), hue driven by chroma/centroid; on `.rgba16Float` feedback (unclamped colour + bloom). The on-theme headliner (nacre = mother-of-pearl = thin-film). Most M7-iteration-prone.
3. **Smooth-Voronoi refractive cells** — replace (431)'s `sin(4·uv)` lattice with C¹ smooth Voronoi (`Utilities/Noise/Worley.metal` + `smin`, FA #64) for organic depth-stacked membranes.
*(Deferred to tuning stage: beat-grid-lock pulse + chroma-driven palette.)*

**Architecture (corrects §5's pass-map — the signature look is a DISPLAY-stage transform of the feedback, NOT the scene fragment):**
- **Feedback loop** — `mvWarpPerFrame`/`mvWarpPerVertex` (direct FeatureVector+stems): the drifting accumulated cell-field — dense cell-advection warp + slow roam; **mid→zoom**, **bass→displacement-kick** (D-026 primitives). Plain decay feedback via shared `mvWarp_fragment` (chromatic=0). `.rgba16Float` feedback.
- **Scene fragment** — `nacre_fragment` (buf 0/1/2/3): draws the additive **central core** (vocals→brightness, waveform→shape) that seeds the field.
- **Custom comp/blit** — `nacre_comp_fragment` (DISPLAY-ONLY, samples feedback `warpTex` at tex 0): the signature look — radial-pulse zoom + **luminance-emboss rims → real iridescence** (hue←chroma; *other*→shift) + **smooth-Voronoi refractive cells** + drums→sparkle + treble→grain. Reads `NacreUniforms` (time + audio/spectral drive, precomputed CPU-side) at buffer 1; texsize from `warpTex.get_width/height()`.

**Wiring is convention-based — NO `RenderPipeline+MVWarp.swift` edit (confirmed).** `PresetLoader.makeWarpPipelines` auto-selects `<prefix>_comp_fragment` / `<prefix>_warp_fragment` from the JSON `fragment_function` (else the shared fns); the standard `drawWithMVWarp` path already uses the per-preset `blitState` + `bindCompStagePresetBuffer` (unconditional; Skein precedent). Minimal change-set:
- NEW `Shaders/Nacre.metal` (`nacre_fragment` + `mvWarpPerFrame`/`mvWarpPerVertex` + `nacre_comp_fragment`) + `Shaders/Nacre.json`.
- NEW `Presets/Nacre/NacreState.swift` (`NacreUniforms` + per-frame `tick`→`writeToGPU`; lighter than SkeinState — no ring buffers).
- `PresetLoader.feedbackFormat`: add `if name == "Nacre" { return .rgba16Float }`.
- `VisualizerEngine+Presets.swift`: Nacre block (alloc `NacreState` + `setDirectPresetFragmentBuffer` + tick), mirroring Skein; `VisualizerEngine.swift`: `nacreState` property + reset.
- NEW `Tests/.../NacreMVWarpAccumulationTest.swift` (adapt DragonBloom's; env-gate `NACRE_MVWARP_DIAG=1`).

## 1. Musical role (the one-sentence rule)

Nacre's translucent refractive cell-field is the song's **harmonic body**: it **inflates and breathes with continuous mid-band energy** (cells swell on sustained chords/pads), **bass onsets jolt the whole field with a bounded displacement-kick** (a ripple crosses the lenses), **treble stipples the chromatic rims with sparkle**, and a **luminous central core pulses with the waveform** — so the viewer reads *sustained energy as swelling translucent volume* and *transients as ripples and sparkle across it*.

This routing is **inherited from the source**, not invented — `(431)`'s own per-frame equations already drive zoom from mid energy and kick displacement from a bass threshold (see §4), which happens to align with Phosphene's Audio Data Hierarchy (continuous energy primary, beats as accents). That alignment is why this preset is low-risk.

## 2. Temporal contract (behaviour over time, not a still)

| When | What the field does |
|---|---|
| **Silence / warmup (D-019)** | Cell-field present and **alive** — slow time-driven roam + palette rotation continue; zoom at baseline; core dim-but-visible. Never black/frozen. |
| **Sustained mid energy** (held chord, build) | Cells **inflate** (zoom pumps up via an EMA-decay envelope), field grows over ~0.5–2 s, recedes slowly. |
| **Bass onset** | The field **lurches** — a bounded displacement-kick sends a ripple across the cells; ~1 beat, spatially bounded (D-157), then settles. |
| **Treble** | Rims **sparkle / grain** — fast, instantaneous, fast decay. |
| **Full slow cycle (~8–18 s)** | Palette **rotates** green→teal→violet→red; whole field slowly **roams/rotates**. Audio-independent — the emotional bed. |
| **Section change** (optional, tuning) | A slow arousal envelope may bias palette warmth + overall brightness. Secondary; faithful base is time-driven. |

## 3. Three-part bar (preset checklist Part 2)

1. **Iconic visual subject deliverable at fidelity — YES.** `mv_warp`/feedback is certified twice (Dragon Bloom, Fata Morgana). The signature look (§4: multi-layer radial-pulse zoom + luminance-gradient emboss rims + chromatic center-offset + domain-warped sine-cell noise) is standard fragment math — texture taps, dot, `sqrt`/`fract`/`sin`/`inversesqrt`, `max`, `mix` — all portable to MSL. **Lower** clipart risk than Dragon Bloom: no bilateral mirror (FA #48 doesn't apply).
2. **Clear musical role — YES** (§1), and inherited from the source rather than bolted on.
3. **Infrastructure-feasible — YES, one minor deferral.** The core look needs only the feedback texture (slot 0) + per-frame/comp math we can express. The **only** source op outside our contract is the warp-shader sharpen's **blur pyramid** (`sampler_blur1/2/3`) — Phosphene exposes no general blur mips (only Fata Morgana has a bespoke 1/4-res blur target). The sharpen is secondary polish, not the signature; **defer it** — approximate with a manual 3-tap, or add a Fata-Morgana-style custom blur target only if a render proves it's needed. **No new engine passes required.**

## 4. Source mechanic (from `source_shaders.txt` — the port reference)

**baseVals:** `wave_mode 7`, near-invisible wave (`wave_a 0.001`, `wave_r/g/b 0`, but `modwavealphabyvolume 1`); slight zoom-in (`zoom 1.009`), minimal baseline `warp 0.00054`; **dense motion-vector field `mv_x 25.6 / mv_y 9.6`** (invisible, `mv_a 0`) — this advects the feedback into the drifting cell structure.

**Per-frame equations (the audio + time coupling):**
- **Palette rotation:** `wave_r=.85+.25*sin(.437*t+1)`, `wave_g`(.544), `wave_b`(.751) — three slow out-of-phase sines → the green→teal→violet→red drift.
- **Slow roam:** `rot/cx/cy/dx/dy += small * sin(low-freq * t)` — the field's slow wander/rotation.
- **Mid → zoom (PRIMARY continuous):** `rg = max(.77*rg, .02 + .5*min(2, 1.3*max(0, mid_att-1))); zoom += .1*rg`. Mid energy above unity raises an EMA-decay (`.77`) envelope that pumps zoom → cells inflate/breathe.
- **Bass → displacement kick (ACCENT):** a hysteresis threshold `bass_thresh` fires when `bass_att` crosses it (`above(...)`), latching `=2.13` and injecting `dx_residual=.016*sin(7t)`, `dy_residual=.012*sin(9t)` (and `wave_x/y -= 7*residual`); threshold relaxes `~.96*` per frame. A bounded, decaying lurch on bass onsets.
- Minor: `decay -= .01` every 6th frame (micro-flicker), `wave_mystery=.03*t`.

**Warp shader:** unsharp-mask **sharpen** (main − weighted blur-pyramid) → edge definition; **+ noise grain scaled by `treb_att`** (treble sparkle); slight desaturation. *(Blur pyramid = the deferred bit.)*

**Comp shader (the signature look):** **four radial-pulse layers** at `dist = 1 − fract(k/4 + t/18)` (k=0..3) → expanding rings every 18 s, quarter-phase offset; each weighted `inten = sqrt(dist)(1−dist)·4`. Layers alternate sample-center **(0.51,0.55)/(0.49,0.55)** → horizontal **chromatic offset** (the R/C/G rims). `dz` = **luminance Sobel gradient × inten** → **edge emboss** (the bright rims). `ret1 = max` of zoomed feedback across layers. Then a **domain-warped sine-cell field** (`sin(4·uv + dz + rand)` at 3 scales, `inversesqrt`) displaced **by the emboss gradient** → the veined cell micro-structure. Final: rand-weighted combine − slow color-roam (`slow_roam_sin·roam_cos`) + `ret*(1+ret)` contrast.

> Butterchurn uniforms with no direct Phosphene equivalent — `rand_preset`/`rand_frame` (per-preset/per-frame randoms), `slow_roam_sin`/`roam_cos` (slow roam), `texsize_*`/`scale*`/`bias*` — get substituted with fixed seeds + `features.time`-driven roam + our texel sizes. Documented per-symbol at port time.

## 5. Port plan onto Phosphene mv_warp

Pass mapping (3-pass `warp → compose → blit/swap`, per the substrate map):
- **Warp pass** (`nacre` per-vertex + decay): port `mv_x/y` advection as the per-vertex UV displacement (`mvWarpPerVertex`), `decay` from `mvWarpPerFrame`. The warp-shader sharpen/grain folds into the compose or a warp-stage fragment (grain = treble route).
- **Scene/compose pass** (`nacre_fragment`): this is where the **comp shader** lives — radial-pulse zoom + emboss rims + chromatic offset + sine-cell noise + the near-invisible additive waveform forming the **central core**. Reads feedback (slot 0), `FeatureVector` (0), `waveformData` (2), `StemFeatures` (3).
- **Blit pass:** display-stage comp (gamma; echo/invert off unless a render wants them).

Port order — **substrate + look first, audio second** (faithful character before reactivity, per FA #65):
1. Static port: get the cell-field + chromatic rims + palette rotation + slow roam rendering faithfully **at silence** (time-driven only). Side-by-side vs `(431)` at silence-equivalent.
2. Then layer the audio routes (§6) one at a time, auditing against the one-primitive-per-layer table.

## 6. Audio-routing table (one-primitive-per-layer — FA #67 audit)

| Visual layer | Audio primitive | Timescale | Source-eq origin |
|---|---|---|---|
| Cell-field zoom / inflation (breathing) | mid energy `f.midRel`/`f.midDev` (EMA memory) | continuous (~0.5 s) | `rg`/`q9` → `zoom` |
| Warp displacement-kick (field lurch/ripple) | bass `f.bassDev`, thresholded | bass-onset / event | `bass_thresh` → `dx/dy_residual` |
| Rim sparkle / micro-grain | treble `f.trebleDev` | fast | warp-shader noise × `treb_att` |
| Central luminous core brightness | waveform (buf 2) + total energy | continuous + per-sample | additive wave + radial-pulse convergence |
| Global palette hue rotation | **time** (faithful) [+ optional slow arousal nudge] | very slow (8–18 s) | `wave_r/g/b` sines; comp `t/18` |
| Slow field roam / rotation | **time** | very slow | `cx/cy/rot/dx/dy` sines |

No two visual layers share a primitive at the same timescale. ✓ (mids→volume/zoom and bass→position/kick are different layers *and* different timescales.)

## 7. Staged increments

| ID | Outcome | Done-when |
|---|---|---|
| **NACRE.1** | Design + reference curation. | ✅ committed `374791d`; uplifts greenlit by Matt. |
| **NACRE.2a** | Wire the custom-comp preset + a STUB look, test-reachable: `Nacre.{metal,json}` (stub `nacre_comp_fragment` + minimal scene + warp fns), `NacreState`, `feedbackFormat` + `VisualizerEngine` wiring, `NacreMVWarpAccumulationTest`. | App + engine build clean; accumulation test runs the live `warp→compose→blit` path ≥60 frames at silence without white-out; preset loads + renders non-black. **← current** |
| **NACRE.2b** | Port the look + 3 uplifts into the shaders: cell-advection warp + core (scene) + comp shader (radial pulse + emboss→iridescence + Voronoi cells + stem/treble drive). | `RENDER_VISUAL=1` contact sheet (silence/mid/beat) committed; side-by-side vs `(431)` reads as the same preset, uplifted; one-primitive-per-layer audit holds; → M7. |
| **NACRE.3** | Audio coupling (§6 routes, one at a time). | Each route's firing shown in a session-replay diagnostic (`features.csv`); one-primitive-per-layer audit holds; M7 round 1. |
| **NACRE.4** | Tuning to certification. | Matt's live M7 sign-off; `certified: true`; capability registry + plan updated. |

(NACRE.2 may split if the comp-shader port is large. Infrastructure and audio never bundled.)

## 8. Build pointers

- **Scaffold:** copy structure from `DragonBloom.metal` (`*_fragment`, `mvWarpPerFrame`, `mvWarpPerVertex`); no strand geometry (Nacre has no instanced geometry — it's pure feedback + fragment).
- **Sidecar:** mirror `DragonBloom.json`. Tentative: `family: "hypnotic"` (revisit "fluid" — affects orchestrator grouping; Dragon Bloom is also "hypnotic", so confirm Nacre shouldn't differ to avoid over-grouping two feedback presets), `passes: ["direct","mv_warp"]`, `decay ≈ 0.95`, `stem_affinity` minimal (Nacre is band-energy-driven more than stem-driven — likely `{}` or a light vocals→core link), `rubric_profile: "lightweight"`, `certified: false` until NACRE.4.
- **GPU contract:** direct-pass mv_warp fragment slots — buf 0 `FeatureVector`, buf 2 `waveformData`, buf 3 `StemFeatures`, tex 0 feedback, tex 4–11 noise. (`SceneUniforms` buf 4 is **not** bound in direct-pass — don't reach for it.)
- **Test harness:** adapt `DragonBloomMVWarpAccumulationTest` → `NacreMVWarpAccumulationTest`, env-gate `NACRE_MVWARP_DIAG=1`, silence vs music, gate on no-white-out + mid→zoom coupling + bass→displacement.
- **Visual harness:** `RENDER_VISUAL=1 swift test --package-path PhospheneEngine --filter PresetVisualReview` → `/tmp/phosphene_visual/<ISO>/` (silence/mid/beat). Required before first tuning commit.
- **Faithful oracle:** re-render `(431)` any time via `tools/milkdrop-render` (`royal_variants/$$$ Royal - Mashup (431).json` already extracted).

## 9. Risks / open decisions

- **Blur-pyramid sharpen** (deferred) — confirm by render whether manual-tap approximation suffices or a custom blur target is warranted (Fata Morgana precedent). Low risk (secondary polish).
- **`family` field** — "hypnotic" vs a new "fluid" grouping (orchestrator fatigue/transition impact of two hypnotic feedback presets). Product-adjacent; decide with Matt at NACRE.2.
- **Palette anchoring** — keep faithful time-driven rotation, or nudge toward album-art / arousal warmth? Faithful-first; arousal-nudge is a NACRE.3+ tuning lever, not a NACRE.2 requirement.
- **butterchurn-only uniforms** (`rand_preset`, `slow_roam`, etc.) — substitution table authored at NACRE.2; risk that fixed seeds flatten variety vs the original's per-load randomness (acceptable — a preset instance is deterministic anyway).
