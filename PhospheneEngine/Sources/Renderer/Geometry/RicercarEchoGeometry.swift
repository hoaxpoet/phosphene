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
    /// Pens per gesture. The stroke shader needs it to find segment endpoints within a gesture's
    /// block and, crucially, to avoid connecting the last pen of one gesture to the first of the next.
    var subSteps: UInt32
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

    /// The trail's CURRENT size. `var`, not `let`: it follows the drawable via
    /// ``ensureAllocated(width:height:)``. The initialiser's value is only a starting size —
    /// treat it as a placeholder, never as the resolution the preset renders at.
    public internal(set) var configuration: RicercarEchoConfiguration

    internal let device: MTLDevice
    private let penBuffer: MTLBuffer
    internal var trail: [MTLTexture]
    internal var cur = 0
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
    private var refractory: Float = 0       // s until the next mark may fire (spaces attacks)
    private var famActivity = SIMD4<Float>(repeating: 0)   // per-section presence (strings/brass/woodwinds/perc)
    private var time: Float = 0
    private var rng: UInt64 = 0x2545F4914F6CDD1D

    public enum EchoError: Error { case bufferAllocationFailed, textureAllocationFailed, functionNotFound(String) }

    public init(device: MTLDevice, library: MTLLibrary,
                configuration: RicercarEchoConfiguration = .init(), pixelFormat: MTLPixelFormat? = nil) throws {
        self.configuration = configuration
        self.device = device
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
        dep.vertexFunction = try fn("ricercar_echo_seg_vertex")
        dep.fragmentFunction = try fn("ricercar_echo_seg_fragment")
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
            // RICERCAR-WIRE.3 — one quad per pen-to-pen SEGMENT, not a point sprite per pen.
            // Segments stay inside a gesture's block, so a stroke never joins the next gesture.
            let segments = configuration.maxGestures * (Self.subSteps - 1)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: segments * 6)
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

        // ONSET-ONLY — a mark ONLY on a note attack, nothing on a timer or sustain-rate (Matt: the pure
        // onset version's first 5 s were "perfect"; any sustain-fill puts marks where there are no notes).
        // One mark per attack. Its articulation from staccatoness: detached ⇒ short clip, sustained ⇒ long
        // flowing line — so a sustained note registers via ONE long mark drawn from its attack, not a stream.
        let onset = (levFast - levMed) / max(0.08, levMed)
        if refractory <= 0 && onset > 0.05 && levFast > 0.045 {
            let devs = max(0, feat.bassDev) + max(0, feat.midDev) + max(0, feat.trebDev)
            let treble = max(0, feat.trebDev) / max(0.05, devs)
            spawnSubject(strength: min(1, 0.45 + energyFast), sharp: min(1, staccatoness * 0.9 + treble * 0.25))
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
        // VOICE CHARACTER — colour (section) picks the FORM (drawn in writePens); articulation modulates how far
        // it's drawn: legato = long/flowing, sharp = short/clipped. Each voice keeps its own natural range.
        let legato = 1 - min(1, sharp)
        switch sub.colorIndex {
        case 1:  sub.scale = 0.7 + 0.8 * legato; sub.drawDuration = 0.20 + 0.30 * legato   // brass — blocky slab
        case 2:  sub.scale = 0.7 + 0.6 * legato; sub.drawDuration = 0.28 + 0.34 * legato   // woodwinds — twirl
        case 3:  sub.scale = 1;                  sub.drawDuration = 0.10                     // percussion — spark
        default: sub.scale = 1.2 + 1.0 * legato; sub.drawDuration = 0.45 + 0.55 * legato    // strings — flowing arc
        }
        sub.markKind = sharp > 0.6 ? 2 : (sharp > 0.4 ? 1 : 0)   // diagnostic bucket only (form is per-voice)
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
                // VOICE HANDWRITING — each section draws its OWN form so you know it without reading colour:
                // strings glide, brass stabs blocky, woodwinds twirl, percussion sparks. Taper = full middle,
                // thin ends (a bowed mark). Articulation set the length/duration per voice in spawnSubject.
                let taper = 0.24 + 0.76 * sinf(ph * .pi)
                // RICERCAR-WIRE.2 — the sz constants are PIXELS, tuned at the 720p trail this
                // geometry used to be pinned to, so they must scale with the drawable or the
                // stroke breaks into beads (the FL.10 "deposit step <= point size" rule).
                let resScale = Float(configuration.height) / 720.0
                var square: Float = 0
                switch ges.colorIndex {
                case 1:                                        // BRASS — a bold BLOCKY slab (square sprites)
                    world = ges.origin + SIMD2(cs, sn) * ((ph - 0.5) * 0.10 * ges.scale)
                    sz = 22 * resScale; square = 1
                case 2:                                        // WOODWINDS — a quick twirly CURL (a little loop)
                    let th = ph * 2.3 * .pi, rad = (0.02 + 0.06 * ph) * ges.scale
                    let lx = cosf(th) * rad, ly = sinf(th) * rad * ges.flipY
                    world = ges.origin + SIMD2(lx * cs - ly * sn, lx * sn + ly * cs)
                    sz = 11 * taper * resScale
                case 3:                                        // PERCUSSION — a bright SPARK dot
                    world = ges.origin; sz = 15 * resScale
                default:                                       // STRINGS — a flowing tapered ARC
                    var loc = Self.subject(ph, ges.variant); loc.y *= ges.flipY
                    world = ges.origin + SIMD2(loc.x * cs - loc.y * sn, loc.x * sn + loc.y * cs) * ges.scale
                    sz = 16 * taper * resScale
                }
                // Soft attack/release along the draw; a dot/dab pops sharper (its whole life is short anyway).
                let env = min(1, ph * 6) * min(1, (1 - ph) * 6)
                ptr[base + ss] = EchoPen(
                    posSize: SIMD4(world.x, world.y, sz, ges.strength * (0.9 + 0.5 * env)),
                    color: SIMD4(hue.x, hue.y, hue.z, square))
            }
        }
    }

    private func makeConfig() -> RicercarEchoConfig {
        RicercarEchoConfig(
            width: UInt32(configuration.width),
            height: UInt32(configuration.height),
            penCount: UInt32(configuration.maxGestures * Self.subSteps),
            subSteps: UInt32(Self.subSteps),
            decay: 0.945,          // FAST fade → each spark is transient (pops and vanishes, no smear/lag)
            exposure: 1.25,        // modest — painterly, keep the marks' COLOUR (readable over the ground, not neon)
            aspect: Float(configuration.width) / Float(configuration.height),
            groundBlend: 1.0,      // soft painterly atmospheric ground (recessive, not the subject)
            time: time)
    }
}
