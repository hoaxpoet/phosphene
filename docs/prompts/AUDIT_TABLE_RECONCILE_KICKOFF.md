# Kickoff — CODE_AUDIT status-row reconcile sweep (approved 2026-06-18)

**Run this in a FRESH session** (Matt's instruction — a clean read avoids the stale-context drift that caused the misses below).

## Why this exists

On 2026-06-18, three audit-table status rows were found stale — claiming "pending / awaiting / after" while the **authoritative bug entry said RESOLVED**:
- **G1 / CLEAN.1.5** — validated 2026-06-17, but the EP CLEAN.1.7 bullet still said "only open gate, this week."
- **BUG-053 / CLEAN.3.7-fix** — Resolved + validated **2026-06-16** (bug entry + EP bullet both correct), but the `CODE_AUDIT` 3.7-fix row still said "pending Matt's manual check."
- **BUG-039 / CLEAN.3.6** — was genuinely open; resolved 2026-06-18.

Root cause: **the `CODE_AUDIT_2026-06-13.md` rows and older `ENGINEERING_PLAN` §Recently-Completed narrative bullets are hand-maintained summaries that lag the authoritative `KNOWN_ISSUES` bug entries.** A validation updates the bug entry but not always the summary row. Read [[feedback_status_from_authoritative_surface]] first.

## Task

Cross-check **every status claim** in `docs/diagnostics/CODE_AUDIT_2026-06-13.md` (all phase tables + the Part-A/B gap rows) against the authoritative source, and reconcile drift in one pass.

**Method (per row that cites a `BUG-NNN`, a `[GAP-N]`, or a "pending/awaiting/after/open/DONE/✅" status):**
1. `grep -n "### BUG-NNN" docs/QUALITY/KNOWN_ISSUES.md` → read that entry's `**Status:**` line. That (plus an EP `✅ … RESOLVED` bullet) is status-of-record.
2. If the audit row disagrees, **edit the audit row to match the bug entry**, citing it (e.g. "RESOLVED <date> — see KNOWN_ISSUES §BUG-NNN").
3. Also scan `ENGINEERING_PLAN.md` §Recently Completed for the same stale-"pending" drift on resolved items.
4. **Do NOT change any bug's actual resolution** — manual-gate sign-offs are Matt's. Only reconcile the lagging *summary* surfaces to match the authoritative entries. If a real discrepancy can't be resolved from the artifacts (e.g. the bug entry itself is ambiguous), **flag it for Matt — do not guess.**

**Already reconciled this session — do NOT re-flag:** G1 (`f24650a`), BUG-039 + BUG-053 (`4d20103`). Start from there.

## Scope guard
Doc-only (audit doc + EP; memory if a note is stale). No code, no test changes, no bug-status changes. This is the duplication/drift class the audit itself warns about — reconcile, don't rewrite.

## Closeout
Run `Scripts/closeout_evidence.sh` (worktree engine-fixture failures are the known environmental class — confirm none are in files you touched). `swift test --package-path PhospheneEngine --filter DocIntegrityTests` green. Update the audit doc's own status + a `RELEASE_NOTES_DEV.md` entry listing each row reconciled (was-X / entry-said-Y / fixed). Commit `[DOC] reconcile CODE_AUDIT status rows vs authoritative KNOWN_ISSUES entries`. **Do not push without Matt's "yes, push."**

## Output
A short report: each reconciled row as `audit-said-X → bug-entry-said-Y → fixed`, plus any genuine discrepancies flagged for Matt.
