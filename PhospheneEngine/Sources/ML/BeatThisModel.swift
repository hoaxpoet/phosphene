// BeatThisModel — Beat This! small0 MPSGraph encoder.
//
// S3: builds the complete transformer encoder graph with zero weights.
// S4 will replace zero weights with loaded small0 checkpoint.
//
// Architecture (small0): 128-dim transformer, 4 heads, 6 blocks, 512 FFN.
// Input: log-mel spectrogram [T, 128]. Output: beat + downbeat probabilities [T].

import Foundation
import Metal
import MetalPerformanceShadersGraph
import os.log

private let logger = Logger(subsystem: "com.phosphene.ml", category: "BeatThisModel")

// MARK: - Errors

public enum BeatThisModelError: Error, Sendable {
    case deviceError(String)
    case graphBuildFailed(String)
    case predictionFailed(String)
}

// MARK: - Graph Bundle

struct BeatThisGraphBundle {
    let graph: MPSGraph
    let inputTensor: MPSGraphTensor
    let beatOutputTensor: MPSGraphTensor
    let downbeatOutputTensor: MPSGraphTensor
}

// MARK: - Internal Result

struct CorePrediction {
    let beats: [Float]
    let downbeats: [Float]
    let frontendShape: [Int]
}

// MARK: - BeatThisModel

/// Beat This! small0 inference engine — MPSGraph, Float32, zero-copy I/O.
///
/// The graph is compiled once at init and reused. First call may incur JIT latency.
/// Thread-safe via an internal lock.
public final class BeatThisModel: @unchecked Sendable {

    // MARK: - Architecture Constants (small0)

    public static let embedDim = 128
    public static let numHeads = 4
    public static let headDim = 32
    public static let numBlocks = 6
    public static let ffnDim = 512
    public static let inputMels = 128
    public static let outputClasses = 2

    /// Fixed sequence length — covers ~30 s at 50 fps (hop=441, sr=22050).
    static let tMax = 1500

    // MARK: - Metal Resources

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let graphBundle: BeatThisGraphBundle
    private let inputBuffer: MTLBuffer
    private let lock = NSLock()

    // MARK: - Init

    /// Build the MPSGraph encoder with zero weights.
    ///
    /// - Parameter device: Metal device for graph execution.
    /// - Throws: `BeatThisModelError` if graph construction fails.
    public init(device: MTLDevice) throws {
        self.device = device
        guard let queue = device.makeCommandQueue() else {
            throw BeatThisModelError.deviceError("Failed to create command queue")
        }
        self.commandQueue = queue
        do {
            self.graphBundle = try Self.buildGraph()
        } catch {
            throw BeatThisModelError.graphBuildFailed(error.localizedDescription)
        }
        let inputBytes = Self.tMax * Self.inputMels * MemoryLayout<Float>.size
        guard let buf = device.makeBuffer(length: inputBytes, options: .storageModeShared) else {
            throw BeatThisModelError.deviceError("Failed to allocate input buffer")
        }
        self.inputBuffer = buf
        logger.info("BeatThisModel ready: small0, \(Self.numBlocks) blocks, tMax=\(Self.tMax)")
    }

    // MARK: - Public API

    /// Run inference on a log-mel spectrogram.
    ///
    /// - Parameters:
    ///   - spectrogram: Flat row-major [T × inputMels] Float32 array.
    ///   - frameCount: Actual frame count T; must be ≤ tMax.
    /// - Returns: Beat and downbeat activation probabilities, each of length `frameCount`.
    public func predict(
        spectrogram: [Float],
        frameCount: Int
    ) throws -> (beats: [Float], downbeats: [Float]) {
        let result = try predictCore(spectrogram: spectrogram, frameCount: frameCount)
        return (result.beats, result.downbeats)
    }

    /// Like `predict`, but also returns `[frameCount, embedDim]` as the frontend output shape.
    func predictIncludingFrontendOutput(
        spectrogram: [Float],
        frameCount: Int
    ) throws -> CorePrediction {
        try predictCore(spectrogram: spectrogram, frameCount: frameCount)
    }

    // MARK: - Private Inference

    private func predictCore(spectrogram: [Float], frameCount: Int) throws -> CorePrediction {
        lock.lock()
        defer { lock.unlock() }

        let clampedCount = min(max(frameCount, 0), Self.tMax)
        let padded = padInput(spectrogram: spectrogram)

        let dst = inputBuffer.contents().assumingMemoryBound(to: Float.self)
        padded.withUnsafeBufferPointer { srcBuf in
            guard let base = srcBuf.baseAddress else { return }
            memcpy(dst, base, padded.count * MemoryLayout<Float>.size)
        }

        let inputShape: [NSNumber] = [NSNumber(value: Self.tMax), NSNumber(value: Self.inputMels)]
        let inputData = MPSGraphTensorData(
            inputBuffer,
            shape: inputShape,
            dataType: .float32
        )

        let feeds: [MPSGraphTensor: MPSGraphTensorData] = [graphBundle.inputTensor: inputData]
        let results = graphBundle.graph.run(
            with: commandQueue,
            feeds: feeds,
            targetTensors: [graphBundle.beatOutputTensor, graphBundle.downbeatOutputTensor],
            targetOperations: nil
        )

        guard let beatResult = results[graphBundle.beatOutputTensor],
              let downbeatResult = results[graphBundle.downbeatOutputTensor] else {
            throw BeatThisModelError.predictionFailed("Missing output tensors")
        }

        var beatFull = [Float](repeating: 0, count: Self.tMax)
        var downbeatFull = [Float](repeating: 0, count: Self.tMax)
        beatResult.mpsndarray().readBytes(&beatFull, strideBytes: nil)
        downbeatResult.mpsndarray().readBytes(&downbeatFull, strideBytes: nil)

        return CorePrediction(
            beats: Array(beatFull.prefix(clampedCount)),
            downbeats: Array(downbeatFull.prefix(clampedCount)),
            frontendShape: [clampedCount, Self.embedDim]
        )
    }

    // MARK: - Padding

    private func padInput(spectrogram: [Float]) -> [Float] {
        let total = Self.tMax * Self.inputMels
        if spectrogram.count >= total {
            return Array(spectrogram.prefix(total))
        }
        return spectrogram + [Float](repeating: 0, count: total - spectrogram.count)
    }
}
