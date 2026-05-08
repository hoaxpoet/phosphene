// ArachneStateBuildTests — V.7.7C.2 (D-095) build state machine.
//
// Verifies the CPU-side foreground BuildState and the per-segment spider
// cooldown that replace V.7.5's beat-measured stage timing and 300 s session
// cooldown. The shader does NOT yet read Row 5 in Commit 2 — these tests
// exercise the Swift API only.
//
// Test coverage (V.7.7C.2 prompt VERIFICATION §10):
//   - WebGPU stride is exactly 96 bytes (Row 5 layout is correct).
//   - reset() lands the build at .frame with completionEmitted = false.
//   - Frame phase completes within ~3 s of effective time at expected pace.
//   - Completion event fires exactly once across a full build cycle.
//   - Spider pause halts build progress; resume advances from paused state.
//   - Per-segment cooldown prevents the spider re-firing until reset().
//   - Alternating-pair radial draw order matches the §5.5 spec for n=13.
//   - Polygon selection produces irregular polygons (no ±2°-equal gaps).
//   - Spiral chord radii are strictly inward (radius decreases with k).
//   - Drop accretion ages chords by laydown order.

import Testing
import Metal
@testable import Presets
import Shared
import simd

private enum ArachneBuildTestError: Error { case noMetalDevice }

private func midEnergyFV(deltaTime: Float = 1.0 / 60.0,
                         midAttRel: Float = 1.0) -> FeatureVector {
    var f = FeatureVector.zero
    f.deltaTime = deltaTime
    f.midAttRel = midAttRel
    return f
}

// V.7.7C.3 / D-095 — spider trigger reformulated to use `bassAttRel` (smoothed
// bass envelope) instead of the V.7.5 `subBass + bassAttackRatio < 0.55` pair,
// which session 2026-05-08T17-01-15Z confirmed was acoustically impossible on
// real music. `bassAttRel = 0.40` is comfortably above the 0.30 threshold.
private func bassTriggerFV(deltaTime: Float = 1.0 / 60.0,
                           bassAttRel: Float = 0.40) -> FeatureVector {
    var f = FeatureVector.zero
    f.deltaTime = deltaTime
    f.bassAttRel = bassAttRel
    f.subBass = 0.45             // legacy field; not consumed by trigger
    return f
}

private func bassTriggerStems(totalEnergy: Float = 0.20) -> StemFeatures {
    var s = StemFeatures.zero
    s.drumsEnergy = totalEnergy / 4
    s.bassEnergy = totalEnergy / 4
    s.otherEnergy = totalEnergy / 4
    s.vocalsEnergy = totalEnergy / 4
    return s
}

@Suite("ArachneStateBuild") struct ArachneStateBuildTests {

    // MARK: - Test 1: WebGPU stride is 96 bytes (V.7.7C.2 Sub-item 2 OPTION A)

    @Test("WebGPU.stride is exactly 96 bytes (Row 5 added cleanly)")
    func webGPUStrideIs96Bytes() {
        #expect(MemoryLayout<WebGPU>.stride == 96)
        #expect(MemoryLayout<WebGPU>.size == 96)
    }

    // MARK: - Test 2: reset() lands at .frame

