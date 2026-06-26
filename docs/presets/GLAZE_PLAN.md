# Glaze — Preset Plan

**Status:** GLAZE.1 ✅ — design + reference curation (this increment); **name + scope greenlit by Matt 2026-06-26.**
No shader code yet (faithful-port discipline: references + plan before `.metal`, NACRE.1 pattern).
**Target:** faithful Phosphene uplift of the Milkdrop preset `Flexi + stahlregen - jelly showoff parade`
(cream-of-the-crop legends; butterchurn built-in — renders faithfully).
**Substrate:** `direct + mv_warp` (same family as Nacre / Dragon Bloom / Fata Morgana).
**References:** `docs/VISUAL_REFERENCES/glaze/` — `source_preset.json`, `source_shaders.txt`
(decoded port artifact), `target_animated.gif`, 3 annotated stills.

> Discipline: faithful port. `source_shaders.txt` is the thing to port, not a starting point to re-derive
> (FA #73 / #65). Adopt the mechanics; adapt only context (audio → deviation primitives, palette, scale).
> Render the actual source beside every iteration (`tools/milkdrop-render`).

## 0. Greenlit scope (Matt, 2026-06-26)

**Name: Glaze.** **Scope: faithful base + 3 uplifts** (the Nacre/Dragon Bloom "substantially exceed the
original" pattern). All three uplifts land **AFTER the faithful base passes live M7** (FA #65 — faithful
first, no uplift before the base is confirmed):
- **Uplift A — Per-stem instrument routing into the spring.** Each separated stem moves the jelly differently:
  bass → the big lateral sway, drums → a sharp impulse "punch" (visible recoil), vocals → swell/glow, harmonic
  *other* → sheen/palette tint. The doctrine win (every instrument visible); Dragon Bloom / Nacre precedent.
- **Uplift B — HDR glossy bloom.** On `.rgba16Float` feedback the wet specular highlights become luminous and
  bloom — the on-theme headliner for "Glaze." Most M7-tuning-prone (white-out risk under decay 1.0; the Nacre
  clamp lesson — re-unclamp carefully, bloom as a display-stage add).
- **Uplift C — Secondary "shiver" mode.** A second fast resonant mode so the body *shivers/ripples* on
  hi-hats/treble while it *sways* on bass — two physical timescales in one jelly. Amplifies the physics
  identity; keeps Glaze distinct from Nacre's calmer field.

Distinctness (Matt-confirmed proceed): a 4th mv_warp feedback preset, but visually unrelated to Nacre (cells),
Dragon Bloom (fiery symmetry), Fata Morgana (mirage) — glossy continuous contour-gel.

---

## 1. Musical role (the one-sentence rule)

The glossy contour-field is a **mass of jelly on a spring that the rhythm section throws around**: the
**bass yanks it one way, the treble flicks it the other, and total energy lifts it**, while gravity, damping
and wall-bounce pull it back — so the viewer reads *transients as a physical lurch-and-wobble of the whole
field* and *sustained energy as a wide, lively swing*, with the jelly settling into a gentle gravity-sway
when the music drops out.

**Why this is a strong, low-risk role:** the spring-mass **integrates** the audio into momentum, so raw beat
jitter becomes smooth organic overshoot/settle — it sidesteps the "never drive primary motion from raw
onsets" failure (FA #4/#31) *by construction*, not by tuning. The routing is **inherited from the source**
(its own frame-eqs drive the spring anchor from bass/treble/energy EMAs), which happens to align with
Phosphene's Audio Data Hierarchy (continuous energy primary; the spring is a physical low-pass on it).
Distinct from every certified preset: this is the catalog's first **physics-of-the-beat** preset.

## 2. Temporal contract (behaviour over time)

| When | What the field does |
|---|---|
| **Silence / warmup (D-019)** | Field present + **alive**: palette rotation continues, the spring idles with a slow gravity-sway, contour structure visible. Never black/frozen. (Source seeds only from a volume-gated waveform → a literal port is black at silence; Phosphene adds a silence-floor seed, exactly as Nacre did.) |
| **Bass / treble transient** | The spring anchor jumps → the whole field **lurches and wobbles** (momentum + overshoot), then settles. Bounded, physical, ~1–3 beats of decay. |
| **Sustained energy** | Anchor swings **wide and lively**; contours flow fast; sheen flares — without white-out. |
| **Full slow cycle (~10–14 s)** | Palette **rotates** red→green→teal→violet; feedback **accretes** the nested contour rings inward (decay 1.0 + zoomexp). |
| **Section change** (optional, tuning) | Slow arousal envelope may bias overall swing amplitude / palette warmth. Secondary. |

## 3. Three-part bar (preset checklist Part 2)

1. **Iconic visual subject deliverable at fidelity — YES, with one infra extension.** The glossy contour-gel
   is feedback+warp+comp math (texture taps, Sobel-of-blur emboss, multi-scale unsharp, hue mix, contrast
   curve) — all portable MSL, mv_warp certified 3×. **The one dependency: a 3-level blur pyramid**
   (`blur1/2/3`) drives the sheen in *both* shaders. Phosphene already has Fata Morgana's blur machinery —
   `blurState`/`blurTexture`, a 1/4-res separable gaussian (= `blur1`), **already wired into `MVWarpState`**
   (`RenderPipeline+MVWarp.swift:62`). The port **extends** it to 2–3 levels (wider/more-downsampled), reusing
   the existing blur pass. Extension of known infra, not a new category — this is the main (bounded) build.
2. **Clear musical role — YES** (§1), and inherited + physically self-smoothing.
3. **Infrastructure-feasible — YES.** Spring physics = a handful of CPU-side floats integrated per frame
   (the `NacreUniforms`/Fata-Morgana per-frame-uniform pattern). Warp + comp = standard fragment math. The
   only new work is the 2-level blur extension (item 1). **No new render-pass category.**

## 4. Source mechanic (decoded — full detail in `source_shaders.txt`)

- **Spring-jelly (frame_eqs):** 3 chained damped point-masses hanging off an **audio-driven anchor**
  (`x1=.5+1.5*(bassEMA−trebEMA)`, `y1=.5+energyEMA`), with gravity, damping, and `bounce=.9` off the [0,1]
  walls. The free tail's position+speed → the moving center of the warp poke.
- **Warp poke (pixel_eqs):** a local radial **swirl-vortex** within radius `.2` of the tail — `dx=sin(y−cy)·dir`,
  `dy=−sin(x−cx)·dir` — dragged across the field as the jelly bounces.
- **Accreting feedback:** `decay 1.0` (never fades) + inward `zoom 1.06`/`zoomexp 11.56` → the nested
  concentric contour "fingerprint" rings that fill the frame.
- **Warp shader:** blur-pyramid Sobel emboss → UV displacement; R/G/B channels flow along *different* gradient
  directions at different decay → chromatic trailing.
- **Comp shader (the gel sheen):** multi-scale unsharp/bandpass from `blur1/2/3` + dual-direction
  gradient-displaced sampling + `pow(hue_shader,·)` palette mix + `ret*ret`/`sqrt` contrast curve.
- **Seed:** a single **volume-gated waveform** (the whole image builds from it under decay 1.0).
- **Butterchurn-only uniforms** (`hue_shader`, `scale*/bias*`, `texsize`) → substituted with a Phosphene
  palette, fixed scale/bias, and our texel sizes. Documented per-symbol at port time.

## 5. Port plan onto Phosphene mv_warp (dedicated branch, Nacre/FM pattern)

- **Per-frame uniforms** (`GlazeUniforms`, CPU-side, integrated each frame): the spring state (anchor ←
  audio EMAs; 3 masses; tail pos/speed) + palette phase + texel sizes. Mirrors `NacreUniforms`/FM.
- **Blur pass(es):** reuse FM's `blurState`/`blurTexture`; add 1–2 more downsample levels for `blur2/3`.
- **Warp fragment** (`glaze_warp_fragment`): port the emboss-displace + channel-decoupled flow; reads
  feedback (tex 0) + blur levels + `GlazeUniforms`; pixel-eq vortex baked in around the tail center.
- **Comp fragment** (`glaze_comp_fragment`, DISPLAY-stage): the gel-sheen multi-scale unsharp + hue + contrast.
- **Scene/seed:** a silence-floor-gated waveform core (D-019), so it's alive at silence (Nacre learned the
  literal volume-gated seed goes black — add the floor).
