# Increment MOOD-FLUX.3 — Unify the offline + live FFT-magnitude path (mechanize BUG-066)

Execute Increment MOOD-FLUX.3.

Authoritative spec: `docs/ENGINEERING_PLAN.md` §Phase MOOD-FLUX §MOOD-FLUX.3.
Background: `docs/diagnostics/BUG-066-diagnosis.md` (read it first — it is the whole reason this increment exists).

────────────────────────────────────────
WHY THIS EXISTS
────────────────────────────────────────

BUG-066: the offline session-prep MIR path (`SessionPreparer.analyzeMIR`) had its **own reimplementation** of the FFT magnitude formula (`computeFFTMagnitudes` + the `FFTContext` struct) that silently **drifted** from the live `Audio/FFTProcessor` — `sqrt(power/fftSize)` (=|FFT|/32) vs live `|FFT|×2/fftSize` (=|FFT|/512), a 16× difference. Because spectral flux is fed raw into the MoodClassifier's z-score, this saturated the mood flux input on every track and quietly degraded preset selection for months (mood is 30 % of the scorer).

MOOD-FLUX.2 (`1d61830`) fixed the **values** by making `computeFFTMagnitudes` byte-identical to `FFTProcessor` (`vDSP_zvabs` + `×2/fftSize`). **MOOD-FLUX.3 fixes the STRUCTURE**: there must be exactly **one** implementation of the window→magnitude formula, so the two paths can never drift apart again. This is the D-161 ratchet in spirit ("violated → mechanize"): the duplicate is the defect.

**This is a behaviour-PRESERVING refactor.** After MOOD-FLUX.2 the two implementations already produce identical magnitudes, so unifying them must change **no** output. If your change alters any mood/MIR feature value, you have a bug — not a behaviour change to accept.

────────────────────────────────────────
PRECONDITIONS
────────────────────────────────────────

- The BUG-066 fix must be on `main`. Verify:
  `git log --oneline | grep -i "MOOD-FLUX.2"` shows `1d61830` (fix) and it is an ancestor of HEAD.
  `grep -n "zvabs" PhospheneEngine/Sources/Session/SessionPreparer+Analysis.swift` — the offline path already uses `vDSP_zvabs` + `× 2/fftSize`. If it still uses `vDSP_zvmags`/`sqrt`, STOP — MOOD-FLUX.2 is not present; do not proceed.
- Confirm the two implementations you are unifying:
  - Live: `PhospheneEngine/Sources/Audio/FFTProcessor.swift` `runFFTCore` — Hann (`vDSP_HANN_NORM`) → `vDSP_zvabs` → `× 2/fftSize`, allocation-free per BUG-036 (reuses `magnitudesScratch`; writes the UMA `magnitudeBuffer`).
  - Offline: `PhospheneEngine/Sources/Session/SessionPreparer+Analysis.swift` `computeFFTMagnitudes` + `struct FFTContext` — the same formula, pure-CPU, no device.
- Module deps already allow this: the `Session` target depends on `Audio` (`Package.swift`), so `FFTProcessor` / a shared Audio helper is importable from `Session` with no new dependency.

────────────────────────────────────────
DELIVERABLE
────────────────────────────────────────

One source of truth for "windowed samples → 512 magnitude bins (Hann, |FFT|×2/fftSize)", consumed by BOTH the live `FFTProcessor` and the offline `analyzeMIR`, plus a regression guard that fails if they ever diverge again.

Two viable approaches — pick one, justify it, and note the trade-off in the closeout:

**Approach B (recommended) — extract a shared pure magnitude kernel.** Factor the window+FFT+magnitude math into ONE small allocation-free helper in the `Audio` module (e.g. `FFTMagnitudeKernel` or a static func taking a caller-owned scratch + FFT setup). `FFTProcessor.runFFTCore` calls it; `analyzeMIR` calls it (deleting `computeFFTMagnitudes` + `FFTContext`). Keeps the offline path CPU-only (no `MTLDevice`, no GPU-buffer round-trip) and preserves FFTProcessor's RT allocation-free property (BUG-036). This is the cleaner unification.

