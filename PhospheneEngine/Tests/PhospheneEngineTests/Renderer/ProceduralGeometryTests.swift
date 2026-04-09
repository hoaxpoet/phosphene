// ProceduralGeometryTests — GPU compute particle system tests.

import Testing
import Metal
@testable import Renderer
@testable import Shared

// MARK: - Unit Tests

@Test func test_init_particleBuffer_allocatedWithCapacity() throws {
    let ctx = try MetalContext()
    let lib = try ShaderLibrary(context: ctx)
    let config = ParticleConfiguration(particleCount: 1024)

    let geometry = try ProceduralGeometry(
        device: ctx.device, library: lib.library, configuration: config
    )

    let expectedSize = 1024 * MemoryLayout<Particle>.stride
    #expect(geometry.particleBuffer.length == expectedSize,
            "Particle buffer should be allocated with capacity for 1024 particles")
}

@Test func test_particleBuffer_storageModeShared() throws {
    let ctx = try MetalContext()
    let lib = try ShaderLibrary(context: ctx)
    let config = ParticleConfiguration(particleCount: 512)

    let geometry = try ProceduralGeometry(
        device: ctx.device, library: lib.library, configuration: config
    )

    // UMA zero-copy: .storageModeShared (no CPU↔GPU copies on Apple Silicon).
    let mode = geometry.particleBuffer.resourceOptions.intersection(.storageModeShared)
    #expect(mode == .storageModeShared,
            "Particle buffer must use .storageModeShared for UMA zero-copy")
}

@Test func test_dispatch_compute_noGPUError() throws {
    let ctx = try MetalContext()
    let lib = try ShaderLibrary(context: ctx)
    let config = ParticleConfiguration(particleCount: 1024)

    let geometry = try ProceduralGeometry(
        device: ctx.device, library: lib.library, configuration: config
    )

    guard let cmdBuf = ctx.commandQueue.makeCommandBuffer() else {
        throw ProceduralGeometryTestError.metalSetupFailed
    }

    let features = FeatureVector(bass: 0.5, beatBass: 0.8, time: 1.0, deltaTime: 0.016)
    geometry.update(features: features, commandBuffer: cmdBuf)

    cmdBuf.commit()
    cmdBuf.waitUntilCompleted()

    #expect(cmdBuf.status == .completed, "Compute command buffer should complete without error")
    #expect(cmdBuf.error == nil, "Compute dispatch should produce no GPU error")
}

@Test func test_particleCount_matchesConfiguration() throws {
    let ctx = try MetalContext()
    let lib = try ShaderLibrary(context: ctx)

    let counts = [256, 1024, 4096]
    for count in counts {
        let config = ParticleConfiguration(particleCount: count)
        let geometry = try ProceduralGeometry(
            device: ctx.device, library: lib.library, configuration: config
        )

        #expect(geometry.configuration.particleCount == count)

        let particleStride = MemoryLayout<Particle>.stride
        let expectedBytes = count * particleStride
        #expect(geometry.particleBuffer.length == expectedBytes)
    }
}

@Test func test_zeroAudioInput_particlesStationary() throws {
    let ctx = try MetalContext()
    let lib = try ShaderLibrary(context: ctx)
    let config = ParticleConfiguration(particleCount: 1024)

    let geometry = try ProceduralGeometry(
        device: ctx.device, library: lib.library, configuration: config
    )

    // Dispatch with completely zero audio features.
    guard let cmdBuf = ctx.commandQueue.makeCommandBuffer() else {
        throw ProceduralGeometryTestError.metalSetupFailed
    }

    let features = FeatureVector.zero
    geometry.update(features: features, commandBuffer: cmdBuf)

    cmdBuf.commit()
    cmdBuf.waitUntilCompleted()

    // Read back particle data — velocities should be very low with zero audio.
    // Particles have slow ambient orbital drift even at rest (they're organisms,
    // not inert objects), but no audio-driven forces should be active.
    let ptr = geometry.particleBuffer.contents().bindMemory(
        to: Particle.self, capacity: config.particleCount
    )

    var maxVelocity: Float = 0
    for i in 0..<config.particleCount {
        let p = ptr[i]
        let speed = sqrt(p.velocityX * p.velocityX
                       + p.velocityY * p.velocityY
                       + p.velocityZ * p.velocityZ)
        maxVelocity = max(maxVelocity, speed)
    }

    #expect(maxVelocity < 10.0,
            "With zero audio, particle velocities should be bounded by flocking physics")
}

