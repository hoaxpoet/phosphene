#!/usr/bin/env bash
# rotate_docs.sh
#
# DOC.6 deterministic doc rotation (D-162). Mechanizes the pruning-pass moves
# that the prose convention (CLAUDE.md §Increment Completion Protocol) failed
# to execute twice (D-161 rule 3: violated twice → mechanize). Three rotations,
# each idempotent — a second run on a rotated tree is a no-op:
#
#   (a) ENGINEERING_PLAN.md §Recently Completed — every `### ` entry whose
#       header carries ✅ or ⏳ and a parseable (YYYY-MM-DD) date older than
#       14 days has its BODY moved to the top of ENGINEERING_PLAN_HISTORY.md
#       §Recently Completed (header + body land there; the header line alone
#       stays in the plan — the RB.3 convention). Date = the LAST
#       YYYY-MM-DD occurrence in the header line (ranges use the end date).
#   (b) KNOWN_ISSUES.md §Resolved (recent) — every `### BUG…` entry whose
#       header date is older than 14 days moves WHOLE (header included) to
#       docs/QUALITY/KNOWN_ISSUES_HISTORY.md, newest-first. §Open and
#       §Pre-existing Flakes are never touched.
#   (c) RELEASE_NOTES_DEV.md — every `## [dev-YYYY-MM-DD-x]` entry from a
#       month before the current month moves to docs/RELEASE_NOTES_DEV_YYYY-MM.md
#       (one file per month, order preserved). The active file keeps its
#       preamble + current-month entries.
#
# Honesty contract (matches closeout_evidence.sh):
#   - Moves are VERBATIM. Nothing is summarized, rewritten, or deleted.
#   - Entries whose header date cannot be parsed are NEVER moved — they are
#     listed on stderr for manual triage. The script does not guess.
#   - When a rotation finds nothing to move, its files are not touched.
#
# Usage: Scripts/rotate_docs.sh [--dry-run]
#   --dry-run  print the planned moves and summaries without writing anything.
#
# PHOSPHENE_TODAY=YYYY-MM-DD overrides "today" (testing only).

set -euo pipefail

# --- Locate repo root; everything runs from there -----------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    *) echo "rotate_docs: unknown argument '$arg' (only --dry-run is accepted)" >&2; exit 2 ;;
  esac
done

TODAY="${PHOSPHENE_TODAY:-$(date +%Y-%m-%d)}"
if [ -n "${PHOSPHENE_TODAY:-}" ]; then
  CUTOFF="$(date -j -v-14d -f %Y-%m-%d "$PHOSPHENE_TODAY" +%Y-%m-%d)"
else
  CUTOFF="$(date -v-14d +%Y-%m-%d)"
fi
CUR_MONTH="${TODAY%-*}"

EP="docs/ENGINEERING_PLAN.md"
EP_HIST="docs/ENGINEERING_PLAN_HISTORY.md"
KI="docs/QUALITY/KNOWN_ISSUES.md"
KI_HIST="docs/QUALITY/KNOWN_ISSUES_HISTORY.md"
RN="docs/RELEASE_NOTES_DEV.md"

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/rotate_docs.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

kb() { echo "$(( ($(wc -c < "$1") + 512) / 1024 ))"; }

# Print the manual-triage report for one rotation, if any.
report_unparseable() {
  local report="$1" label="$2"
  if [ -s "$report" ]; then
    echo "rotate_docs: ${label} — entries with no parseable header date, NOT moved (manual triage):" >&2
    sed 's/^/  /' "$report" >&2
  fi
}

# Insert the contents of $2 into $1 immediately after the first line matching
# regex $3, with a blank line on each side. Writes the result to $4.
insert_after() {
  local target="$1" insert="$2" anchor="$3" out="$4"
  awk -v ins="$insert" -v anchor="$anchor" '
    { print }
    !done && $0 ~ anchor {
      print ""
      while ((getline l < ins) > 0) print l
      done = 1
    }
  ' "$target" > "$out"
}

# =============================================================================
# (a) ENGINEERING_PLAN.md §Recently Completed
# =============================================================================
EP_MAIN="$TMP_DIR/ep_main.md"
EP_MOVED="$TMP_DIR/ep_moved.md"
EP_REPORT="$TMP_DIR/ep_report.txt"
: > "$EP_MAIN"; : > "$EP_MOVED"; : > "$EP_REPORT"

