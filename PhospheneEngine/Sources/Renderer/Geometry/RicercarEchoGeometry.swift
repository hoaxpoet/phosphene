// RicercarEchoGeometry.swift — Fantasia-fugue PROTOTYPE (design-aligned with Matt, 2026-07-09).
//
// Proves one thing before we build the whole preset: does a clear GESTURE that visibly ANSWERS ITSELF read
// as a fugue and stay locked to the music? A fugue = repetition with variation. So: an onset in the music
// spawns a SUBJECT gesture (a pen traces a recognisable curve over ~0.5 s — the drawing IS the movement);
// then ECHOES follow — the SAME stroke returns, transformed by a small fugue grammar (answer higher / invert
// / augment / diminish) and recoloured to another voice, marching across the field. On a swell the answers
// come faster and pile up (stretto); at rest they thin out. Recognition is a feature, not a whisper.
//
// Uncoupled prototype: NOT a selectable preset (no registry/app wiring) — driven by RicercarEchoRenderTests
// so we can judge the FEEL, then decide. Reuses the FL.10 glowing-trail-over-dark substrate (RicercarEcho.metal).

import Metal
import simd
import Shared

// MARK: - GPU-mirrored structs (layouts match RicercarEcho.metal exactly)

/// Mirror of MSL `EchoConfig` — 3 uint + 5 float, all 4-byte, no padding.
struct RicercarEchoConfig {
    var width: UInt32
    var height: UInt32
    var penCount: UInt32
    var decay: Float
    var exposure: Float
    var aspect: Float
    var groundBlend: Float
    var pad0: Float
}

/// Mirror of MSL `EchoPen` — two float4 (32 bytes).
struct EchoPen {
    var posSize: SIMD4<Float>   // pos.xy, size, brightness(0 = inactive)
    var color: SIMD4<Float>     // rgb, a unused
}

// MARK: - Configuration

public struct RicercarEchoConfiguration: Sendable {
    public var width: Int
    public var height: Int
    /// Max concurrent gestures (subject + its live echoes across all recent onsets).
    public var maxGestures: Int
    public init(width: Int = 1280, height: Int = 720, maxGestures: Int = 96) {
        self.width = width; self.height = height; self.maxGestures = maxGestures
    }
}

// MARK: - RicercarEchoGeometry

public final class RicercarEchoGeometry: ParticleGeometry, @unchecked Sendable {

    public var activeParticleFraction: Float = 1.0
    public let configuration: RicercarEchoConfiguration

    private let penBuffer: MTLBuffer
    private let trail: [MTLTexture]
    private var cur = 0
    private let depositPSO: MTLRenderPipelineState?
    private let decayPSO: MTLRenderPipelineState?
    private let displayPSO: MTLRenderPipelineState?

    // The four voice hues (strings violet / brass gold / woodwinds amber / percussion cyan — same palette).
    private static let voiceHue: [SIMD3<Float>] = [
        SIMD3(0.55, 0.45, 1.00), SIMD3(1.00, 0.78, 0.30),
        SIMD3(1.00, 0.52, 0.26), SIMD3(0.35, 0.95, 1.00)]

    // MARK: Gesture model (CPU)

    /// Sub-samples deposited PER gesture PER frame — traces the arc drawn since last frame so the stroke is
    /// continuous (one point/frame left a dotted line). penBuffer holds maxGestures × subSteps points.
    private static let subSteps = 6

    private struct Gesture {
        var active = false
        var phase: Float = 0          // 0→1 draw progress
        var prevPhase: Float = 0      // phase last frame (sub-step interpolation start)
        var drawDuration: Float = 0.5 // seconds
        var origin = SIMD2<Float>(0, 0)
        var scale: Float = 1
        var flipY: Float = 1
        var rot: Float = 0
        var colorIndex = 0
        var strength: Float = 1
        var markKind = 0   // 0 = legato STROKE (flowing line), 1 = staccato DAB (short tick), 2 = pizz DOT (pluck)
    }
    private var gestures: [Gesture]
    private var nextSlot = 0

    // Echo scheduling: pending answers to fire at future times (the fugue subject re-entering).
    private struct Pending { var atTime: Float; var seed: Gesture; var index: Int }
    private var pending: [Pending] = []

    // Music envelopes.
    private var energyEnv: Float = 0        // smoothed energy (density / stretto driver)
    private var energyFast: Float = 0       // fast energy for onset edges
    private var refractory: Float = 0       // s until next subject allowed
    private var time: Float = 0
    private var rng: UInt64 = 0x2545F4914F6CDD1D

