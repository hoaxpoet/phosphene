# Increment BUG087.2 + BUG087.3 — raise the local-file analysis rate from 10 Hz

**Type:** fix (engine + app audio path; no preset, no shader, no sidecar)
**Defect:** BUG-087, diagnosed 2026-08-11 (BUG087.1, merged). Read its
`KNOWN_ISSUES.md` entry first — the root cause is already established and this session
does not re-derive it.
**Two increments, one prompt, with a mandatory hard stop between them** (task 4).
BUG087.2 is a prerequisite for BUG087.3 and must land and verify on its own commit.

**Objective.** After this session, a local-file session analyses at **≥ 40 Hz** instead of
10.0 Hz, and the analysis time base is derived from audio frames consumed rather than
wall-clock — so the seconds-based followers DYN.4/DYN.5 introduced stay correct when more
than one analysis frame is produced per audio callback. `Scripts/measure_analysis_rate.py`
on a fresh local-file capture reports ≥ 40 Hz and a buffer interval ≤ 25 ms.

---

## 1. Why the time base comes first (the trap this increment exists to avoid)

The obvious fix — slice the oversized tap buffer and invoke the audio callback once per
slice — **silently corrupts every rate-dependent follower in the MIR chain if done first.**

`processAnalysisFrame` (`PhospheneApp/VisualizerEngine+Audio.swift`) derives
`dt = now - lastAnalysisTime` from `CFAbsoluteTimeGetCurrent()` and passes both `dt` and
`effectiveFps = 1/dt` into `MIRPipeline.process`. Slices delivered in a loop arrive
microseconds apart, so `dt` collapses toward zero and `effectiveFps` explodes.

That is not cosmetic. `deltaTime` feeds `LoudnessProfile.emaAlpha(deltaTime:, tau:)` in
`SpectralAnalyzer+Density.swift` (DYN.4, `715eaf8c`) and the centroid / rolloff / flux
followers (DYN.5, `11723445`), and `fps` feeds `BandEnergyProcessor`. Those were
*deliberately* converted from frame counts to seconds; a wrong `dt` un-does that work
without failing a test.

**So: fix the time base, verify it is a no-op on today's one-callback-per-buffer behaviour,
commit, stop. Then slice.**

---

## 2. Skill invocations

- **`defect-handling`** — at session start, before any code change. This is BUG-* work.
- **`closeout`** — at the end, before any commit is called final.
- **Not** `preset-session` or `shader-authoring` — no `.metal`, no sidecar, no preset source
  is touched. Wanting either means scope has been exceeded.

---

## 3. Read first

In this order. Skills carry the protocol; this list is only the increment's own surface.

1. `docs/QUALITY/KNOWN_ISSUES.md` → **BUG-087** entry (root cause, the rate-independence
   discriminator, and the verification criteria already written for this fix).
2. `PhospheneEngine/Sources/Audio/LocalFilePlaybackProvider.swift` — the `installTap`
   call site (~line 292) and `handleTapBuffer` (~line 454) in full.
3. `PhospheneApp/VisualizerEngine+Audio.swift` — `makeAudioSampleCallback` and
   `processAnalysisFrame`; note where `dt`, `effectiveFps` and `lastAnalysisTime` are set
   and consumed.
4. `PhospheneEngine/Sources/DSP/SpectralAnalyzer+Density.swift` §`advanceLevelAndDensity`
   — the seconds-based EMA path that a wrong `dt` corrupts.
5. `Scripts/measure_analysis_rate.py` — header comment; this is the verification tool and
   the method is already validated across the corpus.
6. `docs/ENGINE/RENDER_CAPABILITY_REGISTRY.md` → the AGC-normalised deviation-primitives
   row, which carries the 10 Hz authoring note this fix invalidates.

Do **not** read the CHR/Stave docs, `MILKDROP_STRATEGY.md`, or any preset design doc —
none of this touches preset authoring.

---

## 4. Pre-flight invariants

Each failed check stops the session before task 1.

1. Fresh branch off current `origin/main`: `claude/bug087-analysis-rate`.
   `git status --porcelain` clean.
2. Full suite green at the branch point: `swift test --package-path PhospheneEngine`,
   `xcodebuild -scheme PhospheneApp -destination 'platform=macOS' test`, and
   `swiftlint lint --strict`. **Red at the branch point is not this session's problem —
   report and stop.**
3. `python3 Scripts/measure_analysis_rate.py` runs and reproduces the diagnosis: every
   `local` row reads ≈ 10 Hz / ≈ 100 ms, the `streaming` row reads ≈ 51 Hz / ≈ 20 ms.
   **If local rows already read ≥ 40 Hz, the defect is not reproducible on this tree —
   stop and report rather than "fixing" what is already fixed.**
