# Full-Codebase Audit — 2026-06-09

Six parallel review agents audited the complete Phosphene tree (~92k lines: 54k engine Swift,
19k MSL, 19k app Swift). Scope per agent: Audio+DSP, ML+Orchestrator, Renderer+Shared,
Presets+Shaders, Session+Services+Scripts (security focus), Views+ViewModels.
All findings were verified against actual code (file:line cited) and cross-checked against
`docs/QUALITY/KNOWN_ISSUES.md` and the CLAUDE.md Failed Approaches list — nothing below
re-reports a documented issue. No fixes have been applied; per the Defect Handling Protocol,
P0/P1/P2 items need the evidence-before-implementation workflow before code changes.

Severity: P1 = fix soon (crash, data corruption, leak with compounding effect, wrong cert
evidence). P2 = real defect, bounded impact. P3 = latent bug, perf waste, dead code, drift.

---

## P1 — Highest priority

### A1. [concurrency] StemSeparator cross-path data race — live stems can poison the prep cache
`PhospheneEngine/Sources/ML/StemSeparator.swift:174-216`
The live stem pipeline (`VisualizerEngine.performStemSeparation` on `stemQueue`) and the
session preparer (`SessionPreparer.analyzePreview`, `Task.detached`) share **one**
`StemSeparator` instance (`VisualizerEngine+InitHelpers.swift:123`). With progressive
readiness, prep of later tracks runs concurrently with live playback. `separate()` writes
`stemModel.inputMagLBuffer`/`inputMagRBuffer` and reads `stemModel.outputBuffers` **outside
any lock** (only `predict()` itself is locked), and both callers read the shared
`stemBuffers` after return unlocked (`VisualizerEngine+Stems.swift:196`,
`SessionPreparer+Analysis.swift:90`). Overlapping calls can run predict on the other call's
input and read half-written outputs — a prepped track's cached stems can silently be the
live track's stems, poisoning orchestrator stem-affinity scoring. The BUG-012 race analysis
only covered the serial `stemQueue`; the preparer path is a new surface and a plausible
contributor to the BUG-012 family.
**Fix shape:** one lock across input-write → predict → output-read; return stem waveforms
by value instead of exposing shared `stemBuffers`.

### A2. [bug] Duplicate playlist tracks crash `prepare(tracks:)`
`PhospheneEngine/Sources/Session/SessionPreparer.swift:183` (also `:256` for LF path)
`Dictionary(uniqueKeysWithValues:)` traps at runtime on duplicate keys. Spotify playlists
commonly contain the same track twice (identical `TrackIdentity`), and
`PlaylistConnecting`'s doc (`PlaylistConnector.swift:57`) promises duplicates are preserved.
An M3U listing the same file twice does the same on the LF path.
**Fix shape:** `Dictionary(_:uniquingKeysWith:)` or dedupe upstream.

### A3. [bug] `endSession()` orphans the in-flight preparation task; stale prep can hijack the next session
`PhospheneEngine/Sources/Session/SessionManager.swift:562`
`endSession()` flips to `.ended` without cancelling `sessionPreparationTask` or
`statusCancellable`. A new `startSession` resets `cancellationRequested = false`; the
orphaned task's completion closure (`:261`) then passes its guard, overwrites `currentPlan`
with the **old** playlist, cancels the new session's status subscription, and can flip the
new session `.preparing → .ready` prematurely. Also `prepare(tracks:)` — unlike
`prepareLocalFiles` (`:253`) — never cancels a prior task, so two `_runPreparation` loops
can run concurrently against the single `StemSeparator` (compounds A1). This is the exact
bug shape the LF path fixed with `localFileSessionGen` (LF.5.fix.3-A); the streaming path
never got the equivalent.

### A4. [leak] `assign(to:on: self)` retain cycle + per-frame VM construction leaks SessionStateViewModels
`PhospheneApp/ViewModels/SessionStateViewModel.swift:56,61` + `PhospheneApp/PhospheneApp.swift:57-62`
`Subscribers.Assign` retains its target; storing the cancellable in `self.cancellables`
closes the cycle, so the VM never deallocates. Compounding: `PhospheneApp.body` constructs
a **new** `SessionStateViewModel` eagerly on every body evaluation, and the App body
re-evaluates at ~60 Hz during playback (see A5). Every discarded instance has already
subscribed in init and is permanently leaked, each continuing to receive every state change.
**Fix shape:** `sink { [weak self] }` (or `assign(to: &$state)`), and construct the VM once.

