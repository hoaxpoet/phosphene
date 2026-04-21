---
name: DECISIONS.md numbering
description: Tracks the next available decision number to prevent duplicate D-0XX assignments
type: project
---

Next decision is D-038. D-037 was the preset acceptance checklist structural invariants (Increment 5.2, 2026-04-20). Always grep `docs/DECISIONS.md` for `## D-0` before assigning a new number.

**Why:** Prior increments have occasionally had to renumber after collisions.

**How to apply:** Before adding a new DECISIONS.md entry, run `grep "## D-0" docs/DECISIONS.md` and use the next sequential number.
