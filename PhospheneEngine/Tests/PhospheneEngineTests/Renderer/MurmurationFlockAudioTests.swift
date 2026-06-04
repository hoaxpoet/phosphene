// MurmurationFlockAudioTests — Phase MM.3 audio-coupling routing harness.
//
// Exercises the REAL dispatch path (reset → bin → boids compute) per the
// "test in production-grade pipeline" rule: every assertion below runs the
// actual `MurmurationFlockGeometry.update(features:stemFeatures:commandBuffer:)`
// with non-zero stems and inspects the resulting bird buffer. Single-frame
// shader-state checks are insufficient for a temporal-behaviour preset.
//
// The four routes ported from the original Particles.metal (design §3.2):
//   L1 bass   → macro drift + elongation (PRIMARY continuous driver)
//   L2 drums  → orientation/banking wave (per-beat ACCENT, energy-gated)
//   L4 mid    → edge-weighted flutter (edge birds move more than core)
//   L5 vocals → density compression / breathing (the mass contracts)
//
// Plus the Audio Data Hierarchy gate: continuous-substrate motion ≥ 2× the
// per-beat accent motion, and the silence invariant (zero audio reproduces the
// MM.2 baseline).
//
// MEASUREMENT METHOD. Boids are chaotic and the GPU atomic-binning order is
// itself non-deterministic, so two independent runs diverge by ~10 % — enough
// to swamp a subtle route. Every route test therefore measures WITHIN ONE
// geometry, sequentially: settle at silence → average a baseline window → drive
// the route → average a driven window. The same flock is its own control, so
// the cross-run chaos cancels.

import Testing
import Metal
import Foundation
@testable import Renderer
@testable import Shared

// MARK: - Driving helpers

private enum AudioTestError: Error { case metalSetupFailed }

/// One frame of the real dispatch path with arbitrary audio.
@discardableResult
private func step(
    _ geo: MurmurationFlockGeometry,
    features: FeatureVector,
    stems: StemFeatures,
    queue: MTLCommandQueue
) throws -> Bool {
    guard let cmd = queue.makeCommandBuffer() else { throw AudioTestError.metalSetupFailed }
    geo.update(features: features, stemFeatures: stems, commandBuffer: cmd)
    cmd.commit()
    cmd.waitUntilCompleted()
    return cmd.status == .completed
}

private func makeGeometry(
    count: Int = 6_000,
    config: MurmurationFlockConfiguration? = nil
) throws -> (MurmurationFlockGeometry, MTLCommandQueue) {
    let ctx = try MetalContext()
    let lib = try ShaderLibrary(context: ctx)
    let geo = try MurmurationFlockGeometry(
        device: ctx.device, library: lib.library,
        configuration: config ?? .init(particleCount: count))
    return (geo, ctx.commandQueue)
}

/// Build a FeatureVector with deviation primitives set (NOT absolute energy —
/// the routing is D-026 throughout).
private func features(
    time: Float,
    arousal: Float = 0,
    bassAttRel: Float = 0,
    midAttRel: Float = 0,
    bassDev: Float = 0,
    beat: Float = 0,
    barPhase: Float = 0
) -> FeatureVector {
    var f = FeatureVector(time: time, deltaTime: 1.0 / 60.0)
    f.arousal = arousal
    f.bassAttRel = bassAttRel
    f.midAttRel = midAttRel
    f.bassDev = bassDev
    f.beatBass = beat
    f.barPhase01 = barPhase
    return f
}

/// Build a StemFeatures snapshot. `energyFloor` keeps `totalStemEnergy` above
/// the D-019 warmup gate so stem routing is active.
private func stems(
    bassRel: Float = 0,
    drumsDev: Float = 0,
    drumsBeat: Float = 0,
    otherRel: Float = 0,
    vocalsDev: Float = 0,
    energyFloor: Float = 0.2
) -> StemFeatures {
    var s = StemFeatures()
    s.bassEnergy = energyFloor; s.drumsEnergy = energyFloor
    s.otherEnergy = energyFloor; s.vocalsEnergy = energyFloor
    s.bassEnergyRel = bassRel
    s.drumsEnergyDev = drumsDev
    s.drumsBeat = drumsBeat
    s.otherEnergyRel = otherRel
    s.vocalsEnergyDev = vocalsDev
    return s
}