- **Feedback format:** the **base** clamps to `[0,1]` each frame (source stores 8-bit; a float buffer blooms to
  white under decay 1.0 — the Nacre lesson). Allocate `.rgba16Float` from the start (headroom for greenlit
  uplift B) but carry `[0,1]` until B re-unclamps with a display-stage bloom, post-base-M7.
- Port order — **substrate + look first (at silence, time-driven), audio second** (FA #65).

## 6. Audio-routing table (one-primitive-per-layer — FA #67 audit)

| Visual layer | Audio primitive | Timescale | Source-eq origin |
|---|---|---|---|
| Spring anchor X (lateral swing) | `f.bassDev` (one dir) **and** `f.trebleDev` (other dir) of **one anchor** | continuous (EMA) | `xx1`/`xx2` → `x1` |
| Spring anchor Y (lift) | avg energy envelope | continuous (EMA) | `yy1` → `y1` |
| All visible field motion (lurch/wobble/flow) | — (pure spring integration of the anchor) | physical | the spring chain |
| Warp swirl-poke center | — (spring tail pos/speed) | physical | `q4`/`q5` → pixel_eqs |
| Palette hue rotation | **time** [+ optional chroma/centroid nudge] | very slow (10–14 s) | `hue_shader` + drift |

The anchor is **one physical input**; bass and treble drive opposite directions of it (not two layers), energy
drives a different axis, and every visible motion is the spring's single integrated response. ✓ No two layers
share a primitive at a timescale.

## 7. Staged increments (proposed)

| ID | Outcome | Done-when |
|---|---|---|
| **GLAZE.1** ✅ | Design + reference curation (**this increment**). | ✅ references curated, source decoded, plan written; name + scope greenlit by Matt. |
| **GLAZE.2a** | Blur-pyramid extension + wire a STUB preset, test-reachable. | App+engine build clean; accumulation test runs the live warp→comp→swap path ≥60 frames at silence without white-out; loads + renders non-black. |
| **GLAZE.2b** | Port the FAITHFUL BASE (spring + warp + comp + gel sheen + seed) at silence/time-driven. | Side-by-side reads as the glossy contour-jelly; spring idles alive at silence; → Matt live M7. |
| **GLAZE.3** | Base audio coupling (§6, one route at a time). | Each route's firing shown in session-replay (`features.csv`); one-primitive-per-layer holds; M7. |
| **GLAZE.4** | Tune the faithful base to **base cert / live M7 confirmed**. | Matt live M7 sign-off on the base (gate for uplifts, FA #65). |
| **GLAZE.5 (A)** | Uplift A — per-stem instrument routing into the spring. | Per-stem firing in session-replay; one-primitive-per-layer holds; M7. |
| **GLAZE.6 (B)** | Uplift B — HDR glossy bloom (re-unclamp + display-stage bloom). | No white-out under worst-case beat train; flash-safe (multi-pass harness); M7. |
| **GLAZE.7 (C)** | Uplift C — secondary shiver mode. | Treble shiver distinct from bass sway in replay; M7. |
| **GLAZE.8** | Certification. | Matt live M7 sign-off; `certified:true`; rubric + flash gates registered; registry + plan updated. |

(Uplift IDs/order are provisional — uplifts land only AFTER GLAZE.4 confirms the base, FA #65; per-stem first,
bloom last is the risk order. Infrastructure and audio never bundled.)

## 8. Open decisions — RESOLVED (Matt, 2026-06-26)

1. **Name → Glaze.** 2. **Distinctness → proceed** (visually distinct from the 3 existing feedback presets).
3. **Ambition → faithful base + all 3 uplifts (A/B/C), uplifts post-base-M7.** See §0.
