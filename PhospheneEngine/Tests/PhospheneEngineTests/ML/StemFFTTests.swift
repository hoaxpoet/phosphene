// StemFFTTests — Correctness, performance, and thread-safety coverage
// for the MPSGraph-backed ``StemFFTEngine`` (Increment 3.1a).
//
// The GPU path is cross-validated against the preserved vDSP CPU fallback
// on the same machine by toggling ``StemFFTEngine/forceCPUFallback``.

import XCTest
import Metal
@testable import ML

final class StemFFTTests: XCTestCase {

    private var device: MTLDevice!

    override func setUpWithError() throws {
        guard let dev = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device available")
        }
        device = dev
    }

    // MARK: - Fixtures

    /// Deterministic sine + noise signal sized for exactly `modelFrameCount`
    /// STFT frames after center padding.
    private func testSignal() -> [Float] {
        let n = StemFFTEngine.requiredMonoSamples
        var signal = [Float](repeating: 0, count: n)
        let sr: Float = 44100
        var rngState: UInt64 = 0xC0FFEE
        for i in 0..<n {
            let t = Float(i) / sr
            let tone = 0.3 * sinf(2 * .pi * 440 * t)
                     + 0.2 * sinf(2 * .pi * 1320 * t)
            // LCG noise — deterministic and fast.
            rngState = rngState &* 6364136223846793005 &+ 1442695040888963407
            let r = Float(Int32(truncatingIfNeeded: rngState >> 32)) / Float(Int32.max)
            signal[i] = tone + 0.05 * r
        }
        return signal
    }

    // MARK: - Correctness

    func test_forward_matchesVDSP_withinTolerance() throws {
        let engine = try StemFFTEngine(device: device)
        let signal = testSignal()

        // GPU path
        engine.forceCPUFallback = false
        let (gpuMag, gpuPhase) = engine.forward(mono: signal)

        // CPU reference
        engine.forceCPUFallback = true
        let (cpuMag, cpuPhase) = engine.forward(mono: signal)

        XCTAssertEqual(gpuMag.count, cpuMag.count)
        XCTAssertEqual(gpuPhase.count, cpuPhase.count)

        var maxMagErr: Float = 0
        var meanPhaseErr: Float = 0
        var phaseCount: Float = 0
        for i in 0..<cpuMag.count {
            maxMagErr = max(maxMagErr, abs(gpuMag[i] - cpuMag[i]))

            // Only compare phases where the magnitude is non-negligible —
            // phase of near-zero bins is numerically meaningless.
            if cpuMag[i] > 1e-5 {
                // Wrap the difference into [-pi, pi].
                var d = gpuPhase[i] - cpuPhase[i]
                while d > .pi { d -= 2 * .pi }
                while d < -.pi { d += 2 * .pi }
                meanPhaseErr += abs(d)
                phaseCount += 1
            }
        }
        if phaseCount > 0 { meanPhaseErr /= phaseCount }

        XCTAssertLessThan(maxMagErr, 1e-3,
                          "GPU and CPU forward magnitudes disagree: max err \(maxMagErr)")
        XCTAssertLessThan(meanPhaseErr, 1e-2,
                          "GPU and CPU forward phases disagree: mean err \(meanPhaseErr)")
    }

    func test_inverse_roundTripPreservesSignal() throws {
        let engine = try StemFFTEngine(device: device)
        let signal = testSignal()

        // Forward + inverse on the GPU path, then compare to the input.
        engine.forceCPUFallback = false
        let (mag, phase) = engine.forward(mono: signal)
        let reconstructed = engine.inverse(
            magnitude: mag,
            phase: phase,
            nbFrames: StemFFTEngine.modelFrameCount,
            originalLength: signal.count
        )

        XCTAssertEqual(reconstructed.count, signal.count,
                       "Reconstructed length should match originalLength")

        // The first and last nFFT/2 samples have partial overlap-add
        // coverage; only assert strict equality over the fully-overlapped
        // interior window.
        let margin = StemFFTEngine.nFFT
        var maxErr: Float = 0
        for i in margin..<(signal.count - margin) {
            maxErr = max(maxErr, abs(reconstructed[i] - signal[i]))
        }
        XCTAssertLessThan(maxErr, 1e-3,
                          "Round-trip error too large in interior: \(maxErr)")
    }

    // MARK: - Performance

    func test_forward_performance_under100ms() throws {
        let engine = try StemFFTEngine(device: device)
        let signal = testSignal()

        // Prime the graph (first call includes compilation latency).
        _ = engine.forward(mono: signal)

        measure {
            _ = engine.forward(mono: signal)
        }

        // Hard assertion — a single warm call must finish in <100ms.
        let start = Date()
        _ = engine.forward(mono: signal)
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(
            elapsed, 0.1,
            "GPU forward took \(elapsed * 1000)ms (baseline is 100ms)"
        )
    }

    func test_inverse_performance_under100ms() throws {
        let engine = try StemFFTEngine(device: device)
        let signal = testSignal()
        let (mag, phase) = engine.forward(mono: signal)

        // Prime the inverse graph too.
        _ = engine.inverse(
            magnitude: mag, phase: phase,
            nbFrames: StemFFTEngine.modelFrameCount,
            originalLength: signal.count
        )

        measure {
            _ = engine.inverse(
                magnitude: mag, phase: phase,
                nbFrames: StemFFTEngine.modelFrameCount,
                originalLength: signal.count
            )
        }

        // Hard assertion — a single warm call must finish in <100ms.
        let start = Date()
        _ = engine.inverse(
            magnitude: mag, phase: phase,
            nbFrames: StemFFTEngine.modelFrameCount,
            originalLength: signal.count
        )
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(
            elapsed, 0.1,
            "GPU inverse took \(elapsed * 1000)ms (baseline is 100ms)"
        )
    }

    // MARK: - UMA

    func test_storageMode_allUMA() throws {
        let engine = try StemFFTEngine(device: device)
        for (i, mode) in engine.bufferStorageModes.enumerated() {
            XCTAssertEqual(mode, .shared,
                           "StemFFT buffer \(i) must use .storageModeShared for UMA zero-copy")
        }
    }

    // MARK: - Thread safety

    func test_threadSafety_concurrentCalls_noCrash() throws {
        let engine = try StemFFTEngine(device: device)
        let signal = testSignal()

        // Capture a reference result from a serial call.
        let (refMag, _) = engine.forward(mono: signal)

        // Hit forward() from four concurrent workers.
        let expectation = self.expectation(description: "concurrent forward")
        expectation.expectedFulfillmentCount = 4

        let queue = DispatchQueue(
            label: "com.phosphene.test.stemfft",
            attributes: .concurrent
        )

        for _ in 0..<4 {
            queue.async {
                let (mag, _) = engine.forward(mono: signal)
                XCTAssertEqual(mag.count, refMag.count)
                // Spot-check a handful of bins to prove the lock isn't
                // corrupting the output.
                for i in stride(from: 0, to: mag.count, by: 4096) {
                    XCTAssertLessThan(
                        abs(mag[i] - refMag[i]),
                        1e-4,
                        "Concurrent forward output diverged at index \(i)"
                    )
                }
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 30.0)
    }
}
