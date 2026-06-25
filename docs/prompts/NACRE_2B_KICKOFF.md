# NACRE.2b Kickoff — port the look + the three uplifts

**Paste this (or "Resume NACRE.2b — follow docs/prompts/NACRE_2B_KICKOFF.md") to start the session.**

You are implementing **NACRE.2b**, the shader-craft half of the Nacre preset — a faithful
uplift of the Milkdrop preset `$$$ Royal - Mashup (431)` (the translucent refractive
"jello-mirror" cell-field) on Phosphene's `mv_warp`. NACRE.1 (design+refs) and NACRE.2a
(wiring + a stub) are **done and committed** (`374791d`, `1daab73`, `42641de` on branch
`claude/stupefied-volhard-554a97`, local/unpushed).

## Step 0 — MANDATORY session start (do before opening any .metal)

Run the preset session-start checklist: **[docs/PRESET_SESSION_CHECKLIST.md](../PRESET_SESSION_CHECKLIST.md)**. Concretely, read, cover to cover:
1. **[docs/presets/NACRE_PLAN.md](../presets/NACRE_PLAN.md)** §"NACRE.2 — Committed scope & architecture" + §1 (musical role) + §2 (temporal contract) + §6 (one-primitive-per-layer table). This is the contract.
2. **[docs/VISUAL_REFERENCES/nacre/README.md](../VISUAL_REFERENCES/nacre/README.md)** + the 3 annotated stills + `target_animated.gif` (the target) — and **[source_shaders.txt](../VISUAL_REFERENCES/nacre/source_shaders.txt)**, which is (431)'s **actual** warp/comp shaders + per-frame eqs. **Port these verbatim; do not re-derive (FA #73/#65).**

## Locked decisions (do NOT relitigate — Matt sanctioned these)

