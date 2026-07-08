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

/// Mirror of MSL `FluidConfig`. 2×uint + 8×float = 40 bytes, align 4.
struct RicercarFluidConfig {
    var width: UInt32
    var height: UInt32
    var dt: Float
    var velocityDissipation: Float
    var dyeDissipation: Float
    var vorticity: Float
    var pressure: Float
    var exposure: Float
    var time: Float
    var ribbonBrightness: Float
}

/// Mirror of MSL `FluidSplat` — two float4 for a guaranteed layout match (no float3 alignment trap).
struct FluidSplat {
    var posVel: SIMD4<Float>    // pos.xy, vel.xy
    var colorRad: SIMD4<Float>  // color.rgb, radius
}

// MARK: - RicercarFluidGeometry

public final class RicercarFluidGeometry: ParticleGeometry, @unchecked Sendable {

    public var activeParticleFraction: Float = 1.0   // a fluid field is fully coupled; governor unused

    /// Ribbon-overlay gain (ref 01). 1 = full glowing ribbons; 0 = masses-only (used by the
    /// contact-sheet test to render the ref-02 comparison without the ref-01 layer).
    public var ribbonBrightness: Float = 1.0

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
        width: Int = 480,
        height: Int = 270,
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
            vorticity: 0.8,                 // confinement rolls the plumes into billows (ref-02 tell);
                                            // 0.4 left them as smooth teardrops — raised with the render
                                            // checked for the dye-tearing failure the FL.2 note warns of
            pressure: 0.8,
            exposure: 1.2,
            time: 0,
            ribbonBrightness: 1.0)

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
        cfg.time = time
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
        cfgLocal.ribbonBrightness = ribbonBrightness
        encoder.setRenderPipelineState(pso)
        encoder.setFragmentTexture(dye[dcur], index: 0)
        encoder.setFragmentBytes(&cfgLocal, length: MemoryLayout<RicercarFluidConfig>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    }

    // MARK: - FL.3 procedural splats (no audio — judge the LOOK against ref 02)

    /// Six section-sources spread across the top of the frame, billowing DOWNWARD like the ref-02
    /// ink drop (docs/VISUAL_REFERENCES/ricercar/02: dense side-by-side hues hanging from the top,
    /// bleeding wet-into-wet). FL.2's version rose from mid-frame and pulse-gated OFF, so only 1–2
    /// wispy columns showed at a time; ref 02 shows all hues simultaneously — the pulses now overlap
    /// (a breathing floor, never fully off) and adjacent sources sit close enough to merge.
    private func proceduralSplats(time seconds: Float) -> [FluidSplat] {
        // family palette (strings violet, brass gold, woodwinds russet, percussion teal), warm→cool
        // across the width like ref 02; violet + gold doubled for six plumes.
        let violet = SIMD3<Float>(0.34, 0.24, 0.64), gold = SIMD3<Float>(0.88, 0.62, 0.16)
        let russet = SIMD3<Float>(0.76, 0.38, 0.18), teal = SIMD3<Float>(0.13, 0.60, 0.66)
        let colors: [SIMD3<Float>] = [russet, gold, violet, gold, violet, teal]
        let xs: [Float] = [0.12, 0.27, 0.42, 0.57, 0.72, 0.88]
        var out: [FluidSplat] = []
        for i in 0..<colors.count {
            let phase = Float(i) * 1.9
            let x = xs[i] + 0.04 * sin(seconds * 0.13 + phase)         // slow sway, sources stay banded
            let y = 0.08 + 0.03 * sin(seconds * 0.21 + phase * 1.3)    // sim y=0 is screen TOP
            // Overlapping breath: never off (floor 0.35), surging blooms staggered per source.
            let pulse = 0.35 + 0.65 * max(0.0, sin(seconds * (0.35 + 0.04 * Float(i)) + phase))
            // Velocities are TEXELS/FRAME (~1–3; the FL.2 blank-canvas lesson). +y = down-screen:
            // the plumes sink into the frame; an alternating outward lean makes neighbours bloom into
            // each other (wet-into-wet merging) instead of falling as parallel fingers.
            let lean: Float = (i % 2 == 0 ? 0.7 : -0.7)
            let vel = SIMD2<Float>(lean + 0.6 * sin(seconds * 0.3 + phase), 2.2)
            let color = colors[i] * (1.1 * pulse)
            out.append(FluidSplat(posVel: SIMD4(x, y, vel.x, vel.y),
                                  colorRad: SIMD4(color.x, color.y, color.z, 0.085)))
        }
        return out
    }
}
