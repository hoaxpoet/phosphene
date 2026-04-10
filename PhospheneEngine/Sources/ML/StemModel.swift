// StemModel — MPSGraph-based Open-Unmix HQ inference engine.
//
// Reconstructs the Open-Unmix HQ neural network entirely in MPSGraph,
// replacing the CoreML model for stem separation mask estimation. This
// eliminates the ANE Float16→Float32 conversion bottleneck (~420ms) and
// runs the full inference in Float32 on the GPU.
//
// The engine loads 172 weight tensors (43 per stem × 4 stems, ~136 MB)
// from raw .bin files at init. Batch norm layers are fused into scale+bias
// operations. A single MPSGraph contains all 4 stems, compiled once at
// init and reused for every predict() call.
//
// Public API follows the StemFFTEngine pattern: pre-allocated UMA I/O
// buffers, caller writes input → calls predict() → reads output.

import Foundation
import Metal
import MetalPerformanceShadersGraph
import Shared
import os.log

private let logger = Logger(subsystem: "com.phosphene.ml", category: "StemModel")

// MARK: - Errors

public enum StemModelError: Error, Sendable {
    case deviceError(String)
    case weightLoadFailed(String)
    case graphBuildFailed(String)
    case predictionFailed(String)
    case bufferAllocationFailed(Int)
}

// MARK: - StemModelEngine

/// MPSGraph-based Open-Unmix HQ inference engine.
///
/// Replaces CoreML for stem separation mask estimation. Accepts stereo
/// magnitude spectrograms and produces 4 filtered spectrograms (vocals,
/// drums, bass, other).
///
/// Thread-safe via an internal lock — concurrent `predict()` calls are
/// serialized. For throughput-critical workloads, prefer one engine per
/// worker thread.
public final class StemModelEngine: @unchecked Sendable {

    // MARK: - Constants

    /// Number of STFT frames (matches Open-Unmix HQ fixed input size).
    static let modelFrameCount = 431

    /// Total frequency bins from STFT (nFFT/2 + 1 = 2049).
    static let nBins = 2049

    /// Bandwidth-limited bins used by the network input.
    static let bandwidthBins = 1487

    /// Number of output stems.
    static let stemCount = 4

    /// Elements per channel: modelFrameCount × nBins.
    private static var elementsPerChannel: Int { modelFrameCount * nBins }

    // MARK: - Metal Resources

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue

    // MARK: - Graph

    private let graphBundle: StemModelGraphBundle

    // MARK: - I/O Buffers

    /// Input buffer for left channel magnitude [431 × 2049], row-major [frame, bin].
    public let inputMagLBuffer: MTLBuffer

    /// Input buffer for right channel magnitude [431 × 2049], row-major [frame, bin].
    public let inputMagRBuffer: MTLBuffer

    /// Output buffers for 4 stems, each with left and right channel magnitudes.
    /// Stem order: vocals (0), drums (1), bass (2), other (3).
    public let outputBuffers: [(magL: MTLBuffer, magR: MTLBuffer)]

    /// Internal buffer for the assembled [431, 2, 2049] input tensor.
    private let inputAssembledBuffer: MTLBuffer

    /// Internal buffers for each stem's [431, 2, 2049] output.
    private let outputAssembledBuffers: [MTLBuffer]

    // MARK: - Threading

    private let lock = NSLock()

    // MARK: - Init

    /// Create a new MPSGraph-based stem model engine.
    ///
    /// Loads all weight tensors (~136 MB), fuses batch norms, and builds the
    /// complete MPSGraph at init time. First predict() call may incur JIT
    /// compilation latency.
    ///
    /// - Parameter device: Metal device for buffer allocation and graph execution.
    /// - Throws: `StemModelError` if weight loading or graph construction fails.
    public init(device: MTLDevice) throws {
        self.device = device

        guard let queue = device.makeCommandQueue() else {
            throw StemModelError.deviceError("Failed to create command queue")
        }
        self.commandQueue = queue

        // Load weights
        let allWeights: [StemWeights]
        do {
            allWeights = try loadAllStemWeights()
        } catch {
            throw StemModelError.weightLoadFailed(error.localizedDescription)
        }

        // Build graph
        self.graphBundle = Self.buildGraph(allWeights: allWeights)

        // Allocate I/O buffers
        let elemBytes = Self.elementsPerChannel * MemoryLayout<Float>.size
        let assembledBytes = Self.modelFrameCount * 2 * Self.nBins * MemoryLayout<Float>.size

        guard let inL = device.makeBuffer(length: elemBytes, options: .storageModeShared),
              let inR = device.makeBuffer(length: elemBytes, options: .storageModeShared),
              let assembled = device.makeBuffer(length: assembledBytes, options: .storageModeShared)
        else {
            throw StemModelError.bufferAllocationFailed(elemBytes)
        }
        self.inputMagLBuffer = inL
        self.inputMagRBuffer = inR
        self.inputAssembledBuffer = assembled

        var outBufs = [(magL: MTLBuffer, magR: MTLBuffer)]()
        var assembledOuts = [MTLBuffer]()
        for _ in 0..<Self.stemCount {
            guard let oL = device.makeBuffer(length: elemBytes, options: .storageModeShared),
                  let oR = device.makeBuffer(length: elemBytes, options: .storageModeShared),
                  let oA = device.makeBuffer(length: assembledBytes, options: .storageModeShared)
            else {
                throw StemModelError.bufferAllocationFailed(elemBytes)
            }
            outBufs.append((magL: oL, magR: oR))
            assembledOuts.append(oA)
        }
        self.outputBuffers = outBufs
        self.outputAssembledBuffers = assembledOuts

        logger.info("StemModelEngine ready: MPSGraph, \(Self.stemCount) stems, \(Self.modelFrameCount) frames")
    }

