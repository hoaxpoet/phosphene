// CSP3DataPlumbingTests — Lock the CSP.3 (2026-05-27) data-flow contracts.
//
// Three contracts:
//   1. `FeatureVector.trackElapsedS` reflects MIRPipeline.elapsedSeconds when
//      the `ffoColdStartFixEnabled` toggle is ON, resets to 0 on
//      `MIRPipeline.reset()` (track change).
//   2. When the toggle is OFF, `trackElapsedS` is written as 100.0
//      regardless of elapsed time, so the FFO shader's
//      `smoothstep(0.5, 14, ...)` returns 1.0 — the cold-start path
//      collapses to the warm path.
//   3. `RenderPipeline.setCachedBassProportion(_:)` value is preserved
//      across subsequent `setStemFeatures(_:)` calls. Live per-frame stem
//      analysis must NOT overwrite the cached preview-derived proportion.
//
// These guard the load-bearing plumbing for Ferrofluid Ocean's cold-start
// spike-height fix. See CLAUDE.md §Cold-Start Phase Contract.

import Testing
import Foundation
import Metal
@testable import DSP
@testable import Renderer
@testable import Shared

// MARK: - Helpers

private let testMagnitudes = AudioFixtures.uniformMagnitudes(magnitude: 0.5)

@discardableResult
private func driveFrames(_ pipeline: MIRPipeline, frames: Int, deltaTime: Float = 1.0 / 60.0) -> FeatureVector {
    var fv = FeatureVector.zero
    for i in 0..<frames {
        let t = Float(i) * deltaTime
        fv = pipeline.process(magnitudes: testMagnitudes, fps: 60, time: t, deltaTime: deltaTime)
    }
    return fv
}

// MARK: - Suite 1: trackElapsedS reflects MIRPipeline.elapsedSeconds (toggle ON)

@Suite("CSP.3 — trackElapsedS plumbing (toggle ON)")
struct CSP3TrackElapsedSOnTests {

    @Test func freshPipeline_trackElapsedS_isZeroAtFirstFrame() {
        let pipeline = MIRPipeline()
        // Default ffoColdStartFixEnabled = true.
        let fv = pipeline.process(
            magnitudes: testMagnitudes,
            fps: 60,
            time: 0,
            deltaTime: 1.0 / 1000.0
        )
        #expect(fv.trackElapsedS < 0.01,
                "First-frame trackElapsedS = \(fv.trackElapsedS) — expected ≈ 0")
    }

    @Test func trackElapsedS_accumulatesWithDeltaTime() {
        let pipeline = MIRPipeline()
        let fv = driveFrames(pipeline, frames: 60)         // 1.0 s @ 60 fps
        #expect(fv.trackElapsedS > 0.99 && fv.trackElapsedS < 1.01,
                "After 60 × 1/60s frames, trackElapsedS = \(fv.trackElapsedS) — expected ≈ 1.0")
    }

    @Test func trackElapsedS_resetsToZeroOnPipelineReset() {
        let pipeline = MIRPipeline()
        _ = driveFrames(pipeline, frames: 300)             // 5.0 s
        pipeline.reset()
        let fv = pipeline.process(
            magnitudes: testMagnitudes,
            fps: 60,
            time: 0,
            deltaTime: 1.0 / 1000.0
        )
        #expect(fv.trackElapsedS < 0.01,
                "After reset(), trackElapsedS = \(fv.trackElapsedS) — expected ≈ 0")
    }
}

// MARK: - Suite 2: toggle-OFF behaviour

@Suite("CSP.3 — trackElapsedS (toggle OFF)")
struct CSP3TrackElapsedSOffTests {

