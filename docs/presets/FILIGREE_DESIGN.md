# Filigree — physarum agent-network preset

**Status:** ✅ CERTIFIED 2026-06-28 (PHYS.5) as a **loose energy-accompaniment**.
Final shipped coupling (after the sync arc PHYS.3→.5): energy drives cell merge/divide
— LOUD → fine/busy/bright web, QUIET → few calm cells (Matt's polarity) — via a
continuous map + a re-seed that respawns agents to regrow fine; per-beat `hit` pulse;
flash-safe (0.00 flashes/s, real `renderFiligree` harness).

**The sync finding (load-bearing for the next preset).** Three live M7s converged
on the same verdict: physarum reads as a *good accompaniment* but **not tightly synced**
to the music. Root cause (diagnosed off the session CSVs, not guessed): the trail
substrate couples smoothly to the continuous energy envelope, and event-locked
attempts don't land — the per-beat accent is subtle on the fine web, and the
re-seed "burst" is both rare on sustained-loud tracks (the surge detector's baseline
catches up) and redundant with the continuous loud=fine state. Tight, event-synced
cell *division* (mitosis) is **reaction-diffusion's native behaviour**, not physarum's
— so it is a SEPARATE planned preset, not more tuning here (Matt's call; 5 divide
attempts + 3 sync attempts confirm the substrate limit).

**Origin:** Research → organic agent networks → Drift Motes diagnosis (died of
musical role, FA #58, not technique) → musical role locked with Matt → throwaway
sketch (go/no-go gate, all headless criteria green) → **web-dominant concept +
Kintsugi palette locked from rendered evidence** → this increment.

---

## 0. Verdict

A living slime-mold network (Physarum / neural web / river-delta — instantly
readable) whose **form is the song's energy**. Proven feasible at ~0.66 ms/frame
(262k agents, 1080p; 1M agents at ~0.55 ms — vast headroom), flash-safe, on the
existing per-frame-compute + particle-mode-draw paths with **no new render
primitive**. Clears the three-part bar. Recommend building.

---

## 1. Musical role (the gate)

> *As the sustained energy envelope rises, the fine gold searching-web brightens
> and quickens; at a structural peak it blooms into consolidated load-bearing
> veins — the drop payoff — then relaxes back to the searching web.*

This is the **inverse** of the original sketch spec (which had veins as home, web
as the thin-out). The inversion was chosen from rendered evidence: the dense
*searching web* is the most compelling state, so the song should live in it and
treat consolidation as the rare, earned payoff. Mute the audio and the form still
breathes with the energy — the web carries the music. This is exactly what Drift
Motes lacked (its motes drifted identically regardless of audio).

### Temporal contract

| Musical feature | Visual behaviour | Timescale |
|---|---|---|
| Sustained continuous-energy envelope (primary) | web brightens + quickens; deposit/flow rise | slow / continuous, zero-lag |
| Structural peak (`bloom` = smoothstep of the energy envelope) | web consolidates into bright gold veins | rare / per-section |
| Post-peak | persistence releases; veins re-fragment back to the searching web | seconds (hysteresis) |
| Structural drop / collapse (external trigger) | headings perturb → veins reroute and regrow; luminance held steady | rare / structural |

---

## 2. Three-part bar (cleared)

1. **Iconic subject at fidelity** — the physarum vein/web network; working fidelity
   reference (Bleuje, §8). Rendered at fidelity in the sketch (see references).
2. **Clear musical role** — §1, one sentence, specific feature → specific behaviour.
3. **Infrastructure-feasible** — proven: runs on existing `ParticleGeometry`
   per-frame compute + ping-pong + particle-mode draw. No new pass type.

---

## 3. Creative architecture

The substrate is a population of agents depositing onto a trail map that diffuses
and decays (the Jones / Bleuje / Sage-Jenson physarum model). The network's
*topology* is the home↔payoff axis:

- **Web (home).** Short sensor/move range + low deposit + fast decay → a fine,
  dense, continuously-reorganising searching tangle. The song's resting state.
- **Veins (payoff).** A `bloom` signal (peaks only) raises sensor/move range and
  trail persistence → the network consolidates into fewer, thicker, brighter
  load-bearing channels.

Continuous energy drives **brightness + flow** of the web at all times; `bloom`
(peaks only) drives **consolidation**. Keeping these on separate signals is what
makes the web the home and the veins the payoff (rather than energy simply
coarsening the web away).

---

## 4. Audio routing (one primitive per visual layer — D-026, FA #67)

| Visual layer | Primitive | Timescale | Notes |
|---|---|---|---|
| Web brightness/flow + consolidation envelope | smoothed continuous energy (`energyEnv`, EMA of the Murmuration-style stem/full-mix blend) | slow | primary driver; from frame 1 (cold-start safe) |
| Bloom → veins | `smoothstep(0.55, 0.95, energyEnv)` | per-peak | derived from the same envelope; a *threshold*, not a second timescale |
| Collapse-regrow | external structural trigger (`requestCollapse()`) | structural | NOT beat-phase (cold-start contract); reroute, luminance-neutral |

No two layers share a primitive at the same timescale. Cold-start: continuous
energy + deviation available frame 1; collapse keys off structural detection, not
cold-start beat phase.

---

## 5. Rendering architecture

- **`PhysarumGeometry`** — a `ParticleGeometry` sibling (D-097). Owns: an agent
  `MTLBuffer` (`PhysAgent`, 16 B), an atomic deposit accumulator (`atomic_uint` ×
  W·H), two ping-pong `r16Float` trail textures, and the `physarum_*` pipelines.
- **Per-frame compute** (one encoder, `memoryBarrier(.buffers)` between dependent
  dispatches — Metal does not serialise consecutive dispatches; cf.
  `FerrofluidParticles.swift`):
  1. `physarum_reset` — zero the accumulator.
  2. `physarum_agents` — sense trail (toroidal `address::repeat` sampler), steer
     (Jones), step, wrap, atomic-deposit.
  3. `physarum_diffuse` — 3×3 box blur × decay + this-frame deposit (`sqrt(count)·f`,
     Bleuje) → ping-pong target. (Deposit + colorize folded in — both per-cell.)
- **Draw** — `physarum_trail_fragment` samples the latest trail; colorize in the
  fragment (no separate colorized texture). Reuses `fullscreen_vertex` from
  `Common.metal`.
- Sim grid 1280×720; agents 262 144 (headroom to 1M+). Trail `r16Float`
  (filterable, so agents bilinearly sample; r32Float loses filtering — §10 risk).

---

## 6. Palette — Kintsugi (locked)

Gold veins on **pure black** (`ground (0,0,0)` → web `(.30,.18,.05)` dim bronze →
vein `(1.0,.80,.34)` bright gold). Chosen by Matt from a rendered three-candidate
comparison across web/vein/bloom states. The pure-black ground gives the cleanest
figure-ground; gold reads as "load-bearing veins" most literally; strongest in a
dark viewing room.

Rejected (rendered, documented): **Physarum polycephalum** (honest organism, warm
brown substrate ground — close 2nd) and **Bioluminescence** (cool electric teal,
closest to the first sketch). Palette is parameterised (`PhysConfig.paletteId`) so
these remain one constant away if revisited.

---

## 7. Performance (measured, sketch harness)

| Config | GPU ms/frame @ 1080p |
|---|---|
| 262k agents, 1280×720 sim | **0.66** (budget 16.67) |
| 1M agents | **0.55–1.29** |

~25× under budget at the baseline — room for a far richer sim (more agents, larger
trail, multi-species) at promotion if wanted.

---

## 8. Design grounding (descending preference — surfaced per checklist)

- **Level 1 (working code reference):** Bleuje's 4-shader Physarum/36-Points
  pipeline — https://bleuje.com/physarum-explanation/ · repo
  https://github.com/Bleuje/physarum-36p . Sage Jenson "36 Points"
  (parameter-as-function-of-trail) — https://www.sagejenson.com/36points/ .
- **License:** Bleuje / Sage are CC-BY-NC-SA 3.0 — the *algorithm* is
  re-implemented in our own MSL (techniques aren't copyrightable); no GLSL is
  copied into MIT Phosphene.
- The web-dominant *musical* coupling and the Kintsugi grade are Phosphene-original
  (no published demo grounds them) — empirically grounded by this session's
  rendered evidence rather than a prior art reference.

---

## 9. Phased plan

| ID | Done-when |
|---|---|
| **PHYS.1** | Design doc + bootstrap `VISUAL_REFERENCES/filigree/` set. (this) |
| **PHYS.2** | `PhysarumGeometry` graduated to a registered preset: `PresetDescriptor` + JSON sidecar + `ParticleGeometryRegistry` + `VisualizerEngine` factory/resolve + multi-frame production-path test. |
| **PHYS.3** | Wired into the live app render loop; live audio-lock listen on real music (the gating real-feel test). |
| **PHYS.4** | Tuning vs. references: cap the bloom over-fill, return speed, web long-hold stability. |
| **PHYS.5** | Certification — M7, rubric, flash-safety cert, sidecar `certified: true`. |

---

## 10. Known tuning items / risks (carried into PHYS.4)

- **Bloom over-fill at the extreme peak.** At full energy (~0.92) the deposit
  floods cell interiors → figure-ground inverts to bright-field-with-dark-holes.
  The payoff is gorgeous through ~0.55–0.7 (bold bright veins, dark interiors); a
  cap on how far `bloom` pushes deposit/persistence keeps it there. **Palette-
  independent.**
- **Return-to-web is slow.** Post-bloom persistence lingers → relaxes to coarse
  veins before re-fragmenting to the fine web. Reads as musical aftermath; tunable.
- **Web long-hold drift.** At a sustained flat energy the web slowly coarsens
  (deposit gradually outpacing decay). Balance deposit/decay for a stable fine-web
  steady state.
- **Flash-safety holds** (collapse dips to ~0.85× baseline; floor 0.6×) but the
  collapse is currently *subtle* — punch-up headroom exists within the safe band.
- **Live audio-lock unproven** — headless tests prove pipeline, not feel (FA #27).
  PHYS.3 is the gate.

---

## 11. Open decisions for Matt

- Bloom character at PHYS.4: clean vein-lattice (cap deposit) vs. the molten fill.
- Collapse drama: keep subtle, or punch up within the flash-safe band.
- The collapse trigger source for PHYS.3 (structural-boundary signal wiring).

---

## Module-Map history

`PhysarumGeometry.swift`, `Physarum.metal`, `PhysarumSketchRenderTests.swift` —
created in the throwaway sketch; graduating to the Filigree preset across PHYS.1–5.
Per-file behaviour: see `docs/ARCHITECTURE.md §Module Map` once registered (PHYS.2).