    // MARK: - Predict

    /// Run inference on the stereo magnitude spectrograms currently in the input buffers.
    ///
    /// Before calling, write left/right magnitude data (431 × 2049 floats each,
    /// row-major [frame, bin]) into `inputMagLBuffer` and `inputMagRBuffer`.
    ///
    /// After return, read separated magnitudes from `outputBuffers[stem].magL/magR`.
    ///
    /// - Throws: `StemModelError.predictionFailed` if graph execution fails.
    public func predict() throws {
        lock.lock()
        defer { lock.unlock() }

        // Assemble [431, 2, 2049] from separate L/R buffers.
        // Layout: for each frame, channel 0 (L) then channel 1 (R), each nBins floats.
        assembleInput()

        // Create tensor data backed by the assembled input buffer.
        let inputShape: [NSNumber] = [
            NSNumber(value: Self.modelFrameCount),
            2,
            NSNumber(value: Self.nBins)
        ]
        let inputData = MPSGraphTensorData(
            inputAssembledBuffer,
            shape: inputShape,
            dataType: .float32
        )

        // Run graph
        let feeds: [MPSGraphTensor: MPSGraphTensorData] = [
            graphBundle.inputTensor: inputData
        ]

        let results = graphBundle.graph.run(
            with: commandQueue,
            feeds: feeds,
            targetTensors: graphBundle.stemOutputTensors,
            targetOperations: nil
        )

        // Extract outputs
        for (idx, tensor) in graphBundle.stemOutputTensors.enumerated() {
            guard let result = results[tensor] else {
                throw StemModelError.predictionFailed("Missing output for stem \(idx)")
            }
            result.mpsndarray().readBytes(
                outputAssembledBuffers[idx].contents(),
                strideBytes: nil
            )
            disassembleOutput(stemIndex: idx)
        }
    }

    // MARK: - Buffer Assembly

    /// Interleave separate L/R buffers into [frame, 2, bin] layout.
    private func assembleInput() {
        let magL = inputMagLBuffer.contents().assumingMemoryBound(to: Float.self)
        let magR = inputMagRBuffer.contents().assumingMemoryBound(to: Float.self)
        let dst = inputAssembledBuffer.contents().assumingMemoryBound(to: Float.self)

        let bins = Self.nBins
        for frame in 0..<Self.modelFrameCount {
            let srcOffset = frame * bins
            let dstBase = frame * 2 * bins
            // Left channel
            memcpy(dst + dstBase, magL + srcOffset, bins * MemoryLayout<Float>.size)
            // Right channel
            memcpy(dst + dstBase + bins, magR + srcOffset, bins * MemoryLayout<Float>.size)
        }
    }

    /// Deinterleave [frame, 2, bin] output into separate L/R buffers.
    private func disassembleOutput(stemIndex: Int) {
        let src = outputAssembledBuffers[stemIndex].contents().assumingMemoryBound(to: Float.self)
        let dstL = outputBuffers[stemIndex].magL.contents().assumingMemoryBound(to: Float.self)
        let dstR = outputBuffers[stemIndex].magR.contents().assumingMemoryBound(to: Float.self)

        let bins = Self.nBins
        for frame in 0..<Self.modelFrameCount {
            let srcBase = frame * 2 * bins
            let dstOffset = frame * bins
            // Left channel
            memcpy(dstL + dstOffset, src + srcBase, bins * MemoryLayout<Float>.size)
            // Right channel
            memcpy(dstR + dstOffset, src + srcBase + bins, bins * MemoryLayout<Float>.size)
        }
    }
}
