# Phosphene — Architecture

## Overview

Phosphene is a native Swift/Metal macOS application with a modular engine architecture. Its major subsystems are:

- Audio capture and routing
- Buffering and FFT
- MIR / DSP analysis
- ML-powered stem separation
- Metadata and playlist preparation
- Renderer and preset system
- Orchestrator and session planning (increments 4.1–4.3 complete: scorer, transition policy, session planner; golden fixtures and live adaptation forthcoming)
- App shell and UI

## Architectural Principles

**Native macOS stack only.** Swift, Metal, Accelerate, Core Audio, and Apple system frameworks. No third-party audio capture, no virtual audio drivers, no cross-platform abstractions.

**Local-only processing.** Audio analysis, stem separation, preference learning, and all adaptation remain on-device. No cloud, no telemetry.

**Protocol-oriented design.** Cross-module dependencies are injected via protocols (`AudioCapturing`, `AudioBuffering`, `FFTProcessing`, `Rendering`, `MetadataProviding`, `MetadataFetching`, `StemSeparating`, `MoodClassifying`, `PlaylistConnecting`, `PreviewResolving`, `PreviewDownloading`). All tests use doubles from `Tests/TestDoubles/`.

**UMA-first memory model.** All shared buffers between CPU, GPU, and ML use `MTLResourceOptions.storageModeShared` (zero-copy). Never `.storageModePrivate` or `.storageModeManaged` unless GPU-exclusive.

**Non-blocking render path.** Rendering must never wait on network calls, metadata fetches, or ML inference.

## System Diagram

```
Playlist / streaming source
→ SessionManager (idle → connecting → preparing → ready → playing → ended)
  → PlaylistConnector (AppleScript / Spotify Web API)
  → PreviewResolver (iTunes Search API) → PreviewDownloader (AVAudioFile decode)
  → SessionPreparer (stem separation + MIR per track)
  → StemCache + TrackProfile → Session plan

Live audio capture (Core Audio tap)
→ AudioInputRouter → AudioBuffer (UMARingBuffer)
→ FFTProcessor (vDSP 1024-point → 512 bins)
→ MIRPipeline (BandEnergy + BeatDetector + Chroma + Spectral + Structural)
→ StemSeparator (MPSGraph, background 5s cadence)
→ AnalyzedFrame (FeatureVector + StemFeatures + EmotionalState)
# LookaheadBuffer (2.5s analysis/render split) — planned anticipatory architecture; not yet wired.
# AudioInputRouter declares onAnalysisFrame / onRenderFrame callbacks but no production
# code assigns them. See docs/CAPABILITY_REGISTRY/AUDIO.md (CA-Audio-FU-2) — Matt's
# product call needed on whether to wire, keep as infrastructure, or retire.

→ Orchestrator (session mode or ad-hoc mode)
→ RenderPipeline (Metal)
→ Preset output
```

## Audio Capture

Phosphene uses a provider-oriented capture architecture. The current default provider is Core Audio taps via `AudioHardwareCreateProcessTap` (macOS 14.2+).

Supported capture modes (abstracted by `AudioInputRouter`):

- `.systemAudio` — system-wide Core Audio process tap (default)
- `.application(bundleIdentifier:)` — per-app Core Audio process tap
- `.localFile(URL)` — diagnostic PCM injection from a file; does NOT play audio through speakers. Used by `SoakTestHarness` (the `CaptureMode.localFile` settings toggle that also used it was removed in CLEAN.2.3.2).
- `.localFilePlayback(URL)` — `AVAudioEngine`-based playback through the default output device with a tap on the player node (pre-mixer, pre-volume). Bypasses Core Audio process taps entirely — no screen-capture permission required. LF.1 spike (D-128). Activated at app launch via the `PHOSPHENE_LOCAL_FILE_PLAYBACK` env var; `VisualizerEngine.startLocalFilePlayback(url:)` transitions the session to ad-hoc and skips `startAudio()`'s tap path.

Operational requirements:

- Screen capture permission is required for non-zero audio delivery on the process-tap modes (`.systemAudio`, `.application`). `AudioHardwareCreateProcessTap` succeeds without permission but delivers silence. The `.localFilePlayback` mode is the exception — it bypasses the tap.
- Capture must not allocate or block on the real-time audio thread.
- DRM silence detection via `SilenceDetector` monitors for sustained zero-energy frames and transitions to ambient visual mode.
- Tap input quality is continuously assessed by `InputLevelMonitor`: rolling peak dBFS (21 s window) and 3-band spectral balance EMAs → `SignalQuality` (green/yellow/red). Classification is peak-only — treble-ratio thresholds were removed after they produced false positives on bass-heavy tracks. Quality transitions are logged to session.log with 30-frame hysteresis to prevent flapping.

**Tap recovery on prolonged silence.** Streaming-app scrubs frequently break the process tap — the tap stays alive but delivers permanent silence after the source process tears down and reopens its audio session on seek. `AudioInputRouter` watches the silence detector and, after `.silent` persists, schedules a tap reinstall on a backoff schedule (3 s → 10 s → 30 s, three attempts). Each attempt destroys the existing tap + aggregate device and creates a fresh one for the active capture mode. If audio resumes (either on the existing tap or a freshly-installed one) the silence detector transitions through `.recovering → .active` and the reinstall sequence is cancelled. After three exhausted attempts, prolonged silence is treated as a real pause and reinstall stops until the next active → silent transition.

## Audio Analysis Hierarchy

This ordering is the most important design rule in the project. Continuous-energy-dominant designs feel locked to the music. Beat-dominant designs feel out of sync.

1. **Continuous energy bands** (primary visual driver) — bass/mid/treble (3-band) and 6-band equivalents. Zero detection delay.
2. **Spectrum and waveform buffers** (richest data) — 512 FFT magnitude bins + 1024 waveform samples sent to GPU as buffer data.
3. **Spectral features** (derived characteristics) — centroid, flux, rolloff, MFCCs, chroma.
4. **Beat onset pulses** (accent only, never primary) — discrete accent events with ±80ms jitter. Feedback amplifies this jitter.
5. **Stems** — ML-separated vocals/drums/bass/other. Pre-analyzed from preview clips (available from first frame in session mode). Replaced by time-aligned live stems after ~10s.

**MIR pipeline components** (`DSP` module):

- `BandEnergyProcessor` — Milkdrop-style AGC (output = raw / runningAverage × 0.5). 3-band and 6-band per frame. Deviation primitives `xRel`/`xDev` exposed in `FeatureVector` (D-026).
- `BeatDetector` — 6-band onset detection with per-band cooldowns and grouped pulses; tempo via IOI histogram (sub_bass-only timestamps per D-075) + autocorrelation fallback.
- `LiveBeatDriftTracker` (DSP.2 S7) — **primary beat-phase path when an offline `BeatGrid` is installed.** Cross-correlates `BeatDetector`'s sub_bass onset stream against the cached grid in a ±50 ms window, EMA-tracks drift, and computes `beatPhase01` / `beatsUntilNext` / `barPhase01` / `beatsPerBar` analytically. The BUG-007.x cluster of fixes (lock hysteresis, per-track grid-onset calibration, audio-output-latency compensation, bar-phase auto-rotate, hybrid runtime recalibration) all live here.
- `BeatPredictor` (MV-3b) — **reactive-mode fallback** when no offline grid is installed. IIR period smoother on onset rising edges. Writes `beatPhase01` (0→1 per inter-beat interval) and `beatsUntilNext` to `FeatureVector`.
- `ChromaExtractor` — 12-bin chroma with bin-count normalization; Krumhansl-Schmuckler key estimation (24 profiles).
- `SpectralAnalyzer` — centroid, rolloff, flux via vDSP.
- `StructuralAnalyzer` / `NoveltyDetector` / `SelfSimilarityMatrix` — section-boundary detection. Self-similarity matrix (600-frame × 16-feature ring buffer) feeds checkerboard-kernel novelty detection (every 30 frames) → `StructuralPrediction`. **Audit note (CA.1, 2026-05-20):** this chain runs per frame in `MIRPipeline.process` but its output (`latestStructuralPrediction`) is currently consumed only at *preparation time* by `SessionPreparer`; the runtime per-frame work has no live reader. Tracked as a CA-future cleanup.
- `StemAnalyzer` — per-stem `BandEnergyProcessor` + `BeatDetector` on drums + rich metadata (onset rate, centroid, attack ratio, energy slope) via fast/slow RMS EMAs + `PitchTracker` on vocals. Runs at audio-callback rate (~94 Hz) on a sliding 1024-sample window.
- `PitchTracker` (MV-3c) — YIN autocorrelation (vDSP_dotpr, 2048-sample window). Key implementation detail: after finding the first CMNDF crossing below threshold, the algorithm advances to the local minimum before parabolic interpolation — stopping at the crossing causes catastrophic extrapolation on the descending slope. Live caller passes 1024-sample windows; an internal 2048-sample ring buffer accumulates before YIN runs (the **PT.1 fix, 2026-05-19**: pre-fix the live path zero-padded the buffer and `vocalsPitchConfidence` was structurally 0 for ~5 months). Exposes `vocalsPitchHz`/`vocalsPitchConfidence` in `StemFeatures`.
- `MIRPipeline` — coordinator: builds `FeatureVector` from all the above each frame. Picks `LiveBeatDriftTracker` over `BeatPredictor` whenever `liveDriftTracker.hasGrid == true`.

**`StemFeatures` layout** (GPU buffer(3), 64 floats = 256 bytes):
- Floats 1–16: per-stem energy, band0, band1, beat (four stems).
- Floats 17–24: MV-1 deviation primitives (`{vocals,drums,bass,other}EnergyRel/Dev`).
- Floats 25–40: MV-3a rich metadata (`{vocals,drums,bass,other}{OnsetRate,Centroid,AttackRatio,EnergySlope}`).
- Floats 41–42: MV-3c vocal pitch (`vocalsPitchHz`, `vocalsPitchConfidence`).
- Floats 43–64: padding.

Rule: `base_zoom` and `base_rot` (continuous energy) should be 2–4× larger than `beat_zoom` and `beat_rot` (onset pulses).

## Session Lifecycle

`SessionManager` (`@MainActor ObservableObject`, `Session` module) owns the session lifecycle and coordinates `PlaylistConnector`, `SessionPreparer`, and `StemCache`.

**States:** `idle` → `connecting` → `preparing` → `ready` → `playing` → `ended`

**Degradation:** if the playlist connection fails, the manager transitions directly to `ready` with an empty plan (live-only reactive mode). If individual track preparation fails, `ready` is reached with a partial plan — uncached tracks fall back to real-time stem separation.

**Ad-hoc mode:** `startAdHocSession()` transitions directly to `playing`, skipping playlist preparation entirely.

## Session Preparation

When a playlist is available, `SessionManager.startSession(source:)` (Apple Music path) or `SessionManager.startSession(preFetchedTracks:source:)` (Spotify OAuth path, D-070 Bug 2) drives the pipeline below. App-side OAuth-pre-fetched tracks skip step 1; everything else is shared.

