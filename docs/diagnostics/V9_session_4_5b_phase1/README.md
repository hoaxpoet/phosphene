# V.9 Session 4.5b Phase 1 — diagnostic PNGs pruned (DOC.7, 2026-06-13)

This directory held 29 side-by-side fixture renders (~49 MB of plain-blob PNGs)
comparing `main` against the Ferrofluid Ocean height-bake iterations
(`01_silence` / `02_steady_mid` / `03_beat_heavy` / `04_quiet` ×
`main` / `phase1` / `phase1_tuned` / `phase1_dense` / `phase1_hardmin` /
`phase1_4k` / `phase2a` / `phase2b`).

**They were pruned under DOC.7** as spent diagnostics from a closed session.
Matt rendered the visual verdict on 2026-05-14 — *"Looks better. I'm ready to
call this a pass and move on to Phase 2."* — so the comparison images had served
their purpose. Nothing active or programmatic referenced them; the only mentions
are historical narrative in
[`../../RELEASE_NOTES_DEV_2026-05.md`](../../RELEASE_NOTES_DEV_2026-05.md) and
[`../../ENGINEERING_PLAN_HISTORY.md`](../../ENGINEERING_PLAN_HISTORY.md) (the
Session 4.5b Phase 1 entry, ~line 1306), which this tombstone keeps resolvable.

**Recovery:** the PNGs remain in git history — they were committed across
`7dc41106..8862d6f2` (the `[V.9-session-4.5b-phase1/2a/2b]` increments).
`git show <commit>:docs/diagnostics/V9_session_4_5b_phase1/<file>.png` restores any
single frame; `git checkout 8862d6f2 -- docs/diagnostics/V9_session_4_5b_phase1`
restores the set.

**Going forward:** image artifacts under `docs/diagnostics/` are git-LFS-tracked
(see [`../../../.gitattributes`](../../../.gitattributes)) so future contact
sheets never bloat the pack as plain blobs. Spent session diagnostics still get
pruned per the CLAUDE.md pruning-pass policy — LFS keeps the working set lean, it
does not make hoarding free.