    @Test("reset() leaves the build at .frame with completionEmitted = false")
    func buildStateResetsToFrame() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw ArachneBuildTestError.noMetalDevice
        }
        let state = try #require(ArachneState(device: device, seed: 42))
        state.reset()

        #expect(state.buildState.stage == .frame)
        #expect(state.buildState.frameProgress == 0)
        #expect(state.buildState.completionEmitted == false)
        #expect(state.buildState.radialIndex == 0)
        #expect(state.buildState.radialProgress == 0)
        #expect(state.buildState.spiralChordIndex == 0)
        #expect(state.buildState.anchors.count >= 4)
        #expect(state.buildState.anchors.count <= 6)
        #expect(state.buildState.radialDrawOrder.count == state.buildState.radialCount)
    }

    // MARK: - Test 3: Frame phase completes by ~3 s effective

    @Test("frame phase exits at stageElapsed ∈ [2.5, 3.5] s effective")
    func framePhaseCompletesByThreeSeconds() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw ArachneBuildTestError.noMetalDevice
        }
        let state = try #require(ArachneState(device: device, seed: 42))
        state.reset()

        // Drive 6 s wall-clock of mid_att_rel = 1 to overshoot the frame
        // phase (frameDuration = 3 s; pace = 1 + 0.18 ≈ 1.18 → effective 7 s).
        let dt: Float = 1.0 / 60.0
        for _ in 0..<360 {
            state.tick(features: midEnergyFV(deltaTime: dt, midAttRel: 1.0),
                       stems: .zero)
        }

        // Frame phase must have ended; transition stamp must fall in the
        // permissible window per V.7.7C.2 prompt §VERIFICATION 5.
        let frameToRadial = try #require(state.buildState.frameToRadialAtElapsed)
        #expect(frameToRadial >= 2.5)
        #expect(frameToRadial <= 3.5)
        #expect(state.buildState.stage != .frame)
    }

    // MARK: - Test 4: Completion event fires exactly once

    @Test("presetCompletionEvent fires exactly once over a full build cycle")
    func completionEventFiresExactlyOnce() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw ArachneBuildTestError.noMetalDevice
        }
        let state = try #require(ArachneState(device: device, seed: 42))
        state.reset()

        var receivedCount = 0
        let cancellable = state._presetCompletionEvent.sink { _ in
            receivedCount += 1
        }
        defer { cancellable.cancel() }

        // Force the BuildState into .stable directly to exercise the once-only
        // guard without driving 90 s of effective time. The advance helper
        // owns the gate; calling tick once in .stable should trip it once.
        state.buildState.stage = .stable
        state.buildState.completionEmitted = false

        // Drive 600 ticks (≈ 10 s wall) — the sink should fire exactly once.
        // Note: after the event fires, the migration crossfade kicks off
        // (1 s) and ends by rolling buildState into a fresh cycle (stage =
        // .frame, completionEmitted = false). So at end-of-test the flag
        // may not be true — the load-bearing assertion is on receivedCount.
        let dt: Float = 1.0 / 60.0
        for _ in 0..<600 {
            state.tick(features: midEnergyFV(deltaTime: dt, midAttRel: 0),
                       stems: .zero)
        }

        #expect(receivedCount == 1,
                "presetCompletionEvent must fire exactly once across a full cycle (got \(receivedCount))")
    }

    // MARK: - Test 5: Spider pause halts build progress

    @Test("spider pause halts build progress (radial accumulators frozen)")
    func spiderPauseHaltsBuildProgress() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw ArachneBuildTestError.noMetalDevice
        }
        let state = try #require(ArachneState(device: device, seed: 42))
        state.reset()
        // Pin the build into the radial phase at a known progress point so
        // the pause guard's effect on radialIndex / radialProgress is visible.
        state.buildState.stage = .radial
        state.buildState.radialIndex = 5
        state.buildState.radialProgress = 0.4

        // Force-active spider so spiderBlend > 0.01 every tick.
        #if DEBUG
        state.forceSpiderActive = true
        #endif

        let beforeIdx = state.buildState.radialIndex
        let beforeProgress = state.buildState.radialProgress

        // Drive 60 ticks at mid_att_rel = 1 — without the pause guard the
        // radial accumulators would have advanced by ~0.6.
        let dt: Float = 1.0 / 60.0
        for _ in 0..<60 {
            state.tick(features: midEnergyFV(deltaTime: dt, midAttRel: 1.0),
                       stems: .zero)
        }

        #expect(state.buildState.radialIndex == beforeIdx)
        #expect(state.buildState.radialProgress == beforeProgress)
        #expect(state.buildState.pausedBySpider == true)
    }

    // MARK: - Test 6: Per-segment spider cooldown

    @Test("per-segment cooldown prevents spider re-firing until reset()")
    func perSegmentSpiderCooldownPreventsRefiring() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw ArachneBuildTestError.noMetalDevice
        }
        let state = try #require(ArachneState(device: device, seed: 42))
        state.reset()

        // Drive 90 frames of trigger conditions. After ≥ 0.75 s the
        // accumulator fires and `spiderFiredInSegment` latches to true.
        let dt: Float = 1.0 / 60.0
        for _ in 0..<120 {
            state.tick(features: bassTriggerFV(deltaTime: dt),
                       stems: bassTriggerStems())
        }
        #expect(state.spiderFiredInSegment == true)
        let firstFireBlend = state.spiderBlend

        // Now drive enough time for the spider to fade out. Without trigger
        // conditions, `conditionMet` is false → spiderActive flips false →
        // blend ramps down. We avoid driving trigger conditions during this
        // settle window so the per-segment latch isn't tested against the
        // sustained accumulator (which would still be at ≥ 0.75 s).
        for _ in 0..<300 {
            state.tick(features: midEnergyFV(deltaTime: dt, midAttRel: 0),
                       stems: .zero)
        }
        #expect(state.spiderBlend < firstFireBlend) // faded
        #expect(state.spiderFiredInSegment == true) // STILL latched

        // Drive trigger conditions again. The accumulator can climb but the
        // per-segment guard MUST keep `spiderActive` from re-asserting.
        for _ in 0..<120 {
            state.tick(features: bassTriggerFV(deltaTime: dt),
                       stems: bassTriggerStems())
        }
        #expect(state.spiderActive == false)
        #expect(state.spiderFiredInSegment == true)

        // reset() re-arms the cooldown.
        state.reset()
        #expect(state.spiderFiredInSegment == false)
    }

    // MARK: - Test 7: Alternating-pair radial draw order for n = 13

    @Test("computeAlternatingPairOrder(13) = [0, 6, 1, 7, 2, 8, 3, 9, 4, 10, 5, 11, 12]")
    func alternatingPairOrderForN13() {
        let expected: [Int] = [0, 6, 1, 7, 2, 8, 3, 9, 4, 10, 5, 11, 12]
        #expect(ArachneState.computeAlternatingPairOrder(radialCount: 13) == expected)
    }

    @Test("computeAlternatingPairOrder(14) interleaves both halves evenly")
    func alternatingPairOrderForN14() {
        let expected: [Int] = [0, 7, 1, 8, 2, 9, 3, 10, 4, 11, 5, 12, 6, 13]
        #expect(ArachneState.computeAlternatingPairOrder(radialCount: 14) == expected)
    }

    // MARK: - Test 8: Polygon selection is irregular across many seeds

    @Test("polygon angular gaps never collapse to within ±2° of equal across 100 seeds")
    func polygonSelectionIsIrregular() {
        // Convert ±2° to radians for the gap-equality threshold.
        let threshold = (2.0 * Float.pi / 180.0)
        var symmetricCount = 0
        for seedSeed in 0..<100 {
            var rng = UInt32(seedSeed) &+ 1
            let polygon = ArachneState.selectPolygon(rng: &rng)
            let gaps = ArachneState.polygonAngularGaps(forSelection: polygon.anchors)
            guard let maxGap = gaps.max(), let minGap = gaps.min() else { continue }
            if (maxGap - minGap) <= threshold {
                symmetricCount += 1
            }
        }
        #expect(symmetricCount == 0,
                "Polygon should never collapse to angular-equal gaps; got \(symmetricCount) symmetric polygons over 100 seeds.")
    }

    // MARK: - Test 9: Spiral chord radii are strictly inward

    @Test("spiral chord radius strictly decreases with k (INWARD)")
    func spiralChordsAreInward() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw ArachneBuildTestError.noMetalDevice
        }
        let state = try #require(ArachneState(device: device, seed: 7))
        state.reset()
        let radii = state.buildState.spiralChordRadii
        #expect(!radii.isEmpty, "spiral chord radii should be precomputed by reset()")
        for k in 1..<radii.count {
            #expect(radii[k] < radii[k - 1],
                    "Chord \(k) radius (\(radii[k])) should be strictly less than chord \(k-1) (\(radii[k-1]))")
        }
    }

    // MARK: - Test 10: Drop accretion ages chords by laydown order

    @Test("spiralChordBirthTimes preserve laydown order across the spiral phase")
    func dropAccretionAgesChordsCorrectly() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw ArachneBuildTestError.noMetalDevice
        }
        let state = try #require(ArachneState(device: device, seed: 9))
        state.reset()

        // Force the build directly into the spiral phase with 5 chords total
        // so the test runs in O(seconds) rather than the full 30 s cycle.
        state.buildState.spiralRevolutions = 1
        state.buildState.radialCount = 5
        state.buildState.spiralChordsTotal = 5
        state.buildState.spiralChordRadii = (0..<5).map { 0.45 - Float($0) * 0.05 }
        state.buildState.spiralChordIndex = 0
        state.buildState.spiralChordProgress = 0
        state.buildState.spiralChordBirthTimes.removeAll()
        state.buildState.stage = .spiral
        state.buildState.stageElapsed = 0

        // perChord = 0.3 s effective. At pace 1 (mid_att_rel=0) wall-clock
        // matches effective time. Drive 2 s of wall-clock to lay all 5
        // chords (1.5 s effective is enough; 2 s leaves margin).
        let dt: Float = 1.0 / 60.0
        for _ in 0..<120 {
            state.tick(features: midEnergyFV(deltaTime: dt, midAttRel: 0),
                       stems: .zero)
        }

        // All chords should be laid; birth times must be strictly increasing.
        let births = state.buildState.spiralChordBirthTimes
        #expect(births.count == 5)
        for i in 1..<births.count {
            #expect(births[i] > births[i - 1],
                    "birthTime[\(i)] (\(births[i])) must exceed birthTime[\(i - 1)] (\(births[i - 1]))")
        }
    }
}
