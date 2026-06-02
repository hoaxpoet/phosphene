# Dragon Bloom Spike 2 Kickoff — Bilateral symmetry without clipart

Hand this to a new Claude Code session verbatim. Do not summarise.

## What this is

Spike 2 of the Dragon Bloom preset (the faithful Milkdrop uplift of `$$$ Royal - Mashup (220)`). **Spike 1 is ✅ complete and gate-passed** (Matt: "Looks good" on Spotify session `2026-06-02T12-43-25Z`, 2026-06-02). The `direct + mv_warp` feedback bloom now reads as dancing to the music on both local-file and Spotify paths.

Spike 2's single job, per the plan (`docs/presets/DRAGON_BLOOM_PLAN.md` §6): **add the bilateral mirror fold so the bloom matches the reference's left-right-symmetric feathered-petal silhouette — without it reading as flat mirrored clipart.** The target (`docs/VISUAL_REFERENCES/dragon_bloom/01_target.png`) is a bilaterally symmetric warm fiery bloom. The current Spike-1 bloom is radially organic but NOT bilaterally symmetric.

This is a contained, single-preset, single-file shader increment. No engine changes, no new infrastructure.

## The one real risk (read this twice)

**Bilateral symmetry is a Phosphene anti-pattern when it reads as flat clipart symmetry** — Failed Approach #48 (the Arachne anti-reference was symmetric clipart). The plan §5 and the reference README are explicit about why Mashup (220) gets away with symmetry and you must too:

> "The symmetry works ONLY because the texture is rich; flat mirrored shapes = Failed Approach #48 (clipart symmetry, the Arachne anti-reference). **Mirror a feedback-warped field, never flat geometry.**"

The mechanism that keeps it from being clipart is the **rich feedback texture** (the feathered flow the mv_warp accumulator builds across frames). Spike 1 already produces that richness. Spike 2 must apply the mirror fold in a way that preserves it:

- **Mirror the bloom SILHOUETTE** (the polar-curve draw in the fragment) so the left and right halves share the waveform-derived shape → bilateral symmetry of the form.
- **Do NOT perfectly-mirror everything.** If both the fragment curve AND the mv_warp feather field are exact mirror images, the accumulated texture becomes too clean and reads as flat clipart. Keep an asymmetry source so the feathered texture stays rich: per-side hash jitter on the curve, an asymmetric bias in the warp feather field, or a slow asymmetric drift. This is the FA #44 per-instance-variation rule applied to the two mirror halves.
- **Success condition (the gate):** the symmetric output stays in the "rich feathered bloom" read, never the "flat mirrored clipart" anti-reference. Matt's M7 eyeball is the judge.

## Read these first, before touching code

1. **`docs/presets/DRAGON_BLOOM_PLAN.md`** — the whole plan. §5 (the symmetry risk), §6 (Spike 2 definition), §7 (build sequence), and the Spike 1 history block at the top (what shipped, the signal-liveness lesson).
2. **`docs/VISUAL_REFERENCES/dragon_bloom/README.md`** — read cover to cover. Per Failed Approach #63, authoring from the prompt text WITHOUT reading the README annotations is itself a failure. Note the mandatory traits (warm fiery palette red/orange/yellow with green accents; symmetric bloom silhouette; rich feathered texture) and the explicit anti-reference (flat mirrored clipart).
3. **`docs/VISUAL_REFERENCES/dragon_bloom/01_target.png`** — the target still. Look at it. The bloom is bilaterally symmetric about a **vertical** axis (left half mirrors right). Petal/moth forms radiate from a center.
4. **`docs/VISUAL_REFERENCES/dragon_bloom/target_animated.gif`** — the motion reference. Watch how the symmetric form breathes and the feathers stream.
5. **`docs/VISUAL_REFERENCES/dragon_bloom/source.milk`** — the source preset. Bilateral symmetry in Milkdrop comes from the symmetric motion-vector flow field (`nMotionVectorsX/Y = 12/9`) + the waveform draw, not from a per-pixel mirror equation. `nWaveMode=7`, minimal per-frame reactivity — the audio comes through the waveform shape + feedback dynamics.
6. **`PhospheneEngine/Sources/Presets/Shaders/DragonBloom.metal`** — the current Spike-1 shader (~319 lines). Study:
   - The fragment `dragon_bloom_fragment` (around line 102): `pRel = uv − centre`, `r = length(pRel)`, `ang = atan2(pRel.y, pRel.x)`, then `angNorm = (ang + π)/2π` → waveform sample index → polar curve. **The mirror fold goes here** — fold `ang` (or `pRel.x`) about the vertical axis before computing `angNorm`, so both sides sample the same part of the waveform.
   - The audio-driver block + the (layer × primitive × timescale) routing — DO NOT regress this. Spike 2 is geometry only; the alive-signal routing (signed `bass_rel` breathing, `spectralFlux` feather flow, `beatComposite` accent, `bass` Layer-1 brightness) stays exactly as is.
   - `mvWarpPerFrame` / `mvWarpPerVertex` — the warp field. Decide whether to mirror it too (risk: too clean) or leave it asymmetric (keeps texture rich). Recommended: leave the warp field as-is (asymmetric) so the feathered texture stays rich; the fragment-curve mirror alone gives the silhouette symmetry. Verify this reads right against the reference, not by assumption.
