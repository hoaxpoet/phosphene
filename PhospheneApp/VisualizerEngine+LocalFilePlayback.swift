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
        guard let identity = sessionManager.currentPlan?.tracks.first else {
            lfLogger.warning("[LF.4] .ready with LF source but no identity in plan — falling through")
            return
        }
        // Install BeatGrid + cached StemFeatures + cached bass proportion from the
        // engine's stemCache (which IS sessionManager.preparer.cache; LF preparation
        // wrote into it).
        resetStemPipeline(for: identity, caller: .other)

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

            // Start the LF audio router (AVAudioEngine path).
            do {
                try audioRouter.start(mode: .localFilePlayback(url))
                lfLogger.info("[LF.4] LF playback router started: \(url.lastPathComponent, privacy: .public)")
            } catch {
                let msg = error.localizedDescription
                lfLogger.error("[LF.4] LF playback router start failed: \(msg, privacy: .public)")
                return
            }
        }

        startStemPipeline()
        currentTrackIndex = 0                               // LF.5: published for chrome + orchestrator

        sessionManager.beginPlayback()

        if let current = presetLoader.currentPreset {
            applyPreset(current)
            showPresetName(current.descriptor.name)
        }

        refreshLocalFileCacheBytes()
    }

    // MARK: - LF.5 mid-session queue advance

    /// Pop the next URL off the LF.5 queue, install its cached BeatGrid via
    /// `resetStemPipeline(caller: .trackChange)`, restart the audio router
    /// with the next file, and bump `currentTrackIndex`. When the queue is
    /// exhausted, transitions the session to `.ended` (matches the streaming-
    /// path "session over" UX). Single-file queues never reach this path
    /// because the EOF callback is unset (file loops forever per Matt's
    /// audit answer).
    @MainActor
    func advanceLocalFileQueue() {
        guard let source = sessionManager.currentSource, source.isLocalFile else { return }
        let urls = source.allLocalFileURLs
        let tracks = sessionManager.currentPlan?.tracks ?? []
        let currentIdx = currentTrackIndex ?? -1
        let nextIdx = currentIdx + 1

        guard nextIdx < urls.count, nextIdx < tracks.count else {
            lfLogger.info("[LF.5] queue exhausted — transitioning to .ended")
            currentTrackIndex = nil
            sessionManager.endSession()
            return
        }

        let nextURL = urls[nextIdx]
        let nextIdentity = tracks[nextIdx]
        lfLogger.info(
            "[LF.5] advance: \(currentIdx) → \(nextIdx), next='\(nextURL.lastPathComponent, privacy: .public)'"
        )

        if #available(macOS 14.2, *), let audioRouter = router as? AudioInputRouter {
            audioRouter.stop()
            resetStemPipeline(for: nextIdentity, caller: .trackChange)
            // Re-bind the EOF callback BEFORE start() — AudioInputRouter
            // captures the callback at start time and relays it into the
            // freshly-constructed provider.
            audioRouter.onLocalFilePlaybackEnded = { [weak self] in
                Task { @MainActor in self?.advanceLocalFileQueue() }
            }
            do {
                try audioRouter.start(mode: .localFilePlayback(nextURL))
                currentTrackIndex = nextIdx
            } catch {
                let msg = error.localizedDescription
                lfLogger.error("[LF.5] audio router restart failed: \(msg, privacy: .public)")
                // Stop advancing — user can re-pick from Recents or pick a new file.
            }
        }
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
                source: .persistentDisk
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
            source: .freshAnalysis
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
