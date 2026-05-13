# Doc Refactor Plan — 2026-05-13

**Status:** proposal pending Matt sign-off. No mechanical moves land until the structure + borderline calls below are confirmed.

---

## TL;DR

The doc mass — CLAUDE.md (1,240 lines), DECISIONS.md (3,396 lines, 122 entries), Failed Approaches (58 entries inside CLAUDE.md), plus the Module Map and Current Status changelog inside CLAUDE.md — has crossed the threshold where doc-sync overhead is hurting development quality. The fix is a one-time three-layer refactor (active operating doc / topical handbooks / historical reference) plus a recurring pruning step in the Increment Completion Protocol so accumulation has a counterweight. This plan produces the three artifacts you sign off on before mechanical moves start.

---

## The diagnosis

Three accumulation patterns are working simultaneously and have no counterweight:

1. **Increment Completion Protocol mandates a CLAUDE.md update on every increment.** This is correct as a "durable learnings stay in docs" rule, but there is no "every N increments, prune stale entries" counterpart. Result: CLAUDE.md grows monotonically.

2. **Failed Approaches and Decisions accumulate by addition only.** Entries get amended in place (D-103 has a same-day amendment block; D-115 has two; #17 has an in-line "AMENDED" annotation) but never retired. Stale and active entries sit at the same priority.

3. **Module Map and GPU Contract are mirroring code structure inside CLAUDE.md.** ~400 lines of CLAUDE.md describe per-file behavior that is better discovered by reading the code. When the code changes, the mirror has to be hand-updated. This is the highest-overhead, lowest-value content in CLAUDE.md.

The cost shows up as: doc-sync sections of increment closeouts now rival code-change sections in size; planning sessions cite docs that conflict with each other (Phase MD bloc); load-bearing rules sit next to dead-API trivia in the same numbered list, reducing the effective signal of every entry.

---

## Proposed structure (three layers)

| Layer | Purpose | Read frequency | Files |
|---|---|---|---|
| **Active** | What every session needs at the top of context. Bedrock rules + active operating principles. | Every session | `CLAUDE.md` (slim, ~500 lines) |
| **Handbook** | Topical reference. Read when working on that topic. | When working on the topic | `docs/ARCHITECTURE.md` (existing, expanded) · `docs/SHADER_CRAFT.md` (existing, expanded) · `docs/UX_SPEC.md` (existing) · `docs/RUNBOOK.md` (existing, expanded) · `docs/MILKDROP_ARCHITECTURE.md` (existing) |
| **Historical** | Institutional memory. Read rarely, mostly for "did we already try this?" | When investigating | `docs/DECISIONS.md` (pruned to ~60 active entries) · `docs/DECISIONS_HISTORY.md` (new — retired + superseded) · `docs/HISTORICAL_DEAD_ENDS.md` (new — dead APIs from Failed Approaches) |

**Files that stay where they are:** `docs/PRODUCT_SPEC.md`, `docs/ENGINEERING_PLAN.md`, `docs/QUALITY/*`, `docs/presets/*`, `docs/VISUAL_REFERENCES/*`, `docs/diagnostics/*`.

---

## CLAUDE.md target shape (proposed)

Current section list with proposed disposition:

| Current section | Lines | Disposition | Notes |
|---|---:|---|---|
| What This Is | 8 | Keep | |
| Build & Test | 15 | Keep | |
| Increment Completion Protocol | 37 | Keep + add pruning step | See §Pruning rule below |
| Defect Handling Protocol | 40 | Keep | |
| **Module Map** | **224** | **Move to `docs/ARCHITECTURE.md`** | Currently 54% of the doc bloat. Code is the authoritative reference. |
| Audio Data Hierarchy | 26 | Keep | Bedrock — every audio session needs this |
| Proven Audio Analysis Tuning | 59 | Move to `docs/ARCHITECTURE.md` | Reference material, not an operating rule |
| Key Types | 86 | Move to `docs/ARCHITECTURE.md` | Reference material |
| GPU Contract Details | 172 | Move to `docs/ARCHITECTURE.md` | Reference material — preset authors read this once per family |
| Preset Metadata Format | 49 | Move to `docs/SHADER_CRAFT.md` | Preset authoring lives there |
| Visual Quality Floor | 35 | Keep pointer; full text already in `SHADER_CRAFT.md` | Currently duplicated |
| Session Preparation Pipeline | 16 | Move to `docs/ARCHITECTURE.md` | |
| UX Contract | 44 | Keep pointer; full text already in `UX_SPEC.md` | Currently duplicated |
| ML Inference | 20 | Move to `docs/ARCHITECTURE.md` | |
| Code Style | 18 | Keep | Active rules |
| **Failed Approaches** | **87** | **Split** | See §Failed Approaches inventory below |
| Authoring Discipline | 36 | Keep + generalize | See note below |
| **What NOT To Do** | **62** | **Slim** | Many entries duplicate Failed Approaches; consolidate |
| **Current Status** | **190** | **Replace with 1-paragraph pointer** | Engineering plan + `git log` are authoritative; CLAUDE.md should not be a changelog |
| Linked Frameworks | 4 | Keep | |
| Development Constraints | 7 | Keep | |

**Target CLAUDE.md size:** ~500 lines (down from 1,240). All bedrock rules preserved; all reference material moved to handbooks.

**Authoring Discipline generalization:** add one paragraph that the rules apply to project-level commitments too (closes the gap identified in the prior audit — the Phase MD strategy bloc violated rules that were authored at the per-preset scope).

---

## Failed Approaches inventory (58 entries → ~30 active + handbook layer + graveyard)

Categorization from the prior audit. Counts are exact; specific entries listed where the call is non-obvious.

| Disposition | Count | Entries | Destination |
|---|---:|---|---|
| **Keep verbatim (bedrock)** | ~30 | #1–4, #17 (amended), #20–34, #48, #49, #52–58 — the load-bearing rules that have prevented real bugs | CLAUDE.md (numbering re-flowed) |
| **Re-verify (stale tech claims)** | 4 | #5 BlackHole · #7 ScreenCaptureKit audio-only · #12 HTDemucs CoreML · #13 End-to-end CoreML audio | CLAUDE.md (after re-test) OR `HISTORICAL_DEAD_ENDS.md` (if still dead) |
| **Move to graveyard** | 5 | #6 Web Audio API · #8 AcousticBrainz · #9 MPNowPlayingInfoCenter · #10 Spotify Audio Features deprecated · #19 Unweighted chroma | `HISTORICAL_DEAD_ENDS.md` |
| **Relocate to handbook** | 6 | #41 SwiftUI a11y → `UX_SPEC.md` · #42, #43 fbm8 calibration → `SHADER_CRAFT.md` · #44 Metal type-name shadowing → `SHADER_CRAFT.md` · #45, #46, #47 Spotify API → `RUNBOOK.md` · #50, #51 DSP.1 IOI lessons → consolidate as one entry | Topic-specific docs |
| **Scope-clarify in place** | 4 | #4 beat-as-accent (clarify "dominant motion driver" vs all beat coupling) · #23 architecture deformation (clarify "scene architecture") · #33 free-running sin(time) (add ambient-motion exception) · #39 visual references required (scope to certified presets) | CLAUDE.md (with revised text) |
| **Add as new entry** | 2 | D-120 reversion post-mortem · "Filing strategy decisions without empirical validation" | CLAUDE.md (Authoring Discipline section) |

Net effect: Failed Approaches in CLAUDE.md shrinks from 58 to ~30 active strategic rules. Granular gotchas live next to the code they apply to; dead APIs live in their own file.

---

## Decisions inventory (122 entries → ~60 active in DECISIONS.md + history file)

| Disposition | Count | Entries | Destination |
|---|---:|---|---|
| **Keep active** | ~60 | The load-bearing bedrock — D-001 through D-079, D-090, D-091, D-092–D-101, the active LM and Arachne decisions | `DECISIONS.md` |
| **Phase MD bloc — flag for revisit** | 20 | D-103 through D-122 | `DECISIONS.md` with a clear "REVISIT" banner; see prior audit |
| **Mark reverted** | 1 | D-120 (already reverted in commit `0981ca4f` but DECISIONS.md text doesn't say so) | `DECISIONS.md` annotation |
| **Move to history** | ~30 | Superseded by amendments (DASH.2 → DASH.7 chain; LM.3 → LM.3.1 → LM.3.2 → LM.4 → LM.4.1 → LM.4.3 → LM.4.4 → LM.4.5 → LM.4.6 → LM.7 amendments) · stale once their increment shipped (V.5/V.6/V.7.x detailed sub-amendments) | `DECISIONS_HISTORY.md` |
| **Re-evaluate** | 4 | D-029 (motion paradigms not composable — straining under staged composition) · D-039 (dHash gate weakening as slot-8 state spreads) · D-058b (undo restores `livePlan` only) · D-074 (diagnostic preset categorical exclusion) | Keep in `DECISIONS.md`; schedule a re-evaluation session each |

Net effect: `DECISIONS.md` becomes ~60 entries of currently-active commitments. Everything that has been superseded or whose increment is long-shipped moves to `DECISIONS_HISTORY.md`. Both files stay searchable; the active file becomes scannable.

---

## Pruning rule proposal

Concrete addition to the **Increment Completion Protocol** (CLAUDE.md):

> **Pruning pass.** Every tenth increment (or every two weeks, whichever fires first), run a pruning pass against `CLAUDE.md`, `DECISIONS.md`, and Failed Approaches:
>
> 1. **Failed Approaches:** for each entry, ask "would this rule prevent a bug today?" If no, move to `HISTORICAL_DEAD_ENDS.md`.
> 2. **Decisions:** for each entry whose increment has shipped and is no longer cited by another active decision, move to `DECISIONS_HISTORY.md`.
> 3. **CLAUDE.md sections:** for each section, ask "did the last 10 increments need this?" If no, consider moving to a handbook.
> 4. **Current Status section:** trim to the last 10 increments; older entries are in `ENGINEERING_PLAN.md` and `git log` already.
>
> The pruning pass is its own increment with its own closeout report. It does not require Matt sign-off per-entry — borderline calls go through the standard "stop and report" rule.

This adds ~one increment of overhead per ten, which is the right ratio for keeping the docs in working order without becoming a meeting tax.

---

## Execution sequence

The refactor is one planning increment (this doc) plus four mechanical increments. Each lands in isolation; each is small and reversible.

| Increment | Scope | Estimated size |
|---|---|---|
| **DOC.0** (this doc) | Inventory + structure proposal + pruning rule | 1 session |
| **DOC.1** | Set up new files: create `HISTORICAL_DEAD_ENDS.md`, `DECISIONS_HISTORY.md` (empty); add pruning rule to Increment Completion Protocol; no content moves yet | 30 min |
| **DOC.2** | Move CLAUDE.md reference material (Module Map, GPU Contract, Key Types, ML Inference, Session Prep, Audio Tuning) into `ARCHITECTURE.md`; collapse duplicated UX Contract + Visual Quality Floor to pointers | 1 session |
| **DOC.3** | Failed Approaches refactor: re-verify the 4 stale tech claims; move 5 to graveyard; relocate 6 to handbooks; scope-clarify 4 in place; add 2 new entries | 1 session |
| **DOC.4** | DECISIONS refactor: split active vs history; annotate D-120 as reverted; add REVISIT banner to Phase MD bloc; mark 4 for re-evaluation | 1 session |

**Total: ~4 focused sessions** to land the refactor. After DOC.1 the pruning rule is in effect for all subsequent increments.

DOC.2 / DOC.3 / DOC.4 are independent and could be parallelized or reordered. Recommended order is as listed because DOC.2 is the largest size-win and lowest judgment risk.

---

## Borderline calls — your sign-off needed

These are the judgment items where I'd rather have your call before mechanical moves start.

1. **Naming.** I proposed `HISTORICAL_DEAD_ENDS.md` and `DECISIONS_HISTORY.md`. Alternatives: `RETIRED.md`, `ARCHIVE.md`, `LESSONS_ARCHIVE.md`. Your call.

2. **"Current Status" treatment.** I proposed replacing the ~190-line changelog in CLAUDE.md with a one-paragraph pointer to `ENGINEERING_PLAN.md` + `git log`. Alternative: keep the most recent 5 increments (~50 lines) and rotate older entries into ENGINEERING_PLAN. I prefer the pointer; the changelog has become a doc-sync trap.

3. **Per-preset detail in Module Map.** The Module Map currently carries multi-paragraph behavioural descriptions for each preset (Arachne's WORLD/COMPOSITE staged composition; LM's eight calibration rounds). Two options: (a) move all of it to `ARCHITECTURE.md`; (b) split — short architectural notes stay in `ARCHITECTURE.md`, preset-specific design history moves to `docs/presets/<preset>_DESIGN.md` (which already exists for some presets). I lean (b) — preset design docs already exist for LM, Arachne, Aurora Veil, Crystalline Cavern.

4. **Phase MD bloc treatment.** The prior audit recommended revisiting D-103 through D-122. Two options: (a) leave them active in DECISIONS.md with a REVISIT banner pending the empirical evidence from the first inspired-by preset (matches my recommendation); (b) move them all to DECISIONS_HISTORY.md immediately and re-derive when Phase MD restarts. (a) is safer (preserves the strategic thinking); (b) is cleaner (forces a fresh decision). I lean (a).

5. **Re-verification scope for stale tech (#5, #7, #12, #13).** Re-testing requires actually running each system. I can either: (a) re-verify all four in DOC.3 (~half-session of testing); (b) mark them "unverified — assume historical" and leave to a future test session; (c) skip re-verification and move them all to graveyard now (treat as historical). I lean (a) — half-session is cheap and the answer affects whether the rules stay active.

6. **Authoring Discipline generalization wording.** I'd add a paragraph stating the discipline rules apply to project-level strategic commitments, not just preset-authoring sessions. This closes the gap that produced the Phase MD bloc. Your call on the exact wording.

---

## Out of scope (explicitly not touched in this refactor)

- `docs/PRODUCT_SPEC.md` — product vision, stable.
- `docs/ENGINEERING_PLAN.md` — roadmap, separately maintained.
- `docs/QUALITY/*` — defect taxonomy + KNOWN_ISSUES tracker, separately maintained.
- `docs/presets/*` — per-preset design docs, separately maintained.
- `docs/VISUAL_REFERENCES/*` — reference image library.
- Any code changes.
- Any test changes.
- The Increment Completion Protocol itself, beyond adding the pruning step.

---

## What this refactor does not solve

- **The Phase MD bloc's underlying strategy questions.** The refactor only annotates them as REVISIT; it doesn't resolve them. Those need a separate session that examines the empirical evidence from the first inspired-by preset attempt.
- **Future drift.** The pruning rule helps but doesn't eliminate the accumulation tendency. If pruning passes get skipped, the docs will drift back. The protocol addition makes the pruning step mandatory, but enforcement is on Claude (me) and on you to call it out if a pruning increment is overdue.
- **The 14 production-but-uncertified presets.** Phase G-uplift is independent.

---

## Sign-off needed before DOC.1 starts

1. Approve the three-layer structure (Active / Handbook / Historical) and file naming.
2. Pick the six borderline calls above (or substitute alternatives).
3. Confirm the four-increment execution sequence + ordering.

On sign-off, I'll start DOC.1 (set up new files + add pruning rule, no content moves). Each subsequent DOC.x increment lands as its own session with its own closeout.
