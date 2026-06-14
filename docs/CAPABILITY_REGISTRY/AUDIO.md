# Capability Registry — Audio Subsystem

**Audit increment:** CA-Audio
**Date:** 2026-05-21
**Auditor:** Claude (session-driven, read-only)
**Scope:** `PhospheneEngine/Sources/Audio/` — 16 files / 3,294 LoC.
**Methodology:** Phase CA scoping document ([`docs/prompts/PHASE_CA_KICKOFF_CA_AUDIO_2026-05-21.md`](../prompts/PHASE_CA_KICKOFF_CA_AUDIO_2026-05-21.md)).
**Reads relied on:** CLAUDE.md (§What NOT To Do sample-rate + Failed Approach #21 / #22 / #29 / #45-47 / #52 + URLProtocol @Suite serialization), [docs/ARCHITECTURE.md §Audio Capture (lines 38–72)](../ARCHITECTURE.md) + §Module Map Audio/ block (lines 482–496), [docs/QUALITY/KNOWN_ISSUES.md](../QUALITY/KNOWN_ISSUES.md) (every Open entry plus BUG-R002/R003/R006), [docs/RUNBOOK.md](../RUNBOOK.md) §Spotify connector setup, [docs/DECISIONS.md](../DECISIONS.md) (D-018 / D-052 / D-070 / D-079), [`Scripts/check_sample_rate_literals.sh`](../../Scripts/check_sample_rate_literals.sh).
**Sibling audits:** [`SESSION.md`](SESSION.md) (CA.3 — Session ↔ Audio boundary; `MetadataPreFetcher` producer closure + `PreviewResolver` chain), [`APP.md`](APP.md) (CA.5 — App-layer `AudioInputRouter` consumer + tap-sample-rate plumbing wire), [`APP_VIEWS.md`](APP_VIEWS.md) (CA.6 — `AudioSignalState` publisher subscribers), [`DSP_MIR.md`](DSP_MIR.md) (CA.1 — `FFTProcessing` protocol consumer), [`ML.md`](ML.md) (CA.2 — `MoodClassifying` / `StemSeparating` re-export consumers), [`ORCHESTRATOR.md`](ORCHESTRATOR.md) (CA.4 — BUG-015 wire + `TransitionPolicy` LookaheadBuffer-coupled doc claim).

---

## Summary

The Audio module exposes 16 files / 3,294 LoC organised in five clusters: (1) capture pipeline (`Audio.swift`, `AudioBuffer`, `AudioInputRouter`(+`SignalState`), `SystemAudioCapture`, `FFTProcessor`, `LookaheadBuffer`); (2) signal-quality monitors (`SilenceDetector`, `InputLevelMonitor`); (3) metadata fetcher cluster (`MetadataPreFetcher`, `MusicBrainzFetcher`, `SpotifyFetcher`, `SoundchartsFetcher`, `MusicKitBridge`); (4) streaming polling (`StreamingMetadata`); (5) protocol surface (`Protocols`).

**13 of 16 files are `production-active`; 2 are `production-orphan` (file-level); 1 is `production-orphan` (cluster); zero `broken-but-claimed` at the code level; one `broken-but-claimed` at the documentation level (ARCH §Audio Capture diagram claims `LookaheadBuffer` is part of the live capture pipeline; the class is never instantiated outside tests). Zero new BUG entries filed.** All four kickoff-required verifications (sample-rate plumbing, tap-recovery state machine, signal-quality monitor timings, FA #21/#22 at the tap source) land clean. CA.3 Session ↔ Audio boundary-noted item closes here.

| Verdict | Count | Notes |
|---|---|---|
| `production-active` | 13 files | All capture + monitor + metadata-fetcher production paths. |
| `production-orphan` (kept-by-design) | 2 files | `LookaheadBuffer.swift` (0 production instantiations; 9 test sites; dual-read-head architecture never wired) — **kept per Matt 2026-05-21** for Phase MV anticipatory-architecture use (planned consumer: Orchestrator anticipatory transitions via mv_warp pre-modulation against `MIRPipeline.latestStructuralPrediction`). `MusicKitBridge.swift` / `MusicKitFetcher` (0 production usage; not in `buildFetcherList()`; not in any test) — **kept per Matt 2026-05-21** as the Apple Music first-class metadata path (planned consumer: wire into `buildFetcherList()` for Apple Music users; direct-catalog-API tempo fetch when MusicKit Swift SDK exposes `Song.tempo`; queue-awareness scaffolding). Annotated `production-orphan + planned-consumer` per CA.7b-FU-3 RayTracing keep precedent. |
| `production-orphan` (field-level) | 3 | `AudioInputRouter.onAnalysisFrame` (line 113) + `.onRenderFrame` (line 117) — declared but never assigned in production; `FFTProcessor.printHistogram(barCount:)` (line 207) — debug-only API with zero consumers anywhere. |
| `stub` (method-level) | 1 | `MusicKitFetcher.fetchBPM(for:)` always returns nil (`MusicKitBridge.swift:123-137`) — MusicKit Swift SDK does not expose tempo; rest of fetcher would only return genre tags + duration if wired. |
| `broken-but-claimed` (doc-level) | 1 | ARCH §Audio Capture diagram line 40: `→ LookaheadBuffer (2.5s analysis/render split)`. Code: zero production instantiations. Fix: remove the arrow or annotate as planned/unwired. |
| `documented-but-missing` | 2 | ARCH §Module Map Audio/ block (lines 482–496) lists 14 of 16 files; missing `Audio.swift` (module marker) + `AudioInputRouter+SignalState.swift` (extension). |
| `boundary-noted` | 4 | Audio ↔ Session (MetadataPreFetcher producer closed); Audio ↔ App (AudioInputRouter consumer chain closed); Audio ↔ DSP (FFTProcessing protocol consumer closed); Audio ↔ ML (StemSeparating + MoodClassifying re-exports closed). |
| CA.3 carry-forward correction | 1 | CA.3 [SESSION.md line 145](SESSION.md) says "`TrackMetadata` (constructed at :295) live in the **Audio** module." Actual location: `PhospheneEngine/Sources/Shared/AudioFeatures+Metadata.swift:30`. `PreFetchedTrackProfile` + `MetadataSource` likewise live in Shared, not Audio. CA.3 correction filed below. |
| Kickoff staleness | 1 | Kickoff says BUG-005 is "Audio-module-internal; SpotifyFetcher producer-side." Actual producer is **Session-layer** `SpotifyWebAPIConnector.swift:241` (extracts `preview_url` from `/items` endpoint) consumed by `PreviewResolver.swift:73`. Audio's `SpotifyFetcher` calls `/v1/search` for audio-features only and has no `preview_url` field. CA-Audio-FU-1 below. |

**Headline findings:**

1. **`LookaheadBuffer` is the audit's load-bearing finding.** Declared as part of the live capture pipeline by ARCH §Audio Capture (line 40), referenced by `TransitionPolicy.swift:134` ("Matches the LookaheadBuffer delay of 2.5 s"), implemented at full quality with 9 dedicated unit tests — but zero production instantiations. The dual-read-head architecture (analysis head at real-time; render head delayed 2.5 s for anticipatory orchestrator decisions) is structurally absent from runtime. `AudioInputRouter.onAnalysisFrame` (line 113) and `.onRenderFrame` (line 117) are the wire callbacks that would source the lookahead — both are declared but never assigned in production. This is **not** a BUG-XXX-class regression (no user-visible breakage; the Orchestrator's transition decisions don't currently depend on lookahead in any load-bearing way) but is a structural orphan equivalent to CA.7b's RayTracing finding — needs Matt's product call: wire it OR retire it OR keep as future infrastructure. Filed as **CA-Audio-FU-2**.

2. **`MusicKitFetcher` is fully orphan**, with both production and test consumers at zero. The class is declared `public final class`, conforms to `MetadataFetching`, is constructed nowhere, and is not in any test file. Its core feature — BPM extraction via MusicKit — is a stub (`fetchBPM(for:)` always returns nil at line 132-136; MusicKit Swift SDK does not expose tempo per the in-code comment at lines 127-131). The buildFetcherList composition (`VisualizerEngine+Audio.swift:55-66`) uses **MusicBrainz + Soundcharts (env-gated) + Spotify (env-gated) + ITunesSearchFetcher (App-side)** — no path for MusicKitFetcher. Filed as **CA-Audio-FU-3** (recommend delete; the file produces no user-visible value and MusicKit BPM extraction is fundamentally blocked by the SDK).

3. **D-079 sample-rate plumbing is clean at the Audio source.** `bash Scripts/check_sample_rate_literals.sh` exits 0 (the soft Gossamer warning is the D-026 lint, not D-079 / FA #52 — out of scope for CA-Audio). Grep for `44100\|44_100` in `Sources/Audio/` returns 2 hits, both in `Protocols.swift:111` (StemSeparating.separate doc-comment "will be resampled to 44100 if different") — comments, not code; the CI gate correctly ignores them via `^\s*//` filter. The `tapSampleRate` immutable-capture-via-NSLock contract per D-079 / Failed Approach #29 / #52 is honoured at the App-side consumer (`VisualizerEngine.swift:243, 246, 253-262`; `+Audio.swift:106`; `+Stems.swift:165, 261, 348`) — Audio module produces the rate via the `(rate: Float)` callback arg and never mutates a shared sample-rate field.

4. **Failed Approaches #21 + #22 verified clean at `SystemAudioCapture.swift`.** FA #21 (don't use `CATapDescription(stereoMixdownOfProcesses: [])` empty array): code uses `stereoGlobalTapButExcludeProcesses: []` for `.systemAudio` (line 256) and `stereoMixdownOfProcesses: [AudioObjectID(app.processIdentifier)]` for `.application` (line 269) — the prohibited form is *empty-array* mixdown; the production code's array always carries the target PID. FA #22 (CGRequestScreenCaptureAccess required): the request lives in `PhospheneApp/VisualizerEngine+PublicAPI.swift:21` (`startAudio()` permission gate); preflight reads happen at lines 20/41 + `PhospheneApp/Permissions/`; `ScreenCapturePermissionProvider.swift:2` explicitly documents the no-request invariant ("Never calls CGRequestScreenCaptureAccess (system dialog doesn't compose with URL-scheme flow)") so the request stays one-shot at the audio-start path. CA-Audio scope itself does not need to call CGRequestScreenCaptureAccess; it correctly delegates the permission gate to the App layer.

5. **Tap recovery state machine matches ARCH §68 spec byte-for-byte.** `reinstallDelays: [TimeInterval] = [3.0, 10.0, 30.0]` at `AudioInputRouter.swift:70` (3 attempts; backoff 3 s → 10 s → 30 s). `scheduleNextReinstall()` at `AudioInputRouter+SignalState.swift:37-62` guards `attempt < reinstallDelays.count` and logs "backoff exhausted" once the array is consumed. `cancelPendingReinstall()` at `:66-72` cancels the pending work-item and resets `reinstallAttempts = 0` on `.active` re-entry. `attemptTapReinstall(attemptNumber:)` at `:76-96` re-checks `silenceDetector.state == .silent` before performing the install (skips if state changed during the backoff window), then calls `performTapReinstall(...)` which destroys + recreates the tap via `systemCapture.stopCapture()` + `systemCapture.startCapture(mode:)` (line 101-103). After each attempt — success or failure — `scheduleNextReinstall()` is called unconditionally; the silence detector decides whether the next attempt fires (state still `.silent` → fires; state `.active` → cancelled by `handleSignalStateChange`). **Gap:** zero dedicated tests for the reinstall logic (`grep -rn "reinstall" PhospheneEngine/Tests` returns only `UserFacingErrorTests.swift`; `SilenceDetectorTests.swift` covers state-machine timings only). Filed as **CA-Audio-FU-4** (add tap-reinstall test coverage; recovery path is critical and untested).

6. **SilenceDetector + InputLevelMonitor timings match ARCH §487-488.** SilenceDetector defaults at `SilenceDetector.swift:80-91`: `silenceDuration = 3.0` s; `recoveryDuration = 0.5` s; `suspectDuration = silenceDuration / 2.0 = 1.5` s. State transitions at `advanceActive` / `advanceSuspect` / `advanceSilent` / `advanceRecovering` (lines 143-197) implement the spec: `.active → .suspect (1.5s) → .silent (3s total) → .recovering (any non-silent frame) → .active (0.5s sustained)`. InputLevelMonitor at `InputLevelMonitor.swift:188` uses `peakEnvelope = max(peak, peakEnvelope * 0.9995)` per submission; at the documented ~94 Hz analysis rate this gives a time constant of ~21 s (matching the header's "rolling peak dBFS (21 s window)" claim — the value is the decay-time-constant, not a literal sliding window, but the post-2026-04-17T19-31-46Z session diagnosed against this). Hysteresis at `:162` declares `static let gradeSwitchFrames: Int = 30` and at `:284-295` requires the pending grade to persist for `gradeSwitchFrames` updates before publishing — matches ARCH "30-frame hysteresis." Peak-only classification post-2026-04-17T21-05-47Z at `:114-124`: treble-fraction thresholds removed (Oxytocin bass-heavy track falsely fired Bluetooth/AirPlay warnings), in-code comment cross-references the session. **InputLevelMonitor has zero dedicated tests** (no `InputLevelMonitorTests.swift` in `Tests/Audio/`; consumer at `VisualizerEngine.swift:415` is production-active but the monitor's classification logic is untested). Filed as **CA-Audio-FU-5**.

7. **BUG-005 producer is not in this audit's scope.** The kickoff cites BUG-005 (Spotify `preview_url` returns null) as "Audio-module-internal; SpotifyFetcher producer-side." Verification: `Audio/SpotifyFetcher.swift:122-147` (`searchTrack`) calls `https://api.spotify.com/v1/search` returning `SpotifyTrack` with only `id` + `durationMs` (line 172-180). No `preview_url` handling exists in this file. The actual BUG-005 producer is **`PhospheneEngine/Sources/Session/Connectors/SpotifyWebAPIConnector.swift:241`** (the playlist-items connector that extracts `track["preview_url"] as? String`), consumed by **`PhospheneEngine/Sources/Session/PreviewResolver.swift:73`** (Spotify-first / iTunes Search fallback per D-070 / Failed Approach #47). Both sites live in **Session**, not Audio. **Kickoff staleness**: BUG-005 should be re-categorised as a Session-domain bug, not Audio. (Note: CA.3 already audited the producer side at the Session module surface; the bug stays Open with the same content, just with the correct domain attribution.) Filed as **CA-Audio-FU-1**.

8. **BUG-013 producer is correctly in Audio scope.** `SoundchartsFetcher.swift` parses `time_signature` correctly at line 187 + 191 (CodingKey mapping `case timeSignature = "time_signature"`); the field is `Int?` so a null/missing field decodes silently to nil. `fetchSongMetadata(uuid:)` at line 141 passes the value through to `PartialTrackProfile.timeSignature`. The Phosphene-side override mechanism (BUG-013 Round 26, Session-side at `SessionPreparer+Analysis.swift:299` per CA.3) consumes the value and overrides `BeatGrid.beatsPerBar` when present. The producer-side handling is correct — the bug is the Soundcharts API not returning the field, not a parser defect. No code change needed in Audio for BUG-013. Note: there's also no fallback fetcher in `buildFetcherList()` that exposes `time_signature` from another source — the BUG-013 "Path B per-track hardcoded overrides" + "different metadata source" fix paths are both out of scope until a product decision lands.

---

## Sub-scope decision

**Single increment.** 3,294 LoC sits between CA.7b (15 files / 2,241 LoC, single-pass) and CA.7a (23 files / 5,413 LoC, deliberately split). The Audio module's clusters (capture pipeline / signal-quality monitors / metadata fetchers / streaming polling / protocols) are interconnected through the `AudioInputRouter` callbacks and `Protocols.swift` surface — splitting into capture-vs-metadata sub-passes would force two duplicate Pass 0 cross-checks and two duplicate boundary-resolution sections. Direct-read all 16 files in a single sweep, no Explore agents needed at this size.

The audit produces **one BUG cross-check + one source-trace + one verification + one doc-drift pass + one write** across all 16 files. Single closeout report.

---

## Verification of CA.3 Session ↔ Audio boundary closure (CA-Audio-specific)

**MetadataPreFetcher producer-side traced.** `MetadataPreFetcher.swift` (212 LoC) is the producer. Public surface:

- `init(fetchers: [any MetadataFetching], timeoutSeconds: Double, maxCacheSize: Int)` — default 3 s timeout per fetcher, 50-entry LRU cache (lines 41-49).
- `prefetch(for track: TrackMetadata) async -> PreFetchedTrackProfile?` — parallel `withTaskGroup` fire-all + LRU promote-on-hit (lines 58-109).
- `cachedProfile(for track: TrackMetadata) -> PreFetchedTrackProfile?` — synchronous cache lookup with LRU promote (lines 113-116).
- `merge(_ partials: [PartialTrackProfile]) -> PreFetchedTrackProfile` — first-non-nil-wins for scalars; genre tags unioned + dedup (lines 176-211).

**Session-side consumer (CA.3 boundary item, now closed):**

- `SessionPreparer.swift:86` — `private let metadataFetcher: MetadataPreFetcher?` storage.
- `SessionPreparer.swift:132` — `metadataFetcher: MetadataPreFetcher? = nil` init parameter.
- `SessionPreparer.swift:299` — `metadataFetcher?.prefetch(for: track)` call site inside the per-track preparation pipeline (Round 26 metadata-driven `beatsPerBar` override path).

**App-side consumer:**

- `VisualizerEngine.swift:199` — `var preFetcher: MetadataPreFetcher?`
- `VisualizerEngine.swift:641` — `let metadataFetcher = MetadataPreFetcher(fetchers: Self.buildFetcherList())` constructed once; shared between `SessionPreparer` (passed at construction) and the runtime track-change callback at `VisualizerEngine+Capture.swift:113-174` (`makeTrackChangeCallback(fetcher:)` + `kickoffPreFetch(for:fetcher:)`).
- `VisualizerEngine+Audio.swift:37` — fallback construction when shared instance is nil.

**Boundary verdict: complete.** The producer-side signature matches the Session consumer's call sites; the cache key derivation (`cacheKey(for: TrackMetadata)` at line 120-125: `"\(title.lowercased())|\(artist.lowercased())"`) matches the Session pre-fetched-profile lookup semantics in `SessionPreparer.swift:299`. The shared-instance pattern at `VisualizerEngine.swift:641` means the Session-side prep and the App-side runtime track-change callback hit the same LRU cache — a prep-time fetch primes the cache for the runtime callback (same track) and vice versa.

**CA.3 correction.** [SESSION.md line 145](SESSION.md) reads:

> *"`MetadataPreFetcher` (used at `SessionPreparer.swift:86, 132` and called at `:299`) and `TrackMetadata` (constructed at `:295`) live in the **Audio** module (`Sources/Audio/MetadataPreFetcher.swift`)."*

Half-right. `MetadataPreFetcher` indeed lives in Audio. **But `TrackMetadata`, `PreFetchedTrackProfile`, and `MetadataSource` all live in `PhospheneEngine/Sources/Shared/AudioFeatures+Metadata.swift` (lines 30, 69, 10 respectively)** — they are Shared module types, not Audio. The Audio module *consumes* `TrackMetadata` (in `MetadataPreFetcher` + `MetadataProviding` protocol) and *produces* `PartialTrackProfile` (declared in `Protocols.swift:223`, then merged into `PreFetchedTrackProfile` by `MetadataPreFetcher.merge`). The `PreFetchedTrackProfile.timeSignature` field added in Round 25 (2026-05-15) is also in Shared. Doc fix needed in SESSION.md.

---

## Verification of D-079 sample-rate plumbing (CA-Audio-specific)

**Required by kickoff.** D-079 / QR.1 / Failed Approach #29 / #52 ban the literal `44100` from any code path that should consume the live tap sample rate, and require `tapSampleRate` to be captured immutably at tap install through an NSLock-guarded accessor.

**Literal grep — Audio module:**

```bash
grep -rn "44100\|44_100" PhospheneEngine/Sources/Audio/
```

Returns 2 hits:

```
PhospheneEngine/Sources/Audio/Protocols.swift:111:    ///   - sampleRate: Sample rate in Hz (will be resampled to 44100 if different).
PhospheneEngine/Sources/Audio/Protocols.swift:111:    ///   - sampleRate: Sample rate in Hz (will be resampled to 44100 if different).
```

Both hits are the same line (a doc comment in `StemSeparating.separate(audio:channelCount:sampleRate:)` describing the resampling target). The literal lives in a comment; the CI gate at `Scripts/check_sample_rate_literals.sh` correctly ignores comment lines via the `^\s*//` filter.

**CI gate run:**

```bash
$ bash Scripts/check_sample_rate_literals.sh
WARNING: .metal preset code uses raw AGC-normalized energy in arithmetic.
         D-026 / Failed Approach #31 — drive from deviation primitives
         (f.bass_dev, f.bass_rel, f.bass_att_rel) instead.
PhospheneEngine/Sources/Presets/Shaders/Gossamer.metal:189:    float brightness  = 0.12 + f.bass * 0.76 + bassRel * 0.12;
Exit: 0
```

The script's exit code is 0 (sample-rate gate passes); the warning is the script's *secondary* D-026 lint (raw AGC-energy thresholding in `.metal` preset code, Failed Approach #31) — out of CA-Audio scope. The Gossamer.metal hit is preset-domain; either a long-standing pre-CA-Audio condition or a recent regression at the preset author level; not the sample-rate gate's concern.

**Allowlist comparison.** `Scripts/check_sample_rate_literals.sh` allowlists 7 files: `StemSeparator.swift`, `StemSeparator+Reconstruct.swift`, `StemModel.swift`, `BeatThisPreprocessor.swift`, `SoakTestHarness+AudioGen.swift`, `StemSampleBuffer.swift`, `StemAnalyzer.swift`, `PitchTracker.swift`. None of these are Audio-module files. The Audio module's `Protocols.swift` is **not** allowlisted, which is correct — the literal there is in a comment, not code, and the CI gate's comment filter catches it without needing an allowlist entry. The allowlist matches the current code state; no drift.

**Producer-side semantics.** `AudioInputRouter` does not own a mutable `tapSampleRate` field. It exposes a computed `var sampleRate: Float { systemCapture.sampleRate }` at line 212-214 — the producer chain is:

```
SystemAudioCapture.startCapture(mode:)
  → createProcessTap()
  → readTapFormat(tapID:)         # reads kAudioTapPropertyFormat
  → updates SystemAudioCapture.sampleRate (private(set))
  → IO proc callback at :202-217 captures `sr = self.sampleRate` once per createIOProc + passes via every audio buffer callback's `rate: Float` arg
```

The IO proc closure captures `sr` once at IO-proc construction (line 198: `let sr = self.sampleRate`); the per-buffer callback signature passes it to the consumer. The Audio module never mutates the rate from the audio thread — the rate is set once at tap-format-read (line 286-289 in `readTapFormat`) and then read by the IO proc closure. **D-079 immutable-capture semantics are honoured at the Audio source.**

**App-side consumer.** Per CA.5 ([APP.md line 243](APP.md)): the App captures the per-buffer `rate: Float` arg and writes it via `updateTapSampleRate(_:)` at `VisualizerEngine.swift:261-263` under `tapSampleRateLock: NSLock`. Reader at `:253-255`. Three stem-path consumers at `VisualizerEngine+Stems.swift:165, 261, 348` (all read `tapSampleRate` once into `let actualRate` before the stem dispatch — same immutable-snapshot pattern). The producer-consumer contract is intact end-to-end.

**Verdict:** Sample-rate plumbing is clean at the Audio source and at the App consumer. D-079 / Failed Approach #52 invariant holds.

---

## Verification of tap recovery state machine (CA-Audio-specific)

**Required by kickoff.** ARCH §68: `AudioInputRouter` watches the silence detector; after `.silent` persists, schedules tap reinstall on backoff 3 s → 10 s → 30 s (three attempts). Each attempt destroys + recreates the tap. Resumption cancels the sequence. Three exhausted attempts → reinstall stops until next active → silent transition.

**Code verification at `AudioInputRouter.swift:53-71 + AudioInputRouter+SignalState.swift:8-112`:**

| ARCH §68 claim | Code reference | Match |
|---|---|---|
| Backoff schedule 3 s → 10 s → 30 s | `AudioInputRouter.swift:70`: `let reinstallDelays: [TimeInterval] = [3.0, 10.0, 30.0]` | ✅ exact match |
| Three attempts | `reinstallDelays.count == 3` + guard at `+SignalState.swift:44` (`attempt < reinstallDelays.count`) | ✅ |
| Each attempt destroys + recreates the tap | `performTapReinstall(captureMode:attemptNumber:)` at `+SignalState.swift:98-111` calls `systemCapture.stopCapture()` then `systemCapture.startCapture(mode:)`; `SystemAudioCapture.cleanup()` at `:295-317` destroys aggregate device + tap; new `startCapture` runs full `createProcessTap` → `createAggregateDevice` → `createIOProc` → `startDevice` chain | ✅ |
| Resumption cancels the sequence | `handleSignalStateChange(_:)` at `+SignalState.swift:22-32` calls `cancelPendingReinstall()` on `.active`; `cancelPendingReinstall` at `:66-72` cancels `reinstallWorkItem` + resets `reinstallAttempts = 0` | ✅ |
| Three exhausted attempts → stop until next active → silent transition | `scheduleNextReinstall` at `+SignalState.swift:37-62` guards on `attempt < reinstallDelays.count` (line 44); on exhaustion logs "Tap reinstall: backoff exhausted (\(attempt) attempts)" and returns without scheduling. Next `.active` resets `reinstallAttempts = 0` via `cancelPendingReinstall`; next `.silent` will see `attempt == 0` and start fresh | ✅ |

**State re-check before install.** `attemptTapReinstall(attemptNumber:)` at `+SignalState.swift:76-96` re-checks `silenceDetector.state == .silent` before performing the install — if state changed during the backoff window (e.g. user un-paused), the attempt is skipped and `cancelPendingReinstall()` is called. This is a defensive guard not explicitly in ARCH §68 but consistent with its spirit; well-designed.

**Lock guard.** All mutations of `reinstallAttempts` and `reinstallWorkItem` go through `lock.withLock { ... }` — the cross-thread visibility contract (`tapMgmtQueue` background thread + audio-thread / main-thread callers) is honoured.

**Gap: zero dedicated tests for the reinstall logic.** `grep -rn "reinstall\|Reinstall" PhospheneEngine/Tests` returns only `UserFacingErrorTests.swift` (unrelated). `SilenceDetectorTests.swift` covers state-machine timings only. `AudioInputRouter+SignalState.swift`'s tap-reinstall logic (the 105-line extension) has **no unit tests**. The recovery path is critical (without it, scrub-induced silence permanently kills audio) and untested. Filed as **CA-Audio-FU-4**.

**Verdict:** Tap recovery state machine matches ARCH §68 spec byte-for-byte. Test coverage gap is the open follow-up.

---

## Verification of SilenceDetector + InputLevelMonitor state machines (CA-Audio-specific)

**Required by kickoff.** ARCH §487: SilenceDetector `.active → .suspect (1.5s) → .silent (3s) → .recovering → .active (0.5s hold)`. ARCH §488: InputLevelMonitor 21s peak-dBFS window + 30-frame hysteresis + peak-only classification post-2026-04-17T21-05-47Z.

**SilenceDetector verification:**

```swift
// SilenceDetector.swift:80-91
init(
    silenceRMSThreshold: Float = 1e-6,
    silenceDuration: TimeInterval = 3.0,        // ✅ matches ARCH "3s"
    recoveryDuration: TimeInterval = 0.5,        // ✅ matches ARCH "0.5s hold"
    ...
) {
    ...
    self.silenceDuration = silenceDuration
    self.suspectDuration = silenceDuration / 2.0   // ✅ 3.0 / 2.0 = 1.5 → matches ARCH "1.5s"
    self.recoveryDuration = recoveryDuration
    ...
}
```

State transitions at `advanceActive` / `advanceSuspect` / `advanceSilent` / `advanceRecovering` (lines 143-197):

| Spec transition | Code | Match |
|---|---|---|
| `.active → .suspect (1.5s)` | `advanceActive`: `silenceStartTime` set on first silent frame; transitions to `.suspect` when `now - start >= suspectDuration` (1.5s) | ✅ |
| `.suspect → .silent (3s total)` | `advanceSuspect`: measures `now - silenceStartTime`; transitions to `.silent` when `>= silenceDuration` (3.0s total since `.active` entry) | ✅ |
| `.suspect → .active (brief dropout)` | `advanceSuspect`: signal returns → resets `silenceStartTime = nil`, `_state = .active` | ✅ |
| `.silent → .recovering` | `advanceSilent`: any non-silent frame → `_state = .recovering`, sets `signalReturnTime = now` | ✅ |
| `.recovering → .active (0.5s sustained)` | `advanceRecovering`: `now - signalReturnTime >= recoveryDuration` (0.5s) → `_state = .active` | ✅ |
| `.recovering → .silent (interruption)` | `advanceRecovering`: silence returned → resets `signalReturnTime = nil`, `_state = .silent` | ✅ |

Test coverage: `SilenceDetectorTests.swift` exists. Visibility note: `final class SilenceDetector` is **internal** (no `public`); tests use `@testable import` to access — not a finding, just a visibility note. Module-internal scope is correct (only `AudioInputRouter` constructs `SilenceDetector`).

**InputLevelMonitor verification:**

```swift
// InputLevelMonitor.swift:127
public static let warmupFrames: Int = 60  // ~0.6s at 94 Hz

// :162
private static let gradeSwitchFrames: Int = 30  // ✅ matches ARCH "30-frame hysteresis"

// :188-189 (in submitSamples)
peakEnvelope = max(peak, peakEnvelope * 0.9995)  // decay factor

// Comment at :136-138 derives time constant:
// "Decay is applied per submission; at 94 Hz with decay=0.9995 the
//  time constant is ~21s, matching the 30s rolling window described
//  in the header."
```

**Time-constant math.** At 94 Hz update rate, decay factor 0.9995 per update gives:
- Time constant τ = -1 / (94 * ln(0.9995)) ≈ -1 / (94 * -0.0005) ≈ 21.3 s ✅

The "21s window" in ARCH is an envelope-decay time constant, not a literal sliding window. The in-code comment is honest about this; the ARCH wording could be tightened to "21 s decay time constant" but the numeric match is exact.

**Peak-only classification post-2026-04-17T21-05-47Z.** `InputLevelMonitor.swift:114-124` documents the removal of treble-fraction thresholds: *"Classification thresholds were removed after session 2026-04-17T21-05-47Z, where raw_tap.wav analysis of Oxytocin — a bass-heavy modern production with minimal high-frequency content by design — showed the chain was clean but the squared-magnitude fraction read as 0.01-0.2% treble and wrongly fired 'Bluetooth/AirPlay codec' warnings."* Code at `:260-279` confirms only peak-dBFS thresholds + `peak < 1e-6` "no signal" path + warmup-frames check fire; spectral-balance EMAs are still computed but only published as informational fields in the snapshot.

**Hysteresis.** `recomputeSnapshotLocked()` at `:248-308`:
- Lines 281-292: pending-quality logic — if candidate quality matches snapshot, reset pendingCount; if matches pending, increment; if different, switch pending.
- Line 293-294: `publishedQuality = (pendingCount >= gradeSwitchFrames || snapshot.quality == .unknown) ? quality : snapshot.quality` — publish only after 30 same-grade updates OR on warmup-complete bootstrap.

**Verdict:** Both state machines match ARCH §487-488 byte-for-byte. The "21s window" wording in ARCH is approximate; the in-code derivation is exact.

**Gap: zero dedicated tests for InputLevelMonitor.** Test files in `Tests/Audio/`: `AudioBufferTests.swift`, `FFTProcessorTests.swift`, `LookaheadBufferTests.swift`, `MetadataPreFetcherTests.swift`, `SilenceDetectorTests.swift`, `StreamingMetadataTests.swift`. **No `InputLevelMonitorTests.swift`.** Filed as **CA-Audio-FU-5**.

---

## Verification of Failed Approach #21 / #22 (CA-Audio-specific)

**Required by kickoff.** FA #21: `CATapDescription(stereoMixdownOfProcesses: [])` empty array = silence. Use `stereoGlobalTapButExcludeProcesses: []`. FA #22: `CGRequestScreenCaptureAccess()` required before tap creation.

**FA #21 verification at `SystemAudioCapture.swift:252-274`:**

```swift
private func buildTapDescription(for mode: CaptureMode) throws -> CATapDescription {
    switch mode {
    case .systemAudio:
        // Capture all system audio — exclude nothing.
        let desc = CATapDescription(stereoGlobalTapButExcludeProcesses: [])   // ✅ correct form
        desc.uuid = tapUUID
        desc.name = "PhospheneSystemTap"
        return desc

    case .application(let bundleIdentifier):
        // Find the process ID for the target application.
        guard let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == bundleIdentifier
        }) else {
            throw AudioCaptureError.applicationNotFound(bundleIdentifier)
        }

        let desc = CATapDescription(stereoMixdownOfProcesses: [AudioObjectID(app.processIdentifier)])
                                                              // ↑ non-empty array — intended use
        desc.uuid = tapUUID
        desc.name = "PhospheneAppTap-\(bundleIdentifier)"
        return desc
    }
}
```

FA #21 prohibits the *empty-array form* of `stereoMixdownOfProcesses: []` (which is interpreted by Core Audio as "mix down no processes" → silence). The production code:

- For `.systemAudio`: correctly uses `stereoGlobalTapButExcludeProcesses: []` (the empty array means "exclude no processes from the global tap" → captures everything).
- For `.application`: uses `stereoMixdownOfProcesses: [PID]` with a **non-empty** array containing the target process ID — this is the intended/correct use of `stereoMixdownOfProcesses`. The PID is resolved via `NSWorkspace.shared.runningApplications.first(where:)` and throws `AudioCaptureError.applicationNotFound` if the bundle ID isn't a currently-running process.

**Verdict:** FA #21 honoured. The prohibited empty-array form does not appear anywhere in the production code.

**FA #22 verification.** `SystemAudioCapture` does **not** call `CGRequestScreenCaptureAccess()` (correct — permission gating belongs at the application boundary, not in capture code). Grep across the workspace:

```bash
$ grep -rn "CGRequestScreenCaptureAccess\|CGPreflightScreenCaptureAccess" PhospheneApp PhospheneEngine/Sources
PhospheneApp/VisualizerEngine+PublicAPI.swift:20:        var permitted = CGPreflightScreenCaptureAccess()
PhospheneApp/VisualizerEngine+PublicAPI.swift:21:        if !permitted { permitted = CGRequestScreenCaptureAccess() }
PhospheneApp/VisualizerEngine+PublicAPI.swift:41:                if CGPreflightScreenCaptureAccess() {
PhospheneApp/Permissions/PermissionMonitor.swift:21:    /// `true` when `CGPreflightScreenCaptureAccess()` reports permission granted.
PhospheneApp/Permissions/ScreenCapturePermissionProvider.swift:1:// ScreenCapturePermissionProvider — Abstracts CGPreflightScreenCaptureAccess for testability.
PhospheneApp/Permissions/ScreenCapturePermissionProvider.swift:2:// Never calls CGRequestScreenCaptureAccess (system dialog doesn't compose with URL-scheme flow).
PhospheneApp/Permissions/ScreenCapturePermissionProvider.swift:20:        CGPreflightScreenCaptureAccess()
PhospheneApp/Views/Onboarding/PermissionOnboardingView.swift:8:// Never calls CGRequestScreenCaptureAccess.
PhospheneEngine/Sources/Shared/UserFacingError.swift:31:    /// Screen-capture permission not granted (`CGPreflightScreenCaptureAccess() == false`).
```

`CGRequestScreenCaptureAccess()` is called exactly once, at **`PhospheneApp/VisualizerEngine+PublicAPI.swift:21`** inside `startAudio()` — the entry point for audio capture. The code path: preflight read first (`CGPreflightScreenCaptureAccess()` at line 20), and only request if not already granted. `ScreenCapturePermissionProvider.swift:2` explicitly documents the single-request-point invariant: *"Never calls CGRequestScreenCaptureAccess (system dialog doesn't compose with URL-scheme flow)"* — meaning the permission provider abstraction (used by the permission monitor and onboarding view) is preflight-only; the request prompt is reserved for the audio-start path.

**Verdict:** FA #22 honoured. The Audio module correctly delegates the permission request to the App layer; the App layer correctly localises the request to a single audio-start site.

---

## Verification of metadata-fetcher BUG surfaces (CA-Audio-specific)

**Required by kickoff.** Characterise producer-side handling for BUG-005 + BUG-013 + Failed Approaches #45 / #46 / #47.

### BUG-005 (Spotify `preview_url` returns null) — NOT in Audio scope

The kickoff claimed: *"BUG-005 (Open; Spotify `preview_url` returns null for some tracks) — Audio-module-internal; SpotifyFetcher producer-side."*

**Reality.** Audio module's `SpotifyFetcher.swift:122-147` (`searchTrack`) calls `https://api.spotify.com/v1/search`:

```swift
private func searchTrack(title: String, artist: String, token: String) async -> SpotifyTrack? {
    let query = "track:\(title) artist:\(artist)"
    var components = URLComponents(string: "https://api.spotify.com/v1/search")
    ...
}

private struct SpotifyTrack: Decodable {
    let id: String
    let durationMs: Int?
    ...
}
```

The response struct decodes only `id` + `duration_ms`. **No `preview_url` field exists in the Audio `SpotifyFetcher` data path at all.** The fetcher exists to populate `PartialTrackProfile.duration` (only).

The actual BUG-005 producer is `PhospheneEngine/Sources/Session/Connectors/SpotifyWebAPIConnector.swift:241`:

```swift
// SpotifyWebAPIConnector.swift:241 (Session module)
let spotifyPreviewURL = (track["preview_url"] as? String).flatMap(URL.init)
...
spotifyPreviewURL: spotifyPreviewURL  // line 249
```

Consumed by `PreviewResolver.swift:73`:

```swift
// PreviewResolver.swift:73 (Session module)
if let spotifyURL = track.spotifyPreviewURL {
    ...
}
```

BUG-005 lives entirely in the **Session** module (`Connectors/SpotifyWebAPIConnector` produces; `PreviewResolver` consumes; both already audited at the Session-module surface by CA.3). The kickoff prompt is stale on this point. **Filed as CA-Audio-FU-1**: update KNOWN_ISSUES.md BUG-005 with the correct producer-domain attribution (currently the BUG body itself only refers to `PreviewResolver` — the kickoff's "Audio-module-internal" claim was the only place the wrong domain was asserted; the BUG body is correct).

### BUG-013 (Soundcharts does not expose `time_signature`) — Producer-side correct

`SoundchartsFetcher.swift` correctly decodes the `time_signature` field via the explicit `CodingKey` mapping:

```swift
// SoundchartsFetcher.swift:172-193
private struct SCAudioFeatures: Decodable {
    let tempo: Float?
    let key: Int?
    let mode: Int?
    let energy: Float?
    let valence: Float?
    let danceability: Float?
    /// Time-signature numerator (Round 25, 2026-05-15). `Int?` so the
    /// decode silently sets it to nil if Soundcharts doesn't return the
    /// field. ...
    let timeSignature: Int?

    enum CodingKeys: String, CodingKey {
        case tempo, key, mode, energy, valence, danceability
        case timeSignature = "time_signature"
    }
}
```

The decoder is correctly written. `time_signature` is declared `Int?` so a null or missing field silently decodes to nil. `fetchSongMetadata(uuid:)` at line 141 passes the value through to `PartialTrackProfile.timeSignature`. The Session-side override consumer (`SessionPreparer+Analysis.swift:299` per CA.3) applies the value to `BeatGrid.beatsPerBar` via `BeatGrid.overridingBeatsPerBar(_:)` when present.

**The bug is the Soundcharts API not exposing the field** (the BUG-013 body confirms: *"Soundcharts (the only metadata source in production that exposes audio features) does not return `time_signature` in its API response — verified by adding the decode field and observing zero hits in session.log"*). The producer-side handling is correct; there's nothing to fix in Audio for BUG-013.

**Cross-fetcher observation.** The other fetchers in the catalog produce zero `timeSignature` data:
- `MusicBrainzFetcher` (line 89-92): builds `PartialTrackProfile(genreTags: tags, duration: duration)` — no timeSignature.
- `SpotifyFetcher` (line 72-74): builds `PartialTrackProfile(duration: result.durationMs.map { Double($0) / 1000.0 })` — no timeSignature (Spotify deprecated `/audio-features` in Nov 2024; the search endpoint doesn't expose `time_signature`).
- `MusicKitFetcher` (line 85-103): builds profile from genre + duration only; no timeSignature.

So `Soundcharts` is the only catalog member that *could* produce `timeSignature`, and it doesn't. The BUG-013 fix paths (per BUG body: per-track hardcoded overrides; add a fetcher that exposes `time_signature`; improve ML meter detection) are all out of Audio scope until a product decision lands.

### Failed Approaches #45 / #46 / #47 (Spotify API quirks) — RUNBOOK-promoted; verify against RUNBOOK

Per the kickoff and per DOC.3, FAs #45-47 were promoted from CLAUDE.md to `docs/RUNBOOK.md §Spotify connector setup` per the 2026-05-13 doc-refactor. These FAs describe the **PhospheneEngine/Sources/Session/Connectors/SpotifyWebAPIConnector** behaviour (the playlist-items connector at `/items` endpoint), NOT the Audio-module `SpotifyFetcher` (the search-based metadata enrichment fetcher). RUNBOOK is the canonical doc surface; Audio's `SpotifyFetcher` is not affected by FAs #45-47.

Audio's `SpotifyFetcher` uses:
- **Auth flow:** Client Credentials (server-to-server) via env vars `SPOTIFY_CLIENT_ID` + `SPOTIFY_CLIENT_SECRET` (`SpotifyFetcher.swift:47-55`).
- **Endpoint:** `https://api.spotify.com/v1/search` (`:122-130`).
- **Cached token** with 1-minute expiry buffer (`:111`).

This is a separate Spotify code path from the Session-layer OAuth user-token connector. The two paths use different env vars (the Session-layer Spotify uses user OAuth; this Audio fetcher uses client credentials). Worth noting in RUNBOOK if not already there.

**Verdict:** FAs #45-47 do not apply to the Audio module's SpotifyFetcher. The Audio module's Spotify integration is the metadata-enrichment search path, not the preview-URL extraction path that FAs #45-47 cover.

---

## Per-file capability index

Each file gets a verdict + cited evidence. Per the methodology, internal methods are noted but not separately versioned unless load-bearing.

### Capture pipeline (6 files, 1,525 LoC counting Audio.swift module marker)

#### Audio.swift (11 LoC) — `production-active`

Module marker. Imports `Foundation / CoreAudio / AVFoundation / Accelerate`. The header comment notes Core Audio taps as primary capture path (macOS 14.2+) and references the ScreenCaptureKit dead-end. Module markers are typically minimal; this file is correct.

**Doc-drift:** ARCH §Module Map Audio/ block does NOT list `Audio.swift`. Filed in §Cross-references below.

#### AudioBuffer.swift (187 LoC) — `production-active`

UMA ring buffer for GPU consumption. `public final class AudioBuffer: AudioBuffering, @unchecked Sendable`. Init takes `MTLDevice + capacity: Int = 2048`. NSLock-guarded write paths.

| Public API | Verdict | Consumer | Note |
|---|---|---|---|
| `init(device:capacity:)` | `production-active` | `VisualizerEngine.swift:591`; 5 test files | — |
| `write(from pointer:count:)` | `production-active` | (audio thread; via callback) | RMS computed inside lock-protected critical section |
| `write(samples: [Float])` | `production-active` | Tests + indirectly via `StemSampleBuffer.write(samples:count:)` overload chain | App uses pointer form; tests use both |
| `metalBuffer: MTLBuffer` | `production-active` | `RenderPipeline.swift:24, 277` (waveformBuffer slot) | — |
| `head: Int` | `production-active` | — | NSLock-protected; debug + GPU sync |
| `sampleCount: Int` | `production-active` | — | |
| `totalWritten: UInt64` | `production-active` | Tests | Debug stat |
| `currentRMS: Float` | `production-active` | (via AudioBuffering protocol) | RMS for debug monitoring |
| `latestSamples(count:) -> [Float]` | `production-active` | `VisualizerEngine+Audio.swift:111` (FFT input); `FFTProcessor.swift:27` (doc example); 5 test files | Threads `count` for FFT-sample extraction |
| `reset()` | `production-active` | Tests | |
| `defaultWaveformCapacity = 1024` / `defaultCapacity = 2048` static | `production-active` | — | Sizing for 1024 stereo frames |

**No findings.** RMS computation does not allocate (pre-allocated scratch + manual loop); the audio-IO contract is honoured. The lock protects the write path; the read path (`metalBuffer`) is GPU-only and synchronised via Metal command-buffer ordering (per the in-code comment at lines 6-10).

#### AudioInputRouter.swift (313 LoC) — `production-active` (field-level orphans noted)

`@available(macOS 14.2, *) public final class AudioInputRouter: @unchecked Sendable`. Unified audio-input abstraction over `SystemAudioCapture` / file playback / metadata observation.

| Public API | Verdict | Consumer | Note |
|---|---|---|---|
| `enum InputMode { .systemAudio, .application(bundleIdentifier:), .localFile(URL) }` | `production-active` | App's `CaptureModeReconciler` (maps from `SettingsStore.CaptureMode`); SoakTestHarness; SoakRunner; integration tests | |
| `init(capture:metadata:)` / `init(capture:metadata:silenceDetector:)` (internal) | `production-active` | App `VisualizerEngine+Audio.swift:26`; tests | |
| `var onAudioSamples` | `production-active` | App `+Audio.swift:30` (`makeAudioSampleCallback`) | Audio thread; no-alloc; calls `updateTapSampleRate(Double(rate))` |
| `var onAnalysisFrame` | **`production-orphan`** (field-level) | (declared but no production assignment) | Part of LookaheadBuffer architecture; never wired |
| `var onRenderFrame` | **`production-orphan`** (field-level) | (declared but no production assignment) | Part of LookaheadBuffer architecture; never wired |
| `var onTrackChange` | `production-active` | App `+Audio.swift:39` (`makeTrackChangeCallback`) + SoakTestHarness | |
| `var onSignalStateChanged` | `production-active` | App `+Audio.swift:31` (`makeSignalStateCallback`) + SoakTestHarness `:200` | |
| `var signalState: AudioSignalState` | `production-active` | (computed from internal SilenceDetector) | |
| `start(mode:)` | `production-active` | App `startAudioCapture` (`+PublicAPI.swift:54`) | Throws if capture-mode start fails |
| `startMetadataOnly()` | `production-active` | App pre-permission path | Metadata polling does not require screen-capture permission |
| `switchMode(_ mode:)` | `production-active` | App `CaptureModeReconciler.swift:38-...` (D-052 live-switch) | |
| `stop()` | `production-active` | App teardown path | |
| `activeMode: InputMode?` | `production-active` | Tests + diagnostics | |
| `sampleRate: Float` | `production-active` | (via `AudioCapturing.sampleRate`) | Read-only computed |
| `channelCount: UInt32` | `production-active` | (via `AudioCapturing.channelCount`) | Read-only computed |
| `currentTrack: TrackMetadata?` | `production-active` | (via `MetadataProviding.currentTrack`) | |

**Internal:**
- `reinstallAttempts: Int` / `reinstallWorkItem: DispatchWorkItem?` / `reinstallDelays: [TimeInterval] = [3.0, 10.0, 30.0]` / `tapMgmtQueue` — all consumed by `+SignalState.swift` extension. `production-active`.
- `silenceDetector: SilenceDetector` — constructed in init; wires `onStateChanged` callback to `handleSignalStateChange`.

**Findings:**

1. `onAnalysisFrame` + `onRenderFrame` are **production-orphan**. No production code assigns either callback. The `LookaheadBuffer` (which would source these callbacks) is also never instantiated in production. See §LookaheadBuffer below + **CA-Audio-FU-2** (Matt's product call needed).

2. `lock` is declared `let lock = NSLock()` (line 45) — used by `start(mode:)`, `switchMode`, `stop`, `activeMode`, and the `+SignalState.swift` extension. Cross-thread safe.

3. `filePlaybackTask` (line 44) — `Task<Void, Never>?` for local-file playback (testing/offline path). Pre-allocates the interleaved buffer once (lines 247) per the no-allocation-in-tight-loop discipline; comment notes the stale-tail trick is safe because the callback only sees `totalSamples` per chunk.

#### AudioInputRouter+SignalState.swift (112 LoC) — `production-active`

Tap-reinstall state machine extension. Verified clean against ARCH §68 above. **No dedicated tests** (CA-Audio-FU-4).

| Internal API | Verdict | Consumer |
|---|---|---|
| `handleSignalStateChange(_:)` | `production-active` | SilenceDetector callback (line 85 of AudioInputRouter.swift) |
| `scheduleNextReinstall()` | `production-active` | `handleSignalStateChange` on `.silent` |
| `cancelPendingReinstall()` | `production-active` | `handleSignalStateChange` on `.active`; `attemptTapReinstall` defensive cancel |
| `attemptTapReinstall(attemptNumber:)` | `production-active` | DispatchWorkItem fired after backoff delay |
| `performTapReinstall(captureMode:attemptNumber:)` | `production-active` | `attemptTapReinstall` for `.systemAudio` + `.application` |

**Doc-drift:** ARCH §Module Map Audio/ block does NOT list this extension file.

#### SystemAudioCapture.swift (322 LoC) — `production-active`

Core Audio process taps. `@available(macOS 14.2, *) public final class SystemAudioCapture: AudioCapturing, @unchecked Sendable`. FA #21 + #22 verified clean above.

| Public API | Verdict | Consumer | Note |
|---|---|---|---|
| `enum CaptureMode { .systemAudio, .application(bundleIdentifier:) }` | `production-active` | AudioInputRouter; SettingsTypes (different enum, same name) | |
| `enum AudioCaptureError` (9 cases) | `production-active` | `AudioCapturing` callers; UserFacingError mapping | |
| `struct RunningApplication: Sendable, Identifiable` | `production-active` | App settings UI (capture mode picker) | |
| `init()` | `production-active` | AudioInputRouter default; FerrofluidLiveAudioTests | |
| `sampleRate: Float` (private(set)) | `production-active` | AudioCapturing protocol; AudioInputRouter | Set in `readTapFormat` |
| `channelCount: UInt32` (private(set)) | `production-active` | (same) | |
| `onAudioBuffer` | `production-active` | AudioInputRouter wires inside `start(mode:)` | Audio thread; no-alloc closure |
| `isCapturing: Bool` | `production-active` | tests + tap-reinstall defensive checks | NSLock-protected |
| `availableApplications() -> [RunningApplication]` static | `production-active` | App settings UI | NSWorkspace enumeration |
| `startCapture(mode:)` throws | `production-active` | AudioInputRouter | Full chain: createProcessTap → readTapFormat → createAggregateDevice → createIOProc → startDevice |
| `stopCapture()` | `production-active` | AudioInputRouter; tap-reinstall path | Calls `cleanup()` |
| `switchMode(_ mode:)` throws | `production-active` | AudioInputRouter `switchMode` | stop + start |

**Internal:**
- `createProcessTap(for:)` / `createAggregateDevice()` / `createIOProc(aggregateID:)` / `startDevice(aggregateID:procID:)` — full Core Audio setup chain.
- `buildTapDescription(for:)` — verified for FA #21 above.
- `readTapFormat(tapID:)` — reads `kAudioTapPropertyFormat`; updates `sampleRate` + `channelCount` from the tap's actual `AudioStreamBasicDescription`. Falls back to 48 kHz stereo on read failure with `.warning`-level log.
- `cleanup()` — destroys IO proc + aggregate device + tap.
- `deinit { cleanup() }` — defensive teardown.

**No findings.** The IO proc callback at lines 202-217 is the load-bearing real-time path; it does not allocate, takes `let callback = self.onAudioBuffer` snapshot, and iterates the AudioBufferList processing only the first buffer (stereo interleaved per macOS convention).

#### FFTProcessor.swift (249 LoC) — `production-active` (debug API field-level orphan)

vDSP-based 1024-point FFT producing 512 magnitude bins in a UMA buffer. `public final class FFTProcessor: FFTProcessing, @unchecked Sendable`.

| Public API | Verdict | Consumer | Note |
|---|---|---|---|
| `static let fftSize = 1024` / `binCount = 512` | `production-active` | App `latestSamples(count: fftSize * 2)`; tests; RenderPipeline doc | |
| `init(device:) throws` | `production-active` | App `VisualizerEngine.swift:592`; TempoDumpRunner; tests | All buffer allocations at init time |
| `magnitudeBuffer: UMABuffer<Float>` | `production-active` | RenderPipeline (slot 1); 7 test files | GPU-shared output |
| `latestResult: FFTResult` (private(set)) | `production-active` | tests; debug | |
| `process(samples:sampleRate:)` | `production-active` | App `processAnalysisFrame`; tests; TempoDumpRunner | Mono input; Hann window + vDSP_ctoz + vDSP_fft_zrip + vDSP_zvabs |
| `processStereo(interleavedSamples:sampleRate:)` | `production-active` | tests | Mixdown then call `process` |
| `printHistogram(barCount:)` | **`production-orphan`** (field-level) | (zero consumers anywhere) | Debug-only console histogram |

**Internal vDSP resources** (init-allocated, reused per frame): `fftSetup`, `window` (Hann), `realPart` / `imagPart` (split-complex), `windowedSamples`. `deinit { vDSP_destroy_fftsetup(fftSetup) }` cleans up.

**Finding:** `printHistogram(barCount:)` at line 207-242 has zero consumers (verified grep above). Debug-only console output. Worth removing in a future cleanup pass — same shape as CA.7-FU-4's `setRayMarchPresetComputeDispatch` retirement (CA.7-FU-2 dead-code precedent). **Filed as low-priority CA-Audio-FU-6.**

#### LookaheadBuffer.swift (168 LoC) — **`production-orphan`**

Timestamped ring buffer with dual read heads. `public final class LookaheadBuffer: @unchecked Sendable`. Full implementation, 9 dedicated unit tests, doc-claimed as part of the live capture pipeline at ARCH §Audio Capture line 40.

| Public API | Verdict | Consumer | Note |
|---|---|---|---|
| `static let defaultDelay: Double = 2.5` | `production-orphan` | tests + doc claim only | Doc claim at TransitionPolicy.swift:134 + ARCH §Audio Capture line 40 |
| `static let defaultCapacity: Int = 512` | `production-orphan` | tests | |
| `init(capacity:delay:)` | `production-orphan` | **9 test sites; zero production sites** | |
| `var delay: Double { get / set }` | `production-orphan` | tests | NSLock-protected |
| `var frameCount: Int` | `production-orphan` | tests | |
| `enqueue(_ frame:)` | `production-orphan` | tests | |
| `dequeueAnalysisHead() -> AnalyzedFrame?` | `production-orphan` | tests | |
| `dequeueRenderHead() -> AnalyzedFrame?` | `production-orphan` | tests | |
| `reset()` | `production-orphan` | tests | |

**Cited grep (production-orphan evidence):**

```bash
$ grep -rn "LookaheadBuffer(" PhospheneApp PhospheneEngine/Sources --include='*.swift'
# (no hits — zero production instantiations)
```

```bash
$ grep -rn "LookaheadBuffer" PhospheneApp PhospheneEngine/Sources --include='*.swift'
PhospheneEngine/Sources/Shared/AnalyzedFrame.swift:13:                          # doc-comment only
PhospheneEngine/Sources/Audio/AudioInputRouter.swift:116:                       # doc-comment only
PhospheneEngine/Sources/Orchestrator/TransitionPolicy.swift:134:               # doc-comment only — "Matches the LookaheadBuffer delay of 2.5 s."
```

```bash
$ grep -rn "onAnalysisFrame\|onRenderFrame" PhospheneApp PhospheneEngine/Sources --include='*.swift'
PhospheneEngine/Sources/Audio/AudioInputRouter.swift:113:    public var onAnalysisFrame: ((_ frame: AnalyzedFrame) -> Void)?
PhospheneEngine/Sources/Audio/AudioInputRouter.swift:117:    public var onRenderFrame: ((_ frame: AnalyzedFrame) -> Void)?
# (only the declarations; no assignments anywhere)
```

**Verdict:** `LookaheadBuffer` is fully orphan at production. The dual-read-head architecture exists as infrastructure but is never wired. Structurally analogous to CA.7b's RayTracing finding (production-active in code, zero production consumers) → kept-by-design by Matt's product call for future presets. **Matt's product call needed on LookaheadBuffer**: wire it (Phase MV anticipatory architecture intent), keep it as infrastructure, or retire it. **Filed as CA-Audio-FU-2.**

**Doc-level consequence:** ARCH §Audio Capture line 40 claims `→ LookaheadBuffer (2.5s analysis/render split)` in the pipeline. This is **`broken-but-claimed` at the documentation level** — the diagram is load-bearing for new contributors trying to understand the audio chain, and it lies. Fix: remove the arrow OR annotate as planned-but-unwired (similar to ARCH's annotation for RayTracing entries post-CA.7b). Doc fix landed in this increment (see §Cross-references).

### Signal-quality monitors (2 files, 538 LoC)

#### SilenceDetector.swift (216 LoC) — `production-active` (internal)

Hysteresis state machine for DRM tap silencing detection. `final class SilenceDetector: @unchecked Sendable` — **module-internal** (not `public`). Verified clean against ARCH §487 above.

| Internal API | Verdict | Consumer | Note |
|---|---|---|---|
| `init(silenceRMSThreshold:silenceDuration:recoveryDuration:timeProvider:)` | `production-active` | `AudioInputRouter.init` + injectable variant for tests | |
| `var state: AudioSignalState` | `production-active` | (via `AudioInputRouter.signalState`) | NSLock-protected |
| `var onStateChanged` | `production-active` | `AudioInputRouter.init` callback wiring | Invoked outside lock |
| `update(samples:count:)` | `production-active` | `AudioInputRouter.start(mode:)` inside the audio-thread callback | RMS computed; advances state machine |
| `update(rms:)` | `production-active` | Tests + Audio-thread overload | Lock-protected state-machine advance |
| `reset()` | `production-active` | `AudioInputRouter.stopInternal()` | |

**Defaults:** `silenceRMSThreshold = 1e-6`; `silenceDuration = 3.0 s`; `recoveryDuration = 0.5 s`; `suspectDuration = 1.5 s` (derived `= silenceDuration / 2`).

**No findings.** State transitions verified above. Tests at `Tests/Audio/SilenceDetectorTests.swift` cover the state machine; integration with AudioInputRouter is implicit via the callback chain.

#### InputLevelMonitor.swift (322 LoC) — `production-active`

Continuous tap-quality assessment. `public final class InputLevelMonitor: @unchecked Sendable`. Verified clean against ARCH §488 above.

| Public API | Verdict | Consumer | Note |
|---|---|---|---|
| `enum SignalQuality: String { .green, .yellow, .red, .unknown }` | `production-active` | App `QualityGradeIndicator` view + `lastLoggedQuality` | |
| `struct InputLevelSnapshot: Sendable, Equatable` | `production-active` | (via `currentSnapshot()`) | Immutable snapshot for UI/session-log consumption |
| `static let peakWarningDBFS: Float = -9` / `peakCriticalDBFS = -15` | `production-active` | (consumed internally by `recomputeSnapshotLocked`) | |
| `static let warmupFrames: Int = 60` (~0.6s at 94 Hz) | `production-active` | (internal) | |
| `init(sampleRate:)` | `production-active` | App `VisualizerEngine.swift:415` | |
| `submitSamples(pointer:count:)` | `production-active` | App `+Audio.swift:97` (audio thread) | vDSP_maxmgv + vDSP_rmsqv; lock-protected envelope update |
| `submitMagnitudes(_:sampleRate:)` | `production-active` | App `+Audio.swift:125` (analysis queue) | Spectral band-energy EMAs |
| `currentSnapshot() -> InputLevelSnapshot` | `production-active` | App + session.log | |
| `reset()` | `production-active` | (tap-restart path) | |

**Finding: no dedicated tests** (filed as CA-Audio-FU-5 above).

### Metadata fetcher cluster (5 files + 1 streaming poll, 943 + 269 = 1,212 LoC)

#### MetadataPreFetcher.swift (212 LoC) — `production-active`

Parallel-async LRU fetcher. `public final class MetadataPreFetcher: @unchecked Sendable`. Verified at the boundary above.

| Public API | Verdict | Consumer | Note |
|---|---|---|---|
| `init(fetchers:timeoutSeconds:maxCacheSize:)` (defaults 3 s + 50) | `production-active` | App `VisualizerEngine.swift:641`; Session `SessionPreparer.swift:132` | |
| `prefetch(for track:) async -> PreFetchedTrackProfile?` | `production-active` | Session `SessionPreparer.swift:299`; App `+Capture.swift:174` | parallel `withTaskGroup` |
| `cachedProfile(for track:) -> PreFetchedTrackProfile?` | `production-active` | App track-change runtime path | Synchronous; LRU-promote on hit |

**Internal:** `fetchWithTimeout(_:title:artist:timeout:)` static at `:148-170` — uses nested `withTaskGroup` race between the fetcher task and a `Task.sleep(for:.seconds(timeout))` task; first-result wins; `group.cancelAll()` on result; `result.flatMap { $0 }` flattens `Optional<Optional<_>>`. `merge(_:)` at `:176-211` is the first-non-nil-wins reducer (genre tags unioned + dedup).

**No findings at the producer side.** The pre-existing `MetadataPreFetcherTests.fetch_networkTimeout` wall-clock flake that CA-Audio noted (`KNOWN_ISSUES.md §Pre-existing Flakes`) was rewritten deterministic in CLEAN.7.9 (2026-06-13) — behavioural assertion on the merged profile (fast fetcher's `energy` present, slow fetcher's `bpm` excluded by the 1 s timeout), no elapsed-time budget; renamed `fetch_networkTimeout_returnsFastResultNotSlow`. Resolved.

#### MusicBrainzFetcher.swift (119 LoC) — `production-active`

Free MusicBrainz API search. `public final class MusicBrainzFetcher: MetadataFetching, Sendable`. Always-on in `buildFetcherList()` per CA.5.

| Public API | Verdict | Consumer | Note |
|---|---|---|---|
| `sourceName = "MusicBrainz"` | `production-active` | logging | |
| `init()` | `production-active` | `VisualizerEngine+Audio.swift:58` | |
| `fetch(title:artist:) async -> PartialTrackProfile?` | `production-active` | MetadataPreFetcher | Returns `(genreTags, duration)`; never returns BPM/key/etc. |

**User-Agent:** `"Phosphene/1.0 (https://github.com/hoaxpoet/phosphene)"` (line 26) — MusicBrainz API policy requires a descriptive User-Agent. Rate limit (1 req/sec per docs/header comment) is NOT explicitly enforced in code — relies on the per-track event frequency to stay polite. Worth noting; not a finding unless production traffic patterns surface a 429.

**No findings.**

#### SpotifyFetcher.swift (180 LoC) — `production-active`

Search-only Spotify Web API client. `public final class SpotifyFetcher: MetadataFetching, @unchecked Sendable`. Env-gated.

| Public API | Verdict | Consumer | Note |
|---|---|---|---|
| `sourceName = "Spotify"` | `production-active` | logging | |
| `init(clientID:clientSecret:)` | `production-active` | `fromEnvironment()` static | |
| `fromEnvironment() -> SpotifyFetcher?` static | `production-active` | `VisualizerEngine+Audio.swift:64` | Env vars `SPOTIFY_CLIENT_ID` + `SPOTIFY_CLIENT_SECRET` |
| `fetch(title:artist:) async -> PartialTrackProfile?` | `production-active` | MetadataPreFetcher | Returns `(duration)` only — audio features endpoint deprecated Nov 2024 |

**Internal:** Cached `accessToken` + `tokenExpiry` (with 60 s safety buffer) under `lock: NSLock` at line 31. `getAccessToken()` returns cached token if not expired; else POST to `accounts.spotify.com/api/token` with Basic auth header. `searchTrack(title:artist:token:)` calls `/v1/search` with `q=track:title artist:artist&type=track&limit=1`; decodes only `SpotifyTrack { id, duration_ms }`.

**Note:** This is **NOT** where BUG-005 fires (BUG-005 is in the Session-layer `SpotifyWebAPIConnector` /items endpoint; this fetcher uses /v1/search and never touches `preview_url`). See §Verification of metadata-fetcher BUG surfaces above for the full producer trace.

**No findings.**

#### SoundchartsFetcher.swift (193 LoC) — `production-active`

Optional commercial Soundcharts API. `public final class SoundchartsFetcher: MetadataFetching, Sendable`. Env-gated.

| Public API | Verdict | Consumer | Note |
|---|---|---|---|
| `sourceName = "Soundcharts"` | `production-active` | logging | |
| `init(appID:apiKey:)` | `production-active` | `fromEnvironment()` static | |
| `fromEnvironment() -> SoundchartsFetcher?` static | `production-active` | `VisualizerEngine+Audio.swift:60` | Env vars `SOUNDCHARTS_APP_ID` + `SOUNDCHARTS_API_KEY` |
| `fetch(title:artist:) async -> PartialTrackProfile?` | `production-active` | MetadataPreFetcher | Returns `(bpm, key, energy, valence, danceability, timeSignature)` — full audio features |

**Internal:** `searchSong(title:artist:)` → returns UUID; `fetchSongMetadata(uuid:)` → returns full features. Uses `x-app-id` + `x-api-key` headers. Special-cases HTTP 403 to log "audio features not in current plan" (line 119).

**BUG-013 producer-side handling is correct** (`time_signature` decoder is in place; field is `Int?` so null decodes silently to nil; the bug is the API not returning the field). See §Verification of metadata-fetcher BUG surfaces.

**No findings at the producer side.**

#### MusicKitBridge.swift (149 LoC) — **`production-orphan`**

Contains `public final class MusicKitFetcher: MetadataFetching, @unchecked Sendable`. **File name mismatches type name** (file is `MusicKitBridge.swift`, type is `MusicKitFetcher`) — minor inconsistency.

| Public API | Verdict | Consumer | Note |
|---|---|---|---|
| `sourceName = "MusicKit"` | `production-orphan` | (zero) | |
| `init()` | `production-orphan` | **zero production sites; zero test sites** | |
| `requestAuthorizationIfNeeded() async` | `production-orphan` | (zero) | One-time MusicAuthorization prompt |
| `fetch(title:artist:) async -> PartialTrackProfile?` | `production-orphan` | (zero) | Would return `(genreTags, duration)`; BPM is a stub |
| `fetchBPM(for: Song) async -> Double?` (private) | **`stub`** | (only `fetch` calls it; always returns nil) | MusicKit Swift SDK does not expose tempo per in-code comment :127-131 |
| `PartialTrackProfile.hasAnyData` extension | `production-orphan` | (only `MusicKitFetcher.fetch`) | |

**Cited grep (production-orphan evidence):**

```bash
$ grep -rn "MusicKitFetcher\b" PhospheneApp PhospheneEngine/Sources --include='*.swift'
PhospheneEngine/Sources/Audio/MusicKitBridge.swift:23:// MARK: - MusicKitFetcher
PhospheneEngine/Sources/Audio/MusicKitBridge.swift:30:public final class MusicKitFetcher: MetadataFetching, @unchecked Sendable {
# (only the declaration — zero callers)

$ grep -rn "MusicKitFetcher\b" PhospheneEngine/Tests PhospheneAppTests --include='*.swift'
# (no output — zero test consumers)
```

**Verdict:** `MusicKitFetcher` is fully orphan in production and tests. The fetcher is not in `VisualizerEngine+Audio.buildFetcherList()` (which composes MusicBrainz + Soundcharts/Spotify env-gated + App-side ITunesSearchFetcher). The BPM extraction is a stub (MusicKit Swift SDK genuinely does not expose tempo). Even if wired, the fetcher would only produce genre tags + duration — duplicating MusicBrainz's coverage with the added cost of a MusicKit authorization prompt.

**Filed as CA-Audio-FU-3** — recommend delete (fully orphan with no realistic re-activation path; the SDK limitation that makes the BPM fetch a stub is not under Phosphene's control). Alternative: keep with a comment marking it as "future infrastructure if MusicKit ever exposes tempo" — but the structural test (CA.7b precedent: `if "reusable infrastructure" appears in a defense of keeping deleted-concept code, the defense is wrong`) suggests delete is the cleaner call. Matt's product call.

#### StreamingMetadata.swift (269 LoC) — `production-active`

AppleScript polling of Apple Music + Spotify for Now Playing info. `public final class StreamingMetadata: MetadataProviding, @unchecked Sendable`.

| Public API | Verdict | Consumer | Note |
|---|---|---|---|
| `struct NowPlayingInfo: Sendable` | `production-active` | StreamingMetadataTests; internal | |
| `init(pollInterval: Duration = .seconds(2))` | `production-active` | `VisualizerEngine+Audio.swift:25` | |
| `var onTrackChange` (via MetadataProviding) | `production-active` | AudioInputRouter wires inside `start(mode:)` | |
| `var currentTrack: TrackMetadata?` (via MetadataProviding) | `production-active` | AudioInputRouter `currentTrack` computed | |
| `startObserving()` (via MetadataProviding) | `production-active` | AudioInputRouter `start(mode:)` + `startMetadataOnly()` | Polling Task |
| `stopObserving()` (via MetadataProviding) | `production-active` | AudioInputRouter `stopInternal()` | |

**Internal:**
- `AppleScriptBridge` enum (`queryAppleMusic()`, `querySpotify()`, `isAppRunning(_:)`, `queryNowPlaying()`, `executeScript(_:appName:source:)`). All AppleScript dispatched on `Task.detached` per `pollNowPlaying()` to keep blocking AppleScript off the cooperative pool.
- Error code special cases at `:96-103`: `-600` (app not running) + `-1728` (no current track) silently swallowed; other errors logged at `.debug`.
- `var nowPlayingReader: (@Sendable () async -> NowPlayingInfo?)?` (line 161) — test seam for injecting canned info; production path uses AppleScript.

**No findings.**

### Protocols (1 file, 272 LoC)

#### Protocols.swift (272 LoC) — `production-active`

DI surface for the Audio module + re-exports for ML/Session protocols.

| Public type | Verdict | Consumer |
|---|---|---|
| `enum AudioSignalState { .active, .suspect, .silent, .recovering }` | `production-active` | App ViewModels, Services, Views (`AudioSignalStatePublisher`); SoakTestHarness; tests |
| `protocol AudioCapturing` | `production-active` | `SystemAudioCapture` conformer; `MockAudioCapture` test double |
| `protocol AudioBuffering` | `production-active` | `AudioBuffer` conformer |
| `protocol FFTProcessing` | `production-active` | `FFTProcessor` conformer; `MIRPipeline` consumer (per CA.1) |
| `protocol StemSeparating` | `production-active` (re-export from ML) | `StemSeparator` (ML), `NullStemSeparator` (App), `StubSeparator` (tests); Session `SessionPreparer.stemSeparator` field |
| `struct StemSeparationResult` | `production-active` | (returned by `StemSeparating.separate`) |
| `enum StemSeparationError` | `production-active` | StemSeparator failure paths; NullStemSeparator default |
| `struct TrackChangeEvent` | `production-active` | StreamingMetadata producer; AudioInputRouter; App track-change callback |
| `protocol MoodClassifying` | `production-active` (re-export from ML) | `MoodClassifier` (ML) + `MockMoodClassifier` test double; Session `SessionPreparer.moodClassifier` field |
| `enum MoodClassificationError` | `production-active` | MoodClassifier failure paths |
| `protocol MetadataProviding` | `production-active` | `StreamingMetadata` conformer; `MockMetadataProvider` test double |
| `struct PartialTrackProfile` | `production-active` | All fetchers produce; MetadataPreFetcher merges |
| `protocol MetadataFetching` | `production-active` | All 4 fetchers + App `ITunesSearchFetcher` |

**Doc-comment finding:** Line 111 (`StemSeparating.separate(audio:channelCount:sampleRate:)`):

> `///   - sampleRate: Sample rate in Hz (will be resampled to 44100 if different).`

The comment references the literal `44100`. Per the `Scripts/check_sample_rate_literals.sh` CI gate, this is correctly ignored (comment lines pass the filter). The wording is also accurate (`StemSeparator.modelSampleRate = 44100` is the stem model's native rate, and the separator does resample to it — the resampling site is allowlisted in the CI gate). No drift; just noting the comment's literal reference for completeness.

**MoodClassifying feature-count doc-comment.** Line 173-176:

```swift
/// - Parameter features: Array of 10 floats:
///   `[subBass, lowBass, lowMid, midHigh, highMid, high,
///    spectralCentroid, spectralFlux,
///    majorKeyCorrelation, minorKeyCorrelation]`
```

The list shows 10 entries. The `MoodClassificationError.invalidFeatureCount(Int)` error case docstring at `:195` says "(expected 20)" — these claims appear inconsistent. **Verify against ML side.** Per CA.2's ML.md audit and per `Sources/ML/MoodClassifier.swift:14-19` input-vector docstring + line 85's `throw MoodClassificationError.invalidFeatureCount(features.count)` check, the model accepts 2 frames × 10 features = 20 floats. The Protocols.swift comment (line 173) describes the per-frame 10-feature layout; the error message correctly says 20 (the doubled count after frame stacking). This is a doc-clarity gap, not an inconsistency in code. **Recommend tightening Protocols.swift comment:** *"Array of 20 floats (2 consecutive analysis frames × 10 features per frame): for each frame, [subBass, lowBass, ..., minorKeyCorrelation]."* — would close the apparent contradiction. **Filed as low-priority CA-Audio-FU-7** (cosmetic).

---

## Cross-references

### Updates needed in CLAUDE.md

None at present. CLAUDE.md correctly cites the sample-rate plumbing rules, Failed Approaches #21 / #22 / #29 / #52, the URLProtocol @Suite(.serialized) rule, and the engine `Shared/Logging.swift` discipline (Logging.session vs app-layer Logger). The Audio module's code matches every CLAUDE.md claim at the source-file level. The only CLAUDE.md-adjacent concern is that the broader project's CLAUDE.md "What NOT To Do" list is already comprehensive — no new entries earned from this audit.

### Updates needed in ARCHITECTURE.md

Two doc-drift fixes land in this increment:

1. **§Audio Capture diagram (line 38-45)** — Remove the `→ LookaheadBuffer (2.5s analysis/render split)` arrow (line 40), OR replace with `→ LookaheadBuffer (planned; not yet wired — see CAPABILITY_REGISTRY/AUDIO.md)`. The current claim is false; the capture pipeline does not route through LookaheadBuffer in production. The audit applies the planned-but-unwired annotation (analogous to ARCH's post-CA.7b RayTracing annotations).

2. **§Module Map Audio/ block (lines 482–496)** — Add two missing files:
   - `Audio.swift` — module marker (imports + module-level comment header).
   - `AudioInputRouter+SignalState.swift` — tap-reinstall state machine extension (signal-state forwarding + scheduled-reinstall logic per ARCH §68).

3. **§Module Map Audio/ MusicKitBridge entry (line 495)** — Annotate as production-orphan (no production wiring; not in `buildFetcherList()`). Mirrors CA.7b's RayTracing entry annotation pattern.

### Updates needed in ENGINEERING_PLAN.md

Add CA-Audio row to "Recently Completed" + the appropriate increment row.

### Updates needed in DECISIONS.md

None at present. D-018 (graceful degradation on metadata-fetcher failure), D-052 (capture-mode live switch), D-070 (preview-URL primary path), D-079 (sample-rate plumbing) all match the current code. No decision needs amendment from this audit.

### Updates needed in RUNBOOK.md

None required, but worth noting: §Spotify connector setup carries the FAs #45 / #46 / #47 promoted from CLAUDE.md per DOC.3. These FAs cover the **Session-layer** `SpotifyWebAPIConnector` (the /items endpoint connector that fires for playlist preparation). The **Audio-layer** `SpotifyFetcher` (this audit's scope) uses a different code path (Client Credentials flow + /v1/search endpoint for audio-feature enrichment, env vars `SPOTIFY_CLIENT_ID` + `SPOTIFY_CLIENT_SECRET`). If RUNBOOK doesn't already distinguish the two Spotify integrations, a short note disambiguating them would help future contributors avoid the same kickoff-staleness confusion. Filed as **CA-Audio-FU-8** (RUNBOOK doc enhancement; low priority).

### Updates needed in SESSION.md (CA.3 correction)

`SESSION.md` line 145 reads: *"`MetadataPreFetcher` … and `TrackMetadata` (constructed at `:295`) live in the **Audio** module (`Sources/Audio/MetadataPreFetcher.swift`)."*

This is a CA.3 carry-forward error. `MetadataPreFetcher` does live in Audio, but `TrackMetadata`, `PreFetchedTrackProfile`, and `MetadataSource` all live in `PhospheneEngine/Sources/Shared/AudioFeatures+Metadata.swift` (lines 30, 69, 10 respectively). CA-Audio updates `SESSION.md` to remove the false co-location claim.

### New BUG entries

None. Zero `broken-but-claimed` at the code level; the one doc-level `broken-but-claimed` (ARCH §Audio Capture LookaheadBuffer arrow) is being fixed in this same increment via doc-drift correction.

### KNOWN_ISSUES.md sweep

No new entries; no status changes. The BUG-005 attribution clarification (BUG-005 producer is Session-layer, not Audio-layer) is a kickoff staleness, not a BUG content change — BUG-005's body itself correctly references `PreviewResolver` as the consumer of the null `preview_url`. No edit needed in KNOWN_ISSUES.md; the misattribution lived only in the CA-Audio kickoff prompt.

---

## Follow-up Backlog

| ID | Scope | Done-when | Est. sessions | Status |
|---|---|---|---|---|
| **CA-Audio-FU-1** | Document BUG-005 producer-domain correctly (it is **Session-layer** `SpotifyWebAPIConnector.swift:241` → `PreviewResolver.swift:73`, not the Audio-module `SpotifyFetcher`). Kickoff staleness only — the BUG body in KNOWN_ISSUES.md is already correct; only the kickoff prompt asserted the wrong domain. **Resolution:** registry-only note (this audit closes by documenting the correct attribution above). No code change. | This doc | 0 (closed at write-time) | Resolved in CA-Audio |
| **CA-Audio-FU-2** | `LookaheadBuffer` + `AudioInputRouter.onAnalysisFrame` + `.onRenderFrame` are production-orphan. **Matt's product call (2026-05-21): KEEP** as Phase MV anticipatory-architecture infrastructure. Planned consumers: (a) Orchestrator anticipatory preset transitions (switch fired 2.5 s before structural boundary so mv_warp crossfade completes ON the boundary, not after); (b) drop-anticipation visual telegraphing (windup animation triggered by build-up detection ahead of the drop); (c) beat-aligned transitions to the exact frame (BeatGrid downbeat scheduled 2.5 s ahead); (d) Phase MV / `MILKDROP_ARCHITECTURE.md` musicality requires anticipation — mv_warp parameters modulated by what's coming, not just what's arrived. Structurally analogous to CA.7-FU-3 ICB-keep + CA.7b-FU-3 RayTracing-keep precedents. ARCH §Audio Capture diagram annotation updated to reflect kept-by-design status. | Matt 2026-05-21 | 0 (registry only) | **Resolved 2026-05-21 — KEPT** |
| **CA-Audio-FU-3** | `MusicKitFetcher` is production-orphan in both production code and tests. **Matt's product call (2026-05-21): KEEP** as the Apple Music first-class metadata path. Planned consumers: (a) wire into `buildFetcherList()` for Apple Music users (gives ~half the macOS audience a higher-quality metadata path than the current MusicBrainz fallback); (b) direct-catalog-API path for tempo via `https://api.music.apple.com/v1/catalog/{storefront}/songs/{id}` (the underlying REST API exposes `tempo`; only the Swift wrapper doesn't surface it); (c) future-proof against Apple closing the SDK gap (`fetchBPM` stub becomes a one-line replacement when `Song.tempo` ships); (d) scaffolding for queue-awareness (Apple Music playlists, library, Now Playing queue) — pre-warming next preset based on next-track metadata. Structurally analogous to CA.7-FU-3 + CA.7b-FU-3 keep precedents. File/type name mismatch (`MusicKitBridge.swift` contains `MusicKitFetcher`) noted separately as cosmetic — recommend renaming the file to `MusicKitFetcher.swift` in a future cleanup. | Matt 2026-05-21 | 0 (registry only) | **Resolved 2026-05-21 — KEPT** |
| **CA-Audio-FU-4** | Add unit tests for `AudioInputRouter+SignalState.swift` tap-reinstall logic. The 105-line extension implements the critical recovery path (3 s / 10 s / 30 s backoff; three attempts; cancel-on-active) but has **zero dedicated tests**. Recommended coverage: `scheduleNextReinstall_attemptCount`, `cancelPendingReinstall_resetsAttempts`, `attemptTapReinstall_skipsIfStateChanged`, `backoffExhausted_logsOnly`, `nextActiveToSilent_resetsAttempts`. | Test file lands; CI green | 1 session | **Resolved 2026-05-21 (commit `a6404575`).** New test file `PhospheneEngine/Tests/PhospheneEngineTests/Audio/AudioInputRouterSignalStateTests.swift` lands 9 regression tests covering the 5 audit-recommended cases + 4 productivity additions: (1) `test_scheduleNextReinstall_attemptCountSequence` (audit #1) — counter advances 1→2→3 then caps; (2) `test_scheduleNextReinstall_doesNotDoubleScheduleWhilePending` (added) — guards the `reinstallWorkItem == nil` branch at line 51; (3) `test_cancelPendingReinstall_resetsAttempts` (audit #2); (4) `test_handleSignalStateChange_silentSchedulesReinstall` (added) — verifies the `.silent` entry point; (5) `test_handleSignalStateChange_activeCancelsPending` (added) — verifies the `.active` entry point; (6) `test_attemptTapReinstall_skipsIfStateNotSilent` (audit #3) — verifies the state-changed guard at line 78-83; (7) `test_backoffExhausted_noNewScheduling` (audit #4) — verifies the early-return at line 44-48; (8) `test_nextActiveToSilent_resetsAttempts` (audit #5) — full active→silent→active→silent cycle; (9) `test_reinstallDelays_matchDesignSpec` (added) — regression-locks the `[3.0, 10.0, 30.0]` tuning against silent retunes. Zero production-code changes required: the internal init `init(capture:metadata:silenceDetector:)` was already in place as a testability seam (AudioInputRouter.swift:91-101) and all reinstall-machine functions are package-internal-visibility (accessible via `@testable import Audio`). Each test runs in ~1 ms; tests that schedule a workItem clean up via `defer { router.cancelPendingReinstall() }` so background asyncAfter calls don't fire mid-next-test. Engine test count: 1248 → 1257 (+9). |
| **CA-Audio-FU-5** | Add unit tests for `InputLevelMonitor`. No `InputLevelMonitorTests.swift` exists in `Tests/Audio/`. Recommended coverage: `submitSamples_peakDecaysAt0_9995`, `submitMagnitudes_bandEnergyEMA`, `recompute_warmupReturnsUnknown`, `recompute_belowCriticalReturnsRed`, `recompute_hysteresisRequires30Frames`, `reset_clearsAllEnvelopes`. | Test file lands; CI green | 1 session | **Resolved 2026-05-21 (commit `f570688f`).** New test file `PhospheneEngine/Tests/PhospheneEngineTests/Audio/InputLevelMonitorTests.swift` lands 8 regression tests covering the 6 audit-recommended cases + 2 productivity additions: (1) `test_submitSamples_peakDecaysAt0_9995` (audit #1) — analytical `0.9995^N` peak-envelope decay verified within Float tolerance; (2) `test_submitMagnitudes_bandEnergyDominantBand` (audit #2, renamed from `bandEnergyEMA` to reflect the dominant-band-routing assertion shape) — sub/mid/treble band-energy routing via dominant-band spectra; (3) `test_recompute_warmupReturnsUnknown` (audit #3) — `.unknown` gate before `warmupFrames` (60) sample submissions accumulate; (4) `test_recompute_belowCriticalReturnsRed` (audit #4) — sustained peak below `peakCriticalDBFS` (-15) classifies `.red`; (5) `test_recompute_hysteresisRequires30Frames` (audit #5) — 29th post-spike recompute holds the old grade, 30th flips it (off-by-one defence on `gradeSwitchFrames=30`); (6) `test_reset_clearsAllEnvelopes` (audit #6) — `reset()` zeroes every envelope, the frame counter, and the published snapshot; (7) `test_classification_isPeakOnlyNotTrebleSensitive` (added) — Oxytocin defence: regression-locks peak-only classification post-2026-04-17T21-05-47Z; a treble-balance gate re-introduction would flip this test from `.green`; (8) `test_thresholdConstants_matchDesignSpec` (added) — locks `peakWarningDBFS`/-9, `peakCriticalDBFS`/-15, `warmupFrames`/60 against silent retunes (same shape as `AudioInputRouterSignalStateTests.test_reinstallDelays_matchDesignSpec`). Zero production-code changes required: `InputLevelMonitor`'s public surface (`submitSamples`, `submitMagnitudes`, `currentSnapshot`, `reset`) is directly testable and consumes raw `Float` buffers — no injectable dependency or testability seam needed. Float assertions use absolute tolerance. Engine test count: 1257 → 1265 (+8). |
| **CA-Audio-FU-6** | Retire `FFTProcessor.printHistogram(barCount:)` (line 207-242). Zero consumers; debug-only console output. Same shape as CA.7-FU-2 (depth-debug cluster) and CA.7-FU-4 (setRayMarchPresetComputeDispatch). | Lines deleted; build clean | 0.25 session | Open |
| **CA-Audio-FU-7** | Tighten `Protocols.swift:170-176` `MoodClassifying.classify(features:)` docstring to clarify the 20-float layout (2 frames × 10 features) so the doc and the `MoodClassificationError.invalidFeatureCount` "(expected 20)" message agree. | Docstring updated | 0.25 session | Open |
| **CA-Audio-FU-8** | RUNBOOK §Spotify connector setup: add a short note disambiguating the two Spotify integrations — **Session-layer Connector** (OAuth user-token flow, `/me/playlists/{id}/tracks/items` endpoint, where FAs #45-47 fire) vs. **Audio-layer Fetcher** (Client Credentials flow, `/v1/search` endpoint, for audio-feature enrichment). Avoids future kickoff-staleness confusion (this audit's CA-Audio-FU-1 was caused by exactly this conflation). | RUNBOOK updated | 0.25 session | Open |
| **CA-Audio-FU-9** | **Cross-cutting (not Audio-scoped).** ARCH §Module Map drift is now a **5-in-a-row systemic finding** (CA.5 / CA.6 / CA.7a / CA.7b / CA-Audio all surfaced module-map drift at the file-listing granularity, each adding 1–4 missing files per audit). Per-increment overhead is small; cumulative drift is large; the same problem recurs every audit. **Recommended scope:** standalone registry+doc-only increment that runs `find PhospheneEngine/Sources PhospheneApp -name '*.swift' \| sort` against every `§Module Map` block in ARCH and reconciles in one pass. Includes the Tests/ block (CA.4/CA.5 noted entire sub-blocks absent). Estimated 1 session including verification + commit. Filing here because CA-Audio is the 5th confirmation; CA.7b already raised the recommendation but no increment was filed. **Not blocking CA-Presets** — CA-Presets can land first, since it will *also* surface module-map drift in the Presets/ block; bundling that drift into the FU-9 sync pass is cleaner than fixing it piecemeal mid-audit. | Increment lands; verification of zero missing files across every block | 1 session | **Resolved 2026-05-21.** Scope expanded by CA-Shared closeout to cover §Module Map + §Key Types + §GPU Contract Details + per-source-file inline drift. Landed: (a) 5 missing Shared/ files added (StemFeatures, BeatSyncSnapshot, BUG012Probe, UserFacingError, UserFacingError+Presentation, Dashboard/DashboardTokens); (b) 16 missing Presets/ files added (Presets module marker, PresetLoader+Mesh/+Utilities/+WarpPreamble, PresetMetadata, PresetMaxDuration, PresetStage, SpectralCartographText, FidelityRubric+Mandatory/+Optional, AuroraVeil/AuroraVeilState, FerrofluidOcean cluster ×3, Arachnid extensions ×4); (c) 2 missing Diagnostics/ files added (SoakTestHarness+AudioGen, +Reporting); (d) 1 missing Renderer/ file added (RayIntersector+Internal); (e) §Key Types: deleted 3 fictional structs (BandEnergy, SpectralFeatures, OnsetPulses) that have never existed in code, moved 3 misplaced types (Particle → Renderer/Presets; SessionState → Session; AudioSignalState → Audio) into a new "Cross-module reference types" sub-block, added missing RenderPass cases (mv_warp, staged), corrected FeatureVector field documentation (no longer conflates structuralPrediction + camera uniforms into FeatureVector), corrected SpectralHistoryBuffer reserved-section description (post-beat-grid layout through [2429]), corrected EmotionalState `quadrant` as computed property, added missing types (BeatSyncSnapshot, MetadataSource, StemSampleBuffer, Smoother, UMABuffer, UMARingBuffer, UserFacingError); (f) per-source-file inline drift: AnalyzedFrame.swift:35 "96 bytes" → 192 bytes; SpectralHistoryBuffer.swift:78 reserved-section layout extended through [2429]; DashboardTokens.swift:5 "D-080" → "D-081 / DASH.1.1". App-layer ARCH block (~109 referenced entries vs 108 actual files) verified close to complete; no systemic gap. **The 7-in-a-row Module Map drift pattern is now closed.** |

---

## Approach validation

**What worked:**

- **Direct-read at 3.3k LoC scaled cleanly.** All 16 files read directly in two parallel batches (10 + 6), no Explore agents needed. The visibility-verification grep was unnecessary because every file was direct-read (no agent claims to reconcile).
- **Pass 0 BUG cross-check** caught one significant kickoff staleness (BUG-005 producer-domain attribution). The 5-minute KNOWN_ISSUES.md cross-check saved hours of investigation into a non-existent SpotifyFetcher preview-URL handling path.
- **Non-nil-caller production-orphan check (CA.7b refinement)** fired for the LookaheadBuffer callbacks — `onAnalysisFrame` and `onRenderFrame` are declared `public var` setters with zero non-nil assignments anywhere; the file-level orphan check would have missed this (AudioInputRouter itself is heavily production-active) but the field-level non-nil-caller check exposed the gap.
- **Cited grep for production-orphan claims** continues to pay off: every orphan verdict (LookaheadBuffer, MusicKitFetcher, onAnalysisFrame, onRenderFrame, printHistogram) carries the exact grep command + result count so the verdict is falsifiable in a way independent of auditor interpretation.

**What didn't:**

- **Kickoff prompt size has grown.** The CA-Audio kickoff was the longest in the series — useful for being self-contained, but the BUG-005 producer-domain misattribution slipped in because the prompt asserted a fact that wasn't grep-verified at draft time. Future kickoffs should `grep` for the named producer in the named file BEFORE asserting the producer-side scope.
- **The ARCH Module Map drift is now a 5-in-a-row systemic finding** (CA.5 / CA.6 / CA.7a / CA.7b / CA-Audio all surfaced module-map drift at the file-listing granularity). CA.7b recommended *"a future bulk pass against `find` output rather than continuing one-or-two-items-per-increment"*. CA-Audio confirms the need: 2 files missing here, same per-increment overhead. **Recommend filing a standalone module-map sync increment** that runs `find PhospheneEngine/Sources PhospheneApp -name '*.swift' | sort` against the ARCH Module Map blocks and adds every missing file in one pass. Estimate: 0.5 session.

**Carry-forward for CA-Presets (recommended next):**

- The single-pass-at-3.3k-LoC choice worked; expect CA-Presets to be similar size or larger (per-preset state classes under `Sources/Presets/` + the .metal shader files) and may need an explicit split decision at Pass 0 (preset state classes vs. shader files).
- Keep the non-nil-caller production-orphan check — it caught a real finding here (callbacks-without-assignment).
- Keep the Pass 0 BUG cross-check — it caught a real staleness here.
- The "production-orphan + planned-consumer" annotation pattern (CA.7b RayTracing precedent + CA-Audio LookaheadBuffer follow-up) is now well-established; CA-Presets will likely have similar findings (presets retired but JSON/.metal files preserved in git or temporarily left in place pending removal).
