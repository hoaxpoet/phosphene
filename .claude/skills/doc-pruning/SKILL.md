---
name: doc-pruning
description: Invoke when running a documentation pruning pass (RB.3 convention) — every tenth increment or every two weeks, whichever fires first — or when CLAUDE.md approaches its token cap, or when adding an always-loaded rule. Canonical home of the pruning procedure and the D-161 ratchet (from CLAUDE.md at DOC.9).
---

# Documentation Pruning Pass (RB.3)

The pass is its own increment with its own closeout report (invoke the `closeout` skill) and does not require per-entry sign-off — borderline calls go through the standard stop-and-report rule. Rotation tooling: `Scripts/rotate_docs.sh` (DOC.6). Integrity gates: `DocIntegrityTests` (D-continuity, citation resolution, token cap, skill integrity).

## The five passes

1. **Failed Approaches:** for each entry, ask "would this rule prevent a bug today?" If no → `docs/HISTORICAL_DEAD_ENDS.md`.
2. **Decisions:** each entry whose increment shipped and is no longer cited by another active decision → `docs/DECISIONS_HISTORY.md`.
3. **CLAUDE.md sections:** for each section, ask "did the last 10 increments need this?" If no → move to a handbook (`docs/ARCHITECTURE.md`, `docs/SHADER_CRAFT.md`, `docs/UX_SPEC.md`, `docs/RUNBOOK.md`) or a skill (`.claude/skills/`).
4. **Current Status:** trim to the last 10 increments; older entries live in `ENGINEERING_PLAN.md` and `git log`.
5. **Engineering plan:** completed-increment narratives older than two weeks → `docs/ENGINEERING_PLAN_HISTORY.md`; headers stay as the status record.

## Skill hygiene (added at DOC.9)

6. **Skills:** for each `.claude/skills/*/SKILL.md`, verify every doc pointer still resolves and no content has drifted from its authoritative source. Skills are canonical for what they own (closeout protocol, defect protocol, this procedure, audio data hierarchy); they must remain *pointers* for what handbooks own. Duplicated prose between a skill and a handbook is a bug — pick one home.

## Rulebook ratchet (D-161)

1. **Token budget:** CLAUDE.md ≤ 7,000 estimated tokens (`wc -w` × 1.35), gated by `DocIntegrityTests`. Adding above the cap requires demoting or retiring equal mass in the same commit — one-in-one-out.
2. **Admission test:** a new always-loaded rule must name the specific mistake it prevents AND why no deterministic gate can express it. Failing either → handbook, session checklist, skill, or gate. Skills are the preferred demotion target for increment-type-scoped rules (loaded only when the matching work happens).
3. **Violated twice → mechanize:** the second documented violation of a prose rule converts it — the fix increment ships the gate and demotes the prose to a pointer.

Pruning is the counterweight to "durable learnings stay in docs" — skip it and the pre-DOC.3 doc-mass problem returns. Bloat directly degrades session quality by consuming token budget.
