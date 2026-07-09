# QG.1 Task 1 — Replay Feasibility Audit

**Date:** 2026-07-09. **Increment:** QG.1 (per-preset audio route-coverage gate). **Verdict: GO**, with three small, bounded infrastructure sub-tasks (§Gaps). No new stem-separation or capture infrastructure is needed — every production component the gate requires already runs headlessly; the gaps are output-format and fixture-packaging work.

**Question audited:** can the repo, today, replay a canonical fixture (features.csv + stems.csv, or raw audio) through the preset parameter-routing path headlessly and expose per-frame primitive values?

**Answer:** not end-to-end through any single existing tool — but the pieces exist and compose with small extensions. `PresetSessionReplay` replays *recorded session directories* only (it runs no DSP). The production DSP chain itself, however, is separately provable headless on raw audio: `FixtureSessionCaptureGenerator` already drives the tempo fixtures through StemSeparator (MPSGraph) + StemAnalyzer and writes production-schema `stems.csv`; and `MIRPipeline.process(magnitudes:fps:time:deltaTime:)` is the *complete* production FeatureVector assembler (bands, deviation primitives, beat accents, beat/bar phase, pulse, tonal, structural prediction) callable per-1024-hop offline — CENSUS and ColdStartVerifier both already do this pattern. The missing piece is only: write the features.csv half, package the results as checked-in fixtures, and widen the CSV loader's column surface.

---

## (a) Inputs PresetSessionReplay accepts

- One recorded **session directory** (`SessionDataLoader.load`): `features.csv` + `stems.csv` **both required**, strictly parsed (missing named column = error; per-file row/header field-count mismatch = error; features/stems row counts must be equal). `video.mp4` optional (event-frame extraction). Optional `--references-dir` for the rubric section.
- CLI: `--session`, `--preset`, `--output`, `--motion-grid-count`, `--rubric-frame-count`, `--max-events-per-route`, `--references-dir`.
- It accepts **no raw audio and runs no DSP** — it is pure post-hoc analysis of per-frame values the live engine already recorded.

## (b) What it exposes per frame

- `SessionFrame` — a **19-field subset**: 4 timing fields + 5 FeatureVector fields (`bassDev`, `bassAttRel`, `beatPhase01`, `valence`, `arousal`) + 10 StemFeatures fields (4×energy, 4×energyDev, `vocalsPitchHz`, `vocalsPitchConfidence`). The parser reads full row dictionaries but discards all other columns at `SessionFrame` construction.
- Route firing is computed from **hand-authored `RouteSpec` closures** over `SessionFrame`, with gate constants **duplicated by hand** from each shader (documented SR.1 limitation). Registered presets: `aurora_veil`, `murmuration`, `skein` — 3 of 12 certified presets.
- The recorded surface is much richer than the exposed surface: current `features.csv` has **59 columns** (3-band + 6-band energies, 4 beat accents, centroid/flux, valence/arousal, beatPhase01/bassRel/bassDev/bassAttRel, bar-phase block, pulse block, section block, tonal block, perf columns) and `stems.csv` has **52 columns** (per-stem energy/beat/bands, Rel/Dev, rich metadata, vocals pitch, and the IFC.4 instrument-family block).

## (c) Replay-usable fixtures in the repo — audit

| Fixture | What it is | Replay-usable? |
|---|---|---|
| `Tests/PhospheneEngineTests/Fixtures/fbs/*.csv` (9 files) | Narrow diagnostic extracts from real sessions (3–6 columns each: bass/mid/treble, drumsEnergyDev, beatPhase01, stemSum) | **No** — not session directories; far below the declared-primitive surface |
| `Tests/Fixtures/tempo/*.m4a` (love_rehab, so_what, there_there) | Real 30 s preview clips, fetched by `Scripts/fetch_tempo_fixtures.sh` (present in this worktree; gitignored) | **Yes as raw-audio input** to offline generation; not directly loadable by `SessionDataLoader` |
| `beat_this_reference/`, `panns_reference/`, `Regression/Fixtures/*` | Model/pipeline goldens (activations, FFT expectations, API responses) | No |
| Off-repo: `~/Documents/phosphene_sessions/fixturegen-{love_rehab,so_what,there_there}/` | `FixtureSessionCaptureGenerator` output, 2026-06-11: production-pipeline `stems.csv`, ~1288–1290 frames each (> the 500-frame `dsp.stem` convention) | **Partially** — stems only (no features.csv → `SessionDataLoader` rejects), and **stale schema**: 44 columns, predating the IFC.4 (D-177) instrument-family block |

