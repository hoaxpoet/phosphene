// LocalFilePreparationPipeline — the local-file preparation worker.
//
// Moved here verbatim from `VisualizerEngine+LocalFilePlayback.swift` at PREP.1
// (LF.4 / D-131 + LF.5 / D-132 behaviour unchanged — this is a relocation, not
// a rewrite). It sat in the app layer only because that is where the ML
// dependencies are constructed; every function in it is `nonisolated static`
// and every type it touches is an engine type, so nothing about it needed to
// be app-side.
//
// It moved because PREP.1 has to *measure* it, and the measurement has to run
// without a window server: `PrepTimingRunner` and `VisualizerEngine` now drive
// the same code, so the numbers in `docs/diagnostics/PREP1_*` describe the
// pipeline that actually ships rather than a copy of it that drifts.
//
// Stage timing (`PrepStageProbe`) is threaded through the call chain. In
// production the probe is `.disabled` unless `UZUME_PREP_TIMING=1` — see
// `PrepStageTiming.swift`.

import Audio
import DSP
import Foundation
import Shared
import os.log

private let lfLogger = Logger(subsystem: "io.uzume.mac", category: "LocalFilePrep")

// MARK: - Fresh-analysis bundle

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

// MARK: - Pipeline

public enum LocalFilePreparationPipeline {

    /// Hash the file, consult the persistent disk cache, and either load the
    /// cached entry or run the full analysis pipeline and persist the result.
    /// Returns `nil` when neither path produces a usable `CachedTrackData`
    /// (no separator, decode error, etc.) — the caller then falls through to
    /// the LF.1 no-cache start.
    public static func run(inputs: LocalFilePrepWorkerInputs) async -> LocalFilePrepResult? {
        let trackStart = Date()
        let trackCPU0 = PrepStageSink.cpuSeconds()
        var probe = PrepStageProbe(sink: inputs.timingSink, track: inputs.filename)

        let contentHash: String
        do {
            contentHash = try probe.measure(PrepStage.contentHash) {
                try PreviewAudio.sha256(of: inputs.url)
            }
        } catch {
            let msg = error.localizedDescription
            lfLogger.error(
                "[LF.4] sha256 failed: \(msg, privacy: .public) — falling through to no-cache start"
            )
            return nil
        }
        let shortHash = String(contentHash.prefix(12))

        let hit = probe.measure(PrepStage.cacheProbe) {
            tryLoadFromPersistentCache(
                inputs: inputs,
                contentHash: contentHash,
                shortHash: shortHash
            )
        }
        if let hit {
            probe = probe.notingAudioSeconds(hit.decodedDuration)
            recordTrackTotal(probe, since: trackStart, cpu0: trackCPU0)
            return hit
        }

        let result = await analyzeAndPersist(
            inputs: inputs,
            contentHash: contentHash,
            shortHash: shortHash,
            probe: probe
        )
        recordTrackTotal(
            probe.notingAudioSeconds(result?.decodedDuration ?? 0),
            since: trackStart,
            cpu0: trackCPU0
        )
        return result
    }

    private static func recordTrackTotal(_ probe: PrepStageProbe, since start: Date, cpu0: Double) {
        guard probe.isEnabled else { return }
        probe.record(
            PrepStage.trackTotal,
            wallMs: Date().timeIntervalSince(start) * 1000,
            cpuMs: (PrepStageSink.cpuSeconds() - cpu0) * 1000
        )
    }

