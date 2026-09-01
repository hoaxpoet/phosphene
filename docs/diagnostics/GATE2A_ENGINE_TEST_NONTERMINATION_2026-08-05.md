# GATE.2a Engine Debug Test Non-Termination Diagnostic — 2026-08-05

> **Preserved 2026-09-01, verbatim.** Investigated by the Codex session on 2026-08-05 and
> never committed; recovered from that worktree before it was cleared. Paths read
> `PhospheneEngine/` because this predates the RN.2 rename — the tree is `UzumeEngine/`
> today. Kept for its **negative result**: the debug engine suite is slow, not stalled, and
> no production subsystem is implicated. Read it before re-opening that question.

Status: **diagnosis complete — slow-but-progressing; no production fix indicated.**

## Pre-implementation evidence contract

**Expected.** The debug engine suite either completes, or a bounded diagnostic runner
identifies the active test process and live test progress before terminating every process
that it launched. The runner must not signal a Phosphene app, test, or SwiftPM process from
another worktree.

**Actual baseline.** The 2026-08-05 audit bounded
`swift test --package-path PhospheneEngine` at five minutes. Its buffered output still showed
passing tests near termination, the watchdog returned exit 143, and one run left an orphaned
`swift-test`/`xctest` process requiring manual cleanup. That evidence did not record elapsed
time between progress events, the active test, parent/child PIDs, process group, terminal test
names, or whether the suite was slow versus stalled. It does not identify
`SessionRecoverySingleFlightTests` or any production subsystem as the cause.

**Reproduction steps.** Run the new bounded diagnostic path from the repository root against
the full debug engine suite. Preserve its event stream, process snapshots, last-progress
record, termination record, command exit, and post-run ownership-scoped process check. If the
first run stalls, capture a process sample before cleanup, then narrow with focused or
partitioned runs. Exact commands and artifacts will be recorded below.

**Session artifacts required.** Elapsed wall time; the source of per-test progress; runner,
`swift-test`, and `xctest` PIDs; parent PIDs and process groups; final observed test names;
the command exit code; any captured process tree and sample/backtrace; cleanup signals; and an
ownership-scoped post-run statement that no launched process remains.

**Suspected failure class.** `test-isolation` or `resource-management`. No narrower claim is
supported before capture.

**Verification criteria.** Automated: one bounded-run regression exercises the runner's
timeout/stall cleanup and proves its complete launched process tree exits. Diagnostic:
run the bounded path against the engine suite, plus one focused suite seen near the prior
timeout and one independent focused suite. Manual: inspect the runner's recorded PIDs after
each run and confirm that none of its `swift-test`, `xctest`, or SwiftPM-lock-owning processes
survives. A fixed five-minute wall-clock limit without a progress-age measurement is not proof
of a stall.

## Preflight

- Worktree: clean, detached `HEAD` at `69fcde65` (`[GATE.1] Tests: complete release
  configuration coverage`).
- GATE.1: complete; its release-test fix is out of scope.
- BUG-078 relationship: unproven. Its recorded signature is an intermittent
  `AVAudioPlayerNode` teardown SIGTRAP/nonzero test-process exit, not a captured stall.

## Evidence

### Diagnostic runner

`Scripts/bounded_test_runner.py` launches the requested command under a PTY in a new process
session, timestamps Swift Testing/XCTest progress events, snapshots the owned descendant tree,
and writes machine-readable metadata. A run is `stalled` only after a test-progress event and
then the configured no-progress interval. The independent maximum runtime is a safety bound
and reports `max-runtime-without-stall-proof` rather than inventing a hang.

On a bound or interruption, the runner samples a live owned `xctest` or
`swiftpm-testing-helper` when available, then sends TERM and (after a grace interval) KILL to
the runner-owned process group and the descendants present in the immediately preceding
snapshot. Historical build PIDs are retained as evidence but never used as later kill targets,
avoiding PID-reuse interference with another worktree. `Scripts/test_bounded_test_runner.py`
regression-locks a TERM-resistant root plus sleeping child; it passed and reported no survivor.

