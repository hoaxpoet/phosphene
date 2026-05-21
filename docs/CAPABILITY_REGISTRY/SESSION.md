# Capability Registry — Session

**Audit increment:** CA.3
**Date:** 2026-05-20
**Auditor:** Claude (session-driven, read-only)
**Scope:** `PhospheneEngine/Sources/Session/` — 22 Swift files, ~3,425 LoC (20 in the top-level directory + 2 in `Connectors/`). Boundary annotations for Session↔DSP, Session↔ML, Session↔Audio, Session↔Orchestrator, Session↔App.
**Methodology:** [`docs/prompts/PHASE_CA_KICKOFF_CA3_SESSION_2026-05-20.md`](../prompts/PHASE_CA_KICKOFF_CA3_SESSION_2026-05-20.md).
**Reads relied on:** `CLAUDE.md`, `docs/ARCHITECTURE.md`, `docs/CAPABILITY_REGISTRY/DSP_MIR.md` (CA.1), `docs/CAPABILITY_REGISTRY/ML.md` (CA.2), `docs/DECISIONS.md` (D-008, D-017, D-018, D-019, D-046, D-052, D-056, D-061, D-068, D-069, D-070, D-091), `docs/QUALITY/KNOWN_ISSUES.md` (BUG-005, BUG-006, BUG-007.8, BUG-007.9, BUG-008, BUG-R002–R006), `docs/ENGINEERING_PLAN.md`.

---

## Summary

22 file-level entities audited (~3.4k LoC). The Session subsystem is **substantially production-active and largely doc-aligned**. Zero `broken-but-claimed`; zero new BUG entries filed. The most notable findings are doc-drift at the architecture-narrative level (the `§Session Preparation` step list has not kept up with D-070 / BUG-007.8 / Round 26 metadata-meter override) and one genuine `stub` (`LocalFolderConnector` is `#if`-gated behind a flag that is never set).

