// MitosisGen2Geometry — the "detailed psychedelic cell division" preset (Cytokinesis).
//
// Gen-2 sibling of the certified gen-1 `MitosisGeometry` (D-097, NOT an edit of it). Where
// gen-1 is an abstract Gray–Scott spot field, gen-2 is a few LARGE, procedurally-detailed
// dividing cells rendered like confocal fluorescence microscopy (dumbbell furrow + two
// green asters + solid membrane wall + coloured cortex + chromatin + magenta midzone).
//
// Substrate = an explicit CPU cell list (Matt-locked) — NOT reaction–diffusion. So this
// `ParticleGeometry` has NO compute pass: `update` advances the music envelopes + the cell
// model on the CPU; `render` packs the live cells via `setFragmentBytes` to the
// `mitosisgen2_fragment` shader (ported from the approved sketch, `tools/mitosis_gen2_sketch`).
//
// Musical role (MITOSIS_GEN2_DESIGN §1): sustained energy advances each cell's division
// phase (louder = faster toward splitting); a drum onset triggers the cytokinesis SNAP (a
// ready cell splits into two daughters on the beat); spectral centroid drives the palette.

import Metal
import Shared
import os.log

private let logger = Logger(subsystem: "com.phosphene.renderer", category: "MitosisGen2")

// MARK: - GPU layouts (mirror the MSL structs in Renderer/Shaders/MitosisGen2.metal)

/// One cell as the fragment shader sees it (24 B; float2 8-aligned). CPU-only fields
/// (phaseRate, targetRadius, age) live in `Cell` and are not sent to the GPU.
struct Gen2CellGPU {
    var pos: SIMD2<Float> = .zero   // aspect-corrected space, y up
    var radius: Float = 0
    var axis: Float = 0             // division-axis angle
    var phase: Float = 0            // 0 interphase → 1 split
    var seed: Float = 0
}

/// Per-frame fragment uniforms (28 B).
struct Gen2Uniforms {
    var aspect: Float = 1.778  // viewport width/height (features.aspectRatio)
    var energy: Float = 0
    var centroid: Float = 0    // timbre → palette hue bias
    var huePhase: Float = 0
    var hit: Float = 0         // drum transient → bounded glow accent
    var cellCount: UInt32 = 0
    var time: Float = 0
}

// MARK: - Configuration

public struct MitosisGen2Configuration: Sendable {
    /// Hard cap on simultaneous cells — the locked arc is "few large cells" so detail reads
    /// (never crowds to dots). Also the GPU cell-buffer length.
    public var maxCells: Int
    /// Cells the colony starts/seeds with.
    public var seedCells: Int
    /// Baseline seconds for one interphase→split cycle at moderate energy.
    public var divPeriod: Float

    public init(maxCells: Int = 8, seedCells: Int = 3, divPeriod: Float = 9) {
        self.maxCells = maxCells
        self.seedCells = seedCells
        self.divPeriod = divPeriod
    }
}

// MARK: - MitosisGen2Geometry

public final class MitosisGen2Geometry: ParticleGeometry, @unchecked Sendable {

    public let configuration: MitosisGen2Configuration
    /// Protocol requirement (D-057 governor), unused: every cell updates every frame.
    public var activeParticleFraction: Float = 1.0

    private let renderPipeline: MTLRenderPipelineState?

    /// CPU cell model. `radius` is the displayed radius (grows toward `targetRadius`).
    private struct Cell {
        var pos: SIMD2<Float>
        var radius: Float
        var targetRadius: Float
        var axis: Float
        var phase: Float
        var phaseRate: Float    // cycles/sec at unit energy pace
        var seed: Float
        var age: Float          // seconds alive — for cull-oldest at cap
    }
    private var cells: [Cell] = []

    // Music envelopes (port of gen-1 `advanceEnvelopes`; one primitive per layer, FA #67).
    private var energyEnv: Float = 0
    private var centroidEnv: Float = 0
    private var hitEnv: Float = 0
    private var prevHit: Float = 0
    private var huePhase: Float = 0
    private var clock: Float = 0

    private var rng: UInt64 = 0x9E3779B97F4A7C15

