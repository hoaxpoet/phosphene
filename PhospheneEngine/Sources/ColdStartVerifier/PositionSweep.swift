// PositionSweep — BSAudit.2 (Path A.1): within-capture Beat This! position sensitivity.
//
// Per the BSAudit deliverable (`docs/CAPABILITY_REGISTRY/BEAT_SYNC.md`), the
// CS.1.y.2-redo cycle exposed cross-capture non-reproducibility of Beat This!
// on 15-second tap slices. The audit could not separate two candidate causes
// from existing artifacts:
//
//   (A) Beat This! is *position-sensitive* on a 25 s slice — different slice
//       offsets within the same audio produce different beat positions.
//   (B) Beat This! is *capture-sensitive* — same physical preview, two captures,
//       produces different beat positions because the tap audio differs.
//
// This module addresses candidate (A). For each track, Beat This! is run on a
// 25 s slice at multiple sliding positions (default stride 10 s) within ONE
// session's audio. Per-position phase residuals vs position-0 are tabulated.
// Reporting lives in `PositionSweepReport.swift`.
//
// No production code touched. Audit-only / research-only.

import Foundation
import Session

enum PositionSweep {

    // MARK: - Tunables

    /// Default Beat This! slice length (s).
    static let defaultSliceDurationS: Double = 25.0
    /// Default stride between sliding slice positions (s).
    static let defaultPositionStrideS: Double = 10.0
    /// Maximum number of positions to try per track.
    static let maxPositions: Int = 6
    /// "Viable" gate vs position-0 reference.
    static let viablePhaseErrorMs: Double = 30.0
    static let viableResultant: Double = 0.90
    /// Minimum reference beats to consider this track measurable.
    static let minReferenceBeats: Int = 8
    /// Spread > this (ms) across positions flags the track as position-unstable.
    static let unstableSpreadMs: Double = 50.0

    // MARK: - Config (bundle so signatures stay short)

    struct Config {
        let sliceDurationS: Double
        let positionStrideS: Double

        static let `default` = Config(
            sliceDurationS: defaultSliceDurationS,
            positionStrideS: defaultPositionStrideS)
    }

    // MARK: - Result model

    struct PositionResult {
        let positionS: Double
        let beatCount: Int
        let gridBPM: Double
        let phaseErrorMs: Double
        let resultant: Double
        var hasUsableGrid: Bool { beatCount >= 4 }
        var viable: Bool {
            hasUsableGrid && abs(phaseErrorMs) <= viablePhaseErrorMs
                && resultant >= viableResultant
        }
    }

    struct TrackResult {
        let label: String
        let trackIndex: Int
        let referenceBeatCount: Int
        let referenceBPM: Double
        let referencePositionS: Double
        let positions: [PositionResult]
        let phaseSpreadMs: Double
        let flagged: Bool
        let flagReason: String?
    }

    // MARK: - Run

    static func run(
        tracks: [TrackSegment],
        rawTap: RawTapAnalysis,
        rawTapStartWallclockS: Double?,
        analyzer: DefaultBeatGridAnalyzer,
        config: Config = .default
    ) -> [TrackResult] {
        tracks.enumerated().map { idx, track in
            print("  [\(idx + 1)/\(tracks.count)] \(track.label) — position-sweep …")
            return analyzeTrack(
                track: track,
                rawTap: rawTap,
                rawTapStartWallclockS: rawTapStartWallclockS,
                analyzer: analyzer,
                config: config)
        }
    }

    private static func analyzeTrack(
        track: TrackSegment,
        rawTap: RawTapAnalysis,
        rawTapStartWallclockS: Double?,
        analyzer: DefaultBeatGridAnalyzer,
        config: Config
    ) -> TrackResult {
        guard let rawStart = rawTapStartWallclockS, let first = track.frames.first else {
            return flaggedResult(track: track, reason: "no raw-tap-start anchor")
        }
        let beatBass = ColdStartAnalysis.beatBassOnsets(frames: track.frames)
        let coarse = (first.wallclockS - rawStart) - first.playbackTimeS
        let offsetS = ClockOffset.estimate(
            rawOnsets: rawTap.onsets,
            beatBassOnsets: beatBass,
            coarseS: coarse)
        let trackStartRawTap = first.playbackTimeS + offsetS
        let trackEndRawTap = track.lastPlaybackTimeS + offsetS
        let availableDuration = trackEndRawTap - trackStartRawTap
        guard availableDuration >= config.sliceDurationS else {
            let reason = "track has only \(String(format: "%.1f", availableDuration)) s "
                + "in raw_tap (< \(String(format: "%.0f", config.sliceDurationS)) s slice)"
            return flaggedResult(track: track, reason: reason)
        }
        let positions = derivedPositions(
            availableDuration: availableDuration,
            sliceDurationS: config.sliceDurationS,
            stride: config.positionStrideS)
        let context = MeasureContext(
            trackStartRawTap: trackStartRawTap,
            offsetS: offsetS,
            sliceDurationS: config.sliceDurationS,
            rawTap: rawTap,
            analyzer: analyzer)
        return analyzePositions(
            track: track,
            positions: positions,
            context: context)
    }