### A5. [perf] Per-frame `@Published dashboardSnapshot` drives whole-app SwiftUI invalidation at 60 Hz
`PhospheneApp/VisualizerEngine+InitHelpers.swift:75-84`
`setupDashboardSnapshotPump` writes `engine.dashboardSnapshot` from `onFrameRendered` every
frame unconditionally — allocating a `Task { @MainActor }` per frame — even with the
dashboard hidden. `VisualizerEngine` is `@StateObject`/`@EnvironmentObject` across the view
tree, so `objectWillChange` invalidates App body, `ContentView.playbackView`
(12 fresh `eraseToAnyPublisher()` allocations per frame), and the full `PlaybackView` diff
at frame rate throughout playback. The dashboard VM's 30 Hz throttle is downstream of the
damage. **Fix shape:** gate the pump on `showDebugOverlay`, or publish through a
`PassthroughSubject` only the dashboard VM subscribes to.

### A6. [bug] `sceneParamsB.z` double-booked — every ray-march fixture renders at 1/4 the live step budget
`PhospheneEngine/Sources/Presets/PresetDescriptor+SceneUniforms.swift:99`
`makeSceneUniforms()` packs `sceneAmbient` (default 0.1) into `sceneParamsB.z`, but the
G-buffer preamble (`PresetLoader+Preamble.swift:417`) reads `.z` as the D-057 frame-budget
step multiplier: `clamp(0.1, …) = 0.25` → `maxMarchSteps = 32`. The live path overwrites
`.z = 1.0` (128 steps) per frame (`RenderPipeline+RayMarch.swift:118`), but
`PresetAcceptanceTests`, `PresetVisualReviewTests` (RENDER_VISUAL contact sheets),
`PresetRegressionTests` (golden hashes), and `PresetContrastCertificationTests` all bind raw
`makeSceneUniforms()` output — **certification evidence for ray-march presets is generated
at 32 steps vs live's 128** (FA #66 test/prod-parity class). Corollary: the `scene_ambient`
JSON field never reaches any shader on the live path — dead config + doc drift.
**Fix shape:** move one of the two meanings to a free slot (`sceneParamsB.w` is SSGI-only);
fixtures set `.z = 1.0`; regenerate golden hashes.

---

## P2 — Real defects, bounded impact

### Audio / DSP

- **[bug] NoveltyDetector re-detects every section boundary ~4-5× after the ring wraps** —
  `NoveltyDetector.swift:217`. `detectedBoundaries` stores logical ring indices that go
  stale as the ring slides (~30/detect call); the `tooCloseToExisting` dedup compares fresh
  vs stale indices, so the same boundary passes again every ~1.3 s. Downstream
  `StructuralAnalyzer.registerBoundary` appends unconditionally → section durations collapse
  toward 0, `predictedNextBoundary`/`sectionIndex`/confidence are garbage. **Directly
  relevant to Skein.ENGINE.3 / D-151, which just wired structural prediction live.**
  Fix: dedup by timestamp or absolute frame counter.
- **[concurrency] `stop()` racing a tap reinstall leaves a zombie tap; next `start()` throws
  `alreadyCapturing`** — `AudioInputRouter+SignalState.swift:92`. Reinstalls fire exactly
  during silence, which is when users end sessions. Fix: serialize teardown onto
  `tapMgmtQueue` or re-validate `currentMode` immediately before `startCapture`.
- **[perf] RT-audio-thread heap allocations** (violates the standing no-alloc rule, three sites):
  - `FFTProcessor.swift:149,193` — fresh `magnitudes` + `mono` arrays per call, called from
    the IO-proc closure (`VisualizerEngine+Audio.swift:114`).
  - `AudioBuffer.swift:148` — `latestSamples` does 2048 per-element ring reads + allocating
    append under the lock, per callback. (RMS over the same samples computed 3× per callback
    across AudioBuffer/SilenceDetector/InputLevelMonitor.)
  - `SessionRecorder+RawTap.swift:28` — `Data(bytes:count:)` + `queue.async` closure per
    callback for the first 30 s of every session (whole session under
    `PHOSPHENE_FULL_RAW_TAP=1`).

### ML / Orchestrator

