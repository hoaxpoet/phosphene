# Render Environment Scoping — Phase RMENV

**Status:** scoping, 2026-07-20. Matt chose the engine investment (option (b)) over shipping Kinetic Sculpture as luminous glowing-wire (option (a)), after KSRB.1 rendered proof that a polished-chrome-in-a-gallery look is above what the shared ray-march path currently delivers.

**Why:** three shared-renderer limits block metals from reading as metal and block a dark gallery ground — each confirmed by rendered evidence during KSRB.1/.2, not theory:
1. **Single-light deferred lighting.** `SceneUniforms` carries one light; the lighting path reads only `lightPositionAndIntensity` + `lightColor`. Chrome catches one highlight → reads flat.
2. **Uniform IBL environment.** `ibl_proc_env` is a smooth warm-grey gradient. A near-mirror reflecting uniform grey *is* uniform grey ("dull putty" — the KS README §4.1 anti-reference). Chrome needs a detailed, high-contrast surround to reflect (ref 07: "the surroundings are mandatory, not decorative").
3. **Shared pale sky background.** The miss path renders `rm_skyColor` (blue sky gradient) and the sky pixel ignores the per-preset light tint when fog is enabled. There is no per-preset dark-ground lever; all three KS references put the sculpture against a dark ground.

These are the "V.12 material lift" the KS README names — the work that got KS parked. This phase does it as a **shared renderer capability** (benefiting every ray-march preset — Lumen Mosaic, Ferrofluid Ocean, future architectural presets), with KS as the first consumer.

## The load-bearing design constraint — opt-in, byte-identical

**Every capability is additive and opt-in; a preset that does not opt in renders byte-identically to today.** This is what makes a renderer change to shared code safe: existing ray-march goldens (`PresetRegressionTests`) do **not** move — only presets that declare the new fields change. Without this, the phase would force a full golden re-baseline across the catalog (high-risk, high-noise). With it, each increment's gate is literally "all existing ray-march goldens byte-identical."

Concretely:
- Multi-light: the lighting loop must produce bit-identical output for `numLights == 1` as the current single-light path. Existing presets stay at one light.
- Environment: add a NEW selectable env type; the default remains the current `ibl_proc_env` interior / procedural sky. Existing presets don't set the selector.
- Background: add a per-preset background selector; the default remains `rm_skyColor`.

## GPU-contract risk

`SceneUniforms` is defined in **four** places that must stay in lockstep (a mismatch is a silent memory-corruption class, not a compile error):
- `PhospheneEngine/Sources/Renderer/Shaders/Common.metal` (the Metal definition)
- `PhospheneEngine/Sources/Shared/AudioFeatures+SceneUniforms.swift` (the Swift struct)
- `PhospheneEngine/Sources/Presets/PresetLoader+Preamble.swift` and `+WarpPreamble.swift` (the two shader-preamble mirrors)

Current layout: Camera 64 B (4×SIMD4) · Lighting 32 B (2×SIMD4) · Scene params 32 B (2×SIMD4) = 128 B. Growing the lighting block (a light array + count) and adding env/background selector scalars must preserve 16-byte SIMD alignment and update all four definitions plus `docs/ARCHITECTURE.md §Key Types` and `§GPU Contract Details` in the same commit. Prefer packing selectors into existing spare `.w` lanes where safe (audited — `sceneParamsB.w` is the SSGI radius override and is currently writer-less, so it is NOT free-by-assumption; verify before reuse).

## Increment plan

- **RMENV.1 — Multi-light deferred lighting.** Expand `SceneUniforms` to an N-light array (proposed **N = 4**: key / rim / fill / accent) + a `lightCount`. Decode the full sidecar `scene_lights` array (already an array — today only the first entry is read). The deferred lighting loop sums Cook-Torrance over `lightCount` lights. **Gate:** all existing ray-march goldens byte-identical (proof: `numLights==1` path unchanged); a KS 3-light dev render shows distinct key/rim/fill highlights on the metal. Docs: §Key Types + §GPU Contract + registry lighting row.
- **RMENV.2 — Selectable high-contrast gallery IBL.** Add a second procedural environment (a gallery interior with real contrast — bright skylight bands, dark floor, some directional structure the chrome can pick up) selectable via a new `PresetDescriptor.environment` field; default keeps the current env. **Gate:** existing goldens byte-identical; KS chrome reflects legible detail instead of flat grey.
- **RMENV.3 — Per-preset background.** A background selector (dark gallery vs procedural sky) via descriptor field + a miss-path branch; default `rm_skyColor`. **Gate:** existing goldens byte-identical; KS renders a dark ground (pale-tone ≤ 30 % satisfied, form reads against negative space per ref 03).
- **RMENV.4 — Registry + contract docs.** `RENDER_CAPABILITY_REGISTRY` promotions (multi-light: Missing→Supported; environment selection: new row; per-preset background: new row) + the GPU-contract `SceneUniforms` layout doc + a DECISIONS entry.
- **KSRB.2 (resumes, as the first consumer).** KS declares ~3 lights + the gallery environment + the dark background, keeps chrome/aluminum/frosted-glass materials, and now the chrome reads as chrome. Regenerate the KS golden (deliberate). Then KSRB.3 audio.

## Open decisions for Matt

1. **Light count** — N = 4 (key/rim/fill/accent) is the recommendation; enough for a three-point studio setup + one accent, modest struct growth. More is possible but costs per-pixel BRDF work × lights on every ray-march preset.
2. **Sequence** — do the whole RMENV phase first, then resume KSRB.2 as its consumer (recommended — KS is the test bed but the capability is general), vs. interleaving. Recommend engine-first.
3. **Scope of the gallery environment** — procedural (cheap, tunable, no asset) vs. a baked/authored cubemap (richer, an asset to manage). Recommend procedural first; escalate to baked only if procedural can't hit the bar.
