---
name: closeout
description: Increment completion protocol for Phosphene. Invoke at the END of every increment — engine, preset, UX, docs, infrastructure — before committing, and whenever writing a closeout report. Also invoke when about to push, commit, or claim an increment is done.
---

# Increment Completion Protocol

Every increment ends the same way. Skipping a step turns a finished increment into one that "looked finished in chat" and rots within a session or two. This skill is the canonical home of the protocol (moved from CLAUDE.md at DOC.9).

## Closeout report — 8 parts, in order

1. **Files changed** — concrete paths, grouped new vs. edited.
2. **Tests run** — run `Scripts/closeout_evidence.sh` and paste its evidence block **verbatim**. Prose may annotate anomalies below the block (known timing squeezes, parallel-session tree noise) but never replaces or summarizes it. A closeout without the block, or with a block whose commit hash does not match the closeout's commit, is incomplete.
3. **Visual harness output** — when the increment is preset-facing or visually observable, include the `RENDER_VISUAL=1` per-stage / contact-sheet output paths or attach key frames. State explicitly when a change is not visually verifiable.
4. **Documentation updates** — list every doc file touched.
5. **Capability registry updates** — cite the rows changed (see below).
6. **Engineering plan updates** — cite the increment ID (see below).
7. **Known risks and follow-ups** — bounded list: what could break, what was deferred, next recommended increment.
8. **Git status** — branch, commit hash(es), clean/dirty, files staged outside the increment's scope.

## Mandatory doc updates

**`docs/ENGINEERING_PLAN.md`** — update whenever an increment is completed, split, renamed, deferred, or discovered to require prerequisite work. Each increment ID maps to a row stating done-when and whether it's done. If the plan and the code disagree, that is a bug in the plan.

**`docs/ENGINE/RENDER_CAPABILITY_REGISTRY.md`** — update whenever renderer, visual harness, certification pipeline, shader infrastructure, or preset architecture capabilities change. New capability → new row. Promotion (Missing → Partial → Supported) → flip status and cite files. New blocker → add it. Update the preset-implications section: what's now buildable, what's still blocked.

**Durable learnings stay in docs.** Anything a future session needs — a non-obvious tuning constant, a renderer convention, a preset-author rule — goes into CLAUDE.md, `docs/DECISIONS.md`, `docs/SHADER_CRAFT.md`, the relevant docs/ subtree, or memory. If the only record of "we learned X" is a paragraph in chat, future Claude will not have it.

## Commit and push rules

- Commit locally to `main` after tests and docs are complete. Format: `[<increment-id>] <component>: <description>`. Prefer multiple small commits per increment — keeps `git bisect` useful.
- **Do not push without Matt's explicit "yes, push" in chat.** This applies even when the work is clearly green and clearly Matt's request — pushing is a separate decision.

## Stop and report instead of forging ahead when

- tests fail (engine or app), including pre-existing flakes the increment touched;
- preset acceptance gates or rubric checks fail;
- implementing as written would require broader architectural changes than authorized — pause, surface scope, get approval;
- documentation conflicts with code that just changed and resolving requires judgement outside the increment's scope;
- the commit would include unrelated files — back them out or surface for approval first.

When in doubt, write a short status update and ask. The cost of pausing is low; the cost of an increment that silently expanded scope, partially landed, or skipped a doc update is high.