- **[bug] Reactive path can select a hard-excluded preset** — `PresetScorer.swift:67-80` +
  `ReactiveOrchestrator.swift:208-227`. `rank()` never filters despite its doc-comment;
  the reactive nil-current path takes `ranked.first` unconditionally — can pick an
  `excluded: true`/score-0 preset (all-uncertified catalog, or all presets over the
  performance ceiling). The planner path filters; the reactive path doesn't.
- **[bug] Zero-duration track triggers an unscored `catalog.first` fallback bypassing every
  exclusion gate** — `SessionPlanner+Segments.swift:109-129`. May install a diagnostic
  preset (violates D-074). Fix: clamp duration to a positive floor; route fallback through
  `cheapestFallback`.
- **[bug] Mood-override cooldown state never reset across repeat plays/sessions** —
  `LiveAdapter.swift:180-385`. `lastOverrideTimePerTrack` persists; from a track's second
  play onward, override is effectively permanently disabled (stale timestamp + 40 % elapsed
  cap). Fix: clear on track start and at session boundaries.

### Session / Services / Security

- **[bug] `resumeFailedNetworkTracks()` runs a second prep loop concurrently with the live
  one** — `SessionPreparer.swift:509-518`. Doc claims sequential; code spawns a fresh Task.
  Fires precisely during `.preparing` → two loops interleave on one `StemSeparator`,
  progress ping-pongs, `cancelPreparation()` loses the original loop.
- **[bug] `sessionSource`/`currentSource` mutated before the state guard** —
  `SessionManager.swift:174-176,213-215`. A rejected `startSession` still rewrites the
  published origin → `LocalFileTransportBar` hidden mid-session, source labels corrupted.
- **[vuln] Spotify client secret baked into the shipped app bundle** —
  `PhospheneApp/Info.plist:13`. Resolved from the (correctly gitignored)
  `Phosphene.local.xcconfig` into the built Info.plist — plaintext-extractable from any
  distributed binary. PKCE needs no secret; client-credentials is the only consumer.
  Fine for a personal dev build; drop the client-credentials fallback before any distribution.
- **[bug] Re-entrant `login()` leaks the first continuation and arms a stray timeout against
  the second** — `SpotifyOAuthTokenProvider.swift:122-147`. Guard re-entry; cancel the old
  timeout.
- **[leak] Unbounded in-memory stem cache (~7 MB/track), no eviction** — `StemCache.swift:76`.
  A few hundred prepared streaming tracks → multi-GB resident. The disk sibling has a
  500 MB LRU cap; the in-memory cache needs an analogous bound (sliding window around the
  current track index).

### App layer

- **[leak] Same `assign(to:on:)` cycle leaks one `PlaybackChromeViewModel` per session** —
  `PlaybackChromeViewModel.swift:159,255`. Its `deinit` (which cancels `hideTask`) never
  runs; stays subscribed to all ten engine publishers across session boundaries.
- **[bug] `.preparationTotalTimeout` (Rule 5) is unreachable** —
  `PreparationErrorViewModel.swift:150-158`. Rule 4's condition strictly subsumes it; the
  UX_SPEC-backed banner can never fire. Header suggests the guard was meant to be a
  progressive-readiness check.
- **[bug] "Use Apple Music instead" footer button is a no-op in production** —
  `ConnectorPickerView.swift:149,223` (handler `{ }` on both wiring paths). Violates the
  "controls that aren't wired get hidden" rule.
- **[bug] Settings offers a "Local file" capture mode with false copy and no-op selection** —
  `Views/Settings/AudioSettingsSection.swift:42-46`. Copy says "coming in a future update";
  LF.4-LF.6 shipped months ago; `CaptureModeSwitchCoordinator.swift:89` silently returns.
  Violates "Tooltips do not lie."
- **[bug] Localization gate only scans `PhospheneApp/Views/`; user-facing copy in ViewModels
  and ContentView bypasses it** — `Scripts/check_user_strings.sh:21-23`. Verified hardcoded
  English: `SpotifyConnectionViewModel.swift:269,303,305`,
  `AppleMusicConnectionViewModel.swift:142-151`, `ReadyViewModel.swift:88,162-171`,
  `ContentView.swift:194-197`, plus indirection bypasses in `ConnectorType.swift`,
  `TrackInfoCardView.swift:135`, `PlanPreviewTransitionView.swift:30-44`,
  `PreparationProgressView.swift:234-237`, `TrackPreparationRow.swift`.

### Presets