    public enum EchoError: Error { case bufferAllocationFailed, textureAllocationFailed, functionNotFound(String) }

    public init(device: MTLDevice, library: MTLLibrary,
                configuration: RicercarEchoConfiguration = .init(), pixelFormat: MTLPixelFormat? = nil) throws {
        self.configuration = configuration
        self.gestures = Array(repeating: Gesture(), count: configuration.maxGestures)

        let penSlots = configuration.maxGestures * Self.subSteps
        guard let buf = device.makeBuffer(length: penSlots * MemoryLayout<EchoPen>.stride,
                                          options: .storageModeShared) else { throw EchoError.bufferAllocationFailed }
        self.penBuffer = buf

        let td = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float, width: configuration.width, height: configuration.height, mipmapped: false)
        td.usage = [.shaderRead, .renderTarget]; td.storageMode = .private
        var texs: [MTLTexture] = []
        for _ in 0..<2 {
            guard let tex = device.makeTexture(descriptor: td) else { throw EchoError.textureAllocationFailed }
            texs.append(tex)
        }
        self.trail = texs

        func fn(_ name: String) throws -> MTLFunction {
            guard let fun = library.makeFunction(name: name) else { throw EchoError.functionNotFound(name) }
            return fun
        }
        let fmt: MTLPixelFormat = .rgba16Float
        let dec = MTLRenderPipelineDescriptor()
        dec.vertexFunction = try fn("fullscreen_vertex")
        dec.fragmentFunction = try fn("ricercar_echo_decay_fragment")
        dec.colorAttachments[0].pixelFormat = fmt
        self.decayPSO = try device.makeRenderPipelineState(descriptor: dec)

        let dep = MTLRenderPipelineDescriptor()
        dep.vertexFunction = try fn("ricercar_echo_point_vertex")
        dep.fragmentFunction = try fn("ricercar_echo_point_fragment")
        dep.colorAttachments[0].pixelFormat = fmt
        dep.colorAttachments[0].isBlendingEnabled = true
        dep.colorAttachments[0].rgbBlendOperation = .add
        dep.colorAttachments[0].alphaBlendOperation = .add
        dep.colorAttachments[0].sourceRGBBlendFactor = .one
        dep.colorAttachments[0].destinationRGBBlendFactor = .one
        dep.colorAttachments[0].sourceAlphaBlendFactor = .one
        dep.colorAttachments[0].destinationAlphaBlendFactor = .one
        self.depositPSO = try device.makeRenderPipelineState(descriptor: dep)

        if let pixelFormat {
            let dsp = MTLRenderPipelineDescriptor()
            dsp.vertexFunction = try fn("fullscreen_vertex")
            dsp.fragmentFunction = try fn("ricercar_echo_display_fragment")
            dsp.colorAttachments[0].pixelFormat = pixelFormat
            self.displayPSO = try device.makeRenderPipelineState(descriptor: dsp)
        } else { self.displayPSO = nil }