1. **Connect** — read the ordered track list via `PlaylistConnector` (Apple Music AppleScript or Spotify Web API). Skipped when the App layer pre-fetched tracks via the OAuth-aware connector.
2. **Resolve preview URLs** — `PreviewResolver` short-circuits to `TrackIdentity.spotifyPreviewURL` when present (inline from the Spotify `/items` `preview_url` field per D-070; no network call), and falls back to the iTunes Search API (free, 20 req/min sliding-window limiter per D-011) for non-Spotify tracks or tracks where Spotify returns null. Caches results in memory.
3. **Download and decode** — `PreviewDownloader` downloads the AAC/MP3 clip and decodes it to mono Float32 PCM via `AVAudioFile` (stereo averaged). Magic-byte sniffing covers WAV / AIFF / CAF / MP3 / M4A. Per-track metadata pre-fetch (`MetadataPreFetcher`) runs in parallel with the PCM download via `async let` (Round 26, 2026-05-15) — best-effort; `nil` on failure means no override gets applied later in step 5.
   - **LF.2 (2026-05-27, D-129):** the local-file playback path (`VisualizerEngine.prepareAndStartLocalFilePlayback(url:)`) bypasses steps 1–2 and 3's download — it calls `PreviewAudio.fromLocalFile(at:)` to decode the file PCM directly off-disk, then drives the analyzePreview pipeline (step 5) on the result. The cached `BeatGrid` + `StemFeatures` are stored in `StemCache` with a synthetic `TrackIdentity` and installed via `VisualizerEngine.resetStemPipeline(for:caller:)`'s cache-hit branch BEFORE the audio router starts. The underlying analyzers' fixed window limits (StemSeparator ~10 s; Beat This! ~30 s) silently truncate longer inputs; the LF.2 win is structural — same PCM bytes pre-analyzed AND played — not "full-track analysis." See D-129 for scope and rationale.
   - **LF.3 (2026-05-27, D-130):** the same path is now disk-backed. Before running pre-analysis, the LF preparer hashes the file (`PreviewAudio.sha256(of:)`) and consults `PersistentStemCache` at `~/Library/Application Support/Phosphene/StemCache/sha256/<aa>/<full-hash>/`. On a hit, the cached `CachedTrackData` is loaded (~100 ms wall on M2 Pro) and `analyzePreview` is skipped entirely — second-launch cold-start drops from ~2 s to ~634 ms. On a miss, the LF.2 flow runs and the result is persisted to disk for next launch. The synthetic identity is `local:sha256:<hash>` (was `local:<path>` at LF.2) so renamed/moved copies of the same bytes resolve to the same cache entry by construction. Cache failures are non-fatal — the LF path falls through to LF.2's in-memory-only flow.
   - **LF.4 (2026-05-27, D-131):** local-file playback is now SessionManager-owned. `SessionManager.startLocalFile(at:)` drives the full `idle → preparing → ready → playing` state machine; the heavy ML preparation is delegated to `VisualizerEngine` via the `LocalFilePreparing` protocol. The state machine integration replaces LF.3's `startAdHocSession()`-bypass — `PreparationProgressView` now renders during the ~2 s cold-start window, and the engine's `.ready` Combine observer installs the cached BeatGrid + starts the LF audio router + advances to `.playing`. New `SessionOrigin` enum (`.playlist(PlaylistSource) / .localFile(URL)`) replaces the parallel `localFilePlaybackActive` boolean; consumers read `sessionManager.currentSource?.isLocalFile`. `PersistentStemCache` gains LRU eviction (`totalBytes()` / `evictToMaxBytes(_:)` / `clearAll()`) with a default 500 MB cap (UserDefaults override via `phosphene.cache.localFile.maxBytes`). The `Phosphene → Clear Local-File Cache (<size>)` menu item surfaces the current footprint reactively through a new `@Published var localFileCacheBytes` publisher. User-facing entry points: `File → Open Local File…` (⌘O), drag-and-drop of a single audio file, plus the existing `PHOSPHENE_LOCAL_FILE_PLAYBACK` env-var hook (now routes through the same `SessionManager` API).
   - **LF.5 (2026-05-28, D-132):** local-file playback graduates past the single-file ceiling. New canonical API `SessionManager.startLocalFiles(at:origin:)` walks a `[URL]` queue sequentially via the LF.4 `LocalFilePreparing` delegate; LF.4's `startLocalFile(at:)` becomes a thin wrapper (`await startLocalFiles(at: [url], origin: .localFile(url))`). `SessionPreparer.prepareLocalFiles(urls:placeholders:via:)` is the queue worker — mirrors the streaming-path `prepare(tracks:)` shape, publishes per-file `trackStatuses` transitions through the same `PreparationProgressPublishing` publisher. `SessionOrigin` extends with 3 multi-file cases (`.localFiles([URL])`, `.localFolder(URL, expanded: [URL])`, `.localPlaylist(URL, expanded: [URL])`) so the UI can label the source shape; new `allLocalFileURLs` accessor returns the expanded queue. New `M3UParser` (engine) tolerates BOM, CRLF, comment lines, absolute / `file://` / relative paths. `PersistentStemCache` bumps to schema v2 with optional `LocalFileMetadata` (title / artist / album from `AVAsset.commonMetadata`) + optional sibling `artwork.bin` (raw image bytes). New app-layer `LocalFileRecentsStore` persists last 10 opens to `phosphene.lf.recents` UserDefaults; `File → Open Local Folder…` + `File → Open Recent ▸` submenu surface in the menu bar. `Info.plist` registers `CFBundleDocumentTypes` (LSHandlerRank=Alternate, NOT Default) for `m4a / mp3 / flac / m3u / m3u8`; `.onOpenURL` distinguishes `phosphene://` (Spotify OAuth) from `file://` (LF dispatch). Mid-session track transitions are driven by `LocalFilePlaybackProvider.onFileEnded` → `VisualizerEngine.advanceLocalFileQueue` (hard cuts, ≤ 50 ms gap); single-file queues leave the callback unset so the LF.1 loop default fires (preserves the dev-workflow env-var hook). Per Matt's audit, folder + multi-drop queues cap at 200 URLs (alphabetical) with a localized truncation alert.
   - **LF.6 (2026-05-28, D-133):** the LF.5 artwork bytes reach the chrome. New `VisualizerEngine.@Published var currentTrackArtworkData: Data?` publisher fed from a synchronous `persistentStemCache.load(hash:)` lookup at LF session start (`handleLocalFileReady`) and on every track advance (`advanceLocalFileQueue`), via the shared `applyLocalFileTrackState(identity:planIndex:)` helper. **Invariant:** both `currentTrack` and `currentTrackArtworkData` are written back-to-back inside the same MainActor block (title-first then artwork-second) so chrome consumers can't briefly render the previous track's artwork against the new track's title (or vice versa) on advance. As a side effect, LF.6 closes the pre-existing "—" placeholder gap — pre-LF.6 the LF path never wrote `engine.currentTrack`, so every LF session rendered `—` for title; LF.6 publishes a `TrackMetadata` projection from the cached `TrackIdentity` at the same two write sites. The chrome reads `currentTrackArtworkData` via a new `currentTrackArtworkDataPublisher` parameter on `PlaybackChromeViewModel.init`, bound to the existing `currentTrackPublisher` via `Publishers.CombineLatest` so `TrackInfoDisplay` carries `(title, artist, albumArtData)` atomically. `TrackInfoCardView` renders the bytes through `AlbumArtworkCache.image(for:cacheKey:)` — process-wide `NSCache` (20-entry cap, keyed by `title|artist`) that decodes via `NSImage(data:)` and downsizes to 64 pt max edge (128 px native @2x). Streaming-path artwork is deferred to `LF.6.streaming` (kickoff at `docs/prompts/LF6STREAMING_KICKOFF.md`); until then streaming sessions render the chrome with the slot hidden (no out-of-place glyph).
   - **LF.6.streaming (2026-06-01, D-134):** every Spotify / Apple Music / tap-path track-change now feeds the same `currentTrackArtworkData` publisher. The chain is `SpotifyWebAPIConnector.parseTrack` → new `TrackIdentity.spotifyArtworkURL` hint (from `album.images[0].url`) → `StreamingArtworkURLResolver` (Spotify-first short-circuit + iTunes Search fallback with `100x100bb` → `600x600bb` URL rewrite) → `StreamingArtworkDiskCache` (SHA-256-keyed LRU at `~/Library/Caches/com.phosphene.app/streaming-artwork/`, 100 MB cap, atomic writes, oldest-mtime-first eviction) → `StreamingArtworkFetcher` (URLSession, 5 s timeout) → `StreamingArtworkPublisher` (`@MainActor`, owns the in-flight `Task<Void, Never>?` so a rapid A → B track-change cancels A and only B's bytes can ever land — every publish is gated on `!Task.isCancelled`). The publisher is wired in `VisualizerEngine+Capture.swift`'s track-change callback: the canonical `TrackIdentity` is resolved BEFORE the MainActor block (so the publisher sees the `spotifyArtworkURL` hint), then the MainActor block publishes `currentTrack` + nil-artwork on the same tick (LF.6 title-first-then-artwork invariant), then kicks the publisher. Resolved bytes land on a later MainActor tick — the chrome's existing opacity-animate-in covers the gap. The `.connecting` session-state observer also calls `streamingArtworkPublisher.update(for: nil)` to cancel any prior session's in-flight fetch, defense-in-depth with LF.6.fix.1's existing per-track clear. Disk-cache hit short-circuits the fetcher; the chain is idempotent and bounded.
4. **Stem separation** — MPSGraph Open-Unmix HQ, ~142 ms warm predict per track. Mono waveforms extracted from the UMA `stemBuffers`.
5. **Analysis pipeline** (composed in `SessionPreparer+Analysis.analyzePreview(...)`, run inside `Task.detached`):
   - StemAnalyzer multi-frame AGC warmup → `StemFeatures` snapshot.
   - Offline MIR (`MIRPipeline`) over the preview clip — BPM, key, mood (EMA-smoothed via `MoodClassifier.currentState`), spectral centroid, structural section count.
   - **Beat This! offline beat grid on the full mix** (D-077 via `BeatGridAnalyzer` / `BeatGridResolver`).
   - **Metadata-driven `beatsPerBar` override** (Round 26, 2026-05-15): when `MetadataPreFetcher` returned a `time_signature` (e.g. Money's 7/4), `BeatGrid.overridingBeatsPerBar(timeSignature)` overrides the ML-detected meter before caching.
   - **Beat This! offline beat grid on the drums stem** (DSP.4 diagnostic — same analyzer instance, MPSGraph graph reusable across calls; logged via `SessionPreparer+WiringLogs` for 3-way BPM disagreement detection alongside the full-mix grid and MIR BPM).
   - **`GridOnsetCalibrator` per-track median grid-vs-onset offset** (BUG-007.8): replays the preview audio through a live offline `BeatDetector`, matches sub-bass onsets (`result.onsets[0]` per D-075 / Failed Approach #50) to grid beats within ±200 ms, computes median `(gridBeat − onsetTime)` in milliseconds. Stored on `CachedTrackData.gridOnsetOffsetMs` and applied at playback time as the `LiveBeatDriftTracker` EMA's initial bias. BUG-007.9 runtime recalibration re-runs the same calibrator against tap audio after stem-separation lock stabilises.
6. **Cache all results** in `StemCache` keyed by `TrackIdentity` (NSLock-guarded; `CachedTrackData` holds stemWaveforms / stemFeatures / trackProfile / beatGrid / drumsBeatGrid / gridOnsetOffsetMs).
7. **Orchestrator plans the visual session** using per-track `TrackProfile`s (App-layer wiring per `§Orchestrator` — `Session` module cannot import `Orchestrator`).

`SessionManager` degrades gracefully on failure (D-018): a connector failure → `.ready` with empty plan + `.reactiveFallback`; per-track preparation failures → cached + failed tracks both reflected in `currentPlan`, never stuck in `.preparing`. Progressive readiness (D-056) lets the user tap "Start now" once `progressiveReadinessLevel >= .readyForFirstTracks` (default: 3 consecutive ready tracks from position 1).

On track change, `VisualizerEngine.resetStemPipeline(for:)` loads pre-separated stems from `StemCache` immediately — no warmup gap. `StemSampleBuffer` keeps accumulating for live refinement, which crossfades in after ~10s.

## Renderer

The renderer manages the Metal pipeline: device, command queue, triple-buffered semaphore, shader compilation, and frame scheduling. It supports multiple render paths dispatched via a data-driven render graph.

**Render passes** (`RenderPass` enum): `direct`, `feedback`, `particles`, `mesh_shader`, `post_process`, `ray_march`, `icb`, `ssgi`, `mv_warp`. Each preset declares its required passes in JSON metadata.

**Compute kernel buffer layout for particle presets:** `buffer(0)` = particle state, `buffer(1)` = FeatureVector, `buffer(2)` = ParticleConfiguration, `buffer(3)` = StemFeatures. `ProceduralGeometry.update(features:stemFeatures:commandBuffer:)` binds `StemFeatures` at index 3 on the compute encoder. The `stemFeatures` parameter defaults to `.zero` so callers that don't have live stems still compile and run correctly.

**Stem routing warmup pattern for particle presets:** When `StemFeatures` are unavailable (first ~10s of a track in ad-hoc mode), the kernel detects zero stems via `totalStemEnergy = smoothstep(0.02, 0.06, sum_of_all_stem_energies)` and crossfades from FeatureVector 6-band fallback to true stem routing. Zero total stem energy → pure FeatureVector routing (identical behavior to pre-stem implementation). This pattern is reusable for any compute preset that needs to handle the live-stem warmup window.

**Render path priority:** mesh → postProcess → ICB → rayMarch → feedback → direct.

**Per-frame ray-march modulation.** The shared `drawWithRayMarch` path applies preset-agnostic, audio-reactive modulation to `SceneUniforms` each frame — driven by `FeatureVector` values that the lighting / composite passes consume. Modulations:

- **Light intensity** = `baseIntensity × (0.4 + max(beatBass, beatMid, beatComposite) × 2.6)` — pulses on any-band beat onset; cross-genre by reading the strongest of the three onset signals.
- **Light colour** = `baseColor × tint(valence)` — warm amber tint on positive valence, cold blue on negative; used both as direct light tint and as IBL ambient multiplier (see Renderer/Shaders/RayMarch.metal `iblAmbient *= scene.lightColor.rgb`) so colour shift is visible across the whole scene, not only on light-facing surfaces.
- **Fog far plane** = `baseFogFar × (calmFactor or franticFactor)` — calm arousal expands the visible horizon, frantic arousal closes it in.
- **Camera dolly** = `baseCameraZ + features.time × cameraDollySpeed` — constant-speed wall-clock advance, per-preset speed (Glass Brutalist 2.5 u/s; others 0). Decoupled from `accumulatedAudioTime` so motion feels like travel, not energy-tied.
- **`SceneUniforms.cameraForward.w`** is repurposed as a preset-specific scalar for SDF deformation that needs to be visible to both `sceneSDF` and `sceneMaterial` (Glass Brutalist uses it as the glass-fin X-position). The preamble passes `FeatureVector` and `SceneUniforms` to `sceneMaterial` so material classification stays consistent with deformed geometry.

Baselines for these modulations are captured in `RayMarchPipeline.BaseSceneSnapshot` at preset apply time so per-frame modulation is additive on the preset's intent, not destructive.

**Fragment buffer binding layout (direct-pass presets):**

| Index | Content | Notes |
|-------|---------|-------|
| 0 | `FeatureVector` (192 bytes) | All fragment encoders |
| 1 | FFT magnitudes (512 Float32) | All fragment encoders |
| 2 | Waveform (2048 Float32) | All fragment encoders |
| 3 | `StemFeatures` (256 bytes) | All fragment encoders |
| 4 | `SceneUniforms` (128 bytes) | Ray march G-buffer, lighting, SSGI **only** |
| 5 | `SpectralHistory` (4096 Float32, 16 KB) | Direct-pass fragment encoders; see D-030 |
| 6–7 | Future use | — |

`SpectralHistoryBuffer` (Shared module) maintains 5 ring buffers of 480 samples (≈8s at 60 fps): valence, arousal, `beat_phase01`, `bass_dev`, and log-normalized vocal pitch (80→800 Hz mapped to 0→1). Updated once per frame in `RenderPipeline.draw(in:)` before any render encoder; reset on track change. Enables `instrument`-family presets to render recent MIR history without per-preset plumbing.

**Key subsystems:**

- `FrameBudgetManager` — Pure-state frame timing governor attached to `RenderPipeline`. Receives one `FrameTimingSample` per completed frame (via `commandBuffer.addCompletedHandler` → `@MainActor` hop) and walks a `QualityLevel` ladder: `full → noSSGI → noBloom → reducedRayMarch → reducedParticles → reducedMesh`. Downshifts after 3 consecutive overruns; upshifts after 180 consecutive sub-budget frames (asymmetric hysteresis). Per-tier configuration: tier1 (M1/M2) 14ms target, tier2 (M3+) 16ms target. `reset()` is called on every preset change so the governor starts optimistic. Disabled when `QualityCeiling` is `.ultra`. (D-057)
- `PostProcessChain` — HDR bloom + ACES tone mapping. `bloomEnabled` gates the bright-pass + blur stages; composite always runs for ACES tone-mapping.
- `RayMarchPipeline` — Deferred 3-pass: G-buffer → PBR lighting → composite. `reducedMotion` is an OR-gate of `a11yReducedMotion` (accessibility) and `governorSkipsSSGI` (budget governor), ensuring the governor cannot clear a user's accessibility preference. `stepCountMultiplier` is written to `sceneParamsB.z` each frame and consumed in the ray-march preamble loop.
- `IBLManager` — Image-based lighting (irradiance + prefiltered environment + BRDF LUT).
- `ProceduralGeometry` — GPU compute particle system. `activeParticleFraction` scales compute dispatch count for governor-level particle reduction.
- `MeshGenerator` — Hardware mesh shaders (M3+) with vertex fallback (M1/M2). `densityMultiplier` is passed at object/mesh buffer(1) for M3+ opt-in density reduction; no-op on M1/M2 vertex path.
- `TextureManager` — 5 pre-computed noise textures generated via Metal compute at init.
- `RenderPipeline+MVWarp` — Milkdrop-style per-vertex feedback warp: `MVWarpPipelineBundle`, `MVWarpState` (+ `feedbackFormat`), `setupMVWarp`, `drawWithMVWarp` (3-pass warp/compose/blit), `clearMVWarpState`, `reallocateMVWarpTextures`. Pass-2 (scene) + the comp beat-pulse live in `RenderPipeline+MVWarpScene`.
- `RenderPipeline+MVWarpScene` — mv_warp Pass-0/Pass-2 scene helpers (D-138): `renderSceneToTexture` (default direct presets), `encodeMVWarpScenePass` (Dragon Bloom waves-on-top vs. the standard decayed compose), `mvWarpBeatPulse` (Dragon Bloom comp beat envelope).

**Binding layout (summary — see §GPU Contract Details for the canonical contract):**

- Textures: 0=feedback read, 1=feedback write, 2–3=reserved, 4=noiseLQ, 5=noiseHQ, 6=noiseVolume, 7=noiseFBM, 8=blueNoise, 9=IBL irradiance, 10=IBL prefiltered env OR per-preset baked height field (different encoders; no overlap — see D-127), 11=BRDF LUT, 12=DynamicTextOverlay (direct-pass only — SpectralCartograph), 13+=staged-composition sampled stage outputs (V.ENGINE.1).
- Buffers: 0=FeatureVector, 1=FFT, 2=waveform, 3=StemFeatures, 4=SceneUniforms (ray-march G-buffer/lighting/SSGI **only**), 5=SpectralHistory (direct-pass), 6=per-preset fragment buffer #1 (D-092 — Gossamer wave pool / Arachne web pool), 7=per-preset fragment buffer #2 (D-094 — Arachne spider state), 8=per-preset fragment buffer #3 (D-LM-buffer-slot-8 — Lumen Mosaic `LumenPatternState`).

## Presets

Each preset consists of one or more Metal shaders plus a JSON sidecar declaring visual behavior, render passes, audio routing, and orchestration metadata. Presets are discovered automatically at runtime and compiled with a shared preamble (FeatureVector struct, ShaderUtilities library, noise samplers).

**Three architectural patterns coexist:**

- **Milkdrop-style per-vertex feedback warp (`mv_warp`):** 32×24 vertex grid warps the previous frame at per-vertex displaced UVs. Three passes per frame — warp (previous frame → composeTexture via displaced UVs × decay), compose (alpha-blend current scene onto composeTexture), blit (composeTexture → drawable). Motion accumulates across frames; simple audio inputs compound into organic motion. The scene can be pre-rendered by a preceding `.rayMarch` pass (into `warpState.sceneTexture`) or rendered directly by the preset's fragment shader for direct presets (e.g. Starburst). Presets implement `mvWarpPerFrame()` + `mvWarpPerVertex()` Metal functions to author the per-vertex UV displacement. `MVWarpPipelineBundle` holds the three per-preset compiled pipeline states; `MVWarpState` holds the three off-screen textures (warpTexture, composeTexture, sceneTexture) at `feedbackFormat` (the drawable format; an HDR-feedback variant is possible but Dragon Bloom uses 8-bit — the per-frame clamp is load-bearing, D-138). **Custom-warp variant (Dragon Bloom, D-138):** a preset can carry a faithful butterchurn-style custom-warp loop — the warp fragment runs a colour transfer with NO decay (gated by `chromaticMix`), the scene-geometry strands are composited **normal-alpha directly onto the warped frame** (`encodeMVWarpScenePass` strands-on-top branch — that result IS the feedback, replacing the decayed compose), and the blit applies a display-only comp (video echo / gamma / invert + a beat-pulse pump via the `setMVWarpPost` float4 uniform). All gated so other mv_warp presets are byte-identical.
- **Thin global feedback (`feedback`):** read previous frame → single global zoom+rot → composite. Kept for Membrane. Semantically narrower than `mv_warp`.
- **Photorealistic ray march:** SDF scene → G-buffer → PBR lighting → IBL → post-process. Ray-march presets can also opt into `mv_warp` for temporal feedback; in that case the lighting pass renders to `warpState.sceneTexture` instead of the drawable, and `mv_warp` handles drawable presentation.

## Orchestrator

The Orchestrator is the decision layer responsible for selecting visualizers, sequencing transitions, adapting to live analysis, and balancing novelty, continuity, and performance cost.

**Two modes:**

- **Session mode** (playlist connected): Plans the full visual arc before playback using pre-analyzed TrackProfile data. Adapts in real time as live MIR reveals structural details.
- **Ad-hoc mode** (no playlist): Reactive decision-making under uncertainty. Heuristic preset selection based on live MIR data as it accumulates.

The Orchestrator is the product's key differentiator and is implemented as an explicit scoring and policy system with testable golden-session fixtures.

**Implemented (Phase 4, Increments 4.0–4.6 — Orchestrator-module surface complete):**

- **`DefaultPresetScorer`** (D-032) — stateless, deterministic preset ranker. Produces a `PresetScoreBreakdown` with four weighted sub-scores (mood 30 %, stemAffinity 25 %, sectionSuitability 25 %, tempoMotion 20 %) and two multiplicative penalties (family-repeat 0.2×; fatigue via smoothstep over 60/120/300 s cooldowns by `FatigueRisk`). Hard exclusions gate diagnostic presets, uncertified presets (unless `includeUncertifiedPresets`), session-excluded presets, temporary + permanent family exclusions (U.6b), presets exceeding the `QualityCeiling.complexityThresholdMs(for: tier)` budget, and the currently-playing preset. Additive `familyBoost` (U.6b) applied after weighted aggregation. QR.2 / D-080 stem-affinity uses deviation primitives + mean formula with a zero-balance neutral-0.5 guard. `PresetScoringContext` is a fully Sendable value snapshot; `DefaultPresetScorer` contains no mutable state and calls no `Date.now()`, guaranteeing determinism.
- **`DefaultTransitionPolicy`** (D-033) — implements `TransitionDeciding`. Structural boundary (confidence ≥ 0.5, 2.5 s lookahead) fires before the duration-expired timer fallback. Style negotiated from the current preset's `transitionAffordances` and energy (`.cut` preferred at energy > **0.85** per D-080 amendment to D-033; `.crossfade` otherwise). Crossfade duration scales linearly 2.0 s → 0.5 s with energy. Fully inspectable `TransitionDecision` value type.
- **`DefaultSessionPlanner`** (D-034, with V.7.6.2 multi-segment extension in `SessionPlanner+Segments.swift`) — greedy forward-walk over the playlist; for each track scores the full catalog given accumulated history, picks the top eligible preset, and emits one or more `PlannedPresetSegment` per track via `SessionPlanner+Segments.planSegments(...)`. Transition decisions reuse `DefaultTransitionPolicy` via synthetic `StructuralPrediction` at each track boundary (confidence 1.0). `planAsync(...)` accepts a precompile closure — the Orchestrator module carries no Renderer dependency. D-047 seeded variant for "Regenerate Plan". `recentHistory` capped at 50 entries (D-080 rule 6). Deterministic: same inputs → byte-identical plan.
- **`DefaultLiveAdapter`** (D-035; class since D-080) — runtime plan-adaptation. Boundary-reschedule (live boundary deviates from planned by > 5 s) → mood-override (live mood diverges by > 0.4, within first 40 % of track, with NSLock-guarded per-track cooldown of 30 s per D-080 rule 3). `applying(_:at:)` / `extendingCurrentPreset(by:at:)` / `applying(overrides:)` extensions on `PlannedSession` (V.7.6.2-aware: segment-level patching) are the only sanctioned controlled-mutation paths. **Note: the App-layer runtime invocation of `applyLiveUpdate(...)` is currently absent — see [BUG-015](../docs/QUALITY/KNOWN_ISSUES.md) for the missing-wire entry.**
- **`DefaultReactiveOrchestrator`** (D-036; stateless; D-080 reactive `liveStemFeatures` wiring) — ad-hoc preset selection without pre-analysis. Accumulation tiers (`.listening` 0–15 s, `.ramping` 15–30 s, `.full` 30 s+). Switch conditions: score gap > 0.20 OR (boundary confidence ≥ 0.5 AND score gap > 0.05 per D-080 rule 4). `liveStemFeatures` populated once the live stem analyzer converges (~10 s) so QR.2 / D-080 stem-affinity scoring works in reactive mode. **Same runtime-invocation gap as above — see BUG-015.**
- **`PresetSignaling`** (V.7.6.2) — `presetCompletionEvent: PassthroughSubject<Void, Never>` protocol for completion-gated presets. `ArachneState` conforms via `ArachneStateSignaling.swift` (cross-module placement per D-095 to avoid Presets→Orchestrator dependency cycle). `PresetSignalingDefaults.minSegmentDuration = 5.0` enforces a floor against premature emission.
- **`PlaybackActionRouter`** (D-050) — protocol contract for keyboard-surface live-adaptation actions. Concrete `DefaultPlaybackActionRouter` lives in `PhospheneApp/Services/` per U.6b. All seven methods (`moreLikeThis` / `lessLikeThis` / `reshuffleUpcoming` / `presetNudge(_:immediate:)` / `rePlanSession` / `undoLastAdaptation` / `toggleMoodLock`) wired through `PlaybackShortcutRegistry` to keyboard shortcuts.
- **`QualityCeiling`** (U.8, D-053) — `.auto / .performance / .balanced / .ultra` enum; `complexityThresholdMs(for: tier)` returns nil for `.ultra` (no exclusion), 12 ms for `.performance`, `tier.frameBudgetMs` otherwise. Read by `DefaultPresetScorer` for the complexity-cost exclusion gate and by `MLDispatchScheduler` (Renderer) per D-059d.

Golden-session regression fixtures (4.4) live in `Tests/Orchestrator/GoldenSessionTests.swift` — 12 regression tests across three curated playlists; regenerated multiple times since landing as the scoring surface evolved (QR.2 / V.7.6.2 / BUG-004).

## UI Layer

The app shell routes `SessionManager.state` to one top-level SwiftUI view per session state. No view owns more than one state.

**`SessionStateViewModel`** (`@MainActor ObservableObject`, `PhospheneApp` module) — Bridges `SessionManager.state` into the view layer via a Combine `.assign` subscription. Also surfaces `reduceMotion` (from `NSWorkspace.accessibilityDisplayOptionsDidChangeNotification`), which caps beat-pulse amplitude and disables `mv_warp` feedback in reduced-motion mode. Lives in `PhospheneApp/ViewModels/`.

**State-to-view mapping:**

| `SessionState` | View | `accessibilityIdentifier` |
|---|---|---|
| `.idle` | `IdleView` | `phosphene.view.idle` |
| `.connecting` | `ConnectingView` | `phosphene.view.connecting` |
| `.preparing` | `PreparationProgressView` | `phosphene.view.preparing` |
| `.ready` | `ReadyView` | `phosphene.view.ready` |
| `.playing` | `PlaybackView` | `phosphene.view.playing` |
| `.ended` | `EndedView` | `phosphene.view.ended` |

**`ContentView`** layers a permission gate above the session-state switch. When `PermissionMonitor.isScreenCaptureGranted` is `false`, `PermissionOnboardingView` renders regardless of `SessionManager.state` — this catches both fresh installs and mid-session permission revocations. When permission flips to `true` (detected via `NSApplication.didBecomeActiveNotification`), the view tree re-renders and routes to the current `SessionState`. Permission plumbing lives under `PhospheneApp/Permissions/`, not `Views/`, because it is a routing-layer concern.

**`PlaybackView`** hosts the full-bleed `MetalView`, six layered SwiftUI overlays — `TrackChangeAnimationView` (boundary fade), `PlaybackChromeView` (auto-hiding track card + progress + listening badge + toast container), `ShortcutHelpOverlayView` (Shift+? help table), `DebugOverlayView` (bottom-leading raw diagnostics, D key), and `DashboardOverlayView` (top-trailing typographic instrument panel, DASH.7) — and the end-session confirmation dialog. It calls `engine.startAudio()` on appear, owns `LiveAdaptationToastBridge` + `DefaultPlaybackActionRouter.live(...)` + `DisplayManager` + `MultiDisplayToastBridge` + `DisplayChangeCoordinator` + `PlaybackErrorBridge` + `FullscreenObserver` + `PlaybackKeyMonitor` as `@State`, and routes all keyboard shortcuts via `PlaybackShortcutRegistry`. Shortcut surface: `→` / `←` (preset nudge at next boundary), `Shift+→` / `Shift+←` (force-immediate nudge), `Space` (toggle overlay), `+` / `-` (more / less like this), `.` (reshuffle upcoming), `?` (plan preview), `⌘R` (re-plan session), `⌘Z` (undo last adaptation), `M` (mood-lock toggle), `D` (debug overlay + dashboard toggle), `C` (capture toggle), `R` (MIR record toggle), `G` (G-buffer debug cycle), `Esc` (exit fullscreen or end-session with confirm), `Shift+?` (shortcut help overlay), plus `⌘F` (fullscreen) / `⌘Shift+F` (secondary display) and developer-only diagnostic shortcuts (beat-phase / bar-phase / audio-latency tweak, spider easter-egg toggle, direct preset cycle).

**`VisualizerEngine`** is injected into the SwiftUI environment as an `@EnvironmentObject`. `ContentView` and `PhospheneApp.swift` do not own layout — they exist solely to wire the VM and inject the engine.

## Support Tiers

**Tier 1 — M1 / M2:** Baseline feature set. Mesh shaders use vertex fallback. Stricter budgets for geometry, post-process, and advanced shaders.

**Tier 2 — M3 / M4:** Enhanced feature set. Hardware mesh shaders enabled. Mesh/ray-heavy presets allowed. Higher complexity ceilings.

## ML Inference

No CoreML dependency. All ML runs on MPSGraph (GPU) or Accelerate (CPU). Three production models:

- **Stem separator** (MPSGraph): Open-Unmix HQ, Float32 throughout, 142 ms warm predict for 10 s audio (D-009 / D-010). Window: `modelFrameCount = 431` frames × `hopLength = 1024` samples = `requiredMonoSamples = 440320` (≈10 s at 44.1 kHz); `nFFT = 4096`. STFT/iSTFT via the `StemFFTEngine` MPSGraph path (Increment 3.1a; CPU vDSP fallback retained behind `forceCPUFallback`). The 5 s background timer fires every 5 seconds; actual dispatch may be deferred up to 2 s (Tier 1) or 1.5 s (Tier 2) if recent frames are over budget — see Dispatch Scheduling below. Open-Unmix HQ weights: 172 tensors / ~136 MB, loaded at init with BN-fusion baked in.
- **Beat This! transformer** (MPSGraph): 128-dim transformer, 4 heads, 6 blocks, 512 FFN, 1500-frame fixed window (~30 s at 50 fps; sr=22050, hop=441). Input: log-mel spectrogram `[T, 128]` from `BeatThisPreprocessor` (DSP module). Output: per-frame beat + downbeat sigmoid probabilities consumed by `BeatGridResolver` (DSP module) to produce a `BeatGrid`. Architecture: PartialFTTransformer frontend (stem `BN1d → Conv2d(4×3)` → 3 PartialFT blocks with bi-directional F/T attention + RoPE + gating → projection) → 6 transformer blocks (manual RMSNorm + manual SDPA + RoPE paired-adjacent rotation; all three are macOS 14 workarounds — `scaledDotProductAttention` is macOS 15+) → post-norm → 2-class head. Weights: 161 tensors / 8.4 MB / Float32 (extracted from the MIT-licensed reference checkpoint), BN-fused at load. NSLock-guarded inference. D-077 (pivot from D-076 BeatNet, abandoned 2026-05-04 — see `docs/diagnostics/DSP.2-beatnet-archive.md`). Composed with `BeatThisPreprocessor` + `BeatGridResolver` inside `BeatGridAnalyzer` (Session module, CA.1 boundary-deferred).
- **Mood classifier** (Accelerate): 4-layer MLP (10→64→32→16→2) via `vDSP_mmul`. 3,346 hardcoded Float32 params from DEAM training. Tanh output; output clamped to [-1, 1]; per-frame EMA smoothing at α = 0.1 (~0.7 s time constant at 94 Hz). D-009.

### Dispatch Scheduling (Increment 6.3)

`MLDispatchScheduler` (`Renderer` module) coordinates the 5s stem separation cycle with render-loop frame timing. When a heavy ray-march+SSGI frame is in flight, a 142ms MPSGraph burst landing on top causes visible double-jank.

**Algorithm:** on each 5s timer fire, the scheduler checks:
1. If `QualityCeiling == .ultra` → dispatch immediately (recording mode, D-059d).
2. If the dispatch has been pending ≥ `maxDeferralMs` → force-dispatch to prevent stem freeze (D-059c).
3. If fewer than `requireCleanFramesCount` frames have been observed → defer (startup warmup).
4. If `recentMaxFrameMs > currentTierBudgetMs` → defer 100 ms and retry.
5. Else → dispatch now.

**Budget signal:** the scheduler reads `FrameBudgetManager.recentMaxFrameMs` — the worst frame in the last 30-frame rolling window, not `currentLevel`. The level has 180-frame upshift hysteresis; the rolling max reflects the current render state immediately (D-059a).

**Deferral caps:** Tier 1 (M1/M2): `maxDeferralMs = 2000`, `requireCleanFramesCount = 30`. Tier 2 (M3+): 1500 ms / 20 frames. Stems already lag real audio by 5–10 s (per-frame analysis from cached waveforms runs continuously regardless — Increment 3.5.4.9), so a 2 s extra lag is within acceptable routing freshness bounds (D-059b).

**Testability:** `FrameTimingProviding` protocol (`recentMaxFrameMs`, `recentFramesObserved`) is conformed to by both `FrameBudgetManager` and test stubs. Single source of truth — no parallel timing buffer in the scheduler (D-059e).

**Mood injection into the renderer.** Mood (`valence`, `arousal`) is computed on the analysis queue, attenuated by feature-stability, and pushed to the renderer via `RenderPipeline.setMood(valence:arousal:)`. The renderer's `setFeatures` preserves the most recent mood values across MIR-driven feature updates so the slower-cadence mood signal is not overwritten every frame. Without this dedicated path, mood values stay at zero in the GPU-bound `FeatureVector` even though the classifier is running.

## Session Recording (Diagnostics)

`SessionRecorder` (`Shared` module, public) writes a continuous diagnostic capture for every running session to `~/Documents/phosphene_sessions/<ISO-timestamp>/`. Created at `VisualizerEngine.init`, finalized via `NSApplication.willTerminateNotification` so the MP4 `moov` atom is written before process exit.

**Artifacts per session:**

- `video.mp4` — H.264 capture of the rendered output, throttled to 30 fps. Writer is locked once the drawable size has been observed for 30 consecutive same-size frames; later frames at a different size are skipped (preventing corner-rendered video from transient launch-time drawable sizes). MetalView sets `framebufferOnly = false` so the drawable is blit-readable.
- `features.csv` — per-frame `FeatureVector` (22 columns: bass/mid/treble, 6-band, beat onsets, spectral, valence/arousal, accumulatedAudioTime).
- `stems.csv` — per-frame `StemFeatures` (vocals/drums/bass/other × {energy, band0, band1, beat, energyRel/Dev, onsetRate, centroid, attackRatio, energySlope}; plus vocalsPitchHz/Confidence).
- `stems/<NNNN>_<title>/{drums,bass,vocals,other}.wav` — 16-bit mono PCM dump of each stem-separation cycle output, listenable in any audio editor.
- `session.log` — startup banner (recorder version + macOS + GPU + hostname), state transitions (signal `.active/.suspect/.silent/.recovering`), track changes, preset changes, video-writer locked dimensions, and any frame-skip reasons.

**Render-loop integration:** `RenderPipeline` exposes `onFrameRendered: (drawableTex, features, stems, commandBuffer) -> Void`. `VisualizerEngine` sets this closure to blit the drawable into the recorder's capture texture inside the same command buffer, then schedule the readback in `commandBuffer.addCompletedHandler`. CSV rows are written every render frame; video frames are throttled to 30 fps.

**Test surface:** `SessionRecorderTests` validates round-trip correctness against known inputs (CSV column-by-column, WAV PCM sample-by-sample within 16-bit quantization, MP4 readable by `AVURLAsset`). A passing session that shows wrong data tells you the upstream pipeline is wrong, not the recorder.

**Manual MIR recording is a separate path.** The `R` keyboard shortcut toggles `MIRPipeline.startRecording()` / `stopRecording()` (implemented in `DSP/MIRPipeline+Recording.swift`), which writes a *different* file: `~/phosphene_features.csv` (17 columns, 1 Hz throttled, includes `track` / `artist` columns and `stableKey` / `stableBPM`). This path is independent of the auto-on per-session `SessionRecorder` and was historically the only MIR-data path before `SessionRecorder` was added. Both are kept: `SessionRecorder` is for full per-session diagnostic captures; the `R`-shortcut path is for ad-hoc MIR-feature inspection across multiple short observation windows without producing the larger per-session bundle. The schemas and cadences differ; do not assume they are interchangeable.

**`WIRING:` log surface (BUG-006.1 + DSP.4 diagnostic).** `SessionManager.startSession` / `_beginPreparation` / `startNow()` and `SessionPreparer.prepare` / `SessionPreparer+WiringLogs.logWiringDoneSummary` / `logDrumsBeatGridLine` / `logBPMMismatchIfAny` emit `WIRING:`-prefixed lines into `session.log` covering session start, preparer entry/done, per-track beat-grid summary (full-mix and DSP.4 drums-stem), and 2-way / 3-way BPM disagreement warnings. The instrumentation landed for BUG-006.1 diagnosis and stays in place as the load-bearing diagnostic trail for any future session-prep regression. Tracked for QR.5 retirement once BUG-007 + BUG-008 fully close; until then the lines cost nothing at runtime and prove out the wiring on every session capture.

## Soak Test Infrastructure (Increment 7.1, D-060)

`SoakTestHarness` (`Diagnostics` module) drives `AudioInputRouter` in `.localFile` mode for a configurable duration (default 2 hours) and produces a structured `Report` with memory growth, frame timing percentiles, dropped frames, quality-level transitions, signal-state transitions, and ML force-dispatch counts.

### Components

**`MemoryReporter`** (enum, stateless): Wraps the `task_info(TASK_VM_INFO)` Mach call. Returns `MemorySnapshot { residentBytes: phys_footprint, virtualBytes, purgeableBytes, timestamp }`. Uses `phys_footprint` — the same metric as Activity Monitor and jetsam — rather than `resident_size` which includes purgeable pages. Returns `nil` on Mach failure (counted as a hard failure if > 5 consecutive nils).

**`FrameTimingReporter`** (class, `@unchecked Sendable`, NSLock-guarded): Records per-frame effective timing (`max(cpuMs, gpuMs)`). Maintains two views: a 100-bucket fixed-width histogram (0.5 ms/bucket, 0–50 ms) for run-wide cumulative percentiles and a 1000-frame circular ring buffer for rolling percentiles and dropped-frame counts. O(1) record, O(buckets) percentile via histogram scan. Wired into `RenderPipeline.onFrameTimingObserved`.

**`SoakTestHarness`** (`@available(macOS 14.2, *)`, `@MainActor`): Orchestrates the run. Starts audio, installs signal-state and frame-timing observers, runs a 0.25s-slice polling loop for cancel responsiveness, fires periodic sampling tasks, and at completion writes a JSON + Markdown report to `reportBaseDirectory/<ISO-timestamp>/`. Does not require a live Metal render pipeline — GPU timing is optional and wired in by callers with a `RenderPipeline`.

**`SoakRunner`** (executable target): CLI entry point using `swift-argument-parser`. Options: `--duration`, `--sample-interval`, `--audio-file`, `--report-dir`. Generates a synthetic audio fixture automatically when `--audio-file` is omitted (10 s sine sweep + noise + 120 BPM kicks, written to `tmp/`). Use `Scripts/run_soak_test.sh` for 2-hour production runs; the script wraps `caffeinate -i` to prevent App Nap.

### Frame Timing Fan-out (D-060c)

`RenderPipeline.onFrameTimingObserved` is an optional `(cpuMs: Float, gpuMs: Float?) -> Void` closure fired inside the `commandBuffer.addCompletedHandler` Task, before `FrameBudgetManager`. Setting it to `harness.frameTimingRecorder` gives the soak harness GPU-accurate timings from the same source as the frame governor with zero additional overhead in production (nil closure = no call).

### Report Structure

```json
{
  "finalAssessment": "pass | passWithSoftAlerts | hardFailure",
  "snapshots": [{ "elapsedSeconds": 60, "residentBytes": ..., "cumulativeP50Ms": ..., ... }],
  "signalTransitions": [{ "elapsedSeconds": 0.5, "state": "active" }],
  "qualityLevelTransitions": [{ "elapsedSeconds": 120, "from": "full", "to": "no-SSGI" }],
  "mlForceDispatches": 0,
  "alerts": ["Memory grew 52 MB from baseline (threshold: 50 MB)"]
}
```

Soft alerts: memory growth > 50 MB, dropped frames > 60/h, quality downshifts > 3, ML force dispatches > 10/h. Hard failure: `MemoryReporter` nil > 5 times.

---

## Long-Session Resilience (Increment 7.2, D-061)

Two coordinator classes handle disruptions that arise during extended sessions without touching `SessionManager.state` or `livePlan` except where explicitly required.

### DisplayChangeCoordinator

Owned by `PlaybackView` as `@State`. Subscribes to `DisplayManager.$allScreens` and `.$currentScreen` via Combine. When the active display is removed (or the window moves to a different screen), it calls `FrameBudgetManager.resetRecentFrameBuffer()` — clearing only the 30-slot rolling timing window so the post-reparent jitter frames don't poison `MLDispatchScheduler`'s "recent frames over budget" signal. `currentLevel` is preserved (D-061(a)). Screen-added events fire a toast via `MultiDisplayToastBridge` and take no governor action.

### NetworkRecoveryCoordinator

Owned by `PreparationProgressView` as `@State`. Subscribes to `ReachabilityMonitor.isOnlinePublisher`. On a `false → true` transition (network restored), it waits an additional 2 seconds (composing to 3 s total with the monitor's existing 1 s debounce) then calls `SessionManager.resumeFailedNetworkTracks()` — which retries only network-class failures (`.noPreviewURL`, `.downloadFailed`); stem-separation failures stay failed. Guards: state must be `.preparing` (tracked from an injected `sessionStatePublisher`); attempt count must be below 3 (cap per preparation session). `resetForNewSession()` resets the counter and cancels any pending debounce task (D-061(d,e)).

---

## Module Map

Per-file behavioural reference for every Swift source file in `PhospheneApp/` and `PhospheneEngine/`, every Metal shader, and every test target. Read it when you need to locate functionality before `grep`ing the codebase.

Per-preset design history (Arachne V.7.x evolution; LumenMosaic LM.3 → LM.7 iteration; etc.) currently lives inline in the per-preset entries below. A future pruning pass will split those history blocks out into `docs/presets/<preset>_DESIGN.md` per the 2026-05-13 doc-refactor plan's borderline-call B (see `docs/diagnostics/DOC-REFACTOR-PLAN-2026-05-13.md`).

```
PhospheneApp/               → SwiftUI shell, views, view models
  ContentView.swift         → Two-level routing: permission gate (PermissionMonitor.isScreenCaptureGranted) → SessionState switch (six top-level views per UX_SPEC). Binds engine publishers (currentTrackIndexPublisher per D-091/BUG-006.2, livePlannedSession, dashboardSnapshot, audioSignalState, currentPresetName) into per-state views.
  PhospheneApp.swift        → @main App entry. Constructs single SettingsStore per D-091 / Failed Approach #55. @StateObject for engine + permissionMonitor + accessibilityState; `let spotifyOAuth = SpotifyOAuthTokenProvider.makeLive()` (actor — not ObservableObject). Wires SettingsStore.reducedMotion → AccessibilityState.applyPreference via .task; AccessibilityState.reduceMotion → engine.applyAccessibility via .onChange; phosphene://spotify-callback → OAuth actor via .onOpenURL. init() runs SettingsMigrator.migrate(), SessionRecorderRetentionPolicy.apply(policy:), DashboardFontLoader.resolveFonts(in:).
  ITunesSearchFetcher.swift → `ITunesSearchFetcher: MetadataFetching` — free, unauthenticated iTunes Search API for genre + duration. No MusicKit dependency. (Renamed from MusicKitFetcher.swift per CA.5-FU-3.)
  VisualizerEngine.swift    → Audio→FFT→render pipeline owner; owns SessionManager (non-optional). One owner of every engine subsystem (RenderPipeline, MIRPipeline, MoodClassifier, StemSeparator, StemAnalyzer, MLDispatchScheduler, FrameBudgetManager, SessionRecorder, AudioInputRouter, MetadataPreFetcher). Per-preset state classes (ArachneState, GossamerState, AuroraVeilState, NimbusState, LumenPatternEngine, FerrofluidParticles, FerrofluidMesh, DynamicTextOverlay, currentRayMarchPipeline). orchestratorLock-guarded livePlan + livePlannedSession; tapSampleRateLock-guarded tap sample rate (D-079 / QR.1). BUG-015 wire inputs (liveTrackPlanIndex, lastClassifiedMood, orchestratorWireLoggedThisTrack) declared under orchestratorLock. BUG-012-i1 instrumented (init/deinit lifecycle markers). `diagnosticPresetLocked: Bool` (DSP.3.1): when true, `applyLiveUpdate` strips `presetOverride` (mood-derived switch) but passes `updatedTransition` (structural-boundary reschedule) through unchanged. Prepared BeatGrid is authoritative; BeatPredictor is fallback only.
  VisualizerEngine+Audio.swift → Audio routing setup, MIR analysis, mood classification, signal-state callbacks. setupAudioRouting wires onAudioSamples (audio thread → analysisQueue), onSignalStateChanged (→ MainActor), onTrackChange (→ +Capture). processAnalysisFrame at analysis queue runs FFT → MIR → per-frame stem analysis → live Beat This! trigger → mood classifier → BUG-015 wire `runOrchestratorLiveUpdate(mir:)` at line 184. publishMoodResult writes lastClassifiedMood under orchestratorLock (BUG-015 cache). buildFetcherList composes iTunes + MusicBrainz + (Soundcharts + Spotify if env vars).
  VisualizerEngine+Capture.swift → Recording / capture file management + audio signal-state callback + onTrackChange callback. BUG-006.2 cause 2: resolves canonical TrackIdentity via canonicalTrackIdentity(matching:). BUG-015: resolves liveTrackPlanIndex via indexInLivePlan(matching:) and resets orchestratorWireLoggedThisTrack under orchestratorLock before MainActor hop. kickoffPreFetch fires metadata pre-fetch (Round 25/26 beatsPerBar override).
  VisualizerEngine+Dashboard.swift → DASH.7 per-frame snapshot pump: publishDashboardSnapshot(stems:) writes @Published dashboardSnapshot. assemblePerfSnapshot builds PerfSnapshot from FrameBudgetManager + MLDispatchScheduler state.
  VisualizerEngine+InitHelpers.swift → Private setup helpers called from init: setupCaptureHook (SessionRecorder blit + onFrameTimingObserved), setupDashboardSnapshotPump, setupBackgroundTextures (TextureManager + IBLManager async), makeSessionManager factory, setupTerminationObserver (NSApplication.willTerminate → recorder.finish()), detectDeviceTier (M3/M4 → tier2; else tier1). Plus NullStemSeparator fallback (always throws modelNotFound).
  VisualizerEngine+Orchestrator.swift → App-layer adapter for the Orchestrator. Plan building (buildPlan, extendPlan, _buildPlan(seed:), regeneratePlan), plan queries (currentPreset(at:), currentTransition(at:)), Live Adaptation (applyLiveUpdate with mood-override suppression for capture-mode-switch-grace / diagnostic-hold / wait_for_completion_event), reactive mode (applyReactiveUpdate with 60s lastReactiveSwitchTime cooldown + 10s live stem-features convergence per QR.2/D-080), BUG-015 wire (runOrchestratorLiveUpdate(mir:) at ~3 Hz via `orchestratorWireFrameDivisor: Int = 30`, off-plan skip path, once-per-track diagnostic dual-writing to session.log + os.Logger), U.6b router support (extendCurrentPreset, applyPresetByID, restoreLivePlan, buildScoringContext, currentTrackIndexInPlan, indexInLivePlan(matching:) per D-091, currentTrackProfile).
  VisualizerEngine+Presets.swift → applyPreset(_:) — single owner of every preset switch. Per-pass switch (.meshShader / .postProcess / .rayMarch / .feedback / .particles / .icb / .ssgi / .mvWarp / .staged / .direct). Per-preset state allocation: ArachneState (mvWarp + staged), GossamerState (mvWarp), AuroraVeilState (pass-agnostic — passes:[] post-AV.2.2), LumenPatternEngine (rayMarch — BUG-016 surface; slot 8 via setDirectPresetFragmentBuffer3 per D-LM-buffer-slot-8), FerrofluidParticles + FerrofluidMesh (rayMarch — round 57 SDF path live, mesh path retired), NimbusState (direct — 32-byte slot-6 NimbusStateGPU + noiseVolume bind; opts into setDirectRenderScale(0.5) half-res per NB.8; reset() on apply + track change). wirePresetCompletionSubscription (V.7.6.2 / D-095) per applyPreset. handlePresetCompletionEvent honours minSegmentDuration floor and diagnosticPresetLocked suppression (V.7.7C.4).
  VisualizerEngine+PublicAPI.swift → startAudio (permission gate + screen-capture poll), applyAccessibility (U.9 / D-054 reduce-motion + beat-amplitude scale), applyShowUncertifiedPresets, toggleDebugOverlay, toggleForceSpider (DEBUG-only), showPresetName (2s + 0.5s fade).
  VisualizerEngine+Stems.swift → Background stem separation pipeline, 5s cadence, track-change reset. BUG-012-i1 instrumented (timer entry, MainActor self=nil notice, stemQueue.async self=nil notices, performStemSeparation enter/exit, separator.separate CALL/RETURN, dispatch-ID allocation). Increment 6.3: dispatch gated by MLDispatchScheduler — runStemSeparation() hops to @MainActor, consults scheduler, then fires performStemSeparation() on stemQueue when frame window is clean. DSP.3.5: runLiveBeatAnalysisIfNeeded() uses liveBeatAnalysisAttempts counter (max 2) — first attempt at 10 s, retry at 20 s; halvingOctaveCorrected() applied before offsetBy(); inference body extracted to performLiveBeatInference(). DSP.3.6: source-tagged BEAT_GRID_INSTALL logging at all three BeatGrid install sites (preparedCache/liveAnalysis/none); prepared-cache guard in runLiveBeatAnalysisIfNeeded logs and caps counter when hasGrid true; sessionRecorder?.log() one-time per-track events in both install sites. BUG-007.9 runtime recalibration one-shot per track. LM.4.7 per-track palette refresh via refreshLumenPaletteForTrack (FNV-1a track seed, mood-biased Gaussian selection).
  VisualizerEngine+TrackIdentityResolution.swift → BUG-006.2 cause 2 fix. canonicalTrackIdentity(matching:) resolves partial title+artist TrackIdentity against livePlan via PlannedSession.canonicalIdentity(matchingTitle:artist:); returns nil for ad-hoc/reactive sessions and ambiguous matches.
  VisualizerEngine+WiringLogs.swift → BUG-006.1 instrumentation. ResetStemPipelineCaller enum (.preFire / .trackChange / .other). Dual-write WIRING: logger pattern (session.log + os.Logger); the same pattern BUG-015's once-per-track diagnostic now follows. Helpers: logWiringBuildPlanEnter / logWiringBuildPlanEarlyReturn / logWiringBuildPlanDone / logWiringBuildPlanFailed / logWiringResetStemPipelineEnter / logTrackChangeObserved / logWiringStemCacheLookup.
  VisualizerEngine+LocalFilePlayback.swift → LF.4/LF.5/LF.6 local-file playback core. `LocalFilePreparing` conformance (`prepareLocalFile(url:)` → off-main `runLocalFilePreparation` worker: sha256 → persistent-cache hit-or-analyze-and-persist → `LocalFilePrepResult`). `.ready` observer `handleLocalFileReady()` installs cached BeatGrid + starts AVAudioEngine router + advances to `.playing` (LF.5.fix.3-C URL-idempotency guard; LF.5.fix.2-FU4/FU5 `mir.reset()` + `lastAnalysisTime` reset closing the 91 s-prep-gap first-frame dt flood). `advanceLocalFileQueue(direction:)` mid-session forward/backward track advance (queue-exhaust → `.ended`). Transport controls (togglePause/skipNext/skipPrev/stop, D-LF5-3). LF.6: `applyLocalFileTrackState(identity:planIndex:)` unifies identity latch + orchestrator wire + `publishLocalFileTrackSurface` (TrackMetadata + `currentTrackArtworkData` from `lfPersistentArtworkData(for:)` synchronous cache lookup). `LocalFilePrepWorkerInputs` + `FreshAnalysisOutcome(artwork: Data?)` worker bundles.
  AlbumArtworkCache.swift → LF.6 in-memory decode + downsize layer. `static image(for:cacheKey:) -> NSImage?` decodes raw artwork bytes via `NSImage(data:)`, redraws to 64 pt max edge (128 px native @2x), caches in a `nonisolated(unsafe)` process-wide `NSCache<NSString, NSImage>` (count limit 20). Keyed by `title|artist`. Malformed/empty bytes → nil (chrome falls back to glyph). In-memory only — bytes already persisted by LF.5's `artwork.bin`.
  LocalFileMenuCommands.swift + LocalFileMenuCommands+Drop.swift → LF.4/LF.5 user entry points. Six NSOpenPanel / programmatic shapes (openLocalFilePanel, openLocalFolderPanel, openLocalM3UPanel, openLocalFile/Folder/M3U for Recents + file-association re-entry). `+Drop` handles drag-drop of single file / multi-file / folder / M3U / mixed; folder + multi-drop queues truncate at 200 URLs (alphabetical) with a localized alert. All paths thread `LocalFileRecentsStore`.
  LocalFileRecentsStore.swift → LF.5 @MainActor ObservableObject. Persists last 10 local-file opens to `phosphene.lf.recents` UserDefaults; surfaces the `File → Open Recent ▸` submenu (GAP E: SF Symbol per kind, "(missing)" for stale paths, Clear Recents). LocalFileRecentsStoreTests covers ordering + dedup + cap + stale-path marking.
  LocalFileErrorStore.swift → GAP F @MainActor ObservableObject. Holds the last non-destructive LF error (unsupported format / unreadable / M3U-parse-failed / empty folder) for the inline `LocalFileErrorBanner` (replaces NSAlert modals); auto-clears after 6 s, tap to dismiss.
  Models/
    PhospheneToast.swift    → Toast value type. Severity (.info / .warning / .degradation), Source (.signalState / .liveAdaptationAck / .displayChange / .degradation / .generic), ToastAction (label + handler). Default duration 4s; .infinity for manual-dismiss-only.
    SettingsTypes.swift     → App-layer settings value-type enums + structs: CaptureMode (.systemAudio / .specificApp / .localFile), DeviceTierOverride (.auto / .forceTier1 / .forceTier2), ReducedMotionPreference (.matchSystem / .alwaysOn / .alwaysOff), SessionRetentionPolicy (.keepAll / .lastN10 / .lastN25 / .oneDay / .oneWeek), SourceAppOverride struct.
  Permissions/
    ScreenCapturePermissionProvider.swift → Protocol + SystemScreenCapturePermissionProvider concrete backed by CGPreflightScreenCaptureAccess() (never prompts; CGRequestScreenCaptureAccess lives in PublicAPI.startAudio).
    PermissionMonitor.swift               → @MainActor ObservableObject; @Published isScreenCaptureGranted; refreshes on NSApplication.didBecomeActiveNotification (U.2).
    PhotosensitivityAcknowledgementStore.swift → UserDefaults-backed first-run flag; key phosphene.onboarding.photosensitivityAcknowledged (U.2). Injectable defaults suite for tests.
  Services/
    AccessibilityLabels.swift → Centralised VoiceOver label/hint lookup under "a11y.*" Localizable.strings keys. Factory methods for connector tiles, track info cards, toasts. (U.9)
    AccessibilityState.swift → @MainActor ObservableObject (U.9 / D-054). Combines NSWorkspace.accessibilityDisplayShouldReduceMotion + SettingsStore.reducedMotion into single reduceMotion: Bool. Distributes to engine via applyAccessibility(_:). shouldExecuteMVWarp(presetEnabled:) and shouldExecuteSSGI per-frame queries. Beat amplitude 0.5 (reduced) / 1.0 (normal).
    DefaultPlaybackActionRouter.swift → Concrete PlaybackActionRouter per D-050 / U.6b. @unchecked Sendable, @MainActor. AdaptationFields snapshot type returned by adaptationFields(at:). Seven router methods (moreLikeThis, lessLikeThis, reshuffleUpcoming, presetNudge(_:immediate:), rePlanSession, undoLastAdaptation, toggleMoodLock). Family-boost cap 0.3, family-exclusion window 600s, ambient-hint window 90s, override ceiling 8s, undo capacity 8. Static live(engine:toastBridge:onShowPlanPreview:) factory wires weak engine refs.
    DelayProviding.swift    → Protocol for injectable sleep (RealDelay + InstantDelay); makes retry loops unit-testable without wall-clock waits.
    DisplayChangeCoordinator.swift → @MainActor; subscribes to DisplayManager publishers; calls FrameBudgetManager.resetRecentFrameBuffer() on active-screen removal or window move. No session-state changes. D-061(a). Event enum (.screenAdded / .screenRemoved(wasActive:) / .windowMovedToScreen) for tests.
    DisplayManager.swift    → @MainActor ObservableObject. NSScreen tracking + window-move coordination across displays. Handles fullscreen quirk (exit → move → re-enter for cross-screen fullscreen) with 3s cleanup. Publishes allScreens / currentScreen / primaryScreen. onScreensAdded / onScreensRemoved callbacks consumed by MultiDisplayToastBridge.
    FirstAudioDetector.swift → @MainActor ObservableObject (UX_SPEC §6.3). Monitors AudioSignalState; latches hasDetectedAudio after ≥250 ms sustained .active state. .suspect doesn't cancel; .silent/.recovering cancel; second .active doesn't restart.
    FullscreenObserver.swift → @MainActor ObservableObject wrapping NSWindow.didEnterFullScreenNotification / didExitFullScreenNotification; publishes isFullscreen: Bool.
    LiveAdaptationToastBridge.swift → User-action ack toast bridge (U.6 Part C). emitAck(_:) gated on phosphene.settings.visuals.showLiveAdaptationToasts UserDefaults (default true). 2-second coalescing window. Consumed by DefaultPlaybackActionRouter (11 call sites). Engine-driven adaptations (boundary reschedule / mood override) intentionally do NOT toast — the visual change is the feedback (UX_SPEC §7.4 / CA.5-FU-2 product decision); the docstring states this correctly (the earlier CA.5-FU-2 drift was resolved).
    LocalizedCopy.swift     → App-layer bridge from UserFacingError to localized user-facing strings. string(for:), bodyString(for:), cta(_:), containsJargon(_:). 11-term jargon deny-list (MPSGraph, FFT, IRQ, DRM, NSURLError, sandbox, G-buffer, SSGI, MIR, StemCache, AudioHardware) per UX_SPEC §9.5.
    MultiDisplayToastBridge.swift → @MainActor; wires DisplayManager.onScreensAdded/Removed to ToastManager. Screen added → info toast + "Move Phosphene there" action; current-screen removed → warning toast + auto-move to primary. (The CA.5-FU-1 dead fields `coalesceTask` / `pendingEvents` have since been removed — only `toastManager` + `displayManager` remain.)
    NetworkRecoveryCoordinator.swift → @MainActor; wires ReachabilityMonitor to SessionManager.resumeFailedNetworkTracks(); 2s additional debounce (3s total); 3-attempt cap per session; state guard via injected sessionStatePublisher. D-061(d,e).
    OnboardingReset.swift   → Static UserDefaults-key reset utility. Keys: phosphene.onboarding.photosensitivityAcknowledged.
    PlaybackErrorBridge.swift → @MainActor; routes UX_SPEC §9.4 audio-signal silence errors to ToastManager with condition-ID semantics. silenceToastThresholdSeconds=15s. Replaces older 30s SilenceToastBridge.
    PlaybackErrorConditionTracker.swift → @MainActor lightweight register of asserted condition IDs. assert / clear / isAsserted / reset. Used by PlaybackErrorBridge + tests.
    PlaybackKeyMonitor.swift → @MainActor; installs NSEvent local monitor for in-session keyboard shortcuts during .playing state. Routes via PlaybackShortcutRegistry.
    PlaybackShortcutRegistry.swift → @MainActor; declarative catalog of in-session shortcuts. ShortcutCategory (.playback / .liveAdaptation / .developer). PlaybackShortcut struct with matches(event:) API. Built at PlaybackView.onAppear; consumed by PlaybackKeyMonitor + ShortcutHelpOverlayView. Includes BUG-007.4 bar-phase cycling, BUG-007.6 audio-latency tweak, Arachne spider easter egg, preset debug cycling.
    PreparationETAEstimator.swift → Value type (struct). Rolling EMA over per-stage durations (resolving / downloading / stemSeparation / caching). minSamplesRequired=3 before estimate returns non-nil; emaAlpha=0.3.
    PresetScoringContextProvider.swift → @MainActor; canonical builder of PresetScoringContext consumed by the Orchestrator (DefaultPlaybackActionRouter.getScoringContext closure wires to it). Resolves DeviceTierOverride against detected tier (U.8 Part C).
    ReachabilityMonitor.swift → @MainActor ReachabilityPublishing protocol + ReachabilityMonitor concrete (NWPathMonitor with 1s debounce) + StubReachabilityMonitor test double.
    SessionRecorderRetentionPolicy.swift → Static utility. Session-folder pruning at app launch. 60s active-session guard (never delete folders modified within 60s). Policies: .keepAll / .lastN10 (default) / .lastN25 / .oneDay (86_400s) / .oneWeek (604_800s).
    SettingsMigrator.swift  → One-shot UserDefaults key migration on app launch. Current mapping: phosphene.showLiveAdaptationToasts → phosphene.settings.visuals.showLiveAdaptationToasts.
    SettingsStore.swift     → @MainActor final class ObservableObject; the single app-wide instance per D-091 / Failed Approach #55 (SettingsStoreEnvironmentRegressionTests enforces). 9 @Published fields. Keys enum for all UserDefaults keys.
    SpotifyKeychainStore.swift → SpotifyKeychainStoring protocol + SpotifyKeychainStore concrete using SecItem*. Default service "com.phosphene.spotify", account "refresh_token". U.11.
    SpotifyOAuthPlaylistConnector.swift → PlaylistConnecting wrapper; remaps spotifyLoginRequired (HTTP 403) to spotifyPlaylistInaccessible when authenticated. U.11.
    SpotifyOAuthTokenProvider.swift → public actor SpotifyOAuthTokenProvider: SpotifyTokenProviding, SpotifyOAuthLoginProviding. PKCE auth-code OAuth flow. expiryMarginSeconds=300, loginTimeoutSeconds=300, redirect "phosphene://spotify-callback", scopes "playlist-read-private playlist-read-collaborative". makeLive(urlSession:) factory. U.11 / D-069.
    SpotifyURLKind.swift    → Enum: .playlist(id:) / .track(id:) / .album(id:) / .artist(id:) / .invalid.
    SpotifyURLParser.swift  → Pure enum; static parse(_ input:) → SpotifyURLKind; handles HTTPS, spotify: URI, @-prefix, query params, podcasts.
  ViewModels/
    SessionStateViewModel.swift → @MainActor ObservableObject bridging SessionManager.state → SwiftUI; publishes state + reduceMotion (sourced from AccessibilityState per U.9).
    ConnectorPickerViewModel.swift → @MainActor ObservableObject; NSWorkspace observers (nonisolated(unsafe)) for AM launch/terminate; 250ms debounce; localFolderEnabled=false gating local-folder tile to disabled state.
    AppleMusicConnectionViewModel.swift → State machine (.idle / .connecting / .noCurrentPlaylist / .notRunning / .permissionDenied / .error / .connected); 2s auto-retry via DelayProviding; cancelRetry() on view disappear.
    SpotifyConnectionViewModel.swift → State machine, 12 cases (.empty / .parsing / .preview / .rejectedKind / .invalid / .rateLimited / .notFound / .privatePlaylist / .requiresLogin / .waitingForCallback / .authFailure / .error); 300ms paste-debounce; [2s, 5s, 15s] rate-limit retry sequence; U.11 PKCE OAuth `loginAction` injected from ConnectorPickerView.
    PlaybackChromeViewModel.swift → @MainActor ObservableObject driving the auto-hiding overlay chrome during .playing. **Load-bearing BUG-015 / D-091 / QR.4 currentTrackIndex consumer** — binds engine.$currentTrackIndex publisher directly (NO lowercased title+artist string match per Failed Approach #56). Publishes TrackInfoDisplay (LF.6: carries `albumArtData: Data?` — bound via `Publishers.CombineLatest(currentTrackPublisher, currentTrackArtworkDataPublisher)` so title + artwork project atomically), PresetDisplay, OrchestratorDisplayState, SessionProgressData, isLocalFileSession (LF.5.fix D-LF5-3 — drives LocalFileTransportBar + TrackInfoCardView empty-slot visibility). 3s auto-hide via DelayProviding; activity restarts the timer.
    ReadyViewModel.swift → @MainActor ObservableObject for ReadyView (U.5). Owns FirstAudioDetector (UX_SPEC §6.3 — ≥250ms .active latches hasDetectedAudio); 90s Task.sleep timeout per UX_SPEC §6.4; shouldAdvanceToPlaying PassthroughSubject signals first-audio confirmation; subscribes to plan publisher for trackCount + estimatedDuration.
    PreparationProgressViewModel.swift → @MainActor ObservableObject; subscribes to PreparationProgressPublishing.trackStatusesPublisher + SessionManager.$progressiveReadinessLevel; owns PreparationETAEstimator (rolling EMA per stage); publishes ordered [RowData] + PreparationCounts + canStartNow + showCancelConfirmation. 6.1 progressive readiness drives canStartNow ≥ .readyForFirstTracks.
    PreparationErrorViewModel.swift → @MainActor ObservableObject; subscribes to status publisher + ReachabilityMonitor; recomputes PreparationPresentationState (.normal / .banner(UserFacingError) / .fullScreen(UserFacingError)) via 5-rule priority ordering (offline → all-failed → rate-limited → first-track-90s → total-120s → normal). 5s recompute timer keeps banner/full-screen state fresh as elapsed time crosses thresholds.
    PlanPreviewViewModel.swift → @MainActor ObservableObject for PlanPreviewView (U.5 Parts B + D). Builds [PlanPreviewRow] from PlannedSession + plan publisher subscription. Manages manuallyLockedTracks (Set<TrackIdentity>) + lockedPresets ([TrackIdentity: PresetDescriptor]) for D-058 / U.5 Part D regeneration; isRegenerating flag drives spinner.
    EndSessionConfirmViewModel.swift → @MainActor ObservableObject; isPresented + requestEnd / confirm / cancel. Owned by PlaybackView as @StateObject; Esc-triggered confirmation per UX_SPEC §7.7.
    SettingsViewModel.swift → @MainActor ObservableObject; observable facade over SettingsStore (no @StateObject SettingsStore inside — D-091 / Failed Approach #55 compliant; the store flows in via init). Forwards 10 binding properties + about (AboutSectionData: appVersion / buildNumber / macOSVersion / gpuFamily via MTLCreateSystemDefaultDevice().name). Actions: openSessionsFolder / resetOnboarding / copyDebugInfo. U.8.
    ToastManager.swift → @MainActor ObservableObject; FIFO queue, max 3 visible. Auto-dismiss via per-toast Task<Void, Never>; condition-ID dismissal for PlaybackErrorBridge silence-toast lifecycle. dropOldest() favours non-degradation eviction. U.7.
  Views/
    MetalView.swift         → NSViewRepresentable wrapping MTKView with RenderPipeline as delegate. Takes context: MetalContext + pipeline: RenderPipeline from PlaybackView; framebufferOnly=false so SessionRecorder can blit-read the drawable.
    DebugOverlayView.swift  → Developer debug overlay (D key). Bottom-leading SwiftUI surface — raw diagnostics complementary to the top-trailing SwiftUI dashboard cards (BEAT/STEMS/PERF). Tempo / standalone QUALITY / standalone ML rows removed in DASH.6 (now in PERF/BEAT cards); MOOD V/A, Key, SIGNAL block, MIR diag, SPIDER, G-buffer, REC remain. Both surfaces are gated on `if showDebug`; the `D` shortcut toggles the same SwiftUI `@State` that drives both layers (DASH.7, D-087).
    FullScreenErrorView.swift → Reusable full-screen error layout for UX_SPEC §9.1 / §9.2 errors. Takes error: UserFacingError + primary/secondary actions. Spacing 28; max-width 520.
    QualityGradeIndicator.swift → Colored dot + letter code for SignalQuality (U.9 Part C).
    SettingsView.swift      → Settings sheet (U.8 Part B). NavigationSplitView over Audio / Visuals / Diagnostics / About sections. `@StateObject SettingsViewModel` constructed via custom init(store: SettingsStore) — D-091 compliant (store flows in via init). Window 720 × 520; minimum 480 × 360.
    TrackPreparationRow.swift → Single row in the preparation progress list. Custom accessibility label aggregating title + artist + status + ETA. Used by PreparationProgressView.
    TrackPreparationStatusIcon.swift → Small icon component for TrackPreparationRow. static let size = 28pt.
  Views/Dashboard/             → SwiftUI dashboard overlay (DASH.7 / DASH.7.1 / DASH.7.2, supersedes Renderer/Dashboard's Metal composer + DASH.6).
    DashboardOverlayView.swift → Top-trailing single panel containing three `DashboardCardView` typographic sections separated by `border` dividers. Per-card chrome retired in DASH.7.1. Surface is `DarkVibrancyView` (NSVisualEffectView pinned to `.vibrantDark` + `.hudWindow`) + `Color.surface` tint at **0.96α** + 1px `border` stroke + `.environment(\.colorScheme, .dark)` lock — guarantees the panel renders dark regardless of macOS Appearance setting (DASH.7.2, D-089). Sits as PlaybackView Layer 6, conditionally rendered on `showDebug` with a spring-damped fade+offset transition. Width fixed at 320pt.
    DashboardCardView.swift    → Renders one `DashboardCardLayout` as a typographic section (no chrome of its own). Title in **Clash Display Medium @ 15pt** (or system semibold fallback), resolved via `DashboardFontLoader.resolveFonts()`. Rows stack at `layout.rowSpacing`.
    DashboardRowView.swift     → Switches over the 4 row variants (`.singleValue` / `.bar` / `.progressBar` / `.timeseries`). **DASH.7.2 (D-089) inlined `.singleValue`** — label-LEFT + Spacer + value-RIGHT at 13pt mono, matching `.bar` and `.progressBar` row rhythm; the 24pt hero-numeric was retired. `.progressBar` value column widened to 110pt with `.fixedSize(horizontal: true)` so FRAME `"20.0 / 14ms"` no longer truncates. Sparkline rendered via SwiftUI `Canvas` (filled area + stroked line + centre baseline). Labels use **Epilogue Medium @ 11pt** (or system medium fallback) with `labelTracking`. Numeric values stay SF Mono. **No SF Symbols** — status reads through value-text colour only (D-088). When `valueText.isEmpty` (STEMS rows), the right-side numeric column collapses entirely.
    DarkVibrancyView.swift     → `NSViewRepresentable` wrapping `NSVisualEffectView` with `.appearance = NSAppearance(named: .vibrantDark)`, `.material = .hudWindow`, `.blendingMode = .withinWindow`. Used as the dashboard panel backdrop so the surface stays dark on macOS Light appearance (DASH.7.2, D-089). Replaces SwiftUI's appearance-adaptive `.regularMaterial`.
    DashboardOverlayViewModel.swift → `@MainActor ObservableObject`. Subscribes to `VisualizerEngine.$dashboardSnapshot`, throttles to ~30 Hz (`.throttle(for: .milliseconds(33))`), maintains private `MutableStemHistory` rings for the timeseries STEMS card, publishes `[DashboardCardLayout]`. `ingestForTest(_:)` test seam bypasses the throttled subscription.
    ConnectorType.swift     → Enum: .appleMusic/.spotify/.localFolder; title/subtitle/systemImage
    ConnectorTileView.swift → Reusable tile: icon + title/subtitle; disabled state with alt caption + optional secondary action button
    ConnectorPickerView.swift → NavigationStack in sheet; three tiles; navigationDestination(for: ConnectorType.self)
    AppleMusicConnectionView.swift → Five-state connection view (connecting/noCurrentPlaylist/notRunning/permissionDenied/error); onConnect fires on .connected
    SpotifyConnectionView.swift → URL paste field; preview card; rejectedKind copy; rate-limit retry indicator; error body
    LocalSourceConnectionView.swift → GAP A destination for the Local Folder tile in ConnectorPickerView. Three understated action tiles (folder / single file / M3U playlist) each opening the matching NSOpenPanel via LocalFileMenuCommands; typographic drop-hint footer (no dashed-rectangle iconography per .impeccable.md); inline LocalFileErrorBanner above the tiles (GAP F). Dark background — the visualizer is the product, this is dissolving chrome.
    Onboarding/PermissionOnboardingView.swift → Screen-capture permission explainer; "Open System Settings" CTA (U.2)
    Onboarding/PhotosensitivityNoticeView.swift → One-time photosensitivity sheet on IdleView first appearance (U.2)
    Idle/IdleView.swift     → .idle state; "Connect a playlist" sheet CTA + "Start listening now" ad-hoc CTA (U.3)
    Connecting/ConnectingView.swift → .connecting state (QR.4): per-connector spinner (Apple Music / Spotify / Local Folder / generic), localized headline (no trailing ellipsis per UX_SPEC §8.5), per-connector subtext, cancel CTA wired to sessionManager.cancel(). Takes `source: PlaylistSource?` + `onCancel: () -> Void`.
    Preparation/
      PreparationProgressView.swift → .preparing state: per-track status + partial-ready CTA. Owns @StateObject PreparationProgressViewModel + @StateObject PreparationErrorViewModel + @State NetworkRecoveryCoordinator (D-061(d,e)). Three presentation modes (.normal / .banner / .fullScreen) driven by errorViewModel.presentationState.
      PreparationFailureView.swift → Full-screen replacement for the .preparing state when all tracks failed or network offline. Two recovery CTAs: pick playlist (primary) + start reactive (secondary, optional).
      TopBannerView.swift → Amber warning strip above the track list for non-blocking preparation errors per UX_SPEC §5.6 / §9.3.
    Ready/
      ReadyView.swift → .ready state: "Press play in your music app" + first-audio autodetect + 90s timeout overlay (UX_SPEC §6.3 + §6.4). @StateObject ReadyViewModel. PlanPreviewView sheet from Preview-Plan button. Multiple accessibility IDs (.headlineID, .previewPlanButtonID, .endSessionButtonID, .retryButtonID, .timeoutOverlayID).
      PlanPreviewView.swift → Sheet presenting the session plan (U.5 Parts B + D). @StateObject PlanPreviewViewModel. Regenerate button wired to viewModel.regeneratePlan(); Modify button gated behind #if ENABLE_PLAN_MODIFICATION.
      PlanPreviewRowView.swift → One track row: number + title + artist + preset + family pill + duration. Preset swap menu (TODO: U.5.C row-tap preview).
      PlanPreviewTransitionView.swift → Small connector between two rows showing the transition style.
      ReadyPulsingBorder.swift → Ambient pulsing border overlay (2.5s animation; respects reduceMotion).
    Playback/
      PlaybackView.swift → .playing state: six-layer ZStack (MetalView / TrackChangeAnimationView / PlaybackChromeView / ShortcutHelpOverlayView / DebugOverlayView / DashboardOverlayView) + end-session confirmation dialog. Owns 4 @StateObject ViewModels + 7 @State services (DisplayChangeCoordinator, FullscreenObserver, PlaybackKeyMonitor, MultiDisplayToastBridge, PlaybackErrorBridge, DisplayManager, actionRouter: DefaultPlaybackActionRouter) + @EnvironmentObject engine + @EnvironmentObject settingsStore (D-091 compliant, regression-locked by SettingsStoreEnvironmentRegressionTests). Setup wires LiveAdaptationToastBridge → DefaultPlaybackActionRouter.live(engine:toastBridge:onShowPlanPreview:) → PlaybackShortcutRegistry → PlaybackKeyMonitor.
      PlaybackChromeView.swift → Overlay chrome composition. @ObservedObject PlaybackChromeViewModel. Composes 5 subviews (TrackInfoCardView + PlaybackControlsCluster + PreparationBackgroundIndicator + ListeningBadgeView + ToastContainerView). Auto-hides per UX_SPEC §7.2.
      TrackInfoCardView.swift → Top-left card. LF.6: HStack of a 48 × 48 pt artwork slot (cornerRadius 6) + text column (title + artist + preset name + orchestrator state pill, green=planned / orange=reactive). Artwork renders via `AlbumArtworkCache.image(for:cacheKey:)` (cacheKey = `title|artist`) when `TrackInfoDisplay.albumArtData != nil`, else a restrained `music.note.list` glyph on a tinted tile. `showArtworkSlot = (albumArtData != nil) || isLocalFileSession` — streaming sessions with no artwork hide the slot entirely (text-only chrome, pre-LF.6 geometry) until LF.6.streaming. Card maxWidth 320 → 380. Artwork slot is `.accessibilityHidden(true)`.
      LocalFileTransportBar.swift → GAP C / LF.5.fix D-LF5-3 bottom-center transport bar, rendered only when `PlaybackChromeViewModel.isLocalFileSession`. Stop / Prev / Play-Pause / Next geometric glyphs (coral focal play-pause on a purple-backlit cluster); Play/Pause glyph driven by `isLocalFilePaused`. Phosphene IS the player for LF sessions, so these controls are honest (UX-2 exception — unlike streaming, where playback controls would lie).
      PlaybackControlsCluster.swift → Top-right cluster: SessionProgressDotsView + settings gear + close button.
      SessionProgressDotsView.swift → Track-list progress dots. Three rendering branches: reactive mode (pulsing circle); > 30 tracks (text); else dots grid. Respects reduceMotion.
      ListeningBadgeView.swift → Top-center badge for sustained silence (≥3s per UX_SPEC §6.3). Replaces the legacy NoAudioSignalBadge (U.6 rename).
      OverlayBackdropStyle.swift → Shared ≥ 4.5:1 contrast backdrop ViewModifier (UX_SPEC §7.2). .ultraThinMaterial + 0.45α black tint + 10pt corner radius. Exposed as .overlayBackdrop() View extension.
      ShortcutHelpOverlayView.swift → Full keyboard shortcut reference shown on Shift+?. Categorizes via ShortcutCategory.allCases (.playback / .liveAdaptation / .developer).
      ToastContainerView.swift → Bottom-trailing stack of up to 3 visible toasts. @ObservedObject ToastManager. Posts accessibility announcements for new toasts.
      ToastView.swift → Per-toast cell. Severity accent bar (gray/orange/red); 320pt max-width.
      TrackChangeAnimationView.swift → Animated center-to-top-left track announcement on boundary. 1.8s total animation (0.3s easing + 1.0s hold + 0.5s spring). Respects reduceMotion.
    Ended/EndedView.swift   → .ended state (QR.4): session-summary card. Takes `trackCount: Int`, `sessionDuration: TimeInterval?` (nil → em-dash placeholder; full plumbing deferred per D-091.8), `onStartNewSession: () -> Void` (wired to sessionManager.cancel() — the documented .ended → .idle path), `onOpenSessionsFolder: () -> Void`. Coral primary CTA, secondary "Open sessions folder" via NSWorkspace.
    Settings/
      AboutSettingsSection.swift → App version / build / macOS / GPU + debug-info copy CTA (U.8 Part B). Read-only (no SettingsStore mutations).
      AudioSettingsSection.swift → Audio quality-hints (informational text only). Capture-mode + source-app picker removed in CLEAN.2.3.5 (per-app capture deleted). (U.8)
      DiagnosticsSettingsSection.swift → Session recorder + retention + open sessions folder + reset onboarding (U.8). Bindings to .sessionRecorderEnabled, .sessionRetention.
      VisualsSettingsSection.swift → Device tier + quality ceiling + reduced motion + preset family blocklist + Milkdrop toggle (DEBUG-gated) + live-adaptation toasts + show-uncertified-presets (U.8). Bindings to 7 SettingsViewModel properties.
      LocalFilesSettingsSection.swift → GAP G local-file cache + recents management. Shows the persistent-cache footprint (`engine.localFileCacheBytes` publisher), a Clear Local-File Cache action (`PersistentStemCache.clearAll`), and a Clear Recents action (`LocalFileRecentsStore`).
      PresetCategoryBlocklistPicker.swift → Reusable multi-select picker over PresetCategory.allCases. @Binding selection: Set<PresetCategory>. Used by VisualsSettingsSection.
      SourceAppPicker.swift → Multi-row picker over NSRunningApplication filtered by activationPolicy==.regular. @Binding selection: SourceAppOverride?. Used by AudioSettingsSection when capture mode is .specificApp.

PhospheneEngine/
  Audio/
    Audio                   → Module marker (imports + module-level header noting Core Audio taps as primary capture path per FA #29 / #21 / #22)
    SystemAudioCapture      → Core Audio tap: system-wide or per-app. FA #21 verified: .systemAudio uses stereoGlobalTapButExcludeProcesses: []; .application uses stereoMixdownOfProcesses: [PID] (non-empty array, the prohibited empty-array form does not appear).
    AudioInputRouter        → Unified source: .systemAudio/.application/.localFile/.localFilePlayback → callbacks. Wires SilenceDetector + tap-reinstall state machine; immutably captures tap sample rate via per-buffer callback (D-079/QR.1). onAnalysisFrame / onRenderFrame callbacks declared but unwired pending LookaheadBuffer product call. .localFilePlayback delegates to LocalFilePlaybackProvider (LF.1 / D-128); does NOT install a process tap.
    AudioInputRouter+SignalState → Tap-reinstall state machine (ARCH §68): backoff 3s → 10s → 30s; three attempts; cancel-on-active; re-check state before performing the install. Mode-gated: scheduler is dormant in .localFile + .localFilePlayback modes (LF.1 / D-128) — those modes have no process tap to reinstall.
    LocalFilePlaybackProvider → LF.1 spike (D-128, 2026-05-27). Plays a local audio file through the default output device via AVAudioEngine + AVAudioPlayerNode; installs a tap on the player node's output bus (pre-mixer, pre-volume) and forwards interleaved float32 PCM through onAudioSamples. Loops at EOF. Observes AVAudioEngineConfigurationChange and restarts on fire. Bypasses Core Audio process taps; no screen-capture permission required.
    LookaheadBuffer         → production-orphan + planned-consumer (CA-Audio-FU-2 resolved 2026-05-21 — KEPT per Matt). Timestamped ring buffer, dual read heads (analysis + render), configurable 2.5s delay. Zero production instantiations today; planned consumers: Phase MV anticipatory preset transitions (mv_warp crossfade completes ON the structural boundary instead of after), drop-anticipation visual telegraphing, beat-aligned switches to the exact frame, MILKDROP_ARCHITECTURE.md musicality.
    AudioBuffer             → IO proc → UMARingBuffer<Float> bridge for GPU
    FFTProcessor            → vDSP 1024-pt FFT → 512 magnitude bins in UMABuffer. printHistogram(barCount:) debug API has zero production consumers (CA-Audio-FU-6).
    SilenceDetector         → DRM silence state machine: .active → .suspect (1.5s) → .silent (3s) → .recovering → .active (0.5s hold). Module-internal class (not public); only consumed by AudioInputRouter.
    InputLevelMonitor       → Continuous tap-quality assessment: rolling peak dBFS (21s decay time constant via 0.9995 per-update decay at ~94 Hz) + 3-band spectral EMAs → SignalQuality (green/yellow/red) with reason string. Peak-only classification after session 2026-04-17T21-05-47Z showed treble-ratio thresholds fired false positives on bass-heavy tracks. Hysteresis (30-frame hold) prevents log flapping. Logged to session.log on quality transitions via VisualizerEngine+Audio. No dedicated tests today (CA-Audio-FU-5).
    StreamingMetadata       → AppleScript polling of Apple Music/Spotify, track change detection
    MetadataPreFetcher      → Parallel async queries, LRU cache, merge partial results, 3s per-fetcher timeouts. CA.3 Session ↔ Audio boundary-noted item resolved by CA-Audio. Producer of PreFetchedTrackProfile (Shared); consumer at SessionPreparer.swift:299 + App track-change runtime path.
    MusicBrainzFetcher      → Free API, genre tags + duration. Always-on in buildFetcherList().
    SpotifyFetcher          → REMOVED in the CLEAN.2.1 follow-up (2026-06-14). Was an optional, env-gated (SPOTIFY_CLIENT_ID + SPOTIFY_CLIENT_SECRET) Client-Credentials-flow fetcher calling /v1/search for duration only; never active in normal runs and redundant with iTunes/MusicBrainz/Now Playing duration. Its removal eliminated the last Spotify client secret from the codebase. (Unrelated and still present: the Session-layer SpotifyWebAPIConnector — OAuth user-token flow, /items endpoint — where FAs #45-47 + BUG-005 live.)
    SoundchartsFetcher      → Optional commercial API (SOUNDCHARTS_APP_ID/SOUNDCHARTS_API_KEY env vars). Decodes time_signature correctly; BUG-013 is the upstream API not returning the field, not a parser defect.
    MusicKitBridge          → production-orphan + planned-consumer (CA-Audio-FU-3 resolved 2026-05-21 — KEPT per Matt). Contains MusicKitFetcher class (file/type name mismatch noted as cosmetic). Zero production wiring (not in buildFetcherList()); zero test sites. fetchBPM(for:) is a stub today (MusicKit Swift SDK does not expose tempo; the underlying REST catalog API does). Planned consumers: Apple Music first-class metadata path (wire into buildFetcherList() for AM users); direct-catalog-API tempo fetch via api.music.apple.com/v1/catalog/{storefront}/songs/{id}; future-proof against MusicKit Swift SDK exposing Song.tempo; queue-awareness scaffolding.
    Protocols               → AudioCapturing, AudioBuffering, FFTProcessing, MoodClassifying (re-export from ML), StemSeparating (re-export from ML), MetadataProviding, MetadataFetching; plus value types AudioSignalState, TrackChangeEvent, PartialTrackProfile, StemSeparationResult/Error, MoodClassificationError
  DSP/
    DSP.swift               → Module marker (imports only)
    SpectralAnalyzer        → Spectral centroid, rolloff, flux via vDSP
    BandEnergyProcessor     → 3-band + 6-band energy, AGC, FPS-independent smoothing
    ChromaExtractor         → 12-bin chroma (≥500 Hz floor), Krumhansl-Schmuckler key estimation, bin-count normalized
    BeatDetector            → 6-band onset detection, grouped beat pulses, tempo via autocorrelation. recordOnsetTimestamps sources from result.onsets[0] (sub_bass per-band events), never fuses bands (D-075).
    BeatDetector+Tempo      → IOI-based tempo via computeStableTempo: trimmed-mean IOI over the trailing 10 s window (median, drop outliers outside [0.5×, 2×], mean of inliers, BPM = 60/meanIOI). Histogram still built but consumed only by the diagnostic dump (D-075). Plus estimateTempo (autocorrelation fallback). Halving-only octave correction at BPM > 175 (BUG-009; sub-80 doubling deleted per D-079).
    BeatDetector+TempoDiagnostics → DSP.1 baseline-capture instrumentation. dumpHistogram + dumpEarly + dumpTempoTimestamp gated behind BEATDETECTOR_DUMP_HIST=1; optional file output via BEATDETECTOR_DUMP_FILE=<path>. Silent in production.
    BeatGrid                → Codable/Hashable/Sendable value type for Beat This!-resolved offline grids. offsetBy / halvingOctaveCorrected / overridingBeatsPerBar / localTiming / nearestBeat / beatIndex(at:). Forward-extrapolates beat times to a horizon for live-window grids (BUG-R001).
    BeatGridResolver        → Stateless transformer: Beat This! per-frame beat/downbeat probabilities → BeatGrid. 7-frame max-pool peak picking, ±40 ms downbeat-to-beat snap, trimmed-mean IOI BPM, median-downbeat-IOI meter (D-073/D-075/D-077).
    BeatThisPreprocessor    → Beat This! log-mel preprocessor (sr=22050, nFFT=1024, hop=441, nMels=128, fMin=30, fMax=11000, Slaney scale, frame-length normalization). Zero-alloc post-init; NSLock-guarded.
    LiveBeatDriftTracker    → DSP.2 S7 primary beat-phase path. Onset-matched drift tracking against cached BeatGrid (±50 ms window, EMA α=0.4). Variance-adaptive tight-match window [30 ms, 80 ms] (BUG-007.5). BPM-aware lock-release gate `max(2.5 s, 4 × medianPeriod)` (BUG-007.5 part 3). Bar-phase auto-rotate with kick-on-1+3 tiebreaker (BUG-007.4b/4c). Per-track grid-onset calibration via setGrid(_:initialDriftMs:) (BUG-007.8) and runtime hybrid recalibration via applyCalibration (BUG-007.9). audioOutputLatencyMs (BUG-007.6) + visualPhaseOffsetMs apply to the display path only — onset matching uses unmodified playbackTime.
    MIRPipeline             → Coordinator: all analyzers → FeatureVector for GPU. Prefers LiveBeatDriftTracker for beat-phase when grid is installed; falls back to BeatPredictor in reactive mode (D-078). Drives StructuralAnalyzer + writes latestStructuralPrediction (currently consumed only at prep time — CA.1 audit finding).
    MIRPipeline+Recording   → Manual MIR-only CSV recording to ~/phosphene_features.csv (1 Hz throttled, 17 columns). Bound to `R` keyboard shortcut. Distinct from SessionRecorder's auto per-session features.csv (different path, different schema, different cadence).
    BeatPredictor           → Reactive-mode fallback IIR beat-phase predictor when no offline grid: rising-edge onset → period estimate → beatPhase01/beatsUntilNext in FeatureVector (MV-3b, D-028). Bypassed whenever LiveBeatDriftTracker.hasGrid is true.
    PitchTracker            → YIN autocorrelation pitch detector (vDSP_dotpr, 2048-sample window, 80–1000 Hz, local-minimum refinement). Internal ring buffer accumulates 1024-sample live increments before YIN runs (PT.1 fix, 2026-05-19; pre-fix the live path zero-padded the buffer and confidence was structurally 0). → vocalsPitchHz/Confidence in StemFeatures (MV-3c, D-028).
    SelfSimilarityMatrix    → Ring buffer of feature vectors, vDSP cosine similarity (600 frames × 16 features)
    NoveltyDetector         → Checkerboard kernel boundary detection, adaptive threshold (mean + 1.5σ), min-peak-distance gate
    StructuralAnalyzer      → Section boundary prediction (70% duration consistency + 30% repetition similarity), feeds latestStructuralPrediction on MIRPipeline. CA.1 audit note: runtime per-frame work currently consumed only at preparation time by SessionPreparer.
    StemAnalyzer            → Per-stem energy (4× BandEnergyProcessor) + beat (1× BeatDetector on drums) + rich metadata (MV-3a) + PitchTracker (MV-3c) → StemFeatures (64 floats, 256 bytes)
    StemAnalyzer+RichMetadata → Per-stem onset rate / centroid / attack ratio / energy slope computation. Fast/slow RMS EMAs (50/500 ms), rising-edge flux onsets with 100 ms refractory, 0.5 s decay window, ×2.0 rate multiplier.
  ML/
    ML.swift                 → Module entry-point marker (just `import Foundation`).
    BeatThisModel.swift      → Top-level Beat This! transformer wrapper. `public final class BeatThisModel`. Hyperparameters as public static lets (embedDim=128, numHeads=4, headDim=32, numBlocks=6, ffnDim=512, inputMels=128, outputClasses=2). NSLock-guarded `predict(spectrogram:frameCount:)` and `predictDiagnostic(...)` (DSP.2 S8 layer-diff anchor). Internal `tMax = 1500` frame window. D-077.
    BeatThisModel+Frontend   → PartialFTTransformer frontend: stem BN1d→Conv2d(4×3) → 3 PartialFT blocks (bi-directional F/T attention + RoPE 4D + gating + downsampling Conv2d(2×3)) → BN2d → GELU → projection to (tMax, 128). Block dims (32,32) → (64,16) → (128,8). PyTorch-spec ordering: partial → conv → norm → GELU (DSP.2 S8 fix).
    BeatThisModel+Graph      → Encoder graph: 6 transformer blocks (manual RMSNorm + manual SDPA + RoPE 3D paired-adjacent rotation, all macOS 14 workarounds) → post-norm → head linear → beat/downbeat logits via sigmoid. RoPE base 10000; SDPA scale 1/√headDim.
    BeatThisModel+Ops        → MPSGraph primitive helpers: BeatLinearSpec, buildRMSNorm (eps=1e-6), buildGELU (tanh-approx with PyTorch constants), buildLinear, makeConst/makeOnesConst/makeZerosConst. All internal.
    BeatThisModel+Weights    → Manifest parser + 161-tensor loader from Sources/ML/Weights/beat_this/. 8.4 MB Float32. BN-fusion at load (eps=1e-5). Conv weight rearrangement OIHW→HWIO. Weight structs: BeatThisWeights / BeatThisFrontendBlockWeights / BeatThisTransformerBlockWeights / BeatThisAttnWeights / BeatThisFFNWeights / BeatThisFusedBN.
    StemSeparator.swift      → STFT → MPSGraph → iSTFT pipeline, StemSeparating protocol. Public static lets: nFFT=4096, hopLength=1024, nBins=2049, modelSampleRate=44100, stemCount=4, modelFrameCount=431, requiredMonoSamples=440320. NSLock-guarded UMA buffer writes. BUG-012-i1 instrumentation hooks via `BUG012Probe`.
    StemSeparator+Reconstruct → iSTFT reconstruction + mono averaging (vDSP_vadd + vDSP_vsmul). Internal.
    StemModel.swift          → MPSGraph Open-Unmix HQ engine (`StemModelEngine`), pre-allocated UMA I/O buffers (inputMagL/R, outputBuffers per stem). 172 tensors / ~136 MB loaded at init; single graph hosts all 4 stems. NSLock-guarded `predict()`.
    StemModel+Graph          → MPSGraph construction: per-stem subgraph (input slice 1487 bins → FC1(2974→512) + BN1 + Tanh → 3-layer bidirectional LSTM hidden=256 → concat → FC2(1024→512) + BN2 + ReLU → FC3(512→4098) + BN3 + denorm → ReLU mask × input → output [431, 2, 2049]). 4 stem subgraphs sharing the same input placeholder.
    StemModel+Weights        → Weight manifest parsing + .bin loading + BN fusion (eps=1e-5) + bidirectional-LSTM weight assembly (forward + reverse stacked per MPSGraph contract). PyTorch bias_ih + bias_hh summed per direction before stacking.
    StemFFT.swift            → STFT/iSTFT engine entry: `StemFFTEngine` + `StemFFTEngineProtocol`. NSLock-guarded forward/inverse. Hann window, vDSP setup, MPSGraph forward/inverse resources. BUG-012-i1 instrumentation: dispatch-ID allocation, in-flight counters with ALARM-on-overflow, lock await/release log lines. `forceCPUFallback` for cross-validation testing.
    StemFFT+CPU              → Accelerate vDSP STFT/iSTFT fallback (cross-validation + non-431-frame inputs). Center-padded, DC/Nyquist packing per vDSP_fft_zrip convention. Internal.
    StemFFT+GPU              → MPSGraph forward/inverse path. `runForwardGraph()` is the DOCUMENTED BUG-012 EXC_BAD_ACCESS crash site (address 0x8, force-dispatch race; instrumentation in place per BUG-012-i1, diagnosis pending next reproduction). vDSP-vs-MPSGraph amplitude convention: forward × 2 for vDSP parity; inverse round-trips at unity gain via HermiteanToRealFFT scalingMode=.size.
    MoodClassifier.swift     → vDSP_mmul MLP (10 → 64 ReLU → 32 ReLU → 16 ReLU → 2 tanh) + EMA smoothing (α=0.1, ~0.7 s @ 94 Hz). MoodClassifying protocol. Hardcoded z-score scaler means/stds matching `tools/data/mood_scaler.json`.
    MoodClassifier+Weights   → Hardcoded Float32 weight arrays (3,346 params total: 640+64+2048+32+512+16+32+2). Extracted by `tools/extract_mood_weights.py` from a Float16 CoreML model.
  Renderer/
    MetalContext            → MTLDevice, command queue, triple-buffered semaphore, shared-texture helper
    ShaderLibrary           → Auto-discover .metal files, runtime compilation, cache
    RenderPipeline          → Render graph dispatch, feedback ping-pong, activePasses guarded by passesLock
    RenderPipeline+Draw     → Per-frame render-graph executor (renderFrame). Walks activePasses, dispatches the first available pass. MV-2 multi-pass flow: when .mvWarp is present, a preceding .rayMarch pass renders to warpState.sceneTexture and continues the loop instead of returning. Fallback path is drawDirect.
    RenderPipeline+DirectDraw → NB.8 half-resolution direct-render path (Nimbus). `setDirectRenderScale(_:)` opts a `direct` preset into rendering its fragment to a 0.5× offscreen `halfResTarget` then bilinearly upscaling to the drawable (`feedback_blit` + linear-clamp sampler) — ~4× cheaper for a body that swells to fill the frame. `drawDirect` branches on the scale; the shared slot-binding contract lives in `encodePresetVisualization`. Default 1.0 (every other preset full-res, unaffected); the half-res target is pre-allocated at preset apply. MetalFX is NOT wired (Temporal needs motion vectors a procedural volume lacks → ghosting); the bilinear upscale substitutes, appropriate for soft gas. Worst-case Nimbus body ~2.6 ms half-res march + ~0.3 ms upscale ≈ 3 ms (vs ~7.6 ms full-res), well under the 7 ms Tier-2 ceiling.
    RenderPipeline+MeshDraw → Mesh shader draw: drawWithMeshShader. Delegates to MeshGenerator (native M3+ mesh or M1/M2 vertex fallback).
    RenderPipeline+PostProcess → HDR post-process: drawWithPostProcess (stand-alone path; ray-march presets get bloom via PostProcessChain.runBloomAndComposite instead).
    RenderPipeline+FeedbackDraw → Milkdrop-style global feedback path (Membrane). FeedbackDrawContext value type + 2-mode (particle vs surface) dispatch + ping-pong texture swap.
    RenderPipeline+RayMarch → Ray march draw: drawWithRayMarch + per-frame audio-reactive SceneUniforms modulation (light intensity from any-band beat, lightColor from valence, fogFar from arousal, camera dolly from features.time, glass-fin position from bass). Reads BaseSceneSnapshot for additive-on-baseline behaviour. Plus the 150ms-τ aurora-drums EMA smoother (V.9 Session 4.5c / D-127) and the optional per-preset compute dispatch hook (V.9 Session 4.5b Phase 2b — currently nil in production).
    RenderPipeline+MVWarp   → MV-2 per-vertex feedback warp (D-027): MVWarpPipelineBundle (+ feedbackFormat), MVWarpState, setupMVWarp, drawWithMVWarp (3-pass: warp grid → scene-pass → blit + texture swap; Pass-2 delegates to encodeMVWarpScenePass, Pass-3 binds the float4 comp `post` incl. the Dragon Bloom beat pump), clearMVWarpState, reallocateMVWarpTextures, setMVWarpDecay. The `strandsOnTop` branch (sceneGeometry attached → Dragon Bloom) runs the faithful butterchurn loop. AV.2.1 black-clear-on-allocation. Reduced-motion fallback skips the accumulator (single-frame render).
    RenderPipeline+MVWarpScene → mv_warp scene helpers + comp beat pulse (D-138): renderSceneToTexture (default direct presets, binds slots 1/2/3/6/7/8 + noise + scene-geometry overlay); encodeMVWarpScenePass (Dragon Bloom = strands normal-alpha on top of the no-decay warp; else = standard decayed compose); mvWarpBeatPulse (beatComposite smoothstep(0.78,1)→sharp-attack/0.85-decay envelope for the comp pump).
    RenderPipeline+ICB      → Indirect command buffer: drawWithICB, populate compute + execute render. Test-active (RenderPipelineICBTests) but production-orphan today — no preset declares "icb" in passes and no production setICBState call. Deliberately deferred per VisualizerEngine+Presets.swift:305 comment.
    RenderPipeline+Staged   → V.ENGINE.1 per-preset staged composition (Arachne V.7.7B+). StagedStageSpec value type; ordered stage list with per-stage offscreen .rgba16Float textures (non-final) + drawable (final). Earlier stages' outputs sampled at fragment texture(13)+. Per-preset fragment buffers 6/7/8 bound uniformly across every stage.
    RenderPipeline+BudgetGovernor → applyQualityLevel(_:): translates FrameBudgetManager.QualityLevel into per-subsystem flags (SSGI on/off, bloom on/off, ray-march step count 0.75×, particle fraction 0.5×, mesh density 0.5×). Each level is a strict superset of the previous (D-057).
    RenderPipeline+PresetSwitching → All per-preset setter API: setActivePipelineState, setFeedbackParams, setMeshGenerator/+PresetBuffer/+PresetTick/+PresetFragmentBuffer, setParticleGeometry, setPostProcessChain, setRayMarchPipeline, setFeatures (mood-preserving per D-024), setMood, setStemFeatures, setDirectPresetFragmentBuffer{,2,3} (D-092/D-094/D-LM-buffer-slot-8), setRayMarchPresetHeightTexture/+ComputeDispatch (V.9 Session 4.5b), setMeshGBufferEncoder (V.9 Session 4.5c — Ferrofluid Ocean round-57 retirement set nil in live), setDynamicTextOverlay/+TextOverlayCallback.
    FrameBudgetManager      → Pure-state frame timing governor: QualityLevel ladder (full→noSSGI→noBloom→reducedRayMarch→reducedParticles→reducedMesh), asymmetric hysteresis (3 overruns down / 180 frames up), per-tier Configuration factories, reset() on preset change. Exposes recentMaxFrameMs/recentFramesObserved (30-slot rolling window) via FrameTimingProviding for ML scheduling. D-057, D-059.
    MLDispatchScheduler     → Pure-state ML dispatch controller: gates stem separation dispatch onto frame-timing-clean moments. Decision enum (dispatchNow/defer/forceDispatch), DispatchContext value type, decide(context:) algorithm. Tier defaults: 2000ms/30-frame (Tier 1), 1500ms/20-frame (Tier 2). FrameTimingProviding protocol for testability. D-059.
    RayMarchPipeline        → Deferred 3-pass: G-buffer textures, lighting pipeline, composite pipeline. reducedMotion is an OR-gate: a11yReducedMotion || governorSkipsSSGI (D-054, D-057). stepCountMultiplier written to sceneParamsB.z each frame. Owns lumenPlaceholderBuffer (568B zero-filled slot-8 fallback per D-LM-buffer-slot-8) + ferrofluidHeightPlaceholderTexture (1×1 r16Float zero-fallback for texture(10)). meshGBufferEncoder branch (V.9 Session 4.5c Phase 1 Step B / Failed Approach #66) — set via setMeshGBufferEncoder; nil in live production since Ferrofluid Ocean round 57. depthDebugEnabled/runDepthDebugPass cluster is currently dead (CA.7a-FU-2).
    RayMarchPipeline+Passes → Per-pass encoders: runGBufferPass, runMeshGBufferPass (FA#66 mesh branch), runLightingPass, runSSGIPass, runSSGIBlendPass, runDepthDebugPass (dead — CA.7a-FU-2), runGBufferDebugPass (G key), runCompositePass. Slot-8 (LumenPatternState) + slot-10 (FerrofluidParticles height) placeholder fallbacks live here.
    RayMarchPipeline+PipelineStates → Static factory buildPipelineBundle returning compiled lighting/SSGI/SSGI-blend/composite/gbufferDebug/depthDebug pipeline states + sampler. Single call site: RayMarchPipeline.init.
    PostProcessChain        → HDR scene texture, bloom ping-pong, 4 pipeline states, ACES composite. bloomEnabled gates bright-pass + blur; composite always runs for ACES tone-mapping. runBloomAndComposite is the ray-march integration path (consumes externally-rendered HDR scene texture from RayMarchPipeline).
    IBLManager              → Irradiance cubemap (32²) + prefiltered env (128², 5 mips) + BRDF LUT (512²)
    TextureManager          → 5 noise textures via Metal compute at init, bound at texture(4–8)
    DynamicTextOverlay      → Per-frame CPU text rasterization via Core Text + Core Graphics into a 2048×1024 .rgba8Unorm shared (UMA) MTLTexture. CTM permanently flipped to match Metal's top-left UV convention. Bound at fragment texture(12) for presets that declare text_overlay: true (SpectralCartograph mode label).
    Protocols               → Rendering protocol (AnyObject, MTKViewDelegate, Sendable; required setActivePipelineState(_:)). Concrete: RenderPipeline.
    Geometry/ParticleGeometry → Protocol for per-preset particle compute+render pipelines (D-097). Three members: update(features:stemFeatures:commandBuffer:), render(encoder:features:), activeParticleFraction. AnyObject + Sendable. `RenderPipeline.particleGeometry` storage and `setParticleGeometry(_:)` API are typed as `(any ParticleGeometry)?`. Future particle presets each ship their own conformer rather than parameterizing a shared pipeline.
    Geometry/ProceduralGeometry → GPU compute particle system for Murmuration: UMA buffer + compute + render pipelines. activeParticleFraction scales compute dispatch count (governor gate). Conforms to `ParticleGeometry` (D-097); the conformance is the only Murmuration-side change in DM.0 — kernel names, particle count, drag, decay rate are unchanged.
    Geometry/MeshGenerator  → M3+ mesh shader + M1/M2 vertex fallback, draw dispatch abstraction. densityMultiplier passed at object/mesh buffer(1) for M3+ opt-in; no-op on M1/M2 vertex path.
    Geometry/ParticleGeometryRegistry → Catalog of preset names with a registered `ParticleGeometry` conformer (`Set<String> = ["Murmuration"]`). Mirrors the dispatch table in `VisualizerEngine.resolveParticleGeometry`. `ParticleDispatchRegistryTests` walks the production preset catalog and asserts every preset whose `passes` contains `.particles` is listed here — closes the silent-fall-through hole where a JSON-side typo in the preset name would render an audio-driven backdrop with no particles. D-097.
    RayTracing/BVHBuilder   → MTLPrimitiveAccelerationStructure, blocking + non-blocking paths. **Production-orphan** (test-only consumers, no production preset binds it today); CA.7b confirms planned consumer is `Arachne3D` per D-096 V.8.0-spec (V.8.x deferred per 2026-05-08 sequencing call). Keep-or-retire decision: CA.7b-FU-3.
    RayTracing/RayIntersector → Compute-pipeline intersector, nearest-hit + shadow kernels (`rt_nearest_hit_kernel` + `rt_shadow_kernel` in `Shaders/RayTracing.metal`). Same production-orphan + planned-consumer status as BVHBuilder; same CA.7b-FU-3 decision.
    RayTracing/RayIntersector+Internal → Internal sub-structures + `packed_float3` vs `SIMD3<Float>` size-ambiguity workarounds. Documents the per-vertex-attribute layout the ray-intersector kernel expects. SceneUniforms (`AudioFeatures+SceneUniforms.swift:9`) cross-references this file's `packed_float3` discussion.
    Dashboard/DashboardFontLoader → Resolves Epilogue (Regular + Medium TTF) and Clash Display (Medium OTF/TTF) from bundle `Fonts/` subdir; falls back to system sans / semibold; OSAllocatedUnfairLock-guarded cache; `resetCacheForTesting()` test seam. One-shot resolution at app launch via `PhospheneApp.swift:44`. (DASH.1 + DASH.7.1 / D-088.)
    Dashboard/DashboardCardLayout → Pure value type: title + ordered Row enum (.singleValue / .bar / .progressBar / .timeseries) + fixed width + padding/title size/row spacing. Stacked rows — label on top, value below — heights single=39 (11pt label + 4pt gap + 24pt value), bar=32 (11pt label + 4pt gap + 17pt bar+value band), progressBar=32 (matches bar — same visual mass), timeseries=47 (11pt label + 4pt gap + 32pt sparkline+value band). `.bar` is signed-from-centre (D-082). `.progressBar` is unsigned 0–1 left-to-right fill, used for ramps (beat phase, bar phase, frame budget) — DASH.3, D-083. `.timeseries` carries an `[Float]` sample buffer + range + valueText + fillColor for the STEMS sparklines (DASH.7, D-087). `height` computed from `padding + titleSize + (rowSpacing + rowHeight)×N + padding`; titleSize term contributes 0 when title is empty. DASH.2 + DASH.2.1 + DASH.3 + DASH.7, D-082, D-083, D-087.
    Dashboard/BeatCardBuilder → Pure Sendable struct mapping `BeatSyncSnapshot` → `DashboardCardLayout` for the BEAT card. 4 rows in display order: MODE / BPM / BAR / BEAT. Lock-state colour mapping (DASH.7.2, D-089 — AAA contrast on dark surface): REACTIVE / UNLOCKED `textBody`, LOCKING `coral`, LOCKED `teal`. BAR fill `purple` (DASH.7.2, was `purpleGlow` which failed 3:1 on dark). BEAT fill `coral` (D-083). No-grid (`gridBPM <= 0`) emits `—` placeholders with bars at zero. BEAT phase derived as `barPhase01 × beatsPerBar − (beatInBar − 1)` clamped to [0, 1]. DASH.3 → DASH.7.1 → DASH.7.2, D-083 + D-088 + D-089.
    Dashboard/StemsCardBuilder → Pure Sendable struct mapping `StemEnergyHistory` → `DashboardCardLayout` for the STEMS card. **DASH.7 supersedes DASH.4; DASH.7.1 corrects colour**: 4 `.timeseries` rows (sparklines) in percussion-first order DRUMS / BASS / VOCALS / OTHER, range `-1.0 ... 1.0`, uniform `Color.teal` (stem indicators are MIR data per `.impeccable.md`). `valueText` is empty — the sparkline IS the readout (Sakamoto-liner-note discipline, D-088). Empty samples render baseline only — stable absence-of-signal state. DASH.4 → DASH.7 → DASH.7.1, D-084 + D-087 + D-088.
    Dashboard/PerfSnapshot → Sendable value type wrapping renderer governor (`FrameBudgetManager.recentMaxFrameMs` / `currentLevel` / `recentFramesObserved` / `configuration.targetFrameMs`) + ML dispatch state (`MLDispatchScheduler.lastDecision` encoded as `Int` decision code + optional `defer` retry delay in ms) for the PERF card. Decision/quality enums encoded as `Int + displayName: String` so the snapshot is trivially `Sendable` without importing the manager enums. 7 fields total + `.zero` neutral default. DASH.5, D-085.
    Dashboard/PerfCardBuilder → Pure Sendable struct mapping `PerfSnapshot` → `DashboardCardLayout` for the PERF card. **Dynamic row count** (DASH.7) + **brand-aligned, AAA-contrast status colours** (DASH.7.1 → DASH.7.2): FRAME always present (`.progressBar`, `"{recent} / {target}ms"` compact value text, status colour `teal` (healthy) / `coral` (stressed) at 70% budget threshold via `warningRatio` constant); QUALITY hides when governor is `full` AND warmed up — surfaces in `coral` when downshifted; ML hides on idle / `dispatchNow` — surfaces in `coral` only on `defer` / `forceDispatch`. Card collapses to one row in steady-state happy path. Uses only the project's brand palette (purple/coral/teal + neutrals); the `statusGreen` / `statusYellow` tokens are retired from this builder, and DASH.7.2 promoted `coralMuted` → `coral` for AA contrast on the dark surface. DASH.5 → DASH.7 → DASH.7.1 → DASH.7.2, D-085 + D-087 + D-088 + D-089.
    Dashboard/StemEnergyHistory → Sendable value type holding up to 240 recent samples per stem (drums / bass / vocals / other), oldest first. Capacity ≈ 8 s at 30 Hz. Held privately by `DashboardOverlayViewModel` as a mutable ring; snapshotted into this immutable form for `StemsCardBuilder.build(from:)` per redraw. DASH.7, D-087.
    Dashboard/DashboardSnapshot → Sendable bundle of `(BeatSyncSnapshot, StemFeatures, PerfSnapshot)` for one frame. Published from `VisualizerEngine.@Published dashboardSnapshot` on each rendered frame; consumed by `DashboardOverlayViewModel` via Combine with `.throttle(for: .milliseconds(33))` (~30 Hz). `Equatable` synthesized for `PerfSnapshot`; `BeatSyncSnapshot` + `StemFeatures` use private `bytewiseEqual<T>` (no Equatable conformance broadened on shared types — D-086 Decision 4 stands). DASH.7, D-087.
    Shaders/Common.metal    → FeatureVector / FeedbackParams / StemFeatures / SceneUniforms MSL structs, hsv2rgb, fullscreen_vertex, feedback shaders. `FeatureVector` is 192 bytes / 48 floats and `StemFeatures` is 256 bytes / 64 floats — byte-identical to the preset preamble in `PresetLoader+Preamble.swift`. The first 32 / 16 floats match the pre-MV-1/MV-3 layout exactly so existing engine-library readers (Murmuration's `particle_update`, MVWarp shaders, feedback shaders) are byte-identical; the extended tail (MV-1 deviation primitives, MV-3a per-stem rich metadata, MV-3b beat phase, MV-3c vocals pitch) is locked for future engine kernels and currently unused after Drift Motes' removal (D-102) — see D-099 for the rationale.
    Shaders/MVWarp.metal    → Default engine-library mvWarp implementations (mvWarp_vertex_default, identity warpPerFrame/Vertex); the fragment shaders presets actually compile against are the per-preset INJECTED copies in PresetLoader+WarpPreamble (mvWarp_fragment / _compose_fragment / _blit_fragment) — those carry the D-138 Dragon Bloom additions (chromatic transfer + no-decay + comp `post`). MVWarp.metal's plain copies remain for the engine-library default path.
    Shaders/MeshShaders.metal → Mesh pipeline structs, object/mesh/fragment + fallback vertex shaders
    Shaders/Particles.metal → Murmuration compute kernel (`particle_update`) + bird silhouette vertex/fragment (`particle_vertex` / `particle_fragment`). Declares the shared `Particle` (64 bytes, `packed_float4 color`) and `ParticleConfig` (32 bytes) MSL structs once for the engine library.
    Shaders/PostProcess.metal → Bright pass, Gaussian blur H/V, ACES composite
    Shaders/RayTracing.metal → RT structs, nearest-hit kernel, shadow kernel, camera ray utils
    Shaders/RayMarch.metal   → Cook-Torrance PBR deferred lighting (IBL ambient tinted by lightColor), composite fragment, depth/G-buffer debug pipelines
    Shaders/SSGI.metal       → Screen-space global illumination (8-sample spiral, half-res, additive blend)
    Shaders/NoiseGen.metal   → Compute kernels: gen_perlin_2d, gen_perlin_3d, gen_fbm_rgba, gen_blue_noise
    Shaders/IBL.metal        → IBL generation kernels + sampling utilities
  Presets/
    Presets.swift           → Module marker (imports only).
    PresetLoader            → Auto-discover, compile standard + additive + mesh + ray march pipelines, skip utility files.
    PresetLoader+Preamble   → Shared preamble: FeatureVector struct → V.1 Noise utility tree → V.1 PBR utility tree → ShaderUtilities → noise samplers → preset code. Forwards `sceneSDF(p, FeatureVector& f, SceneUniforms& s, StemFeatures& stems)` and `sceneMaterial(p, matID, f, s, stems, albedo, roughness, metallic)` so ray-march presets can do per-stem routing (Milkdrop-style) directly in sceneSDF/sceneMaterial. StemFeatures plumbed through G-buffer fragment call sites. Presets should apply the D-019 warmup fallback `smoothstep(0.02, 0.06, totalStemEnergy)` to mix between FeatureVector proxies and stem direct reads (see VolumetricLithograph for reference implementation). MSL preamble for FeatureVector (48 floats / 192 B) + StemFeatures (64 floats / 256 B) byte-identical to the Swift-side @frozen structs per D-099 / DM.2.
    PresetLoader+Mesh       → Mesh-shader pipeline compilation path: object/mesh/fragment shaders for M3+ + vertex fallback for M1/M2. Walks `meshPipelineState(for:device:library:)` per preset.
    PresetLoader+Utilities  → Discovery helper: identifies Shaders/Utilities/ files (V.1 / V.2 / V.3 / V.4 trees) that must be linked via preamble injection but NOT compiled as standalone presets. The "skip utility files" half of PresetLoader.
    PresetLoader+WarpPreamble → MV-2 mv_warp preamble injection (D-027): MVWarpPerFrame struct + WarpVertexOut + warpSampler + forward declarations for preset `mvWarpPerFrame`/`mvWarpPerVertex` + the 32×24 grid `mvWarp_vertex` shader + the shared `mvWarp_fragment` / `mvWarp_compose_fragment` / `mvWarp_blit_fragment`. The fragment carries the Dragon Bloom faithful-warp colour transfer (normalise + hue-zoom resample + R→G→B transfer) gated by `chromaticMix` (0 ⇒ identity; custom-warp path applies NO decay); the blit carries the faithful comp — video echo (orient-1 mirror) → ×gamma → invert + a beat-pulse pump — via the float4 `post` uniform ((0,0,1,0) ⇒ identity). Both gated so non-Dragon-Bloom mv_warp presets are byte-identical (D-138). SceneUniforms `#ifndef SCENE_UNIFORMS_DEFINED` guard so direct (non-ray-march) mv_warp presets compile correctly.
    PresetDescriptor        → JSON sidecar: passes, feedback params, scene camera/lights, stem affinity, certified/rubric_profile/rubric_hints (V.6). `waitForCompletionEvent: Bool` for completion-gated transitions (BUG-011 round 8, V.7.6.2).
    PresetDescriptor+SceneUniforms → Constructs SceneUniforms from descriptor (camera basis, light, fog, near/far). FOV converted from JSON degrees → radians exactly once.
    PresetCategory          → 10 cream-of-crop aesthetic themes + transition slot (D-123). `family` is optional on PresetDescriptor; diagnostic presets carry no family.
    PresetMetadata          → ComplexityCost (tier1+tier2 ms-at-1080p budget), StemAffinity (per-stem weight 0–1), TransitionAffordance, FatigueRisk, SongSection enums. `cost(for: DeviceTier) -> Float` accessor on ComplexityCost. Sendable + Hashable + Codable throughout.
    PresetMaxDuration       → Per-section preset duration cap. Returns `.infinity` for diagnostic presets (D-074) and for `wait_for_completion_event: true` presets (BUG-011 round 8 / V.7.6.2). Otherwise applies the V.7.6.C `motion_intensity / fatigue / linger` formula bounded by the V.7.7 minSegmentDuration floor.
    PresetStage             → Staged-composition stage spec (V.ENGINE.1). `StagedStageSpec` value type: stage name + fragment function + sources (per-stage offscreen `.rgba16Float` textures sampled at `[[texture(13)]]+` in the next stage). Final stage renders to the drawable.
    SpectralCartographText  → SpectralCartograph diagnostic preset's bitmap-font text overlay support. Pre-computed 3×5 glyph tables for the inline session-mode label / BPM digits / per-panel header labels (no texture atlas — pure shader).
    Certification/RubricResult → Value types: RubricCategory (mandatory/expected/preferred), RubricItemStatus (pass/fail/exempt/manual), RubricItem, RubricProfile (full/lightweight), RubricResult, RuntimeCheckResults. (V.6)
    Certification/FidelityRubric → DefaultFidelityRubric: pure static + runtime rubric evaluator for SHADER_CRAFT.md §12. FidelityRubricEvaluating protocol. Heuristics: M1 cascade (scale markers/scale-literal count), M2 octave (fbmN/warped_fbm/ridged_mf), M3 materials (V.3 mat_* callsites ≥3), M4 deviation (D-026 fields present + no absolute-threshold anti-patterns), M5 silence (runtime), M6 perf (complexity_cost gate), M7 frame match (always manual). E1–E4 expected, P1–P4 preferred. Lightweight L1–L4 profile. (V.6)
    Certification/FidelityRubric+Mandatory → M1–M7 mandatory-rubric implementations extracted from FidelityRubric.swift. Per-item static evaluators + budget threshold lookup against `tier.frameBudgetMs`. Pale-tone-share ceiling (≤ 0.30 per D-LM-cream-rescission) is M7-manual-only here — NOT enforced as an automated item (CA-Presets-FU-5 reminder comment).
    Certification/FidelityRubric+Optional → E1–E4 (Expected) + P1–P4 (Preferred) rubric implementations extracted from FidelityRubric.swift. Non-blocking signals; surfaced in rubric output without affecting cert pass/fail.
    Certification/PresetCertificationStore → actor; loads and caches RubricResult for all production presets. Reads .metal + .json from Bundle.module Shaders dir. setResults(_:) for test injection. (V.6)
    Shaders/ShaderUtilities.metal → 55 reusable functions: noise, SDF, PBR, ray march, UV, color, atmosphere (legacy camelCase names)
    Shaders/Utilities/Noise/  → V.1 Noise utility tree (9 files, snake_case, D-045). Load order: Hash → Perlin → Simplex → FBM → RidgedMultifractal → Worley → DomainWarp → Curl → BlueNoise. Provides: hash_u32/f01 family, perlin2d/3d/4d, simplex3d/4d, fbm4/8/12/fbm_vec3, ridged_mf, worley2d/3d/fbm, warped_fbm/vec, curl_noise, blue_noise_sample/ign/ign_temporal.
    Shaders/Utilities/PBR/    → V.1 PBR utility tree (9 files, snake_case, D-045). Load order: Fresnel → NormalMapping → BRDF → Thin → DetailNormals → Triplanar → POM → SSS → Fiber. Provides: fresnel_schlick/roughness/dielectric/f0_conductor, ggx_d/g_schlick/g_smith, brdf_ggx/lambert/oren_nayar/ashikhmin_shirley/cook_torrance, decode_normal_map/dx, ts_to_ws/ws_to_ts, tbn_from_derivatives, combine_normals_udn/whiteout, triplanar_blend_weights/sample/normal, parallax_occlusion/shadowed (POMResult), sss_backlit/wrap_lighting, fiber_marschner_lite/trt_lobe (FiberBRDFResult), thinfilm_rgb/hue_rotate.
    Shaders/Utilities/Geometry/ → V.2 Geometry utility tree (6 files, snake_case, D-045/D-055). Load order: SDFPrimitives → SDFBoolean → SDFModifiers → SDFDisplacement → RayMarch → HexTile. Provides: 30 sd_* SDF primitives (sd_sphere/box/torus/cylinder/capsule/gyroid/schwarz_p/d/helix/mandelbulb_iterate/etc.), op_union/subtract/intersect/smooth_union/subtract/intersect/chamfer/blend, mod_repeat/mirror/twist/bend/scale/round/onion/extrude/revolve, displace_lipschitz_safe/fbm/perlin/beat_anticipation/energy_breath, ray_march_adaptive/normal_tetra/soft_shadow/ao (RayMarchHit struct), hex_tile_uv/weights (HexTileResult struct).
    Shaders/Utilities/Volume/   → V.2 Volume utility tree (5 files, snake_case, D-055). Load order: HenyeyGreenstein → ParticipatingMedia → Clouds → LightShafts → Caustics. Provides: hg_phase/schlick/dual_lobe/mie/transmittance/phase_audio, VolumeSample/vol_sample_zero/vol_density_*/vol_accumulate/vol_composite/vol_inscatter, cloud_density_cumulus/stratus/cirrus/cloud_march/cloud_lighting, ls_radial_step_uv/ls_shadow_march/ls_sun_disk/ls_intensity_audio, caust_wave/fbm/animated/audio.
    Shaders/Utilities/Texture/  → V.2 Texture utility tree (5 files, snake_case, D-055). Load order: Voronoi → ReactionDiffusion → FlowMaps → Procedural → Grunge. Provides: VoronoiResult/voronoi_f1f2/voronoi_3d_f1/voronoi_cracks/leather/cells, rd_pattern_approx/animated/spots/stripes/worms/rd_step/rd_colorize_tri, flow_sample_offset/blend_weight/curl_advect/noise_velocity/audio/layered, proc_stripes/checker/grid/hex_grid/dots/weave/brick/fish_scale/wood, grunge_scratches/rust/edge_wear/fingerprint/dust/dirt_mask/crack/composite (GrungeResult).
    Shaders/Utilities/Color/    → V.3 Color utility tree (4 files, snake_case, D-062). Load order: Palettes → ColorSpaces → ChromaticAberration → ToneMapping. Provides: palette/palette_warm/palette_cool/palette_neon/palette_pastel, gradient_2/3/5, lut_sample, rgb_to_hsv/hsv_to_rgb, rgb_to_lab/lab_to_rgb, rgb_to_oklab/oklab_to_rgb, chromatic_aberration_radial/directional, tone_map_aces/aces_full/reinhard/reinhard_extended/filmic_uncharted. Legacy palette() deleted from ShaderUtilities.metal; toneMapACES/toneMapReinhard retained as superseded aliases (D-062).
    Shaders/Utilities/Materials/ → V.3 Materials cookbook (5 files, snake_case, D-062). Load order: MaterialResult → Metals → Dielectrics → Organic → Exotic. Provides: MaterialResult struct, FiberParams, material_default, triplanar_detail_normal (3-param procedural, distinct from V.1 texture form), triplanar_normal (3-param overload), mat_polished_chrome, mat_brushed_aluminum, mat_gold, mat_copper, mat_ferrofluid, mat_ceramic, mat_frosted_glass, mat_wet_stone, mat_bark, mat_leaf, mat_silk_thread, mat_chitin, mat_ocean, mat_ink, mat_marble, mat_granite, mat_velvet, mat_sand_glints, mat_concrete. 19 surface-material recipes returning MaterialResult; callers unpack into sceneMaterial() out-params (D-062(c)). V.4 additions: mat_velvet (Organic — retro-reflective fuzz via pow(1-NdotV,2) fuzz term), mat_sand_glints (Exotic — hash-lattice sparkle via hash_f01), mat_concrete (Dielectrics — worley_fbm variation + fbm8 height-gradient normal + grunge). D-063.
    Shaders/Waveform.metal  → Spectrum bars + oscilloscope
    Shaders/Plasma.metal    → Demoscene plasma
    Shaders/Nebula.metal    → Radial frequency nebula
    Shaders/Murmuration.metal → Murmuration sky backdrop (`murmuration_sky_fragment`). Renamed from Starburst.metal in MM.0. Passes `["feedback", "particles"]` per D-029 (the MV-2 mv_warp conversion was reverted); the flock is the GPU compute kernel in Shaders/Particles.metal, the sky fragment is the backdrop. Phase MM is a full flock redesign in progress.
    Shaders/GlassBrutalist.metal → Brutalist corridor — static architecture; only the glass-fin X-position deforms with bass (Option A design, see DECISIONS D-020). Light/fog/colour modulated in shared Swift path.
    Shaders/KineticSculpture.metal → Interlocking lattice of Brushed Aluminum + Frosted Glass + Liquid Mercury, abstract ray march. FOV in degrees (post-fix; was radians, see commit history).
    Shaders/TestSphere.metal → Minimal pipeline-verification SDF (sphere + floor); used for end-to-end ray-march compile/render test.
    Shaders/SpectralCartograph.metal → Instrument-family diagnostic preset. Four-panel real-time MIR visualiser: TL=FFT spectrum (log-freq, centroid-coloured), TR=3-band deviation meters (D-026 compliant), BL=valence/arousal phase plot with 8s trail, BR=scrolling graphs for beat_phase01/bass_dev/bar_phase01 (BAR φ). Reads SpectralHistoryBuffer at buffer(5). Direct pass only; no feedback, no warp. V2 (DSP.2 sign-off): per-panel header labels via inline 3×5 bitmap font (no texture atlas); centered beat orb at (0.5,0.5) with amber fill keyed to beat_phase01 + white ring flash at onset + BPM digits above + session-mode label below; BR panel beat_phase01 row overlaid with cached-BeatGrid tick marks from SpectralHistoryBuffer[2402..2417] so zero-crossings can be visually verified against ground truth. Reactive mode: orb pulses via BeatPredictor fallback, ticks hidden (Float.infinity sentinel). DSP.3.1: session-mode label reads SpectralHistoryBuffer[2420] — `○ REACTIVE` (grey, no grid), `◐ PLANNED · UNLOCKED` (muted amber, grid present <4 matched onsets), `◑ PLANNED · LOCKING` (yellow-green, approaching lock), `● PLANNED · LOCKED` (bright green, locked). Diagnostic hold via `L` shortcut suppresses LiveAdapter mood-override; `is_diagnostic: true` in sidecar suppresses auto-selection.
    Shaders/Arachne.metal → Staged-composition orb-weaver (WORLD atmosphere stage + COMPOSITE web/spider/drops stage; `arachne_composite_fragment` samples WORLD at [[texture(13)]]). 4-slot `ArachneWebGPU` pool at fragment buffer(6) (96 B/slot, Row 5 BuildState drives the single foreground hero web); `ArachneSpiderGPU` 80 B at slot 7 (3D SDF spider easter egg). Operating do-nots: `docs/presets/ARACHNE_V8_DESIGN.md §Operating rules`. Full V.7.7A→V.7.7D design/tuning history: `docs/presets/ARACHNE_V8_DESIGN.md §Module-Map history` (split out at DOC.4, 2026-06-11). D-019/D-026/D-040/D-041/D-072/D-092/D-093/D-094/D-095 compliant.
    Arachnid/ArachneState.swift → V.7.7C.2: single-foreground build state machine on top of the legacy 4-web pool. `ArachneBuildState` struct (CPU-only) tracks the foreground hero web's progression through `.frame → .radial → .spiral → .stable → .evicting` over ~50–55 s of music, with audio-modulated TIME pacing (`pace = 1.0 + 0.18 × midAttRel + max(0, 0.5 × drumsEnergyDev)`, D-026 ratio ≈ 3.6×). Polygon (4–6 of 6 `kBranchAnchors`) selected at `reset()` via Fisher-Yates + bridge-pair largest-angular-gap; alternating-pair radial draw order computed `[0, n/2, 1, n/2+1, …]` (§5.5); spiral chord radii precomputed strictly INWARD; per-chord birth times appended at lay-down for §5.8 accretion. Pause guard evaluated BEFORE `effectiveDt` so spider trigger freezes accumulators and resume picks up exactly where it paused. `presetCompletionEvent` fires once at `.stable` via `PresetSignaling` conformance defined in `Sources/Orchestrator/ArachneStateSignaling.swift` (Presets cannot import Orchestrator without a module cycle — D-095 documents the placement deviation). `_presetCompletionEvent` is `public let` for the cross-module conformance to reach. `spiderFiredInSegment: Bool` per-segment cooldown replaces V.7.5's 300 s session lock (§6.5); reset on `arachneState.reset()`. `WebGPU` 96 bytes (Row 5 = packed BuildState; written only for `webs[0]`, background webs zero it). 1–2 saturated `ArachneBackgroundWeb` entries in `ArachneState+BackgroundWebs.swift` with migration crossfade timers (foreground 1 → 0.4 joins pool; oldest 1 → 0 evicts; 1 s ramp). V.7.5 pool spawn/eviction kept running additively but **no longer reaches the shader** (V.7.7C.3 / D-095 follow-up retired the pool loop visually). `branchAnchors` two-source-of-truth with MSL `kBranchAnchors[6]` regression-locked by `ArachneBranchAnchorsTests`. V.7.7D listening-pose state (`listenLiftAccumulator` / `listenLiftEMA`) lifts `tip[0]` / `tip[1]` CPU-side; `ArachneSpiderGPU` stays at 80 bytes. **V.7.7C.3 polygon flush**: `writeBuildStateToWebs0` packs `bs.anchors[]` (4-bit count + 6 × 4-bit indices) into `webs[0].rngSeed` (byte offset 28) via the new `Self.packPolygonAnchors(_:)` static helper. Shader decodes via `decodePolygonAnchors` to drive ray-clipped spoke tips + irregular frame thread + polygon-aware spiral chord positions. `webs[0].rngSeed` repurposing is safe — Fix 2 retired V.7.5 pool rendering, so `rngSeed` is no longer consumed by the spawn driver's per-spoke jitter on the shader side. `applyPreset .staged` for "Arachne" calls `arachneState.reset()` immediately after init (canonical polygon-seeding entry point). **BUG-011 round 8 (2026-05-12) — three behavioural changes**: (1) `ArachneBuildState.frameDurationSeconds 3.0 → 2.775` / `radialDurationSeconds 1.5 → 1.389` per radial; new `ArachneBuildState.spiralChordsPerBeat = 3.24` + `spiralChordAccumulator: Float` field carrying fractional residual across rising-edge beats. Total build ~100 s → ~92 s. (2) New `ArachneBuildState.stemEnergySilenceThreshold = 0.02`; `advanceBuildState` zeros `effectiveDt` when `vocalsEnergy + drumsEnergy + bassEnergy + otherEnergy < 0.02` — Arachne no longer constructs during silence / prep / source-app paused. `pausedBySpider` flag is set BEFORE the silence check so the spider-pause guard still latches correctly. (3) `Arachne.json` now sets `"wait_for_completion_event": true`; `PresetDescriptor.waitForCompletionEvent` short-circuits `maxDuration(forSection:)` to `.infinity` (same path as `isDiagnostic`) so segments are no longer capped at ~72 s by the V.7.6.C formula. Mood-override suppression added in `applyLiveUpdate` (active segment located by track-relative position; flagged presets get `presetOverride` stripped, `updatedTransition` honoured). The existing `wirePresetCompletionSubscription` path now delivers the transition trigger — Arachne builds reach `.stable` and emit `presetCompletionEvent`, which calls `nextPreset()`. Section boundaries still hard-stop segments (`remainingInSection` cap unchanged) — known limitation, acceptable for sections ≥ 60 s. (Increments 3.5.5 / V.7.7C.2 / V.7.7C.3 / D-095 / BUG-011 round 8)
    Shaders/Gossamer.metal → Bioluminescent hero-web sonic resonator (Increment 3.5.6, v3 geometry). Direct fragment + mv_warp. 17 explicitly-defined irregular spoke angles (spacing 0.27–0.77 rad, one 0.77 rad open sector lower-right). Hub at (0.465, 0.32) — upper screen — clips top spiral rings into asymmetric arcs naturally. No formula, no hash-jitter. Up to 32 propagating color waves emitted when vocalsPitchConfidence > 0.35 OR |vocalsEnergyDev| > 0.05; wave hue baked from YIN pitch, saturation from other-stem density. mv_warp trails accumulate wave echoes. Ambient drift floor keeps ≥2 waves at silence. D-026/D-019 compliant.
    Gossamer/GossamerState.swift → Per-preset world state: 32-wave pool, Wave structs with birthTime/hue/saturation/amplitude, GossamerGPU buffer (528 bytes) at fragment buffer(6). Vocal confidence gate + FV fallback. Retirement when age > maxWaveLifetime=6s. (Increment 3.5.6)
    AuroraVeil/AuroraVeilState.swift → Per-preset world state for the Aurora Veil mv_warp accumulator preset. Holds the silence-fallback ramp, the per-frame `vocalsPitchConfidence` smoother that drives the curtain hue + intensity bias, and the AV.2.x rebuild metadata. Slot-6 fragment buffer flush per frame. AV.2.1 mv_warp grounding documented in `AuroraVeil.metal`; this file owns the CPU-side wave/curtain bookkeeping.
    Nimbus/NimbusState.swift → Per-preset CPU world state for the certified Nimbus volumetric preset (`@unchecked Sendable` + NSLock; 32-byte `NimbusStateGPU` at fragment buffer(6) — byte-matched MSL mirror in `Nimbus.metal`). Owns: the slow `bloom` swell follower (fast-attack ~0.15 s / slow-release ~0.40 s over the mean of the four stem ENERGIES — never floored by one dead band, the NB.4→NB.5 fix; **NB.10 r1.6 recalibration `bloomGain 1.4→1.9` / `bloomOffset −0.2→−0.06` to the REAL ~0.30 stem-energy centre, not the assumed 0.5 — BUG-027 class; `test_bloomVisibleOnTypicalMusic` locks it**); four NB.5 stem followers (`kickPunch` ← anticipatory predicted-beat `smoothstep(0.82,1,beatPhase01)` ∥ `max(beatBass,beatComposite)` onset fallback, NB.8 beat-sync; `bassLobe`/`vocalsLobe`/`otherLobe` ← stem `…EnergyDev` smoothstep[0.12,0.55]); the `flowPhase` Double accumulator (long-accumulator rule) at a bloom+kick-modulated rate; the **NB.10 mood EMAs `smoothedValence`/`smoothedArousal` at ~2.5 s** (FA #25 — from the FeatureVector, never written back; D-024). Time-based **cold-start gate** (self-tracked `trackTime`, NOT `features.trackElapsedS` which the FFO toggle pins) crossfades FV-bass-proxy → live stems over ~9–13 s (fixes the cache-hit constant-snapshot freeze). `reset()` on preset apply + track change. (NB.4–NB.10, D-140/D-141/D-144)
    FerrofluidOcean/FerrofluidMesh.swift → Per-preset mesh / lighting state for Ferrofluid Ocean (rounds 50–67). Owns the smooth-Voronoi height field state (Robert Leitl reference port via Inigo Quilez smooth-min, post-round-65), the 4-component Phong/env/fresnel/iridescence lighting model state, and the §5.8-retired stage-rig replaced by D-127's direct sky/curtain-uniform path. Round 57 retired the mesh G-buffer encoder (`setMeshGBufferEncoder(nil)`); SDF path is the live dispatch. CLAUDE.md Failed Approach #66 (test/prod GPU-branch parity) regression-locked here.
    FerrofluidOcean/FerrofluidParticles.swift → Per-preset particle conformer for Ferrofluid Ocean. Conforms to `ParticleGeometry` (D-097 — siblings, not subclasses; not a `ProceduralGeometry` extension). Owns the particle compute kernel + render pipeline. Particles are pinned (one-shot bake at preset apply, NOT per-frame audio-coupled — V.9 Session 4.5b Phase 1 round 4 decision).
    FerrofluidOcean/FerrofluidParticles+InitialPositions.swift → Static helper: initial particle position generator (one-shot bake) — concentrated at the substrate plane with smooth-Voronoi-cell stratification so particles read as part of the substrate rather than free-floating.
    Arachnid/ArachneState+BackgroundWebs.swift → V.7.7C.2 background-web state: 1–2 saturated `ArachneBackgroundWeb` entries with migration crossfade timers (foreground 1 → 0.4 joins pool; oldest 1 → 0 evicts; 1 s ramp). Background webs flush to a separate slot-8 buffer (NOT the foreground hero web at slot 6 / 7).
    Arachnid/ArachneState+ListeningPose.swift → V.7.7D listening-pose state machine. `listenLiftAccumulator` advances during sustained low-attack-ratio bass; `listenLiftEMA` smooths the value for the per-frame `tip[0]` / `tip[1]` clip-space Y lift in `writeSpiderToGPU()`. CPU-side only — no GPU contract extension.
    Arachnid/ArachneState+Spider.swift → V.7.7D 3D ray-march SDF spider easter-egg state. `ArachneSpiderGPU` struct (80 B, D-094 invariant — `tip[8]` SIMD2<Float> + 4-Float header). Trigger gate on `features.bassAttRel > 0.30` per V.7.7C.3 (Failed Approach #57 lock prohibits the retired `subBass + bassAttackRatio < 0.55` combination). Per-segment `spiderFiredInSegment: Bool` cooldown.
    Arachnid/ArachneState+M7Diag.swift → V.7.7C M7 review-mode diagnostic state: forces specific build-stage progressions + spider-firing toggles for the `PresetVisualReviewTests` fixture without exercising the orchestrator transition machinery. Test-only effect surface — production code paths bypass when `m7DiagnosticEnabled == false`.
    [Stalker preset retired in Increment 3.5.7 — Shaders/Stalker.metal + Stalker/StalkerGait.swift + Stalker/StalkerState.swift were removed from the codebase. The spider's visual role was reborn as the 3D ray-march SDF easter egg inside Arachne (V.7.7D §6, see Arachnid/ArachneState.swift below). The gait solver, sustained-bass discriminator, and GPU buffer architecture were retained as learnings but the standalone preset no longer exists. See ENGINEERING_PLAN.md Increment 3.5.7 for the retirement rationale.]
    Shaders/Nimbus.metal → **Nimbus — the first certified `volumetric`-family preset (NB.1→NB.10, certified 2026-06-05 Matt M7; `Nimbus.json` `certified: true`, `"Nimbus"` ∈ `FidelityRubricTests.certifiedPresets`; D-140/D-141/D-144).** Single-pass 2D direct-fragment volumetric single-scatter ray-march (`passes: []`) composing the preamble-injected V.2 Volume tree — a glowing cool-gas body in a black void that moves with the music. **Density:** Perlin-Worley billows sampled from the `noiseVolume` 64³ 3D texture at `[[texture(6)]]` (NEVER per-step computed `fbm` — the §6.1 budget rule: computed `fbm4` was 20 ms @1080p, the texture is ~1.4 ms) + a 2-octave fractal-Worley detail cascade + interior cauliflower carve, shaped to a BOUNDED body by an analytic ellipsoidal envelope (`nimbus_envelope`) — the §1.4 "one mass, never `05_anti_uniform_fog`" idea-to-protect, gated by `test_bodyCoherenceNegativeSpace`. **Motion:** rising/curling smoke (vertical rise + helical twist + 2-octave organic swirl warp) on `flowPhase`. **Lighting:** BACKLIT forward-scatter (Beer-Powder × Henyey-Greenstein `hg_phase(·,kNimbusPhaseG)`) + a detail-aware cone self-shadow that uses a CHEAP 1-sample density (`nimbus_density_shadow` — the cost centre runs ~6×/in-body step; NEVER `pow()`/transcendentals in a per-march-step falloff, that doubled the budget). NO internal emission (an emission exploration was reverted — the packet is BACKLIT; DESIGN §5.2). **NB.5 (D-141) — the band plays the body:** `nimbus_envelope` heaves the SINGLE body per stem via `rr / (1 + kick + Σ lobe·cos²)` (star-convex — cannot fragment): drums punch + brighten the whole mass, bass↓ / lead↑ / other↔ (FA #4 honoured — beat is an accent on the slow bloom). **NB.10 mood (D-144):** body colour `mix(kNimbusMoodCool indigo-violet, kNimbusMoodWarm amber-gold, warm01)` where `warm01 = clamp((valence01 + energyWarm − 0.5)·kNimbusMoodContrast + 0.5)` and `energyWarm = kNimbusEnergyWarmth · smoothstep(kNimbusEnergyLo, kNimbusEnergyHi, arousal01)` — energy warms genuine high-arousal bangers WITHOUT washing the valence axis (the r1 warm-bias regression fix); the bright core keeps its MOOD HUE brightened (`kNimbusCoreHueGain`, NOT a near-white wash — the Billie Jean "white/gray" fix); arousal → flow agitation. **Reads ONLY `features.aspect_ratio` from the FeatureVector** — every music response arrives via the slot-6 `NimbusStateGPU` (bloom/flow/4 lobes/valence/arousal) + `noiseVolume`. Non-black haze floor (D-037). Renders at HALF-RES + bilinear upscale (NB.8, `RenderPipeline+DirectDraw`, `setDirectRenderScale(0.5)`). PresetRegression golden `0x0F0F0F0F0F0F0F0F` (identical across all 3 fixtures — the zeroed-slot-6 silence-floor silhouette; the shader reads no FV field but aspect_ratio). Known accepted-at-cert limitation: beat-grid live phase (D-145). D-026/D-037/D-140/D-141/D-144 compliant.
    Shaders/VolumetricLithograph.metal → Psychedelic linocut terrain (MV-2 / v4.1). fbm3D heightfield swept by `s.sceneParamsA.x` at slow rate 0.015; melody-primary blend `0.75 × (0.5 + f.mid_att_rel) + 0.35 × (0.3 + f.bass_att_rel × 0.7)` — deviation-driven, genre-stable across AGC shifts (MV-1 / D-026). Stem-accurate drivers blend in via `smoothstep(0.02, 0.06, totalStemEnergy)` warmup (D-019). Forward camera dolly at 1.8 u/s (configured in VisualizerEngine+Presets.swift). Three strata with narrow linocut coverage (~15% peaks): palette-tinted near-black valleys, razor-thin emissive ridge-line seam, polished-metal peaks. Peaks use IQ cosine `palette()` driven by terrain noise + audio time + `0.5 + f.mid_att_rel × 0.5` (melody-modulated hue) + valence. Accent/strobe from `smoothstep(0.30/0.70, stems.drums_beat)` with FV fallback `smoothstep(0.35, 0.70, f.spectral_flux)`. `f.mid_dev × 1.5` polishes peak roughness. `scene_fog: 0` truly disables fog. Miss/sky pixels tinted by `scene.lightColor.rgb`. SSGI omitted. MV-2: mv_warp pass adds temporal feedback accumulation — melody-driven zoom breath (mid_att_rel × 0.003), valence-driven rotation, decay=0.96; per-vertex UV ripple from bass (horizontal) and melody (vertical) at 0.004 UV amplitude. Passes: ray_march + post_process + mv_warp.
    Shaders/LumenMosaic.metal → Vibrant backlit pattern-glass panel (Phase LM CLOSED, **certified 2026-05-12 at LM.7**; `certified: true`, ∈ `FidelityRubricTests.certifiedPresets`). Layer stack in `sceneMaterial`: LM.4.6 per-cell uniform-random RGB palette (per-cell independence is the Matt-contract) → LM.6 cell-depth gradient + hot-spot (albedo-only; SDF normal stays flat) → frost diffusion → LM.7 per-track chromatic-projected tint. Slot-8 `LumenPatternState` (stride 376) + team/period beat-step ratchet. Golden hash `0xF0F0C8CCCCC8F0F0`. Full LM.3.2 → LM.7 palette/tuning history + active-constants table: `docs/presets/LUMEN_MOSAIC_DESIGN.md §Module-Map history` (split out at DOC.4, 2026-06-11).

    Lumen/LumenPatternEngine.swift → LM.4.7 per-preset world state. `LumenLightAgent` (32 B), `LumenPattern` (48 B), `LumenPaletteEntry` (16 B), `LumenPatternState` (**568 B** — was 376 B at LM.4.4, 360 B at LM.3, 336 B at LM.2; LM.3.2 added the four band counters; LM.4.3 reinterpreted bass/mid/treble as rate-of-advance buckets, not FFT-band semantics; LM.4.4 retired the pattern-spawn pool but kept the `patterns[4]` tuple for ABI continuity; **LM.4.7 added the `palette[12]` tuple at the tail for the curated palette payload — +192 B** — and the `trackPaletteSeed{A,B,C,D}` fields became zeroed dead-weight ABI continuity after LM.7's chromatic-tint formula was retired in favour of `LumenMosaicPaletteLibrary.selectPalette`) value types byte-identical to the matching MSL structs in `PresetLoader+Preamble.swift`. `LumenPatternEngine` final class (`@unchecked Sendable`, **failable `init?`**: returns nil if `device.makeBuffer(length: 568, options: .storageModeShared)` fails — BUG-016 candidate root cause where the silent-nil hides a Metal allocation failure; the App-side `applyPreset` consumes the nil with an `os.Logger.error` but does NOT log to session.log). Owns the 568-byte UMA buffer (`patternBuffer`) bound at fragment slot 8 of the ray-march G-buffer + lighting passes via `RenderPipeline.setDirectPresetFragmentBuffer3` while LumenMosaic is the active preset. Per-frame `tick(features:stems:)` (called from `RenderPipeline.meshPresetTick`) does two jobs (LM.4 pattern-spawn pool retired at LM.4.4): (1) advance the four light agents (drift + figure-8 dance + inset clamp — kept for ABI continuity, unused by LM.3.2+ shader), (2) call `updateBandCounters(features:)` which detects `f.beatPhase01` wraps (`prev > 0.85 && now < 0.15` → each grid beat); on each beat wrap `bassCounter += 1`, on every 2nd beat wrap `midCounter += 1`, on every 4th beat wrap `trebleCounter += 1` — all advances uniform `+1.0`, no energy modulation. `barCounter` no longer advances (it had no consumer outside the deleted pattern-spawn path). The wrap-edge state — `prevBeatPhase01` plus the `gridBeatsSinceMidStep / gridBeatsSinceTrebleStep` subdivision counters — lives on the engine. **`reset()` and `setTrackSeed(_:)` both call a private `resetBeatTrackingState()` helper** that zeroes the cell-dance counters + the wrap-edge state + the (now-permanently-zero) `state.patterns` snapshot. The `setTrackSeed` reset is load-bearing for cell colour identity: without the band-counter zero, the new track's cells would jump to a far-off palette index on beat 1. `setTrackSeed(fromHash:)` derives the seed from a 64-bit hash (FNV-1a over `title + artist` in `VisualizerEngine+Stems.resetStemPipeline(for:)`); the seed persists across all subsequent frames in that track (`_tick` does **not** clear it). `setAgentBasePositionForTesting(_:_:)` is the inset-clamp test seam (kept for ABI continuity even though agent positions are unused by the LM.3.2+ shader). `setPalette(_:)` writes a fresh 12-entry palette from `LumenMosaicPaletteLibrary.selectPalette(mood:recentPaletteIndices:trackSeed:)` at each track change (LM.4.7 / D-LM-palette-library). **Known limitation (LM.4.3 carry-over):** no FFT fallback. If `f.beatPhase01` never wraps (pure silence, or before the live BeatGrid lands in reactive sessions ~10 s in), no counters advance and the panel is visually static. Acceptable for prepared sessions (grid is installed at session start). LM.4.5 may add an FFT fallback if reactive ad-hoc sessions surface the gap.
    Lumen/LumenMosaicPaletteLibrary.swift → LM.4.7 curated palette library (D-LM-palette-library, BUG-014 resolution). 18 named palettes (Autumnal, Refn Glow, Glacier, Art Deco, Abyssal Bioluminescence, Kintsugi, Carnival, Holi, Geode, Rothko Chapel, Tropical Aviary, Persian Miniature, Ukiyo-e, Cathedral Lights, Cycladic, Ming Porcelain, Tenebrism, Obsidian) each with a `colors: [SIMD3<Float>]` (12 entries) and a `moodAnchor: SIMD2<Float>` in (valence, arousal). `selectPalette(mood:recentPaletteIndices:trackSeed:)` is a Gaussian-weighted draw: `weight = exp(−‖mood − anchor‖² / σ²)` with `kSigma = 0.35` + anti-repeat window `kAntiRepeatWindow = 3` + Mulberry32 PRNG seeded by track hash. Deterministic — same (mood, recent indices, seed) triple returns the same palette index. Consumer: App-side track-change callback writes the selected palette to `LumenPatternEngine.setPalette(_:)`, which flushes the 192-byte `palette[12]` tuple of `LumenPatternState`.
  Orchestrator/             → AI VJ: preset selection, transitions, session planning, live adaptation, reactive mode (Phase 4 complete — see ENGINEERING_PLAN.md; BUG-015 tracks the missing App-layer runtime invocation of `applyLiveUpdate(...)`)
    PresetScorer            → DefaultPresetScorer: 4 weighted sub-scores (mood 0.30 / tempoMotion 0.20 / stemAffinity 0.25 / sectionSuitability 0.25) + 2 multiplicative penalties (family-repeat 0.2× / fatigue smoothstep over 60/120/300 s) + 5-level hard exclusion (diagnostic / uncertified / session-excluded / family-excluded / complexity-cost / currently-playing). U.6b additive familyBoost. QR.2 / D-080 stem-affinity uses deviation primitives + mean + zero-balance neutral-0.5 guard. PresetScoring protocol. PresetScoreBreakdown for inspection. (D-032)
    PresetScoringContext    → Immutable Sendable snapshot: deviceTier, frameBudgetMs, recentHistory (capped 50 per D-080 rule 6), currentPreset, elapsedSessionTime, currentSection, excludedFamilies + temporarilyExcludedFamilies + sessionExcludedPresets (U.6b), qualityCeiling, familyBoosts, includeUncertifiedPresets. PresetHistoryEntry (presetID + family? + startTime + endTime). Deterministic; no Date.now().
    TransitionPolicy        → DefaultTransitionPolicy: structural boundary (confidence≥0.5, 2.5s window) beats duration-expired timer. TransitionDecision: trigger/scheduledAt/style/duration/confidence/rationale. Style from transitionAffordances + energy. `cutEnergyThreshold = 0.85` (raised from 0.7 per D-080 amendment to D-033). Crossfade duration scales 2.0s→0.5s with energy. TransitionDeciding protocol. Single planning-time consumer (DefaultSessionPlanner.buildTransition); DefaultLiveAdapter holds but never invokes the policy. (D-033)
    SessionPlanner          → DefaultSessionPlanner: greedy forward-walk composes PresetScorer + TransitionPolicy. SessionPlanning protocol. Synchronous plan() + async planAsync(precompile:) + seeded plan(seed:) per D-047. SessionPlanningError. Synthetic StructuralPrediction at the buildTransition site fires structuralBoundary trigger at every track boundary (planning-time only — runtime structural predictions go through `DefaultLiveAdapter.adapt(liveBoundary:)` per BUG-015). (D-034)
    SessionPlanner+Segments → V.7.6.2 multi-segment walk extracted from SessionPlanner.swift for file-length compliance. `makeSections(...)` partitions the track uniformly by `profile.estimatedSectionCount`; `planSegments(...)` loops over sections emitting one or more `PlannedPresetSegment` bounded by `min(remainingInSection, preset.maxDuration(forSection:))`. `recentHistory` 50-entry trim per D-080 rule 6.
    PlannedSession          → Output types: PlannedSession, PlannedTrack (V.7.6.2 multi-segment with backward-compat single-segment init), PlannedPresetSegment (preset / score / breakdown / start / end / incomingTransition / terminationReason), PlannedTransition, PlanningWarning (Codable with custom CodingKeys for the partialPreparation(unplannedCount:) associated-value case), SegmentTerminationReason (.trackEnded / .sectionBoundary / .maxDurationReached / .completionSignal). PlannedSession.track(at:) / .segment(at:) / .transition(at:) playback-time O(N) lookups. `canonicalIdentity(matchingTitle:artist:)` pure-function helper resolves streaming-metadata observations (title+artist) to the planned full TrackIdentity (cache-key surface for BUG-006.2 / D-091). `appendingWarnings(_:)` for partial-plan extend per Increment 6.1. (D-034 + V.7.6.2 + D-091)
    LiveAdapter             → DefaultLiveAdapter (final class @unchecked Sendable since D-080): runtime plan-adaptation. Boundary-reschedule (`liveBoundary.confidence ≥ 0.5` AND `|live − planned| > 5 s`) → mood-override (`|Δvalence| > 0.4` or `|Δarousal| > 0.4` AND `elapsedFraction < 0.4` AND alternative preset scores `> 0.15` higher AND 30 s per-track cooldown lapsed). NSLock-guarded `lastOverrideTimePerTrack: [TrackIdentity: TimeInterval]`. LiveAdapting protocol. LiveAdaptation + AdaptationEvent (4-case kind enum) + PresetOverride value types. **Runtime invocation gap — BUG-015.** (D-035 + D-080 rules 3 + amendment to D-035)
    LiveAdapter+Patching    → PlannedSession.applying(_:at:) (V.7.6.2-aware: patches segments[0]) + extendingCurrentPreset(by:at:) (U.6b moreLikeThis +30 s extend with subsequent-track time-shift) + applying(overrides:) (U.6b reshuffleUpcoming locked-pick preservation). The only sanctioned controlled-mutation paths for PlannedSession outside `DefaultSessionPlanner.plan(...)`. (D-035)
    LiveAdapter+MoodOverride → `applyOverrideIfBetter(...)` extracted from LiveAdapter.swift for file-length compliance. Includes D-074 diagnostic-filter (`ranked.first(where: { !$0.0.isDiagnostic })`). (D-035 + D-074)
    ReactiveOrchestrator    → DefaultReactiveOrchestrator (stateless struct per D-036): ad-hoc preset selection. ReactiveAccumulationState (.listening 0-15 s / .ramping 15-30 s / .full 30 s+). Switch conditions: score gap > 0.20 OR (boundary confidence ≥ 0.5 AND score gap > minBoundaryScoreGap 0.05 per D-080 rule 4). `liveStemFeatures: StemFeatures?` parameter populated once the live stem analyzer converges (~10 s) so QR.2 / D-080 stem-affinity scoring is reachable in reactive mode. ReactiveOrchestrating protocol. ReactiveDecision return type. **Runtime invocation gap — BUG-015.** (D-036 + D-080)
    PresetSignaling         → `PresetSignaling: AnyObject` protocol with `presetCompletionEvent: PassthroughSubject<Void, Never>` requirement. `PresetSignalingDefaults.minSegmentDuration = 5.0` floor enforced at `VisualizerEngine+Presets.handlePresetCompletion`. Only ArachneState conforms today. (V.7.6.2)
    ArachneStateSignaling   → `extension ArachneState: PresetSignaling` lives here (not Presets/Arachnid/) per D-095 — Presets→Orchestrator would create a circular module dependency. The completion event fires from `ArachneState.advanceStablePhase` when `BuildState.stage` transitions to `.stable`. (D-095)
    PlaybackActionRouter    → Protocol (D-050) declaring seven @MainActor live-adaptation keyboard actions (moreLikeThis / lessLikeThis / reshuffleUpcoming / presetNudge(_:immediate:) / rePlanSession / undoLastAdaptation / toggleMoodLock) plus the isMoodLocked observable. Concrete `DefaultPlaybackActionRouter` lives in PhospheneApp/Services/ per D-050 (App-layer concrete; engine-layer protocol). U.6b semantics fully wired through PlaybackShortcutRegistry.
    QualityCeiling          → `.auto / .performance / .balanced / .ultra` enum (U.8, D-053). `complexityThresholdMs(for: tier)` returns nil for .ultra, 12 ms for .performance, `tier.frameBudgetMs` for .auto/.balanced. Consumed by DefaultPresetScorer (exclusion gate) and by MLDispatchScheduler (Renderer, dispatch immediate on .ultra per D-059d).
  Session/
    Session.swift           → Module marker; `@_exported import Shared` so `import Session` consumers automatically get the Shared types.
    SessionManager          → Lifecycle state machine (idle→connecting→preparing→ready→playing→ended), @MainActor ObservableObject; degrades gracefully on connector/preparation failure (D-018). startSession(preFetchedTracks:source:) variant skips the connect phase for sources (e.g. Spotify OAuth) that already fetched tracks in the app layer (D-070 Bug 2).
    SessionManager+Readiness → Pure `computeReadiness(statuses:trackList:cache:) -> ProgressiveReadinessLevel` static; D-056 `.partial` threshold rule (BPM + ≥1 genre tag); extracted from `SessionManager` to stay under SwiftLint's 400-line gate after BUG-006.1 `WIRING:` instrumentation landed.
    PlaylistConnector       → Apple Music (AppleScript) / Spotify (Web API via SpotifyWebAPIConnector) / URL parsing. PlaylistSource enum (4 cases) + PlaylistConnectorError enum (9 cases).
    LocalFolderConnector    → v2 stub gated behind `#if ENABLE_LOCAL_FOLDER_CONNECTOR` — flag never set in any xcconfig or Package.swift; class never compiles in production builds. Intentional scaffold per D-046 / UX_SPEC §4.4.
    TrackIdentity           → Stable cache key: title, artist, album, duration, catalog IDs. spotifyPreviewURL: URL? is a resolution hint (excluded from Equatable/Hashable/Codable) populated by SpotifyWebAPIConnector from the /items preview_url field; PreviewResolver short-circuits to it.
    SessionTypes            → SessionState enum, ProgressiveReadinessLevel enum (D-056), defaultProgressiveReadinessThreshold (= 3), SessionPlan stub (expanded by Orchestrator in Phase 4), PreviewAudio value type.
    TrackPreparationStatus  → AnalysisStage enum (stemSeparation / mir / beatGrid / caching) + 7-status TrackPreparationStatus state machine (queued / resolving / downloading / analyzing / ready / partial / failed). NOTE: `.mir` and `.beatGrid` sub-stages are not emitted as separate transitions (both run inside Task.detached alongside stem separation); PreparationProgressView shows `.stemSeparation` for the entire analysis duration.
    PreparationProgressPublishing → @MainActor protocol exposing per-track preparation status to the UI without leaking SessionPreparer internals; SessionPreparer is the production conformer.
    PreviewResolver          → Resolves 30-second preview URLs. Primary: TrackIdentity.spotifyPreviewURL (inline from Spotify /items, no network call, D-070). Fallback: iTunes Search API (free, 20/60s rate limit, D-011) for non-Spotify tracks or tracks where Spotify returns null. In-memory cache (URL?? semantics).
    PreviewDownloader        → Batch download + format-sniff + AVAudioFile decode to mono Float32, withTaskGroup concurrency ceiling (default 4).
    SessionPreparer          → Download → separate → analyze → cache per track, @MainActor ObservableObject with @Published progress + trackStatuses. Sequential per-track loop (StemSeparator never called concurrently). Stored Task so cancelPreparation() interrupts at stage boundaries.
    SessionPreparer+Analysis → `nonisolated static func analyzePreview(...)` composing the seven-stage pipeline inside `Task.detached`: stem separation → analyzer warmup → MIR → full-mix BeatGrid → metadata-driven beatsPerBar override → drums-stem BeatGrid (DSP.4) → GridOnsetCalibrator (BUG-007.8) → CachedTrackData. The load-bearing Session-side composition seam for DSP + ML + Audio.
    SessionPreparer+WiringLogs → BUG-006.1 `WIRING:` diagnostic emission (per-track beatGrid summary + drumsBeatGrid summary + DONE line) and DSP.4 / BUG-008.2 BPM-mismatch warnings (3-way preferred; 2-way fallback for backward grep-ability). Diagnostic-only; tracked for QR.5 cleanup.
    BeatGridAnalyzer        → `BeatGridAnalyzing` protocol + `DefaultBeatGridAnalyzer` composing DSP's BeatThisPreprocessor + ML's BeatThisModel + DSP's BeatGridResolver. Frame rate fixed at 50.0 fps (22050/441). Graceful `.empty` return on failure. CA.3 verdict: stays in Session/ (testability-seam pattern co-located with consumer).
    GridOnsetCalibrator     → BUG-007.8 per-track median grid-vs-onset offset calibrator. Replays preview audio through offline BeatDetector, matches sub_bass onsets (result.onsets[0], D-075) to BeatGrid beats within ±200 ms, returns median (gridBeat − onsetTime) ms. Stored on CachedTrackData.gridOnsetOffsetMs; applied at playback as drift EMA initial bias. CA.3 follow-up CA.3-FU-1: relocate to Sources/DSP/ (functionally a DSP capability — both consumers already import DSP).
    BPMMismatchCheck        → Pure-function detectors: `detectBPMMismatch` 2-way (BUG-008.2, MIR vs full-mix grid) + `detectThreeWayBPMDisagreement` 3-way (DSP.4, MIR vs full-mix vs drums-stem). Default 3% threshold. No I/O; caller composes log lines.
    StemCache                → Thread-safe per-track: stem waveforms + StemFeatures + TrackProfile + BeatGrid + drumsBeatGrid + gridOnsetOffsetMs, NSLock-guarded. The most-consumed Session type.
    PersistentStemCache      → LF.3 disk-backed content-keyed stem cache (D-130) at `~/Library/Application Support/Phosphene/StemCache/sha256/<aa>/<full-hash>/`. NSLock-guarded. `load(hash:)`/`store(...)`/`contains(hash:)`/`remove(hash:)`. Stems as sibling `.f32` files; non-waveform state as `metadata.json`. Schema v2 (LF.5 / D-132): optional `LocalFileMetadata` (title/artist/album from AVAsset.commonMetadata) + optional sibling `artwork.bin` (raw image bytes — LF.6 consumes via `lfPersistentArtworkData`). LRU eviction (LF.4 / D-131): `totalBytes()` / `evictToMaxBytes(_:)` / `clearAll()`, default 500 MB cap (UserDefaults `phosphene.cache.localFile.maxBytes`). `PersistentStemCacheEntry` wraps `cached` + `decodedDuration` + `metadata` + `artworkData`. Covered by PersistentStemCacheTests + PersistentStemCacheEvictionTests.
    LocalFilePreparing       → LF.4 protocol (`prepareLocalFile(url:) async -> LocalFilePrepResult?`) that SessionManager.startLocalFiles delegates to; the heavy ML deps live on VisualizerEngine (app layer) so Session needn't import them. `LocalFilePrepResult` carries `identity` (synthetic `local:sha256:<hash>`) + `cached` + `decodedDuration` + `source` (.persistentDisk / .freshAnalysis) + `artworkData: Data?` (LF.6).
    M3UParser                → LF.5 playlist parser. Tolerant of BOM, CRLF, `#`-comment lines, absolute / `file://` / relative paths. Covered by M3UParserTests.
    PreviewAudio+Metadata    → LF.5 AVAsset extraction extension on the PreviewAudio value type. `extractMetadata(at:) -> LocalFileMetadata` (title/artist/album from commonMetadata) + `extractArtwork(at:) -> Data?` (JPEG for mp4/m4a covr atom, JPEG/PNG for mp3 ID3 APIC / flac picture block). `sha256(of:)` content hashing + `fromLocalFile(at:contentHash:)` direct off-disk PCM decode.
    TrackProfile             → BPM, key, mood, spectral centroid avg, genre tags, stem energy balance, estimated section count.
                               NOTE: no `fullDuration` field — full track duration comes from TrackIdentity.duration (Double?, nil = unknown). SessionPlanner defaults to 180 s when nil.
    Connectors/
      SpotifyTokenProvider     → SpotifyTokenProviding protocol + internal MissingCredentialsTokenProvider fallback (always throws .spotifyAuthFailure; the makeLive() default used when no authenticated provider is injected). CLEAN.2.1 removed the client-credentials DefaultSpotifyTokenProvider actor and its bundled SpotifyClientSecret. The App-layer SpotifyOAuthTokenProvider (PhospheneApp/Services/, OAuth Authorization Code + PKCE, no secret, D-069 Decision 2) conforms to the same protocol and is the sole production Spotify token source.
      SpotifyWebAPIConnector   → D-070 SpotifyWebAPIConnecting protocol + concrete connector. /v1/playlists/{id}/items endpoint (deprecated /tracks). Per-item read tries item["item"] first then item["track"] fallback (Failed Approach #45). No `fields` parameter (Failed Approach #46 — silent {} return). `market=from_token` for region-restricted handling. Captures preview_url inline → TrackIdentity.spotifyPreviewURL (Failed Approach #47). 401 → invalidate + retry once. 403 → .spotifyLoginRequired (SpotifyOAuthPlaylistConnector remaps to .spotifyPlaylistInaccessible when authenticated per D-069 Decision 6). 429 → .rateLimited(retryAfter). Pagination via API-provided `next` URL.
  Diagnostics/
    MemoryReporter          → `phys_footprint` via TASK_VM_INFO Mach API → MemorySnapshot{residentBytes, virtualBytes, purgeableBytes, timestamp}. Matches Activity Monitor. D-060(a).
    FrameTimingReporter     → 100-bucket 0.5ms histogram (cumulative) + 1000-frame rolling ring buffer. O(1) record, O(buckets) percentile. `droppedFrameThresholdMs = 32.0 ms`. @unchecked Sendable, NSLock-guarded. D-060(b).
    SoakTestHarness         → @MainActor, @available(macOS 14.2, *). Headless soak orchestrator: drives AudioInputRouter (localFile mode), samples memory + frame timing every sampleInterval, observes signal/quality transitions, writes JSON+Markdown report. cancel() via 0.25s polling slice. D-060.
    SoakTestHarness+AudioGen → generateSyntheticAudioFile() — no-fixture procedural audio (10s sine sweep + noise + 120 BPM kicks). Extracted from SoakTestHarness.swift for file-length compliance.
    SoakTestHarness+Reporting → JSON + Markdown report builder. PerSampleSnapshot type + summary statistics (memory growth, frame timing percentiles, signal/quality transition logs). Extracted from SoakTestHarness.swift for file-length compliance.
  SoakRunner/               → CLI executable (swift-argument-parser). --duration, --sample-interval, --audio-file, --report-dir. Prints JSON report summary. Use Scripts/run_soak_test.sh for 2-hour runs with caffeinate -i. D-060(d).
  TempoDumpRunner/          → CLI executable (swift-argument-parser). --audio-file, --label, --out, --metadata-bpm. Decodes audio to mono Float32, runs FFTProcessor + BeatDetector at 1024-sample hops, dumps top-5 IOI bins + autocorrelation BPM + per-band onset events to a plain-text file. Sets BEATDETECTOR_DUMP_HIST=1 + BEATDETECTOR_DUMP_FILE before any BeatDetector access. Use with Scripts/dump_tempo_baselines.sh (3-track driver) and Scripts/analyze_tempo_baselines.py (per-band IOI + grid-fit analyzer). Permanent regression infrastructure for DSP.1/DSP.2. D-075.
  Shared/
    Shared.swift            → Module marker (imports only).
    UMABuffer               → Generic .storageModeShared MTLBuffer + UMARingBuffer + UMABufferError.
    AudioFeatures           → Umbrella file for the AudioFeatures+ extensions (comment-only).
    AudioFeatures+Analyzed  → FeatureVector (48 floats / 192 B, GPU buffer(2), D-099 / DM.2), FeedbackParams (8 floats / 32 B), EmotionalQuadrant enum, EmotionalState (valence + arousal + computed quadrant), StructuralPrediction.
    AudioFeatures+Frame     → AudioFrame (PCM block metadata, 24 B), FFTResult (16 B), StemData (4× AudioFrame).
    AudioFeatures+Metadata  → MetadataSource enum (5 cases), TrackMetadata, PreFetchedTrackProfile. Authoritative location per CA.3 / CA-Audio / CA-Shared boundary closure.
    AudioFeatures+SceneUniforms → SceneUniforms GPU struct (8× SIMD4<Float> = 128 B, bound at buffer(4)).
    StemFeatures            → @frozen 64-float / 256-byte stem-features struct per D-099 / DM.2. Per-stem energy + band + beat (16) + MV-1 deviation primitives (8) + MV-3a rich metadata (16) + MV-3c vocals pitch (2) + V.9 / D-127 drumsEnergyDevSmoothed (1) + padding (21). Bound at GPU buffer(3).
    AnalyzedFrame           → Timestamped container: AudioFrame + FFTResult + StemData + FeatureVector + EmotionalState + StructuralPrediction.
    BeatSyncSnapshot        → Per-frame beat-sync diagnostic snapshot (9 fields: barPhase01, beatsPerBar, beatInBar, isDownbeat, sessionMode, lockState, gridBPM, playbackTimeS, driftMs). CLAUDE.md §Defect Handling load-bearing artifact for the `dsp.beat` domain. NSLock-guarded on VisualizerEngine.
    StemSampleBuffer        → Interleaved stereo PCM ring buffer for stem separation input (15s).
    RenderPass              → Enum: direct, feedback, particles, mesh_shader, post_process, ray_march, icb, ssgi, mv_warp, staged.
    Logging                 → Per-module os.Logger instances (subsystem: "com.phosphene"); categories audio / dsp / renderer / orchestrator / ml / metadata / session / bug012.
    SessionRecorder         → Continuous diagnostic capture per app launch: video.mp4 (H.264, 30 fps) + features.csv + stems.csv + stems/<N>_<title>/{drums,bass,vocals,other}.wav + session.log + raw_tap.wav. Writes to ~/Documents/phosphene_sessions/<timestamp>/. Writer locks after 30 stable drawable frames; if a different size arrives consistently for ≥90 frames after lock (bad initial lock from transient Retina→logical-point resize), tears down and relocks — logs "video writer relocking". Finalised on NSApplication.willTerminateNotification. Validated by SessionRecorderTests.
    SessionRecorder+CSV     → CSV row formatters for features.csv + stems.csv. Append-only column invariant.
    SessionRecorder+RawTap  → Raw Core Audio tap → raw_tap.wav writer; streaming WAV header patched at finish; static writeWav for stem dumps.
    SessionRecorder+Stems   → Per-separation stem WAV dump under stems/<idx>_<title>/.
    SessionRecorder+Video   → AVAssetWriter video.mp4 capture + drawable-size deferred-lock + relock-after-90-stable-mismatched-frames (Failed Approach #28).
    SpectralHistoryBuffer   → Per-frame MIR history ring buffer. 5 rings × 480 samples (≈8s at 60fps) in a 16 KB UMA MTLBuffer bound at fragment index 5 in direct-pass encoders. Tracks valence, arousal, beat_phase01, bass_dev, bar_phase01 (phrase-level sawtooth; 0 = no BeatGrid). Beat-grid metadata section at [2402..2429]: beat_times[16], bpm, lock_state, session_mode, downbeat_times[8], drift_ms. Updated once per frame in RenderPipeline.draw(in:); reset on track change.
    DeviceTier              → .tier1 (M1/M2) / .tier2 (M3/M4). frameBudgetMs getter. Used by PresetScoringContext for complexity-cost exclusion gate.
    Smoother                → @frozen Sendable value type wrapping `pow(rate30, 30/fps)` for FPS-independent EMA / decay. Used by BeatDetector (pulse decay rate30=0.6813) and BandEnergyProcessor (per-band rates 0.65/0.75/0.95). Centralised in [QR.5] C.1 from previously-inlined `powf` calls.
    UserFacingError         → Canonical 29-case error taxonomy organised per UX_SPEC §9 (Permission ×3 / Connection ×7 / Preparation ×7 / Playback ×12). CaseIterable manually implemented (associated-value cases). Nested SpotifyRejectionKind enum.
    UserFacingError+Presentation → Presentation metadata accessors: presentationMode, severity, retryStatus, primaryCTAKey, secondaryCTAKey, isConditionBound, conditionID. Per-case extension; ErrorPresentationMode / ErrorSeverity / ErrorRetryStatus value types. Consumed by App-layer FullScreenErrorView, ToastManager, PlaybackErrorBridge (CA-Shared-FU-1 wired retryStatus + isConditionBound through LocalizedCopy + bridge per 2026-05-21).
    BUG012Probe             → BUG-012-i1 instrumentation namespace. NSLock-guarded counters (stem-dispatch + FFT forward + FFT inverse in-flight; lifecycle counters for StemFFTEngine + StemSeparator + VisualizerEngine) with alarm-level log on count > 1. Free-form log/notice helpers tagged `[BUG-012]`. Read-only per the standing BUG-012-i1 rule; remove file when BUG-012 closes.
    Dashboard/DashboardTokens → Static design-system tokens for the Telemetry dashboard. TypeScale (caption / label / body / bodyLarge / numeric / hero / display + labelTracking), Spacing (4-pt grid xs..xxl + cardGap), Color (4 surface + 3 text + 6 brand + 3 status — OKLCH-derived sRGB), Weight / TextFont / Alignment enums. Lives in Shared so App-side Views/Dashboard + Renderer/Dashboard builders can both consume without cross-module dependency (D-081 / DASH.1.1). private init prevents instantiation.
Tests/
  Audio/                    → AudioBufferTests, FFTProcessorTests, StreamingMetadataTests, MetadataPreFetcherTests, LookaheadBufferTests, SilenceDetectorTests
  DSP/                      → SpectralAnalyzerTests, BandEnergyProcessorTests, ChromaExtractorTests, BeatDetectorTests, MIRPipelineUnitTests, SelfSimilarityMatrixTests, NoveltyDetectorTests, StructuralAnalyzerTests, BeatPredictorTests, PitchTrackerTests, StemAnalyzerMV3Tests
  ML/                       → StemSeparatorTests, StemFFTTests, StemModelTests, MoodClassifierTests, BeatThisFixturePresenceGate (QR.3 — supply-chain gate for love_rehab.m4a + python-activations.json), BeatThisLayerMatchTests, BeatThisBugRegressionTests, BeatThisStemReshapeTests (QR.3 — DSP.2 S8 Bug 2), BeatThisRoPEPairingTests (QR.3 — DSP.2 S8 Bug 4 spec), MoodClassifierGoldenTests (QR.3 — 10-input output anchor)
  Renderer/                 → MetalContextTests, ShaderLibraryTests, RenderPipelineTests, ProceduralGeometryTests, MeshGeneratorTests, BVHBuilderTests, RayIntersectorTests, PostProcessChainTests, ShaderUtilityTests, TextureManagerTests, RayMarchPipelineTests, SceneUniformsTests, FeatureVectorExtendedTests, SSGITests, RenderPipelineICBTests, MVWarpPipelineTests, SpectralCartographTests
  Utilities/                → NoiseTestHarness (compute-pipeline harness), NoiseUtilityTests (~30 @Test, 10 suites), PBRUtilityTests (~45 @Test, 8 suites) — V.1 utility tests. V.2: SDFPrimitivesTests (2 suites), SDFBooleanTests, SDFModifiersTests, SDFDisplacementTests, RayMarchAdaptiveTests, HexTileTests; HenyeyGreensteinTests, ParticipatingMediaTests, CloudsTests, LightShaftsTests, CausticsTests; VoronoiTests, ReactionDiffusionTests, FlowMapsTests, ProceduralTests, GrungeTests.
  Diagnostics/              → MemoryReporterTests (5), FrameTimingReporterTests (7), SoakTestHarnessTests (7 always-run + 2 SOAK_TESTS=1 gated). Run soak tests: SOAK_TESTS=1 swift test --filter SoakTestHarnessTests
  Shared/                   → AudioFeaturesTests, UMABufferExtendedTests, EmotionalStateTests, AnalyzedFrameTests, SpectralHistoryBufferTests
  Session/                  → SessionManagerTests, SessionManagerCancelTests, SessionManagerLocalFileTests (LF.4 + LF.5 lifecycle + per-track-status observer), PlaylistConnectorTests, PreviewResolverTests, PreviewDownloaderTests, SessionPreparerTests, SessionPreparerProgressTests, ProgressiveReadinessTests, TrackPreparationStatusTests, GridOnsetCalibratorTests (BUG-007.8 contract tests), BPMMismatchCheckTests (BUG-008.2 + DSP.4 detector tests), SpotifyWebAPIConnectorTests, SpotifyTokenProviderTests, SpotifyItemsSchemaTests (QR.3 — fixture-driven Failed Approach #45 / #47 lock), PersistentStemCacheTests + PersistentStemCacheEvictionTests (LF.3/LF.4/LF.5 — incl. schema-v2 metadata + artwork roundtrip), M3UParserTests (LF.5). StemCache is exercised inside SessionPreparerTests + the PreparedBeatGrid*WiringTests integration suite — no separate StemCacheTests file. (Audio/ target also holds LocalFilePlaybackFormatCoverageTests — per-format LF prep + LF.5 multi-file queue.)
  Orchestrator/             → PresetScorerTests, PresetScorerAdaptationTests, PresetScoringContextExtensionTests, TransitionPolicyTests, SessionPlannerTests, MultiSegmentSmokeTest, MaxDurationFrameworkTests (BUG-011 round 8 `wait_for_completion_event` regression-lock), PartialPlanTests (Increment 6.1), GoldenSessionTests (12 regression tests across 3 curated playlists; regenerated for QR.2 / V.7.6.2 / BUG-004), LiveAdapterTests (incl. D-080 cooldown), ReactiveOrchestratorTests, StemAffinityScoringTests (D-080 / Failed Approach #53+#54 regression-lock), OrchestratorCertifiedFilterTests (D-053 uncertified-gate), OrchestratorDiagnosticExclusionTests (D-074 diagnostic gate across Scorer/LiveAdapter/Reactive/Planner), DiagnosticHoldTests (L-key suppression simulation), PresetSignalingTests (V.7.6.2 protocol shape + minSegmentDuration floor)
  Presets/                  → ArachneStateTests, GossamerStateTests, ArachneSpiderRenderTests, MurmurationStemRoutingTests, LumenPatternEngineTests, LumenPaletteSpectrumTests (LM.4.6 — pure uniform random RGB per cell, 7 tests / 5 suites mirror the shader algorithm in Swift), PresetLoaderCompileFailureTest (QR.3 — production-count gate, 15 presets; verified by breaking Plasma.metal AND caught the LM.4.6 underscore-literal silent drop, hotfix `888bb856`). LumenPatternsTests was deleted at LM.4.4 along with the pattern engine.
  Integration/              → AudioToFFTPipelineTests, AudioToRenderPipelineTests, MetadataToOrchestratorTests, AudioToStemPipelineTests, MIRPipelineIntegrationTests, LookaheadIntegrationTests, StemsToRenderPipelineTests, SessionPreparationIntegrationTests, BeatGridIntegrationTests, PreparedBeatGridAppLayerWiringTests, PreparedBeatGridWiringTests, LiveDriftValidationTests (QR.3 — closed-loop musical-sync test on love_rehab.m4a)
  Regression/               → FFTRegressionTests, MetadataParsingRegressionTests, ChromaRegressionTests, BeatDetectorRegressionTests, StructuralAnalysisRegressionTests + golden fixtures
  Performance/              → FFTPerformanceTests, RenderLoopPerformanceTests, StemSeparationPerformanceTests, DSPPerformanceTests
  TestDoubles/              → MockAudioCapture, StubFFTProcessor, FakeStemSeparator, MockMoodClassifier, FakePreparationProgressPublisher, AudioFixtures, MockMetadataProvider, MockMetadataFetcher (Mock/Stub/Fake taxonomy standardised [QR.5] C.2)

PhospheneAppTests/            → App-layer test targets
  OrchestratorWiringRegressionTests (BUG-015 — source-presence regression: VisualizerEngine+Audio.swift must contain `applyLiveUpdate(` or `runOrchestratorLiveUpdate(`; App layer must have ≥1 call site outside the declaration), SettingsStoreEnvironmentRegressionTests (D-091 / Failed Approach #55 — three assertions: @EnvironmentObject consumer sees changes; @StateObject SettingsStore() shadow does NOT see changes; PlaybackView.swift source must NEVER contain the dead pattern), PlaybackChromeIndexBindingTests (D-091 / QR.4 — title-case mismatch must not change index), DefaultPlaybackActionRouterTests (D-050 / U.6b contract), NetworkRecoveryCoordinatorTests (D-061(d,e) recovery cap + debounce), SpotifyConnectionViewModelTests + SpotifyKeychainStoreTests + SpotifyOAuthTokenProviderTests (U.11 cluster; URLProtocol-stub-using suites use @Suite(.serialized) per U.10), AppleMusicConnectionViewModelTests (U.3 connector state machine), LiveAdaptationToastBridgeTests (U.6 Part C), PlaybackErrorBridgeTests + PlaybackErrorConditionTrackerTests (UX_SPEC §9.4 silence routing), PresetScoringContextProviderTests (App ↔ Orchestrator scoring bridge), SessionRecorderRetentionPolicyTests (pruning invariants), SettingsMigratorTests (legacy UserDefaults migration), HandleLocalFileReadyIdempotencyRegressionTests (LF.5.fix.3-C — BUG-023 Bug C source-presence regression), LocalFileRecentsStoreTests (LF.5 — ordering / dedup / cap / stale-path), AlbumArtworkCacheTests (LF.6 — decode + downsize + LRU + nil-on-malformed), PlaybackChromeArtworkBindingTests (LF.6 + LF.6.fix.1 BUG-024 — CombineLatest title+artwork binding; LF→streaming artwork-clear regression), plus per-VM tests (PlaybackChromeViewModelTests, ToastManagerTests, ReadyViewTimeoutIntegrationTests, etc. — VM-side inventory deferred to CA.6).
```


---

## Audio Analysis Tuning

These constants were validated across genres. Do not re-tune from scratch.

### Frequency Bands

**3-band:** Bass 20–250 Hz, Mid 250–4000 Hz, Treble 4000–20000 Hz.

**6-band:** Sub Bass 20–80 Hz, Low Bass 80–250 Hz, Low Mid 250–1000 Hz, Mid High 1000–4000 Hz, High Mid 4000–8000 Hz, High 8000+ Hz.

### AGC (Automatic Gain Control)

Milkdrop-style average-tracking. Output = `raw / runningAverage * 0.5`. Two-speed warmup: fast (0.95 rate, ~1s) then moderate (0.992, ~2s settling). 6-band AGC normalizes against total energy (not per-band) to preserve relative differences.

**Authoring implication (D-026):** AGC-normalized outputs like `f.bass` are **centered around 0.5**, not raw amplitudes. The kick that reads `0.35` in a sparse section and `0.22` in a busy one is equally loud acoustically — only the running-average divisor moved. Preset shaders must drive visuals from **deviation primitives** added in MV-1:

- **xRel** = `(x - 0.5) * 2.0` — centered at 0, typical range ±0.5. Use for continuous motion drivers: `zoom = base + 0.1 * f.bass_att_rel`.
- **xDev** = `max(0, xRel)` — positive-only, zero at or below AGC average. Use for accent/threshold drivers: `smoothstep(0.0, 0.3, f.bass_dev)`.

Available fields: `f.bass_rel/dev`, `f.mid_rel/dev`, `f.treb_rel/dev`, `f.bass_att_rel`, `f.mid_att_rel`, `f.treb_att_rel` (FeatureVector); `stems.vocals_energy_rel/dev`, `stems.drums_energy_rel/dev`, `stems.bass_energy_rel/dev`, `stems.other_energy_rel/dev` (StemFeatures). Patterns like `smoothstep(0.22, 0.32, f.bass)` are an anti-pattern: they fail on track changes and on section changes within a single track. See `docs/MILKDROP_ARCHITECTURE.md` for the research establishing this and `docs/DECISIONS.md` D-026 for the rule.

### Smoothing

FPS-independent via `pow(rate, 30/fps)`:
- **Instant** (`bass`, `mid`, `treble`): bass 0.65, mid/treble 0.75.
- **Attenuated** (`bass_att`, `mid_att`, `treb_att`): 0.95 rate for slow motion.

### Onset Detection

Spectral flux on 6-band IIR RMS: `max(0, currentRMS - previousRMS)`. 50-frame circular buffer. Threshold: `median(buffer) × 1.5`. Per-band cooldowns: low 400ms, mid 200ms, high 150ms. Grouped pulses: `beat_bass` (sub_bass OR low_bass, 400ms), `beat_mid` (low_mid OR mid_high, 200ms), `beat_treble` (high_mid OR high, 150ms). Decay: `pow(0.6813, 30/fps)` → 0.1 in ~200ms at 60fps.

### Validated Onset Counts (Reference — per 5-second window)

| Track | Genre | sub_bass | low_bass | low_mid | mid_high | high_mid | high |
|-------|-------|----------|----------|---------|----------|----------|------|
| Love Rehab (Chaim) | Electronic ~125 BPM | 11 | 10 | 20 | 4 | 0 | 1 |
| So What (Miles Davis) | Jazz ~136 BPM | 5 | 2 | 5 | 6 | 2 | 1 |
| There There (Radiohead) | Rock, syncopated | 6 | 7 | 21 | 18 | 16 | 5 |

### Tempo (BPM estimation)

Two parallel paths feed `BeatDetector.Result`:

**IOI-based (primary, post-DSP.1).** `recordOnsetTimestamps` records timestamps from `result.onsets[0]` — sub_bass per-band onset events from `detectOnsets`, which has a 400 ms cooldown. **Single-band only — never fuse with low_bass:** independent per-band cooldowns + FFT-hop quantization make OR-of-bands produce alternating 18/19-frame IOIs (418/441 ms) for a true 441 ms beat, which then bias the histogram. `computeStableTempo` runs at 1 Hz over the trailing 10 s window and computes BPM via **trimmed-mean IOI** — median IOI, drop outliers outside [0.5×, 2×] median, mean of inliers, BPM = `60 / meanIOI`. The 80–160 octave clamp is preserved for deep doubling/halving guard. The histogram is still built (cheap) but only consumed by the diagnostic dump; never by the BPM picker. Picking the histogram mode systematically biased toward faster BPMs because BPM bucket widths grow with BPM in period space. See D-075.

**Autocorrelation (secondary, fallback).** `estimateTempo` runs every frame on the composite-flux onset history. Returns `(tempo, confidence)` for tracks where sub_bass IOI evidence is sparse or absent (a cappella, solo acoustic guitar). Same 80–160 clamp. Used by the live engine when `instantBPM`/`stableBPM` haven't converged; the post-DSP.2 path will instead drive `FeatureVector.beatPhase01` analytically from the pre-cached `BeatGrid` (Beat This! offline) plus a live drift tracker.

**Reference-track results (post-DSP.1):** love_rehab 122–126 (true 125), so_what 135–138 (true 136), there_there 137–140 (true ~86 syncopated — kick is not on every beat; histogram correctly reads kick rate, not meter). DSP.2 (Beat This! transformer via MPSGraph offline + drift-tracker live, planned, D-077; pivoted from the BeatNet path D-076 reserved-but-abandoned) is the answer for the syncopated case and for irregular meters (Pyramid Song 16/8, Money 7/4) the IOI method cannot reach by construction. See `docs/diagnostics/DSP.1-baseline*.txt` for the diagnostic captures and `Scripts/dump_tempo_baselines.sh` to reproduce.

### Chroma

Bin-count normalized: weight = `1/binsInPitchClass`. Skip bins below **500 Hz** — at 48 kHz / 1024-point FFT, the 46.875 Hz bin spacing puts bins 2 / 5 / 10 all in the F♯ pitch class, biasing key estimation systematically. Higher harmonics carry accurate pitch information. Above the floor, pitch classes get 31–55 bins — without bin-count normalization, key estimation is biased toward classes that own more bins. Code: `ChromaExtractor.minFrequency = 500.0` (the file-level docstring at `ChromaExtractor.swift:16` says "65 Hz" but the constant is 500 Hz — the constant is authoritative; the comment is stale and is queued for a code-pass cleanup in a future increment, CA.1 audit finding).

### Mood Classifier Inputs

10 features, in this order at the call site (`VisualizerEngine+Audio.accumulateMoodFeatures`):

| Index | Value | Source |
|---|---|---|
| 0–5 | 6-band energy (subBass, lowBass, lowMid, midHigh, highMid, high) | `FeatureVector.subBass/…/high` |
| 6 | `spectralCentroid` normalized 0–1 by Nyquist (24000 Hz) | `MIRPipeline.rawSmoothedCentroid / 24000` |
| 7 | `spectralFlux` raw smoothed value (un-AGC-normalized) | `MIRPipeline.rawSmoothedFlux` |
| 8 | `majorKeyCorrelation` (best Pearson r vs K-S major profiles, 0–1) | `MIRPipeline.latestMajorKeyCorrelation` |
| 9 | `minorKeyCorrelation` (best Pearson r vs K-S minor profiles, 0–1) | `MIRPipeline.latestMinorKeyCorrelation` |

NOT raw 12-bin chroma (a tiny MLP cannot learn the Krumhansl-Schmuckler function from raw bins). The classifier-input docstring at `MoodClassifier.swift:14-19` is authoritative for the input contract.

**Important: index 7 is the RAW smoothed flux, not the AGC-normalized value.** `MIRPipeline.normalizedFlux` (running-max AGC, 0.999 decay) is what flows into `FeatureVector.spectralFlux` for GPU consumption, but the mood classifier was trained against `rawSmoothedFlux` and the runtime path matches that. Prior versions of this doc claimed AGC-normalized; the claim was stale (CA.2 audit finding 2026-05-20). Z-score normalization is applied per-element inside `MoodClassifier.classify` via the hardcoded `scalerMeans` / `scalerStds` from `tools/data/mood_scaler.json`; the mood classifier is the one that normalizes, not the upstream pipeline.

### LF playback vs process-tap path — empirical deltas (LF.1.5)

The `.localFilePlayback(URL)` mode (D-128) and the process-tap mode produce analysis output that is *equivalent on the load-bearing musical metrics* but *characterizably different on frequency-domain / level-sensitive metrics*. Single-fixture characterization on `love_rehab.m4a` at 2026-05-27 — see [`docs/diagnostics/LF1.5_AB_COMPARISON_2026-05-27.md`](diagnostics/LF1.5_AB_COMPARISON_2026-05-27.md). Implications for preset authors and downstream consumers:

- **BPM and beat-grid timing — equivalent.** Both paths converge to the same BPM within 1 BPM. Beat onset rates agree within 9 %. Any preset whose audio coupling consumes `grid_bpm` / `beatPhase01` / `beatsUntilNext` / sub-bass onset density behaves identically across paths.
- **`spectralCentroid` shifts with capture sample rate.** The LF path opens the file at its native rate (44.1 kHz for AAC files; varies for other formats); the process-tap path runs at the system default output rate (commonly 48 kHz). FFT bin width scales with rate (`44100 / 1024 = 43.07 Hz/bin` vs `48000 / 1024 = 46.88 Hz/bin`), so the same audio content lands at different normalized bin positions. Measured -22.5 % shift on love_rehab (LF 0.087 vs tap 0.068, both divided by the constant `24000 Hz` Nyquist proxy in `MIRPipeline.rawSmoothedCentroid / 24000`). The shift is path-stable: re-running the same fixture on the same path produces the same number.
- **`valence` and `arousal` shift with sample rate too** — `MoodClassifier` consumes `spectralCentroid` as input index 6, so a centroid shift propagates into mood outputs (measured +34 % / -38 % on love_rehab). Cross-path *absolute* mood comparison is NOT meaningful; cross-path *relative* mood movement within a session IS.
- **AGC compresses but does not fully eliminate the volume delta.** The LF path taps pre-mixer at the file's native amplitude (peak ~0 dBFS on a mastered track). The process-tap path captures post-mixer, post-output-volume (peak ~-8 dBFS on this host with default volume + Spotify-normalization-off RUNBOOK settings). AGC normalization reduces but does not erase the level difference: load-bearing bands skew 17-24 % lower on the tap path in proportion to the input level ratio (subBass -17 %, bass -24 %, treble -23 %). Mid-band sits at the noise floor on bass-heavy tracks; relative deltas there are numerical noise, not signal divergence.
- **Authoring rule.** Drive primary motion from continuous deviation primitives (`f.bassDev`, `f.subBassDev` once exposed, etc.) and beat-grid fields rather than absolute thresholds on `f.bass` / `f.mid` (which already fail across track changes per D-026 / Failed Approach #31). The same rule that makes presets robust across tracks also makes them robust across LF-vs-tap source paths.

---


---

## Key Types (Shared Module)

Per-type contract reference for the Shared module's GPU-contract value types + cross-module currency types. For types that live in OTHER modules (Renderer / Audio / Session / Presets / Orchestrator) but are referenced widely enough to deserve a sketch, see the "Cross-module reference types" block at the end of this section.

```swift
// === Shared/ — Swift-side GPU contract & cross-cutting value types ===

struct FeatureVector          // 48 floats = 192 bytes (SIMD-aligned), @frozen. GPU buffer(2). D-099 / DM.2.
                              // Floats  1– 3: bass, mid, treble (instant energy)
                              // Floats  4– 6: bassAtt, midAtt, trebleAtt (smoothed)
                              // Floats  7–12: subBass, lowBass, lowMid, midHigh, highMid, high (6-band)
                              // Floats 13–16: beatBass, beatMid, beatTreble, beatComposite (onset pulses)
                              // Floats 17–18: spectralCentroid, spectralFlux
                              // Floats 19–20: valence, arousal (mood, written via setMood per D-024)
                              // Floats 21–22: time, deltaTime
                              // Float  23   : _pad0
                              // Float  24   : aspectRatio
                              // Float  25   : accumulatedAudioTime (energy-weighted; reset on track change)
                              // Floats 26–31: MV-1 deviation primitives (D-026): bassRel/Dev, midRel/Dev, trebRel/Dev
                              // Floats 32–34: smoothed deviation: bassAttRel, midAttRel, trebAttRel
                              // Floats 35–36: MV-3b beat phase (D-028): beatPhase01, beatsUntilNext
                              // Floats 37–38: barPhase01, beatsPerBar (0 / 4 in reactive mode)
                              // Floats 39–48: padding (_pad3..._pad12)
                              // Structural prediction fields live in StructuralPrediction, NOT here.
                              // Camera/light uniforms live in SceneUniforms, NOT here.
struct FeedbackParams         // 32 bytes (8 floats), @frozen: decay, baseZoom, baseRot, beatZoom, beatRot,
                              //   beatSensitivity, beatValue, padding.
struct StemFeatures           // 256 bytes (64 floats), @frozen. GPU buffer(3). D-099 / DM.2 / D-127.
                              //   Floats  1–16: 4 per stem (vocals/drums/bass/other): energy, band0, band1, beat.
                              //   Floats 17–24: MV-1 deviation primitives: vocalsEnergyRel/Dev,
                              //     drumsEnergyRel/Dev, bassEnergyRel/Dev, otherEnergyRel/Dev.
                              //   Floats 25–40: MV-3a rich metadata (4 per stem): onsetRate, centroid, attackRatio, energySlope.
                              //   Floats 41–42: MV-3c vocalsPitchHz, vocalsPitchConfidence.
                              //   Float  43   : D-127 drumsEnergyDevSmoothed (150 ms τ EMA, aurora curtain).
                              //   Floats 44–64: padding.
struct AudioFrame             // 24 bytes, @frozen. PCM block metadata: timestamp/sampleRate/sampleCount/channelCount/bufferOffset.
struct FFTResult              // 16 bytes, @frozen. binCount/binResolution/dominantFrequency/dominantMagnitude.
struct StemData               // 4× AudioFrame = 96 bytes. Bundle of per-stem PCM block metadata.
struct EmotionalState         // valence (-1…1) + arousal (-1…1). `var quadrant: EmotionalQuadrant` is a COMPUTED PROPERTY,
                              // not a stored field. `.neutral` static; `.happy/.sad/.tense/.calm` cases on EmotionalQuadrant.
enum EmotionalQuadrant        // String-Codable: .happy / .sad / .tense / .calm (Russell circumplex).
struct StructuralPrediction   // sectionIndex, sectionStartTime, predictedNextBoundary, confidence. `.none` static.
struct AnalyzedFrame          // Timestamped bundle: timestamp + audioFrame + fftResult + stemData + featureVector + emotionalState + structuralPrediction.
struct TrackMetadata          // title?/artist?/album?/genre?/duration?/artworkURL?/source. `isFetchable` accessor.
                              // LF.6 (D-133) note: `artworkURL` is nil-for-LF and currently nil-for-streaming too.
                              // LF artwork flows through `VisualizerEngine.currentTrackArtworkData: Data?` (separate
                              // publisher fed from the LF.5 persistent cache); `LF.6.streaming` will populate the same
                              // Data publisher from network-fetched bytes via a `StreamingArtworkURLResolver` +
                              // `StreamingArtworkFetcher` chain — the URL field remains unwritten.
struct PreFetchedTrackProfile // External BPM, key, energy, valence, danceability, genreTags, duration, timeSignature.
enum MetadataSource           // String-Codable: .appleMusic / .spotify / .musicKit / .nowPlaying / .unknown.
struct SceneUniforms          // 8× SIMD4<Float> = 128 bytes, @frozen. Camera basis, light, audio-time/aspect/near/far + fog.
struct BeatSyncSnapshot       // 9 fields: barPhase01, beatsPerBar, beatInBar, isDownbeat, sessionMode, lockState,
                              // gridBPM, playbackTimeS, driftMs. CLAUDE.md §Defect Handling artifact for `dsp.beat`.
enum RenderPass               // String-raw: direct, feedback, particles, mesh_shader, post_process, ray_march, icb,
                              // ssgi, mv_warp, staged. Raw-value strings load-bearing for JSON sidecar decoding.
class SpectralHistoryBuffer   // 16 KB UMA buffer at buffer(5). 5× 480-sample trails + beat-grid metadata
                              // [2402..2429]: beat_times[16] (Float.infinity = unused), bpm, lock_state,
                              // session_mode, downbeat_times[8], drift_ms — written by analysisQueue via
                              // updateBeatGridData() (separate beatGridLock, non-overlapping with ring-buffer writes).
class StemSampleBuffer        // 15s interleaved stereo PCM ring buffer for stem separator input.
                              // NSLock-guarded; rate-aware snapshotLatest/rms overloads (D-079 / BUG-R003).
enum DeviceTier               // .tier1 (M1/M2), .tier2 (M3/M4). frameBudgetMs = 16.6 ms (both tiers).
struct Smoother               // @frozen Sendable: rate30 + factor(at: fps) — FPS-independent decay primitive.
class UMABuffer<T>            // .storageModeShared MTLBuffer view; init throws UMABufferError.allocationFailed.
class UMARingBuffer<T>        // Fixed-capacity overwrite ring backed by UMABuffer.
enum UserFacingError          // 29-case error taxonomy per UX_SPEC §9. Hashable + CaseIterable. Sendable.
                              // Presentation extension provides presentationMode/severity/retryStatus/CTAKeys/conditionID.

// === Cross-module reference types (defined OUTSIDE Shared/; listed here for navigation) ===
struct PresetDescriptor       // Sources/Presets/. id, family, tags, passes: [RenderPass], scene metadata, stem affinity.
struct TrackIdentity          // Sources/Session/. title, artist, album, duration, catalog IDs.
struct TrackProfile           // Sources/Session/. BPM, key, mood, spectral centroid avg, genre tags, stem energy balance.
struct CachedTrackData        // Sources/Session/. stemWaveforms, stemFeatures, trackProfile, beatGrid, drumsBeatGrid.
struct Particle               // Sources/Renderer/ + Sources/Presets/. 64 bytes: position, velocity, color, life, size, seed, age.
enum SessionState             // Sources/Session/SessionTypes.swift. idle, connecting, preparing, ready, playing, ended.
enum AudioSignalState         // Sources/Audio/Protocols.swift. .active, .suspect, .silent, .recovering.
struct PresetScoringContext   // Sendable session snapshot: deviceTier, frameBudgetMs, recentHistory,
                              // currentPreset, elapsedSessionTime, currentSection. .initial(deviceTier:) factory.
struct PresetHistoryEntry     // One past preset appearance: presetID, family, startTime, endTime. Sendable+Hashable.
struct PresetScoreBreakdown   // Per-(preset,track,context) score breakdown: mood, tempoMotion, stemAffinity,
                              // sectionSuitability, familyRepeatMultiplier, fatigueMultiplier, excluded, total.
protocol PresetScoring        // score(preset:track:context:) → Float; breakdown(…) → PresetScoreBreakdown;
                              // rank(presets:track:context:) default extension. Sendable.
struct DefaultPresetScorer    // Concrete PresetScoring. Pure/stateless/deterministic. Weights in static lets.
enum FatigueRisk              // .low / .medium / .high. Controls fatigue-penalty cooldown (60/120/300s).
enum TransitionAffordance     // .crossfade / .cut / .morph. Transition styles a preset tolerates.
enum SongSection              // .ambient / .buildup / .peak / .bridge / .comedown. Section suitability filter.
struct ComplexityCost         // tier1: Float, tier2: Float (ms at 1080p). Scalar or {tier1,tier2} JSON.
                              // .cost(for: DeviceTier) → Float. Exclusion gate in DefaultPresetScorer.
struct TransitionContext      // Sendable snapshot for TransitionDeciding: currentPreset, elapsedPresetTime,
                              // prediction (StructuralPrediction), energy (0–1), captureTime (Float, seconds
                              // since capture start — shared coordinate with StructuralPrediction timestamps).
struct TransitionDecision     // Fully-inspectable transition directive: trigger (structuralBoundary/
                              // durationExpired), scheduledAt (Float), style (TransitionAffordance),
                              // duration (TimeInterval, 0 for cut), confidence (Float), rationale (String).
protocol TransitionDeciding   // evaluate(context: TransitionContext) → TransitionDecision?. Sendable.
struct DefaultTransitionPolicy // Concrete TransitionDeciding. Constants in static lets. Structural boundary
                              // beats timer fallback; energy scales crossfade duration and style selection.
struct PlannedTransition      // fromPreset, toPreset, style (TransitionAffordance), duration, scheduledAt
                              // (session-relative TimeInterval), reason (String).
struct PlannedTrack           // track (TrackIdentity), trackProfile, preset, presetScore, scoreBreakdown,
                              // plannedStartTime, plannedEndTime, incomingTransition (PlannedTransition?).
struct PlannedSession         // deviceTier, tracks: [PlannedTrack], totalDuration, warnings: [PlanningWarning].
                              // track(at: TimeInterval) → PlannedTrack?; transition(at:tolerance:) → PlannedTransition?.
struct PlanningWarning        // kind (noEligiblePresets/forcedFamilyRepeat/budgetExceeded/missingSectionData),
                              // trackIndex (Int), message (String). Sendable, Hashable, Codable.
protocol SessionPlanning      // plan(tracks:catalog:deviceTier:) → PlannedSession. Sendable.
struct DefaultSessionPlanner  // Concrete SessionPlanning. Greedy forward-walk. planAsync() adds precompile.
                              // Accepts scorer: PresetScoring + transitionPolicy: TransitionDeciding + closure.
enum SessionPlanningError     // emptyPlaylist / emptyCatalog / precompileFailed(presetID:underlying:).
```

---


---

## GPU Contract Details

### Texture Binding Layout
```
texture(0)  = feedback read
texture(1)  = feedback write
texture(2–3)= reserved
texture(4)  = noiseLQ    (256² .r8Unorm tileable Perlin FBM)
texture(5)  = noiseHQ    (1024² .r8Unorm Perlin FBM)
texture(6)  = noiseVolume (64³ .r8Unorm 3D FBM)
texture(7)  = noiseFBM   (1024² .rgba8Unorm R=Perlin G=shifted B=Worley A=curl)
texture(8)  = blueNoise  (256² .r8Unorm IGN dither)
texture(9)  = IBL irradiance cubemap (32² .rgba16Float) — ray-march lighting pass
texture(10) = IBL prefiltered env (128² .rgba16Float, 5 mip levels) — ray-march lighting pass
              | per-preset baked height field (e.g. Ferrofluid Ocean V.9 Session 4.5b 1024² .r16Float UMA) — ray-march G-buffer pass. Different encoders; no overlap.
texture(11) = BRDF LUT (512² .rg16Float) — ray-march lighting pass
texture(12) = DynamicTextOverlay (2048×1024 .rgba8Unorm, .storageModeShared UMA) — direct-pass only.
              Bound by RenderPipeline.drawDirect when a text-overlay preset is active
              (SpectralCartograph mode label). The overlay is CPU-rasterised once per frame
              via Core Text + Core Graphics into the shared MTLTexture before the encoder
              is created; the GPU then reads from UMA memory zero-copy. Created/destroyed
              by setDynamicTextOverlay(_:) on preset switch.
texture(13+) = Staged-composition sampled stage outputs (V.ENGINE.1).
              kStagedSampledTextureFirstSlot = 13. Each staged preset declares a `samples`
              list per stage; earlier stages' outputs are bound at texture(13), texture(14),
              ... in declared order. Used by Arachne V.7.7B+ for the WORLD → COMPOSITE
              architecture (the worldTex sample at texture(13) — D-093).
```

### Buffer Binding Layout
```
buffer(0) = FeatureVector (192 bytes, 48 floats)        ← all fragment encoders
buffer(1) = FFT magnitudes (512 floats)
buffer(2) = waveform samples (1024 floats)
buffer(3) = StemFeatures (256 bytes, 64 floats)
buffer(4) = SceneUniforms (128 bytes) — ray march G-buffer, lighting, SSGI passes ONLY.
buffer(5) = SpectralHistory (4096 Float32, 16 KB) — direct-pass fragment encoders
              [0..479]    valence trail (-1..1)
              [480..959]  arousal trail (-1..1)
              [960..1439] beat_phase01 history (0..1)
              [1440..1919] bass_dev history (0..1)
              [1920..2399] bar_phase01 history (0..1, phrase-level sawtooth; 0 = no BeatGrid)
              [2400] write_head  [2401] samples_valid
              [2402..2417] beat_times[16] — relative beat times in seconds (positive=upcoming).
                           Float.infinity sentinel = unused slot. Written by analysisQueue via
                           updateBeatGridData(). Used by SpectralCartograph tick overlay.
              [2418] bpm — BPM from cached BeatGrid (0 = no grid / reactive mode)
              [2419] lock_state — drift-tracker lock: 0=unlocked, 1=locking, 2=locked
              [2420] session_mode — orchestrator state: 0=reactive, 1=planned+unlocked,
                     2=planned+locking, 3=planned+locked. Written by analysisQueue via
                     updateBeatGridData(). Read by SpectralCartographText.drawModeLabel.
              [2421..4095] reserved (zeroed)
buffer(6) = per-preset fragment buffer #1 — bound by setDirectPresetFragmentBuffer.
              Reserved for: Gossamer wave pool (GossamerGPU), Arachne web pool
              (ArachneWebGPU[kArachWebs] — 96 bytes/web post-V.7.7C.2,
              4 webs × 96 = 384 bytes total).
              ArachneWebGPU layout: Row 0 = (hub_x, hub_y, radius, depth);
              Row 1 = (rot_angle, anchor_count, spiral_revolutions, rng_seed);
              Row 2 = (birth_beat_phase, stage, progress, opacity);
              Row 3 = (birth_hue, birth_sat, birth_brt, is_alive);
              Row 4 = (smoothedValence, smoothedArousal, accTime, reserved) —
                       written identically to all slots each frame; drawWorld()
                       reads webs[0].row4 for the V.7.7 WORLD palette;
              Row 5 (V.7.7C.2 / D-095) = (build_stage, frame_progress,
                       radial_packed, spiral_packed) — packed BuildState for the
                       foreground hero web; written only to webs[0]
                       (background webs zero this row). Four individual Floats
                       (NOT a SIMD4<Float> — that 16-byte alignment would push
                       stride past 96).
              The legacy mv_warp / direct paths AND the V.7.7B+ staged path
              bind this slot per-frame uniformly across every stage of a
              staged preset (RenderPipeline+MVWarp.swift +
              RenderPipeline+Staged.swift). Other presets that need additional
              buffers must use slot 8 (setDirectPresetFragmentBuffer3) or
              extend RenderPipeline with directPresetFragmentBuffer4 / 5;
              never overload 6/7.
buffer(7) = per-preset fragment buffer #2 — bound by setDirectPresetFragmentBuffer2.
              Reserved for: Arachne spider state (ArachneSpiderGPU — 80 bytes,
              V.7.7D contract). Same per-frame uniform binding contract as
              slot 6.
buffer(8) = per-preset fragment buffer #3 — bound by setDirectPresetFragmentBuffer3.
              First consumer (LM.2): Lumen Mosaic's `LumenPatternState`
              (LM.2: 336 B → LM.3: 360 B after adding smoothedValence/Arousal
              + 4 × trackPaletteSeed{A,B,C,D} fields → LM.3.2: 376 B after
              adding the four band counters bassCounter / midCounter /
              trebleCounter / barCounter).
              Slot is shared — any future preset that needs a third per-frame
              state buffer binds here. Same per-frame uniform binding contract
              as slots 6 / 7 in the staged + mv_warp + direct paths.
              **LM.2 widened the ray-march binding contract**: slot 8 is bound
              at BOTH `RayMarchPipeline.runGBufferPass` AND `runLightingPass`
              for every ray-march preset. The preamble's
              `raymarch_gbuffer_fragment` declares `[[buffer(8)]]`
              unconditionally (every ray-march preset compiles against the
              same fragment), so when a preset has not called the setter the
              zero-filled `RayMarchPipeline.lumenPlaceholderBuffer` is bound
              instead — Metal validation requires every declared fragment
              buffer to be bound at draw time. The `sceneMaterial` D-021
              signature gained a trailing `constant LumenPatternState& lumen`
              parameter; non-Lumen presets receive the zero placeholder and
              silence it via `(void)lumen;`. (D-LM-buffer-slot-8)
```

**Authoring note:** buffer(0) is `FeatureVector`, not FFT — the old documentation was wrong. All existing presets (Starburst, VolumetricLithograph, etc.) bind in this order. New preset fragment functions must declare `constant FeatureVector& fv [[buffer(0)]]`. The `SpectralHistory` buffer(5) is available in direct-pass presets; ray march presets currently skip it.

### Preamble Compilation Order
`FeatureVector struct` → `V.1 Noise utility tree (9 files)` → `V.1 PBR utility tree (9 files)` → `V.2 Geometry utility tree (6 files)` → `V.2 Volume utility tree (5 files)` → `V.2 Texture utility tree (5 files)` → `V.3 Color utility tree (4 files)` → `ShaderUtilities.metal functions` → `V.3 Materials cookbook (5 files)` → `constexpr sampler declarations` → preset shader code.

Color loads before ShaderUtilities so palette() is canonical (legacy deleted). Materials loads after ShaderUtilities for additive safety (D-062(d)).

Ray march presets get a separate `rayMarchGBufferPreamble` (includes `raymarch_gbuffer_fragment` which calls preset-defined `sceneSDF`/`sceneMaterial`). This must NOT appear in the shared preamble — standard presets never define those functions.

### G-Buffer Layout (Ray March)
```
gbuffer0: .rg16Float   (R = depth_normalized, G = preset matID — D-LM-matid)
gbuffer1: .rgba8Snorm  (normals + AO)
gbuffer2: .rgba8Unorm  (albedo + packed roughness/metallic)
litTexture: .rgba16Float (lighting output)
```

**`gbuffer0.g` — preset matID dispatch (LM.1 / D-LM-matid).** Half-float
written by the G-buffer fragment as `float(outMatID)` (preset's `sceneMaterial`
out-param); read by `raymarch_lighting_fragment` and dispatched on:

- `matID == 0` (default) — standard dielectric: full Cook-Torrance + screen-space
  soft shadows + IBL ambient + IBL specular + atmospheric fog. Existing presets
  (Glass Brutalist, Kinetic Sculpture, Volumetric Lithograph) all stay on this
  path; their `sceneMaterial` bodies leave `outMatID` at the caller's default 0.
- `matID == 1` — frosted backlit glass dielectric (Lumen Mosaic). Albedo
  carries the backlight intensity AND the frosted-glass surface
  character; the lighting path is the round-4 baseline simplified:
  `albedo × kLumenEmissionGain + irradiance × kLumenIBLFloor × ao`,
  skipping Cook-Torrance + screen-space shadow march. **LM.3.2 round 7
  (2026-05-10) moved frost diffusion from the lighting frag into
  sceneMaterial**: frost is now driven by the Voronoi `f2 - f1`
  cell-edge distance (a large-scale, smooth signal) rather than by
  the SDF relief geometry's normal. Cell centres stay fully vivid;
  cell boundaries get a clean white halo via `mix(cell_hue, white,
  frostiness × kFrostStrength = 0.60)` where
  `frostiness = 1 - smoothstep(0, kFrostBlendWidth = 0.04, f2 - f1)`.
  No more per-pixel dot artifacts (round 5/6 had visible white dots
  inside cells from sub-pixel normal noise in central-differences
  sampling). `kReliefAmplitude` and `kFrostAmplitude` in LumenMosaic.metal
  are both 0 at round 7 — the panel's geometric normal is a clean
  flat `(0, 0, -1)` per pixel. **`kLumenEmissionGain` reduced 4.0 → 1.0
  at LM.3.2 round 4** because the HSV palette is vivid without HDR
  boost and the prior 4× was clipping saturated channels in the
  harness's float→Unorm conversion (production with ACES tonemap
  would handle, harness without tonemap did not). Bloom no longer
  engages on individual cells — correct for the uniformly-vivid
  stained-glass aesthetic. The 0.05 IBL ambient floor keeps the panel
  coloured at silence (D-019). `kLumenEmissionGain` and `kLumenIBLFloor`
  are file-scope `constexpr constant` in `Renderer/Shaders/RayMarch.metal`.

The `sceneMaterial` D-021 signature was extended in two steps:

1. **LM.1 (D-LM-matid)** — added `thread int& outMatID` as the trailing
   parameter. Default behaviour for existing presets is to leave it
   untouched (the preamble's `raymarch_gbuffer_fragment` pre-zeros it
   before the call).

2. **LM.2 (D-LM-buffer-slot-8)** — added `constant LumenPatternState& lumen`
   as the new trailing parameter (after `outMatID`). Bound at fragment
   slot 8 in both the G-buffer and lighting passes. Non-Lumen presets
   receive the zero-filled `RayMarchPipeline.lumenPlaceholderBuffer` and
   silence the parameter via `(void)lumen;`. Lumen Mosaic's
   `sceneMaterial` reads it to compute the cell-quantized 4-light
   backlight (contract §P.3 / §P.4). The preamble defines the
   `LumenLightAgent` (32 B) / `LumenPattern` (48 B) / `LumenPatternState`
   (336 B) MSL structs once for every ray-march preset.

### SSGI
Half-res `.rgba16Float`. 8-sample blue-noise-rotated spiral. `kIndirectStrength = 0.3`. Sky pixels (depth ≥ 0.999) early-exit. Additive blend (src=one, dst=one). `sceneParamsB.w` overrides sample radius (0 → default 0.08 UV).

### AccumulatedAudioTime
`_accumulatedAudioTime += max(0, energy) * deltaTime` where energy = `(bass + mid + treble) / 3.0`. Reset on track change via `pipeline.resetAccumulatedAudioTime()`. Written to `sceneUniforms.sceneParamsA.x` each frame for ray march presets. Exposed as `FeatureVector.accumulated_audio_time` (float 25) for all presets.

### Mesh Shader Architecture
Hardware gated: `device.supportsFamily(.apple8)` (M3+). On M3+: `MTLMeshRenderPipelineDescriptor` + `drawMeshThreadgroups`. On M1/M2: standard vertex pipeline + `drawPrimitives`. `MeshGenerator` owns both and abstracts dispatch. MSL: `[[thread_index_in_threadgroup]]` is correct; `[[thread_index_in_mesh]]` does not exist. `ObjectPayload` uses `object_data` address space.

### ICB Architecture
`icb_populate_kernel` reads FeatureVector, activates slots based on cumulative energy thresholds. `setFragmentBytes` is NOT inherited by ICB commands — use `setFragmentBuffer` bindings. Pipelines must set `supportIndirectCommandBuffers = true`. Use `useResource(_:usage:stages:)` (stages-aware API, macOS 13+).

---


