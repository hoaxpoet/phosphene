# Session prompt — Phase MD strategy addendum (inspired-by reframe)

Paste the fenced block below into a new Claude Code session. This
session amends Phase MD's strategic framing after Matt's 2026-05-12
post-sign-off review reframed the work as "inspired by" rather than
"derivative of." The base strategy doc (`MILKDROP_STRATEGY.md`) and
ten decisions (D-103 through D-112) stand; this session authors the
addendum that revises the ones the reframe touches.

Pre-session human prerequisites:

1. The MD-strategy series commits are on `origin/main` (verify
   `git log origin/main --oneline | head -20` shows the
   `[MD-strategy]` entries through `145fe66c` + the counsel-gate
   removal commit that follows this prompt's authoring).
2. No new Matt decisions outstanding (the inputs filed below are
   the operative brief for this session).

---

```
Context: Phase MD's initial strategy (docs/MILKDROP_STRATEGY.md,
D-103 through D-112) was authored under a "derivative work" posture:
mechanically transpile .milk → Phosphene .metal, ship MIT-derivative
with attribution. After post-sign-off review on 2026-05-12, Matt
reframed the work as "inspired by" — each Milkdrop-influenced
Phosphene preset is a NEW CREATION honoring an original, not a
mechanical port. The reframe cascades through most of the existing
decisions; this session authors the addendum.

INPUTS FROM MATT'S 2026-05-12 REVIEW (operative brief for this session):

1. Posture reframe. "Inspired by ..." is the operative legal
   framing, not "derivative of." Every Milkdrop-influenced
   Phosphene preset is a new creation that takes inspiration from a
   source preset's concept and aesthetic, implemented from scratch
   on Phosphene's primitives. The transpiler / mechanical-port
   framing is retired.

2. Scale. Initial planning target ~200 inspired-by uplifts (vs
   ~35 in the original plan). At ~2-3 days per preset authored,
   this is a multi-year work stream, not a finite phase.

3. Release model. Phosphene's first release ships when the
   catalog reaches 20 presets (mix of Phosphene-native + Milkdrop-
   inspired — composition TBD by this session). After release,
   ongoing batches at weekly / monthly / quarterly cadence (the
   specific cadence is a release-management decision deferred to
   release planning, not in this session's scope).

4. Notification protocol — DEFERRED. The original strategy's "pre-
   release notification of original designers" idea is retired for
   the pre-community phase. Rationale: in the pre-community phase
   there are no third-party authors yet; notification before we
   have a community ecosystem looks like a checkbox exercise.
   Provenance + attribution per the I.1 protocol stays. Build
   notification infrastructure WHEN we open preset development to
   community contributors — separate phase, not Phase MD.

5. Brand-identity catalog ratio. Tracked, not yet quantified. The
   addendum should frame the question (what fraction of the catalog
   is Phosphene-native vs Milkdrop-inspired at steady state?) for
   explicit decision later. Do not pick a ratio in this session.

6. Substantial-similarity discipline rule. "Inspired by" does not
   save us if we reproduce a preset's specific protectable
   expression too closely. Each uplift must be a genuine new
   creation — new code, new audio coupling, possibly different
   visual structure that honors the source concept rather than
   reproducing source implementation. A discipline rule analogous
   to Failed Approach #48 ("§10.1-faithful but reference-divergent
   visual outputs") in CLAUDE.md should land in docs/SHADER_CRAFT.md
   §12 to make this an authoring-time constraint.

7. Counsel review. The counsel-gate clause on MD.2 onwards was
   removed by the commit immediately preceding this prompt's
   authoring (see the MILKDROP_COUNSEL_BRIEF.md §9 + D-111 +
   ENGINEERING_PLAN.md MD.5 edits in the relevant commit). Counsel
   review remains optional async due-diligence; the existing brief
   stays in tree as historical context. This session DOES NOT need
   to author a new counsel brief; if Matt later wants one for the
   inspired-by posture, that's a separate ask.

DECISIONS TO REVISE (specific shapes for this session to determine):

- D-103 (three tiers: Classic Port / Evolved / Hybrid) — under
  inspired-by, every uplift is a new creation. Likely collapses to
  a single tier, OR re-tiers on fidelity-to-source (close homage /
  loose homage / hybrid with substantial Phosphene-native
  structure). Recommend exploring both framings; pick the one that
  produces the cleanest authoring story.
- D-105 (three family values: milkdrop_classic / _evolved /
  _hybrid) — collapses if D-103 collapses. Naming proposal under
  inspired-by: single `milkdrop_inspired` family, OR if D-103 keeps
  fidelity tiers, `milkdrop_close` / `milkdrop_loose` / `milkdrop_hybrid`
  or similar.
- D-106 (three Settings toggles) — simplifies if D-105 does.
- D-110 (transpiler scope: expression-language only) — OBSOLETE in
  current form. The transpiler-as-code-emission-pipeline is retired.
  Replace with a decision on whether to ship a read-only analysis
  tool (helps authors understand .milk source files but never emits
  Phosphene code) or drop the tooling entirely (authors read .milk
  files manually, like reading any other reference material). Note
  MD.1's grammar audit is STILL relevant under inspired-by — just for
  a different reason (read-only understanding aid for authors rather
  than transpiler-input spec). Revise the MD.1 framing accordingly.
- D-111 (license posture) — pivots from derivative to inspired-by.
  Counsel-gate already removed. The `milkdrop_source` provenance
  block (or equivalent) and CREDITS.md attribution stay in some
  form. Confirm or revise the schema:
  ```
  "inspired_by": {
    "milkdrop_filename": "...",
    "original_artist": "...",
    "pack": "projectM-visualizer/presets-cream-of-the-crop",
    "sha256": "..."
  }
  ```
  Notification protocol: removed (per Matt input #4).
- D-112 (MD.5 candidate list: 9 named + 1 TBD Geometric, HLSL-free
  subset) — the HLSL-free constraint dissolves under inspired-by
  (all 9,795 presets become viable inspiration sources). The
  10-preset target may stay or expand. Reframe as the initial
  inspiration batch for the 20-preset release bundle.

NEW DECISIONS TO FILE:

- Release-bundle composition. The 20-preset release bundle is a mix
  of Phosphene-native + Milkdrop-inspired. Composition: how many of
  each? (Suggested floor: 5 Phosphene-native + 15 Milkdrop-inspired
  OR 10 + 10; Matt's call.) Currently 1 certified (Lumen Mosaic) +
  ~14 production-but-not-all-certified Phosphene-native; gap to 20
  is the work this addendum scopes.
- Substantial-similarity discipline rule. Specific text for
  docs/SHADER_CRAFT.md §12. Covers what "inspired by" requires of
  the author: read the source, understand the aesthetic, build
  from scratch — never paste source equations or shader logic.
  Cross-reference Failed Approach #48 as the precedent.
- Catalog-ratio framing. Frame the question for explicit later
  decision: at steady state, what fraction Phosphene-native vs
  Milkdrop-inspired? Inputs: brand identity, authoring economics
  (Milkdrop-inspired uplifts are typically faster than from-scratch
  Phosphene-natives), community ratio (when community opens, will
  the inspiration sources skew toward Milkdrop?).
- Read-only analysis tool: ship or skip? If ship, scope (just .milk
  parser + AST + pretty-print? Or also frequency analysis?). If
  skip, MD.2's existing prompt content informs MD.1's grammar audit
  rather than producing standalone tooling.

OUT-OF-SCOPE FOR THIS SESSION:

- Authoring any preset code (.metal / .swift / .json). The
  addendum revises strategy and decisions; preset authoring is the
  MD-uplift sessions that follow.
- Operationalizing the (now-deferred) notification protocol.
- Authoring a new counsel brief.
- Filing release-cadence decisions (weekly vs monthly vs
  quarterly). That's a release-management decision separate from
  this addendum.
- Reshaping Phase AV / Phase CC / Phase G-uplift roadmaps. The
  addendum's catalog-ratio question may inform those phases'
  scheduling but does not in this session restructure them.

READ FIRST (mandatory):
- docs/MILKDROP_STRATEGY.md (the base strategy this revises)
- docs/DECISIONS.md D-103 through D-112 (the decisions this amends)
- docs/diagnostics/MD-strategy-pre-audit-2026-05-12.md (the empirical
  audit; still valid under inspired-by — corpus stats unchanged)
- docs/MILKDROP_COUNSEL_BRIEF.md (historical context for the
  derivative-posture framing; addendum supersedes some sections)
- docs/CREDITS.md "Milkdrop preset attribution" placeholder (the
  attribution section; schema may revise under inspired-by)
- docs/SHADER_CRAFT.md §12 (where the discipline rule lands)
- prompts/MD.1-prompt.md (will need revision in step 4 of this
  session)
- CLAUDE.md "Authoring Discipline" section + Failed Approach #48
  (precedents for the discipline rule)
- docs/ENGINEERING_PLAN.md Phase MD (MD.1 through MD.7 increment
  specs — will need substantial revision)

---

STEPS:

0. Audit current tree state. Confirm:
   - D-103 through D-112 are filed.
   - Counsel-gate clause is REMOVED from D-111, ENGINEERING_PLAN.md
     MD.5, MILKDROP_STRATEGY.md §10, MILKDROP_COUNSEL_BRIEF.md §9,
     and CREDITS.md placeholder. If any of these still reference
     "gated on counsel sign-off" — halt; the prerequisite commit
     didn't land.
   - No pending working-tree changes outside scope.

1. Author the strategy addendum. Recommend appending as a new §12
   "Addendum — inspired-by reframe (2026-05-XX)" to MILKDROP_STRATEGY.md
   rather than rewriting the base. Sections:
   12.1 — Reframe summary + why
   12.2 — Decision revisions table (D-103/D-105/D-106/D-110/D-111/D-112 with old + new)
   12.3 — New decisions filed (D-113+, listed)
   12.4 — Release model (20-preset bundle)
   12.5 — Substantial-similarity discipline rule (link to SHADER_CRAFT.md §12)
   12.6 — Catalog ratio question (frame, defer decision)
   12.7 — Read-only analysis tool scope
   12.8 — Notification protocol deferral
   12.9 — Carry-forward: what changes for MD.1, MD.2, MD.5+

2. File new D-### entries. Numbering starts D-113 (verify against
   `grep -n "^## D-" docs/DECISIONS.md | tail -5` — D-112 is current
   highest as of this prompt's authoring). Each new decision follows
   the same format as D-103 through D-112: rule + why + carry-forward.

3. Update SHADER_CRAFT.md §12 with the substantial-similarity
   discipline rule. The rule applies to Milkdrop-inspired uplifts
   specifically (most of Phosphene's catalog is unaffected). Cross-
   reference Failed Approach #48 and the new D-### entry.

4. Revise prompts/MD.1-prompt.md to reflect the read-only-analysis
   framing. Most of the prompt content stays; the framing shifts from
   "audit that unblocks MD.2 transpiler" to "audit that helps authors
   read source .milk files." The HLSL-free vs HLSL-bearing corpus
   split may dissolve (all presets become viable inspiration sources);
   confirm and revise accordingly.

5. ENGINEERING_PLAN.md revisions. Substantial — MD.2 / MD.3 / MD.4
   collapse or transform; MD.5 / MD.6 / MD.7 re-shape under whatever
   tier structure D-103 revision produces. Take care: the existing
   Phase MD section is now substantial; revision should preserve
   what's still valid (the increment IDs may persist; the increment
   scopes shift). Surface the 20-preset release bundle as a
   load-bearing milestone.

6. Verify. No code changes; only doc + lint sanity:
   ```
   swiftlint lint --strict --config .swiftlint.yml | tail
   xcodebuild -scheme PhospheneApp -destination 'platform=macOS' build 2>&1 | tail
   swift test --package-path PhospheneEngine 2>&1 | tail
   grep -nE '\]\([^)]+\.md\)' docs/MILKDROP_STRATEGY.md prompts/MD.1-prompt.md
   ```

7. Commit + closeout. Recommend three commits for clean diffs:
   - Commit A: strategy addendum + new D-### entries
   - Commit B: SHADER_CRAFT.md discipline rule
   - Commit C: MD.1 prompt revision + ENGINEERING_PLAN.md revisions
   Push after Matt's "yes, push" confirmation.

DO NOT:
- Re-author MILKDROP_STRATEGY.md from scratch. Append as §12, don't
  delete §§1–11. The original strategy is historical record.
- File a new counsel-review brief. Matt's call if/when needed.
- Operationalize the notification protocol. Deferred per Matt input #4.
- Author preset code. This is a strategy session, not an authoring
  session.
- Pick a specific catalog ratio. Frame the question; defer the
  answer.
- Pick a release cadence. Matt's call at release-planning time.
- Push to remote without Matt's "yes, push" confirmation.

Carry-forward (informational only):
- After this session lands: the next runnable preset-authoring
  session is the first inspired-by uplift. Matt picks the source
  preset from the (now-unconstrained) cream-of-crop pack; session
  follows the SHADER_CRAFT.md discipline rule.
- MD.1 prompt remains queued (post-revision in step 4) as the next
  runnable analysis session.
- The 20-preset release bundle is the next project-level milestone.
  Gap analysis (how many native + how many inspired) is a
  release-planning artifact, not authored in this session.
```

---

## Notes on running this prompt

* **Estimated session length:** 60–90 min for the doc revisions + new
  D-### entries. No code, no preset authoring.
* **Output volume:** likely 4-6 commits total (addendum + 3-5 D-###
  entries + SHADER_CRAFT.md rule + MD.1 prompt revision + plan
  revisions). Recommend the 3-commit grouping in step 7 for clean
  diffs.
* **Prerequisite:** the counsel-gate-removal commit must be on
  `origin/main` before this session runs. Step 0 audit confirms.
