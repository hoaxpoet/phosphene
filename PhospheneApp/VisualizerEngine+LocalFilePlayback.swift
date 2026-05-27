// VisualizerEngine+LocalFilePlayback — LF.4 / D-131.
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
    /// file. Installs the cached BeatGrid (cache lookup hits the in-memory
    /// `StemCache` that SessionManager populated during preparation), starts
    /// the LF audio router, and advances the session to `.playing`.
    @MainActor
    func handleLocalFileReady() {
        guard let source = sessionManager.currentSource,
              case .localFile(let url) = source else {
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

        // Start the LF audio router (AVAudioEngine path). On success the audio
        // thread begins delivering samples immediately; on failure the LF.1
        // live-only fallthrough still gets the user playback via the live
        // beat-grid analyzer once it catches up.
        if #available(macOS 14.2, *), let audioRouter = router as? AudioInputRouter {
            do {
                try audioRouter.start(mode: .localFilePlayback(url))
                lfLogger.info("[LF.4] LF playback router started: \(url.lastPathComponent, privacy: .public)")
            } catch {
                let msg = error.localizedDescription
                lfLogger.error("[LF.4] LF playback router start failed: \(msg, privacy: .public)")
                // Audio router failed; don't advance the session — leave it in .ready.
                // The user sees PlaybackView mounting on the next .playing transition
                // (which won't fire here). Surface this as a toast in a future increment.
                return
            }
        }

        startStemPipeline()

        // Advance .ready → .playing through the canonical SessionManager API.
        sessionManager.beginPlayback()

        if let current = presetLoader.currentPreset {
            applyPreset(current)
            showPresetName(current.descriptor.name)
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

        return analyzeAndPersist(
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
            let identity = TrackIdentity(
                title: inputs.filename,
                artist: "local file",
                duration: entry.decodedDuration,
                spotifyID: "local:sha256:" + contentHash
            )
            let cached = entry.cached
            let bpmStr = String(format: "%.1f", cached.beatGrid.bpm)
            let beatCount = cached.beatGrid.beats.count
            let msg = "STEM_CACHE_HIT: source=persistentDisk, track='\(inputs.filename)', "
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
    ) -> LocalFilePrepResult? {
        guard let separator = inputs.separator else {
            lfLogger.warning("[LF.4] no stem separator — continuing without cached install")
            return nil
        }
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

        if let persistentCache = inputs.persistentCache {
            let writeStart = Date()
            do {
                try persistentCache.store(
                    cached,
                    hash: contentHash,
                    decodedDuration: preview.duration
                )
                let elapsedMs = Int(Date().timeIntervalSince(writeStart) * 1000)
                let totalSamples = cached.stemWaveforms.reduce(0) { $0 + $1.count }
                let bytes = totalSamples * MemoryLayout<Float>.size
                let msg = "STEM_CACHE_WROTE: source=persistentDisk, track='\(inputs.filename)', "
                    + "hash=\(shortHash), bytes=\(bytes), elapsedMs=\(elapsedMs)"
                inputs.recorder?.log(msg)
                lfLogger.info("\(msg, privacy: .public)")
            } catch {
                let msg = error.localizedDescription
                lfLogger.warning(
                    "[LF.4] persistent cache store failed: \(msg, privacy: .public)"
                )
            }
        }

        return LocalFilePrepResult(
            identity: preview.trackIdentity,
            cached: cached,
            decodedDuration: preview.duration,
            source: .freshAnalysis
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
