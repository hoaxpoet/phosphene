// DriftMotesAudioCouplingTest — Verify the DM.3 audio reactivities.
//
// Three tests covering the two DM.3 audio routings landing in
// `motes_update`:
//
//   1. Emission rate scaling — high `f.mid_att_rel` over 200 frames
//      compresses average particle age by ≥ 1/0.7 vs. low mid. Validates
//      the `1 / (1 + kEmissionRateGain * mid_att_rel)` lifetime divisor.
//   2. Dispersion shock under a 2 Hz square wave on `stems.drums_beat`
//      raises per-particle velocity-magnitude variance ≥ 1.5× the
//      silence baseline.
//   3. Dispersion shock decays between beats — a single impulse followed
//      by 60 frames of silence settles the velocity-variance back inside
//      1.2× the silence baseline. Proves the field doesn't accumulate
//      runaway dispersion.
//
// Structurally mirrors `DriftMotesRespawnDeterminismTest`: a single
// `MetalContext` + `ShaderLibrary` + `DriftMotesGeometry`, dispatched
// against synthesized FeatureVector / StemFeatures fixtures via the
// public `update(...)` API.

import Testing
import Metal
@testable import Renderer
@testable import Shared

// MARK: - Helpers

private enum DMAudioCouplingTestError: Error { case metalSetupFailed }

@discardableResult
private func dispatch(
    geometry: DriftMotesGeometry,
    features: FeatureVector,
    stems: StemFeatures,
    queue: MTLCommandQueue
) throws -> MTLCommandBuffer {
    guard let cmdBuf = queue.makeCommandBuffer() else {
        throw DMAudioCouplingTestError.metalSetupFailed
    }
    geometry.update(features: features, stemFeatures: stems, commandBuffer: cmdBuf)
    cmdBuf.commit()
    cmdBuf.waitUntilCompleted()
    return cmdBuf
}

private func snapshot(buffer: MTLBuffer, count: Int) -> [Particle] {
    let ptr = buffer.contents().bindMemory(to: Particle.self, capacity: count)
    return (0..<count).map { ptr[$0] }
}

private func variance(_ values: [Float]) -> Float {
    guard !values.isEmpty else { return 0 }
    let mean = values.reduce(0, +) / Float(values.count)
    let sumSq = values.reduce(Float(0)) { acc, v in
        let d = v - mean
        return acc + d * d
    }
    return sumSq / Float(values.count)
}

private func averageAge(_ particles: [Particle]) -> Float {
    guard !particles.isEmpty else { return 0 }
    let sum = particles.reduce(Float(0)) { $0 + $1.age }
    return sum / Float(particles.count)
}

private func velocityMagnitudes(_ particles: [Particle]) -> [Float] {
    particles.map {
        let vx = $0.velocityX
        let vy = $0.velocityY
        let vz = $0.velocityZ
        return sqrt(vx * vx + vy * vy + vz * vz)
    }
}

/// Run `frameCount` frames against the supplied stems/features providers and
/// return the final particle snapshot. Wraps the per-frame dispatch to keep
/// the tests focused on assertions.
private func runFrames(
    geometry: DriftMotesGeometry,
    queue: MTLCommandQueue,
    frameCount: Int,
    midAttRel: Float = 0,
    stemsProvider: (Int) -> StemFeatures
) throws -> [Particle] {
    let dt: Float = 1.0 / 60.0
    var features = FeatureVector.zero
    features.deltaTime = dt
    features.midAttRel = midAttRel
    for frame in 0..<frameCount {
        features.time = Float(frame) * dt
        try dispatch(geometry: geometry, features: features,
                     stems: stemsProvider(frame), queue: queue)
    }
    return snapshot(buffer: geometry.particleBuffer, count: geometry.particleCount)
}

// MARK: - Test 1 — Emission rate scaling (DM.3 Task 1)

@Test func test_driftMotes_emissionRate_scalesWithMidAttRel() throws {
    let ctx = try MetalContext()
    let lib = try ShaderLibrary(context: ctx)

    // 600 frames (10 s simulated) — long enough for the population to
    // relax close to the new steady state under the shortened lifetimes
    // (lifeMin = 5 s; one full lifetime turn-over). The prompt's nominal
    // 200-frame window measures only the first ~half-lifetime of relaxation,
    // which is dominated by the init age distribution and produces a
    // ~5 % age delta — invisible against natural variance.
    func averageAgeAt(midAttRel: Float) throws -> Float {
        let geometry = try DriftMotesGeometry(
            device: ctx.device,
            library: lib.library,
            particleCount: 800,
            pixelFormat: nil
        )
        let snap = try runFrames(
            geometry: geometry,
            queue: ctx.commandQueue,
            frameCount: 600,
            midAttRel: midAttRel,
            stemsProvider: { _ in .zero }
        )
        return averageAge(snap)
    }

    let avgLow  = try averageAgeAt(midAttRel: 0.1)
    let avgHigh = try averageAgeAt(midAttRel: 0.9)
    let ratio   = avgHigh / max(avgLow, 1e-6)
    let diagnostic = "avgAgeLow=\(avgLow), avgAgeHigh=\(avgHigh), ratio=\(ratio)"

    // High mid → shorter lifetimes → particles respawn more often → average
    // age across the field is lower. Steady-state target ratio ≈ 0.49
    // (factor 0.43 over factor 0.87); 0.7 ceiling leaves margin for the
    // ~85% relaxation a 600-frame window produces and the random seed
    // distribution while still catching a no-op (ratio would be ~1.0).
    #expect(ratio < 0.7,
            "Emission rate scaling not firing — avg age under high mid_att_rel should be < 0.7× the low baseline. \(diagnostic)")
}

