#!/usr/bin/env bash
# closeout_evidence.sh
#
# REVIEW.3 closeout evidence generator. Runs the canonical verification set
# (RUNBOOK.md §Build and Test: engine SPM tests, app xcodebuild tests,
# swiftlint --strict, plus the DOC.6 doc gates via DocIntegrityTests) and
# emits ONE fenced markdown evidence block to stdout.
# A byte-identical copy is written to ~/.phosphene/last_closeout_evidence.md
# so a pasted closeout block can be diffed against what was actually generated.
#
# Honesty contract (REVIEW.3 — eliminating the false-green closeout class):
#   - Step failures are REPORTED, never fatal: each step's exit code is
#     captured and the run continues. The script itself exits 0 when it
#     successfully gathered evidence; the verdict line carries pass/fail truth.
#   - Counts are EXTRACTED from tool output (additive grep — pull summary /
#     failure lines), never computed by this script's own arithmetic. If
#     extraction finds no recognizable summary, the block says
#     "PARSE FAILED — raw output follows" with the raw tail of the log.
#     The block never contains a count the tools did not emit.
#   - No suppression flags, no subtractive output filtering, no quick modes.
#     One mode, one truth.
#   - A step that cannot run at all (missing tool) appears in the block as
#     STEP FAILED TO RUN — never as a silent skip.
#   - A dirty tree is reported, not fatal (parallel sessions are normal).
#
# Usage: Scripts/closeout_evidence.sh    (no arguments; runnable from anywhere)

set -uo pipefail

# --- Locate repo root; everything runs from there -----------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

EVIDENCE_DIR="${HOME}/.phosphene"
EVIDENCE_FILE="${EVIDENCE_DIR}/last_closeout_evidence.md"
mkdir -p "$EVIDENCE_DIR"

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/closeout_evidence.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT
BLOCK="$TMP_DIR/block.md"

# Max failing-test identifiers listed per step, and raw-tail length on a
# parse failure. Listing caps are stated in the block (no silent truncation).
MAX_FAILURES=20
RAW_TAIL_LINES=30

# --- Helpers -------------------------------------------------------------------
emit() { printf '%s\n' "$*" >> "$BLOCK"; }

# Run one step: $1=log file, $2...=command. Echoes the exit code, or the
# sentinel 255 + marker file when the tool binary is absent.
run_step() {
  local log="$1"; shift
  local tool="$1"
  if ! command -v "$tool" > /dev/null 2>&1; then
    printf 'tool %s not found on PATH\n' "$tool" > "$log"
    echo "TOOL_MISSING"
    return 0
  fi
  "$@" > "$log" 2>&1
  echo "$?"
}

# Additive extraction of test-summary lines from a log. Recognizes both
# XCTest aggregate lines and swift-testing run-summary lines.
#
# CLEAN.5.3: a swift-testing-only suite (e.g. DocIntegrityTests) still emits the
# XCTest aggregate "Executed 0 tests, with 0 failures" — misleading next to the
# real "Test run with N tests … passed". When a swift-testing summary is present
# AND the XCTest aggregate is zero, drop the zero line. Display-only; the verdict
# logic reads xctest_failure_count + exit codes directly, so honesty is intact.
summary_lines() {
  local log="$1"
  local allsuite xctest swifttesting
  allsuite="$(grep -E "Test Suite 'All tests' (passed|failed)" "$log" 2> /dev/null | tail -2)"
  xctest="$(grep -E "Executed [0-9]+ tests?," "$log" 2> /dev/null | tail -1)"
  swifttesting="$(grep -E "Test run with [0-9]+ tests?.*(passed|failed)" "$log" 2> /dev/null | tail -2)"
  if [ -n "$swifttesting" ] && printf '%s' "$xctest" | grep -qE "Executed 0 tests?,"; then
    xctest=""
  fi
  printf '%s\n%s\n%s\n' "$allsuite" "$xctest" "$swifttesting" \
    | sed 's/^[[:space:]]*//' | awk 'NF' | awk '!seen[$0]++'
}