    /// Consult the persistent cache. Returns the loaded outcome on hit,
    /// `nil` on miss (no entry, load failed, or no cache configured).
    /// Emits a `STEM_CACHE_HIT` / `STEM_CACHE_MISS` log line in every branch.
    static func tryLoadFromPersistentCache(
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

    /// The two full-file analyses the local path can do and streaming cannot, plus the shared
    /// `analyzePreview`.
    ///
    /// Both extras exist for the same reason: this path has decoded the entire track, where
    /// `analyzePreview` is shared with streaming and only ever sees a 30 s preview window.
    /// `LoudnessProfile` (DYN.1c) is the track's own quiet-to-loud range; `StemFeatureSeries`
    /// (LFSTEM.1) is its stems at every playback second.
    static func analyzeWholeFile(
        preview: PreviewAudio,
        separator: any StemSeparating,
        inputs: LocalFilePrepWorkerInputs,
        probe: PrepStageProbe
    ) throws -> CachedTrackData {
        let loudness = probe.measure(PrepStage.loudness) {
            LoudnessProfile.measure(
                samples: preview.pcmSamples,
                sampleRate: Double(preview.sampleRate)
            )
        }
        inputs.recorder?.log(
            "LOUDNESS_PROFILE: track='\(inputs.filename)', "
            + (loudness?.summary ?? "none — surge keeps the fixed band"))
        let analyzed = try SessionPreparer.analyzePreview(
            preview,
            separator: separator,
            analyzer: inputs.analyzer,
            classifier: inputs.classifier,
            beatGridAnalyzer: inputs.beatGridAnalyzer,
            familyAnalyzer: inputs.familyAnalyzer,
            prefetchedProfile: nil,
            // PR.12 — this call site holds the WHOLE decoded file (same reason it can
            // measure `loudnessProfile` and streaming cannot, DYN.1c). Without this the
            // beat grid covered 6.7–11.4 % of the track and everything past it ran on one
            // averaged BPM, which is BUG-065's drift.
            wholeTrackAudio: true,
            probe: probe
        )
        let series = analyzeStemSeriesForLocalFile(
            preview: preview,
            separator: separator,
            filename: inputs.filename,
            recorder: inputs.recorder,
            probe: probe
        )
        return analyzed
            .with(loudnessProfile: loudness)
            .with(stemFeatureSeries: series)
    }

    /// LFSTEM.1 — sweep the whole decoded file into a `StemFeatureSeries`.
    ///
    /// This is the point of the local path. Live separation is late by construction — a 2 s
    /// window plus inference, ~2.5 s before a stem value reaches a preset — but this path has
    /// already decoded the entire file, so the stems can be analysed now and read at the
    /// playback second they describe. Streaming cannot do this and `analyzePreview` is shared
    /// with it, which is why the sweep lives here, next to the loudness profile, for exactly
    /// the same reason.
    ///
    /// A FRESH `StemAnalyzer`, never the session's: the sweep relies on owning its band-energy
    /// AGC across the whole file, and the shared instance is live-playback state.
    ///
    /// Failure returns `.empty`, which leaves live separation in charge — a file that cannot be
    /// swept still plays, just with the old latency.
    static func analyzeStemSeriesForLocalFile(
        preview: PreviewAudio,
        separator: any StemSeparating,
        filename: String,
        recorder: SessionRecorder?,
        probe: PrepStageProbe
    ) -> StemFeatureSeries {
        let start = Date()
        let series = probe.measure(PrepStage.stemSeries) {
            (try? SessionPreparer.analyzeStemSeries(
                samples: preview.pcmSamples,
                sampleRate: preview.sampleRate,
                separator: separator,
                analyzer: StemAnalyzer(sampleRate: Float(preview.sampleRate))
            )) ?? .empty
        }
        let elapsed = Date().timeIntervalSince(start)
        let tail = series.isEmpty ? " — EMPTY, playback falls back to live separation" : ""
        recorder?.log(String(
            format: "STEM_SERIES: track='%@', frames=%d, hop=%.1f ms, covers %.1f s, took %.1f s%@",
            filename,
            series.frames.count,
            series.hopSeconds * 1000,
            series.durationSeconds,
            elapsed,
            tail
        ))
        return series
    }

    /// Run the analysis, persist the result to disk, return the outcome.
    /// Returns `nil` when the separator is missing or the analysis pipeline
    /// throws. Persist failure is non-fatal — logs a warning and still returns
    /// the in-memory outcome so the live pipeline gets the install.
    static func analyzeAndPersist(
        inputs: LocalFilePrepWorkerInputs,
        contentHash: String,
        shortHash: String,
        probe: PrepStageProbe
    ) async -> LocalFilePrepResult? {
        guard let separator = inputs.separator else {
            lfLogger.warning("[LF.4] no stem separator — continuing without cached install")
            return nil
        }
        let (extracted, artwork) = await probe.measureAsync(PrepStage.metadata) {
            (
                await PreviewAudio.extractMetadata(at: inputs.url),
                await PreviewAudio.extractArtwork(at: inputs.url)
            )
        }
        let preview: PreviewAudio
        let cached: CachedTrackData
        do {
            preview = try probe.measure(PrepStage.decode) {
                try PreviewAudio.fromLocalFile(at: inputs.url, contentHash: contentHash)
            }
            cached = try Self.analyzeWholeFile(
                preview: preview,
                separator: separator,
                inputs: inputs,
                probe: probe.notingAudioSeconds(preview.duration))
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
        probe.notingAudioSeconds(preview.duration).measure(PrepStage.cacheWrite) {
            persistToDisk(
                inputs: inputs,
                outcome: outcome,
                contentHash: contentHash,
                shortHash: shortHash
            )
        }

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
    private static func persistToDisk(
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
    static func makeLocalFileIdentity(
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