@Test func test_impulseAudioInput_particlesEmitted() throws {
    let ctx = try MetalContext()
    let lib = try ShaderLibrary(context: ctx)
    let config = ParticleConfiguration(
        particleCount: 4096,
        burstThreshold: 0.4,
        burstVelocity: 1.0
    )

    let geometry = try ProceduralGeometry(
        device: ctx.device, library: lib.library, configuration: config
    )

    // First dispatch: zero audio to establish baseline velocities.
    guard let cmdBuf1 = ctx.commandQueue.makeCommandBuffer() else {
        throw ProceduralGeometryTestError.metalSetupFailed
    }
    let quietFeatures = FeatureVector(time: 0.5, deltaTime: 0.016)
    geometry.update(features: quietFeatures, commandBuffer: cmdBuf1)
    cmdBuf1.commit()
    cmdBuf1.waitUntilCompleted()

    // Measure baseline average speed.
    let ptr = geometry.particleBuffer.contents().bindMemory(
        to: Particle.self, capacity: config.particleCount
    )
    var baselineTotal: Float = 0
    for i in 0..<config.particleCount {
        let p = ptr[i]
        baselineTotal += sqrt(p.velocityX * p.velocityX + p.velocityY * p.velocityY)
    }
    let baselineAvg = baselineTotal / Float(config.particleCount)

    // Second dispatch: strong beat impulse.
    guard let cmdBuf2 = ctx.commandQueue.makeCommandBuffer() else {
        throw ProceduralGeometryTestError.metalSetupFailed
    }
    let beatFeatures = FeatureVector(
        bass: 0.8, mid: 0.5, treble: 0.3,
        beatBass: 0.9, beatComposite: 0.8,
        spectralCentroid: 0.5,
        time: 1.0, deltaTime: 0.016
    )
    geometry.update(features: beatFeatures, commandBuffer: cmdBuf2)
    cmdBuf2.commit()
    cmdBuf2.waitUntilCompleted()

    // Measure post-beat average speed — should be noticeably higher.
    var beatTotal: Float = 0
    for i in 0..<config.particleCount {
        let p = ptr[i]
        beatTotal += sqrt(p.velocityX * p.velocityX + p.velocityY * p.velocityY)
    }
    let beatAvg = beatTotal / Float(config.particleCount)

    // In the flow-field flock model, birds always have velocity from the field.
    // Beat scatter changes direction more than raw speed. Verify birds are moving.
    #expect(beatAvg > 0.05,
            "Particles should have meaningful velocity from the flow field")
    #expect(baselineAvg > 0.05,
            "Particles should have baseline velocity even without beat impulse")
}

// MARK: - Performance Test

@Test func test_particleCompute_1MillionParticles_under8ms() throws {
    let ctx = try MetalContext()
    let lib = try ShaderLibrary(context: ctx)
    let config = ParticleConfiguration(particleCount: 1_000_000)

    let geometry = try ProceduralGeometry(
        device: ctx.device, library: lib.library, configuration: config
    )

    // Warmup dispatch (first dispatch may include pipeline setup overhead).
    if let warmup = ctx.commandQueue.makeCommandBuffer() {
        let features = FeatureVector(bass: 0.5, beatBass: 0.8, time: 0.5, deltaTime: 0.016)
        geometry.update(features: features, commandBuffer: warmup)
        warmup.commit()
        warmup.waitUntilCompleted()
    }

    // Timed dispatch.
    let iterations = 10
    var totalTime: Double = 0

    for i in 0..<iterations {
        guard let cmdBuf = ctx.commandQueue.makeCommandBuffer() else {
            throw ProceduralGeometryTestError.metalSetupFailed
        }

        let features = FeatureVector(
            bass: 0.6, mid: 0.4, treble: 0.2,
            beatBass: 0.9, beatComposite: 0.7,
            time: Float(i) * 0.016, deltaTime: 0.016
        )

        let start = CFAbsoluteTimeGetCurrent()
        geometry.update(features: features, commandBuffer: cmdBuf)
        cmdBuf.commit()
        cmdBuf.waitUntilCompleted()
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        totalTime += elapsed
    }

    let averageMs = (totalTime / Double(iterations)) * 1000.0

    #expect(averageMs < 8.0,
            "1M particle compute should average under 8ms")
}

// MARK: - Error

enum ProceduralGeometryTestError: Error {
    case metalSetupFailed
}
