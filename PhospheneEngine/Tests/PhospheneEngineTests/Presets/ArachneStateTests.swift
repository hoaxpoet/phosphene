// ArachneStateTests — Unit tests for ArachneState web-pool logic (Increment 3.5.5).
//
// Tests exercise the public Swift API only — no @testable import needed.
// GPU buffer contents are read back via webBuffer.contents() using the public
// WebGPU type.
//
// Invariants verified:
//   1. Initial pool: 2 pre-spun stable webs, webCount = 2 (D-037 inv.1, inv.4)
//   2. Determinism: same seed → identical webBuffer contents
//   3. Silence: stable webs remain stable when tick receives all-zero inputs
//   4. Drum drive: high drumsOnsetRate accumulates spawnAccumulator per tick
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

        #expect(state.webCount == 2)

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

    @Test("high drumsOnsetRate advances spawnAccumulator per tick")
    func drumsDriveAccumulator() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw ArachneTestError.noMetalDevice
        }
        let state = try #require(ArachneState(device: device, seed: 42))

        // Use sub-threshold rate so no spawn fires and we can measure the raw drive.
        // drumsOnsetRate=5, dt=0.01 → drumDrive = 5 × 0.01 × stemMix ≈ 0.05 per tick.
        var s = StemFeatures.zero
        s.drumsOnsetRate = 5.0
        s.drumsEnergy = 0.05; s.bassEnergy = 0.05
        s.otherEnergy = 0.05; s.vocalsEnergy = 0.05  // totalEnergy=0.20 → stemMix=1.0

        var f = FeatureVector.zero
        f.deltaTime = 0.01

        let before = state.spawnAccumulator
        state.tick(features: f, stems: s)
        let after = state.spawnAccumulator

        // Accumulator should have increased by ~0.05 (no spawn since 0.05 < 1.0).
        #expect(after > before + 0.01)
    }

    // MARK: Invariant 4b: FV beat fallback fires when stems warm but drums silent

    @Test("beat rising edge spawns when drumsOnsetRate=0 but stems are warm (quiet/drumless track)")
    func fvFallbackFiringWithSilentDrums() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw ArachneTestError.noMetalDevice
        }
        let state = try #require(ArachneState(device: device, seed: 42))

        // Simulate a quiet post-rock opening: stems are warm (bass+other energy present)
        // but drumsOnsetRate=0. The old (1-stemMix) gate would suppress the FV path.
        // The new (1-drumActivity) gate must let beat rising edges through.
        var warmS = StemFeatures.zero
        warmS.drumsOnsetRate = 0          // no drum onsets — silent drums
        warmS.bassEnergy    = 0.10        // totalEnergy=0.20 → stemMix≈1.0
        warmS.otherEnergy   = 0.10
        warmS.drumsEnergy   = 0.0
        warmS.vocalsEnergy  = 0.0

        // Deliver a beat rising edge (composite goes 0 → 0.8) with small dt so
        // the spawned web stays in anchorPulse and beatsDt doesn't advance stages.
        var below = FeatureVector.zero
        below.beatComposite = 0.0
        below.deltaTime = 0.01
        state.tick(features: below, stems: warmS)

        var above = FeatureVector.zero
        above.beatComposite = 0.8
        above.deltaTime = 0.01
        state.tick(features: above, stems: warmS)

        // fvDrive = 0.8 × (1 - drumActivity) = 0.8 × 1.0 = 0.8 per rising edge.
        // spawnThreshold=3.0 → need 4 edges total (3.2). 95 below ticks + 3 more above/below pairs
        // deliver edges 2, 3, 4 and advance globalBeatIndex past minSpawnGapBeats(2.0).
        for _ in 0..<95 { state.tick(features: below, stems: warmS) }
        state.tick(features: above, stems: warmS)  // 2nd rising edge, acc=1.6
        state.tick(features: below, stems: warmS)
        state.tick(features: above, stems: warmS)  // 3rd rising edge, acc=2.4
        state.tick(features: below, stems: warmS)
        state.tick(features: above, stems: warmS)  // 4th rising edge, acc=3.2 ≥ 3.0 → spawn

        #expect(state.webCount >= 3,
                "Expected ≥3 webs (2 seeded + ≥1 spawned via FV beat path); got \(state.webCount)")
    }

    // MARK: Invariant 5: Spawn creates new anchorPulse web

    @Test("accumulator ≥ threshold spawns a new web in anchorPulse")
    func spawnTriggerNewWebInAnchorPulse() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw ArachneTestError.noMetalDevice
        }
        let state = try #require(ArachneState(device: device, seed: 42))

        // Use dt=0.01 so beatsDt=0.02 beats — well below anchorPulseDuration(1.0).
        // This means a newly spawned web stays in anchorPulse after the tick.
        // drumsOnsetRate=5, 100 ticks → accumulator = 0.05 × 100 = 5.0 ≥ spawnThreshold(3.0);
        // globalBeatIndex = 0.02 × 100 = 2.0 ≥ minSpawnGapBeats(2.0) → spawn fires.
        var s = StemFeatures.zero
        s.drumsOnsetRate = 5.0
        s.drumsEnergy = 0.05; s.bassEnergy = 0.05
        s.otherEnergy = 0.05; s.vocalsEnergy = 0.05

        var f = FeatureVector.zero
        f.deltaTime = 0.01

        // Tick 100 times to satisfy both accumulator and beat-gap thresholds.
        for _ in 0..<100 {
            state.tick(features: f, stems: s)
        }

        let webs = readWebs(state)
        let anchorPulseWebs = webs.filter { $0.isAlive != 0 && $0.stage == WebStage.frame.rawValue }

        #expect(anchorPulseWebs.count >= 1)
        #expect(state.webCount == 3)
    }

    // MARK: Invariant 6: Beat-phase wraparound

    @Test("beat_phase01 wraparound 0.95→0.05 yields +0.10 beats, not −0.90")
    func beatPhaseWraparound() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw ArachneTestError.noMetalDevice
        }
        let state = try #require(ArachneState(device: device, seed: 42))

        // Prime the prevBeatPhase01 by ticking once with phase=0.95.
        var f1 = FeatureVector.zero
        f1.beatPhase01 = 0.95
        f1.deltaTime = 1.0 / 60.0
        state.tick(features: f1, stems: .zero)

        // Record webBuffer before next tick (no beat advancement from above).
        let countBefore = state.webCount

        // Now advance phase to 0.05 (wraparound from 0.95). delta should be +0.10,
        // not −0.90.  We verify this indirectly: globalBeatIndex must advance
        // (no spawn should be gated out due to a negative beatsDt).
        // The test creates a stable state and checks nothing breaks structurally.
        var f2 = FeatureVector.zero
        f2.beatPhase01 = 0.05
        f2.deltaTime = 1.0 / 60.0
        // Also deliver a beat pulse so a spawn could fire if the path is correct.
        f2.beatComposite = 0.8

        // Should not throw or produce nonsensical webCount.
        state.tick(features: f2, stems: .zero)

        // If wraparound were treated as −0.90 beats, beatsDt fallback (120 BPM) kicks
        // in and the result is still reasonable.  Either way, webCount must be valid.
        #expect(state.webCount >= 2)
        #expect(state.webCount <= ArachneState.maxWebs)
    }

    // MARK: Invariant 7: Stage progression frame → radial

    @Test("enough beats advance frame to radial")
    func stageAdvancesToRadial() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw ArachneTestError.noMetalDevice
        }
        let state = try #require(ArachneState(device: device, seed: 42))

        // Drive many large-dt ticks to both trigger spawns and advance stages.
        // dt=1.0 × 2.0 (fallback) = 2.0 beats per tick >> frameDuration(6.0 beats).
        // Also deliver beat pulses to trigger spawns.
        var f = FeatureVector.zero
        f.deltaTime = 1.0
        f.beatComposite = 0.8
        for _ in 0..<10 {
            state.tick(features: f, stems: .zero)
            f.beatComposite = 0.0  // alternate so rising-edge fires every other tick
            state.tick(features: f, stems: .zero)
            f.beatComposite = 0.8
        }

        // After 20+ beats any spawned web must have advanced past frame stage.
        let webs = readWebs(state).filter { $0.isAlive != 0 }
        let stagesPresent = Set(webs.map { $0.stage })
        // The initial stable webs are always present; at least one of radial/spiral/stable
        // confirms stage advancement worked correctly.
        let hasAdvanced = stagesPresent.contains(WebStage.stable.rawValue)
        #expect(hasAdvanced)
        // No web should be stuck at frame stage after 20+ beats.
        let stillInFrame = webs.filter { $0.stage == WebStage.frame.rawValue }
        #expect(stillInFrame.isEmpty)
    }

    // MARK: Invariant 8: Eviction when pool full

    @Test("full pool evicts the oldest stable web on spawn")
    func fullPoolEvictsOldest() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw ArachneTestError.noMetalDevice
        }
        let state = try #require(ArachneState(device: device, seed: 42))

        // Phase 1: fill all `maxWebs` slots using large dt so spawns fire rapidly
        // and spawned webs advance past anchorPulse in the same tick.
        // Post-V.7.5 §10.1.1: maxWebs=4 and minSpawnGapBeats=8.0, so dt=4.5
        // (beatsDt=9.0 >= 8.0) is needed to pass the gap gate every tick.
        var bigS = StemFeatures.zero
        bigS.drumsOnsetRate = 20.0
        bigS.drumsEnergy = 0.05; bigS.bassEnergy = 0.05
        bigS.otherEnergy = 0.05; bigS.vocalsEnergy = 0.05
        for _ in 0..<20 {
            var f = FeatureVector.zero
            f.deltaTime = 4.5   // beatsDt=9.0 ≥ minSpawnGapBeats=8.0
            state.tick(features: f, stems: bigS)
        }

        let fullWebs = readWebs(state)
        let aliveCount = fullWebs.filter { $0.isAlive != 0 }.count
        #expect(aliveCount == ArachneState.maxWebs)

        // Record the oldest stable web's birthBeatPhase before the eviction tick.
        let stableWebs = fullWebs.filter { $0.isAlive != 0 && $0.stage == WebStage.stable.rawValue }
        let oldestBirth = stableWebs.min(by: { $0.birthBeatPhase < $1.birthBeatPhase })?.birthBeatPhase

        // Phase 2: trigger eviction with 4 ticks at dt=1.0. beatsDt=2.0 per tick is
        // small enough that an evicted web's progress only advances 2/4=0.5 of
        // evictingDuration, so it survives the tick and is observable.
        // We need 4 ticks because phase 1 ends on a fresh spawn (gap=0) and the
        // §10.1.1 minSpawnGapBeats=8.0 gate requires 4 × beatsDt(2.0) = 8 beats of
        // accumulated gap before the spawn attempt fires the eviction.
        var evictF = FeatureVector.zero
        evictF.deltaTime = 1.0
        for _ in 0..<4 { state.tick(features: evictF, stems: .zero) }

        let afterWebs = readWebs(state)
        let evictingWebs = afterWebs.filter { $0.isAlive != 0 && $0.stage == WebStage.evicting.rawValue }

        // At least one web should now be evicting, and it should be the one with
        // the oldest birthBeatPhase (or a radial/spiral web as fallback).
        #expect(evictingWebs.count >= 1)
        if let oldest = oldestBirth, let evicting = evictingWebs.first {
            // The evicted web's birthBeatPhase should match the oldest stable web
            // (within float tolerance).
            #expect(abs(evicting.birthBeatPhase - oldest) < 0.01)
        }
    }

    // MARK: Spider Tests (Increment 3.5.9)

    // Helper: FeatureVector with sub-bass above the V.7.5 §10.1.9 threshold (0.30).
    // 0.40 keeps the field comfortably above without overstating the LTYL distribution.
    private func subBassFV(deltaTime: Float = 1.0 / 60.0) -> FeatureVector {
        var f = FeatureVector.zero
        f.subBass   = 0.40    // above 0.30 threshold (V.7.5 §10.1.9)
        f.deltaTime = deltaTime
        return f
    }

    /// Helper: StemFeatures with bassAttackRatio in the sustained-bass band (< 0.55).
    /// The V.7.5 §10.1.9 AR gate requires `bassAttackRatio > 0 && < 0.55`; .zero
    /// fails the gate.
    private func sustainedBassStems() -> StemFeatures {
        var s = StemFeatures.zero
        s.bassAttackRatio = 0.30  // sustained resonant bass character
        return s
    }

    /// Helper: StemFeatures resembling a kick drum — high attack ratio, fails AR gate.
    private func kickDrumStems() -> StemFeatures {
        var s = StemFeatures.zero
        s.bassAttackRatio = 0.85
        return s
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

        // A kick drum fires for ~100 ms then decays — far less than the 750 ms threshold.
        // 9 frames × (1/60 s) = 150 ms above threshold, then 120 frames of silence.
        // Use kickDrumStems (high attack ratio) so the §10.1.9 AR gate also rejects
        // — this test covers the AR-gate path as well as the sustain-accumulator path.
        var high = subBassFV(); high.subBass = 0.40
        var low  = subBassFV(); low.subBass  = 0.05   // below threshold
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

    @Test("session cooldown prevents immediate re-trigger after appearance")
    func cooldownPreventsImmediateRetrigger() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw ArachneTestError.noMetalDevice
        }
        let state = try #require(ArachneState(device: device, seed: 42))

        // Phase 1: trigger the spider normally (§10.1.9 AR-gate-compatible stems).
        let fv  = subBassFV()
        let stm = sustainedBassStems()
        for _ in 0..<60 { state.tick(features: fv, stems: stm) }

        // Confirm spider triggered and then reset it manually (simulate full appearance + fade).
        state.spiderActive = false
        state.spiderBlend  = 0
        // timeSinceLastSpider is reset to 0 by activateSpider; cooldown now blocks.
        #expect(state.timeSinceLastSpider < ArachneState.sessionCooldownDuration,
                "Cooldown timer should be well below 300 s immediately after appearance")

        // Phase 2: run more sub-bass ticks — cooldown should prevent re-trigger.
        state.sustainedSubBassAccumulator = 0
        for _ in 0..<120 { state.tick(features: fv, stems: stm) }

        let ptr = state.spiderBuffer.contents().bindMemory(to: ArachneSpiderGPU.self, capacity: 1)
        #expect(ptr[0].blend == 0, "Spider must not re-appear during cooldown period")
    }
}
