// BUG012ConcurrencyTest — Regression coverage for the suspected race in
// BUG-012 (MPSGraph EXC_BAD_ACCESS in `StemFFTEngine.runForwardGraph`).
//
// The crash fired on `Thread 71 — com.phosphene.stemSeparator queue` after
// repeated `ML: force-dispatch after 2100ms` messages. The suspected failure
// class is `concurrency`: a force-dispatch from the scheduler races with an
// in-flight separation, producing a nil-pointer access at MPSGraph.run.
//
// The serial-queue analysis in `docs/QUALITY/KNOWN_ISSUES.md` BUG-012 says
// this shouldn't happen — `stemQueue` is a serial DispatchQueue and
// `performStemSeparation` cannot be concurrent with itself. This test
// regression-locks the related but stricter contract: `StemFFTEngine.forward`
// is safe to call from multiple threads concurrently, even though it
// shouldn't be reachable in production.
//
// If a future change ever exposes `StemFFTEngine` to two threads at once
// (e.g. by replacing the serial queue with a concurrent one, or by adding
// a second caller path that doesn't go through `stemQueue`), this test
// fires — both via the XCTAssert and via the BUG012Probe alarm.

import XCTest
import Metal
@testable import ML
@testable import Shared

final class BUG012ConcurrencyTest: XCTestCase {

    private var device: MTLDevice!

    override func setUpWithError() throws {
        guard let dev = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("No Metal device available")
        }
        device = dev
        BUG012Probe.resetForTesting()
    }

    override func tearDown() {
        super.tearDown()
        BUG012Probe.resetForTesting()
    }

    /// 4 threads × 3 forwards each on a single `StemFFTEngine`.
    /// Asserts every call returns the expected output shape and that the
    /// probe's `stemFFTEngineLive` lifecycle counter remains at 1 throughout.
    /// If the engine's `NSLock` serialization broke, the test would crash at
    /// MPSGraph.run with the same signature BUG-012 reported.
    func test_forward_isThreadSafeUnderConcurrentCallers() throws {
        let engine = try StemFFTEngine(device: device)
        XCTAssertEqual(BUG012Probe.snapshot().stemFFTEngineLive, 1)

        let signal = makeTestSignal()
        let expectedBins = StemFFTEngine.modelFrameCount * StemFFTEngine.nBins

        let group = DispatchGroup()
        let queue = DispatchQueue(
            label: "bug012.test.concurrent", qos: .userInitiated, attributes: .concurrent
        )

        let threadCount = 4
        let callsPerThread = 3
        let resultLock = NSLock()
        var observedSizes: [Int] = []
        observedSizes.reserveCapacity(threadCount * callsPerThread)

        for _ in 0..<threadCount {
            for _ in 0..<callsPerThread {
                group.enter()
                queue.async {
                    let (mag, phase) = engine.forward(mono: signal)
                    resultLock.lock()
                    observedSizes.append(mag.count)
                    observedSizes.append(phase.count)
                    resultLock.unlock()
                    group.leave()
                }
            }
        }

        let outcome = group.wait(timeout: .now() + 30)
        XCTAssertEqual(outcome, .success, "concurrent forwards did not complete within 30s")

        XCTAssertEqual(observedSizes.count, threadCount * callsPerThread * 2)
        for size in observedSizes {
            XCTAssertEqual(
                size, expectedBins,
                "every forward call should return \(expectedBins) bins; got \(size)"
            )
        }

        // After completion, the probe's in-flight counter must be back to 0.
        let snap = BUG012Probe.snapshot()
        XCTAssertEqual(snap.fftForwardInFlight, 0)
        XCTAssertEqual(snap.stemFFTEngineLive, 1)
    }

    /// Lifecycle test — the StemFFTEngine deinit must always decrement the
    /// live count. If this fails, the BUG-012 instrumentation would
    /// over-report engines after a crash and obscure the postmortem.
    func test_engine_deinit_decrementsLiveCount() throws {
        // After setUp's resetForTesting the count is 0.
        XCTAssertEqual(BUG012Probe.snapshot().stemFFTEngineLive, 0)
        do {
            let engine = try StemFFTEngine(device: device)
            _ = engine.forward(mono: makeTestSignal())
            XCTAssertEqual(BUG012Probe.snapshot().stemFFTEngineLive, 1)
        }
        // The engine left scope. Its deinit should have fired.
        XCTAssertEqual(BUG012Probe.snapshot().stemFFTEngineLive, 0)
    }

    // MARK: - Fixtures

    private func makeTestSignal() -> [Float] {
        let n = StemFFTEngine.requiredMonoSamples
        var signal = [Float](repeating: 0, count: n)
        let sr: Float = 44100
        for i in 0..<n {
            let t = Float(i) / sr
            signal[i] = 0.2 * sinf(2 * .pi * 220 * t)
        }
        return signal
    }
}