awk -v cutoff="$CUTOFF" -v MAIN="$EP_MAIN" -v MOVED="$EP_MOVED" -v REPORT="$EP_REPORT" '
  function lastdate(s,    t, d) {
    d = ""; t = s
    while (match(t, /[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/)) {
      d = substr(t, RSTART, RLENGTH); t = substr(t, RSTART + RLENGTH)
    }
    return d
  }
  function flush_entry(    moves) {
    if (header == "") return
    moves = 0
    if (marker && dated != "" && dated < cutoff && bodylines > 0) moves = 1
    if (moves) {
      print header >> MAIN                       # header stays (RB.3 convention)
      printf "%s\n%s", header, body >> MOVED      # header + verbatim body to history
    } else {
      printf "%s\n%s", header, body >> MAIN
      if (bodylines > 0 && dated == "") print header >> REPORT
      else if (bodylines > 0 && !marker && dated != "" && dated < cutoff) print header " [old but no ✅/⏳ marker]" >> REPORT
    }
    header = ""; body = ""; bodylines = 0
  }
  /^## / {
    flush_entry()
    in_rc = ($0 == "## Recently Completed")
    print >> MAIN
    next
  }
  /^### / && in_rc {
    flush_entry()
    header = $0
    marker = (index($0, "✅") > 0 || index($0, "⏳") > 0)
    dated = lastdate($0)
    next
  }
  {
    if (header != "") { body = body $0 "\n"; if ($0 !~ /^[[:space:]]*$/) bodylines++ }
    else print >> MAIN
  }
  END { flush_entry() }
' "$EP"

EP_N="$(grep -c '^### ' "$EP_MOVED" || true)"
report_unparseable "$EP_REPORT" "ENGINEERING_PLAN.md §Recently Completed"
if [ "$EP_N" -gt 0 ]; then
  if [ "$DRY_RUN" = "1" ]; then
    echo "--- (a) ENGINEERING_PLAN.md: would move ${EP_N} entry bodies to ${EP_HIST}:"
    grep '^### ' "$EP_MOVED" | sed 's/^/  /'
  else
    grep -q '^## Recently Completed$' "$EP_HIST" || {
      echo "rotate_docs: ${EP_HIST} has no '## Recently Completed' section — refusing to guess an insertion point" >&2
      exit 1
    }
    BEFORE_KB="$(kb "$EP")"
    insert_after "$EP_HIST" "$EP_MOVED" '^## Recently Completed$' "$TMP_DIR/ep_hist.md"
    mv "$TMP_DIR/ep_hist.md" "$EP_HIST"
    mv "$EP_MAIN" "$EP"
    echo "rotate_docs: (a) ENGINEERING_PLAN.md — moved ${EP_N} entries, ${BEFORE_KB} KB → $(kb "$EP") KB"
  fi
else
  echo "rotate_docs: (a) ENGINEERING_PLAN.md — nothing to move (already rotated)"
fi

# =============================================================================
# (b) KNOWN_ISSUES.md §Resolved (recent)
# =============================================================================
KI_MAIN="$TMP_DIR/ki_main.md"
KI_MOVED="$TMP_DIR/ki_moved.md"
KI_REPORT="$TMP_DIR/ki_report.txt"
: > "$KI_MAIN"; : > "$KI_MOVED"; : > "$KI_REPORT"

awk -v cutoff="$CUTOFF" -v MAIN="$KI_MAIN" -v MOVED="$KI_MOVED" -v REPORT="$KI_REPORT" '
  function lastdate(s,    t, d) {
    d = ""; t = s
    while (match(t, /[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/)) {
      d = substr(t, RSTART, RLENGTH); t = substr(t, RSTART + RLENGTH)
    }
    return d
  }
  function flush_entry() {
    if (header == "") return
    if (dated != "" && dated < cutoff) {
      printf "%s\n%s", header, body >> MOVED      # whole entry, verbatim
    } else {
      printf "%s\n%s", header, body >> MAIN
      if (dated == "") print header >> REPORT
    }
    header = ""; body = ""
  }
  /^## / {
    flush_entry()
    in_res = ($0 == "## Resolved (recent)")
    print >> MAIN
    next
  }
  /^### BUG/ && in_res {
    flush_entry()
    header = $0
    dated = lastdate($0)
    next
  }
  {
    # Sub-headers (### Expected behavior, …) and prose belong to the entry body.
    if (header != "") body = body $0 "\n"
    else print >> MAIN
  }
  END { flush_entry() }
' "$KI"

KI_N="$(grep -c '^### BUG' "$KI_MOVED" || true)"
report_unparseable "$KI_REPORT" "KNOWN_ISSUES.md §Resolved (recent)"
if [ "$KI_N" -gt 0 ]; then
  if [ "$DRY_RUN" = "1" ]; then
    echo "--- (b) KNOWN_ISSUES.md: would move ${KI_N} resolved entries to ${KI_HIST}:"
    grep '^### BUG' "$KI_MOVED" | sed 's/^/  /'
  else
    if [ ! -f "$KI_HIST" ]; then
      cat > "$KI_HIST" << 'PREAMBLE'
