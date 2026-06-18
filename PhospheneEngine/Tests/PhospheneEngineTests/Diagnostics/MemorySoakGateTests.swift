// MemorySoakGateTests — CLEAN.4.7 / GAP-16: peak-RSS leak regression gate.
//
// The SoakTestHarness + the 5-minute memory check OBSERVE memory growth but assert
// nothing ("observability only" — G16). This is the missing regression GATE: it drives
// the per-frame steady-state paths for a fixed frame count and fails if `phys_footprint`
// grows beyond a leak budget after a warmup window.
//
// Frame-count-based (not wall-clock) so it is deterministic in CI. A real per-frame leak
// (whole objects accumulating — KBs/frame) shows as tens of MB over the soak; allocator
// noise/fragmentation is a few MB, so the 25 MB budget catches leaks without flaking. The
// full 2-hour steady-state growth curve stays a manual diagnostic via `SoakRunner`.

import Testing
import Foundation
import Metal
@testable import Audio
@testable import DSP
@testable import Diagnostics
@testable import Shared

// `phys_footprint` is process-wide, so this gate is only meaningful run ISOLATED:
//
//   SOAK_TESTS=1 swift test --package-path PhospheneEngine --filter MemorySoakGate
//
// Under the normal parallel `swift test` / closeout, other suites' allocations (GPU
// buffers, stem models) swamp the measurement — a full-suite run showed +625 MB of
// unrelated churn. So, like the SoakTestHarness 5-minute check, the tests early-return
// unless `SOAK_TESTS=1`. `.serialized` keeps the two soaks from overlapping each other.
@Suite("Memory soak gate (CLEAN.4.7 / GAP-16)", .serialized)
struct MemorySoakGateTests {

    /// Leak budget after warmup. Generous on purpose — a real per-frame leak is far larger,
    /// and a tight budget would flake on allocator noise. Tune down only with evidence.
    private static let leakBudgetMB = 25.0

    private func growthMB(from baseline: MemorySnapshot, to final: MemorySnapshot) -> Double {
        (Double(final.residentBytes) - Double(baseline.residentBytes)) / (1024 * 1024)
    }

    /// 1024-sample frames carved from a slightly-varying sine so the pipeline exercises real
    /// allocation patterns rather than one cached frame.
    private func makeFrames() -> [[Float]] {
        let base = AudioFixtures.sineWave(frequency: 440, sampleRate: 48_000, duration: 0.25)
        return stride(from: 0, to: base.count - 1024, by: 1024).map { Array(base[$0..<$0 + 1024]) }
    }

    // MARK: - Primary per-frame path: FFT → MIR

    @Test("FFT→MIR per-frame path: phys_footprint growth bounded over a 2.5K-frame soak")
    func fftMIR_residentGrowthBounded() throws {
        guard ProcessInfo.processInfo.environment["SOAK_TESTS"] == "1" else { return }  // isolated only — see suite note
        guard let device = MTLCreateSystemDefaultDevice() else { throw MemorySoakError.noMetalDevice }
        let fft = try FFTProcessor(device: device)
        let mir = MIRPipeline()
        let frames = makeFrames()
        var mags = [Float](repeating: 0, count: 512)

        func drive(_ count: Int) {
            for i in 0..<count {
                fft.process(samples: frames[i % frames.count], sampleRate: 48_000)
                for j in 0..<512 { mags[j] = fft.magnitudeBuffer[j] }
                _ = mir.process(magnitudes: mags, fps: 60, time: Float(i) / 60.0, deltaTime: 1.0 / 60.0)
            }
        }

        // 2.5K frames keeps the gate ~5 s while still catching whole-object accumulation
        // (a gross leak is tens of MB; slow sub-KB/frame creep is the manual 2 h SoakRunner job).
        drive(500)                                     // warmup → steady state
        guard let baseline = MemoryReporter.snapshot() else { Issue.record("baseline snapshot failed"); return }
        drive(2_500)                                   // soak
        guard let final = MemoryReporter.snapshot() else { Issue.record("final snapshot failed"); return }

        let grown = growthMB(from: baseline, to: final)
        let grownStr = String(format: "%.1f", grown)
        #expect(grown < Self.leakBudgetMB,
            "FFT→MIR grew \(grownStr) MB over 2.5K frames after warmup — possible leak (CLEAN.4.7 / GAP-16 gate)")
    }

    // MARK: - Per-stem analysis path (heavier; smaller soak)

    @Test("StemAnalyzer per-frame path: phys_footprint growth bounded over a 1.2K-frame soak")
    func stemAnalyzer_residentGrowthBounded() throws {
        guard ProcessInfo.processInfo.environment["SOAK_TESTS"] == "1" else { return }  // isolated only — see suite note
        let stem = StemAnalyzer()
        let frames = makeFrames()
        let silence = [Float](repeating: 0, count: 1024)

        func drive(_ count: Int) {
            for i in 0..<count {
                let frame = frames[i % frames.count]
                _ = stem.analyze(stemWaveforms: [frame, frame, silence, silence], fps: 60)
            }
        }

        drive(200)                                     // warmup
        guard let baseline = MemoryReporter.snapshot() else { Issue.record("baseline snapshot failed"); return }
        drive(1_200)                                   // soak
        guard let final = MemoryReporter.snapshot() else { Issue.record("final snapshot failed"); return }

        let grown = growthMB(from: baseline, to: final)
        let grownStr = String(format: "%.1f", grown)
        #expect(grown < Self.leakBudgetMB,
            "StemAnalyzer grew \(grownStr) MB over 1.2K frames after warmup — possible leak (CLEAN.4.7 / GAP-16 gate)")
    }
}

private enum MemorySoakError: Error { case noMetalDevice }