4. No `PhospheneApp` process is running (`pgrep -fl "MacOS/PhospheneApp"` empty) — a live
   app blocks the XCTest host (BUG-072) and the app suite is a gate here.

---

## 5. Tasks

### Task 1 — Assert the boundary that lied

Make the ignored `bufferSize` request fail loudly instead of silently costing 5× rate. At
the `installTap` site, compare the first delivered buffer's `frameLength` against what was
requested and record the discrepancy to `session.log` via the provider's existing
diagnostic route (`onDiagnosticEvent` / the `TAP:`-style recorder line — match whichever
the provider already uses; do not add a new logging mechanism).

**Done when:** a local-file session's `session.log` states the requested and delivered
buffer sizes, and a test asserts the recorded delivered size is what the analysis rate is
computed from. This is the "ignored hint fails loudly" criterion already written into
BUG-087.

### Task 2 — Derive the analysis time base from audio, not wall-clock (BUG087.2)

Give `processAnalysisFrame` a `dt` that comes from the number of audio frames the callback
carried (`frames / sampleRate`) rather than from `CFAbsoluteTimeGetCurrent()`. The frame
count is already available at the callback boundary (`count` is total samples,
`channelCount` is passed alongside), so this needs no new contract — but plumbing it to
`processAnalysisFrame`, which currently receives only `magnitudes`, does need a signature
change. Keep wall-clock as a fallback only where no frame count is available.

**This must be behaviour-neutral today.** With one callback per buffer, frame-derived `dt`
and wall-clock `dt` already agree to within scheduling jitter — that equivalence is the
test, not an assumption.

**Done when:**
- A test asserts frame-derived `dt` equals `frames / sampleRate` for representative buffer
  sizes at both 44 100 and 48 000 Hz.
- The full engine + app suite is green **with no golden or expectation edits.** Any test
  that moves here is a real behaviour change and is a stop-and-report, not a number to
  update.
- `Scripts/measure_analysis_rate.py` still reports ≈ 10 Hz on the existing captures
  (this task does not change the rate — only where `dt` comes from).

### Task 3 — Commit task 2, separately

`[BUG087.2] Analysis: derive dt from audio frames, not wall-clock`. Its own commit, before
any slicing exists, so `git bisect` can separate the time base from the rate change.

### Task 4 — HARD STOP. Report before slicing.

State: what changed in task 2, that the suite is green with no expectation edits, and the
measured rate is still ≈ 10 Hz. **Do not begin task 5 in the same breath.** If task 2 moved
any test, stop here and report that instead — a time-base change that alters current output
means an existing follower was relying on wall-clock jitter, which is a finding worth
Matt's attention before it is buried under a rate change.

### Task 5 — Slice the oversized tap buffer (BUG087.3)

In `handleTapBuffer`, invoke the callback once per ~1024-frame slice instead of once per
buffer, so a 4800-frame buffer produces ~5 analysis frames.

Constraints, all of which have bitten this repo before:

- **Real-time safety (BUG-036 lineage).** The audio tap callback must not allocate per
  slice. `interleavedScratch` is already reused and already resizes for oversized buffers
  — keep that property; slice by offsetting into it, not by building new arrays.
- **Do not touch the streaming path.** `handleTapBuffer` is local-file only; the system tap
  already delivers ~939-frame buffers at ~51 Hz and is correct. If a change reaches
  `AudioInputRouter`'s tap IOProc, scope has been exceeded.
- **Do not request a smaller `bufferSize` as the fix.** BUG087.1 established that
  AVAudioEngine ignores it — 4414 frames at 44.1 kHz and 4808 at 48 kHz are both exactly
  0.1 s, a fixed duration. That route is a measured dead end.
- **Do not pace or sleep** to spread slices over wall-clock. That blocks the audio thread.
  Correct `dt` (task 2) is what makes burst delivery safe.
- The final slice of a buffer will be short. Handle the remainder; do not drop it and do
  not pad it with zeros (a zero-padded tail is a fake transient into the onset detectors).

**Done when:**
- `Scripts/measure_analysis_rate.py` on a **fresh local-file capture** reports **≥ 40 Hz**
  and buffer interval **≤ 25 ms**. This needs Matt to record one session; the tool needs no
  app instrumentation.
- A test asserts slice count × slice frames accounts for the whole buffer with no dropped
  or synthesised samples.
- Full suite green.

### Task 6 — Fix-increment doc obligations

`docs/QUALITY/KNOWN_ISSUES.md` (BUG-087 → Resolved + commit hash, or an explicit statement
of what remains), `docs/RELEASE_NOTES_DEV.md`, `docs/ENGINEERING_PLAN.md`, and the
**capability-registry row** whose 10 Hz authoring note this fix invalidates — all four in
the same increment. The registry note currently tells preset authors to assume 100 ms steps
on the local-file path; leaving it stale is the documentation-drift failure mode this repo
keeps re-learning (D-120 came back into two shipped sidecars that way).