- **[bug] Arachne spiral chord-count contract three-ways inconsistent (CPU 200 / shader 441 /
  test 104)** — `ArachneState.swift:1005`. Post-BUG-011 ranges make the uncapped product
  324-576, so the `min(200, …)` cap always fires; shader normalizes by 441 →
  `fgProgress` saturates at ~0.45: spiral builds to ~45 % then **pops to complete in one
  frame** on the `.stable` snap. Also halves the build cycle (~62 beats vs the documented
  ~136) and fires `_presetCompletionEvent` early.

---

## P3 — Latent bugs, performance waste, dead code, doc drift

### Latent bugs
- `BeatThisPreprocessor.swift:175` — reflect-padding reads out of bounds for inputs < 513
  samples (latent; production passes ≥10 s windows). Guard `nSamples > padSize`.
- `ChromaExtractor.swift:243` — key-stability hysteresis hardcodes 1/60 s per call but the
  analysis queue runs ~94 Hz → the "8 s" gate fires at ~5.1 s. Thread real `deltaTime`.
- `LocalFilePlaybackProvider.swift:360` — >2-channel files produce a corrupt interleaved
  buffer (frames×6 count with a 2-ch layout).
- `LiveBeatDriftTracker.swift:519` — "tight match" gate measures post-EMA deviation; the
  effective window is ±50 ms, not the documented ±30 ms. Fix the doc (thresholds were tuned
  on as-shipped behavior).
- `MIRPipeline.swift:277` — `latestStructuralPrediction` is the only published property
  written outside the lock. Move under the lock (Skein.ENGINE.3 consumer just landed).
- `ReactiveOrchestrator.swift:311-319` — `scheduleTime` adds a track-relative timestamp to
  wall-clock session time; latent (consumer ignores the field today).
- `SessionPlanner.swift:213-219` — `seededNoise` uses `String.hashValue` (random per-launch
  seed); violates D-047's cross-process determinism claim.
- `LiveAdapter+Patching.swift:60-75` — mood override patches `segments[0]` even when a later
  segment is active; cooldown burned for a visual no-op.
- `ShaderLibrary.swift:96` — PSO cache keyed by name only; ignores pixelFormat/ICB flag on
  hit. Latent until the next HDR/EDR format change.
- `RenderPipeline+RayMarch.swift:115` — aspect-ratio guard checks width, divides by height →
  inf/NaN on zero-height drawable. Mirror `drawDirect`'s guard.
- `RenderPipeline+MVWarpScene.swift:35` — mv_warp Pass 0 omits the buffer(5)
  spectral-history binding every other encoder binds. Latent until an instrument-family
  preset runs under mv_warp.
- `RenderPipeline.swift:543` — resize handler early-returns on feedback-texture alloc
  failure, leaving post-process/ray-march/mv_warp/staged textures at a stale size.
- `PostProcessChain.swift:251` — `sceneTexture` permanently aliased to the ray-march
  `litTexture` after one ray-march frame; a later standalone `.postProcess` preset renders
  into the wrong texture, and a full-res rgba16f texture (~16-66 MB) is retained after
  detach.
- `DynamicTextOverlay.swift:122` — single shared texture rewritten per frame while up to 2
  in-flight frames may still sample it (text shimmer; diagnostic preset only today).
- `SessionRecorder.swift:258` — unsynchronized cross-thread read of `lastVideoFrameTime`.
- `PresetLoader.swift:304-318` — malformed JSON sidecar indistinguishable from missing one
  (`try?` collapse); one bad field silently strips the descriptor → preset compiles down the
  wrong pass path. Log the `DecodingError`.
- `PresetLoader.swift:19` — `presets`/`currentIndex` publicly readable without the internal
  lock while the hot-reload watcher mutates on a background queue (dev-only exposure;
  class is `@unchecked Sendable`).
- `ArachneState+ListeningPose.swift:56-60` — listening-pose trigger reuses the
  FA #57-falsified `bassDev && bassAttackRatio` gate; likely structurally unreachable on
  real music (the V.7.7D front-leg lift never fires). Same fix shape as D-095
  (`bassAttRel > 0.30`).
- `PlaybackView.swift:218` — display management (fullscreen, multi-display, hot-plug)
  silently absent for the whole session if `NSApp.keyWindow` is nil at setup; no retry.
- `ReadyViewModel.swift:110-116` — `retry()` accumulates duplicate first-audio
  subscriptions → N+1 `beginPlayback()` calls on first audio.
