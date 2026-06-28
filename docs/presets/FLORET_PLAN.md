# Floret — Preset Plan

**Status: ✅ CERTIFIED (FLORET.4, 2026-06-27 — Matt's M7 "looks good").** Faithful port of butterchurn `Sunflower Passion` (2b base, LOOK confirmed "beautiful") + a 5-round M7 motion arc (3a beat-lock/swell/spin + internal vortex swirl; 3b drum-sparkle tried+removed → bass-onset kick). `certified: true`, flash-safe (multi-pass harness 0.00 flashes/s), in the production rotation. The 2 originally-greenlit uplifts (thin-film iridescence rims, per-stem routing) were NOT needed — the energy/beat coupling + bass kick satisfied Matt; deferred indefinitely. See **§10–§12** for the build/M7 history.
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
| **FLORET.2b** | ✅ Port the FAITHFUL BASE (z² warp + 3-fold radial-pulse high-pass comp + 4 seed-discs + palette cycle), **flash-safe**. Blur path decided: **in-comp multi-tap** (the source vortex pixel_eqs were vestigial — the warp samples z²(uv_orig), bypassing the mesh warp). Uplifts deferred. | ✅ `FloretMVWarpAccumulationTest` 7/7 over the live `renderFloret` path: non-black + no-white-out at silence (64 f) + reduced-motion format-safe + **flash sentry** (per-frame mean-luma Δ < 0.06 over 150 f — the ~0.5 Hz pulse breathes, doesn't strobe). Contact frames (silence + energy, full cycle) read as the source register — color-cycling fractal-filament bloom + sparkle tips on a dark ground; side-by-side vs `source 02_midcycle`. **→ Matt's live M7** (the 3-fold centering + white-highlight balance are M7 calls; FA #64 — not guessed solo). |
| **FLORET.3a** | ✅ Motion bundle (Matt's M7 pick): **beat-lock** (downbeat camera magnify ← cached `barPhase01`), **energy swell** (bloom inflation ← avg-stem EMA), **bass spin** (comp rotation ← `bassDev`). One primitive per visual channel (FA #67). | ✅ Routes proven to fire on Matt's real SOSB session (`test_motionRoutes_fireOnRealSession`: swell 0.01→0.50, spin 23.5 rad monotone, barPush 0→1.0); spin renders as visible rotation; `FloretMVWarpAccumulationTest` 8/8 (flash sentry still SAFE). **→ Matt's live M7** of the motion. |
| **FLORET.3b** | (deferred — Matt's call after the 3a motion M7) drum-sparkle + the 2 uplifts (thin-film iridescence rims, full stem routing). | per-route session-replay firing; one-primitive-per-layer holds; M7. |
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

- **Comp-stage blur (§3) — RESOLVED at 2b: in-comp multi-tap.** A 5-tap cross blur of `main` stands in for butterchurn's `blur1`; the foam-cell/filament read came through without an FM-style ¼-res blur target (no renderer edit). Revisit only if M7 wants finer/wider cells (then add the blur target).
- **Flash-safety vs faithfulness — RESOLVED at 2b: the breath is NOT a flash.** The source's near-black↔bright swing is a **~0.5 Hz** radial pulse — below the ≥3 Hz flash band — so it doesn't strobe; the flash sentry measures per-frame mean-luma Δ < 0.06 (D-157). Only a faint luma floor (0.02) is kept (stops a fully dead trough). The earlier "must breathe more gently" worry was over-weighted; comp gain is near the source's (3.8 vs ×4). The Harding multi-pass gate is the FLORET.4 cert step.
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

---

## 11. FLORET.2b — what landed (the faithful base)

The source ported verbatim into `Floret.metal` (FA #73 — port, don't re-derive), tuned by render against `docs/VISUAL_REFERENCES/floret/02_midcycle_fractal_bloom.png`:
- **`floret_warp_fragment`** — the z² conformal feedback fold (`z² of (uv_orig−0.5)·1.81 + (0.448,0.701)`, subtractive fade) + the 4 nested colour-cycling seed-discs near (0.3,0.4) (volume-gated; the source shapes folded in, Nacre pattern) + a faint palette wash. `mvWarpPerVertex`/`mvWarpPerFrame` are **identity** — the source warp samples `uv_orig`, so its per-vertex vortex pixel_eqs are **vestigial** (verified by render; the cousin of Nacre's `mv_x/y` debug-grid misread, FA #73).
- **`floret_comp_fragment`** — the 3-fold radial-pulse high-pass kaleidoscope: 4 layers at k·120° (the 4th duplicates the 0th), `dist = 1 − fract(k/3 + t/2)`, `inten = √dist·(1−dist)·8`, tile `fract(3·uvʀ·dist + 0.525)`, unsharp high-pass (`main − blur·0.9`, blur = inline 5-tap), `max`-combined, ×3.8, + a faint flash floor + sRGB decode.

**Decode/tuning learnings (durable):**
- **The breath is ~0.5 Hz → NOT a flash.** The pre-build "must breathe gently for flash-safety" worry was over-weighted: the radial pulse is far below the ≥3 Hz flash band. Measured per-frame mean-luma Δ < 0.06 (flash sentry). Comp gain sits near the source's (3.8 vs ×4); only a faint floor (0.02) is kept. (Contrast Nacre, where a *fast* brightness bump on a bright field DID read as a flash — there the issue was transient brightness, not a slow pulse.)
- **Brightness + seed density drive the read.** First render (gain 2.6 / seed 0.45) was too dim/sparse → warm-only, weak 3-fold. Gain 3.8 + seed 0.80 brought the white-clipping filaments + filled the 3-fold max-combine → matches the source's white+colour-accent register; the palette cycles orange→magenta→… across the loop.
- **The blur target wasn't needed** (the in-comp 5-tap suffices; §9).

**Open for M7 (Matt's eye, not guessed solo — FA #64):** the 3-fold *centering* reads more as an organic fractal swirl than a rigid centred mandala (the source morphs between both); white-highlight + green-accent balance. **`renderFloret` is the live path; M7 needs a build** (worktree → integrate to main or build the worktree; memory [[feedback_worktree_changes_reach_build]]). Render evidence regenerable via `FLORET_MVWARP_DIAG=1 FLORET_ENERGY=0.5`.

**FLORET.2b LIVE M7 (2026-06-26, Matt, worktree build, SOSB "Iamundernodisguise"):** ✅ **LOOK CONFIRMED — "It looks beautiful."** Gap: "little reaction to the music" (expected — 2b is time-driven) → Matt asked for motion → FLORET.3. He also noted the camera "appears to align to the beat" — but the 2b comp pulse is `time/2` (0.5 Hz ≈ this track's bar at 153 bpm), so that alignment was **coincidental**; the validated lever is a real beat-lock.

---

## 12. FLORET.3a — what landed (the motion bundle)

Matt's M7 pick (after the 2b look passed): the motion bundle — beat-lock + energy swell + bass spin. One primitive per visual channel (FA #67): warp-seed = swell, comp-magnify = beat push, comp-rotation = bass spin. Grounded in the attached session (FA #27 real audio) — see §Grounding below.

- **Beat-lock (comp camera magnify).** `barPush = pow(max(0, 1 − barPhase01), 2.5)` on the cached BeatGrid → the comp contracts the view ~6 % on the downbeat, settling over the bar (display-stage → no smear). The Nacre NACRE.4 certified move, re-aimed at the motion Matt validated by eye. Static on beatless tracks.
- **Energy swell (warp-seed inflation).** A ~0.5 s EMA of avg-stem energy (`floretSwellEMA`) scales the seed gate → the bloom fills/grows as the music fills out, recedes when sparse. **Driven off avg-stem, NOT raw mid** (see Grounding). Slow → not a flash.
- **Bass spin (comp rotation).** `floretSpin` accumulates `kSpinBase + kSpinBassGain·tanh(bassDev)` per frame → the whole 3-fold field rotates, faster when the bass is busy; a faint base rate keeps it turning at silence. Soft-saturated (bassDev spikes ~2.2×, the deviation-real-range lesson); accumulates so even a small rate reads as a clear swirl.

**§Grounding (the SOSB session — why the §6 plan changed).** Plan §6 proposed *mid→bloom* and *treble→sparkle*. The real track showed **raw mid + treble are nearly dead** (mid p90 0.08, treble p90 0.01 — classic shoegaze; energy is in bass + the synth wall). So mid→bloom / treble→sparkle would NOT read. Corrected: **swell ← avg-stem** (full-band-aware), **spin ← bass** (the dynamic band, p99 1.16 / max 2.46), **beat ← the cached grid** (strong + locked 75 %). Sparkle deferred to 3b (and will drive from the **drums stem**, not raw treble).

**Evidence (route firing on the real session, `test_motionRoutes_fireOnRealSession`):** swell 0.014→0.496 (tracks the arc), spin 23.5 rad total monotone (~3.7 turns / track, faster on bass), barPush 0→1.0 (full downbeat magnify, relaxes between). Spin renders as visible rotation (frame 90 vs 180). `FloretMVWarpAccumulationTest` 8/8 incl. the flash sentry (the beat magnify is motion, not a strobe). **→ Matt's live M7 of the motion** (does it read as "moving with the music"? is the beat-lock the cadence he wanted, or should the radial-pulse *rate* itself lock to the beat rather than a downbeat surge?). FA #64 — not tuned further solo.

**Durable:** `RenderPipeline.swift` is at the swiftlint `type_body_length` 300-line cap — Floret's 2 accumulators (`floretSwellEMA`/`floretSpin`) were folded onto the Nacre var line to fit. The next per-preset accumulator should not live on `RenderPipeline`; move per-preset mv_warp state into a small per-preset struct (the cap is the signal that the god-class needs that extraction — sibling of the `RenderPipeline+MVWarp.swift` file_length cap, §10).

### FLORET.3a tuning — internal swirl (Matt M7 #2, 2026-06-27, Love Rehab)

**M7:** ✅ "synced to the music, which is great" (the beat-lock reads) — but "the motion is subtle"; Matt asked to **drive the swirls *within* the pattern by music/energy**, "a little more activity to dial this in." **Diagnosis (Love Rehab session):** `bassDev` is modest on this track (p90 0.16 vs SOSB's p99 1.0), so the bass-driven global spin barely lifted off its floor; and there was **no music-driven *internal* swirl** (the z² fold was static — only the whole field rotated). **Fix:** (1) revived the source's vestigial 1/r² **vortex** as an **energy-scaled internal swirl** in `floret_warp_fragment` (rotate the fold's *sample* coord — not the seed — by `kSwirlGain·(base+swell)/(r²+core)`; accumulates through the feedback → the inner filaments churn faster as the mix fills out — the "swirls within"); (2) added an **energy term to the global spin** (`kFloretSpinEnergyGain·swell`) so the field also turns on full-band tracks where bass is modest. Route-firing on Love Rehab: spin total 23.5→**37.7 rad**, swell 0→0.44 (scales the swirl). Render (frame 60↔120) shows visible internal filament churn. `FloretMVWarpAccumulationTest` 8/8 (flash sentry SAFE). **→ Matt's live M7 of the amount** (he expects to dial it — "a little more"). Knobs: `kFloretSwirlGain`/`kFloretSwirlBase` (warp), `kFloretSpinEnergyGain` (Swift). **M7 #3 follow: swirl bumped 0.010→0.014 ("a touch too subtle"), `a9f9e9d`.**

### FLORET.3b — drum sparkle → **bass kick** (Matt M7 #3 pick, then M7 #4/#5 pivot)

> **Outcome: the drum sparkle was REMOVED (it could not be made visible — see below) and replaced by the bass-onset kick (Matt's pivot). The sparkle history is kept as the lesson.**

The first deferred uplift, chosen by Matt over the other motion options. **Drum-driven crystalline sparkle at the filament tips** — `floret_comp_fragment` adds a sparse, screen-fixed per-cell twinkle (`hash(floor(uv·density) + floor(time·rate))`, top ~7 % of cells) gated to the bright filament regions (`smoothstep` on luma — the "tips") and scaled by `fu.drumSparkle`. Display-stage (not fed back) → fine high-freq motion, no smear. **Driver:** `drumSparkle = drumsBeat` (the real percussion onset — phase-correct, and the dynamic channel since raw treble is dead on these tracks; used directly, no accumulator — RenderPipeline is at its type/line-length caps, §12-durable, and the look doesn't need a tail). This also restores the source's "circumflex" sparkle character. **Flash-safety:** the sparkle re-randomises which cells light each ~1/13 s, but it's sparse + tip-masked → tiny whole-frame luma; the flash sentry now runs a **drums-active pass** (`drums:0.7`) and confirms per-frame mean-luma Δ < 0.06 (twinkles, doesn't strobe). **Evidence:** route-firing on the SOSB session shows `drumSparkle` 0→1.0 (fires/varies); render (`FLORET_DRUMS=0.8`) shows glints along the filaments. `FloretMVWarpAccumulationTest` 8/8, lint 0. **→ Matt's live M7.** Knobs: `kFloretSparkleGain`/`Density`/`Rate`/`Thresh`.

**M7 #4 rework (Cherub Rock + SOSB: "not really seeing sparkle… too subtle, especially the MOTION").** Diagnosed first (proper-solutions): `drumsBeat` DOES fire live (session p90 1.0, 54 % of frames) and the wiring delivers it (`stemAnalyzer.analyze` → `setStemFeatures` → `latestStemFeatures` → `renderFloret`; same source as the logged `stems.csv`) — so it was purely **visibility**, not a dead route. The old sparkle was masked to the *clipped* peaks (luma 0.25→0.70 — where a white glint is swallowed), sparse, dim (gain 0.65), and only flared on the rare big hits (drumsBeat median 0.10). Rework: **gain 0.65→1.7** (white pops against the gold), **on the whole filament field** not just the peaks (`onField` luma 0.04→0.20), **round soft glints** (sub-cell falloff), a **slow grid drift** (`kFloretSparkleDrift` → the sparkle field MOVES = the "sparkle motion"), slower blink (13→6/s, reads as glints not noise), and an **always-on floor** (`kFloretSparkleBase 0.30`, Swift — drumsBeat adds the flare) since the median is low. Side-by-side render shows clearly more glints; flash sentry (drums pass) still SAFE. **→ Matt's live M7.**

**M7 #5 — sparkle REMOVED, pivot to the bass kick (Matt's call).** Even after the rework (2.6× brighter, always-on floor, drift), Matt: "still not seeing sparkling… wouldn't matter — still not visible." Decisive diagnosis (1:1 crop render): the drumSparkle uniform was correct live (min 0.30, max 1.0) and it *rendered* — but **the floret is already a dense field of bright orange "bulbs" (the high-pass filament tips), so fine white sparkle points camouflage into it** — no character separates a sparkle glint from the bulbs the pattern is made of. **★ DURABLE LESSON: don't add a fine bright-point effect onto an already-busy bright field — it can't be told apart from the field. A whole-field DISPLACEMENT/motion reads where added brightness-points don't.** Per the escalation rule (2 failed M7s) I brought the options to Matt rather than tune a 3rd time; he chose the **bass kick**. Sparkle code fully removed (no dead-concept code).

**FLORET.3b (final) — bass kick (radial shockwave).** On a bass onset the whole field punches/ripples outward (`floret_comp_fragment`: `uv1 += (uv1/|uv1|)·sin(r·freq − t·speed)·bassKick·amp`). A **displacement** channel — distinct from barPush (uniform magnify) + spin/swirl (rotation), FA #67 — so it's unmissable where fine points were lost. **Driver:** `bassKick = tanh(bassDev)` used directly (bassDev is impulse-like — p99 ~1.0, median ~0 — so it punches on onsets; a punch is sharp, no envelope/accumulator → also dodges the RenderPipeline caps, §12). **Flash-safe by construction** (displacement, not brightness) — the flash sentry's 2nd pass now drives `bassDev:0.8` and confirms Δluma < 0.06. Route-firing: `bassKick` 0→0.99; render (off vs `FLORET_BASSDEV=0.9`) shows the whole field rippled. `FloretMVWarpAccumulationTest` 8/8, lint 0. **→ Matt's live M7.** Knobs: `kFloretKickFreq`/`Speed`/`Amp`.
