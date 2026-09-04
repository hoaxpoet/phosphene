# Session prompt — PREP.1

## Increment PREP.1 — where the preparation minutes go

**Type:** Engine instrumentation + diagnosis. First increment of **Phase PREP — Session preparation throughput**. **Measurement only.** No stage is made faster, removed, reordered, or run concurrently in this increment.

**Objective.** After this session there is a per-stage, per-track timing record for local-file session preparation, taken on a real cold-cache run, and a written report that says which stage or stages account for the 50 s/track the path currently costs — against the 7.5 s/track budget D-242 sets. The report ends in a recommendation with options; it does not implement one.

**Why measurement only.** D-242 records a target and an observation, not a diagnosis. The obvious suspect (LFSTEM.1's whole-file stem sweep) is also load-bearing work Matt's M7 approved, and the serial outer loop is a second candidate that would be invisible in per-stage numbers alone. Guessing wrong here costs a rebuild of something that was right. Evidence before implementation — this is the `defect-handling` protocol's instrumentation increment, run deliberately as its own step.

## Settled facts carried into this increment

**The budget (D-242).** 40 tracks in 5 minutes = **7.5 s/track**, wall-clock from the first preparation task starting to `SessionManager` reaching `.ready`, Mac mini dev target, **cold** persistent cache. Matt's measurement: **12 FLAC files, 10 minutes, 50 s/track** — ~6.7× over.

**The two paths are not the same shape.** Streaming analyses a **30 s preview** per track through `SessionPreparer.analyzePreview`. The local path decodes the **entire file** and adds two analyses streaming structurally cannot do: `StemFeatureSeries` (LFSTEM.1 — the whole file swept in 2 s spans, each placed at the end of a ~10 s separation window) and `LoudnessProfile` (DYN.1c). A 5-minute track is ~10× the audio of a preview. Some multiple is expected; 6.7× over a per-track budget is not explained by that alone.

**The outer loop is serial.** `SessionPreparer._runLocalFilePreparation` is a plain `for (index, pair) in zip(urls, placeholders).enumerated()` awaiting `delegate?.prepareLocalFile(url:)` one file at a time. The streaming path (`_runPreparation`) is not shaped this way. Whether that serialisation costs anything real depends on where the time goes — a stage that already saturates the GPU gains nothing from concurrency, one that blocks on disk gains a lot. **The instrumentation must be able to tell those apart**, which means recording not just stage durations but what the machine was doing (see task 3).

**Nothing here is a defect with a known cause yet.** Do not open a `BUG-*` ID. This is a phase-opening diagnosis; if it lands on a specific defect, file it then, with the artifacts this increment produces.

## Skill invocations

- `defect-handling` at the start — this is its instrumentation step, and its evidence-before-implementation rule is the whole shape of this increment.
- `closeout` at the end (mandatory). §2 is the verbatim `Scripts/closeout_evidence.sh` block.
- **Not** `preset-session`, **not** `shader-authoring` — no `.metal` file, no preset, no shader.
- **Not** `beat-sync-session` / `beatbench` — the beat grid is *timed* here, never changed. No behavioural change to beat sync; say so explicitly in the closeout.

## Read-first file list

1. `docs/DECISIONS.md` D-242 (the budget and what it does not decide) — via the §Index.
2. `UzumeEngine/Sources/Session/SessionPreparer.swift` — `prepareLocalFiles(...)`, `_runLocalFilePreparation(...)` (the serial loop), and `analyzePreview(...)` (shared with streaming). Compare against `_runPreparation` to see how the streaming path is shaped.
3. `UzumeApp/VisualizerEngine+LocalFilePlayback.swift` — `prepareLocalFile(url:)`, `runLocalFilePreparation(inputs:)`, `tryLoadFromPersistentCache(...)`, `analyzeAndPersist(...)`, `analyzeStemSeriesForLocalFile(...)`. This is where the per-track stages actually live.
4. `UzumeEngine/Sources/Session/LocalFilePreparing.swift` — the delegate contract and `LocalFilePrepResult`.
5. `UzumeEngine/Sources/Shared/SessionRecorder*.swift` — how session artifacts are written today, and whether a CSV sidecar has precedent (`features.csv`, `stems.csv`). The timing record should follow that convention, not invent one.
6. `docs/ENGINEERING_PLAN.md` §LFSTEM.1 / §LFSTEM.2 / §DYN.1c — what the whole-file analyses are for and what was measured when they landed.
7. `docs/QUALITY/KNOWN_ISSUES.md` BUG-087 (the local path's ~16 Hz analysis rate and the 100 ms buffer ceiling) — adjacent, and its "measure before believing a rate" lesson applies.
8. `Scripts/measure_analysis_rate.py` — an existing measurement tool; the report's tooling should look like this, not like a bespoke harness.

## Pre-flight invariants

Each is a stop condition. A failed check ends the session with a report, not a workaround.

- **`git status` clean on a branch fresh from `origin/main`** (which contains D-242 and this prompt).
- **`Scripts/closeout_evidence.sh` is ALL GREEN before task 1**, allowing for the two `SpotifyConnectionViewModel` retry-backoff tests if they still flake under load. In a worktree run `Scripts/link_fixtures.sh` first. Anything else red is a stop.
- **A cold-cache local run is actually possible on this machine** — confirm the persistent stem cache location and that it can be cleared and restored. **Move it aside; never delete it.** Matt's real cache is not test scaffolding.
- **At least 12 local audio files are available**, ideally the FLAC set Matt used. If FLAC is unavailable, say so in the report and state what was used instead — format is a variable this increment is explicitly testing (task 5).

## Numbered tasks

1. **Reproduce the number before explaining it.** Run one cold-cache local-file preparation of ≥12 tracks end to end and record the wall clock from preparation start to `.ready`. Confirm it lands near Matt's 50 s/track before instrumenting anything; a run that comes in at 8 s/track means the machine, the files, or the cache state differ from his and the whole increment is measuring the wrong thing.
   **Done-when:** a measured per-track figure is written down with the track count, total duration of the audio, file format, and cache state. If it does **not** reproduce, stop and report — do not instrument a run that isn't the problem.

2. **Instrument the per-track stages.** Every stage inside `prepareLocalFile(url:)` gets a start/end timestamp: content hash, persistent-cache probe, decode, `analyzePreview`, `StemFeatureSeries` sweep, `LoudnessProfile`, beat-grid analysis, instrument-family analysis, cache write. Emit through `SessionRecorder` in the existing session-artifact idiom — a `preparation.csv` sidecar next to `features.csv`/`stems.csv`, one row per (track, stage) with duration and the track's decoded duration, plus the existing `session.log` line per file. Gate it the way other diagnostic surfaces are gated so a normal session pays nothing measurable.
   **Done-when:** a cold-cache run produces `preparation.csv` with a row per stage per track; the stage durations sum to within a few percent of the per-track wall clock (a large unexplained remainder means a stage is missing from the list — find it).

3. **Record what the machine was doing, not only how long each stage took.** For each stage also capture enough to tell a saturated stage from a waiting one: at minimum wall time vs CPU time, and whether the stage is GPU-bound (the MPSGraph stem/beat models) or disk-bound (decode, cache write). This is what makes the serial-loop question answerable — a stage at 5 % CPU for 20 s is a very different finding from one pinning eight cores.
   **Done-when:** the report can state, per dominant stage, whether running two tracks at once would plausibly overlap or merely contend, **with the measurement that supports it**. "Probably parallelisable" without a number is not a finding.

4. **Establish the per-second cost.** Express each stage as cost per second of decoded audio, not just per track, so a 3-minute track and an 8-minute track are comparable and the budget can be reasoned about for real playlists. State the implied total for a 40-track playlist at a realistic mean track length, and how far over 300 s it lands.
   **Done-when:** a table of stage → ms per second of audio, and a projected 40-track total with the assumed mean length stated.

5. **Test the two variables Matt's run and the streaming path differ on.** (a) **Format:** run the same tracks as FLAC and as a already-compressed format (e.g. m4a/AAC) — if decode is a large share, FLAC's cost shows up here. (b) **Track length:** include at least one short (<2 min) and one long (>6 min) track — the whole-file stages should scale with length and the fixed costs should not. This is what separates "the pipeline is heavy" from "one stage scales badly".
   **Done-when:** both comparisons are in the report as measurements, with the conclusion stated plainly, including a null result ("decode is 3 % either way") if that is what the numbers say.

6. **Measure the streaming path the same way, for one playlist.** It is the same `analyzePreview` on 30 s of audio, so it is the natural control: it says how much of the local cost is the shared analysis and how much is the whole-file extras. A short run is enough.
   **Done-when:** streaming per-track and per-second-of-audio figures sit beside the local ones in the same table.

7. **Write the report.** `docs/diagnostics/PREP1_PREPARATION_TIMING_<date>.md`: the reproduction, the per-stage table, the per-second table, the format and length comparisons, the streaming control, and — separately and last — **options** for closing the gap, each with what it would cost the listener. Rank them by measured payoff, not by ease. If one stage dominates so heavily that everything else is noise, say that in the first paragraph rather than burying it.
   **Done-when:** the report exists, every claim in it traces to a row in `preparation.csv` or a named measurement, and the options section names what is lost for each — explicitly including "what the listener loses" for anything that touches LFSTEM.1's sweep or the loudness profile.

8. **HARD STOP — present to Matt.** The report, the headline number, and the options. **Present, stop, and report.** No optimisation is implemented in this increment, however obvious the answer looks by then. The follow-up increment is chosen from the options with Matt.
   **Done-when:** Matt has the report and the recommendation, and has picked a direction (or asked for more measurement).

## Do NOT

- **Do not optimise anything.** Not a reordering, not a concurrency change, not a "while I was in there" cache tweak. If a change is irresistible, write it in the report as an option with its measurement.
- **Do not remove or shorten the whole-file stem sweep or the loudness profile.** They are LFSTEM.1 / DYN.1c, they passed an M7, and they are the reason local-file stems are not 2.5 s late. Cutting them is a product decision with a visible cost, and it belongs to Matt with the numbers in front of him.
- **Do not touch the beat grid's behaviour.** It may be timed and nothing more. No `BeatGridResolver` / `BeatActivationDecoder` / `DefaultBeatGridAnalyzer` behavioural edit — that is the beat-sync program's territory (D-202) and would owe a five-suite BeatBench table.
- **Do not delete Matt's persistent stem cache.** Move it aside for the cold run and put it back.
- **Do not let the instrumentation cost anything in a normal session.** Gate it; prove the gate with a measurement, not an assertion.
- **Do not file a `BUG-*` ID for "preparation is slow"** — that is D-242's target being missed, already recorded. File a defect only for a specific, root-caused failure this increment uncovers.
- **Do not change the preparation UI.** The estimate shown on the preparation screen may well be wrong; fixing it needs this increment's numbers first, and it is DS-phase work.

## Verification commands

```
swiftlint lint --strict --config .swiftlint.yml
xcodebuild -scheme UzumeApp -destination 'platform=macOS' build 2>&1
xcodebuild -scheme UzumeApp -destination 'platform=macOS' test 2>&1
swift test --package-path UzumeEngine 2>&1
Scripts/closeout_evidence.sh
```

Increment-specific gates:

```
# The instrumentation is off by default and costs nothing when off.
grep -rn "preparation.csv\|PREP_TIMING" UzumeEngine/Sources UzumeApp --include='*.swift'

# The timing sidecar exists and every track has every stage.
head -5 ~/Documents/uzume_sessions/<session>/preparation.csv
awk -F, 'NR>1 {print $2}' ~/Documents/uzume_sessions/<session>/preparation.csv | sort | uniq -c
```

No behavioural change to beat sync — state this explicitly in the closeout in place of a BeatBench table.

## Commit message templates

`[PREP.1] <component>: <description>` — small commits per logical step:

```
[PREP.1] SessionRecorder: a preparation.csv sidecar, one row per track stage
[PREP.1] VisualizerEngine+LocalFilePlayback: stage timings around every local prep stage
[PREP.1] SessionPreparer: stage timings on the streaming control path
[PREP.1] diagnostics: where the preparation minutes go — the PREP.1 report
[PREP.1] docs: D-242 target restated against measured per-stage numbers
```

Push only on Matt's explicit approval.

## Closeout format

Invoke the `closeout` skill; produce the 8-part report with the verbatim `Scripts/closeout_evidence.sh` block as §2. Increment-specific additions:

- The reproduction figure from task 1, next to Matt's 50 s/track.
- The per-stage and per-second tables.
- The format and track-length comparisons, including null results.
- The streaming control figures.
- The projected 40-track total against the 300 s budget.
- The explicit statement: **no behavioural change to beat sync**.
- The options list, ranked by measured payoff, each with what the listener loses.

## DECISION-NEEDED

None at authoring time — this increment measures and reports. The decision it produces (which option to take) is task 8's hard stop, and it belongs to Matt with the numbers in front of him.

If a product-level question appears mid-session — one whose answer changes what the listener sees, feels, or waits for — **stop and bring it to Matt** rather than deciding it quietly. Engineering choices remain Claude's.

## Notes for the next increment

PREP.2 is whichever option Matt picks. Two are worth naming now so the report addresses them directly rather than being re-read later:

- **Concurrency across tracks.** The outer loop is serial. Task 3's saturation data is what says whether this is free throughput or just contention.
- **Two budgets instead of one.** Progressive readiness already lets playback begin before the walk finishes, so "time to *ready*" and "time to *fully prepared*" may deserve separate targets — the listener waits only for the first. If the report supports that split, it is a D-242 amendment, not a new decision.