- `SpotifyOAuthTokenProvider.swift:211-241` — no in-flight dedup on `acquire()` refresh;
  concurrent refresh double-spends the rotating refresh token → `invalid_grant` → valid
  token wiped → forced re-login. Mirror `DefaultSpotifyTokenProvider`'s shared-Task pattern.
- `SpotifyOAuthTokenProvider.swift:417-422` — form encoding uses `.urlQueryAllowed`
  (leaves `+`,`&`,`=` unescaped); an auth code containing `+` silently corrupts.
- `SpotifyOAuthTokenProvider.swift:282-293` — no OAuth `state` parameter (PKCE limits
  impact; RFC 8252 defense-in-depth, cheap to add).
- `SpotifyWebAPIConnector.swift:142` — pagination follows the response's `next` URL
  verbatim with the Bearer token attached; require `host == "api.spotify.com"`.
- `SpotifyWebAPIConnector.swift:101,160` — `makeTracksURL` nil yields a silent
  empty-playlist "success"; throw instead.

### Performance
- `BeatDetector+Tempo.swift:364` — full autocorrelation sweep computed twice per frame with
  ~85 array slice copies, at ~94 Hz (`findBestLag` + `computeAutocorrelationConfidence`
  recompute identical correlations; `vDSP_dotpr` accepts offset pointers). Consider gating
  to 1 Hz like `computeStableTempo`.
- `StemAnalyzer.swift:212` — drums stem FFT computed twice per analysis frame (returned
  mags discarded with `_`, then recomputed).
- `NoveltyDetector.swift:124` — `detect()` recomputes the entire novelty curve from scratch
  (~150k lock-acquiring `similarity()` calls per detection) though only ~30 frames changed.
- `StemSeparator.swift:157-166` — mono input computes the identical STFT twice; every
  prepared preview pays a redundant 431-frame 4096-pt GPU STFT.
- `SessionPreparer.swift:355-417` — per-track pipeline fully serial; a 1-deep prefetch
  (track N+1 download overlapping track N analysis) would roughly halve prep wall-clock.
  `PreviewDownloader.batchDownload`'s 4-way concurrency exists but is never used.
- `RenderPipeline+FeedbackDraw.swift:21` — particle-mode feedback runs a full-screen warp
  pass whose output is never sampled (Murmuration pays one wasted full-res fragment pass +
  two retained full-res textures per frame).
- `RenderPipeline.swift:536` — feedback ping-pong textures (~32 MB at 4K) allocated
  unconditionally on resize for every preset, even with no `.feedback` pass.
- `AudioInputRouter+SignalState.swift:45` — tap-reinstall scheduling (locks, DispatchWorkItem
  alloc, os_log interpolation) runs on the RT audio thread on silence transitions.
- `SpectralCartographText.swift:83-364` — ~15 `CTFont` + ~30 `CTLine` created per frame;
  all cacheable (diagnostic preset only).
- `PreparationProgressView.swift:71` — fresh `ReachabilityMonitor()` constructed as a
  default argument on every body re-evaluation during `.preparing`.
- `MusicKitBridge.swift:123-137` — `fetchBPM` performs a real catalog network round-trip
  then unconditionally returns nil.

### Dead code / complexity
- `BeatDetector+Tempo.swift:46` `percentileOfBuffer`; `FFTProcessor.swift:207`
  `printHistogram` (also `%s`-with-Swift-String bug if revived);
  `SelfSimilarityMatrix.swift:63` `scratchB` allocated never used.
- `RayMarchPipeline.swift:163` — `depthDebugEnabled` dead, doc lies; `runDepthDebugPass`
  has zero call sites.
- `RenderPipeline+FeedbackDraw.swift:20` — dead self-assignment
  `ctx.params.beatValue = ctx.params.beatValue`.
- `SessionPlanner+Segments.swift:101-105,197-205` — stall-guard compares a value against
  itself (never fires); acknowledged-unreachable else-if.
- `PlanPreviewViewModel.swift:108-150` — preset swap/lock machinery unreachable from any UI
  (`catalog: []`, permanently-disabled menu item); gate behind a build flag like the Modify
  button until U.5b.
