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

/// Mirror of MSL `FluidConfig`. All 4-byte-aligned scalars (no float4 → no alignment trap). 18×float
/// + 2×uint = 80 bytes, align 4. Ribbon order: 0 strings, 1 woodwinds, 2 brass, 3 percussion.
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
    var rbLevel0: Float, rbLevel1: Float, rbLevel2: Float, rbLevel3: Float
    var rbUndulate0: Float, rbUndulate1: Float, rbUndulate2: Float, rbUndulate3: Float
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
    private var prevBeat: Float = 0     // FL.8 beat rising-edge detection (spray trigger)
    private var bloomPhase: Float = 0   // FL.8 slow wander so summoned blooms don't pin to fixed columns

    /// The dye texture currently holding the field — exposed for render tests to read back.
    public var currentDyeTexture: MTLTexture { dye[dcur] }

    /// Per-ribbon brightness after the last `update` (FL.4 audio drive) — strings, woodwinds, brass,
    /// percussion. Exposed so a test can assert the family→ribbon routing without pixel-diffing.
    public var ribbonLevelsForTest: SIMD4<Float> {
        SIMD4(cfg.rbLevel0, cfg.rbLevel1, cfg.rbLevel2, cfg.rbLevel3)
    }

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
            dyeDissipation: 0.022,          // gentle fade → soft edges + the field breathes back to rest
            vorticity: 0.15,                // FL.8: LOW confinement — high vorticity (0.8) combed the dye
                                            // into spiky radial filaments (hairy-ball look); ref 02's ink
                                            // is soft, so let diffusion/advection dominate, not curl
            pressure: 0.8,
            exposure: 1.2,
            time: 0,
            ribbonBrightness: 1.0,
            rbLevel0: 1,
            rbLevel1: 1,
            rbLevel2: 1,
            rbLevel3: 1,
            rbUndulate0: 1,
            rbUndulate1: 1,
            rbUndulate2: 1,
            rbUndulate3: 1)

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
        applyRibbonDrive(features: features, stems: stemFeatures)   // FL.8: family→brightness, silence rests
        var cfgLocal = cfg

        // FL.8 — the music paints: forms are SUMMONED by musical events, none autonomous. Silence
        // returns [] and the field dissipates to the warm ground (rests).
        var splats = summonForms(features: features, stems: stemFeatures)
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

    // MARK: - FL.8 — the music paints (Fantasia principle)
    //
    // Fantasia (Bach T&F segment, Matt 2026-07-08): "art appears and moves in time with the music."
    // NOTHING is autonomous — the canvas rests until a musical event SUMMONS a form whose motion IS the
    // music's. This inverts FL.2–FL.4 (a self-animating texture with audio sprinkled on top).
    //   APPEAR — blooms on register energy, sprays on beats; MOVE — zero-lag band devs + beats (felt sync,
    //   Audio Data Hierarchy); FEEL — instrument family → colour (lag-tolerant). One primitive per layer
    //   (FA #67): each register band drives its own bloom; beats drive sprays.

    /// Family palette — strings violet, woodwinds russet, brass gold, percussion teal (allCases order).
    private static let familyHue: [SIMD3<Float>] = [
        SIMD3(0.42, 0.28, 0.86), SIMD3(0.90, 0.46, 0.22),
        SIMD3(0.98, 0.72, 0.20), SIMD3(0.16, 0.78, 0.82)
    ]
    /// Per-family soft-saturation working points (IFC.6 dumper corpus): strings, woodwinds, brass, perc.
    private static let familySaturation = SIMD4<Float>(0.30, 0.35, 0.85, 0.20)

    /// soft-saturate a deviation vs its working point → 0…~1 (1 − e^(−x/sat)).
    private func softSat(_ dev: Float, _ sat: Float) -> Float { 1.0 - exp(-max(0, dev) / max(sat, 1e-4)) }

    /// The four family soft-sat activations (strings, woodwinds, brass, percussion).
    private func familyActivations(_ stem: StemFeatures) -> SIMD4<Float> {
        let sat = Self.familySaturation
        return SIMD4(
            softSat(stem.stringsActivityDev, sat.x),
            softSat(stem.woodwindsActivityDev, sat.y),
            softSat(stem.brassActivityDev, sat.z),
            softSat(stem.percussionActivityDev, sat.w))
    }

    /// Colour for a register bloom: the dominant instrument family's hue when the family capture is
    /// present (orchestral tracks — identity), else a fixed register hue so non-orchestral tracks still
    /// paint (low→violet, mid→gold, high→teal). `bias` nudges the fallback across the registers.
    private func bloomHue(_ fam: SIMD4<Float>, fallback: SIMD3<Float>) -> SIMD3<Float> {
        let maxFam = max(fam.x, max(fam.y, max(fam.z, fam.w)))
        guard maxFam > 0.12 else { return fallback }
        let idx = (0..<4).max(by: { fam[$0] < fam[$1] }) ?? 0
        return Self.familyHue[idx]
    }

    /// FL.8 ribbon drive — a ribbon is a music-drawn voice: dark at rest, brightening only while its
    /// family sounds (identity, lag-tolerant), undulating with its register's zero-lag energy (motion).
    /// Silence → all ribbons rest near-invisible (the canvas is empty until the music draws it).
    private func applyRibbonDrive(features feat: FeatureVector, stems stem: StemFeatures) {
        let fam = familyActivations(stem)
        // 0.06 rest floor (barely-there thread), family surges it to full — no bright resting ribbons.
        cfg.rbLevel0 = 0.06 + 0.94 * fam.x      // strings  → violet
        cfg.rbLevel1 = 0.06 + 0.94 * fam.y      // woodwinds → russet
        cfg.rbLevel2 = 0.06 + 0.94 * fam.z      // brass    → gold
        cfg.rbLevel3 = 0.06 + 0.94 * fam.w      // percussion → teal
        func und(_ dev: Float) -> Float { min(2.4, 1.0 + 1.5 * max(0, dev)) }
        cfg.rbUndulate0 = und(feat.bassDev)
        cfg.rbUndulate1 = und(feat.midDev)
        cfg.rbUndulate2 = und(feat.midDev)
        cfg.rbUndulate3 = und(feat.trebDev)
    }

    /// FL.8 — SUMMON the fluid forms from the current musical moment. Returns [] at silence so the field
    /// dissipates to the warm ground (rests). No autonomous animation: every splat here is caused by a
    /// live musical signal this frame.
    private func summonForms(features feat: FeatureVector, stems stem: StemFeatures) -> [FluidSplat] {
        let bass = max(0, feat.bassDev), mid = max(0, feat.midDev), treb = max(0, feat.trebDev)
        let beat = max(0, feat.beatComposite)
        let energy = bass + mid + treb
        defer { prevBeat = beat }
        // Silence rests.
        guard energy > 0.02 || beat > 0.05 else { return [] }

        let fam = familyActivations(stem)
        bloomPhase += energy * 0.015            // a slow wander so blooms don't pin to fixed columns
        var out: [FluidSplat] = []

        // BLOOMS — one per active register band, flowering where the energy is. Spread ACROSS the frame
        // by register (bass left → treble right, warm→cool like ref 02's side-by-side hues), wandering
        // locally; GENTLE, mostly-lateral velocity so vorticity rolls them into rounded billows (the FL.2
        // curtains came from a strong constant down-push). Colour = dominant family (identity) or the
        // register's fallback hue.
        let loHue = bloomHue(fam, fallback: Self.familyHue[0])   // low → violet (strings)
        let midHue = bloomHue(fam, fallback: Self.familyHue[2])  // mid → gold (brass)
        let hiHue = bloomHue(fam, fallback: Self.familyHue[3])   // high → teal (percussion)
        appendBloom(&out, band: bass, xBand: 0.24, phase: bloomPhase, hue: loHue)
        appendBloom(&out, band: mid, xBand: 0.50, phase: bloomPhase + 2.1, hue: midHue)
        appendBloom(&out, band: treb, xBand: 0.76, phase: bloomPhase + 4.2, hue: hiHue)

        // SPRAY — a beat rising edge scatters bright flecks that shoot outward ("sprays of falling
        // stars"). Percussion-teal by default; fast small splats, so they read as a burst, not a mass.
        if beat > 0.22 && beat > prevBeat + 0.04 {
            appendSpray(&out, strength: beat, hue: bloomHue(fam, fallback: Self.familyHue[3]))
        }
        return out
    }

    /// A soft flowering bloom centred on its register's frame-band `xBand`; injected only while its band
    /// sings; large radius + gentle lateral drift so it billows rather than streaks. Skips a silent band.
    private func appendBloom(_ out: inout [FluidSplat], band: Float, xBand: Float, phase: Float,
                             hue: SIMD3<Float>) {
        let level = softSat(band, 0.55)                     // soft-sat vs a mid band working point
        guard level > 0.04 else { return }
        let posX = xBand + 0.10 * sin(phase)                // wander locally within the register's band
        let posY = 0.5 + 0.14 * sin(phase * 0.7)            // drift around mid-height
        let velX = 0.9 * sin(phase * 1.3)                   // gentle lateral swirl (no strong down-push)
        let velY = -0.5 + 0.4 * sin(phase * 0.9)            // slight buoyant drift; vorticity does the rest
        let color = hue * (1.3 * level)                     // luminous; intensity tracks the band energy
        let posVel = SIMD4<Float>(posX, posY, velX, velY)
        let colorRad = SIMD4<Float>(color.x, color.y, color.z, 0.11)
        out.append(FluidSplat(posVel: posVel, colorRad: colorRad))
    }

    /// A beat spray: a handful of small bright splats radiating from a point, fast so they scatter.
    private func appendSpray(_ out: inout [FluidSplat], strength: Float, hue: SIMD3<Float>) {
        let cx = 0.35 + 0.30 * (0.5 + 0.5 * sin(bloomPhase * 1.7))
        let cy = 0.30 + 0.10 * sin(bloomPhase * 2.3)
        let count = 5
        let color = hue * (1.6 * strength)
        let speed = 2.2 * strength
        for idx in 0..<count {
            let ang = Float(idx) / Float(count) * 2 * Float.pi + bloomPhase
            let posVel = SIMD4<Float>(cx, cy, cos(ang) * speed, sin(ang) * speed)
            let colorRad = SIMD4<Float>(color.x, color.y, color.z, 0.035)
            out.append(FluidSplat(posVel: posVel, colorRad: colorRad))
        }
    }
}
