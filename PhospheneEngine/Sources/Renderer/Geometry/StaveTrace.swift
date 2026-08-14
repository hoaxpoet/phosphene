// StaveTrace — Stave's `ParticleGeometry` conformer: two beaded traces on a beat-ruled field.
//
// A sibling, not a subclass (D-097). Lifted from the CHR.2 look spike
// (`StaveLookSpike.swift`), which already carries four fixed defects that this file must
// not rediscover — each is commented at its site below.
//
// The concept, locked by D-216: **low against high, ruled by the beat, in a room the stems
// tint.** Two traces plot band energy in time; the vertical rules are the actual cached
// `BeatGrid` beat; the stems tint the field and touch NOTHING on a trace (L3/L4). CHR.2
// measured `r(position, colour)` at −0.15…+0.25 at the moment a mark is drawn, which is why
// per-mark instrument identity is out of scope.
//
// A trace is a TIME SERIES and `FeatureVector` is instantaneous, so the history ring lives
// here on the CPU — exactly as `WitchlightStroke` keeps its bead trail. No engine surface is
// touched, no `SpectralHistoryBuffer` extension.
//
// Why the ring and not a feedback accumulator: `drawParticleMode` CLEARS the drawable every
// frame and draws preset-fragment → particles into one encoder — there is no accumulator on
// this path at all. The trace's "smear" is the ring's own age-faded tail, which is exact
// where an accumulator would be approximate and would blur the beads away (reference `02`
// makes bead discreteness the hero trait).

import Metal
import Shared
import os.log

private let staveLogger = Logger(subsystem: "com.phosphene.renderer", category: "Stave")

// MARK: - StaveTrace

public final class StaveTrace: ParticleGeometry, @unchecked Sendable {

    public let configuration: StaveConfiguration

    /// Protocol requirement (D-057 governor), unused: the traces are an exact plot of the
    /// last 8 s, so skipping a fraction of the samples would put holes in the record. At
    /// 20 Hz × 8 s the ring is ~160 samples per trace — far inside budget at any level.
    public var activeParticleFraction: Float = 1.0

    // MARK: Gains

    /// **Per-trace gain is a precondition, not a tuning knob.** Melodic std is 4.4–17.5×
    /// below rhythm across the corpus (CHR.2 §2.1); at a shared gain the melodic trace is a
    /// flat line. Set so the corpus-median p95 excursion lands at ~0.30 NDC — measured
    /// p95|R| ≈ 0.65, p95|M| ≈ 0.094 across 15 tracks.
    static let rhythmGain: Float = 0.30 / 0.65
    static let melodicGain: Float = 0.30 / 0.094

    /// Soft saturation ceiling, tuned against p99 rather than 1.0 — deviation primitives
    /// spike to ~3× on real music (FA #73). `limit · tanh(x / limit)` is linear to within
    /// 4 % at the corpus median and compresses the 3.7× excursion span between Bleed and
    /// Dance Yrself Clean instead of clipping it off frame (CHR.2 qualification 2).
    /// **Decided over a running normaliser** (STAVE_DESIGN §6): a normaliser makes loud and
    /// quiet passages look identical, and "the music got louder" is half of what a plot is for.
    static let saturationLimit: Float = 0.85

    /// The traces' band sits across the lower-middle of the frame, per reference
    /// `01_macro_dotted_traces_on_grid.png` — hazy atmosphere above, near-black beneath.
    static let bandCentre: Float = -0.10

    // MARK: State

    struct Sample {
        var time: Float
        var rhythm: Float
        var melodic: Float
    }

    private(set) var samples: [Sample] = []
    /// Times of beat-phase wraps — the vertical rules.
    private(set) var beatTimes: [Float] = []

    private var subBass = StaveBandTracker(), lowBass = StaveBandTracker()
    private var midHigh = StaveBandTracker(), highMid = StaveBandTracker(), high = StaveBandTracker()
    private var tintDriver = StaveFieldTintDriver()
    private var lastBeatPhase: Float = 0
    private var clock: Float = 0

    /// Exposed for the harnesses and the route-coverage evidence.
    public var fieldTint: Float { tintDriver.tint }
    public var ruleDensity: Float { Float(beatTimes.count) }

