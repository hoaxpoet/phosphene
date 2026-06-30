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
    /// Cells the colony seeds/regrows from — few large cells, the early-division showcase.
    public var seedCells: Int
    /// Divide (monotonically, no culling) until the colony reaches this many cells →
    /// "much of the screen is crowded" (Matt's live G2.2 note). Then hold + dissolve + regrow.
    public var crowdCount: Int
    /// Hard array cap (GPU cell-buffer length); ≥ crowdCount with headroom.
    public var maxCells: Int
    /// Baseline seconds for one cell's interphase→split cycle (the growth pace).
    public var divPeriod: Float
    /// Fraction of the screen the packed colony fills when crowded — radius scales so the
    /// cells fill this without overlapping (cells shrink as the count grows).
    public var coverage: Float
    /// Seconds to hold the crowded field before dissolving, and the dissolve duration.
    public var holdSeconds: Float
    public var dissolveSeconds: Float

    public init(
        seedCells: Int = 3,
        crowdCount: Int = 40,
        maxCells: Int = 64,
        divPeriod: Float = 11,
        coverage: Float = 0.62,
        holdSeconds: Float = 4,
        dissolveSeconds: Float = 5
    ) {
        self.seedCells = seedCells
        self.crowdCount = crowdCount
        self.maxCells = maxCells
        self.divPeriod = divPeriod
        self.coverage = coverage
        self.holdSeconds = holdSeconds
        self.dissolveSeconds = dissolveSeconds
    }
}

// MARK: - MitosisGen2Geometry

public final class MitosisGen2Geometry: ParticleGeometry, @unchecked Sendable {

    public let configuration: MitosisGen2Configuration
    /// Protocol requirement (D-057 governor), unused: every cell updates every frame.
    public var activeParticleFraction: Float = 1.0

    private let renderPipeline: MTLRenderPipelineState?

    /// CPU cell model. `radius` is the displayed radius (lerps toward `targetRadius`, which
    /// is set each frame from the packing density so the colony fills the screen as it grows).
    private struct Cell {
        var pos: SIMD2<Float>
        var radius: Float
        var targetRadius: Float
        var axis: Float
        var phase: Float
        var phaseRate: Float    // 1/sec base division rate
        var seed: Float
    }
    private var cells: [Cell] = []

    /// Colony life-cycle: few cells GROW (divide, no culling) until crowded → HOLD → DISSOLVE
    /// (melt back) → regrow. Mirrors the certified gen-1 arc, with detailed non-overlapping cells.
    private enum Stage { case growing, holding, dissolving }
    private var stage: Stage = .growing
    private var stageTimer: Float = 0

