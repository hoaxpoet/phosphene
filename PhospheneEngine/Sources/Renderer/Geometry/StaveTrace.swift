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

    /// The motion model. Exposed so harnesses and the QG.5 gate can reach it; every piece of
    /// Stave's simulation lives there and nothing in this file re-derives it.
    public let model: StaveTraceModel

    /// Exposed for the harnesses and the route-coverage evidence.
    public var fieldTint: Float { model.fieldTint }
    public var ruleDensity: Float { model.ruleDensity }

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
        self.model = StaveTraceModel(configuration: configuration)

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

    /// Pure-CPU tick, drivable without a command buffer (harnesses, tests). Delegates to
    /// `StaveTraceModel` — the simulation has exactly one home.
    public func advance(features: FeatureVector, stems: StemFeatures) {
        model.advance(features: features, stems: stems)
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

    private func upload(features: FeatureVector) {
        config.aspect = features.aspectRatio > 0.05 ? features.aspectRatio : 16.0 / 9.0
        config.time = model.clock
        let tint = model.tintMultiplyColour
        config.tintR = tint.x
        config.tintG = tint.y
        config.tintB = tint.z

        // §5 decision (c) — fade rule opacity by MEASURED on-screen density, meter-free.
        // CHR.2 measured Bleed at 22.9 rules per 8 s window (172 bpm) and the render read as
        // graph paper. (a) rule-on-the-bar and (b) downbeat weighting both need `beatsPerBar`,
        // which the corpus says is unreliable within a single track; this needs no bar
        // knowledge at all.
        let density = model.ruleDensity
        // The fade must not erase the rules — "no longer graph paper" and "the rules still
        // land on the beat" are both gate criteria. At 0.68 the Bleed render put them at the
        // edge of visibility; 0.55 leaves a legible pulse at 172 bpm without ruling the field.
        config.ruleAlpha = 1.0 - 0.55 * smoothstepf(9.0, 24.0, density)

        let ordered = model.samples.suffix(Self.sampleCapacity)
        let count = ordered.count
        uploadedSamples = count
        guard count > 0 else { uploadedRules = 0; return }

        let pointer = traceBuffer.contents()
            .bindMemory(to: StaveVertexGPU.self, capacity: Self.sampleCapacity * 2)
        let window = configuration.window
        let oldest = model.clock - window

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

            // Drawn positions, matching StaveTraceModel's own QG.5 accounting exactly — the
            // gain and the saturation live there, so the picture and the measured band can
            // never drift apart.
            func drawnRhythm(_ value: Float) -> Float {
                StaveTraceModel.softSaturate(value * StaveTraceModel.rhythmGain)
            }
            func drawnMelodic(_ value: Float) -> Float {
                StaveTraceModel.softSaturate(value * StaveTraceModel.melodicGain)
            }
            let rhythmY = drawnRhythm(sample.rhythm) + StaveTraceModel.bandCentre
            let melodicY = drawnMelodic(sample.melodic) + StaveTraceModel.bandCentre
            let rhythmSlope = abs(drawnRhythm(next.rhythm) - drawnRhythm(previous.rhythm)) / dx
            let melodicSlope = abs(drawnMelodic(next.melodic) - drawnMelodic(previous.melodic)) / dx

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
        for time in model.beatTimes.suffix(Self.ruleCapacity) {
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
