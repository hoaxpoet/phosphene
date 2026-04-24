// NoiseTestHarness.swift — Shared Metal compute-pipeline harness for Noise utility tests.
//
// Compiles the full preset preamble (including the new Noise utility tree)
// plus a caller-provided compute kernel, dispatches it over a fixed input
// buffer, and returns the float output buffer.
//
// The harness runs on the system default Metal device so tests exercise the
// same compiled code the renderer uses.

import Foundation
import Metal
@testable import Presets

// MARK: - Harness

/// Errors thrown by the test harness.
enum NoiseHarnessError: Error {
    case noDevice
    case bufferAllocationFailed
    case libraryCompilationFailed(String)
    case kernelNotFound(String)
    case pipelineFailed
    case commandBufferFailed
    case renderFailed
}

/// Execute a compute kernel that reads `inputs` from buffer(10) and writes
/// `outputs` to buffer(11). Returns an array of `outputCount` floats.
///
/// `kernelSource` must define a kernel named `"test_kernel"` with signature:
///
///     kernel void test_kernel(
///         constant float3* inputs  [[buffer(10)]],
///         device   float*  outputs [[buffer(11)]],
///         uint tid [[thread_position_in_grid]]
///     ) { ... }
///
/// Buffer indices 10 and 11 are chosen to avoid any collision with the
/// fragment-shader buffer layout (0–5) declared in the preamble.
func runNoiseKernel(
    kernelSource: String,
    inputs: [SIMD3<Float>],
    outputCount: Int? = nil,
    functionName: String = "test_kernel"
) throws -> [Float] {
    guard let device = MTLCreateSystemDefaultDevice() else {
        throw NoiseHarnessError.noDevice
    }

    let count = inputs.count
    let outCount = outputCount ?? count

    // Build full source: preamble + kernel.
    let fullSource = PresetLoader.shaderPreamble + "\n\n" + kernelSource

    let options = MTLCompileOptions()
    options.fastMathEnabled = true
    options.languageVersion = .version3_1

    let library: MTLLibrary
    do {
        library = try device.makeLibrary(source: fullSource, options: options)
    } catch {
        throw NoiseHarnessError.libraryCompilationFailed("\(error)")
    }

    guard let kernelFn = library.makeFunction(name: functionName) else {
        throw NoiseHarnessError.kernelNotFound(functionName)
    }

    let pipeline: MTLComputePipelineState
    do {
        pipeline = try device.makeComputePipelineState(function: kernelFn)
    } catch {
        throw NoiseHarnessError.pipelineFailed
    }

    // Allocate input and output buffers.
    let inputStride = MemoryLayout<SIMD3<Float>>.stride
    guard let inputBuf = device.makeBuffer(
        bytes: inputs, length: count * inputStride, options: .storageModeShared
    ) else { throw NoiseHarnessError.bufferAllocationFailed }

    guard let outputBuf = device.makeBuffer(
        length: outCount * MemoryLayout<Float>.stride, options: .storageModeShared
    ) else { throw NoiseHarnessError.bufferAllocationFailed }

    guard let cmdQueue = device.makeCommandQueue(),
          let cmdBuf   = cmdQueue.makeCommandBuffer(),
          let encoder  = cmdBuf.makeComputeCommandEncoder()
    else { throw NoiseHarnessError.commandBufferFailed }

    encoder.setComputePipelineState(pipeline)
    encoder.setBuffer(inputBuf,  offset: 0, index: 10)
    encoder.setBuffer(outputBuf, offset: 0, index: 11)

    let threadCount = MTLSize(width: count, height: 1, depth: 1)
    let tgSize      = MTLSize(width: min(pipeline.maxTotalThreadsPerThreadgroup, count), height: 1, depth: 1)
    encoder.dispatchThreads(threadCount, threadsPerThreadgroup: tgSize)
    encoder.endEncoding()

    cmdBuf.commit()
    cmdBuf.waitUntilCompleted()

    guard cmdBuf.status == .completed else { throw NoiseHarnessError.renderFailed }

    let ptr = outputBuf.contents().bindMemory(to: Float.self, capacity: outCount)
    return Array(UnsafeBufferPointer(start: ptr, count: outCount))
}

// MARK: - Helpers

/// A fixed set of deterministic float3 test positions spanning the unit cube
/// and beyond. Used across all noise property tests for consistency.
let noiseTestPositions: [SIMD3<Float>] = {
    var pts: [SIMD3<Float>] = []
    // 5×5×4 grid in [-2, 2]
    for i in 0..<5 {
        for j in 0..<5 {
            for k in 0..<4 {
                let x = Float(i) * 1.0 - 2.0
                let y = Float(j) * 1.0 - 2.0
                let z = Float(k) * (4.0 / 3.0) - 2.0
                pts.append(SIMD3<Float>(x, y, z))
            }
        }
    }
    // Extra non-lattice positions
    pts.append(SIMD3<Float>( 0.37,  1.81, -0.52))
    pts.append(SIMD3<Float>(-1.23,  0.07,  2.14))
    pts.append(SIMD3<Float>( 3.14, -1.59,  0.27))
    return pts
}()
