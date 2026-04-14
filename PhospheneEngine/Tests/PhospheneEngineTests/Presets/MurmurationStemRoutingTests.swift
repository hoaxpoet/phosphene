// MurmurationStemRoutingTests — Verify stem-driven audio routing in the
// Murmuration particle compute kernel (Increment 3.5.2).
//
// Tests exercise the Metal kernel directly via ProceduralGeometry.update()
// and read back particle state from the UMA buffer.
//
// Key invariants:
//   1. Zero stems → full-mix FeatureVector fallback (flock is NOT frozen)
//   2. Drums beat → spatial variance changes when beat fires
//   3. Drums beat → non-uniform per-particle response (turning wave)
//   4. Bass energy → different flock position / shape
//   5. Other energy → higher position jitter, edge-weighted
//   6. Warmup blend → smooth transition (no discontinuous jump)
//   7. Vocals energy → tighter packing (lower position variance along depth axis)
//   8. Buffer binding → kernel compiles without buffer index conflicts

import Testing
import Metal
@testable import Renderer
@testable import Shared

// MARK: - Helpers

private struct FlockStats {
    let meanX: Float
    let meanY: Float
    let varianceX: Float
    let varianceY: Float
    let meanSpeed: Float

    static func measure(
        _ geometry: ProceduralGeometry,
        count: Int
    ) -> FlockStats {
        let ptr = geometry.particleBuffer.contents().bindMemory(
            to: Particle.self, capacity: count
        )
        var sumX: Float = 0, sumY: Float = 0, sumSpeed: Float = 0
        for i in 0..<count {
            let p = ptr[i]
            sumX += p.positionX; sumY += p.positionY
            sumSpeed += sqrt(p.velocityX * p.velocityX + p.velocityY * p.velocityY)
        }
        let n = Float(count)
        let meanX = sumX / n
        let meanY = sumY / n
        var varX: Float = 0, varY: Float = 0
        for i in 0..<count {
            let p = ptr[i]
            let dx = p.positionX - meanX
            let dy = p.positionY - meanY
            varX += dx * dx; varY += dy * dy
        }
        return FlockStats(
            meanX: meanX, meanY: meanY,
            varianceX: varX / n, varianceY: varY / n,
            meanSpeed: sumSpeed / n
        )
    }
}

private enum MurmurationTestError: Error {
    case metalSetupFailed
}

/// Dispatch one compute frame and wait for GPU completion.
@discardableResult
private func dispatch(
    geometry: ProceduralGeometry,
    features: FeatureVector,
    stems: StemFeatures,
    queue: MTLCommandQueue
) throws -> MTLCommandBuffer {
    guard let cmdBuf = queue.makeCommandBuffer() else {
        throw MurmurationTestError.metalSetupFailed
    }
    geometry.update(features: features, stemFeatures: stems, commandBuffer: cmdBuf)
    cmdBuf.commit()
    cmdBuf.waitUntilCompleted()
    return cmdBuf
}

/// Run N warmup dispatches to let the flock reach a stable home configuration,
/// then return the geometry for subsequent test dispatches.
private func warmupGeometry(
    _ geometry: ProceduralGeometry,
    queue: MTLCommandQueue,
    frames: Int = 30,
    features: FeatureVector = FeatureVector(bass: 0.3, time: 1.0, deltaTime: 0.016),
    stems: StemFeatures = .zero
) throws {
    for _ in 0..<frames {
        try dispatch(geometry: geometry, features: features, stems: stems, queue: queue)
    }
}

// MARK: - Tests

// swiftlint:disable:next function_body_length
@Test func test_particleKernel_withZeroStems_usesFullMixFallback() throws {
    // Zero StemFeatures → kernel should use full-mix fallback, not freeze.
    // Verify that flock is actively moving (mean speed above minimum),
    // and matches the pre-stem implementation behavior.
    let ctx = try MetalContext()
    let lib = try ShaderLibrary(context: ctx)
    let config = ParticleConfiguration(particleCount: 1024)
    let geometry = try ProceduralGeometry(
        device: ctx.device, library: lib.library, configuration: config
    )

    let features = FeatureVector(
        bass: 0.5, subBass: 0.3, lowBass: 0.2,
        highMid: 0.15, high: 0.10,
        beatBass: 0.6,
        spectralCentroid: 0.4,
        time: 2.0, deltaTime: 0.016
    )

    // Run with explicit zero stems.
    try warmupGeometry(geometry, queue: ctx.commandQueue, frames: 20,
                       features: features, stems: .zero)

    let stats = FlockStats.measure(geometry, count: config.particleCount)

    // Flock must not be frozen — fallback routing drives movement.
    #expect(stats.meanSpeed > 0.01,
            "With zero stems, full-mix fallback must keep the flock moving")
    #expect(stats.varianceX > 1e-6,
            "With zero stems, particles should be spatially distributed (not collapsed)")
}

