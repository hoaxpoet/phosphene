# Aurora Veil Rendering Architecture Contract

## Purpose

This contract defines the required rendering architecture for Aurora Veil. It translates the design spec into implementation constraints, pass responsibilities, debug outputs, and acceptance gates.

This file is authoritative for implementation. `AURORA_VEIL_DESIGN.md` remains authoritative for visual intent.

> **Visual target reframe (D-096, 2026-05-08).** All "must read as ..." acceptance gates below are aesthetic-family bars, not pixel-match contracts. A render that reads as belonging in the same visual conversation as the references — real photographic aurora, green-base/magenta-crown stratification, multi-ribbon depth, continuous slow-compounding motion — passes the gate. A render that reads like the named anti-reference (`09_anti_neon_festival_aurora.jpg`) fails it. Pixel-fidelity to a particular reference image is an explicit non-goal. Real-time constraints (Tier 1 ~4 ms / Tier 2 ~1.7 ms p95) are inviolable; if a fidelity feature cannot be achieved in budget, document the gap and pick the nearest achievable approximation. See `AURORA_VEIL_DESIGN.md §1` and the visual-references README for the canonical reframe text.

## Required passes

Aurora Veil's rendering pipeline is intentionally minimal: a single direct-fragment shader composing all visual layers internally, wrapped by mv_warp's per-vertex grid feedback. The "passes" below are logical stages within that single pipeline, not separate Metal render passes.

| Pass | Name | Required output | Depends on | Debug view required |
|---|---|---|---|---|
| 1 | SKY | Vertical gradient + sparse stars rendered to scene texture | none | Yes |
| 2 | CURTAINS | 2–3 layered ribbons composited additively over SKY | SKY + audio inputs | Yes |
| 3 | HUE_PALETTE | IQ cosine palette evaluated per-fragment with vertical stratification + `vocalsPitchNorm` offset | CURTAINS + SpectralHistoryBuffer | Yes |
| 4 | MV_WARP_COMPOSE | Per-vertex grid feedback accumulator with current scene composited and presented to drawable | HUE_PALETTE output (= scene texture) + previous-frame accumulator | Yes |

## Minimum viable milestone (Session 1 scope)

Before any audio routing or multi-ribbon layering, the implementation must support:

- SKY-only debug output (gradient + stars, no ribbons);
- single-ribbon CURTAINS output (one ribbon over SKY, no hue stratification yet);
- HUE-applied COMPOSITE output (single ribbon with palette stratification);
- MV_WARP wired with conservative parameters (`baseRot = 0.0008`, `baseZoom = 0.0015`, `decay = 0.945`, `disp_amplitude = 0.005`);
- visual harness contact sheets for SKY-only, single-ribbon, full-composite.

`AuroraVeilSilenceTest` passes at this milestone — render at zero audio asserts non-black output and at least one drifting ribbon.

## Blockers

Aurora Veil cannot be certified if any of the following are missing:

- no `mv_warp` render pass wired (D-027 infrastructure);
- no access to `SpectralHistoryBuffer` at fragment buffer(5) for `vocalsPitchNorm` trail;
- no IQ cosine palette utility (`palette()` from `Color/Palettes.metal`, V.3);
- no `warped_fbm` / `curl_noise` / `fbm4` from `Noise/` utility tree (V.1);
- no `hash_f01_2` for procedural starfield;
- no way to capture pass-separated debug output for SKY / CURTAINS / COMPOSITE;
- no anti-reference rejection gate against `09_anti_neon_festival_aurora.jpg`.

## Certification fixtures

Each acceptance phase must be rendered against the standard fixture set:

- silence (`totalStemEnergy == 0`, all `*_rel` and `*_dev` at zero);
- steady mid-energy (`f.mid_att_rel ≈ 0.3`, `f.bass_att_rel ≈ 0.3`, no drum onsets);
- beat-heavy (drum onsets every ~500 ms, `stems.drums_energy_dev` peaks at 0.4);
- sustained bass (`f.bass_att_rel` held high for ≥ 4 s);
- high-valence (`f.valence ≈ 0.8`) — palette skews magenta-warm;
- low-valence (`f.valence ≈ 0.2`) — palette skews green-cool.

## Stop conditions

Stop implementation and report a blocker if:

- mv_warp amplitude becomes uncontrollable at the design's specified parameters (curtains smear into mush rather than producing slow-compounding motion);
- per-frame palette modulation rate produces visible jitter on rapid melodic phrases (open question §11.2 in design doc; mitigation is a 5-frame smoothing window on the SpectralHistoryBuffer read);
- the visual harness cannot capture pass-separated outputs (SKY-only, CURTAINS-only) — required for diagnostic review;
- performance exceeds Tier 1 budget at the specified scene complexity (3 ribbons, 800-density starfield, 32×24 mv_warp grid). Mitigation: drop to 2 ribbons before reducing star density.

## Acceptance gates per phase

**Session 1 — Single-ribbon foundation.**
- SKY-only debug renders gradient + stars correctly.
- Single ribbon visible against SKY.
- mv_warp accumulating without smearing.
- `AuroraVeilSilenceTest` passes.

**Session 2 — Multi-ribbon with parallax + audio.**
- 3 ribbons rendered with depth-scale dimming readable in COMPOSITE.
- All audio routes wired per design §5.6.
- `AuroraVeilContinuousDominanceTest` passes (continuous primary drivers dominate accents by >10×).

**Session 3 — Refine + cert.**
- Palette constants tuned against `02_palette_green_to_magenta_stratification.jpg` — green base + magenta crown clearly readable.
- mv_warp amplitudes tuned against `01_macro_curtain_hero_purple_green.jpg` — slow compounding motion, no smear.
- `AuroraVeilPitchHueTest` passes (ribbon hue shifts continuously with pitch sweep).
- Performance profile: p95 ≤ Tier 1 4.0 ms / Tier 2 1.7 ms.
- M7 review against `01`, `02`, `03`, `04` — passes aesthetic-family bar per D-096.
- Anti-reference gate: rendered output does NOT read like `09_anti_neon_festival_aurora.jpg`. If it does, return to Session 2 palette tuning.