### Task 7 — Closeout

---

## 6. Do NOT

- **No `.metal`, no sidecar, no preset source.** If a preset looks wrong after the rate
  change, that is an M7 finding for Matt, not a tuning edit in this session.
- **Do not re-tune any smoothing constant, EMA tau, or threshold** to compensate for the
  new rate. If DYN.4/DYN.5's seconds-based followers are correct, they are rate-invariant
  by construction and need no adjustment — and if one turns out not to be, that is a
  finding to report, not to paper over. Tuning constants to chase a rate change is how the
  D-102 / FA #58 spiral starts.
- **Do not change `MLDispatchScheduler`, the stem separation cadence, or anything in
  BUG-086's surface.** They are adjacent and independently open; touching both in one
  session makes neither attributable.
- Do not "fix" `handleTapBuffer`'s scratch resize — BUG087.1 checked it and it is correct.
- Do not update a golden or an expected value to make a test pass (see task 2's done-when).
- No push without Matt's explicit "yes, push"; then branch + PR, never direct to `main`.

---

## 7. Verification

```
swiftlint lint --strict --config .swiftlint.yml
xcodebuild -scheme PhospheneApp -destination 'platform=macOS' build 2>&1
swift test --package-path PhospheneEngine 2>&1
xcodebuild -scheme PhospheneApp -destination 'platform=macOS' test 2>&1
```

Increment-specific:

```
python3 Scripts/measure_analysis_rate.py
python3 Scripts/measure_analysis_rate.py ~/Documents/phosphene_sessions/<fresh-capture>
python3 Scripts/measure_stem_latency.py ~/Documents/phosphene_sessions/<fresh-capture>
```

All expected green. The third is a **watch-for**, not a gate: BUG-087 is a recorded lead
for BUG-086's unexplained weak local-file stem/band correlation (r 0.19–0.46 vs streaming's
0.70–0.94). If raising the rate also raises that correlation, say so — it closes a question
four other hypotheses failed to. If it does not, say that too; a refuted lead is worth
recording.

**Manual validation is required and cannot be waived.** This changes how often every
`FeatureVector` field updates on the path all preset work runs on, so it changes the feel
of every preset. M7-class observation on at least one certified preset with visible
continuous coupling — Aurora Veil is the natural pick, since `other_energy_dev` is its
song-defining anchor and it is already owed an M7 for BUG-086.

---

## 8. Commit message templates

Small commits, local-only until Matt says otherwise.

```
[BUG087.2] Analysis: derive dt from audio frames, not wall-clock
[BUG087.2] Audio: log requested vs delivered tap buffer size
[BUG087.3] LocalFilePlayback: slice the tap buffer to ~1024-frame analysis frames
[BUG087.3] Defects: BUG-087 resolved — local-file analysis at NN Hz (fill measured)
[BUG087.3] Docs: registry, EP and release notes for the analysis-rate fix
```

---

## 9. Closeout format

Invoke the `closeout` skill; produce the 8-part report with the verbatim
`Scripts/closeout_evidence.sh` block as §2. Increment-specific additions:

- `measure_analysis_rate.py` output **before and after**, on a real local-file capture.
- The task-4 hard-stop statement and whether any test moved at task 2.
- Whether the BUG-086 correlation lead was confirmed or refuted (§7).
- The M7 result, or an explicit "code-complete, pending live M7" — this is a felt change,
  so "resolved" is not available without Matt's observation.

---

## 10. DECISION-NEEDED

**#1 — Do you want to compare the two rates before the faster one becomes the default?**

Every preset will respond about five times more often on local files after this. Eighteen
certified presets were tuned against the slow rate without anyone knowing, so the change
could read as more alive — or as jittery — and neither of us can tell from the numbers.

- **A — Ship it as the default, and treat any preset that now reads jittery as a separate
  finding.** *(Recommended.)* The followers are seconds-based by construction and should be
  rate-invariant, so most likely nothing visibly changes except that fast material tracks
  better. Simplest, and the catalog gets reviewed only if something actually looks wrong.
- **B — Ship it behind a temporary switch so you can watch the same track both ways**
  before it becomes default. Costs one extra session to remove the switch afterwards, and
  the switch is dev-only, never user-facing.
- **C — Hold the rate change entirely** and land only the time-base fix (BUG087.2), leaving
  10 Hz until you have seen a side-by-side. Lowest risk, leaves the defect open.

**Default if no reply: A.** The fix restores intended behaviour rather than introducing new
behaviour, and holding a correctness fix on an aesthetic maybe is the wrong default. If any
certified preset does read worse, that is one M7 note and a follow-up increment.