### Run 1 — clean-build full debug suite

Exact command:

```bash
Scripts/bounded_test_runner.py \
  --output-dir /tmp/phosphene-gate2a-full-20260805-1 \
  --stall-seconds 120 --max-seconds 600 --term-grace-seconds 8 \
  --sample-seconds 3 -- \
  swift test --package-path PhospheneEngine
```

Result:

```text
runner PID 48039
swift-test PID 48041, PPID 48039, PGID 48041
xctest PID 49446, PPID 48041, PGID 49446
swiftpm-testing-helper PID 49705, PPID 48041, PGID 49705
classification=completed
elapsed=378.391s
command_exit=1
cleanup_remaining=[]
last progress: Test run with 1784 tests in 266 suites failed after 221.790 seconds with 64 issues.
```

The raw PTY log is 2,258,129 bytes and contains 5,091 matched test-progress events. The run
continued to make progress beyond five minutes: at runner elapsed 316.279 s,
`Mitosis gen-2 geometry (Cytokinesis)` completed; at 378.221 s, the Mitosis cycle-luminance
test and suite completed; the aggregate test result followed at 378.228 s. This is direct
evidence against a stall classification.

The exit-1 test result was environmental, not a termination failure: this worktree had not
linked its documented gitignored tempo fixtures and ML weights. Missing-fixture/weight issues
accounted for the broad red surface, including the lifecycle churn fixture guard. The runner
still observed normal suite termination and left no owned process.

### Fixture-complete focused runs

`Scripts/link_fixtures.sh --verify` found the primary checkout complete (3 required tempo
files and 479 required ML weight files); `Scripts/link_fixtures.sh` linked those ignored
artifacts. The following exact commands then ran through the same bounded path:

```bash
Scripts/bounded_test_runner.py --output-dir /tmp/phosphene-gate2a-recovery-20260805 \
  --stall-seconds 30 --max-seconds 120 --term-grace-seconds 5 --sample-seconds 3 -- \
  swift test --package-path PhospheneEngine --filter SessionRecoverySingleFlightTests

Scripts/bounded_test_runner.py --output-dir /tmp/phosphene-gate2a-scorer-20260805 \
  --stall-seconds 30 --max-seconds 120 --term-grace-seconds 5 --sample-seconds 3 -- \
  swift test --package-path PhospheneEngine --filter PresetScorerTests

Scripts/bounded_test_runner.py --output-dir /tmp/phosphene-gate2a-churn-20260805 \
  --stall-seconds 30 --max-seconds 180 --term-grace-seconds 5 --sample-seconds 3 -- \
  swift test --package-path PhospheneEngine --filter SessionLifecycleChurnTests
```

| Focus | Tool result | Runner wall time | Root / PGID | Cleanup |
|---|---|---:|---|---|
| `SessionRecoverySingleFlightTests` (appeared near the audit bound) | 1 test passed in 0.411 s | 3.061 s | 52896 / 52896 | no survivor |
| `PresetScorerTests` (independent logic suite) | 14 tests passed in 0.006 s | 2.673 s | 53071 / 53071 | no survivor |
| `SessionLifecycleChurnTests` (BUG-078-adjacent) | 6 tests passed in 11.008 s | 12.577 s | 53118 / 53118 | no survivor |

The lifecycle focus includes the previously implicated teardown shapes:
`completionCallbackVsStop_abbaShape_neverDeadlocks` (2.366 s),
`deinitWhilePlaying_quitShape_neverHangs` (1.274 s), and
`concurrentDoubleStart_serializesWithoutDeadlock` (0.957 s). No SIGTRAP or nonzero
assertion-free exit occurred.

### Run 2 — warmed, fixture-complete full debug suite

Exact command:

```bash
Scripts/bounded_test_runner.py \
  --output-dir /tmp/phosphene-gate2a-full-20260805-2 \
  --stall-seconds 120 --max-seconds 600 --term-grace-seconds 8 \
  --sample-seconds 3 -- \
  swift test --package-path PhospheneEngine
```

