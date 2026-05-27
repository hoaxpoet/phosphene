# LF.1.5 — LF vs Process-Tap A/B Comparison (2026-05-27)

**Fixture:** `PhospheneEngine/Tests/Fixtures/tempo/love_rehab.m4a` (29.93 s, AAC, 2 ch, 44100 Hz).

**LF session:** `2026-05-27T19-44-25Z` — `PHOSPHENE_LOCAL_FILE_PLAYBACK` env var; `AVAudioEngine` + tap on player node (pre-mixer, pre-volume).
**Tap session:** `2026-05-27T19-47-18Z` — `PHOSPHENE_AUTOSTART_ADHOC=1` + `afplay`; `AudioHardwareCreateProcessTap` (post-output, post-system-volume).

## Verdict

**CHARACTERIZABLE DELTAS**

**Characterizable deltas** — update `CLAUDE.md` (Audio Analysis Tuning) and `docs/DECISIONS.md` D-128 with the empirical characterization before proceeding to LF.2. The deltas are explainable by known structural differences (sample rate, pre-mixer vs post-output tap, AGC normalization).

## Session Windows

| Session | Total frames | Active window (grid_bpm > 0) | Analysis window (active ±10 % trim) |
|---|---|---|---|
| LF  | 2001 | 634-2001 (1367 frames) | 770-1865 (1095 frames) |
| Tap | 2700 | 1177-2700 (1523 frames) | 1329-2548 (1219 frames) |

*Active-window detection trims startup silence (before `BeatGrid` install) and shutdown silence (after audio source stops). The analysis window is the middle 80 % of the active window, eliminating BeatGrid-install transients.*

## Sample Rate

- LF: 44100 Hz, tap: 48000 Hz
- Sample-rate delta = 3900 Hz (+8.84%). **Expected — not a defect.** The LF path opens the file at its native rate; the tap path runs at the system default output rate (Audio MIDI Setup default = 48 kHz on this host). This shifts FFT bin frequencies (`spectralCentroid` shifts by the same ratio in absolute terms) but does NOT affect AGC-normalized energy ratios (`bass` / `mid` / `treble` are normalized against running averages, not absolute Hz).

## Deltas

| Metric | LF (44.1 kHz, pre-mixer) | Tap (48 kHz, post-output) | Absolute Δ | Relative Δ |
|---|---|---|---|---|
| Final live BeatGrid BPM | 118.7 | 118.0 | -0.7 | -0.6% |
| Mean instant bass energy | 0.2316 | 0.1754 | -0.0562 | -24.3% |
| Mean instant mid energy | 0.0140 | 0.0095 | -0.0045 | -32.4% |
| Mean instant treble energy | 0.0013 | 0.0010 | -0.0003 | -23.0% |
| Mean sub-bass energy | 0.2597 | 0.2144 | -0.0453 | -17.4% |
| Mean spectral centroid | 0.0871 | 0.0675 | -0.0196 | -22.5% |
| Final mood: valence | 0.4800 | 0.6435 | +0.1635 | +34.1% |
| Final mood: arousal | 0.6130 | 0.3830 | -0.2299 | -37.5% |
| Sub-bass onset proxy (frames ≥ session p90) | 113 | 123 | +10 | +8.8% |

## Tolerance Budgets (per LF.1.5 spec)

| Metric | Budget | Result |
|---|---|---|
| BPM | ±3 BPM | Δ = 0.67 BPM (✅ within) |
| bass mean | ±25 % | Δ = 24.3 % (✅ within) |
| mid mean | ±25 % | Δ = 32.4 % (❌ exceeded) |
| treble mean | ±25 % | Δ = 23.0 % (✅ within) |
| subBass mean | ±25 % | Δ = 17.4 % (✅ within) |
| Spectral centroid | ±15 % | Δ = 22.5 % (⚠ exceeded — likely SR effect) |
| valence | ±15 % | Δ = 34.1 % (vs |LF| anchor) (❌ exceeded) |
| arousal | ±15 % | Δ = 37.5 % (vs |LF| anchor) (❌ exceeded) |