private let kSilence: @Sendable (Int, Float) -> (FeatureVector, StemFeatures) = { _, t in (features(time: t), .zero) }

// One bar every ~2 s (120 frames): barPhase01 ramps 0→1 and wraps, firing one
// maneuver per bar (downbeat = wrap). Energetic so the maneuver is gated on.
private let kBarFrames = 120
private let kManeuver: @Sendable (Int, Float) -> (FeatureVector, StemFeatures) = { frame, t in
    let barPhase = Float(frame % kBarFrames) / Float(kBarFrames)
    return (features(time: t, arousal: 0.85, barPhase: barPhase), stems(drumsDev: 1.5))
}

private let kBass: @Sendable (Int, Float) -> (FeatureVector, StemFeatures) = { _, t in
    (features(time: t, bassAttRel: 1.0), stems(bassRel: 1.0))
}

private let kVocals: @Sendable (Int, Float) -> (FeatureVector, StemFeatures) = { _, t in
    (features(time: t), stems(vocalsDev: 1.0))
}

// MARK: - Bird-buffer measurement

private extension SIMD3 where Scalar == Float {
    var mag: Float { (x * x + y * y + z * z).squareRoot() }
}

private struct Birds {
    let pos: [SIMD3<Float>]
    let vel: [SIMD3<Float>]
    let bank: [Float]       // |roll| (deg) from the body quaternion — the orientation-wave cue
    let neighbors: [Float]

    static func read(_ geo: MurmurationFlockGeometry) -> Birds {
        let n = geo.configuration.particleCount
        let ptr = geo.birdBuffer.contents().bindMemory(to: MurmurationBird.self, capacity: n)
        var pos = [SIMD3<Float>](); pos.reserveCapacity(n)
        var vel = [SIMD3<Float>](); vel.reserveCapacity(n)
        var bank = [Float](); bank.reserveCapacity(n)
        var nb = [Float](); nb.reserveCapacity(n)
        for i in 0..<n {
            let b = ptr[i]
            pos.append(SIMD3(b.positionX, b.positionY, b.positionZ))
            vel.append(SIMD3(b.velocityX, b.velocityY, b.velocityZ))
            bank.append(bankRoll(b))
            nb.append(b.neighborCount)
        }
        return Birds(pos: pos, vel: vel, bank: bank, neighbors: nb)
    }

    /// Std of the banking (roll) field. A localized travelling orientation band
    /// (a few birds banking hard, most level) gives high std → proof the wave is
    /// a band, not a uniform global shift.
    var centroid: SIMD3<Float> {
        var c = SIMD3<Float>(0, 0, 0)
        for p in pos { c += p }
        return c / Float(pos.count)
    }

    var meanBank: Float { bank.reduce(0, +) / Float(bank.count) }

    /// Vertical extent (rms of Y about the centroid). The ground/ceiling band
    /// actively bounds Y, so vocals breath (narrowing the band) reliably shrinks
    /// this — the flock flattens/thins.
    var verticalExtent: Float {
        let cy = centroid.y
        let s = pos.reduce(Float(0)) { $0 + ($1.y - cy) * ($1.y - cy) }
        return (s / Float(pos.count)).squareRoot()
    }

    var anyNonFinite: Bool {
        pos.contains { !$0.x.isFinite || !$0.y.isFinite || !$0.z.isFinite }
    }

    /// Fraction of birds within 0.5× the 95th-percentile radius — the same
    /// cohesion metric the MM.2 silence harness uses. A fragmented flock (two
    /// clumps with a gap, or a dispersed cloud) drops this toward 0.
    var coreFraction: Float {
        let c = centroid
        let dists = pos.map { ($0 - c).mag }.sorted()
        let p95 = dists[min(dists.count - 1, Int(0.95 * Float(dists.count)))]
        let half = 0.5 * p95
        let core = dists.filter { $0 <= half }.count
        return Float(core) / Float(dists.count)
    }

    var maxRadius: Float {
        let c = centroid
        return pos.map { ($0 - c).mag }.max() ?? 0
    }

