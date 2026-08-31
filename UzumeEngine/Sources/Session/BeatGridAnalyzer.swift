// BeatGridAnalyzer — Offline beat-grid analysis step in the session preparation pipeline.
//
// Wraps Beat This! preprocessing (audio → log-mel spectrogram), MPSGraph inference,
// and BeatGridResolver postprocessing into a single injectable step. The protocol
// matches the StemSeparating / MoodClassifying pattern so SessionPreparer accepts
// the dependency by interface and tests can stub it without Metal.

import DSP
import Foundation
import ML
import Metal
import os.log

private let logger = Logger(subsystem: "io.uzume", category: "BeatGridAnalyzer")

// MARK: - BeatGridAnalyzing

/// Contract for offline beat grid analysis during session preparation.
public protocol BeatGridAnalyzing: Sendable {
    /// Run Beat This! preprocessing + inference + resolver on mono PCM audio.
    ///
    /// - Parameters:
    ///   - samples: Mono Float32 PCM at `sampleRate`.
    ///   - sampleRate: The native sample rate of `samples` (e.g. 44100). The
    ///     preprocessor resamples internally to 22050 Hz.
    /// - Returns: Resolved `BeatGrid`; `.empty` on failure (graceful degradation).
    func analyzeBeatGrid(samples: [Float], sampleRate: Double) -> BeatGrid
}

// MARK: - DefaultBeatGridAnalyzer

/// Production beat-grid analyzer composing `BeatThisPreprocessor` and `BeatThisModel`.
///
/// Both wrapped components are thread-safe (internal locks), so this analyzer is
/// safe to call from any thread. `analyzeBeatGrid` is synchronous and is intended
/// to be invoked from inside `Task.detached` in `SessionPreparer.prepareTrack`.
///
/// Frame rate is fixed at 50.0 fps — Beat This! always processes audio at
/// 22050 Hz with hop=441, giving 22050/441 = 50.0 fps.
public final class DefaultBeatGridAnalyzer: BeatGridAnalyzing, @unchecked Sendable {

    // MARK: - State

    private let preprocessor: BeatThisPreprocessor
    private let model: BeatThisModel
    private static let frameRate: Double = 50.0

    // MARK: - Init

    public init(device: MTLDevice) throws {
        self.preprocessor = BeatThisPreprocessor()
        self.model = try BeatThisModel(device: device)
    }

    // MARK: - BeatGridAnalyzing

    public func analyzeBeatGrid(samples: [Float], sampleRate: Double) -> BeatGrid {
        let (spec, frameCount) = preprocessor.process(
            samples: samples,
            inputSampleRate: sampleRate
        )
        guard frameCount > 0 else {
            logger.info("BeatGrid: preprocessor returned empty spectrogram")
            return .empty
        }
        do {
            // FT.4 (Matt, 2026-08-27), env-flagged A/B per the program house rule (plan §4).
            // OFF: one `predict` over a fixed 1500-frame (~30 s) window, and bar position from
            // the model's downbeat head. ON: FT.1's tiler decodes the WHOLE track, and bar
            // position comes from FT.3's `BarLineEstimator`, which scores beat-synchronous
            // accent features at already-known beat times instead of reading that head.
            //
            // The head is why this exists: it over-fires. On money it emits a downbeat on 78 %
            // of beats, so `computeMeter`'s round(median_IOI / beat_period) returns 1 and the
            // 7 collapses (docs/diagnostics/DOWNBEAT_SURVEY_2026-08-27.md). Four levers have
            // already failed to fix it in place (TRK.2, DBN.2, MDL.1, FT.1); this bypasses it.
            //
            // The estimator DECLINES rather than guessing — at its calibrated threshold it
            // answers ~2 of 9 ground-truthed tracks. That is the point, not a shortfall: the
            // program's suite-5 principle is that a confident-but-wrong beat is worse than
            // declining, and D-205 makes meter/downbeat a hard gate because Nacre's and
            // Glaze's downbeat pushes are their connection layer.
            // Split into two switches at FT.4.1 (Matt, 2026-08-27). FT.4 bundled them and the
            // A/B could not tell take_five's bar win apart from bleed's beat loss; they are
            // independent — `BarLineEstimator` takes any `beats` array. `UZUME_FULLTRACK_BARS`
            // still turns both on so the FT.4 arm stays reproducible.
            let env = ProcessInfo.processInfo.environment
            let both = env["UZUME_FULLTRACK_BARS"] == "1"
            let fullTrack = both || env["UZUME_FULLTRACK_DECODE"] == "1"
            let barLine = both || env["UZUME_BARLINE"] == "1"
            let activations: (beats: [Float], downbeats: [Float])
            if fullTrack {
                activations = try BeatThisTiledInference.predictFullTrack(
                    model: model,
                    spectrogram: spec,
                    frameCount: frameCount
                )
            } else {
                activations = try model.predict(spectrogram: spec, frameCount: frameCount)
            }

            let grid = BeatGridResolver.resolve(
                beatProbs: activations.beats,
                downbeatProbs: activations.downbeats,
                frameRate: Self.frameRate
            )
            guard barLine else { return grid }
            return Self.applyBarLineEstimate(
                to: grid,
                samples: samples,
                sampleRate: sampleRate
            )
        } catch {
            logger.error("BeatGrid: model.predict failed: \(error.localizedDescription)")
            return .empty
        }
    }

    // MARK: - FT.4 bar-line override

    /// Replace the grid's meter/bar phase with `BarLineEstimator`'s, or leave the grid's
    /// beats alone and carry NO bars when the estimator declines.
    ///
    /// A decline is expressed as `beatsPerBar = 1` with empty `downbeats` and zero
    /// confidence — the same shape a track with no detected bars already produces, so
    /// consumers need no new case. Beats are never touched: they are the layer that
    /// works (F 0.97–0.99), and D-004 keeps them an accent layer regardless.
    private static func applyBarLineEstimate(
        to grid: BeatGrid,
        samples: [Float],
        sampleRate: Double
    ) -> BeatGrid {
        let estimate = BarLineEstimator.estimate(
            beats: grid.beats, audio: samples, sampleRate: sampleRate)
        guard let beatsPerBar = estimate.beatsPerBar, let phase = estimate.barLinePhase else {
            let why = estimate.decline.rawValue
            logger.info("BeatGrid FT.4: bar line DECLINED (\(why), margin \(estimate.margin)) — no bars")
            return BeatGrid(
                beats: grid.beats,
                downbeats: [],
                bpm: grid.bpm,
                beatsPerBar: 1,
                barConfidence: 0,
                frameRate: grid.frameRate,
                frameCount: grid.frameCount
            )
        }
        // Lay downbeats on the estimated phase: every `beatsPerBar`-th beat from `phase`.
        let downbeats = grid.beats.enumerated()
            .filter { $0.offset % beatsPerBar == phase }
            .map(\.element)
        logger.info("BeatGrid FT.4: bar \(beatsPerBar) phase \(phase), \(downbeats.count) downbeats")
        return BeatGrid(
            beats: grid.beats,
            downbeats: downbeats,
            bpm: grid.bpm,
            beatsPerBar: beatsPerBar,
            barConfidence: Float(min(1.0, estimate.margin / 4.0)),
            frameRate: grid.frameRate,
            frameCount: grid.frameCount
        )
    }
}