    @Test func toggleOff_trackElapsedS_isAlways100() {
        let pipeline = MIRPipeline()
        pipeline.ffoColdStartFixEnabled = false
        // First frame.
        let fv0 = pipeline.process(
            magnitudes: testMagnitudes, fps: 60, time: 0, deltaTime: 1.0 / 60.0
        )
        #expect(fv0.trackElapsedS == 100.0,
                "Toggle off, first frame: trackElapsedS = \(fv0.trackElapsedS) — expected 100.0")
        // After accumulating 5 s real time.
        let fv5 = driveFrames(pipeline, frames: 299)        // total 300 frames = 5.0 s real
        #expect(fv5.trackElapsedS == 100.0,
                "Toggle off, after 5 s real: trackElapsedS = \(fv5.trackElapsedS) — expected 100.0")
    }

    @Test func toggleOffThenOn_resumesNormalElapsed() {
        let pipeline = MIRPipeline()
        pipeline.ffoColdStartFixEnabled = false
        _ = driveFrames(pipeline, frames: 60)               // 1.0 s; trackElapsedS still 100
        pipeline.ffoColdStartFixEnabled = true
        let fv = pipeline.process(
            magnitudes: testMagnitudes, fps: 60, time: 0, deltaTime: 1.0 / 60.0
        )
        // After toggle flip, the next frame writes the actual elapsedSeconds
        // (which is ~1.0 + 1/60 s by now).
        #expect(fv.trackElapsedS > 1.0 && fv.trackElapsedS < 1.05,
                "After flipping toggle ON, trackElapsedS = \(fv.trackElapsedS) — expected ≈ 1.02")
    }
}

// MARK: - Suite 3: cachedBassProportion preservation across live updates

@Suite("CSP.3 — cachedBassProportion preservation")
struct CSP3CachedBassProportionTests {

    private static func makePipeline() throws -> RenderPipeline {
        let context = try MetalContext()
        let library = try ShaderLibrary(context: context)
        let floatStride = MemoryLayout<Float>.stride
        guard
            let fftBuf = context.makeSharedBuffer(length: 512 * floatStride),
            let waveBuf = context.makeSharedBuffer(length: 2048 * floatStride)
        else {
            throw CSP3PlumbingError.bufferAllocationFailed
        }
        return try RenderPipeline(
            context: context,
            shaderLibrary: library,
            fftBuffer: fftBuf,
            waveformBuffer: waveBuf
        )
    }

    enum CSP3PlumbingError: Error {
        case bufferAllocationFailed
    }

    @Test func setCachedBassProportion_storesValue() throws {
        let pipeline = try Self.makePipeline()
        pipeline.setCachedBassProportion(0.42)
        let snapshot = pipeline.currentStemFeatures()
        #expect(abs(snapshot.cachedBassProportion - 0.42) < 1e-5,
                "After setCachedBassProportion(0.42), snapshot = \(snapshot.cachedBassProportion)")
    }

    @Test func setStemFeatures_preservesCachedBassProportion() throws {
        let pipeline = try Self.makePipeline()
        pipeline.setCachedBassProportion(0.33)

        // Live per-frame analysis with a DIFFERENT cachedBassProportion (the
        // live analyzer wouldn't set this, but defensively we verify it's
        // ignored even if it does).
        var live = StemFeatures(
            vocalsEnergy: 0.1, drumsEnergy: 0.4,
            bassEnergy: 0.3, otherEnergy: 0.2
        )
        live.bassEnergyDev = 0.5            // live per-frame value
        live.cachedBassProportion = 0.99    // contender — must be ignored

        pipeline.setStemFeatures(live)
        let snapshot = pipeline.currentStemFeatures()

        // Live fields apply.
        #expect(abs(snapshot.bassEnergy - 0.3) < 1e-5,
                "Live bassEnergy not applied: \(snapshot.bassEnergy)")
        #expect(abs(snapshot.bassEnergyDev - 0.5) < 1e-5,
                "Live bassEnergyDev not applied: \(snapshot.bassEnergyDev)")

        // cachedBassProportion preserved at the previously-set value.
        #expect(abs(snapshot.cachedBassProportion - 0.33) < 1e-5,
                "cachedBassProportion overwritten: \(snapshot.cachedBassProportion) — expected 0.33")
    }

    @Test func cachedBassProportion_survivesManyLiveUpdates() throws {
        let pipeline = try Self.makePipeline()
        pipeline.setCachedBassProportion(0.27)

        for i in 1...10 {
            var live = StemFeatures(bassEnergy: Float(i) * 0.05)
            live.cachedBassProportion = Float(i) * 0.10
            pipeline.setStemFeatures(live)
        }

        let snapshot = pipeline.currentStemFeatures()
        #expect(abs(snapshot.cachedBassProportion - 0.27) < 1e-5,
                "After 10 live updates, cachedBassProportion = \(snapshot.cachedBassProportion) — expected 0.27")
    }
}
