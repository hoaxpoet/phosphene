# Phosphene — Runbook

## Preconditions

- macOS 14.0+ (Sonoma)
- Apple Silicon Mac (M1+)
- Xcode 16+ with Command Line Tools
- Screen capture permission for live audio capture
- Swift 6.0, Metal 3.1+

## Build and Test

```bash
# Build
xcodebuild -scheme PhospheneApp -destination 'platform=macOS' build

# Package tests (PhospheneEngine SPM target)
swift test --package-path PhospheneEngine

# App tests (includes XCTest targets)
xcodebuild -scheme PhospheneApp -destination 'platform=macOS' test

# Lint
swiftlint lint --strict --config .swiftlint.yml
```

**Do NOT pass `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES` on the command line.** It propagates to SPM dependencies and conflicts with `-suppress-warnings`. The flag is enforced per-target via `PhospheneApp/Phosphene.xcconfig`.

## Claude Code Session Checklist

Every session that modifies Swift code must end with all four passing:

1. `swiftlint lint --strict --config .swiftlint.yml`
2. `xcodebuild -scheme PhospheneApp -destination 'platform=macOS' build 2>&1`
3. `swift test --package-path PhospheneEngine 2>&1`
4. All existing tests pass before new code is merged (regression gate)

## First-Launch Checklist

1. Launch app.
2. Check screen capture permission status.
3. Start capture.
4. Confirm non-zero signal (check debug overlay).
5. Confirm render loop active.
6. Confirm debug overlay shows source and signal state.

## Debug Overlay Fields

- Active capture provider
- Permission state
- Signal present / absent (`AudioSignalState`)
- Sample rate
- Current track
- Preparation state
- Current preset
- Frame time / dropped-frame warning

## Common Failure Modes

### App captures silence

Likely causes: screen capture permission not granted, wrong capture mode, process tap misconfigured, DRM-triggered silencing, scrub-induced source teardown.

Checks:
- Call `CGPreflightScreenCaptureAccess()` / `CGRequestScreenCaptureAccess()` before starting capture.
- `AudioHardwareCreateProcessTap` succeeds without permission but delivers zeros.
- Confirm system-wide tap vs per-app tap mode.
- Check `SilenceDetector` state transitions (`.active` → `.suspect` at 1.5s → `.silent` at 3s).
- DRM silence: Apple Music lossless/FairPlay and Spotify DRM can zero out the tap buffer. This is expected — Phosphene degrades to ambient visual mode and monitors for recovery.
- Scrub-induced silence: scrubbing in Spotify / Apple Music tears down the source process's audio session and the existing tap stays alive but delivers permanent silence. `AudioInputRouter` automatically reinstalls the tap on backoff `[3s, 10s, 30s]` after `.silent` is confirmed. Look for `Tap reinstall scheduled` / `Tap reinstall #N succeeded` lines in `session.log` to confirm recovery fired.

### Audio levels too low (raw tap peaks below −15 dBFS)

Likely causes: source app normalization, system-wide attenuation in the routing chain, audio MIDI Setup misconfiguration.