    private let traceBuffer: MTLBuffer
    private let ruleBuffer: MTLBuffer
    private let tintPipeline: MTLRenderPipelineState?
    private let rulePipeline: MTLRenderPipelineState?
    private let threadPipeline: MTLRenderPipelineState?
    private let beadPipeline: MTLRenderPipelineState?

    private var config = StaveConfigGPU()
    private var uploadedSamples = 0
    private var uploadedRules = 0

    /// 8 s × 20 Hz = 160 samples; 512 is generous headroom for a slower plot rate.
    private static let sampleCapacity = 512
    private static let ruleCapacity = 256

    public init(
        device: MTLDevice,
        library: MTLLibrary,
        configuration: StaveConfiguration = .init(),
        pixelFormat: MTLPixelFormat? = nil
    ) throws {
        self.configuration = configuration

        let stride = MemoryLayout<StaveVertexGPU>.stride
        guard let trace = device.makeBuffer(length: Self.sampleCapacity * 2 * stride,
                                            options: .storageModeShared),
              let rules = device.makeBuffer(length: Self.ruleCapacity * 2 * stride,
                                            options: .storageModeShared) else {
            throw StaveError.bufferAllocationFailed
        }
        self.traceBuffer = trace
        self.ruleBuffer = rules

        if let pixelFormat {
            let factory = StavePipelineFactory(device: device, library: library, pixelFormat: pixelFormat)
            // The tint MULTIPLIES the backdrop rather than covering it, so the field's haze,
            // cloud and sparkle survive being recoloured (reference `03`: colour lives in the
            // field, the structure stays).
            self.tintPipeline = try factory.make(prefix: "stave_tint", blend: .multiply)
            self.rulePipeline = try factory.make(prefix: "stave_rule", blend: .alpha)
            // Alpha, NOT additive (CHR.2 defect 2): ~160 near-collinear ribbon quads
            // saturate to white under additive blending long before the trace is legible.
            self.threadPipeline = try factory.make(prefix: "stave_thread", blend: .alpha)
            // Beads ARE additive — they are sparse and discrete, so they glow without
            // accumulating into a wedge.
            self.beadPipeline = try factory.make(prefix: "stave_bead", blend: .additive)
        } else {
            self.tintPipeline = nil
            self.rulePipeline = nil
            self.threadPipeline = nil
            self.beadPipeline = nil
        }
        staveLogger.info(
            "StaveTrace: \(configuration.window) s window at \(configuration.plotHz) Hz")
    }

    // MARK: - ParticleGeometry

    public func update(features: FeatureVector, stemFeatures: StemFeatures, commandBuffer: MTLCommandBuffer) {
        // No compute encoder: the whole model is ~160 CPU samples per trace. Advancing in the
        // protocol's per-frame compute slot keeps the tick on the seam every other particle
        // preset uses, so the harnesses drive the identical path.
        advance(features: features, stems: stemFeatures)
        upload(features: features)
    }

    /// Pure-CPU tick, split out so it is drivable without a command buffer (harnesses, tests).
    public func advance(features: FeatureVector, stems: StemFeatures) {
        // The RENDER clock, never `accumulatedAudioTime`. The latter is energy-weighted by
        // definition, so it advances at a music-dependent rate — ~12× slower than wall-clock
        // on the CHR.2 captures. That makes it an animation phase, not a clock, and a
        // time-series plot needs a uniform axis or the whole window is warped.
        clock = features.time

        // POSITION — each band EMA-centred SEPARATELY and then summed, so a loud band cannot
        // drag its partner's pivot (FA #31).
        let rhythm = subBass.rel(features.subBass) + lowBass.rel(features.lowBass)
        let melodic = midHigh.rel(features.midHigh) + highMid.rel(features.highMid)
            + high.rel(features.high)

        tintDriver.advance(stems: stems, deltaTime: features.deltaTime)

        let interval = 1.0 / max(configuration.plotHz, 1)
        if samples.last.map({ clock - $0.time >= interval }) ?? true {
            samples.append(Sample(time: clock, rhythm: rhythm, melodic: melodic))
        }

        // Vertical rules from the beat-phase wrap. `beatsPerBar` is NOT stable within a track
        // (Billie Jean reads 4 in one segment and 3 in another), so every beat gets an
        // identical plain rule — no downbeat weighting, which would need a bar length the
        // capture cannot reliably supply. Density is handled meter-free (§5 decision (c)).
        if features.beatPhase01 < lastBeatPhase - 0.3 { beatTimes.append(clock) }
        lastBeatPhase = features.beatPhase01

        let cutoff = clock - configuration.window
        samples.removeAll { $0.time < cutoff }
        beatTimes.removeAll { $0 < cutoff }
    }

