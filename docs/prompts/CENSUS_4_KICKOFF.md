# Increment CENSUS.4 — full-corpus census run (27,639 tracks) + corpus-scale report

**Type:** infrastructure / data — batch corpus analysis, **measure-only**. **Runs on the Mac with `/Volumes/Extreme SSD` mounted** (needs the corpus + a multi-hour, resumable run).

**Objective.** After this session the production analysis pipeline has been run over the **entire 27,639-track corpus** (not just the CENSUS.3 1,000-track pilot); the per-track results live on the SSD next to the manifest (never the repo); and `docs/diagnostics/CENSUS_FULL_REPORT.md` presents the corpus-scale distributions (extending the pilot's five sections) plus a first characterization of **swing/microtiming on the jazz + classical strata** — D-154's named open problem, now resourced at full scale. **No threshold, scaler, or constant changes** — the census MEASURES; every retune is its own later D-numbered increment (plan §Phase CENSUS scope guard).

---

## Skills to invoke
- **`closeout`** at the end (mandatory — 8-part report with the verbatim evidence block).
- No `preset-session` / `shader-authoring` (no preset or GPU work). No `defect-handling` (not a BUG-*). If the **deep-swing** path is chosen (DECISION-NEEDED), it adds Swift to `CorpusCensusRunner` — still no preset skill, just the standard build/lint/test gates.

## Read first (minimal — skills carry the protocol)
1. `docs/ENGINEERING_PLAN.md` §Phase CENSUS — the CENSUS.1–.4 rows + the **scope guard** (measure-only; retunes are separate increments).
2. `docs/diagnostics/CENSUS_PILOT_REPORT.md` — the pilot's structure + the **5 headline findings** CENSUS.4 lifts to corpus scale, and the "candidate follow-up" framing.
3. `tools/census_report.py` — the report generator CENSUS.4 **extends** (usage block at the top; stdlib-only).
4. `PhospheneEngine/Sources/CorpusCensusRunner/CorpusCensusRunner.swift` + `CensusIO.swift` — the runner CLI (flags, resume-skip, RFC-4180 CSV).
5. `docs/research/CORPUS_ML_OPPORTUNITIES.md` §10 item 1 + §Appendix — the census charter + the corpus survey.

## Pre-flight invariants (a failed check stops the session)
- CENSUS.3 pilot **reviewed** (Matt's go-ahead for the full run — this prompt is that go-ahead).
- `/Volumes/Extreme SSD` mounted; `/Volumes/Extreme SSD/phosphene_corpus_manifest.csv` exists with ~27,639 data rows (the CENSUS.1 full manifest — NOT the 1,000-row pilot).
- `swift build -c release --package-path PhospheneEngine` green (the runner builds from `main`).
- `swift test --package-path PhospheneEngine --filter "CorpusCensus|assessBeatIrregularity"` green (CENSUS.2 baseline intact).
- SSD has free space for the results CSV (tens of MB) and `coreaudiod` is healthy (`ps -o etime= -p $(pgrep -x coreaudiod)` — if it's wedged, decode feeds zeros; `killall coreaudiod` first — [[streaming-tap-signal-health]] BUG-057).
- On `main` at/after the merged CENSUS.1–.3 work, on a fresh branch off it.

## Tasks

1. **Smoke-check the runner on a 20-track full-manifest slice.**
   ```
   swift run -c release --package-path PhospheneEngine CorpusCensusRunner \
     --manifest "/Volumes/Extreme SSD/phosphene_corpus_manifest.csv" \
     --root "/Volumes/Extreme SSD" \
     --out "/Volumes/Extreme SSD/phosphene_census/full_results.csv" --limit 20
   ```
   (NO `--dual-rate` — pilot-only.) **Done-when:** 20 tracks analysed; all `mir_bpm` 60–200; no systematically-empty feature column; per-track < 5 s; the output CSV carries the CENSUS.2 schema. A systematically-empty column → **stop and report** (a pipeline regression since the pilot), do not proceed to the full run.

2. **Launch the full resumable run** (same command, no `--limit`, backgrounded for the overnight):
   ```
   nohup swift run -c release --package-path PhospheneEngine CorpusCensusRunner \
     --manifest "/Volumes/Extreme SSD/phosphene_corpus_manifest.csv" \
     --root "/Volumes/Extreme SSD" \
     --out "/Volumes/Extreme SSD/phosphene_census/full_results.csv" \
     > "/Volumes/Extreme SSD/phosphene_census/full_run.log" 2>&1 &
   ```
   It **skips relpaths already in `--out`** (resume-safe across SIGINT/reboot — just re-run the same command) and graceful-degrades unreadable files to error rows. **Done-when:** the run reaches the manifest end (resume until it does); `full_results.csv` has ~27,639 data rows minus the unreadable; report the analysed / unreadable counts + total wall-clock.

3. **[HARD STOP] Sanity-check the output before writing the report.** Verify: row count ≈ manifest count; unreadable rate ≈ the pilot's **~0.7 %** (a much higher rate = a manifest/decode problem, not a clean run); genre_bucket / decade join keys resolve for a sample. **Stop and report** these coverage numbers to Matt before generating the report.

4. **Extend `census_report.py` to corpus scale + generate `docs/diagnostics/CENSUS_FULL_REPORT.md`.** Re-run the pilot's five sections at full n: (1) octave-folded full-mix-vs-drums disagreement histogram vs the D-154 `0.1` line; (2) mood-feature means/stds vs `mood_scaler.json` (the +38σ flux finding); (3) K-S key-confidence distribution + the F#-minor bias %; (4) per-genre 3-way BPM error census; (5) **drop** the dual-rate section (single-rate full run). Join genre/decade from the full manifest (`/Volumes/Extreme SSD/phosphene_corpus_manifest.csv` — extend the script to read it if it currently assumes the pilot path). **Done-when:** the report renders with corpus-scale n per section + a "**Headline findings & candidate follow-ups**" block mirroring the pilot's — each finding tagged as a candidate for its own D-numbered retune increment, **none applied here**.

5. **Swing/microtiming exploration on the jazz + classical strata** (scope per the DECISION-NEEDED; default = Light). **Light:** from the existing census columns, characterize the jazz + classical subsets' folded-disagreement + bar-confidence distributions against the rest of the library, and quantify how much of each genre the D-154 `0.1` gate excludes from beat-locked presets. **Done-when:** a §Swing/rubato section in the report with the per-stratum distributions + a plain-language read of "how much swing/rubato music the current gate locks out," and a recommendation on whether the **Deep** path (a real swing-ratio measurement) is worth its own follow-up increment.

## Do NOT
- Do NOT change any threshold / scaler / constant — `assessBeatIrregularity` `0.1`, `mood_scaler.json`, the K-S profiles. The census MEASURES; retunes are separate D-numbered increments (scope guard).
- Do NOT commit the results CSV, `full_run.log`, or any per-track data to the repo — SSD only (CENSUS.1–.3 precedent). Only `CENSUS_FULL_REPORT.md` (+ any `census_report.py` change) is in-repo.
- Do NOT run `--dual-rate` on the full corpus (pilot-only; doubles the run for a skew already measured at ~9 %, a DECISIONS-correction candidate, not a re-measure need).
- Do NOT "fix" K-S / mood / beat-grid code — CENSUS.4 reports what they currently produce; corrections are downstream increments the report *seeds*.

## Verification commands
```
swift build -c release --package-path PhospheneEngine 2>&1
swift test --package-path PhospheneEngine --filter "CorpusCensus|assessBeatIrregularity" 2>&1
python3 tools/census_report.py \
  --results "/Volumes/Extreme SSD/phosphene_census/full_results.csv" \
  --manifest "/Volumes/Extreme SSD/phosphene_corpus_manifest.csv" \
  --scaler tools/data/mood_scaler.json \
  --out docs/diagnostics/CENSUS_FULL_REPORT.md \
  --failures "/Volumes/Extreme SSD/phosphene_census/census_failures.log"
```
(+ `swiftlint lint --strict --config .swiftlint.yml` **only if** the Deep-swing path touches Swift.)

## Commit message templates
- `[CENSUS.4] report: full-corpus census (27,639) + swing/rubato exploration` — the report + any `census_report.py` extension.
- `[CENSUS.4] CorpusCensusRunner: <extension>` — **only** if the Deep-swing path adds runner code.
- Small commits per logical step. The results CSV / logs are **never** committed. Push only on Matt's explicit "yes, push."

## Closeout
Invoke `closeout`; produce the 8-part report with the verbatim `Scripts/closeout_evidence.sh` block as §2. **CENSUS-specific additions:** the analysed / unreadable track counts + wall-clock; the report path + its headline findings restated as *candidate* follow-up increments (not applied); an explicit line confirming **no threshold / scaler / constant changed** (the scope guard held). Note that the run + results are SSD-only; only the report is in-repo.

## DECISION-NEEDED — how deep should the swing/rubato investigation go?

**Question:** Should the swing exploration be a quick read of the beat-disagreement data we already have, or add a dedicated swing-ratio measurement?

- **Light — report-only (recommended).** Use the census columns already produced to show how much jazz/classical the current beat gate excludes. *What you'd see:* a clear number — "this much of your swung/rubato music never gets beat-locked visuals" — this session, no extra runtime.
- **Deep — runner extension + a second full pass.** Add per-beat inter-onset-interval capture to the runner and measure an actual swing ratio per track. *What you'd see:* a real "how swung is the library" characterization — but it needs a runner change and another overnight full run.

**Recommendation:** **Light** this session. It answers the product question (how much music the gate locks out) and tells us whether Deep earns its own increment. **Default if no reply:** Light.
