// swiftlint:disable file_length
// VisualizerEngine+LocalFilePlayback — LF.4 / D-131 + LF.5 / D-132.
//
// Bridges `SessionManager.startLocalFile(at:)` to the engine's audio path:
//
//   1. `LocalFilePreparing` conformance — SessionManager calls
//      `prepareLocalFile(url:)` on the engine to run the hash + persistent-cache +
//      analyzePreview + persist pipeline. Returns a `LocalFilePrepResult` whose
//      cached data SessionManager then stores into the in-memory `StemCache` and
//      whose synthetic identity drives plan + state transitions.
//
//   2. `.ready` observer — when `sessionManager.state == .ready` AND
//      `currentSource` is a local file, the engine installs the cached BeatGrid
//      via `resetStemPipeline(for:)`, starts the LF audio router, and advances
//      the session to `.playing`.
//
// This replaces the LF.1 / LF.2 / LF.3 entry points
// (`startLocalFilePlayback(url:)`, `prepareAndStartLocalFilePlayback(url:)`,
// `_completeLocalFilePlaybackStart(url:tag:)`) that previously lived in
// `VisualizerEngine+PublicAPI.swift`. The off-main worker logic
// (`runLocalFilePreparation`, `tryLoadFromPersistentCache`,
// `analyzeAndPersist`) moves here verbatim — only the entry point shape
// changes.

import Audio
import Combine
import DSP
import Foundation
import ML
import Session
import Shared
import os.log

private let lfLogger = Logger(subsystem: "com.phosphene.app", category: "VisualizerEngine+LF")

// MARK: - LocalFilePreparing conformance

extension VisualizerEngine: LocalFilePreparing {

    /// SessionManager (LF.4) calls this delegate to run the LF preparation
    /// pipeline. Returns the freshly-loaded or freshly-analyzed result, or
    /// `nil` on any failure (sha256 + read failure, no separator, decode
    /// error). `nil` is non-fatal — SessionManager still transitions to
    /// `.ready` and the engine's `.ready` observer falls through to the
    /// LF.1 no-cache start.
    public func prepareLocalFile(url: URL) async -> LocalFilePrepResult? {
        let sep = stemSeparator
        let analyzer = stemAnalyzer
        let classifier: any MoodClassifying = moodClassifier ?? MoodClassifier()

        // Eager-init the live Beat This! analyzer here — it's lazy-initialised
        // on first live-inference call by default, but LF needs it ready
        // before audio starts so the cached grid install is BEFORE the
        // live-inference path opens. Same instance is then re-used by live
        // inference once audio is flowing.
        if liveBeatGridAnalyzer == nil {
            do {
                liveBeatGridAnalyzer = try await MainActor.run {
                    try DefaultBeatGridAnalyzer(device: self.context.device)
                }
            } catch {
                let msg = error.localizedDescription
                lfLogger.warning(
                    "[LF.4] DefaultBeatGridAnalyzer init failed: \(msg, privacy: .public) — cached grid empty"
                )
            }
        }
        let gridAnalyzer = liveBeatGridAnalyzer
        // IFC.4 (D-177) — eager-init the PANNs family analyzer for the LF
        // pre-analysis path (mirrors the beat-grid analyzer above).
        if liveFamilyAnalyzer == nil {
            do {
                liveFamilyAnalyzer = try await MainActor.run {
                    try InstrumentFamilyAnalyzer(device: self.context.device)
                }
            } catch {
                let msg = error.localizedDescription
                lfLogger.warning(
                    "[LF.4] InstrumentFamilyAnalyzer init failed: \(msg, privacy: .public) — family series empty"
                )
            }
        }
        let famAnalyzer = liveFamilyAnalyzer
        let persistentCache = persistentStemCache
        let recorder = sessionRecorder
        let filename = url.lastPathComponent

        let inputs = LocalFilePrepWorkerInputs(
            url: url,
            filename: filename,
            separator: sep,
            analyzer: analyzer,
            classifier: classifier,
            beatGridAnalyzer: gridAnalyzer,
            familyAnalyzer: famAnalyzer,
            persistentCache: persistentCache,
            recorder: recorder
        )
        return await Task.detached(priority: .userInitiated) {
            await VisualizerEngine.runLocalFilePreparation(inputs: inputs)
        }.value
    }