    public init(
        device: MTLDevice,
        library: MTLLibrary,
        configuration: MitosisGen2Configuration = .init(),
        pixelFormat: MTLPixelFormat? = nil
    ) throws {
        self.configuration = configuration

        if let pixelFormat {
            guard let vfn = library.makeFunction(name: "fullscreen_vertex"),
                  let ffn = library.makeFunction(name: "mitosisgen2_fragment") else {
                throw MitosisGen2Error.functionNotFound("fullscreen_vertex/mitosisgen2_fragment")
            }
            let desc = MTLRenderPipelineDescriptor()
            desc.vertexFunction = vfn
            desc.fragmentFunction = ffn
            desc.colorAttachments[0].pixelFormat = pixelFormat
            self.renderPipeline = try device.makeRenderPipelineState(descriptor: desc)
        } else {
            self.renderPipeline = nil
        }
        seedColony()
        logger.info("MitosisGen2 (Cytokinesis): \(configuration.seedCells) seed cells, cap \(configuration.maxCells)")
    }

    // MARK: - Deterministic RNG (same scatter every run)

    private func rand() -> Float {
        rng = rng &* 6364136223846793005 &+ 1442695040888963407
        return Float((rng >> 33) & 0xFFFFFF) / Float(0xFFFFFF)
    }
    private func rand(_ lo: Float, _ hi: Float) -> Float { lo + (hi - lo) * rand() }

    private func makeCell(pos: SIMD2<Float>, axis: Float, phase: Float, radius: Float, target: Float) -> Cell {
        Cell(
            pos: clampPos(pos),
            radius: radius,
            targetRadius: target,
            axis: axis,
            phase: phase,
            phaseRate: 1.0 / (configuration.divPeriod * rand(0.8, 1.25)),
            seed: rand(0, 100),
            age: 0)
    }

    /// Keep cells in a central band so the large detail stays on-screen.
    private func clampPos(_ pos: SIMD2<Float>) -> SIMD2<Float> {
        SIMD2(min(max(pos.x, -1.4), 1.4), min(max(pos.y, -0.82), 0.82))
    }

    private func seedColony() {
        cells.removeAll(keepingCapacity: true)
        for _ in 0..<configuration.seedCells {
            let rad = rand(0.42, 0.55)
            cells.append(makeCell(
                pos: SIMD2(rand(-0.9, 0.9), rand(-0.55, 0.55)),
                axis: rand(0, 2 * .pi),
                phase: rand(0, 0.5),
                radius: rad,
                target: rad))
        }
    }

    // MARK: - ParticleGeometry

    public func update(features: FeatureVector, stemFeatures: StemFeatures, commandBuffer: MTLCommandBuffer) {
        var dt = features.deltaTime
        if !(dt > 0) { dt = 1.0 / 60.0 }
        dt = min(dt, 1.0 / 30.0)
        advanceEnvelopes(features: features, stems: stemFeatures, dt: dt)
        clock += dt

        let pace = 0.6 + 0.8 * min(1, max(0, energyEnv))   // louder → faster toward the split

        // Advance each cell's division phase + grow its displayed radius toward target.
        for i in cells.indices {
            cells[i].phase += dt * cells[i].phaseRate * pace
            cells[i].radius += (cells[i].targetRadius - cells[i].radius) * min(1, dt * 1.4)
            cells[i].age += dt
        }

        // Drum onset (rising edge of hitEnv) → SNAP the most-ready cell to completion so the
        // split lands ON the beat. Between onsets cells still complete naturally when their
        // phase reaches 1 (energy-paced) — so a non-percussive track still divides (Audio
        // Data Hierarchy: energy is the primary driver, the onset only times the snap).
        let onset = hitEnv > 0.5 && prevHit <= 0.5
        prevHit = hitEnv
        if onset, let ready = mostReadyCell(minPhase: 0.45) {
            cells[ready].phase = 1.0
        }

        // Resolve completed divisions (phase ≥ 1) into two daughters.
        var i = 0
        while i < cells.count {
            if cells[i].phase >= 1.0 { divide(at: i) } else { i += 1 }
        }
    }

    /// Index of the cell furthest through its cycle (past `minPhase`), or nil.
    private func mostReadyCell(minPhase: Float) -> Int? {
        var best: Int?
        var bestPhase = minPhase
        for i in cells.indices where cells[i].phase > bestPhase { best = i; bestPhase = cells[i].phase }
        return best
    }

