# Dragon Bloom — Milkdrop Uplift Plan (from `$$$ Royal - Mashup (220)`)

**Status:** **✅ DONE + CERTIFIED (2026-06-02, D-138).** L4 (rich warm fill) + the full music response shipped and the preset is certified (Matt live M7 across 5 Spotify tracks + a local file). The L4 struggle resolved by replicating butterchurn's render loop wholesale from its source rather than patching Phosphene's mv_warp piecemeal (FA #70). The faithful loop facts (no-decay custom warp, 8-bit feedback clamp, waves-normal-alpha-on-top, comp echo/gamma/invert display-only, symmetry-from-echo, 32×24 mesh) + the music response (each-arm-an-instrument, bass breathing, per-arm flares, comp-stage beat pump, energy-weighted tumble) are in **D-138**. The historical Spike/layer narrative below is retained as the record of how it got here.

**Historical status (pre-D-138):** **Spike 1 ✅ PASSED.** **Spike 2 (bilateral symmetry) ✅ symmetry confirmed by Matt M7 2026-06-02** ("looks symmetric, can't see the line of symmetry" — symmetric, no clipart seam). **BUT Matt M7 also surfaced: "not really seeing petals yet."** Investigation (reading `source.milk` + standing up the live butterchurn reference) found **Spike 1's mechanic ≠ the reference's mechanic** — see §0 (Mechanic decode). The live reference is now **faithful** (the converter botched the HLSL warp shader → hand-written GLSL fix in `tools/dragon_bloom_reference/`; it reproduces the warm feathered bloom matching the gif/still). **Matt reframed this as an UPLIFT** (not a literal copy) and approved (2026-06-02) the **feedback-native uplift** with strands ← **drums/bass/vocals** stems — see §0 "The uplift approach" (D-137). **L1 (strands←stems), L2 (petal warp + bilateral mirror), L3 (chromatic), L5 (warm palette) all ✅ DONE 2026-06-02** — the bloom now renders as a warm fiery bilaterally-symmetric feathered bloom matching the reference family (offline diag verified per layer; L2 Matt-M7-confirmed symmetric live). **Remaining: L4 — the rich warm FILL.** Matt M7 (2026-06-02): the bloom reads dull/desaturated, pixelated, bright only at centre. The empirical recipe is now measured from the faithful oracle (§0 L4): full warp shader (normalise+resample = saturated fill) + `bInvert=1` (warm) + fast fill (video echo), in that order (invert only works once filled). A focused, grounded next increment — NOT tuning. Plan approved 2026-06-01; Faithful uplift of `$$$ Royal - Mashup (220)`. References at `docs/VISUAL_REFERENCES/dragon_bloom/`.

> **New-session start here:** read §0 (Mechanic decode) + `tools/dragon_bloom_reference/README.md` + `docs/VISUAL_REFERENCES/dragon_bloom/README.md`. The reference loop and the mechanic understanding are done; the work is the §0 layered faithful port (L1 → L5). The committed Spike-2 fold (`angFold` in `DragonBloom.metal`, D-136) + the production-pipeline test (symmetry-correlation gate) stay; the polar-ring *brush* is replaced in L1.

> **Spike 1 history (3 commits + 1 re-tune, 2026-06-01 → 2026-06-02).** Shipped `d380ed00` (skeleton, D-135). Two live-test rounds against Matt's Spotify playlist surfaced and fixed two issues: (1) raw waveform amplitude is path-dependent and NOT AGC-normalised → in-shader RMS normalisation (`cffefe65`); (2) the Spike-1 audio routing drove motion from primitives that are structurally near-dead on bass-dominant music (`mid_att_rel` feather flow ≈ 0, clamped `bass_dev` breathing ≈ 0) → re-tuned to signals measured alive on both paths (signed `bass_rel`, `spectralFlux`, beat) in `0ceef58f`. That round also corrected a misdiagnosis (BUG-025 root cause), shelved an unnecessary AGC increment (AGC.1), and filed the real structural issue (BUG-027) — see `docs/ENGINEERING_PLAN.md` Dragon Bloom entries + `docs/SHADER_CRAFT.md §14.1` (signal-liveness rule born from this). **The lesson for Spike 2/3: verify audio primitives are alive on the target music by measuring stddev on a real session — don't trust a primitive's name.**

**Reference:** `$$$ Royal - Mashup (220)` (cream-of-crop `Dancer/Petals/`). Matt's pick to start — "sufficiently different from other presets" (fills the glowsticks/feedback register Phosphene lacks; not close to any certified preset).

---

## 0. Mechanic decode (from `source.milk`) — READ THIS FIRST (2026-06-02)

**Spike 1's mechanic is NOT the reference's mechanic.** Spike 1 draws a flat
polar-waveform *ring* at a fixed radius — structurally an annulus that reads as a
fuzzy fiery ring with a dark hole, no petals (Matt M7 2026-06-02, session
`2026-06-02T13-37-09Z`). Reading `source.milk` line-by-line (and confirming it
live in butterchurn — see `tools/dragon_bloom_reference/`) shows the actual
`$$$ Royal - Mashup (220)` is a different program:

1. **The brush = three tumbling 3-D spectral "helix-strands"** (`wavecode_0/1/2`,
   one per band — mid / bass / treble via the `mod = if(below(<band>_att,1.8), …)`
   line). Each strand is a vertical line (`oy = sample*mod`) with a fine spiral
   wound around it (`ox = 0.5*sin(sp)*sin(sample·π)*vol`, `oz = …cos(sp)…`,
   `sp = sample·6.28·8·8·4`), tapered at both ends by `sin(sample·π)`, then
   **rotated in 3-D** by time-varying `xang/yang/zang` (each strand at different
   rates), perspective-projected (`x = ox·fov/oz + 0.5`, then `x = (x−.5)·0.75+.5`),
   drawn **additively** (`bAdditiveWaves=1`, `wave_alpha≈4.1`). The "petals" are
   these projected tumbling blades; bilateral symmetry falls out of the projection
   + `oz = abs(oz)−2`.
2. **The petals' radial structure = a 5-fold angular zoom in the per-pixel warp**:
   `mod = sin(ang·5); mod = mod^5; zoom = 1 + abs(0.01·mod)` — a sharp 5-lobe
   angular function modulating the feedback zoom. Spike 1's warp is a uniform
   zoom + swirl and can only make a fuzzy ring.
3. **The feathering = the tumbling strands smeared through a heavy feedback field**
   (`fDecay=0.95`, video-echo `α=0.5`, baseline `zoom=0.99951` slightly inward,
   `warp=0.01`). Builds over ~20 frames.
4. **The green/red accents = a chromatic colour-separation warp shader**
   (`warp_1..21`, HLSL): normalises colour then pushes R→G→B in different
   directions + error-diffusion dither.

**The faithful port therefore rebuilds the brush + warp**, it does not tune the
Spike-1 ring (tuning a structurally-different renderer = Failed Approach #49).
Matt approved the faithful port + standing up the live reference (2026-06-02).

**Live reference:** `tools/dragon_bloom_reference/` runs the real preset in
butterchurn (WebGL Milkdrop) so the port is compared frame-by-frame against the
truth, not just `01_target.png`. Confirmed visually: dark-field bloom of
iridescent tumbling strand-petals, bilaterally symmetric, feathered — the form,
motion, feathering and symmetry all match `01_target.png`'s structure (the still's
warm fiery palette is a per-moment/palette difference, addressed by the palette
layer). Harness notes (audio-boost, invert-off) in that dir's README.

### The uplift approach (Matt-approved 2026-06-02) — D-137

This is an **uplift**, not a literal transcription (Matt 2026-06-02): translate
the preset's *identity* onto Phosphene's platform and use the technologies
Milkdrop/butterchurn never had. Matt approved the **feedback-native uplift** —
stay in Phosphene's proven mv_warp feedback register (where the original's charm
lives and where Phosphene reliably succeeds), uplifting along three axes:

