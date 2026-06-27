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

## ★ GLAZE.2b.2 grain ROOT CAUSE (2026-06-26, Matt's live M7 flagged grain as preset-sinking)

**Root cause: a feedback sharpening instability.** The source's warp does `ret = main + (main − blur2)·0.4`
— an unsharp mask, i.e. a high-pass *boost*. In a feedback loop that term has gain > 1 at high spatial
frequencies, so on our **float** buffer it compounds every frame and amplifies any tiny variation into
ever-thinner razor filaments → a dense crackle/grain that reads as noise. The source gets away with it only
because its **8-bit** feedback storage quantizes the runaway each frame; we can't replicate that bound on a
float buffer.

**Found by isolation** (FA #64 — diagnose, don't guess): comp-passthrough showed the grain was in the *warp
feedback*, not the comp → collapsing the R/G/B channel decoupling kept the thin filaments (so colour wasn't
it) → **disabling the unsharp made the feedback perfectly smooth.** Decisive.

**Fix (durable craft rule): sharpening belongs DISPLAY-only, never in the fed-back warp.** The warp now just
advects + decays + seeds (smooth); the *comp* embosses the smooth feedback into the gel sheen (display-only,
never fed back) — so the high-pass can't compound. Also dropped the `+0.006` uniform self-seed (it flooded the
ground; the explicit curve seed replaces it, and dropping it restores a darker ground). **Generalises:** any
mv_warp/feedback preset that puts an unsharp/high-pass in the warp loop will grain on a float buffer — keep it
in the display comp. (Sibling of the Nacre "brightness is the wrong medium" + "wide blur → membranes" lessons.)

