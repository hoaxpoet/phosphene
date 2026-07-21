Execute Increment CENSUS.2 — CorpusCensusRunner (batch analysis harness).

Authoritative spec: docs/ENGINEERING_PLAN.md §Phase CENSUS §CENSUS.2.
Background + rationale: docs/research/CORPUS_ML_OPPORTUNITIES.md §4, §5, §8
(read these two sections first — the census exists to serve them).

────────────────────────────────────────
PRECONDITIONS
────────────────────────────────────────

1. CENSUS.1 must have landed. Verify:
   `test -f tools/data/corpus_pilot_1000.csv && test -f tools/corpus_manifest.py`
   Both must exist. If the CENSUS.1 artifacts are uncommitted working-tree
   files, commit them FIRST as `[CENSUS.1] tools: corpus manifest + stratified
   pilot` (run the doc gates; they touch no Swift).

2. The corpus volume must be mounted. Verify:
   `test -f "/Volumes/Extreme SSD/phosphene_corpus_manifest.csv"`
   If the mount point differs, every command below takes the root explicitly —
   do NOT hardcode the volume name in Swift.

3. Confirm the APIs you will reuse are where this prompt says they are:
   - `grep -n "func runBeatThis\|func extractSamples" \
      PhospheneEngine/Sources/QualityReelAnalyzer/*.swift`
     — the offline decode → BeatThis pattern to mirror (22050 Hz mono input).
   - `grep -n "public func assessBeatIrregularity" \
      PhospheneEngine/Sources/Session/BPMMismatchCheck.swift`
     — signature: `(gridBPM: Double, drumsBPM: Double, barConfidence: Float,
       foldedDisagreementThreshold: Double = 0.10, barConfidenceFloor:
       Float = 0.2) -> Bool?`.
   - `grep -n "featureCount = 10" PhospheneEngine/Sources/ML/MoodClassifier.swift`
     — the 10-feature input contract (6-band energy, centroid, flux,
       major/minor K-S correlations).
   - MIRPipeline init takes `sampleRate:` (default 48000) — the census decodes
     at FILE-NATIVE rate; pass the real rate, mirroring the LF path.

4. Decision-ID check: this increment makes NO threshold/behaviour changes and
   needs NO new D-number. If implementation pressure pushes toward changing
   any production constant, STOP and report (scope guard in the EP phase
   header: the census measures; retunes are separate increments).

────────────────────────────────────────
DELIVERABLE
────────────────────────────────────────

New `executableTarget` **CorpusCensusRunner** in PhospheneEngine/Package.swift
(pattern: QualityReelAnalyzer — deps DSP, ML, Session, ArgumentParser;
path Sources/CorpusCensusRunner). Retained-diagnostic, zero production
importers BY DESIGN — add it to docs/AUDIT_KEEPLIST.md in this increment.

CLI:

  .build/release/CorpusCensusRunner \
    --root "/Volumes/Extreme SSD" \
    --manifest tools/data/corpus_pilot_1000.csv \
    --out "/Volumes/Extreme SSD/phosphene_census/pilot_results.csv" \
    [--limit N] [--dual-rate] [--window-seconds 30]

Behaviour per manifest row (relpath column; join against --root):

1. **Decode** via AVAudioFile at file-native rate, mono-mixed, first
   `--window-seconds` (default 30 — the preview-equivalent window production
   analyzes; document in --help that this is deliberate parity, not laziness).
   Decode failures → one row in `<out-dir>/census_failures.log`
   (relpath + error), continue. NO ffmpeg dependency — these are audio
   containers AVFoundation handles natively (mp3/m4a/flac on macOS 14).

2. **Full-mix BeatGrid**: resample the window to 22050 Hz mono →
   BeatThisPreprocessor → BeatThisModel → BeatGridResolver (mirror
   QualityReelAnalyzer's `runBeatThis`; reuse one model instance across
   tracks — PREPPERF.2 proved graph reuse matters).

3. **Drums grid**: StemSeparator on the (first 10 s of the) window → drums
   stem → same BeatThis path. Record `drums_bpm`.

4. **Irregularity — record the CONTINUOUS evidence, not just the verdict**:
   compute the octave-folded disagreement exactly as `assessBeatIrregularity`
   does (fold ratio into [1,2), distance to nearer of {1.0, 2.0}) and write
   the raw value; also call the production function and write its Bool?.
   The folding arithmetic must NOT be reimplemented-and-drifted: extract it
   from `assessBeatIrregularity` into a small pure
   `public func foldedBPMDisagreement(_ a: Double, _ b: Double) -> Double?`
   in BPMMismatchCheck.swift that both the production gate and the census
   call (behaviour-identical refactor; existing tests must stay green and a
   new unit test pins fold values incl. the just-under-2.0 edge).

