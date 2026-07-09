---
name: shader-authoring
description: Invoke before writing or editing any .metal shader, MSL code, render pass, or GPU-facing Swift in Phosphene. Covers the GPU contract, quality floor, mv_warp obligations, and the desk-research/reference-porting rules that prevent tuning spirals.
---

# Shader Authoring

## Read before touching GPU code

- `docs/ARCHITECTURE.md §GPU Contract Details` — texture slots 0–11, buffer slots 0–8, preamble order, G-buffer, SSGI, mesh/ICB. Read before authoring any pass.
- `docs/ARCHITECTURE.md §Key Types` — FeatureVector / FeedbackParams / StemFeatures / SceneUniforms layouts are part of the GPU contract; update pointer + reference together.
- `docs/SHADER_CRAFT.md` — quality floor: detail cascade, ≥4 noise octaves, ≥3 materials, pale-tone ≤ 30 %, §12 rubric, §17 JSON sidecar schema. §3 noise recipes and §4 material cookbook are the building blocks — use `fbm8(`/`warped_fbm(` and `mat_*` calls, not single-octave noise or hand-rolled BRDFs.

## Standing mechanics

- Any preset with `mv_warp` in `passes` must implement `mvWarpPerFrame()` and `mvWarpPerVertex()` in its `.metal` file (linker error otherwise; reference: `VolumetricLithograph.metal`). New ray-march presets include `mv_warp` unless deliberately excluded (MV-2, D-027) — without per-vertex feedback accumulation they show only instantaneous audio state.
- `file_length: 400` is relaxed for `.metal` — good ray-march shaders run 800–2000 lines; do not split for lint. `MSLNamingTests` gates naming.
- Never `.storageModeManaged` buffers. Performance target 60 fps @ 1080p; ray march + SSGI ≈ 8 ms + 1 ms overhead — profile before shipping.
- Bit-identical golden gate: `PresetRegressionTests` dHash must hold across refactors.

## Desk research and reference discipline (FA #64 / #65 / #73)

**FA #73 (parent rule) — Don't rebuild what's already been built.** If a reference (paper, repo, demo) for the *exact* system exists — doubly so if Matt handed it to you — READ AND PORT IT before writing your own derivation. "I cited it in the design doc" is not using it. Tell-tale: iterating on tuning rounds to coax behavior the reference already specifies. Case study: Murmuration MM.1→MM.3 built force-based boids and burned an M7 round while Hoetzlein's Flock2 (MIT-licensed) natively produced everything being hand-derived.

**FA #64 — Stop guessing and do desk research** when: (a) ≥2 successive structural fixes failed to converge; (b) the failure mode has a recognizable name in graphics literature; (c) other implementations exist and are findable in 1–2 searches. Case study: six first-principles iterations on Ferrofluid's dot pattern; Quilez's smooth-Voronoi soft-min fixed it in 30 minutes.

**FA #65 — Do not negotiate away components of a working reference.** Default is to adopt the components producing its visual character verbatim; adapt only what differs in *context* (scale, audio routing, scene type). "Redundancy" claims against a working reference require rendering proof, not first-principles math. Tell-tale phrasing: "I think X is redundant with Y" without having tested removal — if you catch yourself writing that sentence, stop.

## Audio coupling

Routing rules (deviation primitives, one-primitive-per-layer, beat constraints) live in the `preset-session` skill — invoke it for any preset-facing shader work. Non-preset engine shader work: drive from deviation primitives per D-026 regardless.