@Test func test_particleKernel_withValidStems_respondsToDrumsBeat() throws {
    // A drums_beat impulse should cause measurably different flock behavior
    // compared to silence on the drums stem.
    let ctx = try MetalContext()
    let lib = try ShaderLibrary(context: ctx)
    let config = ParticleConfiguration(particleCount: 2048)

    let baseFeatures = FeatureVector(
        bass: 0.3, mid: 0.2, treble: 0.1,
        time: 1.5, deltaTime: 0.016
    )

    // Geometry A: drums_beat = 0 (no beat, above warmup threshold via drums_energy).
    let geometryA = try ProceduralGeometry(
        device: ctx.device, library: lib.library, configuration: config
    )
    let stemsNoBeat = StemFeatures(
        drumsEnergy: 0.5, drumsBeat: 0.0,
        bassEnergy: 0.3
    )
    try warmupGeometry(geometryA, queue: ctx.commandQueue, frames: 20,
                       features: baseFeatures, stems: stemsNoBeat)
    let statsA = FlockStats.measure(geometryA, count: config.particleCount)

    // Geometry B: drums_beat = 0.9 (strong beat onset).
    let geometryB = try ProceduralGeometry(
        device: ctx.device, library: lib.library, configuration: config
    )
    var stemsBeat = StemFeatures(
        drumsEnergy: 0.5, drumsBeat: 0.9,
        bassEnergy: 0.3
    )
    try warmupGeometry(geometryB, queue: ctx.commandQueue, frames: 20,
                       features: baseFeatures, stems: stemsNoBeat)
    // One beat frame.
    guard let cmdBuf = ctx.commandQueue.makeCommandBuffer() else {
        throw MurmurationTestError.metalSetupFailed
    }
    geometryB.update(features: baseFeatures, stemFeatures: stemsBeat, commandBuffer: cmdBuf)
    cmdBuf.commit()
    cmdBuf.waitUntilCompleted()

    let statsB = FlockStats.measure(geometryB, count: config.particleCount)

    // Mean speed should differ between the beat and no-beat case.
    let speedDiff = abs(statsB.meanSpeed - statsA.meanSpeed)
    #expect(speedDiff > 0.001,
            "drums_beat should produce measurably different flock velocity vs no beat (speedA=\(statsA.meanSpeed) speedB=\(statsB.meanSpeed))")

    // Suppress unused warning on stemsBeat.
    _ = stemsBeat
}