5. **MIR features**: run MIRPipeline (file-native rate) over the window;
   aggregate the MoodClassifier's 10 input features as means across frames;
   run MoodClassifier once on the aggregated vector → valence/arousal.
   Also record the K-S key class + major/minor correlations and MIRPipeline's
   own tempo estimate (`mir_bpm`) for the 3-way census.

6. **Output row** (append; header written once):
   relpath, duration_s, native_rate, window_s,
   grid_bpm, grid_beat_count, bar_confidence,
   drums_bpm, folded_disagreement, beat_irregular,
   mir_bpm,
   valence, arousal, feat0…feat9 (10 columns, pre-normalization means),
   key_class, key_major_r, key_minor_r,
   error (empty on success).

7. **Resumability**: before running, read --out if it exists and skip
   relpaths already present. Append-only writes, flushed per row. A killed
   run must resume losslessly.

8. **--dual-rate** (pilot only): decode the SAME window at 44100 AND 48000 Hz
   (AVAudioConverter), run step 5 at both rates, emit two extra rows with
   relpath suffixed `#44100` / `#48000`. This feeds the D-numbered LF-vs-tap
   mood-skew calibration (DECISIONS: sample-rate delta, spectralCentroid
   ~22 % → valence +34 % / arousal −38 %).

CSV writing: fields containing commas/quotes are quoted per RFC 4180 —
artist/album paths WILL contain commas (e.g. "Goodnight, Texas").

────────────────────────────────────────
TESTS (engine SPM suite)
────────────────────────────────────────

Pure-function units (no Metal, no audio files):
- `foldedBPMDisagreement`: 1:1 → 0; exact octave (2:1, 4:1) → ~0; 57 % raw →
  ~0.17 folded (the Pyramid Song case from the D-154 narrative); just-under-
  2.0 fold edge → near 0; non-finite/zero → nil.
- `assessBeatIrregularity` behaviour unchanged (existing tests green).
- CSV row escaping round-trip (comma, quote, unicode path).
- Resume-set parsing: given a partial results CSV, already-done relpaths are
  skipped (including `#44100`-suffixed dual-rate rows).
- Manifest parsing: header validation + graceful skip of rows whose
  tag_status ≠ ok.

Integration (Metal-gated, mirrors existing model-test conventions): one
end-to-end run over a committed short synthetic-tone fixture is NOT
acceptable evidence for this harness (FA #27 — synthetic audio proves
nothing about real-music behaviour). Instead the done-when requires a
DEV-LOCAL run on ≥10 real corpus files (see below); the committed test suite
covers the pure functions + a decode-and-shape smoke on an existing repo
audio fixture if one exists (check TestFixtures/ before adding anything).

────────────────────────────────────────
DONE-WHEN
────────────────────────────────────────

- `swift build -c release --package-path PhospheneEngine` succeeds;
  full engine test suite green; app build unaffected (no app-target files
  touched); `swiftlint lint --strict` 0 on touched files.
- Dev-local evidence in the closeout: CorpusCensusRunner over ≥10 real
  corpus files (mixed mp3/m4a/flac) — paste the output rows; BPMs sane
  (60–200), no empty feature columns, at least one FLAC and one 48 kHz
  file among them; kill-and-resume demonstrated (run, ctrl-C mid-run,
  rerun, row count correct with no duplicates).
- docs updated: ENGINEERING_PLAN CENSUS.2 row flipped with evidence;
  AUDIT_KEEPLIST entry; ARCHITECTURE Module Map row for the new target
  (match the QualityReelAnalyzer row's shape); RELEASE_NOTES_DEV entry.
- Closeout report per CLAUDE.md protocol (Scripts/closeout_evidence.sh
  block verbatim; commit `[CENSUS.2] tools: corpus census runner`;
  NO push without Matt's explicit approval).

────────────────────────────────────────
GUARDRAILS
────────────────────────────────────────

- Do NOT modify production analysis behaviour. The only production-file
  change permitted is the behaviour-identical `foldedBPMDisagreement`
  extraction in BPMMismatchCheck.swift.
- Do NOT add dependencies beyond what Package.swift already has.
- Results CSVs and failure logs live on the corpus volume, never in the
  repo (repo gets tools + the pilot manifest only; the pilot RESULTS go to
  docs/diagnostics only in CENSUS.3, summarized).
- If per-track wall clock exceeds ~5 s in the dev-local run, report the
  stage split (reuse the PREPPERF TIMING pattern ad hoc) before optimizing
  anything — measure, don't guess.
- Anything pushing toward architectural change (e.g. making StemSeparator
  concurrent): stop and report, per the standing protocol.
