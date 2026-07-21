# Physarum / Agent-Network Substrate — Capability Closeout (paste-ready)

**Why this exists:** Filigree (certified 2026-06-28) introduced a reusable compute-agent-network substrate (`PhysarumGeometry` + three-kernel loop), but the capability registry doesn't list it and there's no authoring note. Per CLAUDE.md the registry is *mandatory to update when preset-architecture capabilities change* — so this is an overdue piece of Filigree's closeout. It's also what makes the next agent-network preset cheap instead of a re-discovery. Pure docs; no build needed. Proposed text below — paste into the cited docs on the Mac (mind the doc-budget gates).

---

## A. `docs/CAPABILITY_REGISTRY/RENDERER.md` — new capability row

> **Compute agent-network (Physarum / agent-deposit)** — **Supported.**
> Files: `Renderer/Geometry/PhysarumGeometry.swift` (a `ParticleGeometry` sibling, D-097), `Renderer/Shaders/Physarum.metal` (kernels `physarum_reset → physarum_agents → physarum_diffuse`, per-frame compute encoder with buffer barriers, ping-pong `r16Float` trail textures + atomic per-cell deposit), registered in `ParticleGeometryRegistry`.
> First consumer: **Filigree** (certified 2026-06-28), `passes: ["feedback","particles"]`.
> Perf: ~262k agents @ **0.66 ms/frame @ 1080p**; ~1M agents @ ~0.55 ms — large headroom.
> Coupling verdict (accepted by Matt 2026-06-27): physarum carries a **loose continuous-energy accompaniment, not tight event-sync**.

## B. Registry "Preset implications" update

- **Now buildable cheaply:** additional **continuous-energy** agent-network presets on the shared substrate (new color/parameter regimes, 36-Points variety) without new render-graph primitives.
- **Still blocked:** **tight beat-synced / structural-event-synced** agent presets — gated by (1) **BUG-065** (live BeatGrid drift 50–70 ms mid-track, 28% of frames outside the ~60 ms window) and (2) the substrate verdict above. Don't scope event-sync on this substrate until the grid is fixed and the sync is proven.

---

## C. Authoring note — "How to build a compute-agent-network preset"

Short reference (handbook or design-doc snippet) so the next one doesn't re-derive Filigree:

1. **Reuse `PhysarumGeometry` via `ParticleGeometryRegistry` — don't fork Filigree.** Siblings, not subclasses (D-097). Your preset supplies parameters + the fragment that samples the colorized trail; it does not copy the kernel loop.
2. **The substrate** is a per-frame 3-kernel loop (reset deposit accumulator → agents sense/steer/move/atomic-deposit → diffuse+decay+colorize), ping-ponging two `r16Float` trail textures. ~262k agents is the proven default; up to ~1M fits the budget.
3. **Drive the agent params** (sensor distance/angle, rotation angle, move distance) and deposit/decay from **continuous-energy deviation primitives** (`bassRel`, `energyDev`; D-026). This is the validated, certifiable coupling: loud → fine/busy/bright network; quiet → few/calm cells (Filigree's polarity; choose yours). Continuous energy is the primary driver (Audio Hierarchy Layer 1).
4. **36-Points variety:** make the params functions of the local trail value `x` (`p = p1 + p2·x^p3`) for regime variety; this is the per-section / per-track knob bank.
5. **One primitive per layer (FA #67):** don't route the same audio timescale into two visual layers — the substrate already encodes energy; pick a *different* primitive/timescale for any second layer.
6. **Don't promise event-sync.** Tight beat/structural sync on agents is gated by BUG-065 and reads against the substrate's "loose accompaniment" character. Structural-triggered bloom was tried and **removed** from Filigree (2026-06-24). If you need event-sync, fix the grid first and prove it before scoping.
7. **Flash-safety (D-157 / Nacre):** keep global luminance steady; bound any per-event spatial footprint. Filigree passed the flash test at 0.00 flashes/s — hold that bar.

---

*Companion to the SDF.1 hand-off. Both are paste-ready specs for a Mac-side Claude Code session; neither requires the Cowork sandbox.*
