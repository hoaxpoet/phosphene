// UtilityPerformanceHarness.swift — GPU-timestamp-based benchmark harness for V.4.
//
// Measures GPU execution time of shader utility functions in microseconds using
// MTLCommandBuffer.gpuStartTime / gpuEndTime (wall-clock accurate GPU timestamps).
//
// Design:
//   - Each benchmark executes a single utility function in a compute kernel over a
//     full-screen 1920×1080 grid (2,073,600 threads) — realistic fragment-shader load.
//   - Warm-up: 8 iterations discarded to bring GPU to steady state.
//   - Measurement: 32 iterations → median returned (outlier-robust).
//   - Result: microseconds per 1080p pass. Divide by 1000 for ms.
//
// Requires a real MTLDevice (skipped on simulators). All benchmarks are tagged
// @Test(timeLimit: ...) to avoid CI timeout on slower machines.

import Testing
import Foundation
import Metal
@testable import Presets

// MARK: - Result type

struct PerformanceSample {
    let function: String
    let medianMicroseconds: Double
    let minMicroseconds: Double
    let maxMicroseconds: Double
    let sampleCount: Int
}

// MARK: - Harness entry point

/// Run a GPU compute benchmark on a 1920×1080 grid.
///
/// `kernelSource`: MSL fragment (just the body) wrapped in a `fullscreen_compute_kernel`.
/// `warmupIterations`: runs before measurement (discarded). Default 8.
/// `measureIterations`: timed runs. Default 32. Median returned.
///
/// Returns nil if no MTLDevice is available.
func runGPUBenchmark(
    function: String,
    kernelSource: String,
    warmupIterations: Int = 8,
    measureIterations: Int = 32
) throws -> PerformanceSample? {
    guard let device = MTLCreateSystemDefaultDevice() else { return nil }
    guard device.supportsFamily(.apple6) else { return nil }  // M1+ required for GPU timestamps

    let fullSource = PresetLoader.shaderPreamble + "\n\n" + makeComputeKernel(body: kernelSource)

    let options = MTLCompileOptions()
    options.fastMathEnabled = true
    options.languageVersion = .version3_1

    let library: MTLLibrary
    do {
        library = try device.makeLibrary(source: fullSource, options: options)
    } catch {
        throw NoiseHarnessError.libraryCompilationFailed("\(error)")
    }

    guard let fn = library.makeFunction(name: "perf_kernel") else {
        throw NoiseHarnessError.kernelNotFound("perf_kernel")
    }

    let pipeline: MTLComputePipelineState
    do {
        pipeline = try device.makeComputePipelineState(function: fn)
    } catch {
        throw NoiseHarnessError.pipelineFailed
    }

    // Output buffer: 1 float per thread (suppress dead-code elimination).
    let threadCount = 1920 * 1080
    guard let outputBuf = device.makeBuffer(
        length: threadCount * MemoryLayout<Float>.size,
        options: .storageModeShared
    ) else { throw NoiseHarnessError.bufferAllocationFailed }

    guard let queue = device.makeCommandQueue() else {
        throw NoiseHarnessError.commandBufferFailed
    }

    // Warm-up
    for _ in 0..<warmupIterations {
        try encodeAndCommit(device: device, queue: queue, pipeline: pipeline,
                            outputBuf: outputBuf, threadCount: threadCount,
                            waitForCompletion: true)
    }

    // Measurement
    var gpuTimes: [Double] = []
    for _ in 0..<measureIterations {
        let elapsed = try encodeAndCommit(device: device, queue: queue, pipeline: pipeline,
                                          outputBuf: outputBuf, threadCount: threadCount,
                                          waitForCompletion: true)
        gpuTimes.append(elapsed)
    }

    gpuTimes.sort()
    let median = gpuTimes[gpuTimes.count / 2]
    return PerformanceSample(
        function: function,
        medianMicroseconds: median,
        minMicroseconds: gpuTimes.first ?? median,
        maxMicroseconds: gpuTimes.last ?? median,
        sampleCount: measureIterations
    )
}

// MARK: - Internal dispatch

@discardableResult
private func encodeAndCommit(
    device: MTLDevice,
    queue: MTLCommandQueue,
    pipeline: MTLComputePipelineState,
    outputBuf: MTLBuffer,
    threadCount: Int,
    waitForCompletion: Bool
) throws -> Double {
    guard let cmd = queue.makeCommandBuffer() else { throw NoiseHarnessError.commandBufferFailed }
    guard let enc = cmd.makeComputeCommandEncoder() else { throw NoiseHarnessError.commandBufferFailed }

    enc.setComputePipelineState(pipeline)
    enc.setBuffer(outputBuf, offset: 0, index: 0)

    let tgSize = MTLSize(width: pipeline.maxTotalThreadsPerThreadgroup, height: 1, depth: 1)
    let gridSize = MTLSize(width: threadCount, height: 1, depth: 1)
    enc.dispatchThreads(gridSize, threadsPerThreadgroup: tgSize)
    enc.endEncoding()

    cmd.commit()
    if waitForCompletion { cmd.waitUntilCompleted() }

    let gpuStart = cmd.gpuStartTime
    let gpuEnd   = cmd.gpuEndTime
    return (gpuEnd - gpuStart) * 1_000_000  // seconds → microseconds
}

// MARK: - Kernel wrapper

private func makeComputeKernel(body: String) -> String {
    """
    kernel void perf_kernel(
        device float* output [[buffer(0)]],
        uint tid [[thread_position_in_grid]])
    {
        // Map thread id to fake 2D screen position
        float2 uv   = float2(float(tid % 1920) / 1920.0,
                             float(tid / 1920) / 1080.0);
        float3 wp   = float3(uv * 2.0 - 1.0, 0.0);
        float3 n    = float3(0.0, 0.0, 1.0);
        float  t    = float(tid) * 0.001;

        float result = 0.0;
        \(body)

        output[tid] = result;
    }
    """
}

// MARK: - JSON serialization

struct PerformanceReport: Codable {
    let generatedAt: String
    let deviceName: String
    let deviceTier: String
    let results: [PerformanceEntry]
}

struct PerformanceEntry: Codable {
    let function: String
    let category: String
    let medianMicroseconds: Double
    let minMicroseconds: Double
    let maxMicroseconds: Double
    let notes: String
}

func buildReport(samples: [(PerformanceSample, category: String, notes: String)]) -> PerformanceReport {
    let device = MTLCreateSystemDefaultDevice()
    let deviceName = device?.name ?? "Unknown"
    let tier: String = {
        if let d = device, d.supportsFamily(.apple8) { return "tier2" }
        return "tier1"
    }()

    let entries = samples.map { (sample, category, notes) in
        PerformanceEntry(
            function: sample.function,
            category: category,
            medianMicroseconds: (sample.medianMicroseconds * 10).rounded() / 10,
            minMicroseconds: (sample.minMicroseconds * 10).rounded() / 10,
            maxMicroseconds: (sample.maxMicroseconds * 10).rounded() / 10,
            notes: notes
        )
    }
    let dateStr = ISO8601DateFormatter().string(from: Date())
    return PerformanceReport(
        generatedAt: dateStr,
        deviceName: deviceName,
        deviceTier: tier,
        results: entries
    )
}