# Additive extraction of failing-test identifier lines (XCTest + swift-testing).
failure_lines() {
  local log="$1"
  {
    grep -E "Test Case '.*' failed" "$log"
    grep -E "✘ Test .* failed" "$log"
    grep -E "✘ Suite .* failed" "$log"
  } 2> /dev/null | sed 's/^[[:space:]]*//' | awk '!seen[$0]++'
}

# Extract the XCTest aggregate failure count ("with N failures") if emitted.
# Prints nothing when the tool emitted no such line.
xctest_failure_count() {
  local log="$1"
  grep -E "Executed [0-9]+ tests?," "$log" 2> /dev/null | tail -1 \
    | sed -nE 's/.*with ([0-9]+) failures.*/\1/p'
}

# Render one test step's section into the block, and record honesty flags.
# Globals set: STEP_PARSE_OK, STEP_FAILURES_PRESENT
render_test_step() {
  local title="$1" cmd_str="$2" log="$3" exit_code="$4" wall_s="$5"
  STEP_PARSE_OK=1
  STEP_FAILURES_PRESENT=0

  emit "--- ${title} ---"
  emit "Command   : ${cmd_str}"
  if [ "$exit_code" = "TOOL_MISSING" ]; then
    emit "STEP FAILED TO RUN: $(cat "$log")"
    emit ""
    STEP_PARSE_OK=0
    STEP_FAILURES_PRESENT=1
    return 0
  fi
  emit "Exit code : ${exit_code}"
  emit "Wall time : ${wall_s} s"

  local summaries
  summaries="$(summary_lines "$log")"
  if [ -z "$summaries" ]; then
    STEP_PARSE_OK=0
    STEP_FAILURES_PRESENT=1
    emit "PARSE FAILED — raw output follows (last ${RAW_TAIL_LINES} lines):"
    tail -n "$RAW_TAIL_LINES" "$log" >> "$BLOCK"
    emit ""
    return 0
  fi

  emit "Tool summary (verbatim):"
  printf '%s\n' "$summaries" | sed 's/^/  /' >> "$BLOCK"

  local fail_count fails
  fail_count="$(xctest_failure_count "$log")"
  fails="$(failure_lines "$log")"

  if { [ -n "$fail_count" ] && [ "$fail_count" != "0" ]; } || [ -n "$fails" ] || [ "$exit_code" != "0" ]; then
    STEP_FAILURES_PRESENT=1
    if [ -n "$fails" ]; then
      local n
      n="$(printf '%s\n' "$fails" | grep -c . || true)"
      emit "Failing tests (verbatim, first ${MAX_FAILURES} of ${n}):"
      printf '%s\n' "$fails" | head -n "$MAX_FAILURES" | sed 's/^/  /' >> "$BLOCK"
    else
      emit "Nonzero exit / failure count with no per-test failure lines extracted — raw tail (last ${RAW_TAIL_LINES} lines):"
      tail -n "$RAW_TAIL_LINES" "$log" >> "$BLOCK"
    fi
  fi
  emit ""
}

# --- Header ----------------------------------------------------------------------
TIMESTAMP="$(date +%Y-%m-%dT%H:%M:%S%z)"
HOST="$(hostname -s 2> /dev/null || hostname)"
HEAD_SHORT="$(git rev-parse --short HEAD 2> /dev/null || echo 'NO GIT HEAD')"
BRANCH="$(git rev-parse --abbrev-ref HEAD 2> /dev/null || echo 'unknown')"

PORCELAIN="$(git status --porcelain 2> /dev/null || true)"
MODIFIED_N="$(printf '%s\n' "$PORCELAIN" | grep -c '^[^?]' || true)"
UNTRACKED_N="$(printf '%s\n' "$PORCELAIN" | grep -c '^??' || true)"
TOTAL_N="$(printf '%s\n' "$PORCELAIN" | grep -c . || true)"

emit '```'
emit "================ PHOSPHENE CLOSEOUT EVIDENCE ================"
emit "Generated : ${TIMESTAMP}"
emit "Host      : ${HOST}"
emit "Commit    : ${HEAD_SHORT} (branch: ${BRANCH})"
if [ "$TOTAL_N" = "0" ]; then
  emit "Tree      : clean"
