---
name: defect-handling
description: Invoke when working any Phosphene defect — a BUG-* ID, a P0/P1/P2 report, a regression, or a user-reported failure. Enforces evidence-before-implementation and the multi-increment fix process. Canonical home of the Defect Handling Protocol (from CLAUDE.md at DOC.9).
---

# Defect Handling Protocol

References: `docs/QUALITY/DEFECT_TAXONOMY.md` (severities, domain tags, failure classes), `docs/QUALITY/BUG_REPORT_TEMPLATE.md`, `docs/QUALITY/KNOWN_ISSUES.md` (active tracker).

## Evidence before implementation (P0/P1/P2)

Do not modify code until these are documented:

1. **Expected behavior** — observable output in concrete terms (values, units, state names). Not implementation internals.
2. **Actual behavior** — observed values; frequency if intermittent.
3. **Reproduction steps** — minimum reproducer; specific track or fixture if domain-specific.
4. **Session artifacts** — relevant `features.csv` columns, `session.log` lines, contact sheet, or diagnostic dump. Beat-sync/stem-routing: `features.csv` beat columns + `BeatSyncSnapshot`. Render defects: `RENDER_VISUAL=1` contact sheet where available.
5. **Suspected failure class** — one from the taxonomy (`algorithm`, `concurrency`, `api-contract`, `calibration`, `pipeline-wiring`, `resource-management`, `sample-rate`, `precision`, `test-isolation`, `sdf-geometry`, `render-state`, `regression`, `documentation-drift`).
6. **Verification criteria** — written BEFORE the fix. Minimum: one automated gate + one manual check for anything affecting musical feel or visual fidelity.

## Multi-increment process for P0/P1

Separate increments, each with its own commit and stop, unless trivial (<5 lines, root cause obvious from existing artifacts, no architectural risk — collapsing requires Matt's explicit approval, stated in the commit message and KNOWN_ISSUES):

1. **Instrumentation** — expose the failure. Commit and stop.
2. **Diagnosis** — reproduce from artifacts, root-cause, document in KNOWN_ISSUES. No fix code in this increment.
3. **Fix** — implement + regression tests.
4. **Validation** — full suite, domain artifacts, mandated manual validation.
5. **Release notes** — update `RELEASE_NOTES_DEV.md`, mark resolved in KNOWN_ISSUES.

## Fix increment obligations

Every fix updates `docs/QUALITY/KNOWN_ISSUES.md` (Resolved field + commit hash) and `docs/RELEASE_NOTES_DEV.md`. Never skipped under "it's obvious from the commit."

## Domain artifact requirements (before AND after fix work)

| Domain | Required artifacts |
|---|---|
| `dsp.beat` | `features.csv` beat-sync columns (`lock_state`, `grid_bpm`, `drift_ms`, `barPhase01_permille`), SpectralCartograph mode label, `BeatSyncSnapshot` from a real session. Minimum: Love Rehab at 125 BPM. |
| `dsp.stem` | `stems.csv` non-constant deviation-field values across 500+ frames + manual observation of musical connection. |
| `preset.fidelity` | `RENDER_VISUAL=1` contact sheet vs. `docs/VISUAL_REFERENCES/<preset>/`; anti-references explicitly checked (FA #48). |
| `renderer` | `PresetRegressionTests` golden hash before/after; Metal GPU trace if frame budget affected. |

## Manual validation is required for

- **Musical feel** — beat alignment, stem-visual coupling, tempo tracking. Automated tests prove pipeline correctness, not that it feels musical; listen at normal volume.
- **Visual fidelity** — M7 review for any preset approaching certification. Matt's approval; no automated metric substitutes.
- **UX flow** — any session-lifecycle or playback-chrome change: walk the flow end-to-end.
