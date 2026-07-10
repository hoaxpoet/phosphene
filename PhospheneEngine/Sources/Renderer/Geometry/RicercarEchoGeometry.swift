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
    var time: Float
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
        var variant = 0    // which subject curve shape (arch / S / hook) — variety in the drawing
    }
    private var gestures: [Gesture]
    private var nextSlot = 0

    // Echo scheduling: pending answers to fire at future times (the fugue subject re-entering).
    private struct Pending { var atTime: Float; var seed: Gesture; var index: Int }
    private var pending: [Pending] = []

    // Music envelopes.
    private var energyFast: Float = 0       // slow band LEVEL (music presence → strength/brightness)
    private var levFast: Float = 0          // fast band level (attack peak)
    private var levMed: Float = 0           // fast-reset baseline — onset = levFast − levMed (local transient)
    private var levFloor: Float = 0         // level floor (min-tracker) — sits low in staccato gaps, high in legato
    private var flowAccum: Float = 0        // legato-flow emission accumulator (fills sustained notes)
    private var refractory: Float = 0       // s until the next mark may fire (spaces attacks)
    private var famActivity = SIMD4<Float>(repeating: 0)   // per-section presence (strings/brass/woodwinds/perc)
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
    public var currentEnergyEnv: Float { energyFast }
    public func activeGestureCount() -> Int { gestures.reduce(0) { $0 + ($1.active ? 1 : 0) } }
    /// Marks spawned so far, and the `time` (s) each one fired — the sync/density diagnostic (no render needed).
    public private(set) var totalSpawns = 0
    public private(set) var spawnTimes: [Float] = []
    public private(set) var spawnKindCounts = [0, 0, 0]   // [legato stroke, staccato dash, pizz dot]

    private func rand() -> Float {
        rng = rng &* 6364136223846793005 &+ 1442695040888963407
        return Float((rng >> 33) & 0xFFFFFF) / Float(0xFFFFFF)
    }

    // MARK: The subject curve (a recognisable leaning flourish, local space centred on origin)
    private static func subject(_ tt: Float, _ variant: Int) -> SIMD2<Float> {
        switch variant {
        case 1:  return SIMD2((tt - 0.5) * 0.34, 0.15 * sinf(tt * .pi * 2.0))              // an S-curve
        case 2:  return SIMD2((tt - 0.5) * 0.30 + 0.05 * sinf(tt * .pi), 0.22 * (tt - 0.5)) // a rising hook
        default: return SIMD2((tt - 0.5) * 0.34, 0.20 * sinf(tt * .pi * 1.15) - 0.06 * tt)  // a leaning arch
        }
    }

    // MARK: - ParticleGeometry

    public func update(features: FeatureVector, stemFeatures: StemFeatures, commandBuffer: MTLCommandBuffer) {
        advance(features: features, stems: stemFeatures)
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

    private func advance(features feat: FeatureVector, stems stem: StemFeatures) {
        var dt = feat.deltaTime; if !(dt > 0) { dt = 1.0 / 60.0 }; dt = min(dt, 1.0 / 30.0)
        time += dt

        // Which instrument SECTION is most active NOW → the spark's COLOUR (the honest voice). Use the
        // per-family DEVIATION, not the absolute level (families have different natural ranges — FA #31), so
        // the section that's surging relative to ITS norm wins. Flat (rock / warmup) → fallback in spawnSubject.
        famActivity = SIMD4(
            stem.stringsActivityDev,
            stem.brassActivityDev,
            stem.woodwindsActivityDev,
            stem.percussionActivityDev)

        // ONSET = a NOTE ATTACK, detected throughout the piece. The band LEVEL (bass/mid/treble; stays up while
        // music plays) rising above a FAST baseline (levMed, τ0.055 — resets between notes) → each attack is a
        // fresh local transient in the sparse opening AND the sustained sections. (The old detectors used a slow
        // baseline / the deviation primitives, both of which flatten during sustained music → the desync.)
        let level = max(0, feat.bass) + max(0, feat.mid) + max(0, feat.treble)
        levFast += Float(dt / (0.012 + dt)) * (level - levFast)
        levMed += Float(dt / (0.040 + dt)) * (level - levMed)
        energyFast += Float(dt / (0.06 + dt)) * (level - energyFast)   // slow level → strength/brightness
        refractory = max(0, refractory - Float(dt))

        // STACCATO vs LEGATO = does the level DROP between notes (staccato) or SUSTAIN (legato)? Track a level
        // FLOOR (falls instantly with the level, rises slowly): in legato it stays near the level; in staccato/
        // detached playing it sinks toward the gaps. staccatoness = how far the floor sits below the current level.
        if levFast < levFloor { levFloor = levFast } else { levFloor += Float(dt / (0.55 + dt)) * (levFast - levFloor) }
        let staccatoness = 1.0 - min(1, levFloor / max(0.05, levMed))

        // SUSTAIN → LEGATO FLOW: while a note is sounding and sustained (level high, low staccatoness), keep
        // emitting long flowing marks — so a legato note FLOWS the whole time it sounds, not just fires once at
        // the attack (the "opening entry didn't register": its long sustained chord went silent after the hit).
        flowAccum += levFast * (1 - staccatoness) * 14.0 * Float(dt)
        while flowAccum >= 1 {
            flowAccum -= 1
            spawnSubject(strength: min(1, 0.4 + energyFast), sharp: 0.0)       // legato (long flowing line)
        }

        // ONSET → a STACCATO/PIZZ clip on each sharp, DETACHED attack (the level jumped from a gap).
        let onset = (levFast - levMed) / max(0.08, levMed)
        if refractory <= 0 && onset > 0.06 && levFast > 0.045 && staccatoness > 0.45 {
            let devs = max(0, feat.bassDev) + max(0, feat.midDev) + max(0, feat.trebDev)
            let treble = max(0, feat.trebDev) / max(0.05, devs)
            spawnSubject(strength: min(1, 0.5 + energyFast), sharp: 0.55 + treble * 0.4)   // dash or pizz dot
            refractory = 0.05
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

    /// A mark is born from a REAL onset; its MARK FORM is chosen by articulation. NO scheduled echoes.
    private func spawnSubject(strength: Float, sharp: Float) {
        var sub = Gesture()
        sub.origin = SIMD2(0.10 + rand() * 0.80, 0.16 + rand() * 0.68)   // spread across the whole field
        sub.flipY = rand() > 0.5 ? 1 : -1; sub.rot = (rand() - 0.5) * 0.6
        sub.variant = Int(rand() * 3) % 3
        // COLOUR = a section that's actually playing, picked WEIGHTED by each section's activity — so when
        // two sections sound together you get a MIX of their colours (the counterpoint shows), not one hue.
        // Flat capture (rock / warmup) → fall back to a rotating hue so it's never colourless.
        let act = SIMD4(max(0, famActivity.x), max(0, famActivity.y), max(0, famActivity.z), max(0, famActivity.w))
        let total = act.x + act.y + act.z + act.w
        if total > 0.04 {
            var pick = rand() * total; var idx = 3
            for fi in 0..<4 { if pick < act[fi] { idx = fi; break }; pick -= act[fi] }
            sub.colorIndex = idx
        } else {
            sub.colorIndex = Int(rand() * 4) & 3
        }
        sub.strength = strength
        // Articulation → the shape AND DURATION of the mark. Legato must FLOW (a long line drawn slowly →
        // a flowing ribbon), staccato is SHORT + CLIPPED (a quick dab), pizz a pluck dot.
        if sharp > 0.72 { sub.markKind = 2; sub.scale = 0.16; sub.drawDuration = 0.09 }   // pizz — a tiny pluck dot
        else if sharp > 0.45 { sub.markKind = 1; sub.scale = 0.42; sub.drawDuration = 0.12 } // staccato — short clip
        else { sub.markKind = 0; sub.scale = 1.7; sub.drawDuration = 0.90 }               // legato — LONG flowing line
        spawnKindCounts[sub.markKind] += 1
        launch(sub)
        // ECHOES REMOVED (2026-07-10): the scheduled fake echoes fired on a TIMER, so most marks appeared when
        // nothing was happening in the music → "no connection" (r≈0.25 vs FL.10's 0.69). Every mark is now a
        // REAL onset. Recurrence/imitation must come from the music actually repeating + the live instrument
        // voices — not a delay line. `pending` stays empty; the advance() drain is a harmless no-op.
    }

    private func launch(_ seed: Gesture) {
        var ges = seed; ges.active = true; ges.phase = 0; ges.prevPhase = 0
        gestures[nextSlot] = ges
        nextSlot = (nextSlot + 1) % configuration.maxGestures
        totalSpawns += 1; spawnTimes.append(time)
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
                // A brush TAPER along the stroke (thin at the ends, full in the middle) so it reads as a
                // drawn/bowed mark, not a uniform line. Dots don't taper.
                let taper = 0.28 + 0.72 * sinf(ph * .pi)
                if ges.markKind == 2 {                        // PIZZ DOT — a tiny pluck at one spot
                    world = ges.origin
                    sz = 5
                } else if ges.markKind == 1 {                 // STACCATO DASH — a tiny straight bowed tick
                    let along = (ph - 0.5) * 0.055            // a short line along the rotation axis
                    world = ges.origin + SIMD2(cs, sn) * along
                    sz = 6 * taper
                } else {                                       // LEGATO STREAK — a small tapered traced curve
                    var loc = Self.subject(ph, ges.variant)
                    loc.y *= ges.flipY
                    world = ges.origin + SIMD2(loc.x * cs - loc.y * sn, loc.x * sn + loc.y * cs) * ges.scale
                    sz = 8 * taper
                }
                // Soft attack/release along the draw; a dot/dab pops sharper (its whole life is short anyway).
                let env = min(1, ph * 6) * min(1, (1 - ph) * 6)
                ptr[base + ss] = EchoPen(
                    posSize: SIMD4(world.x, world.y, sz, ges.strength * (0.9 + 0.5 * env)),
                    color: SIMD4(hue.x, hue.y, hue.z, 0))
            }
        }
    }

    private func makeConfig() -> RicercarEchoConfig {
        RicercarEchoConfig(
            width: UInt32(configuration.width),
            height: UInt32(configuration.height),
            penCount: UInt32(configuration.maxGestures * Self.subSteps),
            decay: 0.945,          // FAST fade → each spark is transient (pops and vanishes, no smear/lag)
            exposure: 1.25,        // modest — painterly, keep the marks' COLOUR (readable over the ground, not neon)
            aspect: Float(configuration.width) / Float(configuration.height),
            groundBlend: 1.0,      // soft painterly atmospheric ground (recessive, not the subject)
            time: time)
    }
}