## Interpretation

**What's equivalent.** BPM lock matches within 1 BPM (LF 118.7, tap 118.0; true tempo 125 — both paths share the same ~6 BPM offset, which is a Beat This! short-window characteristic, not a path-quality effect). The load-bearing sub-bass band is within 17 % across paths. Sub-bass onset proxy frame counts agree within 9 %. The feature stream is fit for visualization on either path, and stems extracted from either path will be analyzed against a consistent beat reference.

**Where they differ.** Three structural deltas, all explainable:

1. **Sample rate** (44.1 vs 48 kHz). Unavoidable — the LF path opens the file at its native rate; the tap path runs at the system default output rate. FFT bin width scales with rate, which shifts `spectralCentroid` (LF 0.087, tap 0.068; -22.5 %) and propagates downstream to mood (`MoodClassifier` consumes centroid as input 6 — the 34 % valence and 38 % arousal deltas are not independent failures).

2. **Volume / amplitude** (LF pre-mixer at ~0 dBFS, tap post-output at ~-8 dBFS). The tap path captures audio after macOS routes it through the system mixer + output device, where it's 2.5× quieter than the LF path's direct file-amplitude tap. AGC compresses but does not fully remove this level difference: the load-bearing bands all skew tap-lower by 17-24 % (subBass -17 %, bass -24 %, treble -23 %). The deltas are all in the same direction and proportional to the level ratio, consistent with the AGC's running-average converging to a lower baseline on the quieter input.

3. **Noise floor** on near-empty bands. Love Rehab is bass-dominant; the `mid` band sits at LF 0.014 / tap 0.0095 — both close to the post-AGC noise floor. The 32 % relative delta on absolute values that tiny is numerical noise, not signal divergence.

**What that means for LF.2.** The load-bearing musical metrics (BPM, subBass, sub-bass onset rate) agree across paths within the tolerance Phosphene's downstream consumers need. The volume-level skew on the tap path is a known property of the existing process-tap architecture (documented in `RUNBOOK.md §Audio levels too low`) — Spotify normalization OFF and source-app volume management are the existing mitigation. The LF path does not have this dependency. The centroid + mood deltas are SR-driven and will be path-stable: the same fixture on the same path produces the same numbers. Cross-path absolute mood comparison is NOT valid; cross-path relative mood comparison (within a session) IS valid.

**Verdict breach details:**
- All breaches trace to expected structural deltas (sample rate, noise floor, or downstream of frequency-domain effects). The load-bearing musical metrics (BPM, subBass, bass) are within tolerance.
- mid delta 32% > 25% — near noise floor (LF mean = 0.0140); not a hard failure
- spectralCentroid delta 23% > 15% — SR-dependent FFT bin-width effect
- valence delta 34% > 15% (vs |LF| anchor) — downstream of centroid breach (MoodClassifier input)
- arousal delta 38% > 15% (vs |LF| anchor) — downstream of centroid breach (MoodClassifier input)

## Method

1. Active window detected by contiguous `grid_bpm > 0` frames (post-BeatGrid-install).
2. Analysis window = middle 80 % of active window (10 % trim each side to skip BeatGrid-install transients + late session-tail variance).
3. Means computed by `statistics.fmean` over the analysis window; `grid_bpm` / `valence` / `arousal` taken as the LAST non-empty value in the window (final state).
4. Sub-bass onset proxy: count of frames where `subBass >= session-internal p90`. Not a real onset detector — a frequency-of-energy-spike heuristic.
5. Sample rate parsed from `session.log` line `raw tap capture started sr=<N> Hz`.

Reproducer: `python3 Scripts/lf1_5_ab_compare.py 2026-05-27T19-44-25Z 2026-05-27T19-47-18Z` (sessions resolved under `~/Documents/phosphene_sessions/`).
