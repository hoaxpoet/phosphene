// StemFFT — GPU-accelerated STFT/iSTFT engine for stem separation.
//
// Replaces the CPU-bound Accelerate/vDSP STFT path inside `StemSeparator`
// with Metal Performance Shaders Graph (MPSGraph) FFT operations, reducing
// the per-separation cost from ~6.5s (CPU) to the low-hundreds-of-ms target.
//
// Architecture (Option A — MPSGraph):
//
// MPSGraph's `realToHermiteanFFT` and `HermiteanToRealFFT` ops (macOS 14+)
// cover the 4096-point real FFT the Open-Unmix HQ model requires. We build
// the forward and inverse graphs once at init, then reuse them for every
// separation call. Input/output tensors are backed by persistent
// `.storageModeShared` MTLBuffers so CPU writes and GPU reads are zero-copy.
//
// Framing + windowing (forward) and overlap-add (inverse) stay on the CPU
// because they are cheap O(nbFrames × nFFT) gather/scatter operations
// (~1.7M float ops for a 10s window) and avoid another round of
// GPU<->CPU ping-pong. The expensive per-frame butterfly math lives on the
// GPU via MPSGraph.
//
// The CPU fallback path is preserved verbatim from the original
// `StemSeparator` implementation and exposed via `forceCPUFallback`. Tests
// use it as a reference to cross-validate GPU output, and it remains
// available as a safety net until the live stem pipeline (Increment 3.1b)
// has proven the GPU path under load.
//
// Option B (hand-written Metal compute FFT) was NOT needed — MPSGraph's
// real FFT supports 4096-point transforms on Apple Silicon since macOS 14.

import Foundation
import Metal
import MetalPerformanceShadersGraph
import Accelerate
import Shared
import os.log

private let logger = Logger(subsystem: "com.phosphene.ml", category: "StemFFT")

// MARK: - Protocol

/// Abstraction over the STFT/iSTFT engine used by `StemSeparator`.
///
/// Concrete implementation: ``StemFFTEngine``.
/// Tests can inject a stub by conforming to this protocol.
public protocol StemFFTEngineProtocol: AnyObject {
    /// When true, bypass the GPU path and use the CPU vDSP fallback.
    /// Used by cross-validation tests to compare implementations.
    var forceCPUFallback: Bool { get set }

    /// Compute the Short-Time Fourier Transform of a mono signal with
    /// center padding, matching PyTorch's `torch.stft(center=True)`.
    ///
    /// - Parameter mono: Mono float32 samples.
    /// - Returns: Magnitude and phase arrays, each of length `nBins * nbFrames`.
    func forward(mono: [Float]) -> (magnitude: [Float], phase: [Float])

    /// Reconstruct a time-domain signal from magnitude and phase spectrograms.
    ///
    /// - Parameters:
    ///   - magnitude: Magnitude spectrogram (`nBins * nbFrames`).
    ///   - phase: Phase spectrogram (`nBins * nbFrames`).
    ///   - nbFrames: Number of STFT frames.
    ///   - originalLength: If provided, strip center padding to this length.
    /// - Returns: Reconstructed mono waveform.
    func inverse(magnitude: [Float], phase: [Float], nbFrames: Int, originalLength: Int?) -> [Float]
}

// MARK: - StemFFTError

public enum StemFFTError: Error, Sendable {
    case commandQueueCreationFailed
    case vDSPSetupFailed
    case bufferAllocationFailed
    case graphExecutionFailed(String)
}

// MARK: - StemFFTEngine

/// GPU-accelerated STFT/iSTFT engine backed by MPSGraph.
///
/// Thread-safe via an internal lock — concurrent `forward`/`inverse` calls
/// are serialized but do not crash. For throughput-critical workloads,
/// prefer one engine per worker thread.
public final class StemFFTEngine: StemFFTEngineProtocol, @unchecked Sendable {

    // MARK: - STFT Parameters

    /// FFT size (matches Open-Unmix HQ).
    public static let nFFT = 4096

    /// Hop length between consecutive frames.
    public static let hopLength = 1024

    /// Number of frequency bins returned: `nFFT / 2 + 1`.
    public static let nBins = nFFT / 2 + 1  // 2049

    /// Fixed number of STFT frames for a full 10-second chunk.
    public static let modelFrameCount = 431

    /// Mono sample count that produces exactly `modelFrameCount` frames.
    public static let requiredMonoSamples = (modelFrameCount - 1) * hopLength  // 440320

    /// vDSP log2(nFFT) for the CPU fallback FFT setup.
    internal static let log2n = vDSP_Length(log2(Double(nFFT)))

    // MARK: - Public Configuration

    /// When `true`, bypass the GPU path and use vDSP exclusively.
    /// Changing this mid-run is safe; it takes effect on the next call.
    public var forceCPUFallback: Bool = false

