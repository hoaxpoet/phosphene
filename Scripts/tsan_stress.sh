#!/usr/bin/env bash
# tsan_stress.sh — CLEAN.1.6 / GAP-7 dynamic concurrency validation.
#
# Runs the concurrency + session-lifecycle stress/regression tests under
# ThreadSanitizer to prove the BUG-031/032 fixes (CLEAN.1.2/1.3) removed the
# data races rather than moving them. Static review cannot prove the absence of
# races; this can.
#
# What it exercises (all under `swift test --sanitize=thread`):
#   - ConcurrencyStressTests           (opt-in heavy harness: live+prep overlap on
#                                        one shared StemSeparator; rapid session
#                                        start/end/cancel churn) — gated on
#                                        PHOSPHENE_STRESS=1, which this script sets.
#   - StemSeparatorConcurrencyTests    (BUG-031 regression — overlapping separate())
#   - SessionLifecycleGenerationTests  (BUG-032 — end-then-restart guard, source order)
#   - SessionRecoverySingleFlightTests (BUG-032 — recovery single-flight)
#   - ConcurrencyAuditProbeTests       (probe thread-safety)
#
# Pass condition: exit 0 AND no "ThreadSanitizer: data race" / "WARNING:
# ThreadSanitizer" line in the output. TSan is ~5-15× slower than a normal run
# and rebuilds with instrumentation on first use, so this is a separate on-demand
# gate, not part of the per-increment closeout.
#
# Usage: Scripts/tsan_stress.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

# macOS mktemp requires the XXXXXX template at the end (no suffix after it).
LOG="$(mktemp "${TMPDIR:-/tmp}/tsan_stress.XXXXXX")"

echo "==> TSan stress run (this rebuilds with instrumentation on first use; be patient)"

# Explicit per-test filters (unioned by swift test). Function names are stable
# anchors; suite display names contain spaces/parens that are awkward to match.
PHOSPHENE_STRESS=1 swift test --package-path PhospheneEngine --sanitize=thread \
  --filter liveAndPrepOverlap_sharedSeparator_raceFree \
  --filter sessionStartEndCancelChurn_raceFreeNoDeadlock \
  --filter concurrentSeparations_returnPerCallerOwnStems \
  --filter endThenRestart_staleOrphanDoesNotMutateNewSession \
  --filter rejectedStartSession_leavesPublishedSourceUntouched \
  --filter test_recoveryDuringActivePrep_isSingleFlight \
  --filter ConcurrencyAuditProbeTests \
  > "$LOG" 2>&1
TEST_EXIT=$?

# TSan reports races as warnings on stderr/stdout; the swift test exit code does
# NOT always reflect a TSan finding, so grep explicitly (no silent pass).
RACES=$(grep -c -E "ThreadSanitizer: data race|WARNING: ThreadSanitizer" "$LOG" || true)

echo "================ TSAN STRESS EVIDENCE ================"
echo "Commit    : $(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
echo "swift test exit code : $TEST_EXIT"
echo "ThreadSanitizer race/warning lines : $RACES"
echo "--- test summary (verbatim) ---"
grep -E "Test run with|Executed [0-9]+ tests|Suite .* (passed|failed)" "$LOG" | tail -8
if [ "$RACES" -ne 0 ]; then
  echo "--- ThreadSanitizer findings (first 40 lines) ---"
  grep -n -A2 -E "ThreadSanitizer: data race|WARNING: ThreadSanitizer" "$LOG" | head -40
fi
echo "--- full log: $LOG"
if [ "$TEST_EXIT" -eq 0 ] && [ "$RACES" -eq 0 ]; then
  echo "VERDICT: TSAN CLEAN (no data races under stress)"
else
  echo "VERDICT: TSAN FAILURES PRESENT (see above)"
fi
echo "====================================================="
