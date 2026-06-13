# CLEAN Phase 1 — Kickoff: P1 correctness (concurrency family + app-layer leaks + runtime resilience)

> **Paste to start the session:** *"Read `docs/prompts/CLEAN_PHASE1_KICKOFF.md` and `docs/diagnostics/CODE_AUDIT_2026-06-13.md`, then begin CLEAN.1.1."*
> This document is the standing brief for CLEAN Phase 1.

## Where things stand (as of 2026-06-13)

A 17-lane full-system audit landed at [`docs/diagnostics/CODE_AUDIT_2026-06-13.md`](../diagnostics/CODE_AUDIT_2026-06-13.md) — 134 verified findings + 16 verified coverage gaps → the phased **CLEAN** backlog (Phases 0–8), now the authoritative queue (`ENGINEERING_PLAN.md` §Recently Completed → "Phase CLEAN"; supersedes the 2026-05-06 QR→SB ordering).

**Approved June-30 scope (Matt):** CLEAN Phases **0, 1, 2, 5** + elevated gaps **G1** (audio device route-change), **G2** (sample-rate contract), **G7/G8** (TSan + E2E lifecycle tests), **G9** (photosensitivity). Phases 3–4 stretch; 6 / bulk-7 / 8 after June. **Manual M7 visual review is the binding throughput constraint, not engineering effort.**

**Phase 0 is COMPLETE** — `main` is at the verified tip (closeout ALL GREEN: engine 1457 / app 382 / swiftlint 0 of 432 / doc-gates 9/9), BUG-030 fixed + resolved, 22 worktrees decluttered. **You are starting Phase 1.**

## MANDATORY session setup (before any test run)

1. **`Scripts/fetch_tempo_fixtures.sh`** — the tempo clips (`PhospheneEngine/Tests/Fixtures/tempo/*.m4a`) are gitignored. Without them ~13 engine tests **FAIL LOUD by design** (`BeatThisFixturePresenceGate`, `SessionLifecycleChurnTests`, `PreviewAudioContentHash`, `BeatGridAccuracyDiagnostic`, `LiveDriftValidation`, `BeatThisLayerMatch`). This is expected on a fresh worktree, **not a regression** — fetch first. (Validated as CLEAN.5.2 during Phase 0.)
2. **Read:** this doc; `CODE_AUDIT_2026-06-13.md` Part A themes **T1/T2**, Part C **Phase 1 table**, Part B gaps **G1/G7/G8**; `KNOWN_ISSUES.md` **BUG-031 / BUG-032 / BUG-033**; `CLAUDE.md` §Defect Handling Protocol + §Audio Data Hierarchy + §What NOT To Do (the write-or-clear-@Published-on-every-path rule).
3. **Confirm a green baseline:** `Scripts/closeout_evidence.sh` → `EVIDENCE: ALL GREEN`. (Never trust a piped `swift test` exit code — the pipe masks it; CLEAN.5.3.)

## The work — P1 multi-increment protocol

Per the Defect Handling Protocol, P1s run as **separate increments**: instrument → diagnose → fix → validate. Commit & stop after instrumentation and after diagnosis. Evidence (expected/actual/repro/artifacts/failure-class/verification-criteria) is documented **before** any fix code.

**The spine: BUG-031 + BUG-032 are ONE root cause** — a single shared `StemSeparator` instance driven **unlocked** from both the live-playback path and the session-prep path, plus an ungated session lifecycle. ~10 audit findings collapse to this family. It **plausibly also feeds the long-standing BUG-012** MPSGraph `EXC_BAD_ACCESS` — note explicitly if the fix retires it.