        Self.clear(trail: texs, device: device)
    }

    private static func clear(trail: [MTLTexture], device: MTLDevice) {
        guard let queue = device.makeCommandQueue(), let cmd = queue.makeCommandBuffer() else { return }
        for tex in trail {
            let rpd = MTLRenderPassDescriptor()
            rpd.colorAttachments[0].texture = tex
            rpd.colorAttachments[0].loadAction = .clear
            rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
            rpd.colorAttachments[0].storeAction = .store
            cmd.makeRenderCommandEncoder(descriptor: rpd)?.endEncoding()
        }
        cmd.commit(); cmd.waitUntilCompleted()
    }

    // MARK: Test hooks
    public var currentEnergyEnv: Float { energyEnv }
    public func activeGestureCount() -> Int { gestures.reduce(0) { $0 + ($1.active ? 1 : 0) } }

    private func rand() -> Float {
        rng = rng &* 6364136223846793005 &+ 1442695040888963407
        return Float((rng >> 33) & 0xFFFFFF) / Float(0xFFFFFF)
    }

    // MARK: The subject curve (a recognisable leaning flourish, local space centred on origin)
    private static func subject(_ tt: Float) -> SIMD2<Float> {
        let x = (tt - 0.5) * 0.34
        let y = (0.20 * sinf(tt * .pi * 1.15) - 0.06 * tt)   // arch that leans + a slight tail-drop
        return SIMD2(x, y)
    }

    // MARK: - ParticleGeometry

    public func update(features: FeatureVector, stemFeatures: StemFeatures, commandBuffer: MTLCommandBuffer) {
        advance(features: features)
        writePens()

        guard let decayPSO, let depositPSO else { return }
        var cfg = makeConfig()
        let dst = trail[1 - cur], src = trail[cur]
        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = dst
        rpd.colorAttachments[0].loadAction = .clear
        rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        rpd.colorAttachments[0].storeAction = .store
        if let enc = commandBuffer.makeRenderCommandEncoder(descriptor: rpd) {
            enc.setRenderPipelineState(decayPSO)
            enc.setFragmentBytes(&cfg, length: MemoryLayout<RicercarEchoConfig>.stride, index: 0)
            enc.setFragmentTexture(src, index: 0)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)

            enc.setRenderPipelineState(depositPSO)
            enc.setVertexBuffer(penBuffer, offset: 0, index: 0)
            enc.setVertexBytes(&cfg, length: MemoryLayout<RicercarEchoConfig>.stride, index: 1)
            enc.drawPrimitives(type: .point, vertexStart: 0, vertexCount: configuration.maxGestures * Self.subSteps)
            enc.endEncoding()
        }
        cur = 1 - cur
    }

    public func render(encoder: MTLRenderCommandEncoder, features: FeatureVector) {
        guard let displayPSO else { return }
        var cfg = makeConfig()
        encoder.setRenderPipelineState(displayPSO)
        encoder.setFragmentBytes(&cfg, length: MemoryLayout<RicercarEchoConfig>.stride, index: 0)
        encoder.setFragmentTexture(trail[cur], index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    }

    // MARK: - Music → gestures

    private func advance(features feat: FeatureVector) {
        var dt = feat.deltaTime; if !(dt > 0) { dt = 1.0 / 60.0 }; dt = min(dt, 1.0 / 30.0)
        time += dt
        refractory = max(0, refractory - dt)

        // Energy: soft-saturated band-dev sum. Fast copy for onset edges, slow env for density/stretto.
        let raw = 1.0 - expf(-(max(0, feat.bassDev) + max(0, feat.midDev) + max(0, feat.trebDev)) / 0.5)
        energyFast += Float(dt / (0.04 + dt)) * (raw - energyFast)
        energyEnv += Float(dt / (0.35 + dt)) * (raw - energyEnv)

        // Onset = a fast rise clearly above the slow envelope → a SUBJECT enters (gated by a refractory).
        if refractory <= 0 && energyFast - energyEnv > 0.10 && energyFast > 0.18 {
            // ARTICULATION sharpness (0 legato … 1 pizz) of THIS note, read ONLY at the onset (never in silence).
            // Per-NOTE cues (not "how busy the passage is" — that conflates fast-legato with staccato):
            //  • a sharper/bigger energy jump = a more percussive attack;
            //  • more treble share = a brighter, more transient attack (pizz/staccato are transient-rich).
            let total = max(0.05, max(0, feat.bassDev) + max(0, feat.midDev) + max(0, feat.trebDev))
            let treble = max(0, feat.trebDev) / total
            let sharp = min(1, (energyFast - energyEnv) * 1.7 + treble * 0.75)
            spawnSubject(strength: min(1, 0.4 + energyFast), sharp: sharp)
            refractory = 0.12   // low → staccato runs fire rapid marks (a held note needs a fresh rise to re-trigger)
        }

        // Fire scheduled echoes whose time has come.
        var idx = 0
        while idx < pending.count {
            if time >= pending[idx].atTime { launch(pending[idx].seed); pending.remove(at: idx) } else { idx += 1 }
        }

        // Advance the pens (remember last phase for the sub-step interpolation → continuous strokes).
        for gi in gestures.indices where gestures[gi].active {
            gestures[gi].prevPhase = gestures[gi].phase
            gestures[gi].phase += Float(dt) / max(0.05, gestures[gi].drawDuration)
            if gestures[gi].phase >= 1 { gestures[gi].active = false }
        }
    }

    /// A subject enters, its MARK FORM chosen by articulation, then schedules its answers (same form).
    private func spawnSubject(strength: Float, sharp: Float) {
        var sub = Gesture()
        sub.origin = SIMD2(0.16 + rand() * 0.14, 0.30 + rand() * 0.40)
        sub.flipY = 1; sub.rot = (rand() - 0.5) * 0.3
        sub.colorIndex = Int(rand() * 4) & 3
        sub.strength = strength
        // Articulation → the shape of the mark (the thing you SEE differ): flowing stroke ↔ short dash ↔ pluck dot.
        if sharp > 0.74 { sub.markKind = 2; sub.scale = 0.28; sub.drawDuration = 0.12 }       // pizz — a pluck dot
        else if sharp > 0.34 { sub.markKind = 1; sub.scale = 0.5; sub.drawDuration = 0.17 }   // staccato — a short dash
        else { sub.markKind = 0; sub.scale = 1.0; sub.drawDuration = 0.52 }                   // legato — flowing stroke
        launch(sub)

        let answers = 2 + Int(energyEnv * 4.0)               // more voices pile on when louder (stretto)
        let gap = 0.42 - 0.18 * min(1, energyEnv)            // and they answer faster
        for k in 1...answers {
            var ans = sub                                    // the answer keeps the subject's MARK FORM
            // Fugue grammar, cycling: answer / invert / augment / diminish (scale-changes only for strokes).
            switch k % 4 {
            case 1: ans.rot += 0.15                                                            // answer (slight tilt)
            case 2: ans.flipY = -sub.flipY                                                     // inversion
            case 3: if sub.markKind == 0 { ans.scale = sub.scale * 1.4; ans.drawDuration = 0.72 }  // augmentation
            default: if sub.markKind == 0 { ans.scale = sub.scale * 0.7; ans.drawDuration = 0.34 } // diminution
            }
            ans.origin = sub.origin + SIMD2(0.12, 0.10) * Float(k)        // march up-and-right (answer higher)
            ans.origin.x = min(0.9, ans.origin.x); ans.origin.y = min(0.92, ans.origin.y)
            ans.colorIndex = (sub.colorIndex + k) & 3   // next-voice colour (placeholder; real instrument hue = live)
            ans.strength = sub.strength * (1.0 - 0.06 * Float(k))
            pending.append(Pending(atTime: time + gap * Float(k), seed: ans, index: k))
        }
    }

    private func launch(_ seed: Gesture) {
        var ges = seed; ges.active = true; ges.phase = 0; ges.prevPhase = 0
        gestures[nextSlot] = ges
        nextSlot = (nextSlot + 1) % configuration.maxGestures
    }

    /// Trace each active gesture's transformed curve from prevPhase→phase as `subSteps` glow points → the pen
    /// buffer. Sub-stepping fills the between-frames gap so the stroke reads as a continuous bold line.
    private func writePens() {
        let sub = Self.subSteps
        let ptr = penBuffer.contents().bindMemory(to: EchoPen.self, capacity: configuration.maxGestures * sub)
        for idx in gestures.indices {
            let ges = gestures[idx]
            let base = idx * sub
            if !ges.active {
                for ss in 0..<sub { ptr[base + ss] = EchoPen(posSize: .zero, color: .zero) }
                continue
            }
            let hue = Self.voiceHue[ges.colorIndex]
            let cs = cosf(ges.rot), sn = sinf(ges.rot)
            for ss in 0..<sub {
                let frac = sub > 1 ? Float(ss) / Float(sub - 1) : 1
                let ph = ges.prevPhase + (ges.phase - ges.prevPhase) * frac
                let world: SIMD2<Float>
                let sz: Float
                if ges.markKind == 2 {                        // PIZZ DOT — a pluck at one spot, no tracing
                    world = ges.origin
                    sz = 17
                } else if ges.markKind == 1 {                 // STACCATO DASH — a short straight bowed tick
                    let along = (ph - 0.5) * 0.10             // a short line along the rotation axis
                    world = ges.origin + SIMD2(cs, sn) * along
                    sz = 12
                } else {                                       // LEGATO STROKE — trace the flowing curve
                    var loc = Self.subject(ph)
                    loc.y *= ges.flipY
                    world = ges.origin + SIMD2(loc.x * cs - loc.y * sn, loc.x * sn + loc.y * cs) * ges.scale
                    sz = 14 * ges.scale
                }
                // Soft attack/release along the draw; a dot/dab pops sharper (its whole life is short anyway).
                let env = min(1, ph * 6) * min(1, (1 - ph) * 6)
                ptr[base + ss] = EchoPen(
                    posSize: SIMD4(world.x, world.y, sz, ges.strength * (0.6 + 0.4 * env)),
                    color: SIMD4(hue.x, hue.y, hue.z, 0))
            }
        }
    }

    private func makeConfig() -> RicercarEchoConfig {
        RicercarEchoConfig(
            width: UInt32(configuration.width),
            height: UInt32(configuration.height),
            penCount: UInt32(configuration.maxGestures * Self.subSteps),
            decay: 0.972,          // hold the drawn stroke through its draw + a fading memory (the weave)
            exposure: 1.35,
            aspect: Float(configuration.width) / Float(configuration.height),
            groundBlend: 0,
            pad0: 0)
    }
}