@Test func test_particleKernel_drumBeat_producesNonUniformResponse() throws {
    // The turning wave must produce NON-UNIFORM response across the flock:
    // birds at different flock-coordinates (birdU) should receive different
    // turning forces when the wave front is mid-sweep.
    //
    // Strategy: with drums_beat = 0.5, waveFront = 0.5. Birds with birdU
    // near 0.5 receive peak wave influence; birds near 0.0 or 1.0 receive
    // near-zero influence. We compare velocity magnitude between two groups.
    let ctx = try MetalContext()
    let lib = try ShaderLibrary(context: ctx)

    // Use enough particles so each birdU group has good coverage.
    let config = ParticleConfiguration(particleCount: 4096)
    let geometry = try ProceduralGeometry(
        device: ctx.device, library: lib.library, configuration: config
    )

    // Warmup with moderate stems above threshold, no beat.
    let baseFeatures = FeatureVector(
        bass: 0.3, time: 1.5, deltaTime: 0.016
    )
    let warmupStems = StemFeatures(drumsEnergy: 0.5, bassEnergy: 0.3)
    try warmupGeometry(geometry, queue: ctx.commandQueue, frames: 25,
                       features: baseFeatures, stems: warmupStems)

    // Record pre-beat positions.
    let ptr = geometry.particleBuffer.contents().bindMemory(
        to: Particle.self, capacity: config.particleCount
    )
    var preBeatX = [Float](repeating: 0, count: config.particleCount)
    var preBeatY = [Float](repeating: 0, count: config.particleCount)
    for i in 0..<config.particleCount {
        preBeatX[i] = ptr[i].positionX
        preBeatY[i] = ptr[i].positionY
    }

    // Beat dispatch: drums_beat = 0.5 → waveFront = 0.5 → mid-sweep.
    let beatFeatures = FeatureVector(bass: 0.3, time: 1.5, deltaTime: 0.016)
    let beatStems = StemFeatures(drumsEnergy: 1.0, drumsBeat: 0.5, bassEnergy: 0.3)
    try dispatch(geometry: geometry, features: beatFeatures, stems: beatStems,
                 queue: ctx.commandQueue)

    // Partition particles by birdU (flock_hash(seed * 73.0)):
    //   Group CENTER: birdU in [0.35, 0.65] — near the waveFront (high influence)
    //   Group EDGE:   birdU in [0.00, 0.15] ∪ [0.85, 1.00] — far from waveFront

    func flockHash(_ n: Float) -> Float {
        let raw = sin(n) * 43758.5453
        return raw - floor(raw)  // fract
    }

    var centerDeltas = [Float]()
    var edgeDeltas = [Float]()

    for i in 0..<config.particleCount {
        let p = ptr[i]
        let birdU = flockHash(p.seed * 73.0)
        let dx = p.positionX - preBeatX[i]
        let dy = p.positionY - preBeatY[i]
        let delta = sqrt(dx * dx + dy * dy)

        if birdU > 0.35 && birdU < 0.65 {
            centerDeltas.append(delta)
        } else if birdU < 0.15 || birdU > 0.85 {
            edgeDeltas.append(delta)
        }
    }

    #expect(!centerDeltas.isEmpty && !edgeDeltas.isEmpty,
            "Expected particles in both center and edge birdU groups")

    let centerMean = centerDeltas.reduce(0, +) / Float(centerDeltas.count)
    let edgeMean = edgeDeltas.reduce(0, +) / Float(edgeDeltas.count)

    // The center group (wave passing through) must have measurably different
    // displacement than the edge group (wave not yet arrived / already passed).
    let ratio = max(centerMean, edgeMean) / max(min(centerMean, edgeMean), 1e-8)
    #expect(ratio > 1.05,
            "Turning wave must produce non-uniform response (center=\(centerMean), edge=\(edgeMean), ratio=\(ratio))")
}

@Test func test_particleKernel_withValidStems_respondsToBassDrift() throws {
    // Bass energy drives macro body movement — different bass levels should
    // produce different flock center positions after several frames.
    let ctx = try MetalContext()
    let lib = try ShaderLibrary(context: ctx)
    let config = ParticleConfiguration(particleCount: 1024)

    let baseFeatures = FeatureVector(time: 2.0, deltaTime: 0.016)

    // Low bass: compact, slow drift.
    let geometryLow = try ProceduralGeometry(
        device: ctx.device, library: lib.library, configuration: config
    )
    let stemsLow = StemFeatures(drumsEnergy: 0.1, bassEnergy: 0.05, otherEnergy: 0.05)
    try warmupGeometry(geometryLow, queue: ctx.commandQueue, frames: 40,
                       features: baseFeatures, stems: stemsLow)
    let statsLow = FlockStats.measure(geometryLow, count: config.particleCount)

    // High bass: elongated, fast sweep.
    let geometryHigh = try ProceduralGeometry(
        device: ctx.device, library: lib.library, configuration: config
    )
    let stemsHigh = StemFeatures(drumsEnergy: 0.1, bassEnergy: 0.9, otherEnergy: 0.05)
    try warmupGeometry(geometryHigh, queue: ctx.commandQueue, frames: 40,
                       features: baseFeatures, stems: stemsHigh)
    let statsHigh = FlockStats.measure(geometryHigh, count: config.particleCount)

    // Higher bass → larger spatial spread (halfLength increases with bass_energy).
    let totalVarianceLow  = statsLow.varianceX  + statsLow.varianceY
    let totalVarianceHigh = statsHigh.varianceX + statsHigh.varianceY

    #expect(totalVarianceHigh > totalVarianceLow * 1.05,
            "High bass_energy must produce larger flock spread than low (varLow=\(totalVarianceLow), varHigh=\(totalVarianceHigh))")
}

/// Reset all particle positions to origin so the spring converges to homePos
/// in ~25 frames rather than ~100 frames from the golden-spiral initialization.
private func resetParticlePositions(_ geometry: ProceduralGeometry, count: Int) {
    let ptr = geometry.particleBuffer.contents().bindMemory(
        to: Particle.self, capacity: count
    )
    for i in 0..<count {
        ptr[i].positionX = 0; ptr[i].positionY = 0; ptr[i].positionZ = 0
        ptr[i].velocityX = 0; ptr[i].velocityY = 0; ptr[i].velocityZ = 0
    }
}

