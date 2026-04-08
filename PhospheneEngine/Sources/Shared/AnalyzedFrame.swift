// AnalyzedFrame — Timestamped container bundling all per-frame analysis results.
// This is the currency type flowing through the lookahead buffer: the analysis
// head produces AnalyzedFrames, and the render head consumes them after a
// configurable delay.

import Foundation

// MARK: - AnalyzedFrame

/// A timestamped bundle of all audio analysis results for a single frame.
///
/// Produced by the MIR pipeline each frame and enqueued into the
/// `LookaheadBuffer`. The Orchestrator reads from both the analysis head
/// (latest frame, for anticipation) and the render head (delayed frame,
/// for synchronized visuals).
///
/// Memory budget: kept lightweight by storing metadata structs (not raw
/// sample buffers). Raw audio and FFT magnitude data remain in UMA buffers;
/// this struct carries the scalar summaries and feature vectors.
public struct AnalyzedFrame: Sendable {

    /// Timestamp in seconds since capture start.
    /// Monotonically increasing across frames.
    public var timestamp: Double

    /// PCM block metadata (sample count, rate, buffer offset).
    public var audioFrame: AudioFrame

    /// FFT analysis metadata (dominant frequency, bin count).
    public var fftResult: FFTResult

    /// Per-stem separation metadata (vocals, drums, bass, other).
    public var stemData: StemData

    /// Packed feature vector for GPU uniform upload (96 bytes).
    public var featureVector: FeatureVector

    /// Continuous valence/arousal emotional state.
    public var emotionalState: EmotionalState

    public init(
        timestamp: Double = 0,
        audioFrame: AudioFrame = AudioFrame(),
        fftResult: FFTResult = FFTResult(),
        stemData: StemData = StemData(),
        featureVector: FeatureVector = .zero,
        emotionalState: EmotionalState = .neutral
    ) {
        self.timestamp = timestamp
        self.audioFrame = audioFrame
        self.fftResult = fftResult
        self.stemData = stemData
        self.featureVector = featureVector
        self.emotionalState = emotionalState
    }

    /// An empty frame at timestamp zero.
    public static let empty = AnalyzedFrame()
}