| Verdict | Count | Notes |
|---|---|---|
| `production-active` | 21 files | Default verdict. Every other Session source file has at least one production consumer and the documented behaviour matches the code. |
| `stub` | 1 file | `LocalFolderConnector.swift` — `public final class LocalFolderConnector` whose entire body is gated behind `#if ENABLE_LOCAL_FOLDER_CONNECTOR`. Grep confirms the flag is referenced only in the file's own gate and in a `ConnectorPickerViewModel.swift` comment (`localFolderEnabled is false in v1; ENABLE_LOCAL_FOLDER_CONNECTOR compile flag gates it`); it is **not** set in `Package.swift`, `Phosphene.xcconfig`, or any Swift build setting. The class never compiles in production builds. The file is intentional scaffold per D-046 / UX_SPEC §4.4, not dead code — but the audit verdict for a `#if`-gated stub with no enabled site is `stub`. |
| `broken-but-claimed` | 0 | No new BUG entries. BUG-006 (cited in the CA.3 kickoff as Open / P1) is in fact **already `Resolved` per `docs/QUALITY/KNOWN_ISSUES.md`** (BUG-006.2 wiring fix, 2026-05-06); the kickoff prompt's "Active BUGs in scope" list was stale. BUG-005 is Open / P3 / `session.ux` only — UX-copy improvement work, not a Session-module correctness defect. |
| `documented-but-missing` | 2 | (a) `ARCHITECTURE.md §Session Preparation` lines 112–124 describes a 7-step pipeline that omits four pieces of work that have landed since: D-070 preview-URL primary path (Spotify `preview_url` inline, iTunes Search fallback — Failed Approach #47); the Beat This! offline beat-grid pass (D-077 via `BeatGridAnalyzer`); the DSP.4 drums-stem beat grid; BUG-007.8 `GridOnsetCalibrator` per-track offset calibration; Round 26 (2026-05-15) metadata-driven `BeatGrid.overridingBeatsPerBar` override via `MetadataPreFetcher`. (b) `ARCHITECTURE.md §Module Map Tests/Session/` block references `StemCacheTests` as a separate test file; no such file exists on disk (`StemCache` is exercised inside `SessionPreparerTests` and the `PreparedBeatGrid*WiringTests` integration suite). |
| `built-but-undocumented` | 2 | (a) `ARCHITECTURE.md §Session/` module-map block at lines 544–554 lists 9 of 22 source files — 13 are missing (full list under `§Cross-references` below). Same shape as CA.1's DSP/ 6-of-20 drift and CA.2's ML/ 9-of-16 drift. (b) `ARCHITECTURE.md §Module Map Tests/Session/` block at line 580 lists 9 of 14 actual test files (6 missing + 1 phantom — see `documented-but-missing`). |
| `unverified-claim` | 0 | — |
| `boundary-noted` | 4 | Session ↔ App boundaries: `SessionManager` is `@MainActor ObservableObject` observed by `PhospheneApp/ViewModels/SessionStateViewModel`, `PlaybackChromeViewModel`, `PreparationProgressViewModel`, `EndSessionConfirmViewModel`, `ReadyViewModel`; six concrete views switch on `SessionState`. `SpotifyOAuthTokenProvider` (in `PhospheneApp/Services/`) conforms to the Session-module `SpotifyTokenProviding` protocol per D-069 Decision 2 — boundary-noted, not boundary-deferred (no future re-audit will change the placement). |
| `boundary-deferred` | 0 (new) | The three CA.1/CA.2 carry-forward items resolve in §Resolution-of-CA.1/CA.2-boundary-deferred-items below — final verdicts assigned, no new deferrals filed. |
| `dead` | 0 | — |

**The highest-priority non-`production-active` finding** is the `ARCHITECTURE.md §Session Preparation` step-list drift. The pipeline described in lines 112–124 is the U.10-era pipeline; four named pieces of work that have shipped since (D-070, BeatGridAnalyzer / Beat This! offline grid, DSP.4 drums-grid, BUG-007.8 grid-onset calibration, Round 26 meter-override) are not reflected. Any reader who builds a mental model of session preparation from `ARCHITECTURE.md` alone will be missing the load-bearing 2026-04 / 2026-05 work. Doc-drift correction applied in this increment.

**Three follow-up items are tracked in [§Follow-up Backlog](#follow-up-backlog) below** (`CA.3-FU-1` through `CA.3-FU-3`). Per the kickoff's audit-only discipline, none ship as part of this audit increment.

**Doc-drift findings of note:**
1. **`§Session Preparation` step list out of date** — see §Cross-references for the new ordered list reflecting current code (`SessionPreparer+Analysis.swift:66-165`).
2. **`§Session/` module-map block missing 13 files** — same systemic class as CA.1/CA.2 found.
3. **`§Tests/Session/` block missing 6 real files + 1 phantom file** — corrected.
4. **`§Session Recording (Diagnostics)` doesn't mention the `WIRING:` log surface** that landed for BUG-006.1 + DSP.4 (3-way BPM disagreement) and now lives permanently in `SessionPreparer+WiringLogs.swift`. Light note added.

---

## Findings by verdict

### broken-but-claimed (BUG entries filed)

**None filed.** Every public capability that docs claim to work was verified against either tests, code-level evidence, or recent session-log narrative.

**BUG-006 kickoff-prompt staleness.** The CA.3 kickoff prompt's "Active BUGs in scope" list cites BUG-006 (Spotify-prepared session doesn't install prepared BeatGrid) as Open / P1. The actual `KNOWN_ISSUES.md` entry at line 1053 shows `Status: Resolved (wiring — downstream BUG-007 / BUG-008 prevent full LOCKED but the prepared-grid path itself is wired correctly end-to-end)` resolved 2026-05-06 via BUG-006.2 commits `982bf93d` + `d56acd89` and validated end-to-end by session capture `2026-05-06T20-11-46Z`. The audit confirms the cited resolution: (a) `VisualizerEngine.swift:614` wires `engine.stemCache = sessionManager.cache`; (b) `VisualizerEngine+Capture.swift:131` resolves the canonical `TrackIdentity` from `livePlan` via `PlannedSession.canonicalIdentity(matchingTitle:artist:)`; (c) `PreparedBeatGridAppLayerWiringTests` (6 cases) regression-locks the fix. No further audit-side action.

**BUG-005 in-scope but no audit-side action.** Open / P3 / `session.ux`. Documented at `KNOWN_ISSUES.md:601` as an external-API limitation (Spotify `preview_url` returns null for rights-restricted tracks; iTunes Search fallback also misses some of them). Fix scope is UX copy only ("No preview available" status string); no Session-module code path is wrong. The audit verified `PreviewResolver.resolvePreviewURL(for:)` at lines 65–109 correctly returns `nil` (via the `parsePreviewURL` fall-through) when both paths fail, and that the caller (`SessionPreparer.prepareTrack` at line 278) throws `SessionPreparationError.noPreviewURL(track.title)` which maps to `TrackPreparationStatus.failed(reason: "Preview not available")`. The "Preview not available" string is the user-facing copy at `SessionPreparer.swift:242`. Not a Session-module defect.

### documented-but-missing

1. **`ARCHITECTURE.md §Session Preparation` (lines 112–124) — out-of-date step list.** The current 7-step list says:
   ```
   2. Resolve preview clip URLs via iTunes Search API (PreviewResolver).
   …
   5. Run MIR pipeline (BPM, key, mood, spectral features, structural analysis).
   ```
   But the production pipeline (`SessionPreparer+Analysis.swift:66-165`, `SessionPreparer.swift:275-329`) now runs:
   - Preview URL resolution: **primary source `TrackIdentity.spotifyPreviewURL`** (inline from Spotify `/items` per D-070, Failed Approach #47), iTunes Search API only on fallback (`PreviewResolver.swift:65-109`).
   - **Metadata pre-fetch in parallel with the PCM download** (Round 26, 2026-05-15, `SessionPreparer.swift:292-300`) via the optional `MetadataPreFetcher`.
   - Step 5 expanded to: stem separation → analyzer warmup → MIR (BPM/key/mood/centroid/section count) → **Beat This! offline beat grid on full mix** (`SessionPreparer+Analysis.swift:116-123`) → **metadata-driven `beatsPerBar` override** (`:133-139`) → **Beat This! offline beat grid on drums stem** (DSP.4 diagnostic, `:144-152`) → **BUG-007.8 `GridOnsetCalibrator.calibrate(...)` per-track median offset** (`:155, 176-184`) → caching to `StemCache`.

   Doc-drift correction applied in this increment.

2. **`ARCHITECTURE.md §Module Map Tests/Session/` (line 580) — references nonexistent `StemCacheTests`.** The line reads: *"SessionManagerTests, PlaylistConnectorTests, PreviewResolverTests, PreviewDownloaderTests, SessionPreparerTests, **StemCacheTests**, …"*. `find PhospheneEngine/Tests -name "StemCacheTests*"` returns no results. `StemCache`'s behaviour is exercised inside `SessionPreparerTests` (which constructs and asserts on `cache.store` / `cache.loadForPlayback`) and `PreparedBeatGridWiringTests` / `PreparedBeatGridAppLayerWiringTests` (which assert cache-store / cache-load wiring across the engine boundary). The phantom file reference is removed in this increment.

### unverified-claim

None this increment.

### production-orphan

**Production-orphan claims at the file level: zero.** Every file in `Sources/Session/` has at least one production consumer (App or in-Session-module). Per the CA.2+ rule, all candidate production-orphan claims would carry their grep commands. None did.

**Production-orphan claims at the field / type / method level: zero.** Notable visibility cross-checks I performed against the file-level reads (per the CA.3 visibility-verification rule):

- `MissingCredentialsTokenProvider` (`SpotifyTokenProvider.swift:185`) — **`internal`**, not public. Consumers: `SpotifyWebAPIConnector.makeLive(urlSession:)` fallback (`:77`) + 1 test (`SpotifyTokenProviderTests.swift:193` via `@testable import Session`). Visibility is correctly scoped.
- `SessionPreparer.sessionRecorder` (`SessionPreparer.swift:93`) — **`internal`**, not public. The comment at `:92` says verbatim: `Visibility is internal so SessionPreparer+WiringLogs.swift can access it.` Single internal-cross-file consumer (the extension). Verified.
- `SessionPreparationError` (`SessionPreparer.swift:48`) — **`internal`**, not public. Thrown inside `prepareTrack`, caught inside `_runPreparation`. No external consumers.
- `PlaylistConnector.appleScriptReader` (`PlaylistConnector.swift:105`) — **`internal var`** (no explicit access modifier; the `var` is at type level, default is internal). Testing seam used by `PlaylistConnectorTests`. Production code never assigns it.
- `SpotifyWebAPIConnector.networkFetcher` (`SpotifyWebAPIConnector.swift:48`) — **`internal var`**. Testing seam used by `SpotifyWebAPIConnectorTests` + `SpotifyItemsSchemaTests`. Production code never assigns it.

No field-level orphans in the CA.1 / CA.2 sense. The internal-only testability seams (`appleScriptReader`, `networkFetcher`, internal error types) are correctly scoped and correctly consumed.

### dead

None. Every public, internal, or fileprivate symbol in `Sources/Session/` has at least one live caller.

### stub

1. **`LocalFolderConnector` (`LocalFolderConnector.swift:16`) — `stub`.** Entire class body is gated behind `#if ENABLE_LOCAL_FOLDER_CONNECTOR`. The flag is referenced in exactly two places:
   - `LocalFolderConnector.swift:9` — the gate itself.
   - `PhospheneApp/ViewModels/ConnectorPickerViewModel.swift:8` — a code comment: *"localFolderEnabled is false in v1; ENABLE_LOCAL_FOLDER_CONNECTOR compile flag gates it."*

   `grep -rn "ENABLE_LOCAL_FOLDER_CONNECTOR" Package.swift PhospheneApp/Phosphene.xcconfig PhospheneEngine` returns no other hits. The flag is not set in `swiftSettings`, `cSettings`, or any `*.xcconfig`. The class is therefore never compiled into either the test target or the production app target.

   The file is intentional scaffold per D-046 (connector picker architecture) and UX_SPEC §4.4 (Local Folder as a v2 surface). The header comment says verbatim: *"Gated by ENABLE_LOCAL_FOLDER_CONNECTOR compile flag; not enabled in v1. Actual folder reading is out of scope until post-v1."* The body throws `PlaylistConnectorError.networkFailure("Local folder connector not yet implemented.")` — itself a sentinel rather than a real implementation.

   Verdict: `stub` is the correct CA-taxonomy label for a `#if`-gated public type whose body is a sentinel. Not `dead` (the file is intentional scaffold; deletion would lose the v2 commitment), not `production-orphan` (intent is correct — production builds genuinely don't compile it). See `CA.3-FU-2` for the decision question.

### built-but-undocumented

1. **`ARCHITECTURE.md §Module Map Session/` block (lines 544–554) lists 9 of 22 files; 13 are absent.** Same systemic class as CA.1 (DSP/ 6-of-20) and CA.2 (ML/ 9-of-16).

   **Currently listed (9):** `SessionManager`, `PlaylistConnector`, `TrackIdentity`, `SessionTypes`, `PreviewResolver`, `PreviewDownloader`, `SessionPreparer`, `StemCache`, `TrackProfile`.

   **Missing (13):**
   - `Session.swift` (5-line module marker).
   - `SessionManager+Readiness.swift` — `computeReadiness(statuses:trackList:cache:)` static computation extracted from `SessionManager` to stay under the 400-line SwiftLint gate after the BUG-006.1 `WIRING:` instrumentation landed.
   - `SessionPreparer+Analysis.swift` — `analyzePreview(_:separator:analyzer:classifier:beatGridAnalyzer:prefetchedProfile:)` static composition pipeline; runs inside `Task.detached` from `prepareTrack`. The audit's load-bearing read; composes DSP + ML + Audio module dependencies.
   - `SessionPreparer+WiringLogs.swift` — BUG-006.1 `WIRING:` instrumentation and DSP.4 3-way BPM disagreement warning emission.
   - `PreparationProgressPublishing.swift` — `@MainActor public protocol PreparationProgressPublishing: AnyObject` consumed by `PreparationProgressViewModel`.
   - `TrackPreparationStatus.swift` — `AnalysisStage` + `TrackPreparationStatus` enums (7-status canonical state machine for per-track preparation).
   - `BeatGridAnalyzer.swift` — `BeatGridAnalyzing` protocol + `DefaultBeatGridAnalyzer` (composes DSP's `BeatThisPreprocessor` + ML's `BeatThisModel` + DSP's `BeatGridResolver` into a single injectable step). CA.1 boundary-deferred to here; verdict assigned in §Resolution-of-CA.1/CA.2-boundary-deferred-items below.
   - `GridOnsetCalibrator.swift` — BUG-007.8 per-track grid-vs-onset offset calibrator. CA.1 boundary-deferred to here; verdict assigned below.
   - `BPMMismatchCheck.swift` — `detectBPMMismatch(...)` 2-way (BUG-008.2) + `detectThreeWayBPMDisagreement(...)` 3-way (DSP.4) diagnostic functions; consumed only by `SessionPreparer+WiringLogs`.
   - `LocalFolderConnector.swift` — `#if`-gated stub (above).
   - `Connectors/SpotifyTokenProvider.swift` — `SpotifyTokenProviding` protocol + `DefaultSpotifyTokenProvider` actor (client-credentials, D-068) + `MissingCredentialsTokenProvider` internal fallback.
   - `Connectors/SpotifyWebAPIConnector.swift` — `SpotifyWebAPIConnecting` protocol + `SpotifyWebAPIConnector` implementation (D-070 `/items` schema, `preview_url` capture, OAuth + 401-retry mapping).

   Doc-drift correction applied in this increment — Session/ block extended to cover all 22 files with one-line behavioural descriptions.

2. **`ARCHITECTURE.md §Module Map Tests/Session/` block (line 580) — 6 real files missing, 1 phantom listed.**

   **Listed (9 — but 1 is wrong):** SessionManagerTests, PlaylistConnectorTests, PreviewResolverTests, PreviewDownloaderTests, SessionPreparerTests, ~~StemCacheTests~~ (phantom — see `documented-but-missing` finding 2), SpotifyWebAPIConnectorTests, SpotifyTokenProviderTests, SpotifyItemsSchemaTests.

   **Missing (6 real files):** BPMMismatchCheckTests, GridOnsetCalibratorTests, ProgressiveReadinessTests, SessionManagerCancelTests, SessionPreparerProgressTests, TrackPreparationStatusTests.

   Doc-drift correction applied in this increment.

3. **`ARCHITECTURE.md §Session Recording (Diagnostics)` doesn't reference the `WIRING:` log channel.** BUG-006.1 introduced a permanent `WIRING:` line family that flows from `SessionManager.startSession(preFetchedTracks:source:)`, `SessionManager._beginPreparation`, `SessionManager.startNow()`, `SessionPreparer.prepare(tracks:)`, `SessionPreparer+WiringLogs.logWiringDoneSummary` / `logDrumsBeatGridLine` / `logBPMMismatchIfAny`, into the session-log file. The current `§Session Recording` block describes `features.csv` + `stems.csv` + per-stem WAVs + `session.log` but doesn't surface that the `WIRING:` lines are *the* diagnostic trail for prepared-cache wiring, drums-stem beat-grid emission, and 2-way / 3-way BPM disagreement. Removal of the `WIRING:` family is tracked under QR.5 (post-BUG-006 cleanup); until then the lines are load-bearing for any session-prep regression diagnosis. Light note added in this increment.

### boundary-noted

The audit produced no new `boundary-deferred` findings. The following Session-module boundary surfaces are noted (verdict complete; no future re-audit required):

- **Session ↔ App (engine ↔ `PhospheneApp/`).** `SessionManager` is `@MainActor ObservableObject`; consumed by `PhospheneApp/ViewModels/SessionStateViewModel.swift:39` (state mirroring), `PhospheneApp/ViewModels/PlaybackChromeViewModel.swift:114` (progressive readiness subscription), `PhospheneApp/ViewModels/PreparationProgressViewModel.swift:81` (publisher subscription), `PhospheneApp/ViewModels/EndSessionConfirmViewModel.swift:22` + `PhospheneApp/ViewModels/ReadyViewModel.swift:66` + 6 view files (`IdleView`, `ConnectingView`, `PreparationProgressView`, `ReadyView`, `PlaybackView`, `EndedView`). `PhospheneApp/Services/NetworkRecoveryCoordinator.swift:104` subscribes to `sessionStatePublisher` and calls `SessionManager.resumeFailedNetworkTracks()` per D-061(d) when reachability transitions `false → true`. The QR.4 / D-091 `currentTrackIndex` chain is on `VisualizerEngine`, not `SessionManager` (`PhospheneApp/VisualizerEngine.swift:77` `@Published var currentTrackIndex: Int?`); the App-layer view-models bind to `VisualizerEngine.currentTrackIndex` and `SessionManager.state` independently per `D-091`'s "two-publisher" contract.

- **Session ↔ Orchestrator (`Sources/Orchestrator/`).** `TrackProfile` is consumed by `DefaultPresetScorer` (via `PresetScoringContext`) at preparation time and at runtime via `VisualizerEngine+Orchestrator.swift:83` / `:326` / `:449`. `SessionPlan` is a deliberately-minimal stub per D-017; the Orchestrator's `PlannedSession` / `PlannedTrack` / `PlannedTransition` are richer types built on top (D-034). `Session` module **cannot** import `Orchestrator` (circular dependency per `ARCHITECTURE.md:209`); the wiring happens in the App layer.

- **Session ↔ DSP (`Sources/DSP/`).** Session imports DSP at `SessionPreparer.swift:16` (for `BeatGrid` / `BeatGridResolver` indirectly), `SessionPreparer+Analysis.swift:7` (for `MIRPipeline`), `GridOnsetCalibrator.swift:25` (for `BeatDetector` + `BeatGrid`), `BeatGridAnalyzer.swift:9` (for `BeatThisPreprocessor` + `BeatGridResolver`), and `StemCache.swift:6` (for the `BeatGrid` type on `CachedTrackData`). All consumptions match CA.1's DSP-side findings.

- **Session ↔ ML (`Sources/ML/`).** Session imports ML at `SessionPreparer.swift:19` (for `StemSeparating` indirectly via Audio's protocol; the production `StemSeparator` concrete is ML), `BeatGridAnalyzer.swift:10` (for `BeatThisModel`). The `MoodClassifier.currentState` end-of-prep read (`SessionPreparer+Analysis.swift:295`) is the carry-forward item from CA.2; resolved below.

- **Session ↔ Audio (`Sources/Audio/`).** Session imports Audio at `SessionPreparer.swift:15` and `SessionPreparer+Analysis.swift:6` for the protocols (`StemSeparating`, `StemAnalyzing`, `MoodClassifying`) and the `PreviewAudio` value type… wait, `PreviewAudio` is declared in `Session/SessionTypes.swift:88`, not Audio. **Correction:** the only Audio-module consumption from Session is the protocol seams (`StemSeparating` etc. are declared in `Audio/Protocols.swift` per CA.2's note at `ML.md §Cross-references`); `PreviewAudio` is Session-owned. `MetadataPreFetcher` (used at `SessionPreparer.swift:86, 132` and called at `:299`) and `TrackMetadata` (constructed at `:295`) live in the **Audio** module (`Sources/Audio/MetadataPreFetcher.swift`). Boundary-noted: Session consumes `MetadataPreFetcher` as an injected dependency; Audio is the producer.

### production-active

(See per-file index below. Counts only here, no per-finding detail unless a noteworthy nuance applies.)

- **Lifecycle + state machine (6 files):** `SessionManager` (`@MainActor ObservableObject`, D-018 / D-056), `SessionManager+Readiness`, `SessionTypes` (SessionState / ProgressiveReadinessLevel / SessionPlan / PreviewAudio), `TrackPreparationStatus` (AnalysisStage + 7-status state machine), `PreparationProgressPublishing` (protocol seam), `Session.swift` (module marker).
- **Preparation pipeline (6 files):** `SessionPreparer` (orchestrator, @MainActor), `SessionPreparer+Analysis` (static `analyzePreview` composition), `SessionPreparer+WiringLogs` (BUG-006.1 + DSP.4 diagnostic emission), `PreviewResolver` (D-070 Spotify-first / iTunes fallback), `PreviewDownloader` (AAC/MP3 → mono Float32 PCM via `AVAudioFile`), `StemCache` (NSLock-guarded per-track cache).
- **Track / Playlist value types (3 files):** `TrackIdentity` (cache key with the `spotifyPreviewURL` hint excluded from Equatable/Hashable/Codable per D-070), `TrackProfile`, `PlaylistConnector` (Apple Music AppleScript + Spotify routing).
- **Boundary-resolved-from-CA.1 (2 files):** `BeatGridAnalyzer` (`BeatGridAnalyzing` protocol + `DefaultBeatGridAnalyzer` composing DSP + ML), `GridOnsetCalibrator` (BUG-007.8 per-track offset calibration). See §Resolution-of-CA.1/CA.2-boundary-deferred-items below.
- **Quality gates (1 file):** `BPMMismatchCheck` (`detectBPMMismatch` 2-way BUG-008.2 + `detectThreeWayBPMDisagreement` 3-way DSP.4).
- **Connectors subdirectory (2 files):** `Connectors/SpotifyTokenProvider` (D-068 client-credentials + `MissingCredentialsTokenProvider` fallback), `Connectors/SpotifyWebAPIConnector` (D-070 `/items` schema + `preview_url` capture + 401-retry + 403→`spotifyLoginRequired` mapping).

---

## Per-file capability index

Citations use `path:line` format. Inventory data from per-file direct reads (Explore agents not used — file sizes were tractable for direct reading); consumer counts from `grep -rn` of canonical type names across `PhospheneApp/`, `PhospheneEngine/Sources/`, and `PhospheneEngine/Tests/`. Visibility cross-checked against the file's text per the CA.3 visibility-verification rule.

Consolidation: 21 of 22 files concentrate on `production-active`; the per-file index below mirrors CA.1/CA.2's consolidated form. Non-`production-active` files (LocalFolderConnector) are visually marked. Boundary-resolved files (BeatGridAnalyzer, GridOnsetCalibrator) get their final verdicts here plus a cross-link to §Resolution.

### `Session.swift` (5 lines) — `production-active`

Module entry-point marker. `@_exported import Shared` so any `import Session` consumer automatically gets the Shared types. No public surface beyond the import re-export. Consumed implicitly by every `import Session` site (16+ in `PhospheneApp/` + tests).

### `SessionTypes.swift` (124 lines) — `production-active`

Four shared value types for the session preparation pipeline.

| Capability | Verdict | Consumers (prod / test) | Doc-cited |
|---|---|---|---|
| `SessionState` enum (`.idle / .connecting / .preparing / .ready / .playing / .ended`) | `production-active` | 6 view files (one per state) + `SessionStateViewModel.swift:30` + `NetworkRecoveryCoordinator.swift:49,104` + 4 test files | `ARCHITECTURE.md §Session Lifecycle`, `§UX Contract`; D-017 |
| `ProgressiveReadinessLevel` enum (`.preparing / .readyForFirstTracks / .partiallyPlanned / .fullyPrepared / .reactiveFallback`, `Comparable`) | `production-active` | `SessionManager.swift:48`, `PlaybackChromeViewModel.swift:125`, `PreparationProgressViewModel.swift:89`, `PreparationProgressView.swift:61`, `PlaybackView.swift:78`, `ProgressiveReadinessTests` | D-056 |
| `defaultProgressiveReadinessThreshold: Int = 3` (top-level public let) | `production-active` | `SessionManager+Readiness.swift:28`; tests reference via `@testable import Session` | D-056 |
| `SessionPlan` struct (holds `[TrackIdentity]`) | `production-active` | `SessionManager.swift:52,155,199,234` + tests | D-017 |
| `PreviewAudio` struct (`trackIdentity / pcmSamples / sampleRate / duration`) | `production-active` | `SessionPreparer.swift:301` + `SessionPreparer+Analysis.swift:67` + 5 test files | `ARCHITECTURE.md §Session Preparation` |

### `SessionManager.swift` (354 lines) — `production-active`

[`SessionManager.swift:37`](../../PhospheneEngine/Sources/Session/SessionManager.swift) — `@MainActor public final class SessionManager: ObservableObject`. Owns the lifecycle state machine, coordinates `PlaylistConnector` / `SessionPreparer` / `StemCache`. Two `startSession` variants (one for connector-driven, one for App-pre-fetched tracks per D-070 Bug 2). Background preparation `Task` so `startSession` returns immediately; `startNow()` advances `.preparing → .ready` when `progressiveReadinessLevel >= .readyForFirstTracks`.

| Capability | Verdict | Consumers | Notes |
|---|---|---|---|
| `SessionManager` class | `production-active` | App-layer (VisualizerEngine, 5 VMs, 6 views) + 4 test files | `ARCHITECTURE.md §Session Lifecycle`; D-018 degradation contract |
| `state: SessionState` (`@Published`) | `production-active` | ContentView routing + NetworkRecoveryCoordinator | D-018 |
| `progressiveReadinessLevel: ProgressiveReadinessLevel` (`@Published`) | `production-active` | PreparationProgressViewModel CTA gate + PlaybackChromeViewModel background indicator | D-056 |
| `currentPlan: SessionPlan?` (`@Published`) | `production-active` | App-layer (orchestrator wiring) | — |
| `sessionSource: PlaylistSource?` (`@Published`) | `production-active` | `EndedView` + telemetry | — |
| `preparingTracks: [TrackIdentity]` (`@Published`) | `production-active` | `PreparationProgressView` track-list | — |
| `cache: StemCache` (computed) | `production-active` | App-layer engine wiring (BUG-006.2 / D-091 fix); tests | `KNOWN_ISSUES.md §BUG-006` |
| `preparationProgress: (any PreparationProgressPublishing)?` | `production-active` | `PreparationProgressViewModel` | — |
| `init(connector:preparer:sessionRecorder:)` | `production-active` | `VisualizerEngine+InitHelpers.makeSessionManager` | — |
| `startSession(source:) async` | `production-active` | `IdleView` (Apple Music path) | D-018 degradation |
| `startSession(preFetchedTracks:source:) async` | `production-active` | `IdleView` (Spotify OAuth path) | D-070 Bug 2 |
| `startAdHocSession()` | `production-active` | `IdleView` "Start listening now" | D-046 |
| `startNow()` | `production-active` | `PreparationProgressView` CTA | D-056 |
| `beginPlayback()` | `production-active` | `PlaybackView` autodetect path (Increment U.5) | — |
| `cancel()` | `production-active` | `PreparationProgressView` cancel + `ContentView` | `SessionManagerCancelTests` |
| `endSession()` | `production-active` | `EndSessionConfirmViewModel.confirm()` | — |
| `resumeFailedNetworkTracks() async` | `production-active` | `NetworkRecoveryCoordinator` | D-061(d) |
| BUG-006.1 `WIRING:` instrumentation calls | `production-active` | Diagnostic trail in `session.log` | Tracked for QR.5 cleanup |

### `SessionManager+Readiness.swift` (82 lines) — `production-active`

[`SessionManager+Readiness.swift:21`](../../PhospheneEngine/Sources/Session/SessionManager+Readiness.swift) — `static func computeReadiness(statuses:trackList:cache:) -> ProgressiveReadinessLevel`. Pure function (zero side effects); extracted from `SessionManager.swift` to stay under the 400-line SwiftLint gate after BUG-006.1 instrumentation expanded the main file. D-056 `.partial` threshold rule (BPM + ≥1 genre tag) implemented at lines 60–65. Consumed at two sites in `SessionManager.swift` (line 209 subscription, line 237 final-bookkeeping recompute). Tested by `ProgressiveReadinessTests` (10 cases).

### `PreparationProgressPublishing.swift` (35 lines) — `production-active`

[`PreparationProgressPublishing.swift:16`](../../PhospheneEngine/Sources/Session/PreparationProgressPublishing.swift) — `@MainActor public protocol PreparationProgressPublishing: AnyObject`. Three requirements: `trackStatuses: [TrackIdentity: TrackPreparationStatus]` (read-only), `trackStatusesPublisher: AnyPublisher<…, Never>` (Combine subscription), `cancelPreparation()` (no-op-safe). Production conformer: `SessionPreparer` (`SessionPreparer.swift:380` `extension SessionPreparer: PreparationProgressPublishing {}`). Test conformer: `FakePreparationProgressPublisher.swift:15`. Consumer: `PreparationProgressViewModel.swift:67 publisher: any PreparationProgressPublishing` and `PreparationProgressView.swift:58`.

### `TrackPreparationStatus.swift` (75 lines) — `production-active`

Two enums.

| Capability | Verdict | Consumers | Notes |
|---|---|---|---|
| `AnalysisStage` enum (`.stemSeparation / .mir / .beatGrid / .caching`) | `production-active` | `SessionPreparer.swift:309, 231` (transitions); `PreparationProgressViewModel.swift:193` (stage display) | Note: per `SessionPreparer.swift:307-308` comment, `.mir` and `.beatGrid` sub-stages are NOT emitted as separate transitions — both run inside `Task.detached` alongside stem separation. Documented limitation; `PreparationProgressView` therefore shows `.stemSeparation` for the entire duration of analysis. |
| `TrackPreparationStatus` enum (`.queued / .resolving / .downloading(progress:) / .analyzing(stage:) / .ready / .partial(reason:) / .failed(reason:)`) | `production-active` | SessionPreparer transitions; `PreparationProgressViewModel`; `PreparationErrorViewModel`; `TrackPreparationStatusIcon` view; `PreparationETAEstimator` | D-018, D-056 |
| `isTerminal` / `isInFlight` derived properties | `production-active` | `PreparationProgressViewModel` filtering | — |

### `SessionPreparer.swift` (383 lines) — `production-active`

[`SessionPreparer.swift:63`](../../PhospheneEngine/Sources/Session/SessionPreparer.swift) — `@MainActor public final class SessionPreparer: ObservableObject`. Sequential per-track preparation (the `StemSeparator` is single-instance and never called concurrently). Stored `Task` so `cancelPreparation()` interrupts at stage boundaries. Two `@Published` state surfaces: `progress: (completed, total)` (legacy scalar) and `trackStatuses: [TrackIdentity: TrackPreparationStatus]` (per-track, U.4 product of `D-056`).

| Capability | Verdict | Consumers | Notes |
|---|---|---|---|
| `SessionPreparer` class | `production-active` | `VisualizerEngine+InitHelpers.swift:115`; 6 test files (SessionPreparerTests, SessionPreparerProgressTests, ProgressiveReadinessTests, SessionManagerCancelTests, SessionManagerTests, BeatGridIntegrationTests) | `ARCHITECTURE.md §Session Preparation`; D-008 |
| `SessionPreparationResult` struct | `production-active` | `SessionPreparer.prepare(tracks:)` return + `SessionManager._beginPreparation` consumer | — |
| `SessionPreparationError` enum | `production-active` (internal) | Thrown inside `prepareTrack`, caught inside `_runPreparation` | `internal` visibility — no external consumers, correctly scoped. |
| `progress` / `trackStatuses` (`@Published`) | `production-active` | App-layer VMs + tests | — |
| `cache: StemCache` | `production-active` | Forwarded via `SessionManager.cache` to `engine.stemCache` (BUG-006.2 / D-091) | — |
| `init(resolver:downloader:stemSeparator:stemAnalyzer:moodClassifier:beatGridAnalyzer:metadataFetcher:cache:sessionRecorder:)` | `production-active` | 9-argument DI init for full testability | — |
| `prepare(tracks:) async` | `production-active` | `SessionManager._beginPreparation` | — |
| `trackStatusesPublisher: AnyPublisher<…, Never>` | `production-active` | `PreparationProgressViewModel` | — |
| `cancelPreparation()` | `production-active` | `SessionManager.cancel()` | — |
| `resumeFailedNetworkTracks() async` | `production-active` | `SessionManager.resumeFailedNetworkTracks()` | D-061(d) |
| `sessionRecorder: SessionRecorder?` (internal `let`) | `production-active` | `SessionPreparer+WiringLogs` (extension access requires internal visibility per file comment at `:92`) | BUG-006.1 instrumentation; tracked for QR.5 cleanup |
| BUG-006.1 `WIRING: SessionPreparer.prepare ENTER` / `DONE` lines | `production-active` | Diagnostic trail | Tracked for QR.5 cleanup |
| Round 26 metadata-driven meter override (parallel `async let profileTask`) | `production-active` | `SessionPreparer.swift:292-304` — `prefetchedProfile` is threaded into `analyzePreview` which calls `BeatGrid.overridingBeatsPerBar(timeSignature)` at line 136 | 2026-05-15 work; documented in `BeatGrid.swift` (CA.1) but not in `ARCHITECTURE.md §Session Preparation` (see `documented-but-missing` finding 1) |

Two TODO markers at the file top (`U.4-followup`): split `.mir` sub-stage emission from the detached task, and wire URLSession download progress callback. Neither is a defect — both are documented limitations.

### `SessionPreparer+Analysis.swift` (353 lines) — `production-active`

[`SessionPreparer+Analysis.swift:66`](../../PhospheneEngine/Sources/Session/SessionPreparer+Analysis.swift) — `nonisolated static func analyzePreview(...)`. The composition surface for the seven-step pipeline run inside `Task.detached(priority: .userInitiated)`:

1. Stem separation (`separator.separate(audio:channelCount:sampleRate:)` — ML module).
2. Mono waveform extraction from UMA `stemBuffers` (line 84–88).
3. Multi-frame AGC warmup → `StemFeatures` snapshot (`warmUpAndAnalyze`, lines 192–218).
4. Offline MIR (`analyzeMIR`, lines 228–299) — fresh `MIRPipeline` consumed frame-by-frame from a 1024-point non-overlapping vDSP FFT at the preview's native sample rate. Mood classifier called every 30 frames (line 281); `mood: classifier.currentState` at line 295 reads the EMA-smoothed final state.
5. Full-mix `BeatGrid` (Beat This! offline) at lines 116–123.
6. Metadata-driven `beatsPerBar` override at lines 133–139 (Round 26).
7. Drums-stem `BeatGrid` at lines 144–152 (DSP.4 diagnostic).
8. `GridOnsetCalibrator.calibrate(...)` BUG-007.8 per-track offset at lines 155, 176–184.

Returns a fully populated `CachedTrackData`. The function is `swiftlint:disable function_body_length` per the file's top-of-file comment because each stage is short and splitting them into helpers would obscure the sequential pipeline.

This file is the **load-bearing Session-side composition seam** for the entire DSP / ML / Audio prep flow. CA.1 + CA.2 between them audited every component; CA.3's verification is that the composition correctly threads `prefetchedProfile` (Round 26), bypasses `BeatGridAnalyzer` cleanly when `analyzer == nil` (test path), and correctly reads `classifier.currentState` at end-of-prep rather than re-running classify (the CA.2-carry-forward pattern; resolved below).

Notable: `FFTContext` (lines 25–35) is a private working-buffer struct allocated once per `analyzeMIR` call to avoid per-frame heap pressure. The `MIRAnalysisResult` (line 15) is a named struct rather than a tuple — a quality-of-code choice the audit verifies is faithful.

### `SessionPreparer+WiringLogs.swift` (118 lines) — `production-active`

BUG-006.1 + BUG-008.2 + DSP.4 diagnostic emission. Three responsibilities:
1. **`logWiringDoneSummary(cachedTracks:failedTracks:)`** — per-track `WIRING: SessionPreparer.beatGrid` lines + a final `DONE` summary. Called from `SessionPreparer._runPreparation` (line 266).
2. **`logDrumsBeatGridLine(track:)`** — DSP.4 `WIRING: SessionPreparer.drumsBeatGrid` line per cached track.
3. **`logBPMMismatchIfAny(track:)`** — 3-way preferred (`detectThreeWayBPMDisagreement`), falls back to 2-way (`detectBPMMismatch`, BUG-008.2 backward grep-ability) when drums-stem BPM is zero or missing.

Diagnostic-only — no production behaviour depends on these log lines, but they are the load-bearing diagnostic trail for any session-prep regression. Tracked for QR.5 cleanup once BUG-006 / BUG-007 / BUG-008 fully close.

### `PreviewResolver.swift` (171 lines) — `production-active`

[`PreviewResolver.swift:13`](../../PhospheneEngine/Sources/Session/PreviewResolver.swift) — `public protocol PreviewResolving: Sendable` + `public final class PreviewResolver`. D-070 Spotify-inline-then-iTunes-fallback. Per-track in-memory cache with `URL??` semantics (`.none` = not cached; `.some(.none)` = cached "no preview"; `.some(.some(url))` = cached URL). Sliding-window rate limiter (20 req/min default per D-011) implemented at lines 124–143; suspends rather than errors.

The Spotify-inline short-circuit at lines 73–76 is the D-070 Decision (Failed Approach #47): if `track.spotifyPreviewURL != nil`, seed the cache and return without any network call. Tests: `PreviewResolverTests.spotifyPreviewURL_returnedWithoutNetworkCall` (`:160`), `spotifyPreviewURL_cachedOnSecondCall` (`:176`), plus the iTunes-fallback path tests for `spotifyPreviewURL: nil`.

### `PreviewDownloader.swift` (202 lines) — `production-active`

[`PreviewDownloader.swift:12`](../../PhospheneEngine/Sources/Session/PreviewDownloader.swift) — `public protocol PreviewDownloading: Sendable` + `public final class PreviewDownloader`. Injectable `fileFetcher` closure (default `URLSession.shared`) so tests never touch the network. AVAudioFile-based decode to mono Float32 (stereo averaged). `batchDownload(tracks:)` uses `withTaskGroup` with a configurable concurrency ceiling (default 4). Temp files written to `tempDirectoryURL` and deleted via `defer`. Format detection via magic-byte sniffing (`audioFileExtension(for:)` at lines 172–197) — WAV, AIFF, CAF, MP3, default M4A — needed because preview-server `Content-Type` headers aren't reliable.

### `StemCache.swift` (132 lines) — `production-active`

[`StemCache.swift:15, 72`](../../PhospheneEngine/Sources/Session/StemCache.swift) — `public struct CachedTrackData` (six fields: stemWaveforms / stemFeatures / trackProfile / beatGrid / drumsBeatGrid / gridOnsetOffsetMs) and `public final class StemCache: @unchecked Sendable` (NSLock-guarded dictionary). The most-used Session-module type by consumer count.

| Capability | Verdict | Consumers | Notes |
|---|---|---|---|
| `CachedTrackData` struct | `production-active` | App + tests | All six fields read by `VisualizerEngine+Stems.resetStemPipeline(for:)` and `VisualizerEngine+Orchestrator` |
| `StemCache` class | `production-active` | App (`VisualizerEngine.stemCache`) + Session (`SessionPreparer.cache`) + 7 test files | BUG-006.2 wired the engine and session-manager refs to the same instance |
| `store(_:for:) / clear() / count` (write API) | `production-active` | `SessionPreparer._runPreparation`; tests | NSLock-guarded |
| `loadForPlayback(track:) / stemFeatures(for:) / trackProfile(for:) / beatGrid(for:) / drumsBeatGrid(for:)` (read API) | `production-active` | App + WIRING logs + tests | NSLock-guarded |

### `TrackIdentity.swift` (143 lines) — `production-active`

[`TrackIdentity.swift:23`](../../PhospheneEngine/Sources/Session/TrackIdentity.swift) — `public struct TrackIdentity: Sendable, Codable`. Seven identity fields (title / artist / album / duration / appleMusicID / spotifyID / musicBrainzID) plus the `spotifyPreviewURL` resolution hint excluded from `Equatable`, `Hashable`, AND `Codable` per D-070 + D-091 (cache-key invariant: hint must not affect dictionary key contract). The custom `Equatable` (lines 119–127) and `Hashable` (lines 134–141) implementations are the regression-discriminating surface for the cache-key contract; the custom `CodingKeys` enum (lines 65–67) is the regression-discriminator for serialization compatibility. 299 consumer references across `PhospheneApp/` + `PhospheneEngine/` + `Tests/`.

### `TrackProfile.swift` (65 lines) — `production-active`

[`TrackProfile.swift:15`](../../PhospheneEngine/Sources/Session/TrackProfile.swift) — `public struct TrackProfile: Sendable`. Seven fields (bpm / key / mood / spectralCentroidAvg / genreTags / stemEnergyBalance / estimatedSectionCount) + `TrackProfile.empty` defaults. Consumed by `DefaultPresetScorer` (Orchestrator) and `DefaultSessionPlanner.plan(...)`. 162 non-Session consumer references.

### `PlaylistConnector.swift` (254 lines) — `production-active`

Five public types: `PlaylistSource` enum (4 cases), `PlaylistConnectorError` enum (9 cases — `appleMusicNotRunning`, `spotifyAuthFailure`, `spotifyLoginRequired`, `spotifyPlaylistInaccessible`, `spotifyPlaylistNotFound`, `rateLimited(retryAfterSeconds:)`, `unrecognizedPlaylistURL`, `networkFailure`, `parseFailure`), `PlaylistConnecting` protocol, `PlaylistConnector` class, plus `PlaylistSource.displayName` extension. Apple Music path uses AppleScript via `executeAndReturnError` on `Task.detached` with -600 / -1728 swallowed as expected; Spotify path delegates to the `SpotifyWebAPIConnecting` injection seam. `appleScriptReader` is the test-time injection point (`PlaylistConnectorTests` exercises canned scripts).

The `.spotifyCurrentQueue` source explicitly throws `networkFailure("Spotify queue requires an active OAuth session (v2 feature)")` at line 127–129 — deliberate deferral per UX_SPEC §4.4. Not a defect.

The `.appleMusicPlaylistURL` path at lines 204–213 validates the URL format then **falls back to the current-playlist path** with a logged note (`MusicKit deferred`). This is a documented v1 limitation per the in-file comment; correct behaviour.

### `LocalFolderConnector.swift` (25 lines) — `stub`

See `§stub` finding above. Entire body gated behind `#if ENABLE_LOCAL_FOLDER_CONNECTOR`; flag never set; class never compiles into the production app. Intentional scaffold per D-046 + UX_SPEC §4.4.

### `BeatGridAnalyzer.swift` (81 lines) — `production-active` (CA.1 boundary-deferred — resolved)

[`BeatGridAnalyzer.swift:19, 40`](../../PhospheneEngine/Sources/Session/BeatGridAnalyzer.swift) — `public protocol BeatGridAnalyzing: Sendable` + `public final class DefaultBeatGridAnalyzer: BeatGridAnalyzing, @unchecked Sendable`. Composes DSP's `BeatThisPreprocessor` (audio → log-mel) + ML's `BeatThisModel` (transformer inference, D-077) + DSP's `BeatGridResolver` (postprocess to `BeatGrid`). Frame rate fixed at 50.0 fps (22050/441 = 50.0). Graceful degradation: returns `.empty` on preprocessor failure (line 63) or model.predict failure (line 76–79).

Production consumers: `SessionPreparer+Analysis.swift:116` (full mix), `SessionPreparer+Analysis.swift:145` (drums stem only — same analyzer instance, MPSGraph graph reusable across calls); `VisualizerEngine+InitHelpers.swift:108` (engine init wiring); `VisualizerEngine+Stems.swift:392` (runtime live-grid analyzer cache for the BUG-007.x live-grid path).

Test consumers: `BeatGridIntegrationTests` (6 cases with both `CountingBeatGridAnalyzer` and `FixedBPMBeatGridAnalyzer` stubs); `BeatGridAccuracyDiagnosticTests`; `LiveDriftValidationTests` (real `DefaultBeatGridAnalyzer` on `love_rehab.m4a`).

**Verdict assignment per §Resolution-of-CA.1/CA.2-boundary-deferred-items:** `production-active`. Recommendation: **keep in Session/**. The `BeatGridAnalyzing` protocol is the testability-seam pattern that matches Session's other `*-ing` injectables (`StemAnalyzing`, `MoodClassifying`, `PreviewResolving`, `PreviewDownloading`, `PlaylistConnecting`). Relocating the protocol would break that consistency; relocating only the `DefaultBeatGridAnalyzer` implementation would create a confusing protocol-without-default split. The composition shape (DSP + ML inside a single Session-facing protocol) is correct.

### `GridOnsetCalibrator.swift` (198 lines) — `production-active` (CA.1 boundary-deferred — resolved)

[`GridOnsetCalibrator.swift:28`](../../PhospheneEngine/Sources/Session/GridOnsetCalibrator.swift) — `public struct GridOnsetCalibrator`. BUG-007.8 per-track median offset calibrator: replays preview audio offline through a live `BeatDetector` (DSP module), matches sub-bass onsets (`result.onsets[0]`, matching D-075 / Failed Approach #50) to `BeatGrid` beats within ±200 ms, returns median `(gridBeat − onsetTime)` in milliseconds. Returns 0 when grid is empty, samples insufficient, or no matched onsets.

Production consumers: `SessionPreparer+Analysis.swift:179` (prep-time calibration); `VisualizerEngine+Stems.swift:271` (BUG-007.9 runtime recalibration against tap audio after stem-separation lock stabilises).

Test consumers: `GridOnsetCalibratorTests` (5 cases — empty-grid, insufficient-samples, no-onsets, valid-offset, large-offset).

**Verdict assignment per §Resolution-of-CA.1/CA.2-boundary-deferred-items:** `production-active`. Recommendation: **relocate to `Sources/DSP/`** as `CA.3-FU-1`. The struct has no Session-side coupling — it constructs a DSP `BeatDetector`, runs vDSP FFTs, consumes a DSP `BeatGrid` value type, and returns a `Double`. The runtime consumer at `VisualizerEngine+Stems.swift:271` already imports DSP. The Session-side consumer at `SessionPreparer+Analysis.swift:179` already imports DSP. Both call sites would be unchanged by the relocation. Unlike `BeatGridAnalyzer`, there is no protocol-injection pattern to preserve — `GridOnsetCalibrator` is constructed inline by both consumers as a value type. This recommendation matches CA.1-FU-5.

### `BPMMismatchCheck.swift` (181 lines) — `production-active`

[`BPMMismatchCheck.swift:91, 164`](../../PhospheneEngine/Sources/Session/BPMMismatchCheck.swift) — `public func detectBPMMismatch(...)` (2-way, BUG-008.2 backward-grep-able) + `public func detectThreeWayBPMDisagreement(...)` (3-way, DSP.4 diagnostic). Plus two result structs: `BPMMismatchWarning` and `ThreeWayBPMReading`. Pure functions — no I/O, no logging, no Sendable concerns. Default threshold 3 % (intentionally generous — 0.4 % is the `BeatGridResolver`'s own `±0.5` BPM tolerance at 125 BPM; 3 % leaves headroom for legitimate small disagreements like Money's 1.4 %).

Sole production consumer: `SessionPreparer+WiringLogs.logBPMMismatchIfAny(track:)` at lines 81 (3-way) and 104 (2-way). Test consumer: `BPMMismatchCheckTests` (16+ cases). No App-layer or non-Session consumer — diagnostic-only.

### `Connectors/SpotifyTokenProvider.swift` (192 lines) — `production-active`

Three types:
- `public protocol SpotifyTokenProviding: AnyObject, Sendable` — two requirements (`acquire() async throws -> String`, `invalidate() async`). Conformers: `DefaultSpotifyTokenProvider` (engine-side, client-credentials), `SpotifyOAuthTokenProvider` (App-side, OAuth + PKCE per D-069), `MissingCredentialsTokenProvider` (engine-side fallback), test doubles in `SpotifyWebAPIConnectorTests`.
- `public actor DefaultSpotifyTokenProvider` — D-068 client-credentials. Reads `Bundle.main.infoDictionary["SpotifyClientID"]` + `"SpotifyClientSecret"`; throws `.spotifyAuthFailure` on empty. Deduplicates concurrent `acquire()` calls onto a single `refreshTask` (no thundering herd). Cached token returned until within 60 s of expiry.
- `final class MissingCredentialsTokenProvider: SpotifyTokenProviding` — **`internal`**, not public. Fallback used by `SpotifyWebAPIConnector.makeLive()` when Info.plist credentials are absent. Every `acquire()` throws `.spotifyAuthFailure` with the documented copy.

Visibility cross-check: `MissingCredentialsTokenProvider` is `internal` — verified by `grep ^public SpotifyTokenProvider.swift` returning only `SpotifyTokenProviding`, `DefaultSpotifyTokenProvider`, and four public methods. Test consumer (`SpotifyTokenProviderTests:193`) imports `Session` via `@testable import` (line 7 verified).

Tests: 9 cases covering successful fetch, cache hit, near-expiry refresh, 400/401 → `spotifyAuthFailure`, network error, malformed JSON, deduplicated concurrent acquires, missing-credentials always-throws.

### `Connectors/SpotifyWebAPIConnector.swift` (252 lines) — `production-active`

Two types:
- `public protocol SpotifyWebAPIConnecting: AnyObject, Sendable` — one requirement (`connect(playlistID:) async throws -> [TrackIdentity]`).
- `public final class SpotifyWebAPIConnector: SpotifyWebAPIConnecting, @unchecked Sendable` — D-070 `/items` schema, `preview_url` capture, pagination via `next` URL, 401-retry-once-with-fresh-token, 403 → `.spotifyLoginRequired` (`SpotifyOAuthPlaylistConnector` in App layer remaps to `.spotifyPlaylistInaccessible` when authenticated per D-069 Decision 6). `makeLive(urlSession:)` factory builds with `DefaultSpotifyTokenProvider` or `MissingCredentialsTokenProvider` fallback.

`networkFetcher: (@Sendable (URLRequest) async throws -> (Data, URLResponse))?` (internal `var`) is the test-time injection point. Production code never assigns it. Tests assign it for canned-response replay (`SpotifyWebAPIConnectorTests` + `SpotifyItemsSchemaTests` via `@testable import Session`).

Per Failed Approaches #45 + #46 + #47, the connector is the load-bearing surface for three landed lessons:
- **#45 (schema rename, line 134):** read `item["item"]` first, fall back to `item["track"]` — the comment at lines 132–133 calls this out verbatim.
- **#46 (no `fields` parameter, line 153–159):** the comment block explicitly documents why `fields` is omitted (silent `{}` returns).
- **#47 (capture `preview_url`, line 241):** `(track["preview_url"] as? String).flatMap(URL.init)` populates `TrackIdentity.spotifyPreviewURL`.

Tests: 11 cases in `SpotifyWebAPIConnectorTests` (200/401-retry/403/404/429/parse-failure/preview-url captured/preview-url null/pagination) + 4 cases in `SpotifyItemsSchemaTests` (golden /items JSON fixtures locking Failed Approach #45 + #47 regression). All run under `@Suite(.serialized)` per CLAUDE.md Code Style (U.10 learning — URLProtocol stub global-handler race fixed by serialization).

---

## Resolution of CA.1 / CA.2 boundary-deferred items

CA.1 deferred two Session-module files to CA.3; CA.2 carried forward one architectural pattern. All three resolve here.

### CA.1-deferred: `Sources/Session/GridOnsetCalibrator.swift`

**CA.1's read:** Functionally a DSP capability by every criterion except file location. Imports DSP + Accelerate + Foundation; depends on `BeatGrid` + `BeatDetector` from DSP and on vDSP FFT primitives.

**CA.3's verdict:** `production-active`. CA.1's read is correct.

**Recommendation:** **Relocate to `Sources/DSP/GridOnsetCalibrator.swift`** as a follow-up increment. The struct has no Session-side coupling — both consumers (`SessionPreparer+Analysis` and `VisualizerEngine+Stems`) already import DSP. Unlike `BeatGridAnalyzer`, there is no protocol-injection pattern that would benefit from co-location with Session's other testability seams (the calibrator is a value type constructed inline). The relocation is mechanical (1 file move + 1 `Package.swift` line if applicable).

Registered as `CA.3-FU-1`. This matches CA.1-FU-5 (the GridOnsetCalibrator half), which was marked **"Blocked on CA-Session audit"** — that block is now cleared.

### CA.1-deferred: `Sources/Session/BeatGridAnalyzer.swift`

**CA.1's read:** Functionally a DSP-and-ML composition; file location reasonable because the protocol shape matches Session's other `*-ing` testability seams.

**CA.3's verdict:** `production-active`. CA.1's read is correct — and CA.3 confirms the recommendation lean: **keep `BeatGridAnalyzer.swift` in Session/**.

**Reasoning.** The `BeatGridAnalyzing` protocol must be co-located with the consumer (`SessionPreparer`) for the protocol-first DI pattern to make sense. The 5-protocol family in Session (`PreviewResolving`, `PreviewDownloading`, `StemAnalyzing`, `MoodClassifying`, `BeatGridAnalyzing`) plus the App-layer-only `PlaylistConnecting` is the consistent testability-seam shape. Relocating the protocol to DSP/ would break the consistency. Relocating only the `DefaultBeatGridAnalyzer` implementation would create a "protocol without its default" split that is more confusing than the current arrangement.

The implementation itself is short (81 lines, 41 LoC of logic) and the DSP + ML imports it carries (lines 8, 10) are correctly weighted — the composition belongs in a module that already imports both, which `Session` does.

**No follow-up filed.** CA.1-FU-5 (the BeatGridAnalyzer half) is closed by this verdict. If a future increment relocates `GridOnsetCalibrator` to DSP/ per CA.3-FU-1, it should explicitly *not* relocate `BeatGridAnalyzer`.

### CA.2-deferred: `MoodClassifier.currentState` read at end-of-prep

**CA.2's read:** `MoodClassifier.currentState` (public `private(set)` property at `MoodClassifier.swift:63`) is read at `SessionPreparer+Analysis.swift:295` at the very end of `analyzeMIR` to populate `MIRAnalysisResult.mood`. CA.2 flagged this for re-evaluation in the Session-subsystem audit.

**CA.3's verdict:** `production-active` — **the pattern is correct architecture**, not drift.

**Reasoning.** `MoodClassifier.classify(features:)` returns an instant `EmotionalState` value AND updates the internal EMA-smoothed `currentState` property (α = 0.1, ~0.7 s time constant at 94 Hz per CA.2's per-file index). The end-of-prep code at `:281` calls `classify` every 30 frames during the analysis loop, building up the EMA over the entire ~30 s preview clip. By the time the loop ends, `currentState` reflects the time-averaged mood the listener will experience across the preview, which is the correct value to cache as `TrackProfile.mood`. The alternative — using the last `classify` return value — would reflect only the final ~0.7 s of the preview, biased toward whatever happens at the end of the 30 s clip.

The instant return value of `classify` is wired into the **runtime** mood path via `RenderPipeline.setMood(...)` (per CLAUDE.md "Do not write to `latestFeatures.valence` / `arousal` from the MIR path" rule). The end-of-prep `currentState` read is for **cache-time** mood; the runtime instant path is preserved. The two consumers are correctly separated.

**No follow-up filed.** The pattern is correct; no relocation, refactor, or doc-update needed.

---

## Cross-references

### Updates needed in CLAUDE.md

CLAUDE.md's pointers to Session-module documentation are correct and current — `§Session Preparation Pipeline` (the canonical pointer line) routes through `ARCHITECTURE.md §Session Preparation`. The drift surfaced below is entirely in ARCHITECTURE.md, not CLAUDE.md. **No CLAUDE.md edits applied in this increment.**

### Updates needed in ARCHITECTURE.md

Applied in this increment as doc-only corrections:

1. **`§Session Preparation` (lines 112–124) — update the step list** to reflect the production pipeline (`SessionPreparer+Analysis.swift:66-165`):
   - Step 2 corrected: "Resolve preview clip URLs — primary: `TrackIdentity.spotifyPreviewURL` (inline from Spotify `/items` per D-070), iTunes Search API fallback (`PreviewResolver`, D-011)."
   - New step added: metadata pre-fetch parallel with the PCM download (Round 26, 2026-05-15) for ML-detected meter override on odd-time-signature tracks.
   - Step 5 expanded: stem separation → analyzer warmup → MIR → full-mix Beat This! `BeatGrid` (D-077 via `BeatGridAnalyzer`) → metadata-driven `beatsPerBar` override (Round 26) → drums-stem `BeatGrid` (DSP.4 diagnostic) → `GridOnsetCalibrator` per-track median offset (BUG-007.8) → cache to `StemCache`.
   - Cross-link to `KNOWN_ISSUES.md §BUG-007.8` and `§BUG-007.9` for the calibration story.

2. **`§Module Map Session/` block (lines 544–554) — add the 13 missing files** with one-line behavioural descriptions:
   - `Session.swift` — module marker; `@_exported import Shared`.
   - `SessionManager+Readiness.swift` — pure `computeReadiness(...)` static; D-056 `.partial` threshold rule.
   - `SessionPreparer+Analysis.swift` — `nonisolated static func analyzePreview(...)` composing DSP + ML + Audio inside `Task.detached`.
   - `SessionPreparer+WiringLogs.swift` — BUG-006.1 + DSP.4 diagnostic log emission.
   - `PreparationProgressPublishing.swift` — `@MainActor protocol`; SessionPreparer conformer; PreparationProgressViewModel consumer.
   - `TrackPreparationStatus.swift` — `AnalysisStage` + 7-status state machine.
   - `BeatGridAnalyzer.swift` — `BeatGridAnalyzing` protocol + `DefaultBeatGridAnalyzer` composing `BeatThisPreprocessor` + `BeatThisModel` + `BeatGridResolver`.
   - `GridOnsetCalibrator.swift` — BUG-007.8 per-track median grid-vs-onset offset calibrator.
   - `BPMMismatchCheck.swift` — `detectBPMMismatch` 2-way (BUG-008.2) + `detectThreeWayBPMDisagreement` 3-way (DSP.4) pure-function detectors.
   - `LocalFolderConnector.swift` — `#if`-gated v2 stub; never compiles in v1.
   - `Connectors/SpotifyTokenProvider.swift` — D-068 `DefaultSpotifyTokenProvider` (client-credentials actor) + `MissingCredentialsTokenProvider` internal fallback + `SpotifyTokenProviding` protocol.
   - `Connectors/SpotifyWebAPIConnector.swift` — D-070 `/items` schema + `preview_url` capture + 401-retry + 403→`spotifyLoginRequired` mapping; `SpotifyWebAPIConnecting` protocol.

3. **`§Module Map Tests/Session/` block (line 580) — remove phantom `StemCacheTests`, add 6 missing files:**
   - Remove: `StemCacheTests` (does not exist on disk; StemCache exercised inside `SessionPreparerTests` + the `PreparedBeatGrid*WiringTests` integration suite).
   - Add: `BPMMismatchCheckTests` (~16 cases), `GridOnsetCalibratorTests` (5 cases), `ProgressiveReadinessTests` (10 cases), `SessionManagerCancelTests`, `SessionPreparerProgressTests`, `TrackPreparationStatusTests`.

4. **`§Session Recording (Diagnostics)` — note the `WIRING:` log surface.** Add a one-line pointer that BUG-006.1 introduced a `WIRING:` line family covering session start, preparer entry/done, per-track beat-grid summary, drums-stem beat-grid summary (DSP.4), and 2-way / 3-way BPM disagreement warnings (BUG-008.2 / DSP.4); these are diagnostic-only and tracked for QR.5 cleanup.

### Updates needed in ENGINEERING_PLAN.md

Applied:
1. Phase CA section: register `CA.3 (Session)` as ✅ Landed under the existing Phase CA block.
2. Recently Completed: add the CA.3 entry mirroring the CA.1 / CA.2 shape — file count, verdict counts, top findings, doc-drift corrections applied, boundary-deferred items resolved.
3. The CA.3 row in the existing Phase CA section flips from "Pending" to "✅ Landed" with the audit-deliverable link.

### Updates needed in DECISIONS.md

None. The audit verified every D-008, D-017, D-018, D-019, D-046, D-052, D-056, D-061, D-068, D-069, D-070, D-091 claim against current code and found no contradictions. The decisions remain accurate as-written.

- D-008 (playlist-first prep) — implemented end-to-end via the `SessionPreparer` pipeline.
- D-017 (`SessionState` + `SessionPlan` in Session module) — verified at `SessionTypes.swift:10, 71`.
- D-018 (degrade to ready on failure) — `SessionManager.swift:154-159` connector-failure path; `SessionPreparer._runPreparation` partial-plan path.
- D-019 (stem routing warmup fallback) — Renderer-side concern; Session-side unchanged.
- D-046 (connector picker) — `LocalFolderConnector` stub, `.spotifyAuthRequired` silent-degrade (Decision 4) superseded by D-068.
- D-052 (capture-mode reconciler) — App-layer; not Session-module.
- D-056 (progressive readiness) — verified at `SessionManager+Readiness.computeReadiness(...)` (line 21) + `defaultProgressiveReadinessThreshold` (`SessionTypes.swift:63`) + `.partial` threshold rule (`SessionManager+Readiness.swift:60-65`).
- D-061 (long-session resilience) — App-layer coordinators; verified `SessionPreparer.resumeFailedNetworkTracks()` exists at `:346` and `SessionManager.resumeFailedNetworkTracks()` wraps it at `:324`.
- D-068 (client-credentials connector) — verified at `SpotifyTokenProvider.swift` (Info.plist read, deduplicated refresh task, MissingCredentialsTokenProvider fallback).
- D-069 (OAuth + PKCE) — App-layer concrete (`PhospheneApp/Services/SpotifyOAuthTokenProvider.swift`) conforms to engine-side `SpotifyTokenProviding` protocol; correctly placed per Decision 2.
- D-070 (`/items` schema + `preview_url` capture) — verified at `SpotifyWebAPIConnector.parseTrack(_:)` (line 228, especially line 241), `TrackIdentity.spotifyPreviewURL` excluded from Equatable/Hashable/Codable (lines 65-67, 119-127, 134-141), `PreviewResolver` short-circuit (line 73-76).
- D-091 (QR.4 SettingsStore collapse + `currentTrackIndex`) — App-layer; the Session-side touchpoint (`PlannedSession.canonicalIdentity(matchingTitle:artist:)`) lives in Orchestrator, not Session — boundary-noted.

### New BUG entries

**None filed.** The two BUGs the kickoff named in scope (BUG-005, BUG-006) are correctly classified in `KNOWN_ISSUES.md`:
- BUG-005 (Open / P3 / `session.ux`) — external-API limitation, fix scope is UX copy only; not a Session-module correctness defect. No new diagnosis surfaced.
- BUG-006 (Resolved 2026-05-06) — kickoff prompt was stale; the actual file entry has shown `Status: Resolved` since the BUG-006.2 fix landed. The audit's read of the prepared-cache wiring path confirms the fix is in place at `VisualizerEngine.swift:614` (engine.stemCache ↔ sessionManager.cache) and `VisualizerEngine+Capture.swift:131` (canonical TrackIdentity resolution via `PlannedSession.canonicalIdentity`).

### KNOWN_ISSUES.md sweep

None this increment. No entries reproduced as no-longer-applicable; no entries whose code surface no longer exists; no retroactive Resolved entries identified.

---

## Follow-up Backlog

Findings surfaced by CA.3 that are *not* corrected in this audit increment. Each row is a candidate follow-up increment with enough scope to act on cold. Per the kickoff's audit-only discipline, fixes ship as separate increments scheduled whenever Matt prioritises them.

Items are greppable as `CA\.3-FU-\d+`. If/when a top-level `docs/CAPABILITY_REGISTRY/FOLLOWUPS.md` aggregator is authored (CA.1's recommendation, still deferred), CA.3's three rows fold in alongside CA.1's five and CA.2's five.

| ID | Scope | Done-when | Est. sessions | Status |
|---|---|---|---|---|
| **CA.3-FU-1** | Relocate `Sources/Session/GridOnsetCalibrator.swift` → `Sources/DSP/GridOnsetCalibrator.swift`. The struct is functionally a DSP capability (constructs `BeatDetector`, runs vDSP FFTs, consumes `BeatGrid`, returns `Double`). Both consumers (`SessionPreparer+Analysis.swift:179`, `VisualizerEngine+Stems.swift:271`) already import DSP. The relocation is mechanical: 1 file move + verify Package.swift if module exports require it. Closes CA.1-FU-5's GridOnsetCalibrator half (which was marked "Blocked on CA-Session audit" — block is cleared by this audit). Explicitly does NOT relocate `BeatGridAnalyzer` — see §Resolution-of-CA.1/CA.2-boundary-deferred-items for why that stays in Session/. | File at `Sources/DSP/GridOnsetCalibrator.swift`; both consumer call sites unchanged; `swift test --package-path PhospheneEngine` passes; SwiftLint clean. | <1 | Ready now |
| **CA.3-FU-2** | Decide the fate of `LocalFolderConnector.swift`. Today it is a `#if ENABLE_LOCAL_FOLDER_CONNECTOR`-gated stub with no enabled site anywhere in the build. Two options: **(a)** Delete the file. UX_SPEC §4.4 mentions local-folder as a v2 surface, but the deletion can be reverted from git history when v2 work starts. Matches D-068's "silent-degrade removal" aesthetic — don't ship dead scaffold. **(b)** Replace the `#if` gate with a runtime-disabled toggle that surfaces a "Local folder support coming in a future update" UX. The current behaviour (the class never compiles) is the worst of both worlds: a developer reading `LocalFolderConnector.swift` sees scaffold that isn't actually wired and may waste time tracing the gate. **Recommended (a) to Matt** — the engineering cost is low and the v2 revival starts cleaner from spec than from a year-old stub. Either decision is a Matt call. | Either (a) `LocalFolderConnector.swift` is deleted and the `ConnectorPickerViewModel` comment updated, OR (b) the `#if` gate is replaced with a runtime-disabled toggle. Build green; SwiftLint clean. | <1 | **Blocked on Matt's product call** (delete vs. keep-as-runtime-disabled) |
| **CA.3-FU-3** | (Optional, low priority.) Retire BUG-006.1 `WIRING:` log instrumentation per the QR.5 plan. The instrumentation is in `SessionManager.startSession`, `SessionManager._beginPreparation`, `SessionManager.startNow()`, `SessionPreparer.prepare(tracks:)`, `SessionPreparer+WiringLogs.logWiringDoneSummary` / `logDrumsBeatGridLine` / `logBPMMismatchIfAny`. BUG-006 is closed; BUG-007 + BUG-008 are tracked but not Session-module-side issues. Costs nothing at runtime; the value of keeping it is "the next session-prep regression has the diagnostic trail already in place." Costs of retiring: net negative readability surface around 10–20 lines of LOC. Defer to QR.5; flagging here for completeness. | Either the `WIRING:` family is retired (and `SessionPreparer+WiringLogs.swift` either deleted or trimmed to just the DONE summary + the BPM-mismatch warnings), OR the file's top comment is updated to say "intentional permanent instrumentation" so it doesn't read as cleanup-pending. | <1 | Deferred to QR.5 wave |

**Bundling recommendation.** FU-1 is standalone and ready to land in any DSP-touching increment. FU-2 needs a Matt product call before scheduling. FU-3 is part of the QR.5 cleanup wave and doesn't need to be a CA.3-attributed follow-up at all — recorded here for completeness.

**Priority order if Matt picks just one this week:** FU-1 (mechanical, closes the CA.1-FU-5 GridOnsetCalibrator half, narrows Session's DSP-import surface, no behavioural change). FU-2 and FU-3 are housekeeping with minimal user-visible impact.

---

## Approach validation

**What worked.**
- The kickoff's "evidence-based, every claim cites a file:line" rule continues to produce tractable scope. Every verdict in the per-file index above is backed by a citation or a cited grep.
- Reading all 22 files directly (skipping Explore agents because file sizes were tractable — the largest file is 383 lines) eliminated the CA.2-flagged "agent over-asserts publicness" failure mode entirely. The visibility-verification grep was run as a final cross-check anyway and confirmed every audit-stated `public` is correct and every `internal` / `internal var` testing-seam is correctly scoped.
- The boundary-noted vs boundary-deferred distinction introduced for CA.3 had real bite. Three boundary-noted findings (Session ↔ App, Session ↔ Orchestrator, Session ↔ DSP / ML / Audio) were assigned without re-auditing those subsystems' internals; the audit's load-bearing reads stayed within the Session module surface as intended.
- The CA.1/CA.2 carry-forward resolution section (BeatGridAnalyzer, GridOnsetCalibrator, MoodClassifier.currentState end-of-prep) was the audit's clearest contribution. All three items got definitive verdicts; one ships as a follow-up (FU-1, GridOnsetCalibrator relocation), two stay where they are (BeatGridAnalyzer's protocol pattern, MoodClassifier.currentState's EMA-smoothed correctness). The kickoff's prediction that three items would resolve here proved right.
- The kickoff's "BUG-006 active in scope" claim turning out to be stale (it's been Resolved since 2026-05-06) was a load-bearing finding the audit produced quickly — verifying the kickoff prompt against the actual `KNOWN_ISSUES.md` file is something a future CA increment should do as a routine step.

**What didn't.**
- Reading files directly instead of spawning Explore agents was fine for Session (the 22 files totalled 3,425 lines and I could comfortably read every load-bearing one). It will be tighter on a larger subsystem. For CA.4+, agents remain the right call when total LoC exceeds ~5k or when many files are above ~400 lines — but the visibility-verification grep is mandatory regardless.
- The audit's by-verdict sections trended toward sparse — most non-`production-active` findings were doc-drift, not orphan or broken-but-claimed. The per-file index carries most of the audit's value. CA.2's consolidation note (collapse Findings-by-verdict + per-file index when the verdict distribution is heavily `production-active`) probably applies here too; CA.3 kept them split because the boundary-deferred resolution needed a discrete section and that's hard to navigate without distinct headers.
- Three Spotify-connector files (`SpotifyTokenProvider.swift`, `SpotifyWebAPIConnector.swift`, plus the App-layer `SpotifyOAuthTokenProvider`) form a tightly-coupled cluster spanning the Session / App boundary. The audit handled the engine-side correctly; the App-side `SpotifyOAuthTokenProvider` is boundary-noted. When CA-App runs, it should re-audit `SpotifyOAuthTokenProvider` against this audit's notes — the engine-side `SpotifyTokenProviding` protocol contract is the load-bearing seam.

**Recommended changes for CA.4.**
- **Default to direct reads for subsystems ≤ 5k LoC.** Explore agents have real value for larger codebases; their overhead (and the over-assertion-of-public failure mode) is not justified for tight modules. The visibility grep stays mandatory either way.
- **Verify the kickoff prompt against `KNOWN_ISSUES.md`** as the audit's second step (right after reading the prior audit's section). CA.3 found the kickoff's BUG-006 "Open" claim was stale; that was a 30-second cross-check that saved hours of false-positive diagnosis work.
- **Recommended next subsystem for CA.4:** **Orchestrator** (`PhospheneEngine/Sources/Orchestrator/`). The Session audit surfaced multiple Session-Orchestrator boundary touchpoints (`TrackProfile` consumption by `DefaultPresetScorer`, `SessionPlan` → `PlannedSession` lift in App layer, `PlannedSession.canonicalIdentity(matchingTitle:artist:)` consumed during prepared-cache wiring). The Orchestrator's per-file CA audit closes that boundary cleanly and gives the next CA-App audit full context. **Alternative ordering:** if BUG-012 reproduces and Step 2 diagnosis lands within the next week, the diagnosis may surface different priorities; defer CA.4 scope decision until then.

The audit format continues to produce real, actionable findings (one stub, two doc-drift categories, three boundary-deferred resolutions). Recommend continuing into CA.4 with the methodology refinements above; minor consolidations as noted.

---

*End of CA.3 — Capability Registry — Session.*