# Phosphene — Known Issues History

Resolved entries rotated out of [`KNOWN_ISSUES.md`](KNOWN_ISSUES.md) §Resolved (recent) by `Scripts/rotate_docs.sh` (DOC.6) once their resolution is older than 14 days. Moves are verbatim, newest-first; BUG numbers stay searchable here, and the `DocIntegrityTests` BUG-continuity gate spans both files.

---
PREAMBLE
    fi
    BEFORE_KB="$(kb "$KI")"
    insert_after "$KI_HIST" "$KI_MOVED" '^---$' "$TMP_DIR/ki_hist.md"
    mv "$TMP_DIR/ki_hist.md" "$KI_HIST"
    mv "$KI_MAIN" "$KI"
    echo "rotate_docs: (b) KNOWN_ISSUES.md — moved ${KI_N} entries, ${BEFORE_KB} KB → $(kb "$KI") KB"
  fi
else
  echo "rotate_docs: (b) KNOWN_ISSUES.md — nothing to move (already rotated)"
fi

# =============================================================================
# (c) RELEASE_NOTES_DEV.md monthly rotation
# =============================================================================
RN_MAIN="$TMP_DIR/rn_main.md"
: > "$RN_MAIN"

awk -v cur="$CUR_MONTH" -v MAIN="$RN_MAIN" -v TMP="$TMP_DIR" '
  /^## \[dev-/ {
    month = substr($0, index($0, "[dev-") + 5, 7)    # YYYY-MM
    if (month ~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]$/ && month < cur) out = TMP "/rn_" month ".md"
    else out = MAIN
  }
  { if (out == "") out = MAIN; print >> out }
' "$RN"

RN_MONTHS="$(ls "$TMP_DIR" | sed -n 's/^rn_\([0-9]\{4\}-[0-9]\{2\}\)\.md$/\1/p' | sort)"
if [ -n "$RN_MONTHS" ]; then
  RN_N=0
  for m in $RN_MONTHS; do
    n="$(grep -c '^## \[dev-' "$TMP_DIR/rn_${m}.md" || true)"
    RN_N=$((RN_N + n))
  done
  if [ "$DRY_RUN" = "1" ]; then
    echo "--- (c) RELEASE_NOTES_DEV.md: would move ${RN_N} entries into per-month files:"
    for m in $RN_MONTHS; do
      echo "  docs/RELEASE_NOTES_DEV_${m}.md ← $(grep -c '^## \[dev-' "$TMP_DIR/rn_${m}.md" || true) entries"
    done
  else
    BEFORE_KB="$(kb "$RN")"
    for m in $RN_MONTHS; do
      MONTH_FILE="docs/RELEASE_NOTES_DEV_${m}.md"
      if [ ! -f "$MONTH_FILE" ]; then
        {
          echo "# Phosphene — Developer Release Notes — ${m} (rotated monthly from the active [\`RELEASE_NOTES_DEV.md\`](RELEASE_NOTES_DEV.md) by \`Scripts/rotate_docs.sh\`; entries verbatim, newest-first)"
          echo ""
          echo "---"
        } > "$MONTH_FILE"
      fi
      insert_after "$MONTH_FILE" "$TMP_DIR/rn_${m}.md" '^---$' "$TMP_DIR/rn_month_out.md"
      mv "$TMP_DIR/rn_month_out.md" "$MONTH_FILE"
    done
    # Preamble pointer line, added once.
    if ! grep -q '^Older entries:' "$RN_MAIN"; then
      awk '
        !done && /^---$/ { print "Older entries: `RELEASE_NOTES_DEV_YYYY-MM.md` (one file per month)."; print ""; done = 1 }
        { print }
      ' "$RN_MAIN" > "$TMP_DIR/rn_main2.md"
      mv "$TMP_DIR/rn_main2.md" "$RN_MAIN"
    fi
    mv "$RN_MAIN" "$RN"
    echo "rotate_docs: (c) RELEASE_NOTES_DEV.md — moved ${RN_N} entries ($(echo "$RN_MONTHS" | tr '\n' ' ' | sed 's/ $//')), ${BEFORE_KB} KB → $(kb "$RN") KB"
  fi
else
  echo "rotate_docs: (c) RELEASE_NOTES_DEV.md — nothing to move (already rotated)"
fi

if [ "$DRY_RUN" = "1" ]; then
  echo "rotate_docs: dry run — nothing written"
fi
