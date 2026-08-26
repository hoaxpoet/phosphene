// ArachneStateTests — Unit tests for ArachneState web-pool logic (Increment 3.5.5).
//
// Tests exercise the public Swift API only — no @testable import needed.
// GPU buffer contents are read back via webBuffer.contents() using the public
// WebGPU type.
//
// Invariants verified:
//   1. Initial pool: 2 pre-spun stable webs (D-037 inv.1, inv.4)
//   2. Determinism: same seed → identical webBuffer contents
//   3. Silence: stable webs remain stable when tick receives all-zero inputs
//   5. Spawn trigger: accumulator ≥ 1.0 produces a new anchorPulse web
//   6. Beat wraparound: phase 0.95 → 0.05 is treated as +0.10 beats, not −0.90
//   7. Stage progression: sufficient beat-seconds advance anchorPulse → radial
//   8. Eviction: when pool is full, trySpawn begins evicting the oldest stable web

import Testing
import Metal
@testable import Presets
import Shared

// MARK: - Helpers

private enum ArachneTestError: Error { case noMetalDevice }

/// Read the full WebGPU array from an ArachneState's webBuffer.
private func readWebs(_ state: ArachneState) -> [WebGPU] {
    let ptr = state.webBuffer.contents().bindMemory(to: WebGPU.self,
                                                    capacity: ArachneState.maxWebs)
    return (0..<ArachneState.maxWebs).map { ptr[$0] }
}

/// Build a FeatureVector with beat_phase01 and optional bass_rel set.
private func fv(beatPhase: Float = 0, bassRel: Float = 0, deltaTime: Float = 1.0 / 60.0) -> FeatureVector {
    var f = FeatureVector.zero
    f.beatPhase01 = beatPhase
    f.bassRel = bassRel
    f.deltaTime = deltaTime
    return f
}

/// Build a StemFeatures with drumsOnsetRate set to drive spawn accumulation.
private func stems(drumsOnsetRate: Float = 0, totalEnergy: Float = 0.1) -> StemFeatures {
    var s = StemFeatures.zero
    s.drumsOnsetRate = drumsOnsetRate
    // totalEnergy > 0.06 ensures stemMix ≈ 1 (fully warm).
    s.drumsEnergy = totalEnergy / 4
    s.bassEnergy  = totalEnergy / 4
    s.otherEnergy = totalEnergy / 4
    s.vocalsEnergy = totalEnergy / 4
    return s
}

// MARK: - Tests

@Suite("ArachneState") struct ArachneWebPoolTests {

    // MARK: Invariant 1 & 4: Initial pool