    // MARK: - .ready observer (called from the engine init's Combine sub)

    /// Called from the engine's `sessionManager.$state` subscription when the
    /// state machine transitions to `.ready` AND `currentSource` is a local
    /// file (LF.4 single-file or LF.5 multi-file / folder / playlist). Installs
    /// the cached BeatGrid (cache lookup hits the in-memory `StemCache` that
    /// SessionManager populated during preparation), starts the LF audio router
    /// with the **first** URL in the queue, and advances the session to
    /// `.playing`. Mid-session advance to subsequent queue entries is the
    /// `advanceLocalFileQueue()` path (LF.5 Task 8) — not this one.
    @MainActor
    func handleLocalFileReady() {
        guard let source = sessionManager.currentSource,
              source.isLocalFile,
              let url = source.localFileURL else {
            return
        }
        // LF.5.fix.3-C: duplicate-emission guard. If `_completeLocalFilesReady`
        // somehow fires a second time for the URL we already started, do NOT
        // tear down the audio router + restart from frame 0 — that's the
        // 21:02:14 self-inflicted SZ2 restart in session 2026-05-28T20-57-46Z.
        // Bug A's gen-counter gate should prevent the upstream duplicate
        // _completeLocalFilesReady; this is the local defense at the
        // consumer side per Matt's LF.5.fix.3-C kickoff (URL match only).
        if let started = lastStartedLocalFilePlaybackURL, started == url {
            let name = url.lastPathComponent
            lfLogger.info(
                "[LF.5.fix.3-C] handleLocalFileReady ignored — already started for \(name, privacy: .public)"
            )
            return
        }
        guard let identity = sessionManager.currentPlan?.tracks.first else {
            lfLogger.warning("[LF.4] .ready with LF source but no identity in plan — falling through")
            return
        }
        // Install BeatGrid + cached StemFeatures + cached bass proportion from the
        // engine's stemCache (which IS sessionManager.preparer.cache; LF preparation
        // wrote into it).
        resetStemPipeline(for: identity, caller: .other)

        // LFPLAN.1 (2026-06-19) — AI plan RE-ENABLED for local files. The
        // 2026-05-28 BUG-021 revert disabled `buildPlan()` here: with a 2-preset
        // catalog the orchestrator cycled presets "one every ~5 s" and a Next
        // press force-quit the app. The cycling's root cause was BUG-042's
        // note-scale section detector inflating `estimatedSectionCount`
        // (= `StructuralAnalyzer` boundary count, SessionPreparer+Analysis) to
        // ~180 → ~180 tiny planner segments per track. All THREE re-enable
        // preconditions the revert named are now met: (1) BUG-042's section-scale
        // decimation (2026-06-19) collapses the count to ~9 sane sections
        // (`PlannerSectionCountScalingTests` pins 180→9); (2) the certified
        // catalog is now 7 (was 2); (3) the Next-button lockup was the
        // separately-resolved BUG-059 ABBA deadlock (2026-06-18). buildPlan() is
        // source-agnostic (reads `currentPlan` + cached profiles, both present on
        // the LF path) and sets `livePlan`, flipping the orchestrator to session mode.
        buildPlan()

        // LF.5.fix D-LF5-1 + LF.6: orchestrator plan-mode wire (mirrors
        // `makeTrackChangeCallback` in VisualizerEngine+Capture.swift:129 —
        // the LF.5 LF path bypasses the streaming callback) AND chrome
        // surface publish (closes Gap A — pre-LF.6 every LF session rendered
        // "—" for title because `currentTrack` was never written from the LF
        // path). See `applyLocalFileTrackState(...)` for the unified write.
        applyLocalFileTrackState(identity: identity, planIndex: 0)

        // LF.5: wire the EOF callback BEFORE starting the audio router so we
        // can't miss an end-of-stream event for a very short fixture. Per
        // Matt's audit answer (2026-05-27), single-file queues loop the file
        // (LF.1 behavior preserved); multi-file queues advance + .ended on
        // exhaustion.
        let isMultiFile = source.allLocalFileURLs.count > 1
        if #available(macOS 14.2, *), let audioRouter = router as? AudioInputRouter {
            if isMultiFile {
                audioRouter.onLocalFilePlaybackEnded = { [weak self] in
                    Task { @MainActor in self?.advanceLocalFileQueue() }
                }
            } else {
                audioRouter.onLocalFilePlaybackEnded = nil
            }
            // BUG-021 (2026-05-28): forward LocalFilePlaybackProvider's
            // diagnostic breadcrumbs into session.log on the call thread.
            // Captured at install time — same lifecycle as the EOF callback
            // above, applied to every subsequent provider start.
            let recorder = sessionRecorder
            audioRouter.onLocalFilePlaybackDiagnostic = { [weak recorder] msg in
                recorder?.log("WIRING: \(msg)")
            }

            // LF.5.fix.2-FU4 + FU-5: mirror the streaming track-change
            // callback's destructive resets at
            // `VisualizerEngine+Capture.swift:203-204` (and the FU-3
            // placement in `advanceLocalFileQueue`), AND zero
            // `lastAnalysisTime` so the very first audio frame's `dt`
            // (computed at `VisualizerEngine+Audio.swift:137`) is small.
            //
            // FU-4 alone (the two reset() calls below) was necessary but
            // insufficient — verification session `2026-05-28T21-08-33Z`
            // showed `elapsedTrackTime=94.3s` on the first wire-active
            // line despite FU-4 zeroing `mir.elapsedSeconds`. Root cause:
            // `lastAnalysisTime` is initialized at engine setup
            // (`VisualizerEngine+Audio.swift:28`) and only updated inside
            // `processAnalysisFrame`. With a 91 s prep window before the
            // first audio frame post-`audioRouter.start`,
            // `dt = now - lastAnalysisTime ≈ 91 s` on that first frame —
            // and that huge `dt` flows into `mir.process(deltaTime:)`,
            // which executes `elapsedSeconds += Double(ctx.deltaTime)` at
            // `MIRPipeline.swift:235`. The FU-4 reset zeroes
            // `elapsedSeconds`; the single huge first-frame dt then
            // re-adds the prep window in one go (94.3 s ≈ 91 s prep gap
            // + 3 s real playback). FU-5 closes the second mover by
            // setting `lastAnalysisTime` to "now" at the same instant.
            //
            // FU-3 (advance) didn't expose this because audio was flowing
            // right up to `audioRouter.stop()`, so `lastAnalysisTime` was
            // recent (last frame ~10 ms before stop). Restart's first
            // frame sees a small dt and the FU-3 fix alone is sufficient.
            mirPipeline.reset()
            pipeline.resetAccumulatedAudioTime()
            lastAnalysisTime = CFAbsoluteTimeGetCurrent()

            // Start the LF audio router (AVAudioEngine path).
            do {
                try audioRouter.start(mode: .localFilePlayback(url))
                lfLogger.info("[LF.4] LF playback router started: \(url.lastPathComponent, privacy: .public)")
                // LF.5.fix.3-C: mark this URL as the "committed" playback so
                // a subsequent duplicate .ready emission no-ops at the guard
                // above. Cleared on the next .preparing / .ended transition.
                lastStartedLocalFilePlaybackURL = url
            } catch {
                let msg = error.localizedDescription
                lfLogger.error("[LF.4] LF playback router start failed: \(msg, privacy: .public)")
                // PUB.5 (ultra-review): surface it — the user was previously
                // stranded on a silent PlaybackView with a log-only error.
                // Toast (§9.4) + end the session so they land on EndedView
                // with the re-pick CTAs instead of a dead visualizer.
                userFacingErrorSubject.send(
                    .localFilePlaybackFailed(fileName: url.lastPathComponent))
                sessionManager.endSession()
                return
            }
        }