**Approach A — route offline through `FFTProcessor` directly.** `analyzeMIR` constructs an `FFTProcessor` (needs a `MTLDevice` — thread one in; the prep path already has one for `StemSeparator`/`BeatGridAnalyzer`), feeds 1024-sample non-overlapping windows, and reads magnitudes back from the UMA `magnitudeBuffer`. Fewer moving parts conceptually but adds a device dependency + GPU-buffer read to a pure-CPU offline path, and per-call `FFTProcessor` allocation. Only choose this if B proves more invasive than expected.

Constraints (either approach):
- **Byte-identical output.** The magnitudes (and therefore every downstream mood/MIR feature) must be exactly what the current code produces. Prove it (see Tests).
- **Do NOT regress `FFTProcessor`'s RT allocation-free path (BUG-036).** If you refactor `runFFTCore`, the per-frame path must stay allocation-free (caller-owned scratch, no per-call `[Float]` allocation). There is an existing allocation guard test — keep it green.
- Delete the now-dead `computeFFTMagnitudes` / `FFTContext` (the whole point is no second implementation left behind — do not leave it as "reusable infrastructure").
- `FFTResult`'s dominant-frequency/`binResolution` metadata is FFTProcessor-specific; `analyzeMIR` does not need it — the shared kernel produces magnitudes only.

────────────────────────────────────────
TESTS
────────────────────────────────────────

- **The mechanization guard (the load-bearing new test).** A unit test that computes magnitudes for the SAME input via BOTH consumers (or asserts both call the single kernel) and asserts they are identical bin-for-bin. This is what makes a future drift fail CI — it is the reason for the increment. Include a comment tying it to BUG-066.
- **Parity / no-behaviour-change.** Prove the refactor changed nothing: e.g. capture `analyzeMIR`'s magnitude output (or the 10 mood features) on a committed fixture before and after, assert identical (a golden, or a same-input equality test against the pre-refactor formula preserved in the test). The `MoodClassifierGolden` test stays green (classifier untouched).
- Full mood/MIR/session-prep/spectral suites green: `swift test --filter "Mood|MIR|Spectral|SessionPrep|Analysis|FFT"`.
- The `CorpusCensusRunner` census mirror (`CensusAnalysis.swift` `computeMagnitudes`) — decide whether it also adopts the shared kernel. It is a diagnostic mirror of the offline path; keeping it identical to production is the point, so prefer routing it through the same kernel too (Audio is already a census dep). If you don't, note why.

────────────────────────────────────────
DONE-WHEN
────────────────────────────────────────

- Exactly one implementation of the window→magnitude formula remains; `computeFFTMagnitudes`/`FFTContext` deleted.
- Byte-identical output proven (parity test) — no mood/MIR feature value changes. `MoodClassifierGolden` green.
- The divergence-guard test is present and green (and would fail if the formula is forked again).
- `swift build` + full engine suite green (note the known worktree-environmental failures if you are in a worktree — they pass in isolation; app/lint/doc gates are the trustworthy worktree signal); `swiftlint --strict` 0 on touched files; app build unaffected.
- BUG-036 allocation guard for the live RT path still green.
- Docs: EP MOOD-FLUX.3 row flipped with evidence; a one-line note in BUG-066-diagnosis.md that the class is now mechanized; RELEASE_NOTES_DEV entry. Closeout per CLAUDE.md (`Scripts/closeout_evidence.sh` block verbatim); commit `[MOOD-FLUX.3] <component>: <desc>`; NO push without Matt's explicit approval.

────────────────────────────────────────
GUARDRAILS
────────────────────────────────────────

- This is a **behaviour-preserving refactor.** If you cannot keep the output byte-identical, stop and report — do not "improve" the formula in the same increment.
- If Approach B turns out to require restructuring `FFTProcessor` in a way that risks the BUG-036 allocation-free RT path, stop and report the trade-off before proceeding (a mis-timed refactor of the live audio hot path is worse than the duplication it removes).
- No behaviour changes to the live path. The live mood was always correct; this increment must not touch what it produces.
- If, after reading the code, you judge the unification more invasive than the recurrence-risk it removes, say so and propose the lighter alternative (e.g. keep two call sites but a single shared kernel + the guard test) rather than forcing a full merge.