**Still open (M7 tuning, not grain):** the silence base is band-like (the full contour field fills in with
audio = GLAZE.3, as the source's waveform jumps around); the ground reads green (the comp `+1.0` lift).

> **GLAZE.3 learning (seed-fill):** the audio-driven *anchor* sweeps only the warp **poke**; the **seed**
> (the bright structure source) was a fixed horizontal band, so the field stayed band-like even with audio.
> Fix: the seed band's vertical centre rides the spring **tail Y** (`gu.seedY`) → it sweeps the frame with
> the music. **Anchor ≠ fill** — to fill an accreting feedback field you must move the *seed*, not just the
> poke. What's left for **GLAZE.4** is a `decay`-vs-dark-ground tension: `decay 0.96` gives the oracle's dark
> ground but retains only ~1–1.5 s of sweep, so the field doesn't accrete to the oracle's full nested-ring
> density (which uses `decay 1.0` on 8-bit). Raising decay toward 1.0 fills more but risks the float bloom
> (the §0/Nacre lesson) and lifts the ground — that trade is Matt's live-M7 call, not audio wiring.

> **GLAZE.3/4 learning (wash-out is a SLOW ACCUMULATION CREEP, not energy — and a HARNESS-fidelity trap):**
> Matt M7'd the field washing out bright. First instinct (and first fix, `61f62d4`, **now REVERTED**) was that
> dense music over-accumulates → an *energy-adaptive* decay. **Wrong.** The wash is a **base accumulation creep
> toward white over MINUTES of playback**, on BOTH tracks regardless of energy (the seed keeps injecting; decay
> 0.96 doesn't fully bleed it). **★ It only reproduces headless when you render to PLAYBACK LENGTH:** the calm
> track climbs meanLuma 0.68 (1500 frames) → 0.77 (4000) → 0.82 / 25 % saturated (8000 ≈ 2 min). A 1500-frame
> (25 s) render shows none of it — so a short render "validated" the wrong fix. **Rule: validate brightness/wash
> at the accumulation steady-state (thousands of frames), never a 25 s render.** Decay is a weak lever (0.85
> still washes ~9 %); the real drivers are the comp `+1.0` floor + the bright seed. The fix is a base
> brightness-budget retune (comp lift / seed / decay together) = **GLAZE.4, with Matt's eye** — separable from
> the audio coupling, which stands. Sibling of [[feedback_visual_fix_needs_live_m7]].

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
| Spring anchor X (lateral swing) | `stems.bassEnergyDev` (one dir) **and** `stems.otherEnergyDev` (other dir) of **one anchor** | continuous (EMA) | `xx1`/`xx2` → `x1` |
| Spring anchor Y (lift) | mean of the four stem `EnergyRel`s (fullness) | continuous (EMA) | `yy1` → `y1` |
| Seed band vertical centre | — (spring tail Y → `gu.seedY`) | physical | `wave_a` seed |
| All visible field motion (lurch/wobble/flow) | — (pure spring integration of the anchor) | physical | the spring chain |
| Warp swirl-poke center | — (spring tail pos/speed) | physical | `q4`/`q5` → pixel_eqs |
| Palette hue rotation | **time** [+ optional chroma/centroid nudge] | very slow (10–14 s) | `hue_shader` + drift |

The anchor is **one physical input**; the bass stem and the harmonic **other** stem drive opposite directions of
it (not two layers), fullness drives a different axis, and every visible motion is the spring's single integrated
response. ✓ No two layers share a primitive at a timescale.

> **Stem-drive (Matt M7 2026-06-27).** The lateral swing originally used the bass/treble **bands** — but on real
> tracks those are often the quietest channels (School of Seven Bells `2026-06-27T02-00-44Z`: treble active ~4%
> of frames, band bassDev 19%), so the spring integrated a thin, sparse signal → "musical but loosely connected"
> (Matt). The separated **stems** are 4× denser (the `other` = guitar/synth dev active 83%); driving the anchor
> off `bassStemDev ↔ otherStemDev` (+ four-stem fullness for the lift) gives the spring a continuous, melodic
> signal — the bass-vs-harmonic opposition is also more musical than the bass-vs-treble frequency split. The
> spring itself is unchanged: a denser signal is the connection lever, not looser damping (which reintroduces
> FA #4/#31 jitter). This pulls the lateral slice of uplift A forward; the rest (drums punch, vocals swell) stays
> the GLAZE.5 path.

## 7. Staged increments (proposed)

| ID | Outcome | Done-when |
|---|---|---|
| **GLAZE.1** ✅ | Design + reference curation. | ✅ references curated, source decoded, plan written; name + scope greenlit by Matt. |
| **GLAZE.2a** ✅ | Wire the dedicated Glaze branch + STUB shaders, test-reachable. **Blur-pyramid deferred to 2b** (its shader consumers + the 3-level state extension land together — no speculative unused infra; re-scope from the original "blur in 2a"). | ✅ engine+app build clean, swiftlint strict 0; `GlazeMVWarpAccumulationTest` runs the live warp→comp→swap path 64 frames at silence — non-black + no white-out; reduced-motion BUG-061-safe; PresetRegression + Nacre/FM accumulation byte-identical. |
| **GLAZE.2b.1** ✅ | **Blur-pyramid extension (3-level)** — `glaze_blur_fragment` (9-tap downsample) run progressively (prev→blur1 ½ → blur2 ¼ → blur3 ⅛); `MVWarpState` += `blurTexture2/3`; `setupMVWarp`/`renderGlaze` allocate + fill + bind to warp(blur1/2)+comp(blur1/2/3). Infra only — stub shaders don't sample yet. | ✅ pyramid allocates (128/64/32 of 256) + `glaze_blur` compiles + 3 passes run clean in the live path (no cmd error, still non-black/no-whiteout); PresetRegression + Nacre/FM byte-identical; lint 0. |
| **GLAZE.2b.2** ✅ mechanism-complete (M7 tuning pending) | Faithful base LANDED + the structure mechanism now WORKS. The port chain: 3-mass spring (CPU) → fragment swirl-poke; butterchurn's exact per-vertex **zoomexp radial zoom** (`pow(zoom, pow(zoomExp, rad·2−1))`, butterchurn.js L2637) + 4-term warp ripple; channel-flow emboss warp + bounding decay (the float-bloom fix); structure **seed** at the poke (the source's `wave_a 0.207` waveform role) + faint noise floor; multi-scale unsharp comp (blur1/2/3) + palette + contrast + sRGB. **Debug journey:** white-flood → (decay) flat → (zoomexp) still flat → **isolation diagnostic** (comp passthrough showed the *warp feedback was uniform*) → the missing piece was a **structure seed** (a uniform `+0.006` self-seed has no gradient for the flow/emboss to bite on). With the seed, the field develops glossy embossed flowing structure. **Current state:** reads as glossy contour-gel but **grainy + washed-out** vs the oracle's clean concentric rings — a visual-tuning gap (blur width / seed coherence / contrast), the M7 loop (Nacre took ~9 rounds). | Mechanism renders the glossy contour-gel register; non-black + no white-out gate green; → **Matt M7 tuning** (grain → smooth rings, contrast). |
| **GLAZE.3** ⏳ code-complete, pending live M7 | Base audio coupling (§6). **Anchor route** (`479f145` → stem-swapped `a34f9d3`): anchor X ← EMA(bassStemDev)−EMA(otherStemDev), anchor Y ← EMA(four-stem fullness), off the stem deviation primitives (D-026); the spring integrates → smooth momentum. Started on the bass/treble bands; Matt's M7 ("loosely connected") + the session analysis (bands near-dead, stems 4× denser) moved it to stems. **Seed fill** (`3d0691e`): the seed band rides the spring tail Y (`gu.seedY`) so it sweeps the frame with the audio (anchor alone moves only the poke; the seed was a fixed band — the 2b.2 band-like gap). **Wash-out:** energy-adaptive decay tried + **REVERTED** (`aa868d3`) — the wash is a base accumulation creep to white over MINUTES (both tracks, energy-independent), not an energy problem → **GLAZE.4** brightness-budget retune (comp lift/seed/decay, Matt's eye). | ✅ route firing in session-replay (real stems.csv via `GLAZE_SESSION_CSV`: pokeX span 1.085, tailY span 1.048); one-primitive-per-layer holds (FA #67); mechanism gate + replay green; calm "great"/musical (Matt); **wash → GLAZE.4**. |
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