// MARK: - Test 2 — Dispersion shock raises velocity variance (DM.3 Task 2)

@Test func test_driftMotes_dispersionShock_increasesVelocityVariance() throws {
    let ctx = try MetalContext()
    let lib = try ShaderLibrary(context: ctx)

    func varianceAfter240Frames(stemsProvider: (Int) -> StemFeatures) throws -> Float {
        let geometry = try DriftMotesGeometry(
            device: ctx.device,
            library: lib.library,
            particleCount: 800,
            pixelFormat: nil
        )
        let snap = try runFrames(
            geometry: geometry,
            queue: ctx.commandQueue,
            frameCount: 240,
            midAttRel: 0,
            stemsProvider: stemsProvider
        )
        return variance(velocityMagnitudes(snap))
    }

    // Silence baseline — the field velocity variance comes from the
    // wind+turbulence baseline alone.
    let silenceVar = try varianceAfter240Frames(stemsProvider: { _ in .zero })

    // 2 Hz square wave on drums_beat — 30-frame period at 60 fps, 50% duty.
    // Stems are otherwise warm so D-019-gated paths agree the field is
    // active (matters for hue baking; not strictly required for dispersion).
    let shockVar = try varianceAfter240Frames(stemsProvider: { frame in
        var stems = StemFeatures.zero
        stems.drumsEnergy  = 0.4
        stems.bassEnergy   = 0.3
        stems.otherEnergy  = 0.2
        stems.vocalsEnergy = 0.2
        let inHighHalf = (frame / 15) % 2 == 0
        stems.drumsBeat = inHighHalf ? 1.0 : 0.0
        return stems
    })

    let ratio = shockVar / max(silenceVar, 1e-6)
    let diagnostic = "silenceVar=\(silenceVar), shockVar=\(shockVar), ratio=\(ratio)"
    #expect(ratio >= 1.5,
            "Dispersion shock not firing — velocity-magnitude variance under 2 Hz drums_beat should be ≥ 1.5× the silence baseline. \(diagnostic)")
}

// MARK: - Test 3 — Dispersion shock decays between beats (DM.3 Task 2)

@Test func test_driftMotes_dispersionShock_decaysBetweenBeats() throws {
    let ctx = try MetalContext()
    let lib = try ShaderLibrary(context: ctx)

    // Silence baseline — same setup as Test 2 but no beat ever fires.
    let silenceGeometry = try DriftMotesGeometry(
        device: ctx.device,
        library: lib.library,
        particleCount: 800,
        pixelFormat: nil
    )
    let silenceSnap = try runFrames(
        geometry: silenceGeometry,
        queue: ctx.commandQueue,
        frameCount: 60,
        midAttRel: 0,
        stemsProvider: { _ in .zero }
    )
    let silenceVar = variance(velocityMagnitudes(silenceSnap))

    // Single impulse at frame 0, then 60 frames of silence. Damping 0.97/frame
    // brings the dispersion contribution down to 0.97^60 ≈ 0.16 of its
    // original size; the wind component dominates the steady state.
    let impulseGeometry = try DriftMotesGeometry(
        device: ctx.device,
        library: lib.library,
        particleCount: 800,
        pixelFormat: nil
    )
    let impulseSnap = try runFrames(
        geometry: impulseGeometry,
        queue: ctx.commandQueue,
        frameCount: 60,
        midAttRel: 0,
        stemsProvider: { frame in
            guard frame == 0 else { return .zero }
            var stems = StemFeatures.zero
            stems.drumsEnergy  = 0.4
            stems.drumsBeat = 1.0
            return stems
        }
    )
    let postImpulseVar = variance(velocityMagnitudes(impulseSnap))

    let ratio = postImpulseVar / max(silenceVar, 1e-6)
    let diagnostic = "silenceVar=\(silenceVar), postImpulseVar=\(postImpulseVar), ratio=\(ratio)"
    // 1.2× ceiling: the field has settled back into wind drift; any residual
    // dispersion is a small additive on top of the baseline.
    #expect(ratio < 1.2,
            "Dispersion shock not decaying — 60 frames after a single beat the velocity-magnitude variance should be within 1.2× of the silence baseline. \(diagnostic)")
}
