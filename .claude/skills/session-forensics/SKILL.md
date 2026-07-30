---
name: session-forensics
description: Invoke when analyzing recorded Phosphene sessions (features.csv, stems.csv, raw_tap.wav, session.log) or choosing/using the diagnostic CLIs (TempoDumpRunner, ColdStartVerifier, PresetSessionReplay, BeatThisActivationDumper, QualityReelAnalyzer, BeatBench). Enforces replay-before-live.
---

# session-forensics — recorded sessions + the diagnostic CLIs

Recorded sessions and the offline CLIs are how a beat-sync change is validated *before* a live capture is requested. Live captures and Matt's review time are the scarce resource; replay is not. Load this before reaching for a live run.

## 1. Session directory anatomy

A `SessionRecorder` capture (auto-on per session) writes a session directory containing:

- **`features.csv`** — per-frame `FeatureVector` (see `docs/ARCHITECTURE.md` §Session Recording for the authoritative schema). Beat-relevant columns: **`drift_ms`** (live tracker residual), **`lock_state`** (0/1/2 lock quality), **`grid_bpm`** (installed grid tempo), **`barPhase01_permille`** (bar phase ×1000, the dsp.beat artifact set), and the FBS pulse columns **`pulse_phase01`** / **`pulse_amp01`**.
- **`stems.csv`** — per-frame `StemFeatures` (vocals/drums/bass/other × energy/band/beat/deviation/onset/centroid…). Drums-stem onset behaviour is the TRK.2 evidence surface.
- **`raw_tap.wav`** — the raw system-audio tap PCM. The replay substrate: re-decode it to re-run a tracker/decoder offline, or run a reference tool on it for ground truth (BEAT_SYNC.md Component 5b).
- **`session.log`** — startup banner, signal `.active/.suspect/.silent` transitions, track/preset changes, and the `WIRING:`-prefixed beat-grid + BPM-disagreement trail.

(Distinct from the `R`-shortcut `~/phosphene_features.csv` MIR-only path — different schema/cadence; not interchangeable.)

## 2. CLI inventory

Every invocation's flags were read this session directly from each tool's `@main` `ParsableCommand` `@Option`/`@Flag` declarations (argument-parser derives `--kebab-case` from camelCase property names); executable target names confirmed against `PhospheneEngine/Package.swift`. Run form: `swift run --package-path PhospheneEngine <Target> …`.

| Tool | Answers the question… | Verified one-line invocation |
|---|---|---|
| **TempoDumpRunner** | What IOI/tempo does BeatDetector derive from this audio file offline? (per-band IOI histogram + autocorrelation BPM) | `swift run --package-path PhospheneEngine TempoDumpRunner --audio-file <path> --label <name> --out <dump.txt> [--metadata-bpm <bpm>]` |
| **ColdStartVerifier** | How well does a captured session's cold-start beat sync align to Beat This! ground truth? (default = session verify) | `swift run --package-path PhospheneEngine ColdStartVerifier --session <dir> [--out <report.md>]` |
| ↳ ColdStartVerifier modes | Short-window Beat This! accuracy / within-capture position stability / cross-capture reproducibility / accent-window pass-rate / arithmetic self-check | append one of `--rediagnose [--rediagnose-windows 3,4,5]` · `--position-sweep` · `--cross-capture --sessions <a,b,c>` · `--accent-window-pass-rate` · `--self-test` |
| **PresetSessionReplay** | How did a preset's audio→visual routes fire on a recorded session, and does it score against the cert rubric? | `swift run --package-path PhospheneEngine PresetSessionReplay --session <dir> --preset <name> [--output <dir>] [--references-dir <dir>]` |
| **BeatThisActivationDumper** | What are Beat This!'s per-frame activations on this audio, for cross-validation against the PyTorch reference? | `swift run --package-path PhospheneEngine BeatThisActivationDumper --audio <path> --out <activations.json> [--raw-dir <dir>]` |
| **QualityReelAnalyzer** | How beat-reactive is a rendered quality reel — do visual events land on the beat grid? | `swift run --package-path PhospheneEngine QualityReelAnalyzer --reel <video> --out <report.md> --frames-dir <dir> [--audio <path>] [--max-beats N] [--audio-only]` |
| **BeatBench** | How does a beat grid score against the tapped ground truth? (metrics + targets: `beatbench`) | `swift run --package-path PhospheneEngine BeatBench --mode offline-grid [--tracks <ids>] [--report <path>]`; `--audio <file> [--seconds N]` inspects one file's grid; `--self-test` validates the metrics. **session-replay mode is not built yet** — live-path metrics have no baseline. |

## 3. Replay-before-live (rule, not advice)

**Any tracker or decoder change is validated against recorded sessions before a live capture or M7 is requested.** Build and tune against `raw_tap.wav` replay + `features.csv` (the `LiveDriftValidationTests` / BUG-065 Cherub-capture pattern); only after the replay gate is green do you ask Matt to record or review. This is the M7-bottleneck guard (plan §7): live captures and Matt's review time are the program's scarcest resource, and a change that fails on replay would waste both.

## 4. Capture-request protocol

When replay is green and a live capture is genuinely needed:

- **What to ask Matt to record** — name the specific tracks (from the relevant BeatBench suite) and the path (streaming vs local file); state what the capture must exercise (e.g. a gapless segue, a mid-song tempo change) so the session actually contains the phenomenon.
- **Where sessions land** — the `SessionRecorder` output directory; captures are timestamp-named (`YYYY-MM-DDTHH-MM-SSZ`). Reference a capture by that stamp in closeouts and BeatBench runs.
- **One capture, many questions** — a single recorded session feeds every offline CLI above; prefer re-analyzing an existing capture to requesting a fresh one.