    // Music envelopes (port of gen-1 `advanceEnvelopes`; one primitive per layer, FA #67).
    private var energyEnv: Float = 0
    private var centroidEnv: Float = 0
    private var hitEnv: Float = 0
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
        logger.info("MitosisGen2 (Cytokinesis): \(configuration.seedCells) seed → \(configuration.crowdCount) crowded")
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
            seed: rand(0, 100))
    }

    /// Keep cell centres on-screen (aspect space spans ±~1.78 × ±1 at 16:9).
    private func clampPos(_ pos: SIMD2<Float>) -> SIMD2<Float> {
        SIMD2(min(max(pos.x, -1.7), 1.7), min(max(pos.y, -0.92), 0.92))
    }

    /// Displayed radius so `count` cells fill `coverage` of the screen without overlapping —
    /// few cells start large (the detail showcase), and they shrink as the colony crowds.
    private func packRadius(count: Int, aspect: Float) -> Float {
        let screenArea = 4.0 * max(1.0, aspect)            // (2·aspect) × 2 in aspect space
        let perCell = configuration.coverage * screenArea / Float(max(1, count))
        return min(0.62, max(0.10, (perCell / .pi).squareRoot()))
    }

    private func seedColony() {
        cells.removeAll(keepingCapacity: true)
        for _ in 0..<configuration.seedCells {
            let rad = rand(0.42, 0.55)
            cells.append(makeCell(
                pos: SIMD2(rand(-0.9, 0.9), rand(-0.55, 0.55)),
                axis: rand(0, 2 * .pi),
                phase: rand(0, 0.5),
                radius: 0.06,    // fade in (grow to target) — no sudden bright pop at (re)seed
                target: rad))
        }
        stage = .growing
        stageTimer = 0
    }

    // MARK: - ParticleGeometry

    public func update(features: FeatureVector, stemFeatures: StemFeatures, commandBuffer: MTLCommandBuffer) {
        var dt = features.deltaTime
        if !(dt > 0) { dt = 1.0 / 60.0 }
        dt = min(dt, 1.0 / 30.0)
        advanceEnvelopes(features: features, stems: stemFeatures, dt: dt)
        clock += dt

        let aspect = features.aspectRatio > 0.1 ? features.aspectRatio : 1.778
        let pace = 0.6 + 0.8 * min(1, max(0, energyEnv))   // energy nudges the growth pace
        let packR = packRadius(count: cells.count, aspect: aspect)

        // Each cell: radius lerps toward the packing size (0 while dissolving → it melts);
        // phase advances only while the colony is still growing.
        let dissolving = stage == .dissolving
        for i in cells.indices {
            cells[i].targetRadius = dissolving ? 0 : packR
            let lerp = dissolving ? min(1, dt * 0.9) : min(1, dt * 2.2)
            cells[i].radius += (cells[i].targetRadius - cells[i].radius) * lerp
            if stage == .growing { cells[i].phase += dt * cells[i].phaseRate * pace }
        }

        advanceStage(dt: dt)
        relax(aspect: aspect, iterations: 4)   // circle-packing → cells never overlap
    }

    /// The grow → hold → dissolve → regrow life-cycle.
    private func advanceStage(dt: Float) {
        switch stage {
        case .growing:
            // A completed cell (phase ≥ 1) divides into two — monotonically, NO culling —
            // until the colony reaches the crowd target. Once crowded, completed cells just
            // re-enter interphase (keep visibly cycling) instead of adding more.
            var i = 0
            while i < cells.count {
                if cells[i].phase >= 1.0 {
                    if cells.count < configuration.crowdCount && cells.count < configuration.maxCells {
                        divide(at: i)
                    } else {
                        cells[i].phase = 0   // crowded: re-cycle in place, don't grow
                    }
                }
                i += 1
            }
            if cells.count >= configuration.crowdCount { stage = .holding; stageTimer = 0 }
        case .holding:
            stageTimer += dt
            if stageTimer >= configuration.holdSeconds { stage = .dissolving; stageTimer = 0 }
        case .dissolving:
            cells.removeAll { $0.radius < 0.03 }                       // melted cells drop out
            stageTimer += dt
            if cells.count <= configuration.seedCells || stageTimer >= configuration.dissolveSeconds {
                seedColony()                                          // regrow from a few cells
            }
        }
    }

    /// A completed cell splits along its axis into two daughters (cytokinesis). Daughters
    /// start at the parent's radius (then shrink toward the new packing size) and are offset
    /// along the axis; the packing relaxation separates them from neighbours over the next
    /// frames. Monotonic growth — no culling (Matt G2.2: divide until crowded, no respawning).
    private func divide(at index: Int) {
        let parent = cells[index]
        let off = parent.radius * 0.7
        let dir = SIMD2(cos(parent.axis), sin(parent.axis)) * off
        let r0 = parent.radius * 0.7
        let daughterA = makeCell(
            pos: parent.pos - dir,
            axis: parent.axis + .pi / 2 + rand(-0.5, 0.5),
            phase: 0,
            radius: r0,
            target: r0)
        let daughterB = makeCell(
            pos: parent.pos + dir,
            axis: parent.axis + .pi / 2 + rand(-0.5, 0.5),
            phase: 0,
            radius: r0,
            target: r0)
        cells[index] = daughterA
        cells.append(daughterB)
    }

    /// Soft circle-packing: push overlapping cells apart so they never visually overlap.
    /// Collision radius is inflated slightly with division phase to account for the dumbbell
    /// elongation. O(n²) per iteration — fine for n ≤ crowdCount (~40); raise to a grid only
    /// if the crowd target grows large. ponytail: O(n²), grid-bucket it if crowdCount ≫ 64.
    private func relax(aspect: Float, iterations: Int) {
        guard cells.count > 1 else { return }
        func collisionR(_ cell: Cell) -> Float {
            let sep = smoothstepF(0.2, 1.0, cell.phase)
            return cell.radius * (1.0 + 0.22 * sep)
        }
        for _ in 0..<iterations {
            for ia in 0..<cells.count {
                let ra = collisionR(cells[ia])
                for ib in (ia + 1)..<cells.count {
                    let delta = cells[ib].pos - cells[ia].pos
                    let minD = ra + collisionR(cells[ib])
                    var dist = (delta.x * delta.x + delta.y * delta.y).squareRoot()
                    if dist >= minD { continue }
                    let dir: SIMD2<Float>
                    if dist < 1e-4 {                                  // coincident → deterministic nudge
                        dir = SIMD2(cos(Float(ia) * 2.399), sin(Float(ia) * 2.399)); dist = 0.001
                    } else {
                        dir = delta / dist
                    }
                    let push = (minD - dist) * 0.5
                    cells[ia].pos = clampPos(cells[ia].pos - dir * push)
                    cells[ib].pos = clampPos(cells[ib].pos + dir * push)
                }
            }
        }
    }

    private func smoothstepF(_ e0: Float, _ e1: Float, _ x: Float) -> Float {
        let tn = max(0, min(1, (x - e0) / (e1 - e0)))
        return tn * tn * (3 - 2 * tn)
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

    /// Live cell count — exposed so the lifecycle test can assert the grow→crowd→regrow arc.
    public var currentCellCount: Int { cells.count }
    /// Smoothed energy envelope (test).
    public var currentEnergyEnv: Float { energyEnv }

    /// Worst pairwise overlap of the drawn cell circles (`r_a + r_b − dist`); ≤ 0 means no
    /// two cells overlap. Exposed so the packing gate can assert non-overlap (Matt G2.2).
    public var maxPairOverlap: Float {
        var worst: Float = 0
        for ia in 0..<cells.count {
            for ib in (ia + 1)..<cells.count {
                let delta = cells[ib].pos - cells[ia].pos
                let dist = (delta.x * delta.x + delta.y * delta.y).squareRoot()
                worst = max(worst, cells[ia].radius + cells[ib].radius - dist)
            }
        }
        return worst
    }

    private static func smoothstep(_ e0: Float, _ e1: Float, _ x: Float) -> Float {
        let tn = max(0, min(1, (x - e0) / (e1 - e0)))
        return tn * tn * (3 - 2 * tn)
    }
}

// MARK: - Errors

public enum MitosisGen2Error: Error, Sendable {
    case functionNotFound(String)
}
