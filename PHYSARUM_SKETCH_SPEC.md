# Physarum Agent-Network — Throwaway Sketch Spec

**Status:** Pre-implementation spec for a *throwaway harness sketch* (not a preset). No JSON sidecar, no certification, no closeout protocol. Single purpose: prove framerate, look, and audio-lock on Apple Silicon, then gate the go/no-go to a real preset increment. Uncommitted, repo-root, relocate as you like.

**Origin:** Research → direction chosen (organic agent networks) → Drift Motes diagnosis (the prior agent-deposit preset died of *musical role*, FA #58, not technique) → musical role locked with Matt's sign-off → this spec.

---

## 1. Locked musical role (clears the three-part bar)

> **The network's form is the song's energy: it consolidates into bright load-bearing veins as energy sustains, and dissolves into a faint searching web as energy thins — and structural drops collapse and regrow it.**

- **Iconic subject, deliverable at fidelity:** the Physarum vein network — instantly recognizable (slime mold / neural web / river delta), with a working reference for fidelity (Bleuje).
- **Clear musical role:** continuous energy → consolidation (primary); structural drop → collapse-regrow (accent). Mute the audio and the *form* changes with the energy — the form carries the music. This is the specific thing Drift Motes lacked (its motes drifted identically regardless of audio).
- **Infrastructure-feasible:** runs on Phosphene's existing per-frame compute + ping-pong feedback paths (see §4). No new render-graph primitive expected; flagged if that changes (§9).

Future variant (out of scope here): **stems-as-colonies** — per-stem colored colonies competing for the trail map.

---

## 2. Reference & grounding (FA #73 — port, don't derive)

Port Bleuje's documented 4-shader Physarum/36-Points pipeline; do **not** re-derive the agent logic from first principles (that is the Drift-Motes/Murmuration failure mode).

- Bleuje write-up (4-shader structure, formulas, perf): https://bleuje.com/physarum-explanation/ · repo https://github.com/Bleuje/physarum-36p
- Sage Jenson "36 Points" (parameter-as-function-of-trail): https://www.sagejenson.com/36points/
- **License:** Bleuje/Sage are CC-BY-NC-SA 3.0 — re-implement the *algorithm* in our own Metal (techniques aren't copyrightable); do not paste their GLSL into MIT Phosphene.

---

## 3. The agent loop (what the kernels implement)

Per Bleuje, four compute kernels per frame:

1. **reset_counters** — zero the per-cell deposit accumulator.
2. **agents_update** — per agent: sense trail at three points (ahead, ahead±sensorAngle, at sensorDistance); rotate toward the brightest by rotationAngle (random tie-break); step forward moveDistance; wrap (toroidal); `atomic_fetch_add` 1 into the accumulator at the new cell.
3. **deposit_colorize** — per cell: `trail = clamp(sqrt(count) * depositF)`; write the colorized trail texture (Bleuje's `sqrt(count)·f` deposit reads better than linear).
4. **diffuse_decay** — per cell: 3×3 box blur of trail × decayFactor → ping-pong target.

The **36-Points** upgrade (our variety/knob bank): make the four params functions of the locally-sensed trail value `x`, e.g. `sensorDistance = p1 + p2·x^p3` (same shape for angle/rotation/move). Start the sketch with the base loop; expose the 36-Points exponents as the later audio-to-variety surface.

---

## 4. Metal architecture (mapped to existing Phosphene paths)

From the capability audit, all required paths already exist — this is additive, no prerequisite plumbing:

- **Per-frame compute** is established (`TextureManager`, `IBLManager`, and especially `Murmuration3DGeometry`'s per-frame `murmuration3d_update`). Model the agent stage on the Murmuration per-frame compute contract.
- **Ping-pong textures** are established (`RenderPipeline+FeedbackDraw.swift`, two-texture swap + decay). Reuse the pattern for the trail map.
- **Direct fullscreen draw** of a texture is established (Membrane/feedback consumers) — use it to render the trail texture for the sketch.

Concrete pieces:

- **Agents:** `MTLBuffer` of `struct Agent { float2 pos; float heading; float age; }` (16B aligned). Start N = 2^18 (262k); scale toward 2^20 (1M) per perf headroom.
- **Deposit accumulator:** `MTLBuffer<atomic_uint>` sized `W*H` (Metal texture atomics are limited; atomic buffer is the portable path). `atomic_fetch_add` in agents_update; convert + zero in deposit/reset.
- **Trail map:** two `MTLTexture` `r16Float` (ping-pong) — `r32Float` if precision/stability needs it. Colorized output to an `rgba16Float` the fragment pass samples.
- **Stage wiring:** new per-frame compute stage (agents → accumulator → trail ping-pong) feeding a direct draw. Integrate via the same hook Murmuration uses; if it needs more than per-frame-compute + direct-draw, that's a scope expansion — surface to Matt before expanding (§9).

---

## 5. Audio coupling — real primitives, one-primitive-per-layer (FA #67)

Drive from Phosphene's actual deviation primitives (D-026) and structural signals, **not** raw onsets and **not** the browser-toy FFT. Continuous energy is the default primary driver (Audio Hierarchy Layer 1).

| Visual layer | Audio primitive | Timescale | Effect |
|---|---|---|---|
| Network consolidation (veins ↔ web) — **PRIMARY** | smoothed continuous energy (`bassRel` / `energyDev`) | slow / continuous | raises sensorDistance, moveDistance, depositF; raises decay toward persistence → veins. Low energy → weak deposit + fast decay → diffuse searching web. |
| Structural collapse-regrow — **ACCENT** | structural boundary / `barPhase01` downbeat after a drop / strong `energyDev` transient | rare / structural | dissolve-and-reseed: scale trail down + perturb headings, then let it regrow. |
| (future) branch character | spectral centroid / chroma → 36-Points exponents | medium | tightness/branchiness variety |

No two layers share a primitive or timescale (FA #67 satisfied). Cold-start contract: continuous energy + deviation are available from frame 1; the collapse accent keys off structural detection, not cold-start beat phase.

**Flash-safety constraint (D-157 / Nacre):** the collapse must **not** spike or crater global luminance — it is a *re-routing/dissolve*, not a blackout. Keep overall brightness steady; bound the spatial footprint. Verify flash-safe before any promotion.

---

## 6. Performance plan & targets

- **Target:** 60 fps @ 1080p on the Mac mini dev target, with headroom.
- **Trail resolution:** start 1280×720 (or 1024×576 if margin is tight); agents 262k → 1M.
- **Datapoint:** Bleuje runs 5.8M agents @ 60 fps on an RTX 2060 at 1280×736 — Apple Silicon should clear our lower counts comfortably; the sketch *confirms* it.
- **Cost centers to watch:** atomic deposit contention at high agent density on a tile GPU; the 3×3 diffuse pass. Both are cheap vs. the 16.6 ms budget at our res, but contention is the most likely surprise — mitigations: lower density, or tile/stride the accumulator.

---

## 7. Go / no-go criteria (gate to a real preset increment)

Promote only if **all** hold:

1. Holds 60 fps @ 1080p on the Mac mini with headroom (`RENDER_VISUAL=1` contact sheet + frame timing).
2. Produces a stable organic vein network — no degenerate clumping or numeric blow-ups; trail stays bounded.
3. Continuous energy → consolidation reads as *locked* on a real track (manual listen at volume — automated tests prove pipeline, not feel).
4. Collapse-regrow lands on structural events and is flash-safe (steady global luminance).

If all pass → open a real preset increment under `PRESET_SESSION_CHECKLIST.md` (build the `docs/VISUAL_REFERENCES/<preset>/` set, JSON sidecar, certification path). If any fail → report which criterion, with artifacts, and decide before iterating.

---

## 8. Explicitly out of scope (sketch)

JSON sidecar · certification / M7 · Orchestrator + transition integration · stems-as-colonies variant · 36-Points audio-to-exponent mapping · final color grade to the SHADER_CRAFT fidelity floor. These belong to the preset increment if the gate passes.

---

## 9. Open risks / unknowns

- **Atomic contention** at high density on Apple tile GPUs — may force lower density or accumulator striping.
- **Trail precision/format** (`r16Float` vs `r32Float`) and stability of the `sqrt(count)` mapping under decay.
- **Domain:** toroidal wrap is simplest; a bounded domain needs edge handling. Wrap for the sketch.
- **Render-graph fit:** if a compute-driven agent system needs more than the existing per-frame-compute + direct-draw (e.g. a new pass type), that's a scope expansion — stop and surface to Matt (per the increment protocol).
- **Promotion fidelity:** color/luminance mapping must reach the visual-quality floor when promoted (≥4 noise octaves equivalent richness, pale-tone ≤30%, flash-safety).

---

## 10. Build / verify boundary

This sketch must be built and frame-timed on **macOS + Xcode + Apple Silicon** (`xcodebuild -scheme PhospheneApp …`, `RENDER_VISUAL=1` harness). It cannot be compiled or run in the Cowork Linux sandbox — Metal needs the Apple toolchain and GPU. Implementation + framerate capture happen on the Mac (Matt, or a Claude Code session there). This document is the design hand-off.
