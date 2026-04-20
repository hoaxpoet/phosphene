// SpectralHistoryBuffer — Per-frame MIR history ring buffer, bound at buffer(5).
//
// Maintains 5 parallel ring buffers of 480 float samples (~8s at 60 fps):
//   valence, arousal, beat_phase01, bass_dev, vocal pitch (log-normalized).
//
// Single-writer (render thread), single-reader (GPU). No lock required.
// Bound unconditionally at fragment buffer index 5 in all direct-pass encoders.
// Reset on track change via VisualizerEngine.resetStemPipeline(for:).

import Metal
import os.log

private let logger = Logger(subsystem: "com.phosphene", category: "SpectralHistory")

// MARK: - Protocol

/// Abstracts the spectral history GPU buffer; enables test doubles.
public protocol SpectralHistoryPublishing: AnyObject, Sendable {
    /// Pre-allocated `.storageModeShared` MTLBuffer for fragment binding at index 5.
    var gpuBuffer: MTLBuffer { get }

    /// Append one frame's worth of MIR data to the ring buffers.
    /// Call exactly once per frame, before fragment encoders are created.
    func append(features: FeatureVector, stems: StemFeatures)

    /// Zero the buffer and reset ring indices. Call on track change.
    func reset()
}

// MARK: - SpectralHistoryBuffer

/// Per-frame MIR history ring buffer for the `instrument` preset family.
///
/// GPU buffer layout (4096 Float32 = 16 384 bytes, bound at fragment index 5):
/// ```
/// [0..479]    valence        (-1..1, raw)
/// [480..959]  arousal        (-1..1, raw)
/// [960..1439] beat_phase01   (0..1, raw sawtooth)
/// [1440..1919] bass_dev      (0..1, positive deviation)
/// [1920..2399] pitch_norm    (0..1, log-mapped 80-800 Hz; 0 = unvoiced/low confidence)
/// [2400]      write_head     (integer stored as Float, 0..479)
/// [2401]      samples_valid  (integer stored as Float, capped at 480)
/// [2402..4095] reserved      (zeroed; future consumers)
/// ```
public final class SpectralHistoryBuffer: SpectralHistoryPublishing, @unchecked Sendable {

    // MARK: - Layout Constants

    /// Number of samples per ring (~8s at 60 fps).
    public static let historyLength = 480
    /// Total floats in the GPU buffer (16 KB).
    public static let totalFloats = 4096
    /// GPU buffer size in bytes.
    public static let bufferSizeBytes = totalFloats * MemoryLayout<Float>.size

    public static let offsetValence: Int = 0
    public static let offsetArousal: Int = 480
    public static let offsetBeatPhase: Int = 960
    public static let offsetBassDev: Int = 1440
    public static let offsetPitchNorm: Int = 1920
    public static let offsetWriteHead: Int = 2400
    public static let offsetSamplesValid: Int = 2401

    // Pitch: log2(hz/80) / log2(10) -> [0..1] for 80..800 Hz.
    private static let pitchMinHz: Float = 80.0
    private static let pitchLog10Divisor: Float = Float(log2(10.0))  // ~3.3219
    private static let pitchConfidenceThreshold: Float = 0.6

    // MARK: - State

    /// Pre-allocated `.storageModeShared` buffer; written by CPU, read by GPU.
    public let gpuBuffer: MTLBuffer

    private var writeHead: Int = 0
    private var samplesValid: Int = 0

    // MARK: - Init

    public init(device: MTLDevice) {
        guard let buf = device.makeBuffer(
            length: Self.bufferSizeBytes,
            options: .storageModeShared
        ) else {
            fatalError("SpectralHistoryBuffer: failed to allocate \(Self.bufferSizeBytes) B")
        }
        self.gpuBuffer = buf
        memset(buf.contents(), 0, Self.bufferSizeBytes)
        logger.info("SpectralHistoryBuffer allocated (\(Self.bufferSizeBytes) bytes)")
    }

    // MARK: - API

    /// Append one frame to the ring buffers and advance the write head.
    ///
    /// No allocations, no locks. Single-writer contract must be respected
    /// (call from the render thread only).
    public func append(features: FeatureVector, stems: StemFeatures) {
        let ptr = gpuBuffer.contents().assumingMemoryBound(to: Float.self)
        let slot = writeHead

        ptr[Self.offsetValence + slot] = features.valence
        ptr[Self.offsetArousal + slot] = features.arousal
        ptr[Self.offsetBeatPhase + slot] = features.beatPhase01
        ptr[Self.offsetBassDev + slot] = features.bassDev
        ptr[Self.offsetPitchNorm + slot] = Self.normalizePitch(
            hz: stems.vocalsPitchHz,
            confidence: stems.vocalsPitchConfidence
        )

        writeHead = (writeHead + 1) % Self.historyLength
        samplesValid = min(samplesValid + 1, Self.historyLength)

        ptr[Self.offsetWriteHead] = Float(writeHead)
        ptr[Self.offsetSamplesValid] = Float(samplesValid)
    }

    /// Zero the entire buffer and reset ring indices. Call on track change.
    public func reset() {
        memset(gpuBuffer.contents(), 0, Self.bufferSizeBytes)
        writeHead = 0
        samplesValid = 0
    }

    // MARK: - Private

    /// Map vocal pitch to [0..1]. Returns 0 when unvoiced or low confidence.
    ///
    /// Formula: log2(hz / 80) / log2(10), clamped to [0..1].
    /// Maps 80 Hz -> 0.0, 800 Hz -> 1.0, ~253 Hz -> 0.5 (perceptual midpoint).
    private static func normalizePitch(hz: Float, confidence: Float) -> Float {
        guard confidence >= pitchConfidenceThreshold, hz > 0 else { return 0 }
        let norm = log2(hz / pitchMinHz) / pitchLog10Divisor
        return max(0, min(1, norm))
    }
}