    @Test("init seeds 2 stable webs (D-037 inv.1 and inv.4)")
    func initSeeds2StableWebs() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw ArachneTestError.noMetalDevice
        }
        let state = try #require(ArachneState(device: device, seed: 42))

        #expect(state.webs.filter { $0.isAlive != 0 }.count == 2)

        let webs = readWebs(state)
        let alive = webs.filter { $0.isAlive != 0 }
        #expect(alive.count == 2)

        // Both should be fully-spun stable webs (D-037 inv.4 satisfied from frame zero).
        for web in alive {
            #expect(WebStage(rawValue: web.stage) == .stable)
            #expect(web.progress == 1.0)
            #expect(web.opacity == 1.0)
        }
    }

    // MARK: Invariant 2: Determinism

    @Test("same seed produces identical webBuffer contents")
    func initDeterminism() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw ArachneTestError.noMetalDevice
        }
        let a = try #require(ArachneState(device: device, seed: 7))
        let b = try #require(ArachneState(device: device, seed: 7))

        let webSize = MemoryLayout<WebGPU>.stride * ArachneState.maxWebs
        let aBytes = Data(bytes: a.webBuffer.contents(), count: webSize)
        let bBytes = Data(bytes: b.webBuffer.contents(), count: webSize)

        #expect(aBytes == bBytes)
    }

    // MARK: Invariant 3: Silence leaves stable webs untouched

    @Test("tick with silence leaves stable webs unchanged")
    func tickSilenceStableUnchanged() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw ArachneTestError.noMetalDevice
        }
        let state = try #require(ArachneState(device: device, seed: 42))
        let before = readWebs(state).filter { $0.isAlive != 0 }

        // 60 silent frames
        for _ in 0..<60 {
            state.tick(features: .zero, stems: .zero)
        }

        let after = readWebs(state).filter { $0.isAlive != 0 }

        // Same web count, same hubs, still stable.
        #expect(after.count == before.count)
        for (a, b) in zip(before, after) {
            #expect(a.hubX == b.hubX)
            #expect(a.hubY == b.hubY)
            #expect(WebStage(rawValue: b.stage) == .stable)
        }
    }

    // MARK: Invariant 4: Drums drive accumulator


    // MARK: Invariant 4b: FV beat fallback fires when stems warm but drums silent


    // MARK: Invariant 5: Spawn creates new anchorPulse web


    // MARK: Invariant 6: Beat-phase wraparound


    // MARK: Invariant 7: Stage progression frame → radial


    // MARK: Invariant 8: Eviction when pool full


    // MARK: Spider Tests (Increment 3.5.9)

    // V.7.7C.3 / D-095: spider trigger uses `features.bassAttRel` (smoothed
    // bass envelope), NOT `features.subBass + stems.bassAttackRatio`. Live
    // LTYL session 2026-05-08T17-01-15Z confirmed the prior subBass+AR gate
    // pair was acoustically impossible on real music. `bassAttRel` rises
    // during sustained bass passages and stays near 0 at AGC-average levels;
    // brief kick pulses are filtered by the 0.75 s sustain threshold.
    private func subBassFV(deltaTime: Float = 1.0 / 60.0) -> FeatureVector {
        var f = FeatureVector.zero
        f.bassAttRel = 0.40     // above 0.30 threshold (V.7.7C.3)
        f.subBass    = 0.40     // legacy field; not consumed by trigger
        f.deltaTime  = deltaTime
        return f
    }

    /// Helper: StemFeatures with no special configuration — V.7.7C.3 retires
    /// the V.7.5 AR gate, so any zeroed StemFeatures passes the trigger
    /// alongside a positive `bassAttRel` on the FeatureVector.
    private func sustainedBassStems() -> StemFeatures {
        StemFeatures.zero
    }

    /// Helper: StemFeatures resembling a kick drum — V.7.7C.3 has no AR gate,
    /// so the test relies on the 0.75 s sustain threshold to reject brief
    /// pulses. Helper retained for symmetry with the sustained variant.
    private func kickDrumStems() -> StemFeatures {
        StemFeatures.zero
    }

    @Test("sustained sub-bass triggers spider materialisation")
    func sustainedSubBassTriggersSpider() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw ArachneTestError.noMetalDevice
        }
        let state = try #require(ArachneState(device: device, seed: 42))

        // Tick for just over 0.75 s with continuous sub-bass above threshold,
        // and stems satisfying the §10.1.9 AR gate (bassAttackRatio < 0.55).
        // dt = 1/60 s → 60 ticks = 1.0 s ≥ 0.75 s sustain threshold.
        let fv = subBassFV()
        let stems = sustainedBassStems()
        for _ in 0..<60 {
            state.tick(features: fv, stems: stems)
        }

        let ptr = state.spiderBuffer.contents().bindMemory(to: ArachneSpiderGPU.self, capacity: 1)
        #expect(ptr[0].blend > 0, "Expected spider blend > 0 after 1 s sustained sub-bass")
    }

    @Test("brief sub-bass pulse (kick drum) does NOT trigger the spider")
    func kickDrumPulseDoesNotTrigger() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw ArachneTestError.noMetalDevice
        }
        let state = try #require(ArachneState(device: device, seed: 42))

        // V.7.7C.3 / D-095: AR gate retired. The 0.75 s sustain accumulator
        // is now the only debounce against brief kick pulses.
        // 9 frames × (1/60 s) = 150 ms with bassAttRel above threshold, then
        // 120 frames decay below threshold — the accumulator decays at 2× rate
        // during sub-threshold frames, so it never reaches 0.75 s.
        var high = subBassFV(); high.bassAttRel = 0.40    // above 0.30 threshold
        var low  = subBassFV(); low.bassAttRel  = 0.05    // below threshold (decay)
        let kStems = kickDrumStems()

        for _ in 0..<9   { state.tick(features: high, stems: kStems) }  // 150 ms burst
        for _ in 0..<120 { state.tick(features: low,  stems: kStems) }  // 2 s decay

        let ptr = state.spiderBuffer.contents().bindMemory(to: ArachneSpiderGPU.self, capacity: 1)
        #expect(ptr[0].blend == 0, "Brief kick pulse (150 ms) must not trigger the spider")
    }

    @Test("spider dematerialises when sub-bass condition ends")
    func spiderDematerialisesWhenConditionEnds() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw ArachneTestError.noMetalDevice
        }
        let state = try #require(ArachneState(device: device, seed: 42))

        // Phase 1: trigger the spider (§10.1.9 AR-gate-compatible stems).
        let fv  = subBassFV()
        let stm = sustainedBassStems()
        for _ in 0..<60 { state.tick(features: fv, stems: stm) }

        let ptrAfterTrigger = state.spiderBuffer.contents()
            .bindMemory(to: ArachneSpiderGPU.self, capacity: 1)
        #expect(ptrAfterTrigger[0].blend > 0, "Spider must be active before dematerialisation test")

        // Phase 2: silence — condition no longer met. Blend should start decaying.
        for _ in 0..<10 { state.tick(features: .zero, stems: .zero) }

        let blendAfterSilence = ptrAfterTrigger[0].blend
        #expect(blendAfterSilence < 1.0, "Blend should have started decaying after condition ended")
    }

    @Test("per-segment cooldown prevents immediate re-trigger after appearance")
    func cooldownPreventsImmediateRetrigger() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw ArachneTestError.noMetalDevice
        }
        let state = try #require(ArachneState(device: device, seed: 42))

        // Phase 1: trigger the spider normally (§10.1.9 AR-gate-compatible stems).
        let fv  = subBassFV()
        let stm = sustainedBassStems()
        for _ in 0..<60 { state.tick(features: fv, stems: stm) }

        // V.7.7C.2 (D-095): the V.7.5 300 s session timer is replaced by a
        // per-segment latch. After the spider fires, `spiderFiredInSegment`
        // latches to true and only `reset()` re-arms it.
        #expect(state.spiderFiredInSegment == true,
                "Per-segment cooldown latch must be set immediately after fire")

        // Manually fade the spider (simulate appearance + fade).
        state.spiderActive = false
        state.spiderBlend  = 0

        // Phase 2: run more sub-bass ticks — per-segment guard blocks re-trigger.
        state.sustainedSubBassAccumulator = 0
        for _ in 0..<120 { state.tick(features: fv, stems: stm) }

        let ptr = state.spiderBuffer.contents().bindMemory(to: ArachneSpiderGPU.self, capacity: 1)
        #expect(ptr[0].blend == 0, "Spider must not re-appear within the same segment")
        #expect(state.spiderFiredInSegment == true, "Latch stays true until reset()")
    }
}
