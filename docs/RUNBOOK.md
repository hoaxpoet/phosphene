# Phosphene — Runbook

## Preconditions

- macOS 14.0+ (Sonoma)
- Apple Silicon Mac (M1+)
- Xcode 16+ with Command Line Tools
- Screen capture permission for live audio capture
- Swift 6.0, Metal 3.1+

## Spotify connector setup (U.11 — OAuth PKCE)

Phosphene uses Spotify's Authorization Code + PKCE flow (user-level OAuth). The user logs in once via their system browser; the refresh token is stored in the macOS Keychain and used silently on subsequent launches.

**One-time developer setup:**

1. Go to [https://developer.spotify.com/dashboard](https://developer.spotify.com/dashboard) and log in.
2. Click **Create app**. Name it "Phosphene". Add redirect URI: **`phosphene://spotify-callback`** (exact, required). Check **Web API**. Accept terms.
3. Copy the **Client ID** from the app dashboard. (No client secret is needed for PKCE.)
4. Create `PhospheneApp/Phosphene.local.xcconfig` (gitignored) with:
   ```
   SPOTIFY_CLIENT_ID = your_client_id_here
   ```
5. In Xcode: Project → Info → Configurations. For **Debug** and **Release**, set the xcconfig to `Phosphene.local`.

The app reads `SpotifyClientID` at runtime via `Bundle.main.infoDictionary`. An empty or missing Client ID causes every Spotify connect attempt to throw `.spotifyAuthFailure` immediately.

**User flow (end-user, one-time):**

1. Paste a Spotify playlist URL in the connector view.
2. Phosphene shows "Log in with Spotify" if not yet authenticated.
3. Tap "Log in with Spotify" → system browser opens `accounts.spotify.com/authorize`.
4. User approves → browser redirects to `phosphene://spotify-callback?code=…`.
5. Phosphene exchanges the code for tokens; refresh token stored in Keychain.
6. Future sessions skip the login step (silent token refresh).

**Logout:** Not yet exposed in the Settings UI. Developer workaround: delete the Keychain item via Keychain Access.app → search "com.phosphene.spotify".


### Spotify connector gotchas — relocated from CLAUDE.md §Failed Approaches (DOC.3b, 2026-05-13)

Three connector-implementation lessons relocated to live next to the Spotify setup instructions. Original CLAUDE.md numbering preserved for cross-reference.

**CLAUDE.md #45 — Assuming the Spotify `/items` response JSON schema is unchanged from `/tracks`.** The Spotify Web API documentation is authoritative. When `/tracks` was deprecated and replaced by `/items`, the response schema changed: each `PlaylistTrackObject` now uses `"item"` as the key for the track/episode object. The old `"track"` key is deprecated. Code that reads `item["track"]` from `/items` responses returns `nil` for every item and silently produces an empty track list. Always check current Spotify Web API reference docs before implementing or modifying connector parsing logic. Confirmed by console log: `hasItem=true hasTrack=false`. **Note (QR.3, 2026-05-07):** `SpotifyItemsSchemaTests` regression-locks this against an on-disk fixture (`Fixtures/spotify_items_response.json`) — if the parser ever falls back to reading only `"track"`, the test fails with `Track A`/`B`/`C` count = 0.

**CLAUDE.md #46 — Using the `fields` query parameter on Spotify's `/items` endpoint.** Field filtering (`fields=items(track(name,artists,...))`) causes the `/items` endpoint to silently return empty dictionaries `{}` for any item whose track data does not exactly match the filter. The result: `items` is a non-empty array of `{}` objects, `compactMap` returns zero tracks, and the session falls back to reactive mode with no error. The root cause is invisible — the API responds 200 with correct `total` and item count but empty item bodies. Fix: omit the `fields` parameter entirely. Use `market=from_token` instead to handle region-restricted tracks, which can otherwise return null track objects.

**CLAUDE.md #47 — Discarding the Spotify `preview_url` field and then calling iTunes Search API to find it.** Spotify's `/items` response includes `preview_url` directly in each `TrackObject` — a CDN URL for the 30-second MP3 preview. Throwing this away and then querying iTunes Search API to find the same URL (at 20 req/min, with fuzzy text matching that can miss tracks) wastes a round-trip and causes false "Preview not available" results. Store `preview_url` on `TrackIdentity` as a hint field excluded from `Equatable`/`Hashable`/`Codable`, and short-circuit `PreviewResolver` when it is present. Tracks where Spotify returns `null` for `preview_url` (rights-restricted, like some Mclusky tracks) genuinely have no preview — fall through to iTunes for those.

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

### Spotify connector failure modes

**Missing Client ID** (`authFailure` state, "Couldn't connect to Spotify"):
- `SpotifyClientID` in Info.plist is empty.
- Cause: `Phosphene.local.xcconfig` not created, or not wired into the xcconfig configuration.
- Fix: follow §Spotify connector setup above. Build again after editing the xcconfig.

**Redirect URI mismatch** (browser shows Spotify error page after login):
- Cause: the redirect URI registered in Spotify's developer dashboard does not exactly match `phosphene://spotify-callback`.
- Fix: re-open the app on developer.spotify.com, edit the redirect URI, and save.

**Authorization denied by user** (`authFailure` state):
- User clicked "Cancel" or "Deny" on the Spotify authorization page.
- Fix: tap "Log in with Spotify" again and approve.

**Login timeout** (`authFailure` state, "Login timed out"):
- The user did not complete the browser flow within 5 minutes.
- Fix: tap "Log in with Spotify" again.

**Refresh token revoked** (`requiresLogin` state reappears on launch):
- Cause: user revoked Phosphene's access in Spotify account settings, or the token expired after a very long period.
- Fix: tap "Log in with Spotify" again to re-authenticate.

**Private playlist** (`privatePlaylist` state, "That playlist is private"):
- HTTP 403 while the user IS authenticated. Two distinct causes:

  **Cause A — Playlist is genuinely private:** Most common. The playlist owner has set it to private.
  - Fix: make the playlist public in Spotify, or use a different playlist.

  **Cause B — Spotify Developer App not configured for Web API (403 on any playlist, even public ones):**
  Spotify's Developer Dashboard requires apps to explicitly opt in to Web API access. If "Web API"
  was not checked when creating the app, the access token is issued without playlist permissions,
  and all `/v1/playlists/{id}/tracks` requests return `{"error":{"status":403,"message":"Forbidden"}}`.
  This happens even for public playlists with a valid OAuth token.
  - Diagnosis: Check `Console.app` → filter for "Spotify 403 body" in the `com.phosphene.app` process.
    If body is exactly `{"error":{"status":403,"message":"Forbidden"}}`, it's Cause B.
  - Fix:
    1. Go to [developer.spotify.com/dashboard](https://developer.spotify.com/dashboard), open your app.
    2. Click **Edit** → under "Which API/SDKs are you planning to use?", tick **Web API**.
    3. Add or re-confirm redirect URI: `phosphene://spotify-callback`.
    4. Click **Save**.
    5. Delete the stored refresh token: open Keychain Access → search "com.phosphene.spotify" → delete it.
    6. Relaunch Phosphene and log in again. The new token will carry playlist permissions.

**Empty playlist / 0 tracks prepared (reactive fallback despite successful login):**
Root causes, in order of likelihood:
1. `"item"` key — the `/items` endpoint uses `"item"` (not `"track"`) as the PlaylistTrackObject key since 2024. A `"track"` key lookup returns nil for all items. Check console for `hasItem=true hasTrack=false`.
2. `fields` query parameter — field-filtered responses silently return `{}` for items where the filter path doesn't match. Check console for `first-item keys: []`. Fix: remove `fields` from the request.
3. `market` parameter missing — region-restricted tracks return null track objects. Add `market=from_token`.
4. Dual-connector re-fetch — `SessionManager`'s own client-credentials connector re-fetches after OAuth succeeds → 401. Routes via `startSession(preFetchedTracks:source:)` should prevent this; check `IdleView` source routing.

**Rate limit exhausted** (after [2s, 5s, 15s] backoff fails):
- Spotify API quota exceeded.
- Fix: wait 60 seconds and retry. Access tokens are cached for their full lifetime (~1 hour).

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

### Display hot-plug causes jank or quality downshift after reconnect

When an external display is connected or disconnected, the `MTKView` drawable reparents and emits a burst of anomalous frame timings that can temporarily suppress stem separation via `MLDispatchScheduler`.

Expected behaviour:
- `DisplayChangeCoordinator` calls `FrameBudgetManager.resetRecentFrameBuffer()` on active-screen removal or window move.
- The rolling timing window is cleared. `MLDispatchScheduler` loses its deferral signal and reverts to `dispatchNow` until the window refills with real frames (~0.5 s at 60 fps).
- Quality level (`currentLevel`) is **not** reset — the governor retains its downshift position.

If quality unexpectedly drops to `.reducedMesh` after reconnect: check `session.log` for `quality: rolling window cleared (display event)` — if absent, `DisplayChangeCoordinator` was not wired in `PlaybackView.setup()`. See [Architecture §Long-Session Resilience](ARCHITECTURE.md#long-session-resilience-increment-72-d-061).

### Capture-mode switch during playback triggers spurious preset change

When the user changes the capture mode (Settings → Audio) while music is playing, `CaptureModeReconciler` relaunches the audio tap. `SilenceDetector` briefly enters `.silent`, which can cause `LiveAdapter` to compute a large mood delta and trigger a preset override.

Expected behaviour:
- `CaptureModeSwitchCoordinator` opens a 5-second grace window: `VisualizerEngine.captureModeSwitchGraceWindowEndsAt` is set and `PlaybackErrorBridge.effectiveThresholdSeconds` is raised to 20 s.
- `applyLiveUpdate` discards any `presetOverride` events during the window. Structural-boundary transitions still fire normally.
- The silence toast does not appear unless audio is still absent after 20 s.

If the preset still changes during mode switch: verify `isCaptureModeSwitchGraceActive` guard in `VisualizerEngine+Orchestrator.swift:applyLiveUpdate`. If the silence toast still fires at 15 s: verify `PlaybackErrorBridge.effectiveThresholdSeconds` is being raised by `CaptureModeSwitchCoordinator.openGraceWindow()`.

### Preparation stalls after brief network outage (tracks remain .failed)

During session preparation, a brief network outage may leave tracks in `.failed` status with no automatic retry.

Expected behaviour:
- `NetworkRecoveryCoordinator` monitors `ReachabilityMonitor.isOnlinePublisher`.
- On `false → true`, it waits 3 s (1 s from monitor + 2 s additional debounce) then calls `SessionManager.resumeFailedNetworkTracks()`.
- Only network-class failures (`.noPreviewURL`, `.downloadFailed`) are retried. Stem-separation failures are not.
- Cap: 3 automatic attempts per preparation session.

If tracks are still stuck after reconnect: check `session.log` for `NetworkRecoveryCoordinator: network restored — resuming failed tracks`. If absent, verify `NetworkRecoveryCoordinator` is wired in `PreparationProgressView.onAppear`. After 3 automatic attempts, use the "Retry" button in `PreparationFailureView` for a manual hard-restart.

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

### 30-second Arachne COMPOSITE kernel cost benchmark (BUG-011 regression gate)

```bash
SOAK_TESTS=1 swift test --package-path PhospheneEngine --filter shortRunArachneComposite
```

Renders Arachne's COMPOSITE fragment to a 1920×1080 offscreen target for 30 simulated seconds at 60 Hz with the spider forced active and a placeholder WORLD texture bound; reports p50 / p95 / p99 / kernel-overrun count from `MTLCommandBuffer.gpuStartTime/gpuEndTime`. Loose gate: kernel p95 < 16 ms on M2 Pro. Arachne is fragment-only so kernel ≈ full-pipeline; spider-forced is the worst case. Failures indicate a shader-side regression (step count, coverage gate, or dispatch gate creep) before the full-pipeline real-music capture catches it.

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

---

## Recording the quality reel

The quality reel is a 3-minute screen capture of Phosphene playing the canonical
playlist (`docs/quality_reel_playlist.json`). Output: `docs/quality_reel.mp4`,
1080p60, H.264, ~50–150 MB. Committed via Git LFS.

**Procedure:**

1. Confirm all three playlist tracks are present in your Apple Music library
   and queueable via the Phosphene Apple Music connector.
2. Build Phosphene Release: `xcodebuild -scheme PhospheneApp -destination 'platform=macOS' -configuration Release`.
3. Set your display to 1920×1080 (external display or Sidecar at 1080p).
4. Open Phosphene and connect the playlist. Wait for `.ready` state.
5. Open macOS Screen Recording (Cmd+Shift+5 → "Record Selected Portion"), target
   the Phosphene window. Set audio source to OFF — the reel captures visuals only.
6. Start recording, then immediately start playback in your music app.
7. Record continuously through all three segments (∼3 min). Do not stop and
   re-start between segments — transitions are part of the artefact.
8. Save as `docs/quality_reel.mp4`. Git LFS commits automatically on `git add`.

**Using Spotify as the source (v1 reel procedure):**

Spotify is a viable reel source — the canonical v1 reel (`docs/quality_reel.mp4`)
was captured this way. Two settings are mandatory and one architectural difference
requires adjustment.

*Spotify settings (before recording):*
- **Settings → Playback → Normalize volume: OFF.** Default normalization (-14 LUFS)
  drops mastered peaks to ~0.15–0.20 RMS, compressing AGC headroom and degrading
  the mood classifier. Failed Approach #30.
- **Settings → Playback → Audio quality → Streaming quality: Lossless (or Very
  High).** Lower bitrates introduce encoding artifacts that corrupt spectral flux
  thresholds and produce spurious onsets.

*Reactive-mode caveat:*
Phosphene has no Spotify OAuth integration. Without OAuth, `SessionManager` cannot
call `startSession(source: .spotify(...))` — the `.ready` state is never reached
via the normal preparation pipeline. Instead, launch Phosphene and invoke
`startAdHocSession()` (the "Start listening now" CTA in IdleView), which advances
directly to `.playing` (reactive mode). The AI Orchestrator has no pre-planned
session; `DefaultReactiveOrchestrator` drives preset selection live. This is a
known degradation relative to a full Apple Music session — the Orchestrator has not
pre-analyzed stems and cannot schedule transitions at structural boundaries. For
V.6 fidelity evaluation, which is per-preset visual quality rather than plan
quality, this is acceptable. See D-066.

*Post-recording sanity checks:*
1. **raw_tap.wav peak level**: Open the session's `raw_tap.wav` (in
   `~/Documents/phosphene_sessions/<timestamp>/`) in QuickLook or Audacity.
   Peak level should be −3 to −9 dBFS. If peak is below −12 dBFS, Spotify
   normalization was still active — re-record.
2. **DRM-silence scan**: `grep -i "drm\|silence\|silent\|recovering" ~/Documents/phosphene_sessions/<timestamp>/session.log`.
   Expect zero `DRM silence` lines for Spotify Lossless. If DRM silence appears,
   the track triggered FairPlay and the captured segment is visually inert — discard
   that segment.
3. **Tap-reinstall scan**: `grep -i "tap reinstall" ~/Documents/phosphene_sessions/<timestamp>/session.log`.
   Any reinstall entries indicate a scrub-induced silence; if they appear inside a
   recording segment, that segment's visuals will show a freeze gap — discard.
4. **Love Rehab onset-count spot-check**: From the session's `features.csv`, count
   `sub_bass` onset rows in any consecutive 5-second window during the Love Rehab
   segment. Reference: 11 sub_bass onsets per 5 s at ~125 BPM (CLAUDE.md Validated
   Onset Counts table). Counts below 6 indicate normalization was active or Lossless
   quality was not set.

**Clone instructions (if LFS not yet pulled):**

```bash
git lfs install
git lfs pull   # downloads quality reel + ML weights + reference images
```

**Re-recording policy:** when V.6+ uplifts land, re-record if visuals changed
materially. Increment `"version"` in `quality_reel_playlist.json` and save the
prior reel as `quality_reel_v<N>.mp4` so prior artefacts remain referenceable.

**Do NOT build an in-engine capture pipeline for this.** QuickTime is sufficient;
adding video output to the engine is a cross-cutting change with frame-pacing
and file-handling scope that doesn't belong in a curation increment. (D-064(d))

---

## Reviewing rubric reports (Increment V.6)

### Print the full rubric breakdown for all presets

```bash
swift test --package-path PhospheneEngine --filter "FidelityRubricReportTests/rubricReport_allPresetsLoad" 2>&1 | grep -E "\[.\]|pass|FAIL|manual"
```

Runs Suite 1 of `FidelityRubricTests` and prints each preset's per-item breakdown. No content assertions — this is a diagnostic readout only.

### Locking in a newly passing preset (Suite 2 gate)

After a fidelity uplift that flips a preset's `meetsAutomatedGate` from `false → true`:

1. Run the report above and confirm the preset shows `[✓]`.
2. Open `PhospheneEngine/Tests/PhospheneEngineTests/Renderer/FidelityRubricTests.swift`.
3. In `expectedAutomatedGate` (Suite 2), change the preset's entry from `false` to `true`.
4. Run `swift test --package-path PhospheneEngine --filter FidelityRubricGateTests` to confirm no regressions.
5. Commit the updated dictionary referencing the preset and D-067.

### Certifying a preset (setting `certified: true`)

1. Confirm `meetsAutomatedGate == true` in the report above.
2. Open each reference image in `docs/VISUAL_REFERENCES/<preset>/README.md` and compare against a live session frame.
3. If visually satisfactory, set `"certified": true` in `PhospheneEngine/Sources/Presets/Shaders/<Preset>.json`.
4. Run `swift test --package-path PhospheneEngine --filter FidelityRubricTests` — all suites must pass.
5. Run `swift test --package-path PhospheneEngine --filter OrchestratorCertifiedFilterTests` — preset should now be included by the Orchestrator.

### Debugging a failing rubric item

| Item | Diagnosis |
|------|-----------|
| M1 (detail cascade) | Add `// macro`, `// meso`, `// micro` comments OR 3+ distinct scale literals in noise calls |
| M2 (octave count) | Use `fbm8(` or `warped_fbm(` — single-octave noise fails |
| M3 (materials) | Add 3+ `mat_*` cookbook calls: `mat_polished_chrome(`, `mat_frosted_glass(`, `mat_wet_stone(`, etc. |
| M4 (deviation) | Replace `f.bass > 0.x` with `f.bass_dev`/`f.bass_rel`; at least one deviation field required |
| M5 (silence) | Check D-019 warmup: `smoothstep(0.02, 0.06, totalStemEnergy)` gate before stem reads |
| M6 (perf) | Lower `complexity_cost.tier2` in JSON sidecar or optimize shader |
| P1 (hero specular) | Set `"rubric_hints": {"hero_specular": true}` in JSON after visual confirmation |
| P3 (dust motes) | Set `"rubric_hints": {"dust_motes": true}` or add `ls_radial_step_uv(` call |
