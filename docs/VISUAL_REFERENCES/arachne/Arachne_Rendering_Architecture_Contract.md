# Arachne Rendering Architecture Contract

## Purpose

This contract defines the required staged rendering architecture for Arachne v8. It translates the design spec into implementation constraints, pass responsibilities, debug outputs, acceptance gates, and sequencing rules.

This file is authoritative for implementation. `ARACHNE_V8_DESIGN.md` remains authoritative for visual intent.

> **Visual target reframe (D-096, 2026-05-08).** All "must read as ..." acceptance gates below are aesthetic-family bars, not pixel-match contracts. A pass output that reads as belonging in the same visual conversation as the references — backlit macro nature photography, dewy webs, atmospheric forest, biological asymmetry, droplets as primary visual carrier — passes the gate. A pass output that reads like the named anti-reference (`09_anti_clipart_symmetry.jpg`, `10_anti_neon_stylized_glow.jpg`) fails it. Pixel-fidelity to a particular reference image is an explicit non-goal. Real-time constraints (Tier 1 14ms / Tier 2 16ms p95) are inviolable; if a fidelity feature cannot be achieved in budget, document the gap and pick the nearest achievable approximation. See `ARACHNE_V8_DESIGN.md §1.1` and `ARACHNE_3D_DESIGN.md §1.1` for the canonical reframe text and the system-wide application.

## Required passes

| Pass | Name | Required output | Depends on | Debug view required |
|---|---|---|---|---|
| 1 | WORLD | `arachneWorldTex` | mood + seed + audio atmosphere inputs | Yes |
| 2 | BACKGROUND_WEBS | background web layer | WORLD | Yes |
| 3 | FOREGROUND_WEB_GEOMETRY | foreground silk geometry | WORLD + web state | Yes |
| 4 | DROPLET_MATERIAL | refractive droplet layer | WORLD + foreground web geometry | Yes |
| 5 | ATMOSPHERIC_COMPOSITE | final scene atmosphere/light | WORLD + WEB + DROPLETS | Yes |
| 6 | SPIDER | spider layer when triggered | final scene + spider state | Yes when active |

## Minimum viable staged-composition milestone

Before any additional visual tuning, the implementation must support:

- WORLD-only debug output;
- WEB-only debug output;
- COMPOSITE output;
- offscreen WORLD texture or equivalent;
- visual harness contact sheets for each pass.

## Blockers

Arachne v8 cannot be certified if any of the following are missing:

- no WORLD pass;
- no way for droplets to sample WORLD;
- no pass-separated debug capture;
- no irregular branch-anchored frame;
- no refractive droplet material;
- no anti-reference rejection gate.

## Certification fixtures

Each phase must be rendered against:

- silence;
- steady;
- beat-heavy;
- sustained bass;
- high-valence / high-arousal mood;
- low-valence / low-arousal mood.

## Stop conditions

Stop implementation and report a blocker if:

- the engine cannot support offscreen render targets or equivalent compositing;
- droplet refraction cannot sample a previously-rendered world texture;
- the visual harness cannot capture pass-separated outputs;
- performance cost makes the staged architecture impossible at target resolution.