        startStemPipeline()
        currentTrackIndex = 0                               // LF.5: published for chrome + orchestrator
        isLocalFilePaused = false                           // LF.5.fix D-LF5-3: fresh session starts playing

        sessionManager.beginPlayback()

        if let current = presetLoader.currentPreset {
            applyPreset(current)
            showPresetName(current.descriptor.name)
        }

        refreshLocalFileCacheBytes()
    }

    // MARK: - LF.5 mid-session queue advance

    /// Direction parameter for `advanceLocalFileQueue` — `.forward` is the
    /// natural EOF advance path; `.backward` is the user-driven "previous
    /// track" transport button (LF.5.fix D-LF5-3).
    enum LocalFileQueueDirection: Sendable {
        case forward
        case backward
    }

    /// Pop the next URL off the LF.5 queue (forward or backward), install its
    /// cached BeatGrid via `resetStemPipeline(caller: .trackChange)`, restart
    /// the audio router with the next file, and update `currentTrackIndex`.
    /// Forward advance from the last track transitions the session to
    /// `.ended`; backward advance from the first track is a no-op (matches
    /// standard music-player UX). Single-file queues never reach this path
    /// from an EOF (the LF.1 loop default fires instead per Matt's audit
    /// answer); transport-driven entries to this method on a 1-track queue
    /// are no-ops because there is no previous or next track.
    @MainActor
    func advanceLocalFileQueue(direction: LocalFileQueueDirection = .forward) {
        guard let source = sessionManager.currentSource, source.isLocalFile else { return }
        let urls = source.allLocalFileURLs
        let tracks = sessionManager.currentPlan?.tracks ?? []
        let currentIdx = currentTrackIndex ?? -1
        let nextIdx: Int
        switch direction {
        case .forward: nextIdx = currentIdx + 1
        case .backward: nextIdx = currentIdx - 1
        }

        guard nextIdx >= 0, nextIdx < urls.count, nextIdx < tracks.count else {
            if direction == .forward {
                lfLogger.info("[LF.5] queue exhausted — transitioning to .ended")
                currentTrackIndex = nil
                sessionManager.endSession()
            } else {
                lfLogger.info("[LF.5] queue at start — prev is no-op")
            }
            return
        }

        let nextURL = urls[nextIdx]
        let nextIdentity = tracks[nextIdx]
        lfLogger.info(
            "[LF.5] advance: \(currentIdx) → \(nextIdx), next='\(nextURL.lastPathComponent, privacy: .public)'"
        )
        // BUG-021 diagnostic (2026-05-28): synchronous session.log breadcrumbs
        // at each advance step so the next capture pinpoints where a
        // user-pressed Next hangs (session 2026-05-28T19-04-51Z froze + force-
        // quit). lfLogger writes to os.log; sessionRecorder writes to
        // session.log on the call thread. If a step blocks MainActor, the
        // last successfully-logged step identifies the culprit.
        sessionRecorder?.log(
            "WIRING: advanceLocalFileQueue ENTER from=\(currentIdx) to=\(nextIdx) " +
            "file='\(nextURL.lastPathComponent)' direction=\(direction)"
        )

        if #available(macOS 14.2, *), let audioRouter = router as? AudioInputRouter {
            sessionRecorder?.log("WIRING: advanceLocalFileQueue audioRouter.stop BEGIN")
            audioRouter.stop()
            sessionRecorder?.log("WIRING: advanceLocalFileQueue audioRouter.stop COMPLETE")
            // LF.5.fix.2-FU3: mirror the streaming track-change callback's
            // destructive resets at `VisualizerEngine+Capture.swift:203-204`.
            // Without these the LF advance path leaves `mir.elapsedSeconds` and
            // the renderer's accumulated audio time growing session-monotonic
            // across track boundaries — visible in the `Orchestrator: wire
            // active` log line's `elapsedTrackTime=` field (verification log
            // 2026-05-28T19-42-50Z: 10.9 s → 23.0 s → 35.1 s instead of
            // resetting near 0 on each press) and also wrong-shaped for every
            // other consumer of `mir.elapsedSeconds` (FFO cold-start fix via
            // `fv.trackElapsedS`, featureStability ramp-up curve, recording
            // playbackTime). Single call here restores per-track semantics for
            // every consumer.
            mirPipeline.reset()
            pipeline.resetAccumulatedAudioTime()
            resetStemPipeline(for: nextIdentity, caller: .trackChange)
            sessionRecorder?.log("WIRING: advanceLocalFileQueue resetStemPipeline COMPLETE")
            // LF.5.fix D-LF5-1 + LF.6: orchestrator plan-mode wire + chrome
            // surface publish via the shared helper. See
            // `applyLocalFileTrackState(...)`.
            applyLocalFileTrackState(identity: nextIdentity, planIndex: nextIdx)
            sessionRecorder?.log("WIRING: advanceLocalFileQueue orchestratorLock COMPLETE")
            // BUG-044: mirror the streaming callback's per-track PRESET resets (Nimbus settle +
            // Skein §1.5 canvas wipe/reseed). Before this call existed, a local-file next/prev/EOF
            // advance never wiped Skein's canvas — the painting accumulated across tracks
            // (Matt's live read, session 2026-06-10T19-48-27Z: five track changes with Skein
            // active, zero wipes). Must run AFTER `applyLocalFileTrackState` — the Skein reseed
            // derives from `lastResolvedTrackIdentity`, which that helper sets.
            resetPerTrackPresetState()
            sessionRecorder?.log("WIRING: advanceLocalFileQueue resetPerTrackPresetState COMPLETE")
            // Re-bind the EOF callback BEFORE start() — AudioInputRouter
            // captures the callback at start time and relays it into the
            // freshly-constructed provider.
            audioRouter.onLocalFilePlaybackEnded = { [weak self] in
                Task { @MainActor in self?.advanceLocalFileQueue() }
            }
            do {
                sessionRecorder?.log("WIRING: advanceLocalFileQueue audioRouter.start BEGIN")
                try audioRouter.start(mode: .localFilePlayback(nextURL))
                sessionRecorder?.log("WIRING: advanceLocalFileQueue audioRouter.start COMPLETE")
                currentTrackIndex = nextIdx
                isLocalFilePaused = false                                   // restart implies playing
                sessionRecorder?.log("WIRING: advanceLocalFileQueue EXIT ok=true")
            } catch {
                handleAdvanceStartFailure(error, url: nextURL, index: nextIdx, direction: direction)
            }
        }
    }

    /// PUB.5 (ultra-review): a mid-queue file failed to start. The chrome for
    /// `index` was already published, so commit the index (chrome-consistent),
    /// toast the failure (§9.4, 4 s auto-dismiss), and try the NEXT entry in
    /// the same direction — terminating at queue end (`endSession`) or the
    /// first playable file. Each broken file gets its own named toast.
    @MainActor
    private func handleAdvanceStartFailure(
        _ error: Error, url: URL, index: Int, direction: LocalFileQueueDirection
    ) {
        let msg = error.localizedDescription
        lfLogger.error("[LF.5] audio router restart failed: \(msg, privacy: .public)")
        sessionRecorder?.log("WIRING: advanceLocalFileQueue EXIT ok=false error='\(msg)'")
        userFacingErrorSubject.send(.localFilePlaybackFailed(fileName: url.lastPathComponent))
        currentTrackIndex = index
        advanceLocalFileQueue(direction: direction)
    }

    // MARK: - LF.5.fix transport controls (D-LF5-3)

    /// Toggle the LF audio router between paused and playing. Drives the
    /// transport bar's Play/Pause glyph via the `isLocalFilePaused` publisher.
    /// No-op when no LF session is active.
    @MainActor
    func togglePauseLocalFile() {
        guard sessionManager.currentSource?.isLocalFile == true else { return }
        if #available(macOS 14.2, *), let audioRouter = router as? AudioInputRouter {
            if isLocalFilePaused {
                audioRouter.resumeLocalFilePlayback()
                isLocalFilePaused = false
                lfLogger.info("[LF.5] transport: resume")
            } else {
                audioRouter.pauseLocalFilePlayback()
                isLocalFilePaused = true
                lfLogger.info("[LF.5] transport: pause")
            }
        }
    }

    /// Skip to the next track in the LF queue. End-of-queue transitions the
    /// session to `.ended` (same behaviour as natural EOF advance).
    @MainActor
    func skipToNextLocalFileTrack() {
        guard sessionManager.currentSource?.isLocalFile == true else { return }
        lfLogger.info("[LF.5] transport: next")
        advanceLocalFileQueue(direction: .forward)
    }

    /// Skip back to the previous track in the LF queue. No-op at index 0
    /// (matches standard music-player UX — there is no track before the
    /// first one).
    @MainActor
    func skipToPreviousLocalFileTrack() {
        guard sessionManager.currentSource?.isLocalFile == true else { return }
        lfLogger.info("[LF.5] transport: prev")
        advanceLocalFileQueue(direction: .backward)
    }

    /// Stop LF playback and end the session. Drives the transport bar's Stop
    /// button. Equivalent to clicking "End session" on the existing chrome —
    /// triggers the D-LF5-2 .ended observer to tear down the audio router.
    @MainActor
    func stopLocalFilePlayback() {
        guard sessionManager.currentSource?.isLocalFile == true else { return }
        lfLogger.info("[LF.5] transport: stop")
        sessionManager.endSession()
    }

    // MARK: - LF.6 chrome publishers

    /// Apply the per-LF-track state mutations that both `handleLocalFileReady`
    /// and `advanceLocalFileQueue` need: latch the resolved identity, update
    /// the orchestrator wire's plan index + per-track diagnostic latch, and
    /// publish the chrome surface (TrackMetadata + artwork). Single helper so
    /// the two call sites stay under SwiftLint's function-body-length cap and
    /// can't drift out of sync.
    @MainActor
    private func applyLocalFileTrackState(identity: TrackIdentity, planIndex: Int) {
        lastResolvedTrackIdentity = identity
        orchestratorLock.withLock {
            liveTrackPlanIndex = planIndex
            orchestratorWireLoggedThisTrack = false
            // LFPLAN.3: new track → plan resumes (clear manual hold) + first planned
            // segment applies (clear the last-applied marker).
            manualPresetOverrideThisTrack = false
            lastAppliedPlannedPresetID = nil
            // LFPLAN.4: reset the min-dwell clock so the new track's first apply lands promptly.
            lastPlannedApplyTrackTime = 0
        }
        publishLocalFileTrackSurface(identity: identity)
    }

    /// Publish the `TrackMetadata` + artwork bytes that drive `TrackInfoCardView`.
    /// Both writes land back-to-back inside this @MainActor method so chrome
    /// consumers observe title + artwork updates as one tick (avoids the "—" +
    /// artwork flash documented on `currentTrackArtworkData`).
    @MainActor
    private func publishLocalFileTrackSurface(identity: TrackIdentity) {
        // Title-first.
        currentTrack = TrackMetadata(
            title: identity.title,
            artist: identity.artist,
            album: identity.album,
            duration: identity.duration,
            source: .unknown
        )
        // Artwork-second. Synchronous disk read on the LF persistent cache —
        // ~5–20 ms on warm OS file cache (post-LF.5 prep), bounded once per
        // track change. Failures (no cache, missing entry, art-free track)
        // surface as nil, which the chrome renders as the fallback glyph.
        currentTrackArtworkData = lfPersistentArtworkData(for: identity)
    }

    /// Look up the LF.5-cached artwork bytes for a synthetic `local:sha256:`
    /// identity. Returns nil for non-LF identities, missing persistent cache,
    /// or tracks whose source file shipped no embedded artwork. The
    /// `persistentStemCache.load(hash:)` call is NSLock-serialized internally
    /// so this is safe to invoke from any actor context.
    @MainActor
    private func lfPersistentArtworkData(for identity: TrackIdentity) -> Data? {
        let prefix = "local:sha256:"
        guard let spotifyID = identity.spotifyID, spotifyID.hasPrefix(prefix) else {
            return nil
        }
        let hash = String(spotifyID.dropFirst(prefix.count))
        guard let cache = persistentStemCache else { return nil }
        guard let entry = try? cache.load(hash: hash) else { return nil }
        return entry.artworkData
    }

    // MARK: - Off-main worker

    /// Off-main worker that hashes the file, consults the persistent disk
    /// cache, and either loads the cached entry or runs the full
    /// `analyzePreview` pipeline and persists the result. Returns `nil`
    /// when neither path produces a usable `CachedTrackData` (no separator,
    /// decode error, etc.) — the caller then falls through to the LF.1
    /// no-cache start.
    nonisolated static func runLocalFilePreparation(
        inputs: LocalFilePrepWorkerInputs
    ) async -> LocalFilePrepResult? {
        let contentHash: String
        do {
            contentHash = try PreviewAudio.sha256(of: inputs.url)
        } catch {
            let msg = error.localizedDescription
            lfLogger.error(
                "[LF.4] sha256 failed: \(msg, privacy: .public) — falling through to no-cache start"
            )
            return nil
        }
        let shortHash = String(contentHash.prefix(12))

        if let hit = tryLoadFromPersistentCache(
            inputs: inputs,
            contentHash: contentHash,
            shortHash: shortHash
        ) {
            return hit
        }

        return await analyzeAndPersist(
            inputs: inputs,
            contentHash: contentHash,
            shortHash: shortHash
        )
    }

    /// Consult the persistent cache. Returns the loaded outcome on hit,
    /// `nil` on miss (no entry, load failed, or no cache configured).
    /// Emits a `STEM_CACHE_HIT` / `STEM_CACHE_MISS` log line in every branch.
    nonisolated private static func tryLoadFromPersistentCache(
        inputs: LocalFilePrepWorkerInputs,
        contentHash: String,
        shortHash: String
    ) -> LocalFilePrepResult? {
        guard let persistentCache = inputs.persistentCache else { return nil }
        guard persistentCache.contains(hash: contentHash) else {
            let msg = "STEM_CACHE_MISS: source=persistentDisk, track='\(inputs.filename)', "
                + "hash=\(shortHash), reason=no-entry"
            inputs.recorder?.log(msg)
            lfLogger.info("\(msg, privacy: .public)")
            return nil
        }
        do {
            let entry = try persistentCache.load(hash: contentHash)
            let identity = makeLocalFileIdentity(
                filename: inputs.filename,
                contentHash: contentHash,
                duration: entry.decodedDuration,
                metadata: entry.metadata
            )
            let cached = entry.cached
            let bpmStr = String(format: "%.1f", cached.beatGrid.bpm)
            let beatCount = cached.beatGrid.beats.count
            let titleLabel = entry.metadata.title ?? inputs.filename
            let msg = "STEM_CACHE_HIT: source=persistentDisk, track='\(titleLabel)', "
                + "hash=\(shortHash), bpm=\(bpmStr), beats=\(beatCount)"
            inputs.recorder?.log(msg)
            lfLogger.info("\(msg, privacy: .public)")
            return LocalFilePrepResult(
                identity: identity,
                cached: cached,
                decodedDuration: entry.decodedDuration,
                source: .persistentDisk,
                artworkData: entry.artworkData
            )
        } catch {
            let msg = "STEM_CACHE_MISS: source=persistentDisk, track='\(inputs.filename)', "
                + "hash=\(shortHash), reason=load-failed(\(error.localizedDescription))"
            inputs.recorder?.log(msg)
            lfLogger.warning("\(msg, privacy: .public)")
            return nil
        }
    }

    /// Run `analyzePreview`, persist the result to disk, return the outcome.
    /// Returns `nil` when the separator is missing or the analysis pipeline
    /// throws. Persist failure is non-fatal — logs a warning and still returns
    /// the in-memory outcome so the live pipeline gets the install.
    nonisolated private static func analyzeAndPersist(
        inputs: LocalFilePrepWorkerInputs,
        contentHash: String,
        shortHash: String
    ) async -> LocalFilePrepResult? {
        guard let separator = inputs.separator else {
            lfLogger.warning("[LF.4] no stem separator — continuing without cached install")
            return nil
        }
        let extracted = await PreviewAudio.extractMetadata(at: inputs.url)
        let artwork = await PreviewAudio.extractArtwork(at: inputs.url)
        let preview: PreviewAudio
        let cached: CachedTrackData
        do {
            preview = try PreviewAudio.fromLocalFile(at: inputs.url, contentHash: contentHash)
            cached = try SessionPreparer.analyzePreview(
                preview,
                separator: separator,
                analyzer: inputs.analyzer,
                classifier: inputs.classifier,
                beatGridAnalyzer: inputs.beatGridAnalyzer,
                familyAnalyzer: inputs.familyAnalyzer,
                prefetchedProfile: nil
            )
        } catch {
            let msg = error.localizedDescription
            lfLogger.error(
                "[LF.4] pre-analysis failed: \(msg, privacy: .public) — continuing uncached"
            )
            return nil
        }

        let outcome = FreshAnalysisOutcome(
            cached: cached,
            preview: preview,
            metadata: extracted,
            artwork: artwork
        )
        persistToDisk(
            inputs: inputs,
            outcome: outcome,
            contentHash: contentHash,
            shortHash: shortHash
        )

        let identity = makeLocalFileIdentity(
            filename: inputs.filename,
            contentHash: contentHash,
            duration: preview.duration,
            metadata: extracted
        )
        return LocalFilePrepResult(
            identity: identity,
            cached: cached,
            decodedDuration: preview.duration,
            source: .freshAnalysis,
            artworkData: outcome.artwork
        )
    }

    /// Write the freshly-analyzed entry + AVAsset-extracted metadata + optional
    /// artwork bytes to disk. Persist failure is non-fatal — logged and
    /// swallowed so the live pipeline still gets the in-memory install.
    nonisolated private static func persistToDisk(
        inputs: LocalFilePrepWorkerInputs,
        outcome: FreshAnalysisOutcome,
        contentHash: String,
        shortHash: String
    ) {
        guard let persistentCache = inputs.persistentCache else { return }
        let writeStart = Date()
        do {
            try persistentCache.store(
                outcome.cached,
                hash: contentHash,
                decodedDuration: outcome.preview.duration,
                metadata: outcome.metadata,
                artworkData: outcome.artwork
            )
            let elapsedMs = Int(Date().timeIntervalSince(writeStart) * 1000)
            let totalSamples = outcome.cached.stemWaveforms.reduce(0) { $0 + $1.count }
            let stemBytes = totalSamples * MemoryLayout<Float>.size
            let artworkBytes = outcome.artwork?.count ?? 0
            let msg = "STEM_CACHE_WROTE: source=persistentDisk, track='\(inputs.filename)', "
                + "hash=\(shortHash), bytes=\(stemBytes), artworkBytes=\(artworkBytes), "
                + "elapsedMs=\(elapsedMs)"
            inputs.recorder?.log(msg)
            lfLogger.info("\(msg, privacy: .public)")
        } catch {
            let msg = error.localizedDescription
            lfLogger.warning(
                "[LF.4] persistent cache store failed: \(msg, privacy: .public)"
            )
        }
    }

    /// Build the LF.3 `local:sha256:<hash>` synthetic identity, layering in any
    /// `AVAsset.commonMetadata` overrides for title / artist / album. Filename
    /// is the fallback title; "local file" is the fallback artist (LF.4-shape).
    /// Centralized so the cache-hit and fresh-analyze paths produce
    /// byte-identical identities for the same inputs.
    nonisolated private static func makeLocalFileIdentity(
        filename: String,
        contentHash: String,
        duration: TimeInterval,
        metadata: LocalFileMetadata
    ) -> TrackIdentity {
        TrackIdentity(
            title: metadata.title ?? filename,
            artist: metadata.artist ?? "local file",
            album: metadata.album,
            duration: duration,
            spotifyID: "local:sha256:" + contentHash
        )
    }
}

// MARK: - Worker inputs

/// Bundle of injected dependencies the LF.4 off-main worker reads.
/// Collapses what would otherwise be an 8-parameter call into one,
/// and keeps the worker itself Sendable-safe (every field is either
/// an immutable value or a Sendable reference type).
struct LocalFilePrepWorkerInputs: Sendable {
    let url: URL
    let filename: String
    let separator: StemSeparator?
    let analyzer: StemAnalyzer
    let classifier: any MoodClassifying
    let beatGridAnalyzer: (any BeatGridAnalyzing)?
    let familyAnalyzer: (any InstrumentFamilyAnalyzing)?
    let persistentCache: PersistentStemCache?
    let recorder: SessionRecorder?
}

/// LF.5 fresh-analysis output bundle. Collapses the four values the
/// `analyzeAndPersist` worker hands to `persistToDisk` (cached + preview
/// + metadata + artwork) into one parameter so the persist helper stays
/// under SwiftLint's 5-param cap.
private struct FreshAnalysisOutcome: Sendable {
    let cached: CachedTrackData
    let preview: PreviewAudio
    let metadata: LocalFileMetadata
    let artwork: Data?
}