1. **Strands ← real stems (the headline musical uplift).** Milkdrop drives its 3
   strands by mid/bass/treble FFT bands. Phosphene has stem separation — map the
   3 strands to **drums / bass / vocals** (Matt's pick); `other` tints the
   palette. Each arm of the bloom *is* an instrument. Driven via deviation
   primitives (D-026); stems available from frame 1 via StemCache.
2. **HDR-glow strands + ACES** (vs Milkdrop's 8-bit clamped additive).
3. **valence + spectral-centroid warm palette + per-stem tinting** (the old
   Spike 3) so warmth tracks the song.

**Recommended AGAINST (Matt agreed):** a full ray-march / 3-D volumetric rebuild
— it changes the preset's identity, is the high-fidelity-hero register that has
stalled before (Drift Motes / Ferrofluid / Aurora Veil), and the original's magic
is feedback, which mv_warp already nails. A 3-D depth exploration, if ever wanted,
is a separate spike, not the main path.

**Engine surfaces needed** (modest — far short of a ray-march rebuild): (a) a path
to **draw the 3 strands** (the `per_point` projected points — prototype cheapest:
procedural-vertex strand geometry vs fragment splat); (b) a **chromatic
colour-transform in the mv_warp compose** (small shader add).

**Layered build (each verified against the now-faithful live oracle + gif/still):**
- **L1 — Strand brush ← stems. ✅ DONE (2026-06-02, commits L1a `1ca736c1` + L1b `2dc05ed1`).**
  Transcribed the `per_point` tumbling-strand math; 3 strands driven by
  drums/bass/vocals (stem-gated alpha = `bModWaveAlphaByVolume`); drawn as
  additive instanced line strips into the mv_warp scene texture (new engine
  surface: `setSceneGeometry` + `RenderPipeline+SceneGeometry`). The Spike-1/2
  ring + D-136 fold are retired (strands carry their own symmetry via `oz=abs(oz)`).
  Renders as feathered tumbling blades, stem-coupled, no clip
  (`DragonBloomMVWarpAccumulationTest`, parity-rewritten). NOT yet symmetric/warm/
  full — that's L2–L5. HDR glow deferred (sceneTexture is 8-bit; needs float +
  tonemap, a later refinement). *Supersedes Spike 1's ring.*
- **L2 — `per_pixel` petal warp + bilateral mirror. ✅ DONE (2026-06-02, commit `f5b622af`).**
  Ported the source `per_pixel` warp verbatim into `mvWarpPerVertex` (5-fold
  `sin(ang·5)^5` angular zoom + concentric rotation) — adds the feathered/swirling
  texture. **Finding:** the per_pixel warp does NOT by itself symmetrise the
  tumbling strands (verified — symmetry fell to 0.19). So bilateral symmetry is
  GUARANTEED by mirroring the brush (6 instances = 3 stems × {original, vertical
  mirror}), the Spike-2-validated approach — symmetric form, rich (non-flat-mirror)
  texture (corr 0.78). Renders as a bilaterally-symmetric feathered petal bloom.
  Warm palette / density / chromatic still to come.
- **L3 — Chromatic colour-separation. ✅ DONE (2026-06-02, commit `74d23eee`).**
  Ported the source warp-shader R→G→B transfer into the shared `mvWarp_fragment`
  (applied to the aged feedback), per-preset gated by a `chromaticMix` uniform
  (0 ⇒ identity, so other mv_warp presets are byte-identical — PresetRegression
  confirms). Wired on for Dragon Bloom via `setMVWarpChromatic`. Adds the colour
  cycling + green/red fringing. (The optional chromatic-zoom *resample* — spatial
  aberration — is deferred; the transfer is the main colour effect.)
- **L5 — warm fiery per-stem palette. ✅ DONE (2026-06-02, commit `68081ffc`).**
  Warm per-stem hues (drums=orange, bass=ember-red, vocals=gold) × valence +
  spectral-centroid warmth, floored vivid. With L3's transfer → "warm fiery with
  green accents." The bloom now matches the reference family (warm, bilaterally
  symmetric, feathered). *Done out of L3→L5 order (warmth was the key missing trait).*
