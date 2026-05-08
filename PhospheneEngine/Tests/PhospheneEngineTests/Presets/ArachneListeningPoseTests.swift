// ArachneListeningPoseTests — Unit tests for the V.7.7D listening-pose state
// machine (D-094).
//
// The state machine is CPU-side only — the shader contract `ArachneSpiderGPU`
// stays at 80 bytes. These tests exercise the public Swift API of `ArachneState`:
//
//   - At silence the listening pose stays at rest (target=0, EMA≈0).
//   - Sustained low-attack-ratio bass for ≥ 1.5 s drives the EMA toward 1.0.
//   - Easing the bass returns the EMA toward 0 over ~1 s.
//   - The GPU flush lifts tip[0]/tip[1] in clip-space Y by 0.5 × kSpiderScale × EMA.
//
// Trigger spec (FV-mapped per Sub-item 4 note in V.7.7D prompt):
//   f.bassDev > 0.30 AND stems.bassAttackRatio ∈ (0, 0.55)

import Testing
import Metal
@testable import Presets
import Shared

private enum ArachneListeningTestError: Error { case noMetalDevice }

private func makeFV(bassDev: Float, deltaTime: Float = 1.0 / 60.0) -> FeatureVector {
    var f = FeatureVector.zero
    f.bassDev = bassDev
    f.deltaTime = deltaTime
    return f
}

private func makeStems(bassAttackRatio: Float, totalEnergy: Float = 0.1) -> StemFeatures {
    var s = StemFeatures.zero
    s.bassAttackRatio = bassAttackRatio
    s.drumsEnergy = totalEnergy / 4
    s.bassEnergy  = totalEnergy / 4
    s.otherEnergy = totalEnergy / 4
    s.vocalsEnergy = totalEnergy / 4
    return s
}

@Suite("ArachneListeningPose") struct ArachneListeningPoseTests {

    // MARK: - Test 1: silence keeps the pose at rest

    @Test("listening pose stays at rest at silence")
    func listenLiftQuiescentAtSilence() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw ArachneListeningTestError.noMetalDevice
        }
        let state = try #require(ArachneState(device: device, seed: 42))

        // 5 seconds of silence: bassDev = 0, no stems energy.
        let dt: Float = 1.0 / 60.0
        for _ in 0..<300 {
            state.tick(features: makeFV(bassDev: 0), stems: makeStems(bassAttackRatio: 0))
        }
        _ = dt

        #expect(state.listenLiftAccumulator == 0)
        #expect(state.listenLiftEMA < 0.01)
    }

    // MARK: - Test 2: sustained low-attack-ratio bass ramps the EMA up

    @Test("sustained low-attack-ratio bass drives EMA toward 1.0")
    func listenLiftRampsOnSustainedBass() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw ArachneListeningTestError.noMetalDevice
        }
        let state = try #require(ArachneState(device: device, seed: 42))

        // Hold the trigger for 5 seconds: bassDev = 0.50, attackRatio = 0.30.
        // Accumulator clamps at 1.5 s (the sustain threshold). After it reaches
        // the threshold, target=1.0 and the EMA exponentially approaches 1 with
        // τ=1 s, so after 5 s of sustained input it should be > 0.9.
        for _ in 0..<300 {
            state.tick(features: makeFV(bassDev: 0.50),
                       stems: makeStems(bassAttackRatio: 0.30))
        }

        #expect(state.listenLiftAccumulator >= ArachneState.listenLiftSustainThreshold - 0.001)
        #expect(state.listenLiftEMA > 0.9)
    }

    // MARK: - Test 3: easing the bass returns the EMA toward rest

    @Test("EMA returns toward rest as bass eases")
    func listenLiftRampsOffWhenBassEases() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw ArachneListeningTestError.noMetalDevice
        }
        let state = try #require(ArachneState(device: device, seed: 42))

        // Pump it up first.
        for _ in 0..<300 {
            state.tick(features: makeFV(bassDev: 0.50),
                       stems: makeStems(bassAttackRatio: 0.30))
        }
        let peakEMA = state.listenLiftEMA
        #expect(peakEMA > 0.9)

        // Now ease the bass: bassDev = 0 (silence). Hold for 3 seconds.
        for _ in 0..<180 {
            state.tick(features: makeFV(bassDev: 0), stems: makeStems(bassAttackRatio: 0))
        }

        // Accumulator drains in 1.5 s; EMA target snaps to 0 then exponentially
        // decays with τ=1 s. After 1.5 s of drain + 1.5 s of decay, expect < 0.3.
        #expect(state.listenLiftAccumulator == 0)
        #expect(state.listenLiftEMA < 0.3)
    }

    // MARK: - Test 4: GPU flush lifts tip[0]/tip[1] in clip-space Y

    @Test("flush applies tip lift to legs 0+1 in clip-space Y")
    func gpuFlushAppliesTipLift() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw ArachneListeningTestError.noMetalDevice
        }
        let state = try #require(ArachneState(device: device, seed: 42))

        // Drive the EMA close to 1.0 with sustained bass.
        for _ in 0..<300 {
            state.tick(features: makeFV(bassDev: 0.50),
                       stems: makeStems(bassAttackRatio: 0.30))
        }
        let liftEMA = state.listenLiftEMA
        #expect(liftEMA > 0.9)

        // Capture the un-lifted tips (CPU state is not mutated by writeSpiderToGPU).
        let cpuTip0 = state.spiderLegTips[0]
        let cpuTip1 = state.spiderLegTips[1]
        let cpuTip2 = state.spiderLegTips[2]

        // Read the GPU tips (this is the path the fragment shader sees).
        let ptr = state.spiderBuffer.contents().bindMemory(to: ArachneSpiderGPU.self, capacity: 1)
        let gpu = ptr[0]

        let expectedLift = ArachneState.listenLiftTipMagnitudeUV * liftEMA
        #expect(abs((gpu.tip0.y - cpuTip0.y) - expectedLift) < 1e-6)
        #expect(abs((gpu.tip1.y - cpuTip1.y) - expectedLift) < 1e-6)
        // Other tips must NOT receive the lift.
        #expect(abs(gpu.tip2.y - cpuTip2.y) < 1e-6)
    }
}
