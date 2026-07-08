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
    var ribbonBrightness: Float   // FL.9: soft-wash gain for the demoted fluid dye
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

    // FL.9 (option B) — drawn voices. Each voice is a scrolling contour: a history of (height,
    // brightness) whose newest sample (right edge) is set from THIS frame's audio, scrolling left into
    // the past. Handed to the display fragment at buffer(1) as kVoices runs of [height(N), brightness(N)].
    static let voiceCount = 4
    static let strokeN = 96
    static let voiceBase: [Float] = [0.68, 0.50, 0.58, 0.34]  // rest height (top-down): strings/wood/brass/perc
    private var strokeData = [Float](repeating: 0, count: voiceCount * strokeN * 2)

    /// The dye texture currently holding the field — exposed for render tests to read back.
    public var currentDyeTexture: MTLTexture { dye[dcur] }

    /// The newest (right-edge) height of each drawn voice after the last `update` — strings, woodwinds,
    /// brass, percussion. Exposed so a test can assert the voices MOVE with the audio (position sync).
    public var voiceHeadHeightsForTest: SIMD4<Float> {
        let pts = Self.strokeN
        func head(_ voice: Int) -> Float { strokeData[voice * pts * 2 + pts - 1] }
        return SIMD4(head(0), head(1), head(2), head(3))
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
        initStrokes()
    }

    /// Seed each voice's contour history at its rest height, dim — the canvas starts empty (silence rests).
    private func initStrokes() {
        let pts = Self.strokeN
        for voice in 0..<Self.voiceCount {
            let base = voice * pts * 2
            for i in 0..<pts { strokeData[base + i] = Self.voiceBase[voice]; strokeData[base + pts + i] = 0.05 }
        }
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
        updateVoices(features: features, stems: stemFeatures)       // FL.9: draw the voice contours (option B)
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
        cfgLocal.ribbonBrightness = ribbonBrightness       // wash gain (test knob)
        var strokes = strokeData                           // the drawn voices (buffer 1)
        encoder.setRenderPipelineState(pso)
        encoder.setFragmentTexture(dye[dcur], index: 0)
        encoder.setFragmentBytes(&cfgLocal, length: MemoryLayout<RicercarFluidConfig>.stride, index: 0)
        encoder.setFragmentBytes(&strokes, length: MemoryLayout<Float>.stride * strokes.count, index: 1)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    }

    // MARK: - FL.8/FL.9 — the music paints (Fantasia principle)
    //
    // "Art appears and moves in time with the music" (Matt, Bach T&F segment). NOTHING is autonomous.
    // FL.9 (option B): the drawn VOICES (updateVoices) are the subject — lines drawn in time whose height
    // tracks this-frame audio (zero lag). The fluid blooms (summonForms) are demoted to a soft wash.
    // MOVE = zero-lag band devs + beats (felt sync); FEEL = instrument family → colour (lag-tolerant).

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

    /// FL.9 (option B) — advance the drawn voices. Each voice appends a new head sample from THIS frame's
    /// audio (zero accumulation lag) and scrolls its history left. HEIGHT tracks the voice's zero-lag
    /// register energy → the line MOVES with the music (rises on energy); BRIGHTNESS tracks the family
    /// activity (identity) with a band fallback so non-orchestral tracks still draw. Silence → the new
    /// samples are dim and rest at base height, so the visible line fades away (the canvas rests).
    private func updateVoices(features feat: FeatureVector, stems stem: StemFeatures) {
        let fam = familyActivations(stem)                        // strings, woodwinds, brass, percussion
        let band: [Float] = [max(0, feat.bassDev), max(0, feat.midDev),
                             max(0, feat.midDev), max(0, feat.trebDev)]   // voice → register band
        let pts = Self.strokeN
        for voice in 0..<Self.voiceCount {
            let energy = softSat(band[voice], 0.5)               // zero-lag → position tracks the music
            let height = Self.voiceBase[voice] - 0.20 * energy   // rises (up) with its band energy
            let bright = 0.05 + 0.95 * max(fam[voice], energy)   // bright where the voice sings
            let base = voice * pts * 2
            for i in 0..<(pts - 1) {                             // scroll left, newest enters at the right
                strokeData[base + i] = strokeData[base + i + 1]
                strokeData[base + pts + i] = strokeData[base + pts + i + 1]
            }
            strokeData[base + pts - 1] = height
            strokeData[base + 2 * pts - 1] = bright
        }
    }

    /// SUMMON the background wash's fluid forms from the current musical moment (blooms per active band,
    /// spread bass→treble across the frame; a beat spray). Returns [] at silence so the field rests.
    private func summonForms(features feat: FeatureVector, stems stem: StemFeatures) -> [FluidSplat] {
        let bass = max(0, feat.bassDev), mid = max(0, feat.midDev), treb = max(0, feat.trebDev)
        let beat = max(0, feat.beatComposite)
        let energy = bass + mid + treb
        defer { prevBeat = beat }
        guard energy > 0.02 || beat > 0.05 else { return [] }   // silence rests
        let fam = familyActivations(stem), fh = Self.familyHue
        bloomPhase += energy * 0.015
        var out: [FluidSplat] = []
        appendBloom(&out, band: bass, xBand: 0.24, phase: bloomPhase, hue: bloomHue(fam, fallback: fh[0]))
        appendBloom(&out, band: mid, xBand: 0.50, phase: bloomPhase + 2.1, hue: bloomHue(fam, fallback: fh[2]))
        appendBloom(&out, band: treb, xBand: 0.76, phase: bloomPhase + 4.2, hue: bloomHue(fam, fallback: fh[3]))
        if beat > 0.22 && beat > prevBeat + 0.04 {              // beat → spray ("falling stars")
            appendSpray(&out, strength: beat, hue: bloomHue(fam, fallback: fh[3]))
        }
        return out
    }

    /// A soft bloom centred on its register's frame-band `xBand`, only while its band sings; large radius
    /// + gentle lateral drift so it billows rather than streaks (low vorticity does the rest).
    private func appendBloom(_ out: inout [FluidSplat], band: Float, xBand: Float, phase: Float,
                             hue: SIMD3<Float>) {
        let level = softSat(band, 0.55)
        guard level > 0.04 else { return }
        let posX = xBand + 0.10 * sin(phase)
        let posY = 0.5 + 0.14 * sin(phase * 0.7)
        let velX = 0.9 * sin(phase * 1.3)
        let velY = -0.5 + 0.4 * sin(phase * 0.9)
        let color = hue * (1.3 * level)
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
