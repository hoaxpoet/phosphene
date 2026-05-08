// DriftMotesTests — Verify Drift Motes' force-field motion is non-flocking.
//
// The non-flock property is the preset's identity (DM.1, D-097). A real
// flocking algorithm pulls particles toward neighbours; over a few hundred
// frames the global spread (positions relative to the cloud centroid)
// shrinks dramatically as particles cluster.
//
// Test strategy: dispatch 200 frames of `motes_update` against a silence
// fixture (zero `FeatureVector`, zero `StemFeatures`). Then measure two
// things at frame 50 and frame 200:
//
//   1. Pairwise distances between 50 fixed random particle pairs
//      (median, mean, 25th percentile). The mean is translation-invariant
//      and shouldn't change much in either direction.
//   2. Centroid-relative spread — RMS distance of every particle from the
//      cloud centroid. This is the load-bearing flock-discriminator.
//      Wind translates the cloud but doesn't change its spread; flocking
//      shrinks the spread substantially.
//
// Tolerances (D-098): pairwise distances are loose (≥ 80% of frame-50)
// because the asymmetric box (±8, ±8, ±4) and the top-slab respawn
// distribution produce a real ~10–15% drift between the uniform-cube init
// at frame 0 and the steady-state emission distribution by frame 200.
// Centroid spread is tighter (≥ 85%) because translation-invariance
// removes the wind component. A flocking implementation would drop both
// metrics by 50%+ over 150 frames, so these thresholds still catch real
// cohesion. Manual sanity-check: a cohesion-force kernel drops the spread
// ratio below 0.05 within 50 frames. See D-098 for the decision context;
// ratchet thresholds tighter (toward the prompt's original 0.95) if a
// future kernel revision becomes more rigorously translation-invariant.
//
// Determinism: the geometry seeds particles from particle index, the
// kernel reads no audio, and the `delta_time` is fixed. The same test
// process produces the same sample distribution every run.

import Testing
import Metal
@testable import Renderer
@testable import Shared

// MARK: - Helpers

private enum DriftMotesTestError: Error { case metalSetupFailed }

@discardableResult
private func dispatchOneFrame(
    geometry: DriftMotesGeometry,
    features: FeatureVector,
    queue: MTLCommandQueue
) throws -> MTLCommandBuffer {
    guard let cmdBuf = queue.makeCommandBuffer() else {
        throw DriftMotesTestError.metalSetupFailed
    }
    geometry.update(features: features, stemFeatures: .zero, commandBuffer: cmdBuf)
    cmdBuf.commit()
    cmdBuf.waitUntilCompleted()
    return cmdBuf
}

private struct PairwiseStats {
    let median: Float
    let mean: Float
    let p25: Float
}

private struct CentroidSpread {
    let rms: Float
}

private func measureCentroidSpread(buffer: MTLBuffer, count: Int) -> CentroidSpread {
    let ptr = buffer.contents().bindMemory(to: Particle.self, capacity: count)
    var cx: Float = 0, cy: Float = 0, cz: Float = 0
    for i in 0..<count {
        cx += ptr[i].positionX
        cy += ptr[i].positionY
        cz += ptr[i].positionZ
    }
    let n = Float(count)
    cx /= n; cy /= n; cz /= n
    var sumSq: Float = 0
    for i in 0..<count {
        let dx = ptr[i].positionX - cx
        let dy = ptr[i].positionY - cy
        let dz = ptr[i].positionZ - cz
        sumSq += dx * dx + dy * dy + dz * dz
    }
    return CentroidSpread(rms: (sumSq / n).squareRoot())
}

private func sampleDistances(
    buffer: MTLBuffer,
    count: Int,
    pairs: [(Int, Int)]
) -> PairwiseStats {
    let ptr = buffer.contents().bindMemory(to: Particle.self, capacity: count)
    var distances: [Float] = []
    distances.reserveCapacity(pairs.count)
    for (a, b) in pairs {
        let pa = ptr[a]
        let pb = ptr[b]
        let dx = pa.positionX - pb.positionX
        let dy = pa.positionY - pb.positionY
        let dz = pa.positionZ - pb.positionZ
        distances.append((dx * dx + dy * dy + dz * dz).squareRoot())
    }
    distances.sort()
    let n = distances.count
    let median = n % 2 == 0
        ? (distances[n / 2 - 1] + distances[n / 2]) * 0.5
        : distances[n / 2]
    let mean = distances.reduce(0, +) / Float(n)
    // 25th percentile: lower quartile.
    let p25Index = max(0, n / 4 - 1)
    let p25 = distances[p25Index]
    return PairwiseStats(median: median, mean: mean, p25: p25)
}

