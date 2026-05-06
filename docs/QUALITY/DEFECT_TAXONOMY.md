# Phosphene — Defect Taxonomy

Defects are classified by **severity** (P0–P3) and **domain**. Both axes determine the evidence requirements, fix process, and update obligations for each defect.

---

## Severity Levels

### P0 — Critical (session-ending or data-loss)

The application crashes, hangs, corrupts persistent data, or makes the primary session flow completely unusable. Requires immediate attention. Fix cannot be deferred to a planned increment.

**Examples:**
- App crash during active playback
- `StemCache` corruption causing permanent failure across restarts
- Audio tap delivering silence silently with no recovery path
- `SessionRecorder` writing corrupt video that cannot be finalized

**Evidence required before any fix:** Crash log or hang trace, git bisect to the introducing commit, reproduction steps on a clean build, and a proposed verification procedure. Do not modify code before evidence is documented.

---

### P1 — High (feature broken or consistently wrong output)

A core feature produces wrong output across a range of inputs, or a critical pipeline stage fails in a way that degrades the musical experience significantly and reliably. Not session-ending but noticeably broken.

**Examples:**
- Beat sync LOCKED state never reached for correctly-prepared Spotify playlists
- Stem separation producing silence on all stems
- `PresetScorer` always returning 0 for all presets (no auto-selection)
- `BeatGrid.halvingOctaveCorrected()` halving below 80 BPM (breaking Pyramid Song)
- Preset shader fails to compile, silently dropped from catalog

**Evidence required before any fix:** Session artifacts (features.csv, session.log, or diagnostic dump), expected vs. actual values with units, reproduction steps. For DSP/beat-sync defects: `BeatSyncSnapshot` CSV or diagnostic capture. Fix increments must update `KNOWN_ISSUES.md` and `RELEASE_NOTES_DEV.md`.

---

### P2 — Medium (degraded quality or intermittent failure)

A feature works for typical inputs but degrades noticeably for specific inputs or conditions, or fails non-deterministically.

**Examples:**
- Money 7/4 stays REACTIVE on live path (Beat This! returns empty grid)
- `PresetVisualReviewTests` PNG export broken for staged presets under `RENDER_VISUAL=1`
- `MetadataPreFetcher.fetch_networkTimeout_returnsWithinBudget` intermittent failure
- Visual quality lower than expected for a specific preset/track combination
- Orchestrator drift-tracker locking too slowly on quiet-intro tracks

**Evidence required before any fix:** Specific track + session artifacts; for render issues, a contact-sheet screenshot. P2 defects are triaged; a fix may be deferred to a planned increment. Known P2s are listed in `KNOWN_ISSUES.md`.

---

### P3 — Low (cosmetic, documentation, or edge-case)

Non-blocking quality issues, minor rendering artifacts, documentation drift, or edge cases that affect a small fraction of inputs.

**Examples:**
- Stale doc comment referencing removed API
- Minor audio label misalignment in `SpectralCartograph` text overlay
- `PresetCategory.allCases.count` not matching actual categories in a comment
- Debug overlay showing a jargon term that users could theoretically see

**Process:** P3 defects may be bundled into any increment that touches the affected area, or logged in `KNOWN_ISSUES.md` for tracking. No separate fix increment required.

---

## Defect Domains

Every defect is tagged with one or more domains. The domain determines required artifacts and validation approach.

| Domain | Tag | Required Artifacts | Validation |
|---|---|---|---|
| Beat sync / tempo | `dsp.beat` | `features.csv` beat columns, `SpectralCartograph` capture, lock-state log | Manual: beats align to perceived beat at normal listening volume |
| Stem routing | `dsp.stem` | `stems.csv`, `StemFeatures` GPU buffer dump | Automated: deviation field ranges; manual: visual response feels musically connected |
| Preset fidelity | `preset.fidelity` | Contact sheet vs. reference images, rubric scores | Manual: M7 review against `docs/VISUAL_REFERENCES/<preset>/` |
| Render pipeline | `renderer` | Frame timing report, Metal GPU trace, `features.csv` quality-level column | Automated: regression hash; manual: no visible artifacts |
| Audio capture | `audio.capture` | `session.log` signal-quality transitions, tap rate, `InputLevelMonitor` grade | Automated: silence detector state machine; manual: signal grade green at steady-state |
| Session / UX | `session.ux` | App state log, `ContentView` state trace | Automated: state machine tests; manual: walkthrough of affected flow |
| Performance | `perf` | `FrameTimingReporter` histogram, soak test output (`SoakTestHarness`) | Automated: p95 ≤ tier budget; 2-hour soak test passes |
| Orchestrator | `orchestrator` | Golden session test output, `PresetScoreBreakdown` dump | Automated: golden session fixtures; manual: preset choices feel musically appropriate |
| ML inference | `ml` | Layer-match diagnostic dump (`BeatThisActivationDumper`), per-stage min/max/mean | Automated: layer-match within tolerance; end-to-end beat count against ground-truth fixture |
| Documentation | `docs` | Diff of affected doc files | Review: no contradictions with current code |

---

## Defect Process by Severity

### P0 / P1

1. **Instrumentation increment** (if no existing artifacts cover the defect): add logging, diagnostic capture, or test infrastructure to expose the failure. Commit separately.
2. **Diagnosis increment**: reproduce from artifacts, identify root cause, document in `KNOWN_ISSUES.md` before fix work begins.
3. **Fix increment**: implement the fix, add or extend regression tests.
4. **Validation increment**: run full test suite, produce required domain artifacts, perform manual validation where mandated.
5. **Release notes**: update `RELEASE_NOTES_DEV.md` and mark resolved in `KNOWN_ISSUES.md`.

Trivial P1 defects (< 5 lines of change, root cause obvious from existing artifacts, no architectural risk) may collapse steps 1–4 into a single increment with Matt's explicit approval.

### P2

May use a single fix increment when root cause is already documented. Must update `KNOWN_ISSUES.md` resolution field.

### P3

Bundle into any passing increment. No separate process.

---

## Failure Classes

Used in bug reports to group defects by root-cause category. See `BUG_REPORT_TEMPLATE.md`.

| Class | Description |
|---|---|
| `algorithm` | Incorrect computation or formula (e.g., wrong mel filterbank interpolation) |
| `concurrency` | Race condition, actor isolation violation, misuse of `@MainActor` |
| `api-contract` | External API schema mismatch (Spotify, iTunes, MusicBrainz) |
| `calibration` | Correct algorithm, tuning constants wrong for real-world inputs |
| `pipeline-wiring` | Correct module, but not connected or connected in wrong order |
| `resource-management` | Buffer allocation, MTLBuffer reuse, memory footprint |
| `sample-rate` | Hardcoded rate assumption violated by actual tap or file |
| `precision` | Float16/Float32 mismatch, integer truncation, threshold miscalibration |
| `test-isolation` | Test interference, parallel execution, global state leak |
| `sdf-geometry` | Incorrect SDF construction or coverage formula in shader |
| `render-state` | Missing or incorrect Metal pipeline state setup |
| `regression` | Previously-passing behavior broken by a subsequent change |
| `documentation-drift` | Code and docs describe different behavior; both may be correct |