else
  emit "Tree      : dirty — ${MODIFIED_N} modified, ${UNTRACKED_N} untracked"
  if [ "$TOTAL_N" -le 15 ]; then
    printf '%s\n' "$PORCELAIN" | sed 's/^/  /' >> "$BLOCK"
  else
    emit "  (${TOTAL_N} paths; first 15:)"
    printf '%s\n' "$PORCELAIN" | head -15 | sed 's/^/  /' >> "$BLOCK"
  fi
fi
emit ""

# --- Step 1: Engine tests (SPM) -----------------------------------------------------
ENGINE_LOG="$TMP_DIR/engine_tests.log"
ENGINE_CMD_STR="swift test --package-path PhospheneEngine"
t0=$SECONDS
ENGINE_EXIT="$(run_step "$ENGINE_LOG" swift test --package-path PhospheneEngine)"
ENGINE_WALL=$((SECONDS - t0))
render_test_step "Step 1: Engine tests (PhospheneEngine SPM)" "$ENGINE_CMD_STR" "$ENGINE_LOG" "$ENGINE_EXIT" "$ENGINE_WALL"
ENGINE_PARSE_OK=$STEP_PARSE_OK
ENGINE_FAILS=$STEP_FAILURES_PRESENT

# --- Step 2: App tests (xcodebuild) ---------------------------------------------------
APP_LOG="$TMP_DIR/app_tests.log"
APP_CMD_STR="xcodebuild -scheme PhospheneApp -destination 'platform=macOS' test"
t0=$SECONDS
APP_EXIT="$(run_step "$APP_LOG" xcodebuild -scheme PhospheneApp -destination platform=macOS test)"
APP_WALL=$((SECONDS - t0))
render_test_step "Step 2: App tests (PhospheneApp xcodebuild)" "$APP_CMD_STR" "$APP_LOG" "$APP_EXIT" "$APP_WALL"
APP_PARSE_OK=$STEP_PARSE_OK
APP_FAILS=$STEP_FAILURES_PRESENT

# --- Step 3: SwiftLint ---------------------------------------------------------------
LINT_LOG="$TMP_DIR/swiftlint.log"
LINT_CMD_STR="swiftlint lint --strict --config .swiftlint.yml"
t0=$SECONDS
LINT_EXIT="$(run_step "$LINT_LOG" swiftlint lint --strict --config .swiftlint.yml)"
LINT_WALL=$((SECONDS - t0))

LINT_PARSE_OK=1
LINT_FAILS=0
emit "--- Step 3: SwiftLint ---"
emit "Command   : ${LINT_CMD_STR}"
if [ "$LINT_EXIT" = "TOOL_MISSING" ]; then
  emit "STEP FAILED TO RUN: $(cat "$LINT_LOG")"
  LINT_PARSE_OK=0
  LINT_FAILS=1
else
  emit "Exit code : ${LINT_EXIT}"
  emit "Wall time : ${LINT_WALL} s"
  LINT_SUMMARY="$(grep -E 'Done linting! Found [0-9]+ violation' "$LINT_LOG" 2> /dev/null | tail -1)"
  if [ -z "$LINT_SUMMARY" ]; then
    LINT_PARSE_OK=0
    LINT_FAILS=1
    emit "PARSE FAILED — raw output follows (last ${RAW_TAIL_LINES} lines):"
    tail -n "$RAW_TAIL_LINES" "$LINT_LOG" >> "$BLOCK"
  else
    emit "Tool summary (verbatim):"
    emit "  ${LINT_SUMMARY}"
    LINT_VIOLATIONS="$(printf '%s\n' "$LINT_SUMMARY" | sed -nE 's/.*Found ([0-9]+) violation.*/\1/p')"
    if [ "$LINT_EXIT" != "0" ] || { [ -n "$LINT_VIOLATIONS" ] && [ "$LINT_VIOLATIONS" != "0" ]; }; then
      LINT_FAILS=1
      emit "Violations (verbatim, first ${MAX_FAILURES}):"
      grep -E '(warning|error):' "$LINT_LOG" 2> /dev/null | head -n "$MAX_FAILURES" | sed 's/^/  /' >> "$BLOCK"
    fi
  fi
fi
emit ""

