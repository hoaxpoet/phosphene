# Floret — Preset Plan

**Status:** FLORET.1 ✅ (design + reference curation) + FLORET.2a ✅ (wiring stub, test-reachable) — `[FLORET.1]`/`[FLORET.2a]` commits. Scope + name greenlit by Matt 2026-06-26 (**faithful base + uplifts**; named **Floret**). The faithful base lands at FLORET.2b. See **§10 FLORET.2a — what landed** below.
**Target:** a faithful Phosphene uplift of the Milkdrop preset `suksma - Rovastar - Sunflower Passion (Enlightment Mix)_Phat_edit + flexi und martin shaders - circumflex in character classes in regular expression` (butterchurn built-in; cream-of-the-crop legends; pick #1 on `MILKDROP_UPLIFT_PICKS.md`).
**Substrate:** `direct + mv_warp` (same family as the certified Dragon Bloom / Fata Morgana / Nacre).
**Scaffold:** Nacre (`RenderPipeline+Nacre.swift` dedicated-branch + `Nacre.metal`/`.json` + `NacreMVWarpAccumulationTest`) — Floret has the same custom-warp + custom-comp shape, including the comp-stage blur dependency (see §3).
**References:** `docs/VISUAL_REFERENCES/floret/` — `source_preset.json`, `source_shaders.txt` (the literal port artifact), `target_animated.gif`, three annotated stills.

> Discipline: faithful port. The source shaders in `source_shaders.txt` are the thing to port, not a starting point to re-derive (FA #73 / #65). Adopt the reference's mechanics; adapt only context (audio routing → our deviation primitives, palette anchoring, flash-safety, scale). Render the actual source beside every Floret iteration (`tools/milkdrop-render`).

---

## Committed scope (Matt, 2026-06-26)

**Faithful base + two 2026 uplifts** (the Nacre / Dragon Bloom "faithful + uplifted" pattern):

1. **Real thin-film iridescence on the bubble/cell rims** — the source already shows a greenish iridescent sheen on the bubble rims; replace its high-pass edge-ringing colour with genuine `iridescence()` / `fresnel()` (`Utilities/PBR/Fresnel.metal`, `Materials/Exotic.metal`, Ferrofluid — FA #65), hue driven by chroma/centroid, on `.rgba16Float` feedback. On-theme headliner; most M7-iteration-prone.
2. **Stem-instrument routing** — the doctrine win (each instrument visible): bass→swirl spin + field rotation; vocals→central seed-orb core; drums→sparkle bursts at the filament tips; harmonic *other*→iridescence hue shift. Dragon Bloom / Nacre precedent.

**Correctness requirement, NOT an uplift — flash-safety.** The source breathes hard to near-black troughs and bright peaks on a ~2 s cycle. Faithfully copying that global luminance swing fails the cert flash gate. Floret holds a **steady global luminance floor (D-157)** and carries the pulse through expansion + rim intensity, not full-frame brightness. This is Nacre's NACRE.3 lesson applied up-front: brightness is the wrong connection medium for a bright field; drive the read through motion. Baked into FLORET.2b, not deferred.

*Deferred to tuning stage (not committed): smooth-Voronoi cells (FA #64) if the high-pass foam reads noisy; beat-grid-lock pulse; album-art / arousal palette nudge.*

## 1. Musical role (the one-sentence rule)

Floret's 3-fold radial bloom is the song's **body**: it **inflates and brightens its rims with continuous mid/overall energy** (the filament-mandala swells outward toward the bubble-foam on sustained energy), **bass onsets spin and lurch the whole field** (the vortex spins up; a bounded rotation kick), and **treble stipples crystalline sparkle at the filament tips** — so the viewer reads *sustained energy as a swelling, breathing bloom* and *transients as spin and sparkle across it*.

Loosely inherited from the source (energy⁶ accelerates the swirl accumulator `q8`; `bass` drives rotation) — re-cast onto Phosphene's Audio Data Hierarchy (continuous energy primary, beats as accents).

## 2. Temporal contract (behaviour over time, not a still)

| When | What the field does |
|---|---|
| **Silence / warmup (D-019)** | Filament-mandala present and **alive** — slow vortex swirl + 3-fold radial pulse + palette color-cycle continue; bloom at baseline radius; seed-orbs dim-but-visible. Never black/frozen. |
| **Sustained mid/overall energy** | Bloom **inflates** — filaments swell outward toward the bubble-foam, rims brighten, over ~0.5–2 s via an EMA-decay envelope; recedes slowly. |
| **Bass onset** | The vortex **spins up** + a bounded rotation/displacement kick crosses the field; ~1 beat, spatially bounded (D-157), then settles. |
| **Treble** | Filament tips **sparkle / grain** — fast, instantaneous, fast decay (the "circumflex" `^` clusters). |
| **Full slow cycle (~8–18 s)** | Palette **color-cycles** (green ↔ magenta ↔ violet); the whole field **swirls/rotates** slowly. Audio-independent — the emotional bed. |

## 3. Three-part bar (preset checklist Part 2)

1. **Iconic visual subject deliverable at fidelity — YES.** `mv_warp`/feedback is certified three times (Dragon Bloom, Fata Morgana, Nacre). The signature look (3-fold rotational radial-pulse high-pass kaleidoscope + `z²` conformal fold + 1/r² vortex + seed discs) is standard fragment/per-vertex math — texture taps, `fract`, complex-square, `sqrt`, `max`, rotation matrices — all portable to MSL. Lower clipart risk than Dragon Bloom (no bilateral mirror, no representational subject).
2. **Clear musical role — YES** (§1), inherited from the source rather than bolted on.
3. **Infrastructure-feasible — YES, one real decision.** The core look needs the feedback texture (slot 0) + per-frame/comp math we can express. The **one source op outside the plain mv_warp contract is the comp-stage unsharp high-pass** (`main − sampler_blur1` — this is what makes the bubble-foam rims). Phosphene exposes no general blur mips; **Fata Morgana's `blurState` (a bespoke ¼-res blur target on a dedicated render branch) is the precedent** — Nacre took this exact path for its warp-stage blur. Floret's high-pass is more central than Nacre's sharpen, so the blur quality matters: **decide by render** between (a) Fata-Morgana-style ¼-res blur target on a `RenderPipeline+Floret.swift` branch, or (b) an in-comp multi-tap blur approximation. No new *engine pass type* either way.

## 4. Source mechanic (from `source_shaders.txt` — the port reference)

**baseVals:** bright gamma `gammaadj 1.98`; `zoom 1.025` (overridden to **1.09** in frame eqs); `warp 1.29` baseVal but **`warp 0` in frame eqs** (per-frame wins → mesh warp comes from the per-vertex eqs, not the warp scalar); `warpscale 2.853`, `zoomexp 2.1`; `echo_zoom 2.448 / echo_alpha 0.5` (a zoomed double-image); dense invisible MV grid `mv_x 64 / mv_y 48` with `mv_a 0` (a hidden debug-grid — does **not** advect, per Nacre's FA #73 correction); `wave_a 3.645` baseVal but **`wave_a 0` in frame eqs** (the main per-frame waveform is OFF). 4 custom shapes enabled; 4 custom waves all `enabled:0`.

**Seed = 4 custom shapes** (the only drawn geometry): 100-gon ≈ circles, radii **0.135 / 0.066 / 0.036 / 0.012** (nested), positioned near **(0.3, 0.4)** with small `sin(q8)` jitter; per-corner colour gradient (`r/g/b` → `r2/g2/b2`) each a slow `sin(k·time)` → the slow color-cycle. These are the colored seed-orbs the feedback blooms.

**Per-frame (audio + time):** `q8 = oldq8 + .003·pow(1 + 1.2·bass + .4·bass_att + …, 6)/fps` — an accumulator that advances ∝ **energy⁶** (loudness → motion speed). `mybass += .01·(bass+bass_att)` (accumulates; largely unused downstream). The `vb/vvb/vm/vvm/vt/vvt` EMA envelopes → `q1..q3` → `q4..q32` are **mostly dead** in this edit (set, but the shapes read `q8`+`time`, the waves are off). Final `q1=q2=0.5` (comp center). `decay=.95`.

**Per-vertex warp (`pixel_eqs`):** centered `myx/myy`; `myrad = myx²+myy²`; **vortex** `dx = (.5+.02·sin(q8))·myy/(myrad+1)`, `dy = −(.5+…)·myx/(myrad+1)` (1/r² tangential flow → swirl); **bass→rotation** `rot = bass·rad/10` (outer edges spin on bass); **radial bulge** `sy = 1.02 + rad/10`, `sx = sy − myrad`.

**Warp shader:** `z → z²` complex-conformal map of the centered, ×1.81-scaled uv (`(x²−y², 2xy)`), sample feedback at `z² + (0.448,0.701)`, `− 0.004` (slight decay). The petal/2-fold fold.

**Comp shader (the signature look):** **4 layers** at `dist = 1 − fract(time/2 + k/3)` (k=0..3) → outward radial pulse, ~2 s period; each layer **rotated by ~120°** (rotation matrices in the source → 3-fold symmetry). Each: `neu = texture(main, fract(3·uv·dist + 0.5 + 0.025)) − (texture(blur1, +0.003)·scale1 + bias1)` (**unsharp high-pass** at 3× tiling → bubble-cell edges), `inten = sqrt(dist)·(1−dist)·8`, `ret1 = max(ret1, neu·inten)`. Final `ret = ret1·4` (the ×4 is the hard brightness swing → flash-safety target).

> Butterchurn uniforms with no direct Phosphene equivalent — `scale1/bias1` (blur weight/offset), `aspect`, `q1/q2` (→0.5), `time` — substituted with our texel sizes, `features.time`, and fixed centers. Documented per-symbol at port time.

## 5. Port plan onto Phosphene mv_warp

Pass mapping (3-pass `warp → compose → blit/swap`):
- **Warp pass** (`floret` per-vertex + warp fragment): port the vortex/rotation/bulge as `mvWarpPerVertex` UV displacement; the `z²` conformal fold + `0.95` decay as the warp fragment (`floret_warp_fragment`).
- **Scene/compose pass** (`floret_fragment` + `floret_comp_fragment`): the scene fragment draws the **4 seed discs** (SDF circles, nested, color-cycling — vocals→core brightness uplift). The comp fragment is the signature look — 3-fold radial-pulse high-pass kaleidoscope (needs the blur input, §3) → real iridescent rims (uplift #1) → sparkle (treble/drums). Reads feedback (tex 0), `FeatureVector` (buf 0), `StemFeatures` (buf 3).
- **Blit pass:** display-stage comp (gamma ~1.98 faithful; flash-safe luminance floor here).

Port order — **substrate + look first, audio + uplifts second** (faithful character before reactivity, FA #65):
1. Static port: 3-fold bloom + seed discs + palette cycle + slow vortex swirl rendering faithfully **at silence** (time-driven). Side-by-side vs source.
2. Then layer audio routes (§6) + the 2 uplifts one at a time, auditing one-primitive-per-layer.

## 6. Audio-routing table (one-primitive-per-layer — FA #67 audit)

| Visual layer | Audio primitive | Timescale | Source-eq origin |
|---|---|---|---|
| Bloom inflation (filament→foam swell + rim brightness) | mid/overall energy `f.midRel`/`f.midDev` (EMA memory) | continuous (~0.5–2 s) | energy⁶ → `q8` motion speed |
| Vortex spin-up / field rotation | bass `f.bassDev`, thresholded | bass-onset / event | `rot = bass·rad` |
| Sparkle at filament tips | treble `f.trebleDev` (+ drums stem, uplift) | fast | (new — the "circumflex" clusters) |
| Central seed-orb core brightness | vocals stem (uplift) + overall energy | continuous | shape colour/`a2` |
| Iridescence rim hue (uplift) | chroma / centroid (+ *other* stem) | slow–mid | (new — replaces high-pass colour) |
| 3-fold radial pulse + palette color-cycle + vortex roam | **time** | very slow (2–18 s) | comp `time/2`; shape `sin(k·time)` |

No two visual layers share a primitive at the same timescale. ✓

## 7. Staged increments

| ID | Outcome | Done-when |
|---|---|---|
| **FLORET.1** | Design + reference curation. | ✅ this doc + `docs/VISUAL_REFERENCES/floret/` (source JSON + shaders + GIF + 3 annotated stills + README); scope + name greenlit. |
| **FLORET.2a** | ✅ Wire the custom warp+comp preset + a STUB look, test-reachable: `Floret.{metal,json}` (stub `floret_comp_fragment` + minimal scene + warp fns), `RenderPipeline+Floret.swift` branch (`isFloret` discriminator), `feedbackFormat` `.rgba16Float`, app bundle wiring, `FloretMVWarpAccumulationTest`. | ✅ App build + engine build clean; `FloretMVWarpAccumulationTest` 6/6 (compile/load + live `renderFloret` 64-frame accumulation: non-black + no white-out at silence + reduced-motion format-safe); preset/rubric/regression 62/62 unaffected; swiftlint 0. |
| **FLORET.2b** | Port the FAITHFUL BASE (z² warp + vortex per-vertex + 3-fold radial-pulse high-pass comp + seed discs + palette cycle), **flash-safe** (luminance floor). Decide blur path (§3) by render. Uplifts deferred. | Live `renderFloret` path: non-black + no-white-out + flash-safe at silence over ≥60 frames; contact frames read as the 3-fold bloom on dark ground; side-by-side vs source. → Matt M7. |
| **FLORET.3** | Audio coupling (§6) + the 2 uplifts (iridescence rims, stem routing), one route at a time. | Each route's firing shown in a session-replay diagnostic (`features.csv`/`stems.csv`); one-primitive-per-layer holds; M7. |
| **FLORET.4** | Tuning to certification. | Matt's live M7 sign-off; `certified: true`; flash harness measured SAFE; rubric + capability registry + module map + plan updated. |

(Splits allowed if the comp-shader port is large. Infrastructure and audio never bundled.)

## 8. Build pointers

- **Scaffold:** copy structure from `Nacre.metal` / `RenderPipeline+Nacre.swift` (the dedicated custom-warp+comp branch dispatched by an `isNacre`-style discriminator) — Floret is the same shape. No instanced geometry.
- **Blur input (§3):** evaluate Fata Morgana's `blurState` wiring (`RenderPipeline+FataMorgana`/`blurState`) vs. an in-comp multi-tap. Decide at 2b by render; don't pre-build the heavy path.
- **Sidecar (`Floret.json`):** `family: "hypnotic"` (revisit — Dragon Bloom + Nacre are both hypnotic feedback; confirm Floret shouldn't differ to avoid over-grouping), `passes: ["direct","mv_warp"]`, `decay ≈ 0.95`, `feedbackFormat .rgba16Float`, `rubric_profile: "lightweight"`, `stem_affinity` set only once the routing lands (per NACRE.5 — `PresetScorer` reads only the keys; don't list stems the preset doesn't actually route), `certified: false` until FLORET.4.
- **GPU contract:** direct-pass mv_warp fragment slots — buf 0 `FeatureVector`, buf 2 `waveformData`, buf 3 `StemFeatures`, tex 0 feedback, tex 4–11 noise. `SceneUniforms` (buf 4) is **not** bound in direct-pass.
- **Test harness:** adapt `NacreMVWarpAccumulationTest` → `FloretMVWarpAccumulationTest`, env-gate `FLORET_MVWARP_DIAG=1`; gate on no-white-out + flash-safety (Δluma) + mid→bloom + bass→spin.
- **Visual harness:** `RENDER_VISUAL=1 swift test --package-path PhospheneEngine --filter PresetVisualReview`. Required before first tuning commit.
- **Faithful oracle:** re-render the source any time via `tools/milkdrop-render` (key in `source_shaders.txt`; `music.wav` = same clip as Nacre).

## 9. Risks / open decisions

- **Comp-stage blur (§3)** — the central infra decision. The bubble-foam rims ARE the unsharp high-pass; an under-powered blur approximation may flatten the signature. Decide by render (FM blur target vs multi-tap). Medium risk — higher than Nacre's deferred sharpen because here it's the signature, not polish.
- **Flash-safety vs faithfulness** — the source's ×4 / near-black-trough breathing is intrinsic to its character; the flash-safe floor will make Floret breathe more gently than the source. Accept the divergence (cert gate is non-negotiable); tune the floor for maximum perceived breath within SAFE.
- **`family` field** — "hypnotic" vs a new grouping; three hypnotic feedback presets risks orchestrator fatigue/transition monotony. Product-adjacent; decide with Matt before cert.
- **Iridescence over-bloom** — the on-`.rgba16Float` HDR iridescence is the most M7-prone uplift (Nacre/Ferrofluid history); 8-bit fallback if it over-blooms.
- **butterchurn-only uniforms** (`scale1/bias1`, `aspect`, dead `q4..q32`) — substitution table authored at 2b; fixed seeds acceptable (a preset instance is deterministic).

---

## 10. FLORET.2a — what landed (the wiring stub)

The Nacre dedicated-branch structure, mirrored for Floret (FA #70 — port the proven loop wholesale):
- **`Floret.metal`** — `FloretUniforms` (32 B: time/coreEnergy/texel/aspect), `floret_fragment` (near-black loader placeholder), `mvWarpPerFrame`/`mvWarpPerVertex` (stub zoom + slow rot), `floret_warp_fragment` (decay + faint palette wash + volume-gated core seed + `[0,1]` clamp), `floret_comp_fragment` (display feedback + sRGB decode). Every stub carries a `TODO(FLORET.2b)` for the faithful mechanic (vortex + z² fold, 3-fold radial-pulse high-pass kaleidoscope, 4-disc seed).
- **`RenderPipeline+Floret.swift`** — `FloretUniforms` (Swift, byte-matched) + stateless `computeFloretUniforms` + `drawWithFloret`/`renderFloret` (warp→comp→swap, target-agnostic, FA #66) + `renderFloretReducedMotion` (BUG-061-safe, comp pipeline to the drawable format).
- **Wiring (mirrors Nacre):** `isFloret` discriminator on `MVWarpPipelineBundle` + `MVWarpState`; dispatch branch in `drawWithMVWarp` + the reduced-motion path; `PresetLoader.feedbackFormat` `.rgba16Float`; app `VisualizerEngine+Presets` fbFormat case + `isFloret: desc.name == "Floret"`. All new files are SPM-engine / copied `Shaders/` → **no pbxproj edits**.
- **Test:** `FloretMVWarpAccumulationTest` (6/6) — static fn/JSON guards, GPU compile/load, the live `renderFloret` 64-frame silence accumulation gate (non-black `meanLuma > 0.01` + no white-out `< 85 %` saturated), the BUG-061 reduced-motion format gate, env-gated PNG diag (`FLORET_MVWARP_DIAG=1`).

**Durable learnings:**
- **`RenderPipeline+MVWarp.swift` is at the `file_length` 400-line cap.** Adding Floret's dispatch branch pushed it to 416; recovered by tightening verbose comments (all D-refs preserved). **A 3rd custom-warp+comp preset should extract `drawWithMVWarpStandard` to its own file** (the established split pattern — `+Nacre`/`+FataMorgana`/`+MVWarpReducedMotion` already split out) rather than trim further.
- **The dispatch now carries two name-keyed bools** (`isNacre`, `isFloret`) + the `blurPipeline` check. Two is fine; **a 4th custom branch → replace the bool chain with an enum** (`MVWarpBranch`) on the bundle. Not worth it yet (YAGNI).