    public func render(encoder: MTLRenderCommandEncoder, features: FeatureVector) {
        var cfg = config
        let stride = MemoryLayout<StaveVertexGPU>.stride

        // 1. The room the stems tint — recolours the whole backdrop, behind everything.
        if let state = tintPipeline {
            encoder.setRenderPipelineState(state)
            encoder.setVertexBytes(&cfg, length: MemoryLayout<StaveConfigGPU>.stride, index: 1)
            encoder.setFragmentBytes(&cfg, length: MemoryLayout<StaveConfigGPU>.stride, index: 1)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }
        // 2. The beat.
        if let state = rulePipeline, uploadedRules >= 2 {
            encoder.setRenderPipelineState(state)
            encoder.setVertexBuffer(ruleBuffer, offset: 0, index: 0)
            encoder.setVertexBytes(&cfg, length: MemoryLayout<StaveConfigGPU>.stride, index: 1)
            for line in 0..<(uploadedRules / 2) {
                encoder.setVertexBufferOffset(line * 2 * stride, index: 0)
                encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            }
        }
        guard uploadedSamples >= 2 else { return }
        // 3/4. Faint connecting thread, then the beads on top. Reference `02` makes the beads
        //      the hero and `05_anti` is exactly two solid polylines, so the thread stays
        //      subordinate — it is there to say the beads belong to one trace, nothing more.
        for (index, offset) in [(0, 0), (1, Self.sampleCapacity * stride)] {
            _ = index
            if let state = threadPipeline {
                encoder.setRenderPipelineState(state)
                encoder.setVertexBuffer(traceBuffer, offset: offset, index: 0)
                encoder.setVertexBytes(&cfg, length: MemoryLayout<StaveConfigGPU>.stride, index: 1)
                encoder.drawPrimitives(
                    type: .triangleStrip,
                    vertexStart: 0,
                    vertexCount: 4,
                    instanceCount: uploadedSamples - 1
                )
            }
            if let state = beadPipeline {
                encoder.setRenderPipelineState(state)
                encoder.setVertexBuffer(traceBuffer, offset: offset, index: 0)
                encoder.setVertexBytes(&cfg, length: MemoryLayout<StaveConfigGPU>.stride, index: 1)
                encoder.drawPrimitives(
                    type: .triangleStrip,
                    vertexStart: 0,
                    vertexCount: 4,
                    instanceCount: uploadedSamples
                )
            }
        }
    }

    // MARK: - Upload

    /// `limit · tanh(x / limit)` — see `saturationLimit`.
    private static func softSaturate(_ x: Float) -> Float {
        saturationLimit * tanhf(x / saturationLimit)
    }