@Test func test_particleKernel_withValidStems_respondsToOtherFlutter() throws {
    // other_energy drives flock width: halfWidth = 0.10 + 0.05 * otherEnergy.
    //   Low (0.02): halfWidth ≈ 0.101
    //   High (0.90): halfWidth ≈ 0.145  → 44% wider → variance ≈ 2× higher
    //
    // At t ≈ 0 shapeAngle ≈ 0, so flock length → X and width → Y.
    // Y variance is therefore ∝ halfWidth² and clearly distinguishable.
    //
    // Particle positions are reset to origin so the spring converges to homePos
    // in ~25 frames (rather than 100+ frames from the golden-spiral init).
    let ctx = try MetalContext()
    let lib = try ShaderLibrary(context: ctx)
    let config = ParticleConfiguration(particleCount: 2048)

    // t=0.01: shapeAngle ≈ 0.06 (nearly axis-aligned, width → Y).
    let baseFeatures = FeatureVector(time: 0.01, deltaTime: 0.016)

    // Low other energy: narrow flock.
    let geometryLow = try ProceduralGeometry(
        device: ctx.device, library: lib.library, configuration: config
    )
    let stemsLow = StemFeatures(
        drumsEnergy: 0.1, bassEnergy: 0.2,
        otherEnergy: 0.02, otherBand0: 0.01, otherBand1: 0.01
    )
    resetParticlePositions(geometryLow, count: config.particleCount)
    try warmupGeometry(geometryLow, queue: ctx.commandQueue, frames: 25,
                       features: baseFeatures, stems: stemsLow)
    let statsLow = FlockStats.measure(geometryLow, count: config.particleCount)

    // High other energy: wider flock.
    let geometryHigh = try ProceduralGeometry(
        device: ctx.device, library: lib.library, configuration: config
    )
    let stemsHigh = StemFeatures(
        drumsEnergy: 0.1, bassEnergy: 0.2,
        otherEnergy: 0.9, otherBand0: 0.7, otherBand1: 0.8
    )
    resetParticlePositions(geometryHigh, count: config.particleCount)
    try warmupGeometry(geometryHigh, queue: ctx.commandQueue, frames: 25,
                       features: baseFeatures, stems: stemsHigh)
    let statsHigh = FlockStats.measure(geometryHigh, count: config.particleCount)

    // halfWidth ratio 1.44 → variance ratio ≈ 2.07. Use 50% threshold.
    #expect(statsHigh.varianceY > statsLow.varianceY * 1.50,
            "High other_energy must produce wider flock (varYLow=\(statsLow.varianceY), varYHigh=\(statsHigh.varianceY))")
}

@Test func test_particleKernel_warmupBlend_smoothTransition() throws {
    // Verify that the crossfade from full-mix fallback to stem routing
    // does not produce a discontinuous position jump.
    //
    // We run frames with increasing totalStemEnergy and measure per-frame
    // maximum position delta. No single frame should exceed a jump threshold.
    let ctx = try MetalContext()
    let lib = try ShaderLibrary(context: ctx)
    let config = ParticleConfiguration(particleCount: 1024)
    let geometry = try ProceduralGeometry(
        device: ctx.device, library: lib.library, configuration: config
    )

    let baseFeatures = FeatureVector(
        bass: 0.3, subBass: 0.2, lowBass: 0.1,
        highMid: 0.1, high: 0.05,
        time: 1.0, deltaTime: 0.016
    )
    let ptr = geometry.particleBuffer.contents().bindMemory(
        to: Particle.self, capacity: config.particleCount
    )

    // Warmup with zero stems.
    let zeroStems = StemFeatures.zero
    try warmupGeometry(geometry, queue: ctx.commandQueue, frames: 15,
                       features: baseFeatures, stems: zeroStems)

    // Ramp stem energy through the crossfade window and record max frame delta.
    let energySteps: [Float] = [0.0, 0.01, 0.02, 0.03, 0.04, 0.05, 0.06, 0.08, 0.10]
    var maxFrameDelta: Float = 0

    for energy in energySteps {
        // Snapshot positions before dispatch.
        var prevX = [Float](repeating: 0, count: config.particleCount)
        var prevY = [Float](repeating: 0, count: config.particleCount)
        for i in 0..<config.particleCount {
            prevX[i] = ptr[i].positionX
            prevY[i] = ptr[i].positionY
        }

        let stems = StemFeatures(
            drumsEnergy: energy, bassEnergy: energy, otherEnergy: energy
        )
        let feat = FeatureVector(
            bass: 0.3, subBass: 0.2, lowBass: 0.1,
            highMid: 0.1, high: 0.05,
            time: 1.0 + energy, deltaTime: 0.016
        )
        try dispatch(geometry: geometry, features: feat, stems: stems,
                     queue: ctx.commandQueue)

        // Measure maximum position change for any particle.
        for i in 0..<config.particleCount {
            let dx = ptr[i].positionX - prevX[i]
            let dy = ptr[i].positionY - prevY[i]
            maxFrameDelta = max(maxFrameDelta, sqrt(dx * dx + dy * dy))
        }
    }

    // With dt=0.016 and max speed 3.0, max theoretical displacement = 0.048.
    // Allow 3× margin for spring forces at transition, but no discontinuous jump.
    let maxAllowedDelta: Float = 0.20
    #expect(maxFrameDelta < maxAllowedDelta,
            "Warmup crossfade must not produce discontinuous position jumps (maxFrameDelta=\(maxFrameDelta))")
}

