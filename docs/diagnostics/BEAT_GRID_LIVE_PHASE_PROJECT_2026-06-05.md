# Beat-grid live-phase — project scoping note

**Opened:** 2026-06-05 (Matt, after Nimbus M7 round 1, session `2026-06-05T18-26-37Z`). **Decision:** D-143. **Status:** scoping only — needs its own design session + a premise decision from Matt before any increment is written.

> This is **not** an increment and **not** a green light to start coding. Per Failed Approach #69, any work on beat-phase requires a *new premise*, and that premise must be chosen with Matt first. This note records the diagnosis and the candidate premises so the future design session starts from evidence, not a blank page.

## Why this is a project, not a Nimbus fix

Nimbus M7 r1: "feels like it is behind the beat, certainly not locked with downbeats" (Money: "follows the bassline but is in the wrong downbeat"; Royals: "took seconds before reactivity kicked in"; Superstition: "nice perception of sync in the verse" — so it *can* lock when the phase happens to line up). The session data shows this is upstream of Nimbus:

- **Grids lock.** `lock_state` = 2 (locked) on ~84 % of frames across the session.
- **Tempo is right.** The cached-grid BPM agrees with the independent drums-stem BPM to < 1 % on most tracks (Billie Jean 0.7 %, Royals 0.0 %, B.O.B. 0.2 %, Money 0.6 %). The problem is **not** tempo.
- **Phase is imperfect on live audio.** `drift_ms` (grid vs live sub-bass onsets) sits ~10–35 ms, signs mixed per track — and the sub-bass onset isn't the true beat reference anyway (FA #68: it fires on bass *events*, not beats), so even a small drift number doesn't mean the grid is on the audible beat.
- **Meter is assumed simple.** The installed grids came through as `4/X`; Money (famously 7/4) logged `beatsPerBar = 2`. So "downbeat" is structurally unreliable on odd-meter material.

Nimbus consumes `beatPhase01` from this grid faithfully. **No Nimbus shader tuning can make a wrong-phase grid right.** NB.8's anticipatory kick (`smoothstep(0.82,1,beatPhase01)`) actually commits *harder* to the grid's predicted phase, so on a slightly-off grid it leads the eye to the wrong spot — the pre-NB.8 onset-driven kick was phase-correct but lagged ~80–120 ms ("behind"). Both fail differently; that tension is the structural signature of FA #69.

## What's already been tried (do not repeat)

The Cold-Start Phase Contract (CLAUDE.md) + Failed Approach #69: **six iterations** (CS.1 → BSAudit.3.impl, 2026-05-22 → 25) tried to derive correct beat *phase* from short live-tap audio. All failed; the premise ("some automated signal in the first ~3 s reliably gives audible beat phase") is **retired**. Beat This!-on-tap is cross-capture-unstable on 5–6 of 10 catalog tracks. Do not file iteration #7 of the same premise.

## Candidate NEW premises (the only paths forward per FA #69)

Each needs Matt's product call — they have very different UX and scope:

1. **Human-tap reference** (BSAudit-FU-5 Path B). The user taps the beat for a few bars on a new track; we phase-lock the grid to the taps. Highest-quality phase, but adds a per-track interaction. *Question for Matt: acceptable UX, or too much friction for a "press play and watch" product?*
2. **Full-track local-file analysis.** For local files (not 30 s previews), run Beat This! over the *whole* track offline → a far more stable grid than the preview-derived one. Only helps the local-file path, not streaming. *Lower friction, narrower coverage.*
3. **Per-track manual calibration UX.** A nudge control (±) that shifts the grid phase, persisted per track identity. One-time per track; cheap to build. *Puts the human in the loop without a tap game.*

A combination is plausible (e.g. local-file full-track analysis as the default, manual nudge as the override).

## Relationship to Nimbus cert

Nimbus's **beat axis** (kick timing / downbeat feel) is gated on this project — Matt's M7 r1 verdict explicitly waits on it. The **mood axis** is not (NB.10 / D-142 shipped independently). Whether Nimbus can certify on the achievable bar (mood fixed + best-effort beat within the current grid) vs. waiting for this project to land is Matt's call at a future M7.

## Artifacts

- Session: `~/Documents/phosphene_sessions/2026-06-05T18-26-37Z/` (features.csv has the `lock_state` / `grid_bpm` / `drift_ms` / `beatPhase01` / `barPhase01_permille` / `is_downbeat` columns this note draws on).
- Prior record: CLAUDE.md §Cold-Start Phase Contract; Failed Approach #69; `docs/CAPABILITY_REGISTRY/BEAT_SYNC.md`.
