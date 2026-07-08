// RicercarFluidGeometry.swift — GPU fluid dye simulation conformer for Ricercar (Fantasia rebuild).
//
// A `ParticleGeometry` sibling (D-097), modelled on MitosisGeometry: a ping-ponged compute field
// advanced in `update()` and drawn by a fullscreen fragment in `render()`. Here the field is a Jos
// Stam stable-fluids sim (kernels in RicercarFluid.metal) producing the luminous ink-in-water flowing
// colour masses the Fantasia rebuild needs (RICERCAR_DESIGN §FANTASIA REBUILD; ref
// docs/VISUAL_REFERENCES/ricercar/02). Glowing weaving ribbons (ref 01) layer on later.
//
// Per frame the encoder runs, in order (a `.textures` barrier between dependent passes — Metal does not
// serialise consecutive dispatches, cf. MitosisGeometry):
//   splat vel → splat dye → curl → vorticity → divergence → pressure Jacobi ×N → gradient-subtract
//   → advect velocity → advect dye.
//
// Splats are the section sources. Until the audio drive lands (FL.3) the conformer injects a small
// PROCEDURAL set (hand-animated blooms in family colours) so the look can be judged against ref 02 with
// no music wiring — the prototype-the-look-first commitment.

import Metal
import simd
import Shared

// MARK: - GPU-mirrored structs (layouts match RicercarFluid.metal exactly)

/// Mirror of MSL `FluidConfig`. 2×uint + 6×float = 32 bytes, align 4.
struct RicercarFluidConfig {
    var width: UInt32
    var height: UInt32
    var dt: Float
    var velocityDissipation: Float
    var dyeDissipation: Float
    var vorticity: Float
    var pressure: Float
    var exposure: Float
}

/// Mirror of MSL `FluidSplat` — two float4 for a guaranteed layout match (no float3 alignment trap).
struct FluidSplat {
    var posVel: SIMD4<Float>    // pos.xy, vel.xy
    var colorRad: SIMD4<Float>  // color.rgb, radius
}

// MARK: - RicercarFluidGeometry

public final class RicercarFluidGeometry: ParticleGeometry, @unchecked Sendable {

    public var activeParticleFraction: Float = 1.0   // a fluid field is fully coupled; governor unused

    private let width: Int
    private let height: Int
    private var cfg: RicercarFluidConfig
    private let pressureIterations: Int

    // Ping-pong fields.
    private var velocity: [MTLTexture]   // 2× rg16Float
    private var pressure: [MTLTexture]   // 2× r16Float
    private var dye: [MTLTexture]        // 2× rgba16Float
    private let curl: MTLTexture         // r16Float scratch
    private let divergence: MTLTexture   // r16Float scratch
    private var vcur = 0, pcur = 0, dcur = 0

    // Compute pipelines.
    private let clearPSO, splatVelPSO, splatDyePSO, curlPSO, vorticityPSO: MTLComputePipelineState
    private let divergencePSO, pressurePSO, gradSubPSO, advectVelPSO, advectDyePSO: MTLComputePipelineState
    private let renderPSO: MTLRenderPipelineState?

    private var time: Float = 0

    /// The dye texture currently holding the field — exposed for render tests to read back.
    public var currentDyeTexture: MTLTexture { dye[dcur] }

    public enum FluidError: Error { case textureAllocationFailed, functionNotFound(String) }