    private func upload(features: FeatureVector) {
        config.aspect = features.aspectRatio > 0.05 ? features.aspectRatio : 16.0 / 9.0
        config.time = clock
        let tint = tintDriver.multiplyColour
        config.tintR = tint.x
        config.tintG = tint.y
        config.tintB = tint.z

        // §5 decision (c) — fade rule opacity by MEASURED on-screen density, meter-free.
        // CHR.2 measured Bleed at 22.9 rules per 8 s window (172 bpm) and the render read as
        // graph paper. (a) rule-on-the-bar and (b) downbeat weighting both need `beatsPerBar`,
        // which the corpus says is unreliable within a single track; this needs no bar
        // knowledge at all.
        let density = Float(beatTimes.count)
        // The fade must not erase the rules — "no longer graph paper" and "the rules still
        // land on the beat" are both gate criteria. At 0.68 the Bleed render put them at the
        // edge of visibility; 0.55 leaves a legible pulse at 172 bpm without ruling the field.
        config.ruleAlpha = 1.0 - 0.55 * smoothstepf(9.0, 24.0, density)

        let ordered = samples.suffix(Self.sampleCapacity)
        let count = ordered.count
        uploadedSamples = count
        guard count > 0 else { uploadedRules = 0; return }

        let pointer = traceBuffer.contents()
            .bindMemory(to: StaveVertexGPU.self, capacity: Self.sampleCapacity * 2)
        let window = configuration.window
        let oldest = clock - window

        // Bead size rides the trace's OWN local slope (D3) — a derived geometric quantity,
        // not a new audio primitive, so it costs nothing against FA #67 and reads as "the
        // line is moving fast here". Needs both neighbours, so it is computed over the
        // materialised array rather than streamed.
        let array = Array(ordered)
        for (i, sample) in array.enumerated() {
            let x = ((sample.time - oldest) / window) * 2.0 - 1.0
            // Age-faded tail: the oldest end of the ring dims toward the left edge. This is
            // the preset's "smear", and it is exact where a feedback accumulator would blur
            // the beads away.
            let age = Float(i) / Float(max(count - 1, 1))
            let alpha = 0.18 + 0.82 * age * age

            let previous = array[max(i - 1, 0)]
            let next = array[min(i + 1, count - 1)]
            let dx = max(next.time - previous.time, 1e-4)

            let rhythmY = Self.softSaturate(sample.rhythm * Self.rhythmGain) + Self.bandCentre
            let melodicY = Self.softSaturate(sample.melodic * Self.melodicGain) + Self.bandCentre
            let rhythmSlope = abs(Self.softSaturate(next.rhythm * Self.rhythmGain)
                                  - Self.softSaturate(previous.rhythm * Self.rhythmGain)) / dx
            let melodicSlope = abs(Self.softSaturate(next.melodic * Self.melodicGain)
                                   - Self.softSaturate(previous.melodic * Self.melodicGain)) / dx

            // BOTH traces carry the SAME cyan. Reference `03` is explicit that the traces
            // stay cyan throughout while the field's hue drifts, and giving the two traces
            // different hues would re-introduce exactly the frequency-band colour label
            // D-216 retired — a static hue asserting an identity even on material where it
            // is false. They are told apart by shape and position, which is what "two
            // voices" means; CHR.2's flat-white control already read as two voices on 3 of
            // 4 captures with no colour difference at all.
            let bead = SIMD3<Float>(0.34, 0.86, 0.98)
            pointer[i] = StaveVertexGPU(
                x: x,
                y: rhythmY,
                colour: bead,
                alpha: alpha,
                width: Self.beadWidth(configuration.beadRadius, slope: rhythmSlope)
            )
            pointer[Self.sampleCapacity + i] = StaveVertexGPU(
                x: x,
                y: melodicY,
                colour: bead,
                alpha: alpha,
                width: Self.beadWidth(configuration.beadRadius, slope: melodicSlope)
            )
        }

        uploadRules(oldest: oldest, window: window)
    }

    /// The beat verticals, split from `upload` for the function-body lint budget.
    private func uploadRules(oldest: Float, window: Float) {
        let rulePointer = ruleBuffer.contents()
            .bindMemory(to: StaveVertexGPU.self, capacity: Self.ruleCapacity * 2)
        var written = 0
        for time in beatTimes.suffix(Self.ruleCapacity) {
            let x = ((time - oldest) / window) * 2.0 - 1.0
            let violet = StaveVertexGPU(
                x: x,
                y: 0,
                colour: SIMD3<Float>(0.42, 0.36, 0.72),
                alpha: 1,
                width: 0.0018
            )
            var bottom = violet, top = violet
            bottom.posY = -1.0
            top.posY = 1.0
            rulePointer[written] = bottom
            rulePointer[written + 1] = top
            written += 2
        }
        uploadedRules = written
    }

    /// Beads swell where the trace is moving fast and shrink where it is flat, so bead SIZE
    /// and SPACING both vary along one trace — the `02_meso_bead_spacing.png` hero trait.
    private static func beadWidth(_ base: Float, slope: Float) -> Float {
        base * (0.55 + 0.85 * smoothstepf(0.0, 2.2, slope))
    }
}

// MARK: - Helpers

/// Local `smoothstep`, so this file does not depend on a SIMD import for two call sites.
private func smoothstepf(_ edge0: Float, _ edge1: Float, _ x: Float) -> Float {
    let ramp = min(max((x - edge0) / max(edge1 - edge0, 1e-6), 0), 1)
    return ramp * ramp * (3 - 2 * ramp)
}

// MARK: - Errors

public enum StaveError: Error, Sendable {
    case bufferAllocationFailed
    case functionNotFound(String)
}
