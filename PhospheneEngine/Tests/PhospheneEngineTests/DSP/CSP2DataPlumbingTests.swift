// CSP2DataPlumbingTests — Lock the CSP.2 (2026-05-27) data-flow contracts.
//
// Two contracts:
//   1. `FeatureVector.trackElapsedS` reflects MIRPipeline.elapsedSeconds and
//      resets to 0 on `MIRPipeline.reset()` (the track-change call).
//   2. `RenderPipeline.setCachedBassProportion(_:)` value is preserved across
//      subsequent `setStemFeatures(_:)` calls. Live per-frame stem analysis
//      must NOT overwrite the cached preview-derived bass proportion.
//
// These tests guard the load-bearing plumbing for Ferrofluid Ocean's
// cold-start spike-height fix (CSP.2 Layers 1 + 2). See CLAUDE.md
// §Cold-Start Phase Contract.

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

// MARK: - Suite 1: trackElapsedS reflects MIRPipeline.elapsedSeconds

@Suite("CSP.2 — trackElapsedS plumbing")
struct CSP2TrackElapsedSTests {

    @Test func freshPipeline_trackElapsedS_isZeroAtFirstFrame() {
        let pipeline = MIRPipeline()
        // First frame: elapsedSeconds accumulates by deltaTime, so it
        // won't be exactly 0 after the call. Drive a single very-small-
        // deltaTime frame and check the result is small.
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
        // 60 frames at 1/60 s = 1.0 s.
        let fv = driveFrames(pipeline, frames: 60)
        #expect(fv.trackElapsedS > 0.99 && fv.trackElapsedS < 1.01,
                "After 60 × 1/60s frames, trackElapsedS = \(fv.trackElapsedS) — expected ≈ 1.0")
    }

    @Test func trackElapsedS_resetsToZeroOnPipelineReset() {
        let pipeline = MIRPipeline()
        // Accumulate to ~5 s, then reset, then take one tiny frame.
        _ = driveFrames(pipeline, frames: 300)         // 5.0 s
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

    @Test func trackElapsedS_matchesElapsedSecondsCast() {
        let pipeline = MIRPipeline()
        // Drive 7.3 s. Float-cast of `elapsedSeconds` should equal `fv.trackElapsedS`.
        let fv = driveFrames(pipeline, frames: 438)    // 7.3 s
        let expected = Float(pipeline.elapsedSeconds)
        #expect(abs(fv.trackElapsedS - expected) < 1e-5,
                "trackElapsedS=\(fv.trackElapsedS), elapsedSeconds=\(pipeline.elapsedSeconds), cast=\(expected)")
    }
}

// MARK: - Suite 2: cachedBassProportion preserved across live setStemFeatures

@Suite("CSP.2 — cachedBassProportion preservation")
struct CSP2CachedBassProportionTests {

    private static func makePipeline() throws -> RenderPipeline {
        let context = try MetalContext()
        let library = try ShaderLibrary(context: context)
        let floatStride = MemoryLayout<Float>.stride
        guard
            let fftBuf = context.makeSharedBuffer(length: 512 * floatStride),
            let waveBuf = context.makeSharedBuffer(length: 2048 * floatStride)
        else {
            throw CSP2PlumbingError.bufferAllocationFailed
        }
        return try RenderPipeline(
            context: context,
            shaderLibrary: library,
            fftBuffer: fftBuf,
            waveformBuffer: waveBuf
        )
    }

    enum CSP2PlumbingError: Error {
        case bufferAllocationFailed
    }

    @Test func setCachedBassProportion_storesValueInLatestStemFeatures() throws {
        let pipeline = try Self.makePipeline()
        pipeline.setCachedBassProportion(0.42)
        let snapshot = pipeline.currentStemFeatures()
        #expect(abs(snapshot.cachedBassProportion - 0.42) < 1e-5,
                "After setCachedBassProportion(0.42), snapshot.cachedBassProportion = \(snapshot.cachedBassProportion)")
    }

    @Test func setStemFeatures_preservesCachedBassProportion() throws {
        let pipeline = try Self.makePipeline()
        pipeline.setCachedBassProportion(0.33)

        // Live per-frame analysis result with a DIFFERENT cachedBassProportion
        // value (the live analyzer shouldn't be setting this, but defensively
        // we want to confirm the field is preserved even if it does).
        var liveFeatures = StemFeatures(
            vocalsEnergy: 0.1, drumsEnergy: 0.4,
            bassEnergy: 0.3, otherEnergy: 0.2
        )
        liveFeatures.bassEnergyDev = 0.5     // live per-frame value
        liveFeatures.cachedBassProportion = 0.99  // contender — should be ignored

        pipeline.setStemFeatures(liveFeatures)
        let snapshot = pipeline.currentStemFeatures()

        // Live fields take effect (the energy values, the dev primitives).
        #expect(abs(snapshot.bassEnergy - 0.3) < 1e-5,
                "Live bassEnergy not applied: \(snapshot.bassEnergy)")
        #expect(abs(snapshot.bassEnergyDev - 0.5) < 1e-5,
                "Live bassEnergyDev not applied: \(snapshot.bassEnergyDev)")

        // But cachedBassProportion stays at the original setCachedBassProportion value.
        #expect(abs(snapshot.cachedBassProportion - 0.33) < 1e-5,
                "cachedBassProportion overwritten: \(snapshot.cachedBassProportion) — expected 0.33")
    }

    @Test func cachedBassProportion_survivesMultipleLiveUpdates() throws {
        let pipeline = try Self.makePipeline()
        pipeline.setCachedBassProportion(0.27)

        for i in 1...10 {
            var live = StemFeatures(bassEnergy: Float(i) * 0.05)
            live.cachedBassProportion = Float(i) * 0.10   // attempted contender each time
            pipeline.setStemFeatures(live)
        }

        let snapshot = pipeline.currentStemFeatures()
        #expect(abs(snapshot.cachedBassProportion - 0.27) < 1e-5,
                "After 10 live updates, cachedBassProportion = \(snapshot.cachedBassProportion) — expected 0.27")
    }

    @Test func setCachedBassProportion_overridesPreviousValue() throws {
        let pipeline = try Self.makePipeline()
        pipeline.setCachedBassProportion(0.15)
        // Live updates happen in between.
        pipeline.setStemFeatures(StemFeatures(bassEnergy: 0.5))
        pipeline.setStemFeatures(StemFeatures(bassEnergy: 0.6))
        // Then a new cachedBassProportion is installed (e.g., track change).
        pipeline.setCachedBassProportion(0.41)
        let snapshot = pipeline.currentStemFeatures()
        #expect(abs(snapshot.cachedBassProportion - 0.41) < 1e-5,
                "After new setCachedBassProportion, value = \(snapshot.cachedBassProportion)")
    }
}