**Net: zero fixtures in the repo are loadable by the replay path today.** The three tempo fixtures + the existing generator get us there.

## (d) Gaps → minimal infrastructure sub-tasks

1. **QG.1a — features.csv offline generation.** `FixtureSessionCaptureGenerator` writes only stems.csv. All components for the features half already exist and are production code: suite-standard ffmpeg decode → `FFTProcessor` per 1024-hop → `MIRPipeline.process` (returns the fully-populated production `FeatureVector`, including deviation primitives, beat accents, beat/bar phase, pulse, tonal, and `latestStructuralPrediction` — StructuralAnalyzer survived D-170, which removed SECDET only) → `SessionRecorder.csvRow(features:stems:beatSync:...)` production writer. Extend the generator to emit features.csv alongside stems.csv, truncating both to equal frame counts (SessionDataLoader requires row alignment). Beat-phase note: with no cached BeatGrid installed, `beatPhase01` comes from the reactive `BeatPredictor` fallback — still real-signal-driven and non-constant, which is what the gate asserts.
2. **QG.1b — regenerate + check in the canonical fixture set.** The generator's local stems header is **stale (44 names) while `csvRow(stems:)` now emits 52 fields** — as-is it would write CSVs the strict loader rejects; fix by promoting SessionRecorder's header literals to shared internal constants and referencing them from both writer sites. Then regenerate and **check in** the three features.csv+stems.csv pairs under `Tests/PhospheneEngineTests/Fixtures/route_coverage/<fixture>/` (~0.5–1 MB text per file, ~3–5 MB total, compresses well — acceptable vs. the repo-size ledger). Checked-in CSVs make RouteCoverageTests deterministic and runnable on any checkout **without** Metal, MPSGraph, the ~136 MB stem-model weights, or ffmpeg; regeneration stays env-gated (`PHOSPHENE_GEN_SESSION_DIR`) for schema-append migrations. FA #27 is satisfied: real music through the production separation + analysis chain, nothing hand-authored.
3. **QG.1c — by-name column access in `SessionDataLoader`.** RouteCoverageTests must read *any* declared primitive, not the 19-field `SessionFrame`. The parser already materializes `[String: String]` row dictionaries; add an additive API that exposes named columns as `[Float]` series (and the header set, for schema validation of `audio_routes.primitive` names). No change to existing consumers.

**Explicitly not needed:** new stem-separation/capture infrastructure (Do-NOT respected — the MPSGraph path already exists in the generator); any `.metal` change; any PresetSessionReplay executable change (RouteCoverageTests consumes `SessionDataLoader` directly — the per-preset `RouteSpec` registry with hand-duplicated gate constants is the *complement* of this gate, not its substrate: QG.1 asserts the declared *primitive* is alive on real music; SR.1 evidence packs assert the *shader's gate* fires in a live session).

## Design notes surfaced for Task 3 (recorded here, decided there)

- **Structural floor caveat:** `StructuralAnalyzer` needs 2+ observed boundaries before predicting; a 30 s clip may legitimately contain no section boundary. The "fixture that contains a section boundary" precondition must be verified empirically against the generated fixtures before any `structural` route is backfilled — if none of the three fixtures produces a boundary, `structural` floors are documented as not-yet-armed rather than tuned to pass (red route = working gate; missing fixture = honest gap, QG.1.1 territory).
- **Perf/diagnostic columns** (`frame_cpu_ms`, subsystem timing, render/ray-march pass columns) are not primitives; the offline writer emits empty cells there exactly as cold-start live frames do. Schema validation for `audio_routes.primitive` should whitelist FeatureVector/StemFeatures-backed columns only.
- **D-number:** the prompt's "D-164" is stale — `docs/DECISIONS.md` is at D-178. The Task 5 record takes the next free number verified at write time.

## Recommendation

**GO.** Order: QG.1a+b (generator fix + features half + regenerate + check in, one commit), QG.1c (loader accessor), then Tasks 2–5 as prompted. Fixture breadth: **option (1)** — the three tempo fixtures (dance/jazz/rock, zero licensing work, already vendored); sparse-material fixtures (ambient/vocal-only, where routes most plausibly go dead) noted as QG.1.1 follow-up needing preview-clip sourcing.
