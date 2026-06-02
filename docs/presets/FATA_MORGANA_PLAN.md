# Fata Morgana — port plan (butterchurn → Phosphene)

**Preset:** `martin [shadow harlequins shape code] - fata morgana` (a Milkdrop/butterchurn builtin).
**Goal:** faithful port of the **mirage** (custom warp + custom comp + custom shapes) onto Phosphene's
`mv_warp`, certified against the live oracle; **stem/beat uplift deferred** (Matt: "mirage first, decide
uplift later", 2026-06-02). Direct successor to Dragon Bloom (D-137/D-138); cardinal rule **FA #70** —
replicate butterchurn's render loop wholesale from source, do not patch-and-tune divergences.

**Decode artifact:** `/tmp/fata_faithful_checklist.md` (every element transcribed from
`/private/tmp/mdrender/node_modules/butterchurn/lib/butterchurn.js`). **Live oracle:** `fata-ref` (port
8734), `tools/fata_morgana_reference/` — real-session tap, boost 6×, clean GLSL (no fixWarpShader).

## What the preset is

A **mirage**: starfield night sky, a glowing horizon line, and a reflective rippling neon floor. Built
from **4 custom SHAPES** (40-gons; no waves), a **custom feedback WARP** shader, and a **custom procedural
COMP** shader (the mirage projection). Mechanic per `/tmp/fata_faithful_checklist.md`.

## Canonical render loop (identical structure to D-138)

`warp(prev)→target → blur(target)→blur1 → draw SHAPES on top of target → COMP(target)→display → swap`.
Shapes-on-top **are** the feedback; COMP is **display-only**. The custom warp **bakes its own decay**
(`×0.98 − 0.02`); the per-frame `decay` baseVal is unused. A custom comp **fully replaces** fixed-function
comp — so **no** gamma/darken/echo/invert is applied (those baseVals are ignored; verified in source).

## Reuse (from D-138) vs net-new

**Reuse:** the mv_warp loop driver (`drawWithMVWarp`), 8-bit feedback (`feedbackFormat`), the prev↔target
swap, the scene-overlay draw hook (`drawSceneGeometryOverlay` is where shapes go — on top of the warp
target), `bindNoiseTextures` (Phosphene's `noiseHQ`/`noiseLQ` map to the comp's `noise_hq`/`pw_noise_lq`),
the real-session-replay diag pattern (`DragonBloomMVWarpAccumulationTest`), and the gating discipline
(every other mv_warp preset stays byte-identical — `PresetRegression`).

**Net-new (3 GPU surfaces):**
1. **Preset-overridable warp + comp fragment functions.** The mv_warp pipeline currently hardwires the
   shared `mvWarp_fragment` / `mvWarp_blit_fragment`. Add name-based override: a preset may compile
   `<preset>_warp_fragment` / `<preset>_comp_fragment`; the bundle uses them when present, else the shared
   defaults. (Cleaner than overloading the shared gated shaders with a third behaviour — keeps the
   byte-identical guarantee trivially, siblings-not-subclasses per D-097.)
2. **Blur-of-previous-frame** bound to the warp pass. Phosphene has no blur-mip chain; approximate the
   butterchurn `blur1` with a small separable/multi-tap blur of the prev frame, stored in colour space
   (so warp `scale1=1, bias1=0`). Only generated for presets that request it (gated).
3. **Custom-SHAPE draw encoder.** TRIANGLE_FAN n-gons (center = primary rgba, rim = secondary r2/g2/b2/a2),
   per-shape blend (additive vs normal), per-instance transforms, optional textured sampling of the prev
   frame. Distinct from the line-strip strand path. A `FataShapes` geometry conformer + its own encode
   pass (binds prevTex; one draw per shape × instance) invoked on top of the warp target.

New per-frame warp/comp uniforms (CPU-computed, fata-scoped): `roam_sin`/`slow_roam_sin` (time), `q1`/`q2`
(beat-rotation `cos/sin(rott)` from the frame_eqs accumulator), `rand_preset` (fixed vec4), `time`,
`texsize`. Beat detection (`is_beat`) for the rotation accumulator runs CPU-side from `bass/mid/treb`.

## Build order (each layer compared against the oracle; Matt M7 per layer)

- **L1 — Mirage substrate (warp + comp + blur), no shapes.** Get the starfield/horizon/floor and the
  feedback warp reading right against the oracle on a near-empty field. Milestone: floor reflection +
  horizon glow + stars present, stable, no GPU stall.
- **L2 — Shapes on top.** The 3 additive neon blobs (sized by `bass_att`/`mid_att`/`treb_att` — the source
  uses overall band attack; that IS the faithful copy) + the faint textured shape 0. Reflected by the
  floor + smeared by the warp. Milestone: oracle-matching neon reflections in the floor.
- **L3 — Diag harness + certify.** Real-session replay test through the live dispatch path
  (warp→blur→shapes→comp→swap, ≥N frames). Matt live M7 across Spotify + local tracks. Cert flag + rubric
  ground-truth sets + closeout (DECISIONS **D-139**, CLAUDE.md, ENGINEERING_PLAN, RENDER_CAPABILITY_REGISTRY).

## Deferred (post-cert decision)

Stem/beat **uplift** (D-137 move): swap the source's band-attack shape sizing for Phosphene **stems**
(bass/drums/vocals deviation primitives, D-026), a comp-stage beat pump, energy-weighted time. Decide
as a separate increment after the faithful mirage certifies.

## Pitfalls carried from D-138

- Pipeline format must match the feedback texture format (8-bit) or the GPU **stalls** (beachball) at the
  preset transition — set BOTH `PresetLoader.feedbackFormat` and the app bundle format.
- Test the **live dispatch path**, not single-frame `preset.pipelineState` (production-grade testing rule).
- Aspect: authored 4:3; Phosphene is 16:9. Use the live aspect for shape `aspecty` (round n-gons); let the
  comp projection widen. Oracle is the comparison reference, not a 4:3 lock.