- Three near-identical iTunes Search clients (`PreviewResolver.swift:145`,
  `StreamingArtworkURLResolver.swift:100`, `ITunesSearchFetcher.swift`) — only one has
  rate-limiting; the artwork resolver hits the same 20 req/min endpoint unthrottled. Two
  Spotify client-credentials implementations (`Audio/SpotifyFetcher.swift` duplicates
  `DefaultSpotifyTokenProvider`). `Session/LocalFolderConnector.swift` is a superseded stub.

### Documentation drift (in-code)
- `RenderPipeline+ICB.swift:64,71` — FeatureVector "128 bytes" / StemFeatures "64 bytes"
  (actual: 192/256 post-D-099).
- `RayMarchPipeline.swift:199` — `lumenPlaceholderBuffer` "376 bytes (LM.3.2)" (actual 568,
  LM.4.7).
- `AudioFeatures+Analyzed.swift:39-41` — inline MSL sketch names float 39 `_pad3` (now
  `track_elapsed_s`).
- `FerrofluidParticles+InitialPositions.swift:44-67` — header says 55×55=3025; code is
  50×50=2500.
- `ArachneState+Spider.swift:18-30` — header documents the FA #57-retired trigger; code uses
  `bassAttRel > 0.30`.
- `PresetDescriptor` — `scene_ambient` documented as "stored in sceneParamsB.z" but never
  reaches any shader on the live path (see A6).

---

## Clean areas (explicitly verified, no findings)

- **GPU contract**: FeatureVector (48 floats), StemFeatures (64), SceneUniforms (8×float4),
  FeedbackParams (8) match `Common.metal` field-for-field; slots 0-8 / textures 0-13
  consistent across direct, staged, mv_warp, ray-march, ICB; triple-buffer semaphore
  signalled on all exit paths. All six per-preset GPU state structs (WebGPU, SkeinUniforms,
  GossamerGPU, NimbusStateGPU, AuroraVeilStateGPU, LumenPatternState) match Swift
  counterparts.
- **Shader sweeps**: no FA #44 (type-name shadowing) or FA #72 (camelCase-in-MSL) hits; all
  particle kernels bounds-guarded; zero-vector normalizes guarded; ray-march loops
  integer-bounded; the single `while` loop (FractalTree) depth-capped. Zero Drift Motes
  orphans (D-102 removal fully clean).
- **OAuth core**: PKCE S256 with SecRandomCopyBytes verifier; tokens in POST bodies over
  HTTPS only; refresh token Keychain-only; no tokens in logs; logout/refresh-failure wipe
  paths correct. No committed secrets repo-wide (`Phosphene.local.xcconfig` gitignored +
  untracked).
- **Disk caches**: PersistentStemCache (500 MB LRU, schema-versioned, atomic) and
  StreamingArtworkDiskCache (100 MB LRU, SHA-256 names) well built; no path traversal.
- **Scripts/**: all `set -euo pipefail`, quoted, argv-passed — no injection, no unsafe temps.
- **ML models**: BeatThisModel (RoPE, BN fusion, padding) and StemModel (shapes, locking)
  internally consistent; MoodClassifier weight dimensions verified programmatically.
- **DSP**: LookaheadBuffer, BeatGrid/Resolver (incl. wrap-aware nearestBeat, halving-only
  octave policy), BeatPredictor, BandDeviationTracker, PitchTracker, SilenceDetector state
  machine, BeatThisPreprocessor STFT/mel math — all verified correct.
- **App layer**: no second SettingsStore (FA #55 holds); LocalFileTransportBar correctly
  gated (UX-2); all VM state-enum switches exhaustive; DashboardOverlayViewModel throttles
  correctly with weak-self sinks.

---

## Suggested sequencing (not yet actioned)

1. **A2 (duplicate-track crash)** — trivial fix, user-facing crash, highest
   likelihood-of-occurrence.
2. **A6 (sceneParamsB.z)** — invalidates ray-march certification evidence; fix + golden-hash
   regen before any further ray-march cert work.
3. **A1 + A3 + resumeFailedNetworkTracks as one increment** — they share a root cause
   (prep/live concurrency around one StemSeparator with no session-generation guard);
   the LF path's `localFileSessionGen` pattern is the template.
4. **A4 + A5 + PlaybackChromeViewModel leak as one increment** — shared root causes
   (assign-cycle pattern; per-frame engine objectWillChange).
5. **NoveltyDetector boundary dedup** — before leaning further on Skein structural signals.
6. Remainder batched by file/subsystem as P3 cleanup increments.