- **Faithful character base + three 2026 uplifts:** (1) **stem-instrument routing** (vocals→core, bass→swell/kick, drums→rim sparkle, harmonic *other*→iridescence shift); (2) **real thin-film iridescence + HDR** (replace (431)'s 2-px chromatic hack with `iridescence()`/`fresnel()`, hue←chroma/centroid; on `.rgba16Float` feedback); (3) **smooth-Voronoi refractive cells** (replace the `sin(4·uv)` lattice). Beat-grid/chroma-palette lock is **deferred** to tuning.
- **Architecture (load-bearing):** the signature look is a **DISPLAY-stage transform** in `nacre_comp_fragment` (it samples the feedback `warpTex` at texture 0; output is *not* fed back — Milkdrop comp semantics). The scene fragment (`nacre_fragment`) only draws **new** content (the core) and has **no feedback access**. The feedback loop itself is `mvWarpPerFrame`/`mvWarpPerVertex` (drift + zoom).
- **Wiring is done — NO renderer edits.** `nacre_comp_fragment` auto-selects via PresetLoader naming convention; `NacreUniforms` arrives at comp **buffer(1)** (populated by `NacreState.tick` → `directPresetFragmentBuffer`). HDR opt-in is already in `PresetLoader.feedbackFormat`.

## The work, in order

1. **Harness FIRST (checklist item: multi-frame before shader work).** Extend `PhospheneEngine/Tests/PhospheneEngineTests/Presets/NacreMVWarpAccumulationTest.swift` with a real multi-frame loop: drive `RenderPipeline.renderMVWarpToTexture` (the shared headless seam in `RenderPipeline+MVWarpHeadless.swift`) for ≥60 frames at **silence** and at **synthetic music**, read back the final frame, and assert it stays **non-black** and never **whites out**. Adapt `DragonBloomMVWarpAccumulationTest.runAccumulationLoop` (its private harness is the reference; the seam is shared). **Produce an early `RENDER_VISUAL=1` contact sheet before any look-tuning** (item 6 — rendered evidence early ends tuning spirals).
2. **Port (431)'s comp shader** into `nacre_comp_fragment` (from `source_shaders.txt`): 4-layer radial-pulse zoom `dist = 1 − fract(k/4 + t/18)` (k=0..3), luminance-Sobel emboss `dz`, sine-cell domain warp — then **swap the cheap bits for the uplifts**: emboss rims → real `iridescence()` (hue ← `nu.hueDrive` from centroid; band shift ← `nu.iriShift` from *other*); `sin(4·uv)` cells → **smooth Voronoi** (`smin`/Worley). **Inline** the iridescence/`smin`/Voronoi helpers into `Nacre.metal` (presets are self-contained — only `ShaderUtilities.metal` auto-merges; copy from `Utilities/PBR/Fresnel.metal`, `Utilities/Materials/Exotic.metal`, `Utilities/Noise/Worley.metal`).
3. **Stem routing.** Scene `nacre_fragment`: vocals→core brightness + waveform→core shape. `mvWarpPerVertex`: bass→cell swell + displacement-kick. `nacre_comp_fragment` (via `NacreUniforms`): drums→rim sparkle, treble→rim grain. Populate `NacreUniforms` in `NacreState.tick`. **Verify the exact Swift field names first** (MSL names are confirmed in `Renderer/Shaders/Common.metal`: `vocals_energy`, `bass_energy_dev`, `drums_energy_dev`, `other_energy`, `mid_rel`, `bass_dev`, `spectral_centroid`, `treb_att_rel`; the Swift `StemFeatures`/`FeatureVector` camelCase equivalents need a quick grep — there is **no** `treble_dev`, use `treb_att_rel`). Use **deviation primitives (D-026)**, never absolute thresholds on AGC values (FA #31). Hold **one primitive per layer per timescale** (FA #67 — NACRE_PLAN §6).

## Cautions

- **Faithful character first at silence**, audio coupling second (FA #65) — get the cell-field + chromatic/iridescent rims + slow palette right with time-only, then layer audio.
- **Watch HDR over-accumulation.** `feedbackFormat` is `.rgba16Float`; decay (0.94) bounds it, but the no-clamp float buffer can over-bloom — the white-out gate + contact sheet catch it. Tune `kNacreDecay`/core gain if it blooms to white (Dragon Bloom hit exactly this with a *no-decay* float loop).
- **Compare side-by-side against `(431)`** (`tools/milkdrop-render/renders/$$$ Royal - Mashup (431).gif`; re-render via `tools/milkdrop-render/render-gif.js royal_variants/*.json`) — never self-judge "looks reasonable" (checklist item 5).
- After each M7 round write the one sentence "what I now believe about why this is failing"; if it doesn't change between rounds, stop and re-scope (authoring-discipline escalation).

## Done-when / gates

Accumulation loop ≥60 frames, no white-out (silence + music); `RENDER_VISUAL=1 swift test --package-path PhospheneEngine --filter PresetVisualReview` contact sheet (silence/mid/beat) committed; side-by-side vs (431) reads as the same preset, **uplifted**; `swift test --package-path PhospheneEngine --filter Nacre` green; `xcodebuild -scheme PhospheneApp -destination 'platform=macOS' build`; `swiftlint lint --strict` 0 violations. Then **NACRE.2 closeout** (`Scripts/closeout_evidence.sh` block) + commit `[NACRE.2b] …`, and take the render to **Matt for M7** (do not flip `certified` — that's NACRE.4 after his live sign-off).

## Key files

- Author: `PhospheneEngine/Sources/Presets/Shaders/Nacre.metal` (stub now — the 2a comp is a palette tint to replace), `PhospheneEngine/Sources/Presets/Nacre/NacreState.swift` (`NacreUniforms` 64 B — extend fields as needed, keep Swift/MSL byte-matched).
- Scaffold/reference: `Shaders/DragonBloom.metal` (per-frame/per-vertex + scene pattern), `Renderer/RenderPipeline+MVWarpHeadless.swift` (`renderMVWarpToTexture`), `Tests/…/DragonBloomMVWarpAccumulationTest.swift` (loop to adapt), `Presets/PresetLoader+WarpPreamble.swift` (the mv_warp preamble: `MVWarpPerFrame`, `VertexOut`, `warpSampler`).
- Memory: `project_nacre_preset.md` carries this same state.
