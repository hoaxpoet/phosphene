---
name: beat-sync-session
description: Invoke BEFORE any work on a dsp.beat increment — BeatDetector, BeatGridResolver or a decoder alternative, LiveBeatDriftTracker, RollingBeatTracker, BeatPulseClock, BeatGrid, or any BUG tagged dsp.beat. The mandatory opener for the beat-sync program (D-202). Covers the beat-sync constraint set, the banned approach families, and the benchmark obligation.
---

# Beat-Sync Session Opener

The mandatory opener for any increment in the beat-sync program (D-202; spec `docs/BEAT_SYNC_PROGRAM_PLAN.md`). Load this before touching any beat-path code so 24–34 sessions do not re-derive or violate the constraints below. Measurement lives in the `beatbench` skill; recorded-session forensics in `session-forensics`; algorithm ports in `reference-port`.

## 1. The constraint set (do not re-litigate — cite, don't restate)

Each is canonical in the linked doc; this is the citation index, not a copy.

- **D-004 — continuous energy is the primary visual driver; beats are accents.** This program improves an accent-layer signal; it never promotes beats to primary motion. Canonical: `docs/DECISIONS_HISTORY.md` D-004 + CLAUDE.md §Audio Data Hierarchy (Layer 4).
- **Cold-Start Phase Contract + FA #69 — no automated *short-window* (≤ ~15 s) cold-start beat-phase derivation.** Stated as written: the ban is on deriving the audible beat *phase* of a novel track from the first few seconds of tap audio (falsified across six iterations, retired Matt's Choice A 2026-05-25). It does **NOT** ban steady-state, full-length-window tracking — everything in this program is steady-state. Cold start stays BeatPulseClock / first-note anchor (D-153). Any new cold-start-phase idea needs a fundamentally different premise (human-tap reference, full-track local analysis, or manual calibration UX) surfaced to Matt first. Canonical: CLAUDE.md §Cold-Start Phase Contract + `docs/CAPABILITY_REGISTRY/BEAT_SYNC.md` §Cold-Start Phase Contract; history in `docs/HISTORICAL_DEAD_ENDS.md` §Cold-start beat-phase derivation.
- **FA #68 — sub-bass onsets are events, not beats.** The sub-bass detector fires on bassline notes / 808s, off-beat on syncopated tracks; it is never a beat-phase *reference*. It remains usable as drift *evidence* against an already-trusted grid. Canonical: `docs/CAPABILITY_REGISTRY/BEAT_SYNC.md` (Component 6 / Hypothesis 2).
- **D-075 — never fuse onset bands for IOI timestamps.** Tempo comes from sub_bass-only onsets + trimmed-mean IOI; cross-band fusion biases the IOI histogram. A second detector instance on a different stem (e.g. drums-stem onsets, TRK.2) is a distinct detector, not a fused band. Canonical: DECISIONS D-075.
- **Halving-only octave correction (BUG-009 / D-079).** Octave correction halves at BPM > 175 only; sub-80 doubling was deleted (D-079). Do not reintroduce doubling. Canonical: DECISIONS D-079 + `docs/ARCHITECTURE.md` §Audio Analysis (BeatDetector+Tempo).

Beat-locked motion **is** a valid technique on the cached `BeatGrid` under the Layer-4 constraints (beat-irregular tracks excluded D-154; bounded per-beat footprint + steady luminance D-157; D-153 → D-158). The constraint set bounds *how*, it does not forbid beat sync.

## 2. The dead-end map — if your approach resembles a row here, stop and say so before writing code

Six iterations exhausted the short-window cold-start-phase premise; the FBS Stage-1 live verdict retired the whole-track pulse-as-driver premise. Rows 1–6 are cataloged in full at `docs/HISTORICAL_DEAD_ENDS.md` §Cold-start beat-phase derivation dead ends — read the row before proposing anything adjacent.

| Attempt | Mechanism → why it died |
|---|---|
| CS.1 | Trust cached grid phase from frame 1 → preview-time clock ≠ track-time clock |
| CS.1.y.2 | Phase-lock from first sub-bass onsets → onsets are events, not beats (FA #68) |
| CS.1.y re-diagnosis | Beat This! on 3–5 s tap → short windows degrade tempo/period estimation |
| CS.1.y.2-redo r1 | Beat This!@15 s snap → engine `horizon` bug; refixed, not a signal win |
| CS.1.y.2-redo r2 | Beat This!@15 s snap → per-capture stable, cross-capture unstable on 5–6/10 |
| BSAudit.3.impl | BPM-prior + broadband-peak phase + confidence gate → fires on pre-beat content; confidence climbs on any period-matching phase |
| FBS Stage-1 (own home: RELEASE_NOTES_DEV_2026-06 `[dev-2026-06-09-fbs-s1]`, D-153/D-154) | Whole-track per-beat pulse → reads robotic; gapless segues make mid-playlist anchors musically meaningless; the pulse is a cold-start bridge, not the driver |

Structural lesson: no short-window automated signal converges on the audible phase. The program's answer is steady-state full-window tracking (TRK), full-track offline decode (FT), and research-gated rolling grids (RLG) — not another short-window signal.

## 3. The benchmark obligation

- Any **behavioral** change to a beat signal ships a **before/after BeatBench table across all five suites** in the closeout, or an explicit "no behavioral change to beat sync" statement. This is a `closeout` done-when for dsp.beat increments.
- **Category-win claim rules live in the `beatbench` skill** — no category is claimed won without a number, regressions on any suite are reported even when the target suite improves, and windows are never cherry-picked. Load `beatbench` before writing the closeout table.
- Diagnostic logging lands first; new runtime behavior ships behind an env flag with a one-increment A/B path (program house rule, plan §4).

## 4. The two-strikes stop rule

**Two failed validation attempts on the same premise within any increment → stop, write findings, surface a DECISION-NEEDED. No third attempt without Matt's sign-off on a changed premise** (plan §7). The verifier-passing → M7-failing pattern (CS.1 → BSAudit.3, six iterations) is the documented cost of iterating a broken premise; RLG.0's window study is explicitly scoped to two iterations max. For BUG-* work, evidence-before-implementation and the multi-increment process defer to the `defect-handling` skill (which uses BeatBench as the evidence substrate).

## 5. Pointer map

- **Audio analysis internals** (AGC, band definitions, onset thresholds, tempo, BeatDetector/BeatGridResolver behaviour): `docs/ARCHITECTURE.md` §Audio Analysis Tuning + §Module Map.
- **Beat-sync capability + full cold-start history**: `docs/CAPABILITY_REGISTRY/BEAT_SYNC.md`.
- **Open dsp.beat defects** (BUG-065 mid-track drift, BUG-028 phase-imperfect, BUG-001 Money odd-meter ceiling, BUG-013 no time_signature): `docs/QUALITY/KNOWN_ISSUES.md` (filter domain `dsp.beat`).
- **Program spec** (phases, suites, targets, per-increment detail): `docs/BEAT_SYNC_PROGRAM_PLAN.md`.
