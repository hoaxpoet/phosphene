# Kickoff — CLEAN.6.2 / BUG-042: re-express the structural stream at section scale

**Run this in a FRESH session** (Matt's preference — a clean read avoids stale-context drift). Build live tests from the **PRIMARY** checkout, not a worktree — the gitignored tempo fixtures and real-session captures this increment needs are absent in worktrees.

## Why this exists

Phase 6 (capability) is the next CLEAN batch; everything before it (Phases 0/1/2/3/5/7) is done. CLEAN.6.2 is the recommended first increment: it retires a tracked **P2** and the bulk of the work is CPU/headless. The audit row: *"BUG-042 re-express structural stream at ~2 Hz section scale; recalibrate vs real session streams; re-express BUG-035/040 tests."* (`docs/diagnostics/CODE_AUDIT_2026-06-13.md` §Phase 6.)

## Read first (authoritative surfaces — don't trust this brief over them)

- **`docs/QUALITY/KNOWN_ISSUES.md` §BUG-042** — the authoritative evidence (Expected/Actual/Repro/Status). Status is **Open**. Headline: the analyzer's GEOMETRY is note-scale (**6.4 s window, 85 ms checkerboard**); at the live ~94 Hz analysis rate it emits a "section" every **~1.5 s**, and post-BUG-040 confidence now *endorses* that junk. Expected: musical sections of **15–60 s** with confidence reflecting real form.
- **`CLAUDE.md` §Defect Handling Protocol** + **`docs/QUALITY/DEFECT_TAXONOMY.md`** — this is a `dsp.structure` P2. Evidence-before-implementation; the domain-specific artifact requirements (before/after structural-stream diagnostics on a real capture) are the Validation step.
- **`CLAUDE.md` Failed Approach #27** — **no synthetic audio for diagnostics.** Recalibration MUST run the real capture path on real music. Hand-authored envelopes don't reproduce real MIR structure. This is the load-bearing constraint for this increment.

## What's already true (so you don't re-solve it)

- **BUG-035** (NoveltyDetector boundary re-detection after similarity-ring wrap) and **BUG-040** (live-edge boundary every ~4 intervals) are **RESOLVED**. Their tests exist and the audit asks you to **re-express** them against the new section-scale geometry, not re-fix them.
- **BUG-046** already guards the **Skein** consumer (10 wall-second boundary spacing in `SkeinState`). So the *live visual* impact is contained. The still-riding consumer is the **orchestrator's `StructuralPrediction`** path (preset switching) — that's the one this increment actually fixes.

## The task

Re-express the structural-analysis stream so it emits **section-scale** boundaries (target ~15–60 s musical sections, "~2 Hz" in the audit refers to the *analysis cadence* to re-express against, not the section rate), with confidence that reflects real musical form — then **recalibrate against real session streams** and re-express the BUG-035/040 regression tests.

**Files to start from** (confirmed 2026-06-18):
- `PhospheneEngine/Sources/PhospheneEngine/DSP/StructuralAnalyzer.swift` — the window/checkerboard geometry (the 6.4 s / 85 ms defaults live here or in its inputs).
- `PhospheneEngine/Sources/PhospheneEngine/DSP/NoveltyDetector.swift`, `DSP/SelfSimilarityMatrix.swift` — the novelty/SSM machinery feeding boundaries.
- Consumer side: `Renderer/RenderPipeline.swift` + `Renderer/RenderPipeline+PresetSwitching.swift` (orchestrator `StructuralPrediction` consumer). Skein's consumer is already guarded — leave it.

**Likely shape** (architectural → probably multi-increment per the P0/P1-style process even though it's P2): **instrument → diagnose** (characterise the current geometry's output on a real capture, propose the section-scale re-expression; commit & stop) **→ fix** (re-express geometry + confidence; + regression tests) **→ validate** (before/after structural stream on the same real capture). If the root cause + fix turn out small and obvious from the existing artifacts, collapse to a single fix increment — but get Matt's nod to collapse.

## How to get a real capture (FA #27 — no synthetic)

You need a real session stream to recalibrate against. Two routes:
1. **`FixtureSessionCaptureGenerator`** (engine test target, `Diagnostics/`, from BUG-049): env-gated, replays vendored tempo fixtures (`love_rehab` / `so_what` / `there_there`) through the PRODUCTION pipeline and writes real `stems.csv`/structural captures. Needs the tempo fixtures present — run from the PRIMARY checkout, or `Scripts/bootstrap_fixtures.sh` first. Usage: `PHOSPHENE_GEN_SESSION_DIR="$HOME/Documents/phosphene_sessions" swift test --package-path PhospheneEngine --filter FixtureSessionCaptureGenerator`.
2. **A real listening session** from Matt (the `~/Documents/phosphene_sessions/<ts>/` capture with the structural columns).

## Scope guard & validation reality

- **This worktree/headless can't fully close it.** The re-expression + regression tests are CPU/headless, but the *recalibration validation* needs a real capture (route 1 or 2). Expect to land **"code-complete, pending Matt's validation"** if no real capture is available in-session.
- The orchestrator `StructuralPrediction` consumer's behaviour is a **musical-feel** judgement (does preset switching land on real sections?) — that needs Matt, not just a green test.
- Don't touch the Skein consumer (BUG-046 guards it). Don't re-fix BUG-035/040 (re-express their tests only).

## Closeout (per CLAUDE.md Increment Completion Protocol)

- `docs/QUALITY/KNOWN_ISSUES.md` §BUG-042 — fill `Resolved` + commit hash when it lands (manual-feel sign-off is Matt's).
- `docs/RELEASE_NOTES_DEV.md` — new `[dev-YYYY-MM-DD-HHMMSS]` entry (prepend-only).
- `docs/ENGINEERING_PLAN.md` — mark **CLEAN.6.2** progress (and the audit §Phase 6 row).
- `docs/ENGINE/RENDER_CAPABILITY_REGISTRY.md` — only if a structural-analysis *capability* status changes.
- `Scripts/closeout_evidence.sh` evidence block + the before/after structural-stream artifact.

## Output

Start with the **instrument/diagnose** step: characterise the current note-scale geometry on a real capture, state the section-scale re-expression you'd make, and stop for Matt's review before the fix — unless you and Matt agree to collapse to a single fix increment.