    /// A completed cell splits along its axis into two daughters (the cytokinesis snap →
    /// two cells). Daughters start small (regrow), with fresh phases/axes/seeds. Population
    /// is bounded: at cap, cull the oldest *other* cell first so the count stays in the
    /// "few large cells" band while real split events still happen.
    private func divide(at index: Int) {
        let parent = cells[index]
        let off = parent.targetRadius * 0.6
        let dir = SIMD2(cos(parent.axis), sin(parent.axis)) * off
        let dTarget = max(0.34, parent.targetRadius * 0.86)   // daughters a touch smaller; never tiny
        let daughterA = makeCell(
            pos: parent.pos - dir,
            axis: parent.axis + .pi / 2 + rand(-0.4, 0.4),
            phase: 0,
            radius: dTarget * 0.55,
            target: dTarget)
        let daughterB = makeCell(
            pos: parent.pos + dir,
            axis: parent.axis + .pi / 2 + rand(-0.4, 0.4),
            phase: 0,
            radius: dTarget * 0.55,
            target: dTarget)
        cells[index] = daughterA
        if cells.count >= configuration.maxCells {
            // cull the oldest other cell to make room (keeps the count bounded)
            if let oldest = oldestCell(excluding: index) { cells[oldest] = daughterB } else { cells.append(daughterB) }
        } else {
            cells.append(daughterB)
        }
    }

    private func oldestCell(excluding idx: Int) -> Int? {
        var best: Int?
        var bestAge: Float = -1
        for i in cells.indices where i != idx && cells[i].age > bestAge { best = i; bestAge = cells[i].age }
        return best
    }

    public func render(encoder: MTLRenderCommandEncoder, features: FeatureVector) {
        guard let pipeline = renderPipeline else { return }
        let cap = configuration.maxCells
        var gpu = [Gen2CellGPU](repeating: Gen2CellGPU(), count: cap)
        let live = min(cells.count, cap)
        for i in 0..<live {
            gpu[i] = Gen2CellGPU(
                pos: cells[i].pos,
                radius: cells[i].radius,
                axis: cells[i].axis,
                phase: cells[i].phase,
                seed: cells[i].seed)
        }
        let aspect = features.aspectRatio > 0.1 ? features.aspectRatio : 1.778
        var uni = Gen2Uniforms(
            aspect: aspect,
            energy: max(0, min(1.2, energyEnv)),
            centroid: centroidEnv,
            huePhase: huePhase,
            hit: min(1.4, hitEnv),
            cellCount: UInt32(live),
            time: clock)

        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uni, length: MemoryLayout<Gen2Uniforms>.stride, index: 0)
        gpu.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            encoder.setFragmentBytes(base, length: raw.count, index: 1)
        }
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    }

    // MARK: - Music envelopes (ported from gen-1 MitosisGeometry.advanceEnvelopes)

    private func advanceEnvelopes(features: FeatureVector, stems: StemFeatures, dt: Float) {
        let stemTotal = stems.drumsEnergy + stems.bassEnergy + stems.otherEnergy + stems.vocalsEnergy
        let blend = Self.smoothstep(0.02, 0.06, stemTotal)
        let stemEnergy = (stems.drumsEnergy + stems.bassEnergy + stems.otherEnergy) / 3 + 0.4 * stems.vocalsEnergy
        let fullEnergy = (features.bass + features.mid) * 0.5
        let rawEnergy = fullEnergy + (stemEnergy - fullEnergy) * blend
        energyEnv += Float(dt / (0.30 + dt)) * (rawEnergy - energyEnv)

        huePhase += Float(dt) * (0.10 + 0.9 * max(0, min(1.2, energyEnv)))
        centroidEnv += Float(dt / (0.50 + dt)) * (max(0, min(1, features.spectralCentroid)) - centroidEnv)

        let hitRaw = max(stems.drumsEnergyDev, 0.7 * stems.bassEnergyDev) * blend
        let hitAlpha = hitRaw > hitEnv ? dt / (0.015 + dt) : dt / (0.22 + dt)
        hitEnv += Float(hitAlpha) * (hitRaw - hitEnv)
    }

    // MARK: - Test introspection

    /// Live cell count — exposed so the lifecycle test can assert the bounded few-cells arc.
    public var currentCellCount: Int { cells.count }
    /// Smoothed energy envelope (test).
    public var currentEnergyEnv: Float { energyEnv }

    private static func smoothstep(_ e0: Float, _ e1: Float, _ x: Float) -> Float {
        let tn = max(0, min(1, (x - e0) / (e1 - e0)))
        return tn * tn * (3 - 2 * tn)
    }
}

// MARK: - Errors

public enum MitosisGen2Error: Error, Sendable {
    case functionNotFound(String)
}
