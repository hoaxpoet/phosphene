# Dragon Bloom — Milkdrop Uplift Plan (from `$$$ Royal - Mashup (220)`)

**Status:** **Spike 1 ✅ PASSED (Matt, 2026-06-02)** — "Looks good" on Spotify session `2026-06-02T12-43-25Z`. The bloom reads as dancing to the music on both LF and Spotify. **Next work item: Spike 2 (bilateral symmetry without clipart, §6).** Plan approved 2026-06-01; Faithful uplift of `$$$ Royal - Mashup (220)`. References at `docs/VISUAL_REFERENCES/dragon_bloom/`.

> **New-session start here:** read this plan + `docs/VISUAL_REFERENCES/dragon_bloom/README.md` + the Spike 1 history below, then build **Spike 2** (§6) — add the bilateral mirror fold with FA #48 anti-clipart per-side jitter. Then Spike 3 (warm palette via valence/centroid + per-stem feather tinting). The `direct + mv_warp` skeleton, the alive-signal audio routing, and the multi-frame production-pipeline test all exist (shipped Spike 1).

> **Spike 1 history (3 commits + 1 re-tune, 2026-06-01 → 2026-06-02).** Shipped `d380ed00` (skeleton, D-135). Two live-test rounds against Matt's Spotify playlist surfaced and fixed two issues: (1) raw waveform amplitude is path-dependent and NOT AGC-normalised → in-shader RMS normalisation (`cffefe65`); (2) the Spike-1 audio routing drove motion from primitives that are structurally near-dead on bass-dominant music (`mid_att_rel` feather flow ≈ 0, clamped `bass_dev` breathing ≈ 0) → re-tuned to signals measured alive on both paths (signed `bass_rel`, `spectralFlux`, beat) in `0ceef58f`. That round also corrected a misdiagnosis (BUG-025 root cause), shelved an unnecessary AGC increment (AGC.1), and filed the real structural issue (BUG-027) — see `docs/ENGINEERING_PLAN.md` Dragon Bloom entries + `docs/SHADER_CRAFT.md §14.1` (signal-liveness rule born from this). **The lesson for Spike 2/3: verify audio primitives are alive on the target music by measuring stddev on a real session — don't trust a primitive's name.**

**Reference:** `$$$ Royal - Mashup (220)` (cream-of-crop `Dancer/Petals/`). Matt's pick to start — "sufficiently different from other presets" (fills the glowsticks/feedback register Phosphene lacks; not close to any certified preset).

---

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

### Spike 2 — symmetry without clipart
Add the mirror fold; confirm it reads as *organic feathered bloom*, not *flat mirrored clipart* (FA #48 check). Tune the per-side jitter if needed.
**Success:** symmetric output stays in the "rich feathered" read, never the anti-reference.

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