    // MARK: - Shared Resources

    /// Hann window used for both forward analysis and inverse synthesis.
    internal let window: [Float]

    /// vDSP FFT setup for the CPU fallback path.
    internal let fftSetup: FFTSetup

    /// Serializes access to the graph execution path.
    private let lock = NSLock()

    // MARK: - GPU Resources
    //
    // These are `internal` rather than `private` because the GPU
    // fast path lives in `StemFFT+GPU.swift` — Swift extensions in a
    // different source file cannot see `private` members.

    internal let device: MTLDevice
    internal let commandQueue: MTLCommandQueue
    private let mpsGraphDevice: MPSGraphDevice

    /// Forward graph: [nbFrames, nFFT] real → (real, imag) [nbFrames, nBins].
    internal let forwardGraph: MPSGraph
    internal let forwardInputTensor: MPSGraphTensor
    internal let forwardRealOutput: MPSGraphTensor
    internal let forwardImagOutput: MPSGraphTensor

    /// Inverse graph: (real, imag) [nbFrames, nBins] → [nbFrames, nFFT] real.
    internal let inverseGraph: MPSGraph
    internal let inverseRealInput: MPSGraphTensor
    internal let inverseImagInput: MPSGraphTensor
    internal let inverseRealOutput: MPSGraphTensor

    /// UMA input buffer for windowed frames (forward path).
    internal let forwardInputBuffer: MTLBuffer

    /// UMA output buffers for real and imaginary parts (forward path).
    internal let forwardRealBuffer: MTLBuffer
    internal let forwardImagBuffer: MTLBuffer

    /// UMA input buffers for packed real/imag spectrograms (inverse path).
    internal let inverseRealBuffer: MTLBuffer
    internal let inverseImagBuffer: MTLBuffer

    /// UMA output buffer for the time-domain reconstruction (inverse path).
    internal let inverseOutputBuffer: MTLBuffer

    // MARK: - Precomputed

    /// Precomputed `sum_k window[k]^2` for the fixed-size inverse path.
    /// Length = `(modelFrameCount - 1) * hopLength + nFFT`.
    internal let windowSquareSum: [Float]

    // MARK: - Init

    /// Create a new STFT engine.
    ///
    /// - Parameter device: Metal device for UMA buffer allocation.
    /// - Throws: ``StemFFTError`` if graph or buffer setup fails.
    public init(device: MTLDevice) throws {
        self.device = device
        guard let queue = device.makeCommandQueue() else {
            throw StemFFTError.commandQueueCreationFailed
        }
        self.commandQueue = queue
        self.mpsGraphDevice = MPSGraphDevice(mtlDevice: device)

        // Hann window (matches vDSP convention so the CPU and GPU paths
        // are comparable byte-for-byte).
        var win = [Float](repeating: 0, count: Self.nFFT)
        vDSP_hann_window(&win, vDSP_Length(Self.nFFT), Int32(vDSP_HANN_NORM))
        self.window = win

        guard let setup = vDSP_create_fftsetup(Self.log2n, FFTRadix(kFFTRadix2)) else {
            throw StemFFTError.vDSPSetupFailed
        }
        self.fftSetup = setup

        let forward = Self.buildForwardGraph()
        self.forwardGraph = forward.graph
        self.forwardInputTensor = forward.input
        self.forwardRealOutput = forward.real
        self.forwardImagOutput = forward.imag

        let inverse = Self.buildInverseGraph()
        self.inverseGraph = inverse.graph
        self.inverseRealInput = inverse.real
        self.inverseImagInput = inverse.imag
        self.inverseRealOutput = inverse.output

        let buffers = try Self.allocateIOBuffers(device: device)
        self.forwardInputBuffer = buffers.forwardInput
        self.forwardRealBuffer = buffers.forwardReal
        self.forwardImagBuffer = buffers.forwardImag
        self.inverseRealBuffer = buffers.inverseReal
        self.inverseImagBuffer = buffers.inverseImag
        self.inverseOutputBuffer = buffers.inverseOutput

        self.windowSquareSum = Self.computeWindowSquareSum(window: win)

        logger.info("StemFFTEngine ready: MPSGraph, \(Self.nFFT)-pt FFT, \(Self.modelFrameCount) frames")
    }

    deinit {
        vDSP_destroy_fftsetup(fftSetup)
    }

    // MARK: - Graph Construction

    private struct ForwardGraphBundle {
        let graph: MPSGraph
        let input: MPSGraphTensor
        let real: MPSGraphTensor
        let imag: MPSGraphTensor
    }

    private struct InverseGraphBundle {
        let graph: MPSGraph
        let real: MPSGraphTensor
        let imag: MPSGraphTensor
        let output: MPSGraphTensor
    }

