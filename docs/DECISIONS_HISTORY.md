# Decisions History

This file holds decisions that have been **superseded by amendments** or **whose increment shipped long ago and is no longer cited by an active decision**. Decisions that remain load-bearing — referenced by code, by another active decision, or by an open follow-up — stay in `docs/DECISIONS.md`.

## Why this file exists

`docs/DECISIONS.md` grew to 122 entries (3,396 lines). Several decision chains involve multiple amendments to the same decision (e.g. the DASH series: DASH.2 → DASH.2.1 → DASH.7 → DASH.7.1 → DASH.7.2; the LM series: LM.3 → LM.3.1 → LM.3.2 → LM.4 → LM.4.1 → LM.4.3 → LM.4.4 → LM.4.5 → LM.4.6 → LM.7). The terminal decision in each chain remains load-bearing; the intermediate amendments are institutional memory worth preserving but should not crowd the active-decisions list.

The cut is:

- **Active:** the decision is currently referenced by code, by another active decision, or by an open follow-up.
- **History:** the decision has been superseded by a newer decision, or its increment shipped and nothing currently references it.

Both lists stay fully searchable via `grep`. The active list becomes scannable.

## Population

This file is populated by **DOC.4** (Decisions refactor). It is empty in DOC.1.

Entries land below this divider preserving their original D-NNN number for cross-reference with git history. A one-line "Superseded by:" or "Shipped in:" header on each entry records why it moved.

---

<!-- Entries land here. Format mirrors docs/DECISIONS.md: ## D-NNN header + body. -->
