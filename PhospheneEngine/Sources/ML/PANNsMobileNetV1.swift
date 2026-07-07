// PANNsMobileNetV1 — PANNs MobileNetV1 audio tagger, MPSGraph port (IFC.2 / D-177).
//
// AudioSet 527-class multi-label tagger (Kong et al., 2020). Phosphene uses it
// for instrument-family activity on the 30 s preview clip (strings / brass /
// woodwinds / percussion), the load-bearing capability for Ricercar (D-176).
//
// Pipeline: waveform (32 kHz mono) → log-mel front-end (Swift/vDSP, exact
// matmuls against the checkpoint's STFT/mel matrices, see +Frontend) → conv
// stack (MPSGraph, see +Graph) → 527 sigmoid activations.
//
// This increment is the port + numerical-parity validation only; feature-pipeline
// integration (FeatureVector / StemFeatures) is IFC.4.
//
// Weights: CC-BY-4.0 (Zenodo 3987831). Model def reimplemented from
// github.com/qiuqiangkong/audioset_tagging_cnn (MIT). Attribution ships in IFC.4.

import Foundation
import Metal
import MetalPerformanceShadersGraph
import os.log

private let logger = Logger(subsystem: "com.phosphene.ml", category: "PANNsMobileNetV1")

// MARK: - Errors

public enum PANNsModelError: Error, Sendable {
    case deviceError(String)
    case graphBuildFailed(String)
    case predictionFailed(String)
}

// MARK: - Graph Bundle

struct PANNsGraphBundle {
    let graph: MPSGraph
    let input: MPSGraphTensor          // [1, frames, 64, 1] NHWC log-mel
    let probs: MPSGraphTensor          // [527] sigmoid
    let logits: MPSGraphTensor         // [527] pre-sigmoid
    /// Diagnostic taps matching the Python reference dump schema (parity
    /// localization — avoids guess-iterating on a divergence, FA #64).
    var intermediates: [String: MPSGraphTensor] = [:]
}

// MARK: - Diagnostic Result

/// Probs + logits + named intermediate taps, for the numerical-parity test.
public struct PANNsDiagnostic {
    public let probs: [Float]
    public let logits: [Float]
    public let taps: [String: [Float]]
}

// MARK: - PANNsMobileNetV1

/// PANNs MobileNetV1 inference engine — MPSGraph, Float32, zero-copy log-mel input.
///
/// Built for a fixed window of `frames` log-mel frames (default 201 = a 2 s
/// window at 32 kHz / hop 320, the per-family inference unit). The graph is
/// compiled once at init and reused; thread-safe via an internal lock.
public final class PANNsMobileNetV1: @unchecked Sendable {

    // MARK: - Architecture Constants

    public static let sampleRate = 32000
    public static let nFFT = 1024
    public static let hop = 320
    public static let melBins = 64
    public static let classCount = 527
    /// 2 s window = 1 + 64000/320 = 201 frames (center-padded STFT).
    public static let defaultFrames = 201

    // MARK: - Stored Properties

    let frames: Int
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let bundle: PANNsGraphBundle
    private let frontend: PANNsFrontend
    private let inputBuffer: MTLBuffer
    private let lock = NSLock()

    // MARK: - Init

    public init(device: MTLDevice, frames: Int = PANNsMobileNetV1.defaultFrames) throws {
        self.device = device
        self.frames = frames
        guard let queue = device.makeCommandQueue() else {
            throw PANNsModelError.deviceError("Failed to create command queue")
        }
        self.commandQueue = queue

        let weights = try Self.loadWeights()
        self.frontend = PANNsFrontend(matrices: weights.frontend)
        self.bundle = try Self.buildGraph(weights: weights, frames: frames)

        let count = frames * Self.melBins
        guard let buf = device.makeBuffer(length: count * MemoryLayout<Float>.size,
                                          options: .storageModeShared) else {
            throw PANNsModelError.deviceError("Failed to allocate input buffer")
        }
        self.inputBuffer = buf
    }

    // MARK: - Public API

    /// Compute the log-mel spectrogram for `waveform` (32 kHz mono).
    /// Exposed for front-end parity testing. Returns [frames * 64] row-major.
    public func logMel(waveform: [Float]) -> [Float] {
        frontend.logMel(waveform: waveform, frames: frames)
    }

    /// Run the full pipeline: waveform → 527 clipwise activations (sigmoid).
    public func predict(waveform: [Float]) throws -> [Float] {
        try predictFromLogMel(frontend.logMel(waveform: waveform, frames: frames)).probs
    }

    /// Run the conv stack on a precomputed log-mel ([frames * 64] row-major).
    /// Isolates the network from the front-end for parity testing.
    public func predictFromLogMel(_ logmel: [Float]) throws -> PANNsDiagnostic {
        lock.lock()
        defer { lock.unlock() }

        let expected = frames * Self.melBins
        guard logmel.count == expected else {
            throw PANNsModelError.predictionFailed(
                "log-mel size \(logmel.count) != expected \(expected)")
        }
        let dst = inputBuffer.contents().assumingMemoryBound(to: Float.self)
        logmel.withUnsafeBufferPointer { src in
            guard let base = src.baseAddress else { return }
            memcpy(dst, base, expected * MemoryLayout<Float>.size)
        }
        let inputData = MPSGraphTensorData(
            inputBuffer,
            shape: [1, NSNumber(value: frames), NSNumber(value: Self.melBins), 1],
            dataType: .float32)

        var targets = [bundle.probs, bundle.logits]
        let tapKeys = Array(bundle.intermediates.keys)
        // swiftlint:disable:next force_unwrapping
        targets.append(contentsOf: tapKeys.map { bundle.intermediates[$0]! })

        let results = bundle.graph.run(
            with: commandQueue,
            feeds: [bundle.input: inputData],
            targetTensors: targets,
            targetOperations: nil)

        guard let probsData = results[bundle.probs],
              let logitsData = results[bundle.logits] else {
            throw PANNsModelError.predictionFailed("missing output tensors")
        }
        var taps: [String: [Float]] = [:]
        for key in tapKeys {
            if let tensor = bundle.intermediates[key], let data = results[tensor] {
                taps[key] = Self.readback(data)
            }
        }
        return PANNsDiagnostic(
            probs: Self.readback(probsData),
            logits: Self.readback(logitsData),
            taps: taps)
    }

    // MARK: - Readback

    private static func readback(_ data: MPSGraphTensorData) -> [Float] {
        let count = data.shape.reduce(1) { $0 * $1.intValue }
        var out = [Float](repeating: 0, count: count)
        data.mpsndarray().readBytes(&out, strideBytes: nil)
        return out
    }
}