    private struct IOBuffers {
        let forwardInput: MTLBuffer
        let forwardReal: MTLBuffer
        let forwardImag: MTLBuffer
        let inverseReal: MTLBuffer
        let inverseImag: MTLBuffer
        let inverseOutput: MTLBuffer
    }

    private static func buildForwardGraph() -> ForwardGraphBundle {
        let graph = MPSGraph()
        let shape: [NSNumber] = [
            NSNumber(value: modelFrameCount),
            NSNumber(value: nFFT)
        ]
        let input = graph.placeholder(shape: shape, dataType: .float32, name: "frames")
        let desc = MPSGraphFFTDescriptor()
        desc.inverse = false
        desc.scalingMode = .none
        let complex = graph.realToHermiteanFFT(
            input, axes: [NSNumber(value: 1)], descriptor: desc, name: "realFFT"
        )
        let real = graph.realPartOfTensor(tensor: complex, name: "real")
        let imag = graph.imaginaryPartOfTensor(tensor: complex, name: "imag")
        return ForwardGraphBundle(graph: graph, input: input, real: real, imag: imag)
    }

    private static func buildInverseGraph() -> InverseGraphBundle {
        let graph = MPSGraph()
        let shape: [NSNumber] = [
            NSNumber(value: modelFrameCount),
            NSNumber(value: nBins)
        ]
        let real = graph.placeholder(shape: shape, dataType: .float32, name: "real")
        let imag = graph.placeholder(shape: shape, dataType: .float32, name: "imag")
        let complex = graph.complexTensor(realTensor: real, imaginaryTensor: imag, name: "complex")
        let desc = MPSGraphFFTDescriptor()
        desc.inverse = true
        desc.scalingMode = .size
        let output = graph.HermiteanToRealFFT(
            complex, axes: [NSNumber(value: 1)], descriptor: desc, name: "iFFT"
        )
        return InverseGraphBundle(graph: graph, real: real, imag: imag, output: output)
    }

    private static func allocateIOBuffers(device: MTLDevice) throws -> IOBuffers {
        let fwdInputBytes = MemoryLayout<Float>.stride * modelFrameCount * nFFT
        let binsBytes = MemoryLayout<Float>.stride * modelFrameCount * nBins
        let invOutputBytes = MemoryLayout<Float>.stride * modelFrameCount * nFFT
        guard
            let fwdIn = device.makeBuffer(length: fwdInputBytes, options: .storageModeShared),
            let fwdRe = device.makeBuffer(length: binsBytes, options: .storageModeShared),
            let fwdIm = device.makeBuffer(length: binsBytes, options: .storageModeShared),
            let invRe = device.makeBuffer(length: binsBytes, options: .storageModeShared),
            let invIm = device.makeBuffer(length: binsBytes, options: .storageModeShared),
            let invOutBuf = device.makeBuffer(length: invOutputBytes, options: .storageModeShared)
        else {
            throw StemFFTError.bufferAllocationFailed
        }
        return IOBuffers(
            forwardInput: fwdIn,
            forwardReal: fwdRe,
            forwardImag: fwdIm,
            inverseReal: invRe,
            inverseImag: invIm,
            inverseOutput: invOutBuf
        )
    }

    private static func computeWindowSquareSum(window: [Float]) -> [Float] {
        let outputLength = (modelFrameCount - 1) * hopLength + nFFT
        var wsum = [Float](repeating: 0, count: outputLength)
        for frame in 0..<modelFrameCount {
            let offset = frame * hopLength
            for i in 0..<nFFT {
                wsum[offset + i] += window[i] * window[i]
            }
        }
        return wsum
    }

    // MARK: - Test Hooks

    /// Storage modes of every internal MTLBuffer, used by the UMA test.
    /// All entries must be `.shared` for zero-copy CPU↔GPU access.
    internal var bufferStorageModes: [MTLStorageMode] {
        [
            forwardInputBuffer.storageMode,
            forwardRealBuffer.storageMode,
            forwardImagBuffer.storageMode,
            inverseRealBuffer.storageMode,
            inverseImagBuffer.storageMode,
            inverseOutputBuffer.storageMode
        ]
    }

    // MARK: - Public API

    public func forward(mono: [Float]) -> (magnitude: [Float], phase: [Float]) {
        lock.lock()
        defer { lock.unlock() }
        if forceCPUFallback {
            return cpuForward(mono: mono)
        }
        return gpuForward(mono: mono)
    }

    public func inverse(
        magnitude: [Float], phase: [Float], nbFrames: Int, originalLength: Int?
    ) -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        if forceCPUFallback {
            return cpuInverse(
                magnitude: magnitude, phase: phase, nbFrames: nbFrames, originalLength: originalLength
            )
        }
        return gpuInverse(
            magnitude: magnitude, phase: phase, nbFrames: nbFrames, originalLength: originalLength
        )
    }
}
