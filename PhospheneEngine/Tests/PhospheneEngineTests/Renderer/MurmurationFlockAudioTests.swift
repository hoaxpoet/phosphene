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
    beat: Float = 0
) -> FeatureVector {
    var f = FeatureVector(time: time, deltaTime: 1.0 / 60.0)
    f.arousal = arousal
    f.bassAttRel = bassAttRel
    f.midAttRel = midAttRel
    f.bassDev = bassDev
    f.beatBass = beat
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

/// A decaying beat pulse every 0.5 s (a realistic beat envelope so the wave
/// front sweeps across the mass). Stateless: pulse = 0.82^(frame mod 30).
private let kBeats: @Sendable (Int, Float) -> (FeatureVector, StemFeatures) = { frame, t in
    let pulse = powf(0.82, Float(frame % 30))
    return (features(time: t, arousal: 0.8, beat: pulse), stems(drumsDev: 1.0, drumsBeat: pulse))
}

private let kBass: @Sendable (Int, Float) -> (FeatureVector, StemFeatures) = { _, t in
    (features(time: t, bassAttRel: 1.0), stems(bassRel: 1.0))
}

// Strong mid (realistic peak — drivers are tanh-saturated, so this clamps to a
// gentle flutter; driving at peak gives the routing test a clear signal).
private let kMid: @Sendable (Int, Float) -> (FeatureVector, StemFeatures) = { _, t in
    (features(time: t, midAttRel: 2.5), stems(otherRel: 2.5))
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
    let bank: [Float]
    let neighbors: [Float]
    let waveDark: [Float]   // pad0 — L2 instantaneous wave-darkening channel

    static func read(_ geo: MurmurationFlockGeometry) -> Birds {
        let n = geo.configuration.particleCount
        let ptr = geo.birdBuffer.contents().bindMemory(to: MurmurationBird.self, capacity: n)
        var pos = [SIMD3<Float>](); pos.reserveCapacity(n)
        var vel = [SIMD3<Float>](); vel.reserveCapacity(n)
        var bank = [Float](); bank.reserveCapacity(n)
        var nb = [Float](); nb.reserveCapacity(n)
        var wd = [Float](); wd.reserveCapacity(n)
        for i in 0..<n {
            let b = ptr[i]
            pos.append(SIMD3(b.positionX, b.positionY, b.positionZ))
            vel.append(SIMD3(b.velocityX, b.velocityY, b.velocityZ))
            bank.append(b.bank)
            nb.append(b.neighborCount)
            wd.append(b._pad0)
        }
        return Birds(pos: pos, vel: vel, bank: bank, neighbors: nb, waveDark: wd)
    }

    var meanWaveDark: Float { waveDark.reduce(0, +) / Float(waveDark.count) }

    /// Std of the wave-darkening field. For a sparse localized band (most birds
    /// 0, a few high) std exceeds the mean → proof the response is a band, not a
    /// global uniform shift.
    var waveDarkStd: Float {
        let m = meanWaveDark
        let v = waveDark.reduce(Float(0)) { $0 + ($1 - m) * ($1 - m) } / Float(waveDark.count)
        return v.squareRoot()
    }

    var centroid: SIMD3<Float> {
        var c = SIMD3<Float>(0, 0, 0)
        for p in pos { c += p }
        return c / Float(pos.count)
    }

    var meanBank: Float { bank.reduce(0, +) / Float(bank.count) }

    var rmsRadius: Float {
        let c = centroid
        let s = pos.reduce(Float(0)) { $0 + ($1 - c).mag * ($1 - c).mag }
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

    var bankStd: Float {
        let m = meanBank
        let v = bank.reduce(Float(0)) { $0 + ($1 - m) * ($1 - m) } / Float(bank.count)
        return v.squareRoot()
    }

    /// Anisotropy = sqrt(λ_max / λ_min) of the position covariance. ≈ 1 for a
    /// spherical mass; rises as the flock elongates into a comma/ribbon.
    var anisotropy: Float {
        let c = centroid
        var cov = [[Double]](repeating: [0, 0, 0], count: 3)
        for p in pos {
            let d = SIMD3<Double>(Double(p.x - c.x), Double(p.y - c.y), Double(p.z - c.z))
            cov[0][0] += d.x * d.x; cov[0][1] += d.x * d.y; cov[0][2] += d.x * d.z
            cov[1][1] += d.y * d.y; cov[1][2] += d.y * d.z; cov[2][2] += d.z * d.z
        }
        let n = Double(pos.count)
        for i in 0..<3 { for j in i..<3 { cov[i][j] /= n; if i != j { cov[j][i] = cov[i][j] } } }
        let (a, _, c3) = Birds.eigenvalues3x3(cov)
        let lmax = max(a, c3), lmin = max(min(a, c3), 1e-9)
        return Float((lmax / lmin).squareRoot())
    }

    /// Edge-vs-core gap in the banking (direction-change) field. Flutter is a
    /// high-frequency random force; the min/max speed clamp masks it in raw
    /// speed, but it shows clearly as extra direction agitation. `edge − core`
    /// banking: rises when the feathered edge shimmers more than the solid core.
    var edgeCoreBankGap: Float {
        let sorted = neighbors.sorted()
        let loCut = sorted[Int(0.25 * Float(sorted.count))]
        let hiCut = sorted[Int(0.75 * Float(sorted.count))]
        var edgeSum: Float = 0, edgeN = 0
        var coreSum: Float = 0, coreN = 0
        for i in 0..<pos.count {
            if neighbors[i] <= loCut { edgeSum += bank[i]; edgeN += 1 }
            else if neighbors[i] >= hiCut { coreSum += bank[i]; coreN += 1 }
        }
        return edgeSum / Float(max(edgeN, 1)) - coreSum / Float(max(coreN, 1))
    }

    /// Sorted eigenvalues of a 3×3 symmetric matrix (Smith 1961, analytic).
    static func eigenvalues3x3(_ m: [[Double]]) -> (Double, Double, Double) {
        let p1 = m[0][1] * m[0][1] + m[0][2] * m[0][2] + m[1][2] * m[1][2]
        if p1 < 1e-18 {
            let e = [m[0][0], m[1][1], m[2][2]].sorted()
            return (e[0], e[1], e[2])
        }
        let q = (m[0][0] + m[1][1] + m[2][2]) / 3
        let p2 = (m[0][0] - q) * (m[0][0] - q) + (m[1][1] - q) * (m[1][1] - q)
               + (m[2][2] - q) * (m[2][2] - q) + 2 * p1
        let p = (p2 / 6).squareRoot()
        var b = m
        for i in 0..<3 { for j in 0..<3 { b[i][j] = (m[i][j] - (i == j ? q : 0)) / p } }
        let detB =
            b[0][0] * (b[1][1] * b[2][2] - b[1][2] * b[2][1])
          - b[0][1] * (b[1][0] * b[2][2] - b[1][2] * b[2][0])
          + b[0][2] * (b[1][0] * b[2][1] - b[1][1] * b[2][0])
        let r = max(-1.0, min(1.0, detB / 2))
        let phi = acos(r) / 3
        let e1 = q + 2 * p * cos(phi)
        let e3 = q + 2 * p * cos(phi + 2 * Double.pi / 3)
        let e2 = 3 * q - e1 - e3
        let s = [e1, e2, e3].sorted()
        return (s[0], s[1], s[2])
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
    drive: Int = 420,
    window: Int = 24,
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

@Suite("Murmuration audio coupling (MM.3)")
struct MurmurationFlockAudioTests {

    /// The Swift `FlockParams` mirror must stay byte-identical to the MSL struct
    /// (it is uploaded via `setBytes` each frame). 144 bytes after the MM.3
    /// audio fields. A mismatch silently corrupts every boids dispatch.
    @Test("FlockParams stride matches the 144-byte MSL mirror")
    func test_flockParamsLayout() {
        #expect(MemoryLayout<FlockParams>.stride == 144)
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
            #expect(a.turnGain == 0)
            #expect(a.midEdgeGain == 0)
            #expect(a.breath == 0)
            #expect(a.driftOffset.mag == 0)
        }
    }

    /// L1 — sustained bass elongates the mass (comma/ribbon) AND drifts it.
    @Test("Bass route: elongation + macro drift")
    func test_bassElongatesAndDrifts() throws {
        let (base, driven) = try sequential(audio: kBass)
        let baseAniso = base.mean { $0.anisotropy }
        let drivenAniso = driven.mean { $0.anisotropy }
        let drift = (driven.meanCentroid - base.meanCentroid).mag
        #expect(drift > 0.1, "bass should drift the flock; drift=\(drift)")
        #expect(drivenAniso > baseAniso * 1.15,
                "bass should elongate the mass: silence=\(baseAniso) bassed=\(drivenAniso)")
    }

    /// L2 — drum beats fire an orientation/darkening wave that PROPAGATES as a
    /// localized band. Silence has none; under beats the wave-darkening channel
    /// lights up, and its per-frame std exceeds its mean — the signature of a
    /// sparse travelling band, not a uniform global shift. That it does NOT
    /// relocate the flock (a roll, not a shove) is proven by the
    /// continuous:beat ratio test (the curl force nets to ≈0 translation).
    @Test("Drum route: propagating orientation wave (localized band)")
    func test_drumsBankingWave() throws {
        let (base, driven) = try sequential(audio: kBeats)
        let baseWave = base.mean { $0.meanWaveDark }
        let drivenWave = driven.mean { $0.meanWaveDark }
        let drivenStd = driven.mean { $0.waveDarkStd }
        #expect(baseWave < 1e-4, "silence must have no orientation wave: \(baseWave)")
        #expect(drivenWave > 0.01, "drums must fire the orientation wave: \(drivenWave)")
        // Non-uniform band: a uniform global shift would have std ≈ 0. A
        // localized band gives std a large fraction of the mean (~0.5 here).
        #expect(drivenStd > 0.3 * drivenWave,
                "the wave must be a localized band, not a uniform shift: std=\(drivenStd) mean=\(drivenWave)")
    }

    /// L4 — mid energy flutters the feathered edge: edge birds (few neighbours)
    /// get extra direction agitation (banking), the solid core stays steady. The
    /// edge-vs-core banking gap widens under mid (the flutter is edge-weighted
    /// ≈5×). Speed is the wrong measure — the min/max clamp masks the flutter;
    /// banking (direction change) is what edge shimmer actually is.
    ///
    /// Tests the WIRING (mid → edge agitation) at an amplified `midEdgeAmp` so
    /// the signal clears the boids chaos floor. The PRODUCTION amplitude is
    /// deliberately gentle (it must not scatter the flock — that was the M7
    /// failure); its safety is proven by `test_loudAudioStaysCohesive`.
    @Test("Mid route: edge birds flutter more than core")
    func test_midEdgeFlutter() throws {
        let amplified = MurmurationFlockConfiguration(particleCount: 6_000, midEdgeAmp: 1.5)
        let (base, driven) = try sequential(config: amplified, audio: kMid)
        let baseGap = base.mean { $0.edgeCoreBankGap }
        let drivenGap = driven.mean { $0.edgeCoreBankGap }
        #expect(drivenGap > baseGap,
                "mid must widen the edge-vs-core banking gap: silence=\(baseGap) mid=\(drivenGap)")
    }

    /// L5 — vocals compress the mass (the dark pulse): cohesion spacing tightens,
    /// so the rms radius shrinks vs the silence baseline.
    @Test("Vocals route: density compression (mass contracts)")
    func test_vocalsBreathing() throws {
        let (base, driven) = try sequential(audio: kVocals)
        let baseR = base.mean { $0.rmsRadius }
        let drivenR = driven.mean { $0.rmsRadius }
        #expect(drivenR < baseR,
                "vocals should contract the mass: silenceR=\(baseR) vocalsR=\(drivenR)")
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
        var maxR: Float = 0
        var maxCentroid: Float = 0
        var bad = false
        var pulse: Float = 0
        for frame in 0..<900 {
            if frame % 24 == 0 { pulse = 1.0 }
            // Real-music peak magnitudes (from the 2026-06-03 Billie Jean session).
            let f = features(time: t, arousal: 0.85, bassAttRel: 2.7, beat: pulse)
            let s = stems(bassRel: 3.4, drumsDev: 3.2, drumsBeat: pulse, otherRel: 1.5, vocalsDev: 1.7)
            try step(geo, features: f, stems: s, queue: q)
            pulse *= 0.82
            if frame % 60 == 0 && frame > 180 {     // sample after the substrate ramps
                let b = Birds.read(geo)
                minCore = min(minCore, b.coreFraction)
                maxR = max(maxR, b.maxRadius)
                maxCentroid = max(maxCentroid, b.centroid.mag)
                bad = bad || b.anyNonFinite
            }
            t += 1.0 / 60.0
        }
        #expect(!bad, "positions must stay finite under loud audio")
        #expect(minCore > 0.16, "loud audio must NOT fragment the flock: minCoreFrac=\(minCore)")
        #expect(maxR < cfg.worldHalfSpan * 1.6, "flock must not fly apart: maxR=\(maxR)")
        #expect(maxCentroid < 1.2, "flock must stay framed under bounded drift: maxCentroid=\(maxCentroid)")
    }

    /// Audio Data Hierarchy — the continuous substrate (bass drift) must drive
    /// ≥ 2× the whole-mass net displacement of the per-beat accent. Both are
    /// measured as the net centroid shift from the baseline window to the driven
    /// window, with the silence run subtracted so the procedural roost drift
    /// (present in every run) cancels. The beat wave is a curl → near-zero net
    /// translation, so this is a wide margin by construction.
    @Test("Continuous : beat motion ratio ≥ 2×")
    func test_continuousDominatesBeat() throws {
        func netShift(_ audio: (Int, Float) -> (FeatureVector, StemFeatures)) throws -> Float {
            let (base, driven) = try sequential(audio: audio)
            return (driven.meanCentroid - base.meanCentroid).mag
        }
        let silence = try netShift(kSilence)
        let bass = try netShift(kBass)
        let beats = try netShift(kBeats)
        let continuousMotion = max(0, bass - silence)
        let beatMotion = max(0, beats - silence)
        let detail = "silence=\(silence) bass=\(bass) beats=\(beats) → continuous=\(continuousMotion) beat=\(beatMotion)"
        #expect(continuousMotion >= 2 * beatMotion,
                "continuous (bass) motion must be ≥ 2× beat motion above the silence baseline: \(detail)")
    }
}
