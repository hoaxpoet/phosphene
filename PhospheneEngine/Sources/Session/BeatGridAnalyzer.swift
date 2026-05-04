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

private let logger = Logger(subsystem: "com.phosphene", category: "BeatGridAnalyzer")

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
            let (beats, downbeats) = try model.predict(
                spectrogram: spec,
                frameCount: frameCount
            )
            return BeatGridResolver.resolve(
                beatProbs: beats,
                downbeatProbs: downbeats,
                frameRate: Self.frameRate
            )
        } catch {
            logger.error("BeatGrid: model.predict failed: \(error.localizedDescription)")
            return .empty
        }
    }
}