@Test func test_particleKernel_vocalsEnergy_affectsDensity() throws {
    // Vocals energy should compress the flock (tighter packing = lower variance).
    // The density compression is applied to halfLength and halfWidth via densityScale.
    let ctx = try MetalContext()
    let lib = try ShaderLibrary(context: ctx)
    let config = ParticleConfiguration(particleCount: 2048)

    let baseFeatures = FeatureVector(
        bass: 0.3, mid: 0.2, time: 2.0, deltaTime: 0.016
    )
    let baseStems = StemFeatures(drumsEnergy: 0.1, bassEnergy: 0.3, otherEnergy: 0.1)

    // No vocals: flock at natural spread.
    let geometryNoVocals = try ProceduralGeometry(
        device: ctx.device, library: lib.library, configuration: config
    )
    let stemsNoVocals = StemFeatures(
        vocalsEnergy: 0.0, drumsEnergy: 0.1, bassEnergy: 0.3, otherEnergy: 0.1
    )
    try warmupGeometry(geometryNoVocals, queue: ctx.commandQueue, frames: 35,
                       features: baseFeatures, stems: stemsNoVocals)
    let statsNoVocals = FlockStats.measure(geometryNoVocals, count: config.particleCount)

    // High vocals: density compression applied.
    let geometryVocals = try ProceduralGeometry(
        device: ctx.device, library: lib.library, configuration: config
    )
    let stemsVocals = StemFeatures(
        vocalsEnergy: 1.0, drumsEnergy: 0.1, bassEnergy: 0.3, otherEnergy: 0.1
    )
    try warmupGeometry(geometryVocals, queue: ctx.commandQueue, frames: 35,
                       features: baseFeatures, stems: stemsVocals)
    let statsVocals = FlockStats.measure(geometryVocals, count: config.particleCount)

    let varianceNoVocals = statsNoVocals.varianceX + statsNoVocals.varianceY
    let varianceVocals   = statsVocals.varianceX   + statsVocals.varianceY

    // Vocal density compression (22%) should reduce spatial variance.
    #expect(varianceVocals < varianceNoVocals * 0.98,
            "High vocals_energy must produce tighter flock packing (varNoVocals=\(varianceNoVocals), varVocals=\(varianceVocals))")

    _ = baseStems
}

@Test func test_stemFeatures_bufferBinding_noConflictWithExistingBindings() throws {
    // Verify that the Murmuration compute kernel compiles successfully with
    // all its buffer parameters (particles=0, features=1, config=2, stems=3).
    // A compilation failure here indicates a buffer index collision.
    let ctx = try MetalContext()
    let lib = try ShaderLibrary(context: ctx)
    let config = ParticleConfiguration(particleCount: 256)

    // If there's a buffer index conflict, the kernel lookup or pipeline creation
    // inside ProceduralGeometry.init would throw.
    let geometry = try ProceduralGeometry(
        device: ctx.device, library: lib.library, configuration: config
    )

    // Dispatch with non-zero stems at buffer(3) — confirms binding is live.
    let features = FeatureVector(bass: 0.5, time: 1.0, deltaTime: 0.016)
    let stems = StemFeatures(drumsEnergy: 0.5, drumsBeat: 0.8, bassEnergy: 0.4)
    let cmdBuf = try dispatch(
        geometry: geometry, features: features, stems: stems, queue: ctx.commandQueue
    )

    #expect(cmdBuf.status == .completed,
            "Compute kernel must compile and dispatch without buffer index conflicts")
    #expect(cmdBuf.error == nil,
            "No GPU error expected when all four buffer slots are correctly bound")
}