| ID | Increment | Done-when |
|----|-----------|-----------|
| **CLEAN.1.1** | **Instrument + diagnose (commit & stop)** the BUG-031/032 family. Logging / test scaffolding that exposes (a) the unlocked input→predict→output interleave on the shared `StemSeparator`, and (b) the orphaned-prep-hijacks-next-session sequence. | Root cause documented in KNOWN_ISSUES; **no fix code** in this increment. |
| **CLEAN.1.2** | **BUG-031 fix.** `StemSeparator.separate()` writes `inputMag*Buffer` (`StemSeparator.swift:174-181`) and reads `outputBuffers` (`:196-204`) **outside** the lock that only `writeToBuffers()` (`:224-235`) holds → two concurrent calls corrupt stems. **DECISION FOR MATT (bring a recommendation):** (A) extend the lock to span the full input→predict→output pipeline, or (B) give session-prep its own `StemSeparator` instance (no sharing). Prefer returning stems **by value** over exposing shared `stemBuffers[]`. | Concurrency regression test RED pre-fix, green post; closeout ALL GREEN. |
| **CLEAN.1.3** | **BUG-032 fix (lifecycle cluster).** (i) `SessionManager.endSession()` (`:562-566`) doesn't cancel `sessionPreparationTask`/`statusCancellable` — mirror `cancel()` (`:542-557`). (ii) Gate the prep-completion closure by a **session-generation token** so a stale task can't overwrite the new session's plan/state (LF path already does this). (iii) `SessionPreparer.resumeFailedNetworkTracks` (`:509-519`) spawns a **second** concurrent `_runPreparation` loop — make it not. (iv) startSession source-mutation-before-state-guard. | Lifecycle + failure-path tests (red pre-fix); closeout green. |
| **CLEAN.1.4** | **BUG-033 (app layer — independent, can run in parallel).** Per-frame `@Published dashboardSnapshot` invalidates the whole SwiftUI tree at 60 Hz even when hidden; `assign(to:on:self)` retain cycles leak `SessionStateViewModel`/`PlaybackChromeViewModel` (deinit never runs). Throttle/decouple the snapshot + skip when hidden; `[weak self]`. | ViewModel deinit/retain-cycle tests; no 60 Hz tree invalidation; closeout green. |
| **CLEAN.1.5** | **G1: audio output-device route-change.** No listener for `kAudioHardwarePropertyDefaultOutputDevice` exists (verified) → on AirPods connect / monitor unplug the tap stays bound to the dead device and visuals **silently freeze**. Add the device-change listener + tap reinstall. | Manual: swap output device mid-session, visuals stay live. Automated: listener-fires test. |
| **CLEAN.1.6** | **G7: dynamic concurrency validation.** A ThreadSanitizer scheme + a stress harness (overlapping live+prep `StemSeparator` calls; rapid session start/end churn). Static review cannot prove the absence of races. | TSan-clean under stress; validates 1.2/1.3 didn't just move the race. |
| **CLEAN.1.7** | **G8: E2E session-lifecycle integration test.** Drive connect → prepare → ready → play → track-change → end → restart — the path the orphaning class lives on (today only per-VM unit + beat-grid wiring tests exist). | The cycle runs clean; would catch the orphaning class structurally. |

## Rules / pitfalls

- **Land 1.2 + 1.3 as a coherent unit** (one root cause). 1.4 is independent (app layer). 1.5/1.6/1.7 support and lock in the fixes.
- **Manual validation is required for concurrency** (the protocol): automated race tests + TSan prove pipeline correctness; a real session start/end/track-change exercise (Matt) confirms it feels right and doesn't deadlock/stall.
- **Per-increment closeout:** run `Scripts/closeout_evidence.sh`, paste the block verbatim (commit hash must match HEAD), update `KNOWN_ISSUES.md` + `RELEASE_NOTES_DEV.md` + `ENGINEERING_PLAN.md`, commit locally `[CLEAN.1.x] <component>: …`. **Do NOT `git push` without Matt's explicit "yes, push".**
- **Phase 4 perf (BUG-036)** shares `StemAnalyzer`/`StemSeparator` — it comes **after** this; land the locking first or the two will thrash the same files.
- This is **engine/app correctness work, not a preset increment** — `PRESET_SESSION_CHECKLIST.md` does **not** apply; the **Defect Handling Protocol** does.
- Salvage branches preserved for later phases (do not delete): Glass Brutalist (`confident-bassi`/`wizardly-galileo` → CLEAN.6.5), AGC3.6/BUG-029 (`naughty-goldstine` → focused increment), LM.3.2 (`eloquent-bhabha`).

**Start with CLEAN.1.1. Bring Matt the CLEAN.1.2 lock-strategy choice (A vs B) with a recommendation before implementing it.**