    /// Stage two of analyzeTrack — split out so the function body stays under the
    /// SwiftLint length cap. Runs Beat This! at position 0 (reference) and at
    /// every position, then assembles the final result.
    private static func analyzePositions(
        track: TrackSegment,
        positions: [Double],
        context: MeasureContext
    ) -> TrackResult {
        let referenceBeatsRaw = BeatThisGrid.beats(
            samples: context.rawTap.samples,
            sampleRate: context.rawTap.sampleRate,
            sliceStartS: context.trackStartRawTap,
            durationS: context.sliceDurationS,
            analyzer: context.analyzer)
        let referenceBeats = referenceBeatsRaw.map { $0 - context.offsetS }
        let refPeriod = BeatPhaseStats.medianIOI(referenceBeats)
        let refBPM = refPeriod > 0 ? 60.0 / refPeriod : 0
        guard referenceBeats.count >= minReferenceBeats, refPeriod > 0 else {
            return flaggedResult(
                track: track,
                referenceBeatCount: referenceBeats.count,
                referenceBPM: refBPM,
                reason: "Beat This! found only \(referenceBeats.count) beats at "
                    + "position 0 — unreliable reference on this track")
        }
        let positionResults = positions.map { positionS in
            measurePosition(
                positionS: positionS,
                context: context,
                reference: referenceBeats,
                refPeriod: refPeriod)
        }
        let offsets = positionResults.map(\.phaseErrorMs)
        let spread = (offsets.max() ?? 0) - (offsets.min() ?? 0)
        let unstable = spread > unstableSpreadMs
        let reason = unstable
            ? "phase spans \(Int(spread.rounded())) ms across "
                + "\(positionResults.count) positions — Beat This! is position-sensitive "
                + "on this track"
            : nil
        return TrackResult(
            label: track.label,
            trackIndex: track.index,
            referenceBeatCount: referenceBeats.count,
            referenceBPM: refBPM,
            referencePositionS: 0,
            positions: positionResults,
            phaseSpreadMs: spread,
            flagged: unstable,
            flagReason: reason)
    }

    /// Per-position fixed inputs grouped to keep `measurePosition` under the
    /// SwiftLint parameter-count cap.
    private struct MeasureContext {
        let trackStartRawTap: Double
        let offsetS: Double
        let sliceDurationS: Double
        let rawTap: RawTapAnalysis
        let analyzer: DefaultBeatGridAnalyzer
    }

    /// Run Beat This! on `positionS` and score it against the reference grid.
    private static func measurePosition(
        positionS: Double,
        context: MeasureContext,
        reference: [Double],
        refPeriod: Double
    ) -> PositionResult {
        let sliceStartRaw = context.trackStartRawTap + positionS
        let beatsRaw = BeatThisGrid.beats(
            samples: context.rawTap.samples,
            sampleRate: context.rawTap.sampleRate,
            sliceStartS: sliceStartRaw,
            durationS: context.sliceDurationS,
            analyzer: context.analyzer)
        let beats = beatsRaw.map { $0 - context.offsetS }
        let stats = BeatPhaseStats.phaseOffset(
            of: beats,
            vs: reference,
            period: refPeriod)
        let period = BeatPhaseStats.medianIOI(beats).nonZeroOr(refPeriod)
        return PositionResult(
            positionS: positionS,
            beatCount: beats.count,
            gridBPM: period > 0 ? 60.0 / period : 0,
            phaseErrorMs: stats.offsetMs,
            resultant: stats.resultant)
    }

    /// Sliding positions: 0, stride, 2×stride, … capped at `maxPositions`.
    private static func derivedPositions(
        availableDuration: Double,
        sliceDurationS: Double,
        stride: Double
    ) -> [Double] {
        guard stride > 0, availableDuration >= sliceDurationS else { return [0] }
        let lastStart = availableDuration - sliceDurationS
        var positions: [Double] = []
        var pos = 0.0
        while pos <= lastStart && positions.count < maxPositions {
            positions.append(pos)
            pos += stride
        }
        if let last = positions.last,
           last < lastStart - 0.5,
           positions.count < maxPositions {
            positions.append(lastStart)
        }
        return positions
    }

    /// Build a flagged-track result without measurable positions.
    private static func flaggedResult(
        track: TrackSegment,
        referenceBeatCount: Int = 0,
        referenceBPM: Double = 0,
        reason: String
    ) -> TrackResult {
        TrackResult(
            label: track.label,
            trackIndex: track.index,
            referenceBeatCount: referenceBeatCount,
            referenceBPM: referenceBPM,
            referencePositionS: 0,
            positions: [],
            phaseSpreadMs: 0,
            flagged: true,
            flagReason: reason)
    }

    // MARK: - Console summary (full report lives in PositionSweepReport.swift)

    static func consoleSummary(_ results: [TrackResult]) -> String {
        var lines = ["BSAudit.2 (Path A.1) — within-capture Beat This! position sensitivity"]
        for result in results {
            if result.positions.isEmpty {
                lines.append("  [FLAG] \(result.label) — \(result.flagReason ?? "no data")")
                continue
            }
            let cells = result.positions.map { cellText($0) }
            let flag = result.flagged ? "  ⚠ \(result.flagReason ?? "")" : ""
            lines.append("  \(result.label) — \(cells.joined(separator: "  "))\(flag)")
        }
        let unstable = results.filter { $0.flagged && !$0.positions.isEmpty }.count
        let rated = results.filter { !$0.positions.isEmpty }.count
        lines.append("  \(unstable)/\(rated) tracks position-unstable "
            + "(phase spread > \(Int(unstableSpreadMs)) ms)")
        return lines.joined(separator: "\n")
    }

    private static func cellText(_ position: PositionResult) -> String {
        let pos = String(format: "%.0f", position.positionS)
        guard position.hasUsableGrid else {
            return "+\(pos)s empty(\(position.beatCount)b)"
        }
        let mark = position.viable ? "✓" : "✗"
        let off = String(format: "%+.0f", position.phaseErrorMs)
        return "+\(pos)s \(off)ms\(mark)"
    }
}

extension Double {
    /// Replace 0 with a fallback (BPM recovery when a single-beat grid is returned).
    fileprivate func nonZeroOr(_ fallback: Double) -> Double { self == 0 ? fallback : self }
}