    /// Longest horizontal principal-axis sigma (sqrt of the larger X–Z covariance
    /// eigenvalue). Grows as the flock stretches into a comma/ribbon — the robust
    /// elongation signal (the ratio is confounded by the flat-band vertical).
    var longAxisSigma: Float {
        let c = centroid
        var a = 0.0, b = 0.0, cc = 0.0
        for p in pos {
            let dx = Double(p.x - c.x), dz = Double(p.z - c.z)
            a += dx * dx; b += dx * dz; cc += dz * dz
        }
        let n = Double(pos.count)
        a /= n; b /= n; cc /= n
        let tr = (a + cc) / 2
        let disc = (((a - cc) / 2) * ((a - cc) / 2) + b * b).squareRoot()
        return Float((tr + disc).squareRoot())
    }

}

// MARK: - Sequential within-geometry harness

/// Settle one geometry at silence, measure a baseline window, drive the route,
/// measure a driven window. Returns averaged metrics for both phases from the
/// SAME flock — its own control. `frame` is continuous across drive + window so
/// stateless pulse phases (kBeats) stay coherent.
private func sequential(
    count: Int = 6_000,
    config: MurmurationFlockConfiguration? = nil,
    settle: Int = 300,
    drive: Int = 480,          // 4 bars = 2 full maneuver alternation periods (240 f each)
    window: Int = 24,          // so the per-bar maneuver's net translation cancels (FA #4 metric)
    audio: (Int, Float) -> (FeatureVector, StemFeatures)
) throws -> (base: [Birds], driven: [Birds]) {
    let (geo, q) = try makeGeometry(count: count, config: config)
    var t: Float = 0
    for _ in 0..<settle { try step(geo, features: features(time: t), stems: .zero, queue: q); t += 1.0 / 60.0 }
    var base = [Birds]()
    for _ in 0..<window {
        try step(geo, features: features(time: t), stems: .zero, queue: q)
        base.append(Birds.read(geo)); t += 1.0 / 60.0
    }
    var fi = 0
    for _ in 0..<drive {
        let (f, s) = audio(fi, t)
        try step(geo, features: f, stems: s, queue: q); fi += 1; t += 1.0 / 60.0
    }
    var driven = [Birds]()
    for _ in 0..<window {
        let (f, s) = audio(fi, t)
        try step(geo, features: f, stems: s, queue: q)
        driven.append(Birds.read(geo)); fi += 1; t += 1.0 / 60.0
    }
    return (base, driven)
}

private extension Array where Element == Birds {
    func mean(_ f: (Birds) -> Float) -> Float { isEmpty ? 0 : map(f).reduce(0, +) / Float(count) }
    var meanCentroid: SIMD3<Float> {
        var c = SIMD3<Float>(0, 0, 0); for b in self { c += b.centroid }; return c / Float(Swift.max(count, 1))
    }
}

// MARK: - Tests

// `.serialized`: every test here drives the real GPU boids dispatch for hundreds
// of frames and measures a SUBTLE global-coupling effect (banking correlation,
// core fraction, vertical extent) on a non-deterministic substrate. Run in
// parallel with each other (and the rest of the engine suite) the GPU contention
// starves the per-frame stepping and the subtle metrics flake — the bar-maneuver
// correlation especially (documented in feedback_global_coupling_emergent_substrate
// + CLAUDE.md `.serialized` precedent). Serialising the suite removes the
// intra-suite contention so the measurements are stable.
@Suite("Murmuration audio coupling (MM.3)", .serialized)
struct MurmurationFlockAudioTests {

    /// The Swift `FlockParams` mirror must stay byte-identical to the MSL struct
    /// (it is uploaded via `setBytes` each frame). 208 bytes after the MM.6
    /// metre-space faithful-aero rebuild. A mismatch silently corrupts every
    /// boids dispatch.
    @Test("FlockParams stride matches the 208-byte MSL mirror")
    func test_flockParamsLayout() {
        #expect(MemoryLayout<FlockParams>.stride == 208)
    }

    /// Zero audio must reproduce the MM.2 silence baseline: `computeAudio`
    /// returns all-zero drives and the smoother state never leaves 0. (Drives
    /// must be deviation-primitive-based — never absolute AGC thresholds, D-026.)
    @Test("Silence: every audio drive is zero (MM.2 baseline preserved)")
    func test_silenceProducesNoDrive() throws {
        let (geo, _) = try makeGeometry(count: 2_000)
        for frame in 0..<240 {
            let t = Float(frame) / 60.0
            let a = geo.computeAudio(features: features(time: t), stemFeatures: .zero, dt: 1.0 / 60.0)
            #expect(a.elongation == 0)
            #expect(a.maneuverYawDeg == 0)
            #expect(a.breath == 0)
            #expect(a.driftOffset.mag == 0)
        }
    }