7. **`docs/SHADER_CRAFT.md §14.1`** (signal liveness) — only relevant if you add any NEW audio coupling. Spike 2 shouldn't need new audio routing; if you find yourself adding some, measure stddev on a real session first.
8. **`CLAUDE.md`** — Failed Approach #48 (clipart symmetry), #44 (per-instance variation), #39 + #63 (author against references + README), and the "Test in the production-grade rendering pipeline. No shortcuts." rule.

## Hard rules

1. **Mirror the feedback-warped field, never flat geometry.** The fragment curve is the brush; the mv_warp accumulator gives it rich feathered texture. Apply the fold so the symmetric form is built from that rich texture. If the output ever reads as flat mirrored clipart, break it with per-side jitter / asymmetric warp bias before shipping (FA #44 / #48).

2. **Do not regress Spike 1's audio routing.** The alive-signal routing (signed `bass_rel`, `spectralFlux`, `beatComposite`, `bass` Layer-1; beat boost bounded at 0.15) is the result of two live-test rounds and a measured liveness diagnosis. Spike 2 touches geometry (the mirror fold + anti-clipart jitter), not the audio→visual mapping. If you believe a routing change is needed, surface it to Matt with a stddev measurement first — do not silently retune.

3. **Test through the production pipeline.** `DragonBloomMVWarpAccumulationTest` already runs the live scene → warp → compose → swap chain for 60 frames with three audio modes (silence / LF-like / Spotify-like) and the `radiusMotion` metric. Extend it for Spike 2:
   - Add a symmetry assertion: sample the final accumulated frame and verify left-right mirror correlation is high (the bloom IS bilaterally symmetric) BUT not a perfect pixel mirror (the anti-clipart jitter keeps the two halves from being identical). A correlation in a sensible band (e.g. > 0.7 but < 0.999) captures "symmetric but textured, not flat-mirrored."
   - Keep the existing `radiusMotion` / brightness / no-clip assertions green (Spike 1 regression-lock).
   - Env-gate any new heavy diagnostic the same way (`DRAGON_BLOOM_MVWARP_DIAG=1`).

4. **Mid-session sanity = side-by-side against `01_target.png` + the gif, NOT self-judgment.** Per FA #63, render a frame (the env-gated harness writes PNGs to `/tmp/dragon_bloom_mvwarp_diag/<ISO>/`) and compare it against the named reference images. "Looks reasonable" is not verification.

5. **No golden-hash drift without surfacing.** If `PresetRegressionTests` hashes shift for Dragon Bloom, that's expected (the silhouette changed). Regenerate per the existing `UPDATE_GOLDEN_SNAPSHOTS` flow and note it in the closeout — but confirm no OTHER preset's hash moved (the change is Dragon-Bloom-only).

## Suggested build sequence

1. Re-read the references (rule above). Note exactly what axis the symmetry is about (vertical, per `01_target.png`) and how many "petals" / lobes the reference shows.
2. Add the mirror fold to the fragment polar-curve sampling. Simplest form: fold `pRel.x = abs(pRel.x)` (or fold the angle about the vertical axis) before computing `ang`/`angNorm`, so the right half's waveform draw is mirrored onto the left. Verify it produces a bilaterally symmetric silhouette in the env-gated render.
3. Render + compare against `01_target.png`. If it reads as flat clipart, add per-side variation: a per-side hash offset on the waveform sample index, or a small asymmetric phase in the warp feather field, so the two halves share the silhouette but differ in texture detail.
4. Tune until the render sits in the "rich symmetric feathered bloom" read. Use the harness PNGs + side-by-side comparison each iteration.
5. Extend the test (symmetry-correlation assertion). Run the full preset-side sweep (`PresetAcceptance|PresetRegression|PresetLoader|DragonBloom`) + the env-gated diag. App build.
6. Closeout (see below). Matt M7 against `01_target.png` + a live Spotify session is the gate.

## Decision points for Matt (surface before or during, as they arise)

These are product-level (per CLAUDE.md "Decisions presented to Matt must be framed in product-level language"). Frame them in what-the-viewer-sees terms, with a recommendation + default:

- **Symmetry axis / lobe count** — vertical mirror (per `01_target.png`) is the obvious default; confirm if the reference reads otherwise. If the fold introduces a choice of how many petals/lobes, frame it as "how many petals does the bloom have" with a recommended value, not a code parameter.
- **How strict the symmetry reads** — "perfectly mirrored (cleaner, risks clipart)" vs "mirrored silhouette with textured halves (richer, matches reference)". Recommend the latter; it's the FA #48 mitigation. Let Matt see both renders if it's a close call.

Do not ask Matt to choose shader constants (fold strength, jitter amplitude, hash seed) — make those yourself and show him the visual result.

## Done-when criteria

- [ ] The bloom is bilaterally symmetric (matches `01_target.png`'s left-right-mirror silhouette).
- [ ] The symmetric output reads as a rich feathered bloom, NOT flat mirrored clipart (FA #48). Confirmed by side-by-side against the reference, not self-judgment.
- [ ] `DragonBloomMVWarpAccumulationTest` symmetry assertion passes (high left-right correlation, but not a perfect pixel mirror).
- [ ] All Spike 1 regression assertions still green (`radiusMotion`, no-clip, bloom-not-collapsed).
- [ ] Full preset-side sweep green (4 acceptance × 17 + 3 regression × 17 + DragonBloom + PresetLoader count). Golden-hash drift, if any, is Dragon-Bloom-only and regenerated deliberately.
- [ ] App build green.
- [ ] Env-gated render PNG written + compared against `01_target.png` in the closeout.
- [ ] Matt M7 on a live Spotify session: the bloom is symmetric AND still dances AND reads rich (not clipart). This is the gate.
- [ ] Docs: `DRAGON_BLOOM_PLAN.md` status → Spike 2 done / Spike 3 next; `ENGINEERING_PLAN.md` Spike 2 entry; `DECISIONS.md` only if a Spike-2-scope decision warrants it (Spike 1 = D-135; a Spike 2 decision would be a new ID — grep `^## D-` first, next new is likely D-136+).
- [ ] Local commit on `main` (`[dragon-bloom]` prefix). Do NOT push without Matt's "yes, push."

## What success looks like

A live Spotify session shows the Dragon Bloom as a warm fiery **bilaterally-symmetric** feathered bloom — the left and right halves mirror each other in overall form, but the feathered texture is rich and alive (not a flat stamp), the bloom breathes with the bass and the feathers stream with the spectral flux, and it matches `01_target.png`'s character. Then Spike 3 (warm palette via valence/centroid + per-stem feather tinting) is the last build step before M7 polish rounds toward certification.

## Context you don't have to rediscover

- **Spike 1 shipped 7 commits** (`d380ed00` → `3491ed8f`, all on `origin/main` as of 2026-06-02). The skeleton, a waveform-RMS-normalisation fix (raw slot-2 buffer is NOT AGC-normalised; tap path is quieter than LF), and a signal-liveness re-tune (route to signed `bass_rel` + `spectralFlux` + beat, not the structurally-dead `bass_dev`/`mid_att_rel`).
- **Two open bugs, neither blocks Spike 2:** BUG-025 (P3 cosmetic ~2s cold-start flash, first-onset only) and BUG-027 (structural: positive deviation primitives near-dead for non-dominant bands — the reason Spike 1 routes to signed `*_rel` not `*_dev`). Do not try to fix these in Spike 2.
- **The preset is `family: "hypnotic"`, location `Shaders/`, no `inspired_by` provenance block** (Spike 1 scope). Whether to adopt the Phase MD `milkdrop_inspired` framework (rename family, relocate to `Shaders/Milkdrop/`, add provenance + settings toggle + CREDITS) is a SEPARATE decision deferred to Matt — do not silently adopt it in Spike 2.
