---
name: DECISIONS.md numbering
description: Tracks the next available decision number to prevent duplicate D-0XX assignments
type: project
---

Next decision is D-064. D-063 was the V.4 utility library audit + missing materials (mat_velvet, mat_sand_glints, mat_concrete) + §16.2 precompile deferral (2026-04-26). Always grep `docs/DECISIONS.md` for `## D-0` before assigning a new number.

**Why:** Prior increments have occasionally had to renumber after collisions.

**How to apply:** Before adding a new DECISIONS.md entry, run `grep "## D-0" docs/DECISIONS.md` and use the next sequential number.