Checks:
- **Spotify**: Settings → Playback → toggle **"Normalize volume"** OFF. Default normalization (-14 LUFS) drops mastered peaks to ~0.15-0.20.
- **Apple Music**: Settings → Playback → toggle **"Sound Check"** OFF.
- **Streaming quality**: pin to **Very High** / **Lossless**, disable any "auto-adjust quality" toggle. Lower bitrates compress dynamic range and flatten transients.
- **Audio MIDI Setup**: if a Multi-Output Device is the system output, all member devices should be at the same sample rate (48 kHz preferred — Phosphene's stem pipeline assumes 44.1/48 kHz internally; 96 kHz forces resampling). Set the *physical* device (e.g., built-in speakers) as Primary and enable Drift Correction on virtual subdevices, not the other way around.
- **Verification**: `raw_tap.wav` (30s Stage-4 capture in each session dir) peak should land at −3 to −9 dBFS for properly mastered tracks with normalization off. Peaks below −15 dBFS point to source-app normalization or routing attenuation. **Do not interpret post-stem-separation WAV spectra as the raw chain** — the stem separator isolates per-instrument content, so a "drums.wav with narrow spectrum" on a drum-sparse track tells you nothing about the chain. Only `raw_tap.wav` reflects what macOS actually delivers to Phosphene.

### Diagnosing signal-chain degradation (proper methodology)

Do not guess at chain culprits from post-processing symptoms. The audio pipeline has distinct stages:

```
Spotify → coreaudiod → CATap → IO proc → AudioBuffer → FFT → StemSeparator → stem WAVs
[Stage 1]  [Stage 2]   [Stage 3] [Stage 4]  [Stage 5]   [Stage 6]  [Stage 7]     [Stage 8]
```

`SessionRecorder` captures **Stage 4** as `raw_tap.wav` (first 30 seconds, IEEE Float32 48 kHz stereo) and **Stage 8** as `stems/<N>_<title>/{drums,bass,vocals,other}.wav`.

To localize degradation:

1. **Spectrum-check `raw_tap.wav`** — this is ground truth for what macOS hands us. If it looks clean here, the issue is in Phosphene or the preset, not the source chain.
2. **If `raw_tap.wav` is degraded**, play a 20 Hz–20 kHz sine sweep through the same chain (YouTube: "20Hz to 20kHz sine sweep stereo"). A clean chain produces a flat spectrum across the sweep duration; any dip localizes the attenuated frequency range.
3. **If the sweep is flat but specific content still looks wrong**, the issue is Spotify/source app — bypass it with a locally-owned FLAC/MP3 through QuickTime and re-capture.
4. **Post-separation stem WAVs are unreliable for chain diagnostics** — they reflect the stem separator's per-instrument isolation, not the mix. A track with minimal drums will produce a narrow-spectrum `drums.wav` regardless of chain quality.

This procedure was established after session 2026-04-17T21-05-47Z, where earlier guesses at Voice Isolation / Multi-Output Device / BT codec degradation were all wrong — `raw_tap.wav` analysis confirmed the chain was clean and Oxytocin's bass-heavy spectrum was the song, not chain loss. Always test Stage 4 before concluding anything about upstream stages.

### Jank / dropped frames

Likely causes: preset too expensive, ML workload colliding with rendering, post-process or particle budget exceeded.

Checks:
- Inspect frame timing in debug overlay.
- Test with simpler preset to isolate.
- Ray march presets with SSGI are the most expensive (~8ms + 1ms overhead at 1080p).
- MPSGraph stem separation runs on GPU — check for contention with heavy render passes. (Increment 6.3 mitigates this; check `ML: dispatch ...` log lines in `session.log` for force-dispatches, which indicate the 2s ceiling was hit under sustained jank.)

### Wrong or missing metadata

Likely causes: streaming app metadata unavailable, API timeout or rate limit, track identity mismatch.

Checks:
- Self-computed MIR is the source of truth — metadata is supplemental.
- MetadataPreFetcher has 3s per-fetcher timeouts.
- PreviewResolver rate limiter: 20 req/60s sliding window.
- Continue with audio-only mode if all external sources fail.

### Preparation takes too long

Likely causes: preview download bottleneck (network), large playlist.

Checks:
- Preview downloads are the bottleneck (~10MB total for 20 tracks).
- Stem separation is ~142ms per track on Apple Silicon.
- Total preparation budget: ~20–30s for a full playlist.
- Progressive readiness is a planned improvement (see ENGINEERING_PLAN.md).

### Stem separation produces garbage

Likely causes: STFT parameter mismatch, weight file corruption.

Checks:
- STFT params: n_fft=4096, hop=1024, sample_rate=44100, 431 frames (~10s).
- Weights: 172 `.bin` files in `ML/Weights/`, tracked via Git LFS. Verify `manifest.json`.
- Performance gate: warm predict must be <400ms.

## Diagnostic Session Captures

Every Phosphene launch creates `~/Documents/phosphene_sessions/<ISO-timestamp>/` and writes diagnostic data continuously while the app runs. Use these to triage user-reported issues (visualizer behaviour, audio dropouts, stem-quality concerns).

**Files:**

- `video.mp4` — H.264 capture of the rendered output, 30 fps. Open in QuickTime / VLC. Writer locks to drawable size after 30 stable frames; mid-session size changes are logged and skipped from video, not blitted into wrong-sized buffers.
- `features.csv` — per-frame `FeatureVector` (60 rows/sec): bass/mid/treble, 6-band, beat onsets, spectral, valence/arousal, accumulatedAudioTime.
- `stems.csv` — per-frame `StemFeatures`: drums/bass/vocals/other × {energy, beat, band0, band1}.
- `stems/<NNNN>_<title>/{drums,bass,vocals,other}.wav` — listenable mono PCM dump per stem-separation cycle. Good for verifying separation quality on a real track.
- `session.log` — startup banner, signal state transitions, track changes, preset changes, video writer state.

**Triage isolation rules** (when a session looks wrong):

| Symptom | Most likely root cause |
|---|---|
| `features.csv` all zeros during music | App audio path broken (tap silent, MIR not running) |
| `features.csv` non-zero but `video.mp4` black | Capture blit broken in recorder |
| `video.mp4` matches what user saw | Recorder works end-to-end; problem is upstream (visualizer or audio) |
| `stems/*.wav` silent when drums clearly audible | Stem separator broken |
| `stems/*.wav` contain real audio | Separation works |
| `session.log` missing startup banner | Recorder failed to initialize (disk, permissions, path writable?) |
| `session.log` has `Tap reinstall scheduled` entries | Audio path saw silence; check whether reinstall succeeded |
| `video frame skipped: drawable WxH != writer WxH` log lines | Drawable size changed mid-session (window resize) |

**Quitting cleanly matters.** `AVAssetWriter.finishWriting` is called from an `NSApplication.willTerminateNotification` observer in `VisualizerEngine.init`. Force-quitting the app (Activity Monitor, kill -9) skips this and leaves `video.mp4` without its `moov` atom — unplayable. Use ⌘Q.

## Operational Rules

- Never block the render loop on network or ML work.
- Never allocate in the real-time audio callback.
- Never assume metadata is correct — cross-reference with MIR.
- Never let beat pulses dominate motion.
- Never ship a preset without a performance profile.
- Never use `print()` — use `os.Logger` via `Shared/Logging.swift`.
- Never use `.storageModeManaged` buffers.
- Never use `CATapDescription(stereoMixdownOfProcesses: [])` with an empty array (silence). Use `CATapDescription(stereoGlobalTapButExcludeProcesses: [])`.
- App sandbox is disabled (`com.apple.security.app-sandbox = false`).
- Any preset that includes `mv_warp` in its `passes` array must implement `mvWarpPerFrame()` and `mvWarpPerVertex()` in its `.metal` file. Missing implementations cause a linker error at preset-library compile time. See `VolumetricLithograph.metal` or `Starburst.metal` for reference implementations.
- New ray-march presets should include `mv_warp` in their passes unless there is a deliberate reason not to. Without per-vertex feedback accumulation, ray-march presets show only instantaneous audio state regardless of how sophisticated the shader drivers are (MV-2, D-027).

## Running a Soak Test (Increment 7.1)

### Quick smoke run (60 seconds, in test suite)

```bash
SOAK_TESTS=1 swift test --package-path PhospheneEngine --filter SoakTestHarnessTests
```

Reports are written to `$TMPDIR/phosphene_soak_smoke_<timestamp>/`.

### 5-minute memory check (in test suite)

```bash
SOAK_TESTS=1 swift test --package-path PhospheneEngine --filter "SoakTestHarnessTests/fiveMinuteMemoryCheck"
```

### Full 2-hour production run (CLI, with App Nap prevention)

```bash
Scripts/run_soak_test.sh
```

The script builds `SoakRunner` in release mode, then runs:
```bash
caffeinate -i .build/release/SoakRunner --duration 7200
```

Reports are written to `~/Documents/phosphene_soak/<ISO-timestamp>/report.json` and `report.md`.

### Custom run (shorter duration for iteration)

```bash
swift build --package-path PhospheneEngine --configuration release --product SoakRunner
caffeinate -i PhospheneEngine/.build/release/SoakRunner \
  --duration 300 \
  --sample-interval 30 \
  --audio-file /path/to/loop.wav
```

### Interpreting the report

| `finalAssessment` | Meaning |
|---|---|
| `pass` | No alerts fired |
| `passWithSoftAlerts` | Soft thresholds crossed (memory, drops, downshifts, ML force) — informational |
| `hardFailure` | `MemoryReporter` returned nil > 5 times — indicates Mach kernel API failure |

**Soft alert thresholds (defaults):**
- Memory growth from baseline: 50 MB
- Dropped frames: 60/hour
- Quality governor downshifts: > 3
- ML force dispatches: > 10/hour

Pass these as `SoakTestHarness.Configuration` overrides for different workloads.