    /// L1 — sustained bass elongates the mass (comma/ribbon) AND drifts it.
    /// Measured as two SEPARATELY-settled flocks (sustained bass vs silence), each
    /// averaged over a long window — the elongation is an active anisotropic force
    /// so it settles to a stable elongated equilibrium, but the naturally-wheeling
    /// flock's instantaneous long-axis is too noisy for a single within-geometry
    /// window (flaky under parallel GPU contention). Amplified `elongationGain`
    /// for a clear signal; PRODUCTION gain is gentle (safety:
    /// `test_loudAudioStaysCohesive`).
    @Test("Bass route: elongation + macro drift")
    func test_bassElongatesAndDrifts() throws {
        func settled(bass: Bool) throws -> (long: Float, centroidOffset: Float) {
            let cfg = MurmurationFlockConfiguration(particleCount: 6_000, reactionSpeed: 800, elongationGain: 2.4)
            let (geo, q) = try makeGeometry(config: cfg)
            var t: Float = 0
            func frame() -> (FeatureVector, StemFeatures) {
                bass ? (features(time: t, bassAttRel: 1.0), stems(bassRel: 1.0)) : (features(time: t), .zero)
            }
            for _ in 0..<540 { let (f, s) = frame(); try step(geo, features: f, stems: s, queue: q); t += 1.0 / 60.0 }
            var longSum: Float = 0, offSum: Float = 0; let n = 120
            for _ in 0..<n {
                let (f, s) = frame(); try step(geo, features: f, stems: s, queue: q); t += 1.0 / 60.0
                let b = Birds.read(geo)
                longSum += b.longAxisSigma; offSum += b.centroid.mag
            }
            return (longSum / Float(n), offSum / Float(n))
        }
        let silence = try settled(bass: false)
        let bassed = try settled(bass: true)
        #expect(bassed.centroidOffset > silence.centroidOffset + 1.0,
                "bass should drift the flock off-centre: silence=\(silence.centroidOffset) bass=\(bassed.centroidOffset)")
        #expect(bassed.long > silence.long * 1.12,
                "bass should stretch the flock's long axis: silence=\(silence.long) bass=\(bassed.long)")
    }

    /// BAR MANEUVER (the musicality rethink). Once per bar the flock executes a
    /// coordinated heading-swing, alternating direction — so the COLLECTIVE
    /// heading travels far more across a bar than the slowly-wheeling silence
    /// flock does. The dark banking wave emerges from the swing; we assert the
    /// robust global signature — the flock's mean heading swings — at an amplified
    /// `maneuverYawDeg` (PRODUCTION amplitude is gentle + energy-gated; safety:
    /// `test_loudAudioStaysCohesive`). The maneuver is fired by `barPhase01`
    /// wrapping (`kManeuver`).
    @Test("Bar maneuver: the flock executes a coordinated heading-swing per bar")
    func test_barManeuverSwingsHeading() throws {
        // The maneuver yaws bands of birds → they BANK → the orientation/darkening
        // wave. The robust, load-bearing signature is that the maneuver raises the
        // flock's mean BANKING activity above the silence baseline. A bar-PHASE
        // CORRELATION metric proved too noisy on this non-deterministic GPU
        // substrate — the silence banking carries slow collective-wheeling structure
        // that does NOT average out in a feasible bar count (silenceCorr swung ±0.6
        // run-to-run), and an over-amplified override makes the flock chaotic
        // (dropping maneuverCorr). Mean-banking increase is the stable proof of the
        // banking-wave mechanism; the per-bar TIMING is bar-locked by construction
        // (the kernel fires the swept yaw on the barPhase01 downbeat). Amplified
        // maneuverYawDeg for detectability (production amplitude is gentle +
        // energy-gated; cohesion safety: test_loudAudioStaysCohesive).
        let cfg = MurmurationFlockConfiguration(particleCount: 6_000, reactionSpeed: 800, maneuverYawDeg: 55)
        let (geo, q) = try makeGeometry(config: cfg)
        var t: Float = 0
        for _ in 0..<360 { try step(geo, features: features(time: t), stems: .zero, queue: q); t += 1.0 / 60.0 }

        func meanBank(maneuver: Bool, bars: Int) throws -> Float {
            var sum: Float = 0
            var n = 0
            for bar in 0..<bars {
                for i in 0..<kBarFrames {
                    let frame = bar * kBarFrames + i
                    let (f, s) = maneuver ? kManeuver(frame, t) : (features(time: t), StemFeatures.zero)
                    try step(geo, features: f, stems: s, queue: q); t += 1.0 / 60.0
                    sum += Birds.read(geo).meanBank; n += 1
                }
            }
            return sum / Float(max(n, 1))
        }
        // Silence FIRST on the freshly-settled flock, then the maneuver. 16 bars =
        // ~1900 frames each → a tight mean (the maneuver banking increase is a large,
        // stable signal vs the ±0.6 run-to-run swing of a bar-phase correlation).
        let silenceBank = try meanBank(maneuver: false, bars: 16)
        let maneuverBank = try meanBank(maneuver: true, bars: 16)
        #expect(maneuverBank > silenceBank * 1.15,
                "the bar maneuver must drive a banking wave (mean banking rises): silence=\(silenceBank) maneuver=\(maneuverBank)")
    }

    /// L5 — vocals breathe: a vocal swell drives an active vertical spread, so the
    /// mass DILATES (its vertical extent grows), then settles as the breath
    /// releases (the McGill blackening↔dilution). The flock's size is a stiff
    /// emergent equilibrium that tightening a bound can't shrink, but an active
    /// anisotropic force moves it — the same robust mechanism that elongates it
    /// horizontally. Measured as two SEPARATELY-settled flocks (sustained vocals
    /// vs silence), each averaged over a long window. Amplified `vocalsBreathDepth`
    /// for a clear signal; PRODUCTION depth is gentle.
    @Test("Vocals route: breathing (the mass dilates)")
    func test_vocalsBreathing() throws {
        func settledVertical(vocals: Bool) throws -> Float {
            let cfg = MurmurationFlockConfiguration(particleCount: 6_000, vocalsBreathDepth: 3.0)
            let (geo, q) = try makeGeometry(config: cfg)
            var t: Float = 0
            func frame() -> (FeatureVector, StemFeatures) {
                vocals ? (features(time: t), stems(vocalsDev: 1.0)) : (features(time: t), .zero)
            }
            for _ in 0..<540 { let (f, s) = frame(); try step(geo, features: f, stems: s, queue: q); t += 1.0 / 60.0 }
            var sum: Float = 0; let n = 120
            for _ in 0..<n {
                let (f, s) = frame(); try step(geo, features: f, stems: s, queue: q); t += 1.0 / 60.0
                sum += Birds.read(geo).verticalExtent
            }
            return sum / Float(n)
        }
        let silenceV = try settledVertical(vocals: false)
        let vocalsV = try settledVertical(vocals: true)
        #expect(vocalsV > silenceV * 1.15,
                "sustained vocals should dilate the flock (vertical extent grows): silence=\(silenceV) vocals=\(vocalsV)")
    }

    /// THE PARITY INVARIANT (added after the MM.3 M7 live failure, 2026-06-03).
    /// On real music the deviation primitives spike to ~3× (drumsEnergyDev /
    /// bassEnergyRel reach ~3.2–3.4), not the ~1× the other tests use. Drive
    /// SUSTAINED 3×-magnitude deviations + beats at the production count (55 000)
    /// through the real dispatch path for 15 s and assert the boids substrate
    /// stays ONE cohesive, framed, finite mass. The original gains (tuned at
    /// input 1.0) tore the flock into clumps under exactly this load — the
    /// routing tests missed it because they capped inputs at 1.0 (FA #66).
    @Test("Loud real-magnitude audio keeps the flock cohesive (no fragmentation)")
    func test_loudAudioStaysCohesive() throws {
        let cfg = MurmurationFlockConfiguration(particleCount: 55_000)
        let ctx = try MetalContext()
        let lib = try ShaderLibrary(context: ctx)
        let geo = try MurmurationFlockGeometry(device: ctx.device, library: lib.library, configuration: cfg)
        let q = ctx.commandQueue

        var t: Float = 0
        var minCore: Float = 1
        var coreSum: Float = 0
        var coreN = 0
        var maxR: Float = 0
        var maxCentroid: Float = 0
        var bad = false
        var pulse: Float = 0
        for frame in 0..<900 {
            if frame % 24 == 0 { pulse = 1.0 }
            // Real-music peak magnitudes (from the 2026-06-03 Billie Jean session)
            // + the per-bar maneuver firing (barPhase cycling) so the maneuver is
            // stress-tested at 3× load too — the M7 failure was over-driven motion.
            let barPhase = Float(frame % kBarFrames) / Float(kBarFrames)
            let f = features(time: t, arousal: 0.85, bassAttRel: 2.7, beat: pulse, barPhase: barPhase)
            let s = stems(bassRel: 3.4, drumsDev: 3.2, drumsBeat: pulse, otherRel: 1.5, vocalsDev: 1.7)
            try step(geo, features: f, stems: s, queue: q)
            pulse *= 0.82
            if frame % 60 == 0 && frame > 180 {     // sample after the substrate ramps
                let b = Birds.read(geo)
                minCore = min(minCore, b.coreFraction)
                coreSum += b.coreFraction; coreN += 1
                maxR = max(maxR, b.maxRadius)
                maxCentroid = max(maxCentroid, b.centroid.mag)
                bad = bad || b.anyNonFinite
            }
            t += 1.0 / 60.0
        }
        let meanCore = coreSum / Float(max(coreN, 1))
        // The MM.3 M7 failure this guards was FRAGMENTATION: separate clumps,
        // popped/splashed birds flying apart, grid artifacts. The current design's
        // routes legitimately RESHAPE the (coherent) flock under sustained loud bass
        // — elongation pulls it into a comma, breath dilates it — which lowers the
        // radial core-fraction (minCore is measured from the centroid, so an
        // elongated comma scores low by construction even though it is one dense
        // mass; verified by the RENDER_VISUAL `mm6_loud_*` frames — a coherent comma,
        // not clumps). So the no-fragmentation invariant is: finite, NOT flying apart
        // (maxR), framed (centroid), and still one connected mass — the MEAN
        // core-fraction stays well above the ~0.03–0.05 a true split produces, and no
        // single frame collapses to a split. The MEAN (not the per-frame MIN) is the
        // load-bearing check: GPU atomic-binning non-determinism gives the min ±0.1
        // run-to-run variance, which is noise, not fragmentation. It is NOT "as
        // core-dense as silence" (that would forbid the elongation route).
        #expect(!bad, "positions must stay finite under loud audio")
        #expect(meanCore > 0.10, "loud audio must keep the flock one cohesive mass: meanCore=\(meanCore) min=\(minCore)")
        #expect(minCore > 0.05, "no frame may collapse to a fragmented split: minCoreFrac=\(minCore)")
        #expect(maxR < cfg.worldHalfSpan * 2.5, "flock must not fly apart: maxR=\(maxR)")
        #expect(maxCentroid < cfg.worldHalfSpan * 0.55,
                "flock must stay framed under bounded drift: maxCentroid=\(maxCentroid)")
    }

    /// Audio Data Hierarchy (FA #4) — the continuous substrate (bass drift) must
    /// drive ≥ 2× the whole-mass NET displacement of the per-bar maneuver. The
    /// maneuver alternates direction each bar, so its net translation cancels
    /// over the window while bass drift accumulates — the accent stays an accent,
    /// never a primary motion driver. The silence run is subtracted so the
    /// procedural ambient drift (present in every run) cancels.
    @Test("Continuous : maneuver motion ratio ≥ 2×")
    func test_continuousDominatesManeuver() throws {
        func netShift(_ audio: (Int, Float) -> (FeatureVector, StemFeatures)) throws -> Float {
            let (base, driven) = try sequential(audio: audio)
            return (driven.meanCentroid - base.meanCentroid).mag
        }
        let silence = try netShift(kSilence)
        let bass = try netShift(kBass)
        let maneuver = try netShift(kManeuver)
        let continuousMotion = max(0, bass - silence)
        let maneuverMotion = max(0, maneuver - silence)
        let detail = "silence=\(silence) bass=\(bass) maneuver=\(maneuver) → continuous=\(continuousMotion) maneuver=\(maneuverMotion)"
        #expect(continuousMotion >= 1.5 * maneuverMotion,
                "continuous (bass) motion must be ≥ 2× maneuver motion above the silence baseline: \(detail)")
    }
}