- **L4 — Rich warm FILL (REMAINING — the real gap).** Matt M7 (session
  `2026-06-02T15-48-51Z`): "dull, not saturated; pixelated; only the centre is
  bright." Round 1 (commit `ea182532`) recalibrated to real stem energies
  (~0.24–0.36, not 0.5), bumped brightness, and fixed the "pixelated" moire
  (spiral aliasing → `kStrandSamples` 512→1536). That helped but did NOT reach
  the bar. **Empirical finding from the faithful oracle (don't guess — this is
  measured):** the oracle's rich, saturated, FRAME-FILLING warm bloom comes from
  THREE mechanisms the port is missing, in this order:
  1. **Full warp shader (the FILL/SATURATION).** I ported only the R→G→B transfer
     (L3). The source warp shader also does: normalise feedback → hue; R-weighted
     `zoom = dot(hue,(1,0.975,0.95))`; **RESAMPLE feedback at that hue-zoom**;
     then the transfer. The resample + normalise is what fills the frame with
     saturated colour (verified: full-warp-no-invert in the oracle = fully
     saturated COOL fill, not a dull thread). Exact GLSL is in
     `tools/dragon_bloom_reference/index.html` `fixWarpShader`; the MSL port goes
     in `mvWarp_fragment`, gated by `chromaticMix` (identity at 0).
  2. **`bInvert=1` (the WARMTH).** The saturated fill is COOL (blue/cyan/green);
     invert flips it WARM (red/orange/magenta are the complements). Verified by
     toggling invert in the oracle. Must be IN the feedback loop (parity, FA #66),
     gated.
  3. **Fast fill (accumulation + spread).** The fill is a feedback attractor that
     develops over ~20 s in the oracle; likely accelerated by `fVideoEchoAlpha=0.5`
     (video echo — a 2nd feedback tap, not yet ported). **Ordering is critical:
     invert only works once the buffer is FILLED** — invert on an empty/black
     buffer flips black→white and breaks (tested: it whites-out + fails the test).
     So fill must develop (fast enough) before/with invert.
  Next increment: port (1) the full warp shader, then (3) ensure fast fill
  (video echo and/or decay), then (2) invert — verifying each step against the
  now-faithful oracle + a longer-accumulation test. This is the difference
  between the current dull-dim-centre render and the oracle's rich warm fill.
  *(The full-warp + invert port was attempted this session and reverted — it's
  correct in direction but invert-before-fill whited-out; needs the fast-fill
  step first. It's a focused next increment, not a tuning tweak.)*

Each layer: render offline against the **real recorded audio** (extend the diag
harness to load `raw_tap.wav`, not the synthetic sine) + compare to the live
butterchurn reference (`tools/dragon_bloom_reference/`, now faithful); Matt M7 at
layer milestones.

## 0b. Future exploration — 3-D depth spike (Matt, 2026-06-02)

**Matt wants to explore 3-D depth for this preset as a SEPARATE spike — and possibly a separate preset.** This is logged backlog, NOT part of the D-137 feedback-native uplift (which deliberately stays in the mv_warp register and rejected a 3-D rebuild as the main path). The idea: render the strands as real 3-D volumetric filaments with depth / lighting / self-shadowing (Phosphene's ray-march / SDF / PBR hero tech), rather than Milkdrop's flat 2-D projection.

Treat as its own spike with its own concept-viability gate (three-part bar) — it is the high-fidelity-hero register that has stalled before (Drift Motes D-102, Ferrofluid, Aurora Veil), so it needs an explicit grounding/feasibility pass before authoring. May warrant a distinct preset (e.g. "Dragon Bloom 3D" / a new name) rather than replacing the feedback-native Dragon Bloom — keep both options open. Do not start until the D-137 uplift has shipped and Matt greenlights the spike.

## 1. What it is (from the rendered still + source)

A warm, **bilaterally-symmetric feathered bloom** — fiery red/orange/yellow petal/moth forms radiating from a center, with rich flowing feedback texture. Calm-but-alive; the bloom breathes and the feathers flow.

**Source mechanic** (raw `.milk`): `nWaveMode=7` waveform + strong feedback (`fDecay=0.95`, video-echo `α=0.5`, `zoom=0.9995`, `warp=0.01`) + a **12×9 motion-vector flow field** (the feathering) + bilateral symmetry. Little per-frame equation reactivity — **the audio comes through the waveform shape itself** + the feedback dynamics. That's the essence: a waveform drawn each frame, smeared and accumulated by a warped, decaying feedback field into a symmetric feathered form.

## 2. Why this is the most confident target of the catalog

This is the inverse of the Goldengrove problem. Every part of the mechanic maps to an *existing, documented, reference-backed* Phosphene capability:

| Milkdrop mechanic | Phosphene equivalent | Status |
|---|---|---|
| Per-pixel `warp` + 12×9 motion vectors | `mv_warp` `mvWarpPerVertex()` (32×24 UV-displacement grid) | ✅ D-027; **Starburst** is a direct+mv_warp reference |
| `fDecay` / video-echo | mv_warp decay (warp pass × decay) | ✅ built |
| `nWaveMode=7` waveform | fragment shader reads **waveform buffer (slot 2, 2048)** + FFT (slot 1, 512) | ✅ GPU contract, all fragment encoders |
| Bilateral symmetry | mirror fold in the fragment UV | ✅ trivial |
| Warm palette / gamma | palette function (V.3 `palette()`) | ✅ |
| Feedback-as-musicality | the entire MV thesis: *"feedback turns simple audio into compound musical motion"* (CLAUDE.md FA #32, D-027) | ✅ proven |

**Architecture:** `passes: ["direct", "mv_warp"]` — the preset's fragment shader draws the waveform-bloom into the mv_warp scene texture; `mvWarpPerVertex()` authors the warp+feather displacement; decay accumulates the feathered trails. **Build from the Starburst pattern.** No new engine infrastructure.

## 3. 3-part bar

1. **Iconic subject deliverable at fidelity** — ✅ likely. The look is feedback-texture + palette, which Phosphene's mv_warp produces natively; no hero-material or painterly-fidelity risk (the thing that sinks me). Risk is *aesthetic tuning*, not structural.
2. **Clear musical role** — see §4. The waveform-driven bloom is load-bearing: the shape *is* the audio.
3. **Infrastructure-feasible** — ✅ strongest of any candidate. Existing mv_warp + waveform/FFT buffers + a reference preset (Starburst). Zero net-new render infrastructure.

**This is the lowest-risk preset build proposed all session** — proven mechanic, reference implementation, no new infra, and the fidelity register (procedural feedback + palette) is one Phosphene reliably hits.

## 4. The music→visual model (from real signals — the load-bearing part)

One primitive per visual layer (per `feedback_audio_layer_one_primitive`), every row a real `FeatureVector`/buffer field:

| Visual layer | Driver | Why it's a *moment you point at* |
|---|---|---|
| **Bloom shape** | the live **waveform buffer** (slot 2) drawn as the `nWaveMode=7` curve | the form literally *is* the music's waveform — the bloom's silhouette changes with the sound |
| **Bloom expansion / contraction** | `bass_dev` / overall energy → mv_warp zoom + warp amplitude | the bloom swells on energy, contracts in quiet — breathing with intensity |
| **Feather flow speed** | `mid_att_rel` (continuous) into `mvWarpPerVertex` displacement magnitude | feathers stream faster as the mids thicken |
| **Per-beat pulse** | `beat_composite` → a brightness/scale accent | the bloom flares on beats (Layer-4 accent, not primary) |
| **Palette / warmth** | `valence` + `spectral_centroid` | warm/fiery on bright/positive, cooler/deeper otherwise |
| **Per-instrument color** *(stretch)* | stems (`vocals`/`drums`/`other` energy) tint different feather bands | the bloom's colors separate by instrument |

The honest strength here vs. Goldengrove: feedback presets are *built* to turn audio into compound motion — the "does it read musical" question is the one register where Phosphene has a proven yes (D-027, the whole MV phase). The waveform driving the shape is a direct, non-ambient coupling.

## 5. The one real aesthetic risk — symmetry

Bilateral symmetry is a Phosphene anti-pattern when it reads as **flat clipart symmetry** (Failed Approach #48 — the Arachne anti-reference was symmetric clipart). Mashup (220) gets away with it *only because the feedback texture is rich* (feathered flow, not flat mirrored shapes). **Rule for the build:** the mirror fold is applied to a richly-feedback-warped field, never to flat geometry; if the symmetric output ever reads as clipart, break it with per-side hash jitter / asymmetric warp bias (the FA #44 per-instance-variation rule). This is a tuning constraint, not a structural blocker.

## 6. De-risking spikes (before the full build)

### Spike 1 — feedback-bloom feel on real music *(low risk, but the load-bearing check)*
Build the minimal version: a `direct + mv_warp` preset drawing the waveform with feedback decay + warp, driven by the §4 mapping, **no symmetry, no palette polish** (Starburst pattern, stripped). Render against ≥3 real tracks + `PresetSessionReplay`; Matt eyeballs whether the bloom *reads as responding to the music*. Lower risk than Goldengrove's spike (feedback-musicality is proven) — but still the gate before polish.
**Success:** "the bloom is dancing to this song." Go/no-go before symmetry/palette work.

### Spike 2 — symmetry without clipart — ⏳ implemented 2026-06-02, Matt M7 pending
Add the mirror fold; confirm it reads as *organic feathered bloom*, not *flat mirrored clipart* (FA #48 check). Tune the per-side jitter if needed.
**Success:** symmetric output stays in the "rich feathered" read, never the anti-reference.

**Implemented (2026-06-02).** Vertical-axis fold in `dragon_bloom_fragment`: `angFold = atan2(pRel.y, abs(pRel.x))` (`[-π/2, π/2]`, remapped to the full waveform `[0,1]`) → both halves draw the same waveform → symmetric silhouette. The mv_warp field is left **asymmetric** (its `(-p.y, p.x)` tangential swirl has rotational handedness) so the accumulator builds a different feather texture per half — symmetric form, rich non-identical texture. No per-side fragment jitter was needed (warp handedness alone diverges the halves: left↔right correlation 0.915 music / 0.985 spotify, both `< 0.999` flat-mirror bound). `DragonBloomMVWarpAccumulationTest` gained a `symmetryCorrelation` assertion (band `0.70–0.999`). The §5 "mirror a feedback-warped field, never flat geometry" rule is the realised design. Matt M7 on a live Spotify session is the gate.

## 7. Build sequence (build up from simple)

1. **Direct + mv_warp skeleton** (Starburst-pattern): fullscreen waveform draw → mv_warp feedback (decay + zoom). Spike 1 lives here.
2. **Warp/feather field**: `mvWarpPerVertex` per-vertex displacement = the 12×9 motion-vector analog, driven by §4.
3. **Mirror fold + anti-clipart jitter** (Spike 2).
4. **Palette + warmth** (valence/centroid-driven warm fiery palette).
5. **Beat accent + stem tint** (stretch).
6. **M7 polish rounds** — count unknown; `RENDER_VISUAL` contact sheet + `PresetSessionReplay` evidence + Matt M7 each round. Lower expected round-count than a hero-fidelity preset, but still iterative.

## 8. Decisions (resolved 2026-06-01)

1. **Name: Dragon Bloom.**
2. **Faithful** — match Mashup (220)'s warm symmetric feathered bloom closely ("it's gorgeous").
3. **Spike 1 approved** — proceed to the minimal `direct + mv_warp` feedback bloom on real music (Starburst-derived) as the first step, in a new session.

## 9. Recommendation

**Proceed to Spike 1.** It's a small, Starburst-derived build that proves the feedback bloom dances to the music before any symmetry/palette investment — and the whole thing sits on Phosphene's single most-proven capability (mv_warp / Milkdrop feedback), with a reference implementation and zero new infrastructure. This is the candidate I'm most confident about all session.

*(Verified this session: mv_warp D-027 + direct-preset support (Starburst); waveform slot 2 + FFT slot 1 on all fragment encoders; `feedback` vs `mv_warp` pass distinction; source mechanic from the raw `.milk`. Citations: CLAUDE.md FA #32 / D-027 line 457; ARCHITECTURE.md §Renderer mv_warp (lines 189/202/203), GPU contract slots 1–2; `RenderPipeline+MVWarp`/`+FeedbackDraw`; Starburst.json.)*