    public init(
        device: MTLDevice,
        library: MTLLibrary,
        width: Int = 320,
        height: Int = 180,
        pressureIterations: Int = 25,
        pixelFormat: MTLPixelFormat? = nil
    ) throws {
        self.width = width
        self.height = height
        self.pressureIterations = pressureIterations
        self.cfg = RicercarFluidConfig(
            width: UInt32(width),
            height: UInt32(height),
            dt: 1.0,                        // per-frame integration; velocities are in TEXELS/FRAME
            velocityDissipation: 0.08,      // gentle drag → currents persist and roll
            dyeDissipation: 0.015,          // slow fade → dye accumulates into masses, then breathes out
            vorticity: 0.4,                 // small confinement → the plumes roll/billow (ref-02 tell)
            pressure: 0.8,
            exposure: 1.2)

        self.velocity = [try Self.makeField(device, .rg16Float, width, height),
                         try Self.makeField(device, .rg16Float, width, height)]
        self.pressure = [try Self.makeField(device, .r16Float, width, height),
                         try Self.makeField(device, .r16Float, width, height)]
        self.dye = [try Self.makeField(device, .rgba16Float, width, height),
                    try Self.makeField(device, .rgba16Float, width, height)]
        self.curl = try Self.makeField(device, .r16Float, width, height)
        self.divergence = try Self.makeField(device, .r16Float, width, height)

        func pso(_ name: String) throws -> MTLComputePipelineState {
            guard let fn = library.makeFunction(name: name) else { throw FluidError.functionNotFound(name) }
            return try device.makeComputePipelineState(function: fn)
        }
        self.clearPSO      = try pso("fluid_clear")
        self.splatVelPSO   = try pso("fluid_splat_velocity")
        self.splatDyePSO   = try pso("fluid_splat_dye")
        self.curlPSO       = try pso("fluid_curl")
        self.vorticityPSO  = try pso("fluid_vorticity")
        self.divergencePSO = try pso("fluid_divergence")
        self.pressurePSO   = try pso("fluid_pressure")
        self.gradSubPSO    = try pso("fluid_gradient_subtract")
        self.advectVelPSO  = try pso("fluid_advect_velocity")
        self.advectDyePSO  = try pso("fluid_advect_dye")

        if let pixelFormat {
            guard let vfn = library.makeFunction(name: "ricercar_fluid_vertex"),
                  let ffn = library.makeFunction(name: "ricercar_fluid_fragment") else {
                throw FluidError.functionNotFound("ricercar_fluid_vertex/fragment")
            }
            let desc = MTLRenderPipelineDescriptor()
            desc.vertexFunction = vfn
            desc.fragmentFunction = ffn
            desc.colorAttachments[0].pixelFormat = pixelFormat
            self.renderPSO = try device.makeRenderPipelineState(descriptor: desc)
        } else {
            self.renderPSO = nil
        }

        clearAllFields(device: device)
    }

    // MARK: - Init helpers