Result:

```text
runner PID 53206
swift-test PID 53207, PPID 53206, PGID 53207
xctest PID 53220, PPID 53207, PGID 53220
swiftpm-testing-helper PID 53453, PPID 53207, PGID 53453
classification=completed
elapsed=293.484s
command_exit=0
cleanup_remaining=[]
last progress: Test run with 1784 tests in 266 suites passed after 218.848 seconds with 1 known issue.
```

The final individual progress was the Mitosis cycle-luminance test at 212.685 test seconds;
the Mitosis suite completed at 218.838 s and the aggregate pass followed at 218.848 s. The
raw PTY log is 1,575,200 bytes and contains 5,082 matched progress events. No sample/backtrace
was captured because neither full run met the evidence-based stall condition.

### Manual process and lock check

After every run, `metadata.json` reported an empty `cleanup_remaining_pids`. A final read-only
process-table query scoped to this exact worktree found no surviving `swift-test`, `xctest`,
or `swiftpm-testing-helper`; the only matches were the query's own shell/`awk` command.
`lsof PhospheneEngine/.build/build.db` returned no lock holder. An existing user-owned xctest
from a different worktree (PID 64560) was visible during preflight and was never signalled.

## Diagnosis

**Classification: slow-but-progressing.** The audit's exit 143 came from a fixed five-minute
watchdog that did not distinguish build/test progress from a stall and did not own/clean the
whole spawned tree. GATE.2a reproduced the critical timing fact: a clean-build run required
378.391 s end-to-end while emitting continuous test progress, so a 300 s termination can cut
off healthy work. Even the warmed pass used 293.484 s, leaving only 6.516 s of margin under
the old bound.

This establishes the runner/watchdog failure class; it does not retroactively identify which
test was executing at the audit cutoff because the audit did not retain that evidence. No
production subsystem root cause is proved or suggested by these captures.

**BUG-078 remains unrelated to the captured non-termination evidence.** Its known signature is
an intermittent AVAudio teardown SIGTRAP/nonzero exit without a failing assertion. GATE.2a
captured neither that trap nor a stall, and its BUG-078-adjacent focus was green. This is not a
closure or a claim that the intermittent has been ruled out; BUG-078 retains its debugger and
five-consecutive-full-run criteria.

## Next evidence

Stop for review. No production fix is warranted. The remaining product/process choice is
whether the canonical closeout script should adopt the bounded runner. If a future run is
classified `stalled`, the required next evidence is already mechanized: active/recent test
events, owned process tree, `sample` output, cleanup signals, command exit, and post-cleanup
survivor check. Only that capture should reopen production fault isolation.

## Closeout status

The required `Scripts/closeout_evidence.sh` invocation completed rather than hanging, but its
engine gate was red, so this increment is **not cleanly committable under the closeout
protocol**. The evidence block reported:

```text
engine: exit 1, 347 s
XCTest: 229 tests, 7 skipped, 3 failures in 93.923 s
Swift Testing: 1,784 tests / 266 suites passed in 247.027 s (1 known issue)
app: 407 tests / 70 suites passed
SwiftLint: 0 violations
DocIntegrityTests: 12 tests passed
repo lint scripts: passed
```

The three XCTest failures were wall-clock performance gates outside this increment's changed
surface. One bounded isolated rerun of each reproduced the failure, so no green result is being
forced:

| Suite / test | Isolated measurement | Required |
|---|---:|---:|
| `PostProcessChainTests.test_fullChain_under2ms_at1080p` | 7.59 ms | < 5 ms |
| `RayMarchPipelineTests.test_fullPipeline_under8ms_at1080p` | 8.08 ms | < 8 ms |
| `StemModelTests.test_predict_performance_under400ms` | 472 ms | < 400 ms |

All three had passed in the fixture-complete full run earlier in this diagnostic. That makes
the result load/timing-sensitive evidence, not authorization to change renderer, ML, or test
budgets in GATE.2a. The increment stops uncommitted for review. Every isolated bounded command
terminated and reported an empty cleanup survivor set.