private func makePairs(count: Int, particleCount: Int) -> [(Int, Int)] {
    var rng = LCG(seed: 0xDEADBEEF)
    var seen: Set<UInt64> = []
    var pairs: [(Int, Int)] = []
    while pairs.count < count {
        let a = Int(rng.next() % UInt64(particleCount))
        let b = Int(rng.next() % UInt64(particleCount))
        if a == b { continue }
        let key = UInt64(min(a, b)) << 32 | UInt64(max(a, b))
        if seen.insert(key).inserted {
            pairs.append((a, b))
        }
    }
    return pairs
}

private struct LCG {
    var state: UInt64
    init(seed: UInt64) { self.state = seed }
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}

// MARK: - Tests

@Test func test_driftMotes_nonFlock_pairwiseDistancesDoNotContract() throws {
    let ctx = try MetalContext()
    let lib = try ShaderLibrary(context: ctx)
    let geometry = try DriftMotesGeometry(
        device: ctx.device,
        library: lib.library,
        particleCount: 800,
        pixelFormat: nil
    )

    // Silence fixture: zero audio. Drift Motes is audio-independent in DM.1
    // beyond the warmup-blend hook (which the kernel touches but does not
    // consume), so this is the canonical "ambient" run.
    let fixedDt: Float = 1.0 / 60.0
    var features = FeatureVector.zero
    features.deltaTime = fixedDt

    // Compare two STEADY-STATE samples to catch flocking. Pre-DM.3.1 this
    // test compared frame 50 (early) to frame 200 (still early) — both
    // partway through the init-to-steady-state transition. With the
    // DM.3.1 spawn-Y geometry fix, steady-state spawn is concentrated
    // in a tight upper-right band (world ±3.64+pad, not ±8 uniform), so
    // 50 vs 200 produces a transient spread ratio reflecting the init
    // clearing out — not flocking. After DM.3.1, sample two frames
    // both in the steady state (mean lifetime 7 s ≈ 420 frames; init
    // has fully cycled out by frame 600). Flocking would still
    // contract the ratio toward < 0.5 between any two steady-state
    // samples; non-flocking force-field motion holds it near 1.0.
    let warmupFrames = 600         // 10 s — past mean-lifetime turn-over
    let secondSampleAt = 1500       // 25 s — well into steady state

    for frame in 0..<warmupFrames {
        features.time = Float(frame) * fixedDt
        try dispatchOneFrame(geometry: geometry, features: features, queue: ctx.commandQueue)
    }

    let pairs = makePairs(count: 50, particleCount: 800)
    let frameA = sampleDistances(buffer: geometry.particleBuffer, count: 800, pairs: pairs)
    let spreadA = measureCentroidSpread(buffer: geometry.particleBuffer, count: 800)

    for frame in warmupFrames..<secondSampleAt {
        features.time = Float(frame) * fixedDt
        try dispatchOneFrame(geometry: geometry, features: features, queue: ctx.commandQueue)
    }
    let frameB = sampleDistances(buffer: geometry.particleBuffer, count: 800, pairs: pairs)
    let spreadB = measureCentroidSpread(buffer: geometry.particleBuffer, count: 800)

    let medianRatio = frameB.median / frameA.median
    let meanRatio   = frameB.mean   / frameA.mean
    let p25Ratio    = frameB.p25    / frameA.p25
    let spreadRatio = spreadB.rms   / spreadA.rms

    let diagnostic = """
        DriftMotesNonFlockTest steady-state distribution diagnostics:
          frame \(warmupFrames) pairwise:   median=\(frameA.median),  mean=\(frameA.mean),  p25=\(frameA.p25)
          frame \(secondSampleAt) pairwise:  median=\(frameB.median), mean=\(frameB.mean), p25=\(frameB.p25)
          frame \(warmupFrames) centroid spread RMS: \(spreadA.rms)
          frame \(secondSampleAt) centroid spread RMS: \(spreadB.rms)
          pairwise ratios:  median=\(medianRatio), mean=\(meanRatio), p25=\(p25Ratio)
          spread ratio:     \(spreadRatio)
        """

    // The flock-discriminator: centroid spread is translation-invariant,
    // so the wind-driven cloud drift cancels out. Real flocking would
    // drop this ratio to < 0.5 between any two steady-state samples;
    // non-flocking dynamics hold it near 1.0. 0.85 threshold catches
    // flocking with margin.
    #expect(spreadRatio >= 0.85,
            "Centroid spread RMS contracted — flocking detected. \(diagnostic)")

    // Pairwise distance check is intentionally looser. Even at steady
    // state, particle ages drift slightly (some particles in the
    // spawn-band are fresh, others are aged), producing ~5–10%
    // pairwise variation. Cohesion would shrink all three by ≥ 50%;
    // 80% threshold catches that without false-firing on natural
    // steady-state variance.
    #expect(medianRatio >= 0.80,
            "Median pairwise distance contracted — flocking detected. \(diagnostic)")
    #expect(meanRatio   >= 0.80,
            "Mean pairwise distance contracted — flocking detected. \(diagnostic)")
    #expect(p25Ratio    >= 0.80,
            "P25 pairwise distance contracted — flocking detected. \(diagnostic)")
}