# --- Step 4: Doc gates (DocIntegrityTests — rotation / budget / index, DOC.6) --------
DOC_LOG="$TMP_DIR/doc_gates.log"
DOC_CMD_STR="swift test --package-path PhospheneEngine --filter DocIntegrityTests"
t0=$SECONDS
DOC_EXIT="$(run_step "$DOC_LOG" swift test --package-path PhospheneEngine --filter DocIntegrityTests)"
DOC_WALL=$((SECONDS - t0))
render_test_step "Step 4: Doc gates (DocIntegrityTests)" "$DOC_CMD_STR" "$DOC_LOG" "$DOC_EXIT" "$DOC_WALL"
DOC_PARSE_OK=$STEP_PARSE_OK
DOC_FAILS=$STEP_FAILURES_PRESENT

# --- Step 5: Comparison sheet (QG.2 — canonical §3 artifact for preset increments) ---
# If a RENDER_VISUAL=1 session produced a compare_render.sh sheet, surface its path
# so preset closeouts cite the side-by-side sheet, not a bare contact sheet. Absence
# is normal for non-preset increments — reported as "none", never fatal.
emit "--- Step 5: Comparison sheet (compare_render.sh) ---"
COMPARE_SHEET=""
if [ -d /tmp/phosphene_visual ]; then
  COMPARE_SHEET="$(find /tmp/phosphene_visual -maxdepth 2 -type f -name '*_compare.png' 2> /dev/null \
    | sort | tail -1)"
fi
if [ -n "$COMPARE_SHEET" ]; then
  emit "Sheet     : ${COMPARE_SHEET}"
else
  emit "Sheet     : none (no compare_render.sh output this session)"
fi
emit ""

# --- Step 6: Coupling report (QG.3 — attached to preset closeouts, NEVER asserted) ---
# The audio-visual coupling baseline is a REPORT with a WARNING-tier review flag, not a
# cert gate (D-182/D-183): surfaced for preset increments and read alongside the M7 seat,
# never a pass/fail. A REVIEW flag means "coupling not measured as present," not "bad".
# The real multi-pass sweep is expensive (PHOSPHENE_COUPLING=1, ~130 s), so this step
# points at the standing baseline + the VERDICT regeneration command; it never runs the
# sweep and never affects this evidence block's verdict.
emit "--- Step 6: Coupling report (QG.3, report-only + QG.3.2 warning tier) ---"
COUPLING_BASELINE="docs/diagnostics/QG3_COUPLING_BASELINE.md"
if [ -f "$COUPLING_BASELINE" ]; then
  emit "Baseline  : ${COUPLING_BASELINE} (report-only, D-182/D-183 — warning tier, never a cert gate)"
  emit "Verdict   : PHOSPHENE_COUPLING=1 swift test --package-path PhospheneEngine --filter CouplingReportTests"
  emit "            (prints the per-preset VERDICT block: ok / REVIEW; informs, does not fail cert)"
else
  emit "Baseline  : ${COUPLING_BASELINE} not found"
fi
emit ""

# --- Footer -----------------------------------------------------------------------
emit "--- Footer ---"
emit "Exit codes: engine=${ENGINE_EXIT} app=${APP_EXIT} swiftlint=${LINT_EXIT} docgates=${DOC_EXIT}"
if [ "$ENGINE_EXIT" = "0" ] && [ "$APP_EXIT" = "0" ] && [ "$LINT_EXIT" = "0" ] && [ "$DOC_EXIT" = "0" ] \
  && [ "$ENGINE_PARSE_OK" = "1" ] && [ "$APP_PARSE_OK" = "1" ] && [ "$LINT_PARSE_OK" = "1" ] && [ "$DOC_PARSE_OK" = "1" ] \
  && [ "$ENGINE_FAILS" = "0" ] && [ "$APP_FAILS" = "0" ] && [ "$LINT_FAILS" = "0" ] && [ "$DOC_FAILS" = "0" ]; then
  emit "EVIDENCE: ALL GREEN"
else
  emit "EVIDENCE: FAILURES PRESENT (see above)"
fi
emit "=============================================================="
emit '```'

# --- Emit: file copy first, then stdout from the same bytes ------------------------
cp "$BLOCK" "$EVIDENCE_FILE"
cat "$EVIDENCE_FILE"

# The script's own exit code reflects "evidence gathered", not pass/fail —
# the verdict line above carries the truth.
exit 0