    private static func makeField(_ device: MTLDevice, _ fmt: MTLPixelFormat,
                                  _ width: Int, _ height: Int) throws -> MTLTexture {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: fmt, width: width, height: height, mipmapped: false)
        desc.usage = [.shaderRead, .shaderWrite]
        desc.storageMode = .private
        guard let tex = device.makeTexture(descriptor: desc) else { throw FluidError.textureAllocationFailed }
        return tex
    }

    private func clearAllFields(device: MTLDevice) {
        guard let queue = device.makeCommandQueue(),
              let cmd = queue.makeCommandBuffer(),
              let enc = cmd.makeComputeCommandEncoder() else { return }
        var cfgLocal = cfg
        for tex in velocity + pressure + dye + [curl, divergence] {
            enc.setComputePipelineState(clearPSO)
            enc.setTexture(tex, index: 0)
            enc.setBytes(&cfgLocal, length: MemoryLayout<RicercarFluidConfig>.stride, index: 0)
            dispatch(enc)
        }
        enc.endEncoding()
        cmd.commit()
        cmd.waitUntilCompleted()
    }

    private func dispatch(_ enc: MTLComputeCommandEncoder) {
        enc.dispatchThreads(MTLSize(width: width, height: height, depth: 1),
                            threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
    }

    // MARK: - ParticleGeometry

    public func update(features: FeatureVector, stemFeatures: StemFeatures, commandBuffer: MTLCommandBuffer) {
        let dt = features.deltaTime > 0 ? features.deltaTime : 1.0 / 60.0
        time += dt
        var cfgLocal = cfg

        var splats = proceduralSplats(time: time)   // FL.2 prototype: hand-animated section blooms
        var splatCount = UInt32(splats.count)

        guard let enc = commandBuffer.makeComputeCommandEncoder() else { return }
        enc.setBytes(&cfgLocal, length: MemoryLayout<RicercarFluidConfig>.stride, index: 0)

        // 1. Splat velocity + dye from the section sources.
        if splatCount > 0 {
            run(enc, splatVelPSO, tex: [velocity[vcur], velocity[1 - vcur]]) {
                enc.setBytes(&splats, length: MemoryLayout<FluidSplat>.stride * splats.count, index: 1)
                enc.setBytes(&splatCount, length: MemoryLayout<UInt32>.stride, index: 2)
            }
            vcur = 1 - vcur
            run(enc, splatDyePSO, tex: [dye[dcur], dye[1 - dcur]]) {
                enc.setBytes(&splats, length: MemoryLayout<FluidSplat>.stride * splats.count, index: 1)
                enc.setBytes(&splatCount, length: MemoryLayout<UInt32>.stride, index: 2)
            }
            dcur = 1 - dcur
        }

        // 2. Curl → 3. Vorticity confinement.
        run(enc, curlPSO, tex: [velocity[vcur], curl])
        run(enc, vorticityPSO, tex: [velocity[vcur], curl, velocity[1 - vcur]])
        vcur = 1 - vcur

        // 4. Divergence → 5. Pressure Jacobi ×N → 6. Gradient subtract.
        run(enc, divergencePSO, tex: [velocity[vcur], divergence])
        // Fresh Poisson solve each frame: clear pressure, then iterate. (Warm-starting from stale
        // pressure without the cfg.pressure fade drifted → chaotic velocity → dye torn into dots.)
        run(enc, clearPSO, tex: [pressure[pcur]])
        for _ in 0..<pressureIterations {
            run(enc, pressurePSO, tex: [pressure[pcur], divergence, pressure[1 - pcur]])
            pcur = 1 - pcur
        }
        run(enc, gradSubPSO, tex: [pressure[pcur], velocity[vcur], velocity[1 - vcur]])
        vcur = 1 - vcur

        // 7. Advect velocity → 8. Advect dye.
        run(enc, advectVelPSO, tex: [velocity[vcur], velocity[1 - vcur]])
        vcur = 1 - vcur
        run(enc, advectDyePSO, tex: [velocity[vcur], dye[dcur], dye[1 - dcur]])
        dcur = 1 - dcur

        enc.endEncoding()
    }

    /// Dispatch one compute pass: bind textures at 0,1,2…, run `extra` for extra bindings, dispatch,
    /// then a `.textures` barrier so the next dependent pass sees the writes.
    private func run(_ enc: MTLComputeCommandEncoder, _ pso: MTLComputePipelineState,
                     tex: [MTLTexture], _ extra: (() -> Void)? = nil) {
        enc.setComputePipelineState(pso)
        for (i, texture) in tex.enumerated() { enc.setTexture(texture, index: i) }
        extra?()
        dispatch(enc)
        enc.memoryBarrier(scope: .textures)
    }

    public func render(encoder: MTLRenderCommandEncoder, features: FeatureVector) {
        guard let pso = renderPSO else { return }
        var cfgLocal = cfg
        encoder.setRenderPipelineState(pso)
        encoder.setFragmentTexture(dye[dcur], index: 0)
        encoder.setFragmentBytes(&cfgLocal, length: MemoryLayout<RicercarFluidConfig>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    }

    // MARK: - FL.2 procedural splats (no audio — judge the LOOK against ref 02)

    /// A few gentle blooming section-sources in family colours, drifting slowly, each puffing
    /// upward-ish so the dye rolls and merges like the ink in ref 02.
    private func proceduralSplats(time seconds: Float) -> [FluidSplat] {
        // strings violet, brass gold, woodwinds russet, percussion teal
        let colors: [SIMD3<Float>] = [
            SIMD3(0.34, 0.24, 0.64), SIMD3(0.88, 0.62, 0.16),
            SIMD3(0.76, 0.38, 0.18), SIMD3(0.13, 0.60, 0.66)
        ]
        var out: [FluidSplat] = []
        for i in 0..<colors.count {
            let phase = Float(i) * 1.7
            // slow horizontal drift across the lower field; each source pulses in/out over ~6 s
            let x = 0.2 + 0.6 * (0.5 + 0.5 * sin(seconds * 0.11 + phase))
            let y = 0.30 + 0.12 * sin(seconds * 0.17 + phase * 1.3)
            let pulse = max(0.0, sin(seconds * 0.5 + phase))          // gated blooms, not constant
            if pulse < 0.15 { continue }
            // Velocities are TEXELS/FRAME — a gentle buoyant rise (~2.5 tx/frame) that vorticity rolls
            // into billows. (The first pass used ~34 → advection sampled 19% of the frame away and wiped
            // the dye every frame — the blank-canvas bug.)
            let up = SIMD2<Float>(1.0 * sin(seconds * 0.3 + phase), -2.5)
            let color = colors[i] * (0.8 * pulse)
            out.append(FluidSplat(posVel: SIMD4(x, y, up.x, up.y),
                                  colorRad: SIMD4(color.x, color.y, color.z, 0.06)))
        }
        return out
    }
}
