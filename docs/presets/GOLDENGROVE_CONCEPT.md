# Goldengrove — Concept Scope (V.10 hero preset)

**Status:** pre-authoring concept scope, awaiting Matt sign-off. **No shader code until this is approved.**

## Decision recorded

- **Preserve the existing Fractal Tree** untouched — it's a fun, distinctive mesh preset and stays in the catalog as an uncertified sibling. (Siblings, not subclasses — D-097 grain.)
- **Goldengrove** is a **new** high-fidelity preset that takes over the V.10 cert-ladder rung and the `§10.4` uplift target. It inherits the `docs/VISUAL_REFERENCES/fractal_tree/` reference set (curated for exactly this painterly target).
- **Load-bearing musical role: the tree grows with the song.** The L-system canopy builds with musical structure — generations unfold, foliage fills in, full canopy at the peak — and sheds at section boundaries / track end. Growth state *is* song structure (the Arachne web-build analog). Wind and season are *secondary* texture on top, not the headline.

## Visual target (grounded in the reference set)

Gold-standard 14-image reference set with per-image mandatory/decorative/anti-traits, each cross-referenced to an existing `SHADER_CRAFT.md` recipe. Hero reads:

- **Macro form** (`01`): dense **asymmetric** multi-generation crown — fine perimeter branches blur into a cloud-mass. ≥4 generations, no mirror symmetry (FA #44 — per-branch hash jitter).
- **Hero moment — back-lit canopy glow** (`06`): warm yellow-green transmission when the key light is behind the foliage. **Critical scoping note:** at tree-render distance the per-leaf venation in the macro reference is sub-pixel — the readable effect is the **aggregate foliage mass glowing warm against the light**, not literally-resolved veins. That makes the hero moment *more* tractable than the macro photo implies.
- **Golden-hour lighting** (`09`): warm low-angle key, rim/SSS glow on back-lit edges, airborne dust motes, soft warm atmosphere, cool shadow fill.
- Bark POM + lichen (`04`/`07`/`08`), seasonal palette (`11`/`12`, default autumn, valence-synced), ground fog (`10`), painterly soft-edge aesthetic (`13`).

## Feasibility — the Arachne FA #49 trap check

Arachne stalled because its references demanded compositing layers the ray-march renderer **structurally lacked** (background pass, refraction, DoF). Goldengrove is the opposite case — **every demanded layer maps to an existing engine capability:**

| Layer | Need | Status |
|---|---|---|
| Growth mechanic | runtime-varying L-system geometry + CPU state machine | ✅ **already prototyped** — existing FT varies `branch_count 3–63` at runtime; `setMeshPresetTick` CPU-state pattern proven by `ArachneState` |
| Bark material + POM | §4.7 + §8.3 | ✅ recipes exist |
| Translucent SSS leaves | §4.8 | ✅ recipe exists |
| Golden-hour lighting | §5.6 | ✅ recipe exists |
| Seasonal palette | IQ-cosine, valence-synced | ✅ standard palette path |
| Wind / atmosphere | curl_noise + ground fog + dust motes | ✅ standard utilities |

**No net-new engine infrastructure is required.** The novel work is *design + authoring on proven rails*, not building missing render passes.

## The one genuinely novel piece — the growth state machine

The existing FT growth is **instantaneous** (`branch_count ← bass_att`, frame-to-frame). Goldengrove's musical role needs **structural** growth: a CPU-side `GoldengroveState` (an `ArachneBuildState` analog wired via `setMeshPresetTick`) that advances build stages over the song's arc — canopy density tracking the energy/structure arc, peaking at the chorus/drop, shedding at section boundaries. Inputs already exist (StructuralAnalyzer section boundaries, energy envelope). Design risk: pacing must be driven by structure/energy, **not** `sin(time)` (FA #33), so growth lands with the music rather than scrolling mechanically.

## 3-part bar verdict

1. **Iconic subject deliverable at fidelity** — CONDITIONAL PASS. References are gold-standard, recipes exist, the hero SSS moment reduces to aggregate canopy glow (tractable). Residual risk is *execution polish* (the painterly soft-edge target, hero golden-hour) — the category that's been botched before — not structural impossibility.
2. **Clear musical role** — PASS. "Grows with the song," load-bearing, points-at-a-moment, feasible mechanism.
3. **Infrastructure-feasible** — PASS. Strongest of the three; no missing engine surfaces.

**This is the best-positioned hero-preset cert attempt in the catalog** — precisely because the references map to existing recipes and the growth mechanism is on proven rails, where Arachne/Aurora Veil are not.

## Honest risk register (not soft-pedaled)

- **Execution fidelity** — painterly hero look is the category Matt has watched get botched. Gold-standard references + recipes are real mitigants; they don't eliminate the risk. This will be a multi-round M7 grind (Lumen Mosaic took 8, FFO 69).
- **Perf** — §10.4 budgets ~6.5 ms Tier 2 (POM bark + 200–500 leaf billboards) ≈ 40 % of the 16 ms Tier 2 frame. Tier-1/Tier-2 mitigations (capped leaf count, POM off on Tier 1, half-res where possible) must be designed in from session 1, per the D-072 ladder's Tier-1-default-mitigation rule — not bolted on at the end.
- **Growth state machine** — new design; pacing must read as musical, not mechanical (FA #33).

## Proposed session breakdown (musical role first, per Authoring Discipline)

1. **`GoldengroveState` growth state machine** — structural-arc-driven build/shed, wired via `setMeshPresetTick`. The load-bearing musical layer goes first, validated on real music before any decoration.
2. **Geometry** — deeper asymmetric L-system + real branch geometry (ribbons/cylinders, not flat quads) + bark POM (§4.7/§8.3).
3. **Foliage** — leaf-cluster billboards + §4.8 SSS (the hero canopy-glow moment).
4. **Lighting + atmosphere + season + wind** — §5.6 golden-hour + ground fog + dust motes + valence-synced seasonal palette + curl_noise wind (← `other_energy_att`).
5. **Perf pass + M7 polish rounds** (count unknown until the first M7).

Each session ends with a `RENDER_VISUAL` contact sheet; cert is gated on Matt's M7 against the reference set + a `PresetSessionReplay` evidence pack on a real capture (per SR.1 + the §Diagnostic-infrastructure rule).

## Open question for sign-off

The verdict is **go, with eyes open** — Goldengrove clears the bar that Arachne and Aurora Veil don't, but it's still a high-fidelity painterly grind. Confirm: (a) the concept + musical role as scoped, (b) start with session 1 (the growth state machine on the existing flat-quad geometry, so the musical behaviour is proven before the expensive material work), or a different sequencing.
