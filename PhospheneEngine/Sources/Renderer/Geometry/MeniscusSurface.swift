// MeniscusSurface — the serpentine projected line-strip water surface (MEN.2a).
//
// A `ParticleGeometry` sibling (D-097) for Meniscus. Owns the height field, the
// two-buffer wave step, and the line pipeline. Per frame: step the sim →
// serialize the grid into ONE serpentine path → draw each path segment as a
// sideways-spread quad.
//
// WHY CPU, NOT COMPUTE (MEN.2a task 1c). The wave step is trivially parallel but also
// trivially small: `MENISCUS_PLAN.md` §7 R4 says raising the resolution CLOSES the
// raster gaps that make the preset legible, so the grid can never grow to where a
// dispatch pays for itself. The decisive argument is MEN.2b — drop placement is
// CPU-derived, so a CPU height field keeps a drop a single `+=` with no upload path.
// Precedent: `MitosisGen2Geometry` (CPU) vs `CymaticSandGeometry` (compute).
//
// SERPENTINE LIVES ON THE CPU. The serialization loop emits points in traversal order
// (alternate rows reversed), so the vertex shader indexes the buffer linearly and
// carries no boustrophedon logic. The rounded turnaround caps at the margins
// (reference `07`, trait T1) are the joins between one row's end and the next row's
// start — they fall out of the ordering, they are not drawn specially.
//
// NO AUDIO AT MEN.2a. `update` ignores `features` apart from `deltaTime`. The
// source's own drop placement lands at MEN.2b; the Phosphene stem routing at MEN.3.
//
// See `docs/presets/MENISCUS_PLAN.md` and `Renderer/Shaders/MeniscusSurface.metal`.

import Metal
import Shared
import os.log

private let meniscusLogger = Logger(subsystem: "com.phosphene.renderer", category: "Meniscus")

// MARK: - MeniscusPoint (mirror of MSL `MeniscusPoint`, 8 bytes)

/// One sample on the serpentine path: its display height and the slope term the
/// shading reads. Grid coordinates are NOT stored — the vertex shader recovers
/// them from the path index, which keeps the buffer at 8 B/point.
@frozen
public struct MeniscusPoint: Sendable {
    public var height: Float
    public var slope: Float
}

// MARK: - MeniscusConfig (mirror of MSL `MeniscusConfig`, 56 bytes: 3×uint + 11×float)

struct MeniscusConfig {
    var gridN: UInt32
    var pointCount: UInt32
    var spreadMode: UInt32      // 0 = screen-space X (source), 1 = line normal
    var spread: Float           // half-width of the sideways spread, NDC-x units
    var yaw: Float
    var pitch: Float
    var camDist: Float
    var camHeight: Float
    var focal: Float
    var heightScale: Float
    var slopeGain: Float
    var aspect: Float
    var brightness: Float
    var lightDir: Float         // screen-space angle of the key light (radians)
}

// MARK: - Configuration

public struct MeniscusConfiguration: Sendable {

    /// Grid resolution per side. The source's figure is 45; raising it smooths the
    /// surface but closes the raster gaps (`MENISCUS_PLAN.md` §7 R4).
    public var gridN: Int
    /// Wave-propagation damping per step. < 1 so energy bleeds away.
    public var damping: Float
    /// Vertical exaggeration applied to the height field at projection time.
    public var heightScale: Float
    /// Half-width of the sideways glow spread, in NDC-x units. This single number IS
    /// the §9 soft/crisp axis: 0.035 reads diagrammatic, 0.070 reads as light lying on
    /// water. It costs nothing either way — see `spreadMode`.
    public var spread: Float
    /// 0 = spread along screen-space X (what the source does), 1 = along the segment's
    /// screen-space normal. MEN.2a task 1a answered this from renders — screen-space X;
    /// the tangent-normal ribbon closes the raster. Full reasoning at the `THE SPREAD`
    /// note in `MeniscusSurface.metal`, and see `yawCentre`, which it constrains.
    public var spreadMode: Int
    /// Amplitude of the MEN.2a placeholder standing swell (task 6). Set to 0 and
    /// the surface is whatever the sim is doing on its own.
    public var swellAmplitude: Float
    /// IIR coefficient for the lagged smoothed height the slope term differences
    /// against. 1.0 degenerates to a plain forward difference.
    public var slopeLag: Float
    /// Contrast of the slope→brightness term (trait T3).
    ///
    /// Tied to `swellAmplitude`: a calmer field has proportionally smaller slopes, so
    /// holding the gain fixed while calming the surface trades all-over agitation for
    /// a flat grey sheet — "a soft, evenly-lit version of this looks like fabric, not
    /// water". The two move together. MEN.2b must revisit this once drop impacts
    /// exist: an impact SHOULD saturate to white, so the gain wants to be set from the
    /// calm baseline and allowed to clip on transients, not fitted to the peak.
    public var slopeGain: Float
    /// Centre of the camera heading's oscillation, radians.
    ///
    /// The heading is NOT a free parameter: the screen-X spread thickens a row
    /// perpendicular to itself by `spread · |sin θ|` where θ is the row's screen
    /// angle. Near 0 the rows run across the frame, the spread runs ALONG them, and
    /// the raster gaps survive — the "crisp in Y, soft in X" asymmetry the reference
    /// README calls load-bearing. At the 0.62 rad this shipped with at first, |sin θ|
    /// was 0.58 and the raster closed into ribbons. A small non-zero centre keeps the
    /// rows off exact pixel-row alignment.
    public var yawCentre: Float
    /// Half-range of the heading oscillation, radians. BOUNDED on purpose: a free
    /// drift walks back into the raster-closing regime within seconds, so the fix has
    /// to bound the angle rather than just re-centre it. `sin(0.16) ≈ 0.16`, so the
    /// worst-case perpendicular fattening stays under a fifth of the spread.
    public var yawSwing: Float
    /// Period of the heading oscillation, seconds. MEN.2b replaces the whole camera
    /// with the source's own behaviour.
    public var yawPeriod: Float

    public init(
        gridN: Int = 45,
        damping: Float = 0.995,
        heightScale: Float = 0.32,
        spread: Float = 0.070,
        spreadMode: Int = 0,
        swellAmplitude: Float = 0.10,
        slopeLag: Float = 0.35,
        slopeGain: Float = 34.0,
        yawCentre: Float = 0.06,
        yawSwing: Float = 0.16,
        yawPeriod: Float = 44.0
    ) {
        self.gridN = gridN
        self.damping = damping
        self.heightScale = heightScale
        self.spread = spread
        self.spreadMode = spreadMode
        self.swellAmplitude = swellAmplitude
        self.slopeLag = slopeLag
        self.slopeGain = slopeGain
        self.yawCentre = yawCentre
        self.yawSwing = yawSwing
        self.yawPeriod = yawPeriod
    }
}

// MARK: - MeniscusSurface

public final class MeniscusSurface: ParticleGeometry, @unchecked Sendable {

    public let configuration: MeniscusConfiguration
    /// The surface is one coupled field — there is nothing to decimate, so the
    /// budget governor's fraction is accepted and ignored (the `CymaticSand`
    /// precedent).
    public var activeParticleFraction: Float = 1.0

    /// Serpentine-ordered path samples, consumed directly by the vertex shader.
    public let pointBuffer: MTLBuffer
    private let linePipeline: MTLRenderPipelineState?

    // Height field — two buffers, ping-ponged by the wave step.
    private var current: [Float]
    private var previous: [Float]

    // Camera + clock.
    private var elapsed: Float = 0

    /// Wall-clock milliseconds the most recent `update` spent in the wave step +
    /// serialization. Read by `MeniscusMultiFrameRenderTest` for the task-1c
    /// frame-budget evidence.
    public private(set) var lastStepMilliseconds: Double = 0

    public var pointCount: Int { configuration.gridN * configuration.gridN }
    /// Segments joining consecutive path samples. Each becomes one spread quad.
    public var segmentCount: Int { max(0, pointCount - 1) }

    public init(
        device: MTLDevice,
        library: MTLLibrary,
        configuration: MeniscusConfiguration = .init(),
        pixelFormat: MTLPixelFormat? = nil
    ) throws {
        self.configuration = configuration
        let cells = configuration.gridN * configuration.gridN
        self.current = [Float](repeating: 0, count: cells)
        self.previous = [Float](repeating: 0, count: cells)

        guard let points = device.makeBuffer(
            length: cells * MemoryLayout<MeniscusPoint>.stride,
            options: .storageModeShared
        ) else {
            throw MeniscusError.bufferAllocationFailed
        }
        self.pointBuffer = points

        if let pixelFormat {
            guard let vfn = library.makeFunction(name: "meniscus_line_vertex"),
                  let ffn = library.makeFunction(name: "meniscus_line_fragment") else {
                throw MeniscusError.functionNotFound("meniscus_line_vertex/meniscus_line_fragment")
            }
            let desc = MTLRenderPipelineDescriptor()
            desc.vertexFunction = vfn
            desc.fragmentFunction = ffn
            let attachment = desc.colorAttachments[0]
            attachment?.pixelFormat = pixelFormat
            // MAX blending, not additive. The source's comp stage spreads the lines
            // with a max-dilation along screen X (`MENISCUS_PLAN.md` §3); drawing
            // overlapping spread quads under `.max` reproduces exactly that
            // morphological union, and — unlike additive — overlapping quads cannot
            // accumulate into a blown-out sheet, so the spread is flash-safe by
            // construction rather than by a clamp.
            attachment?.isBlendingEnabled = true
            attachment?.rgbBlendOperation = .max
            attachment?.alphaBlendOperation = .max
            attachment?.sourceRGBBlendFactor = .one
            attachment?.destinationRGBBlendFactor = .one
            attachment?.sourceAlphaBlendFactor = .one
            attachment?.destinationAlphaBlendFactor = .one
            self.linePipeline = try device.makeRenderPipelineState(descriptor: desc)
        } else {
            self.linePipeline = nil
        }
        meniscusLogger.info(
            "Meniscus surface: \(configuration.gridN)×\(configuration.gridN) grid, \(cells) path samples")
    }

    // MARK: - ParticleGeometry

    public func update(features: FeatureVector, stemFeatures: StemFeatures, commandBuffer: MTLCommandBuffer) {
        let started = DispatchTime.now().uptimeNanoseconds

        var dt = features.deltaTime
        if !(dt > 0) { dt = 1.0 / 60.0 }
        dt = min(dt, 1.0 / 30.0)
        elapsed += dt

        stepWave()
        serializeSerpentinePath()

        lastStepMilliseconds = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
    }

    public func render(encoder: MTLRenderCommandEncoder, features: FeatureVector) {
        guard let state = linePipeline, segmentCount > 0 else { return }
        var cfg = makeConfig(aspect: max(features.aspectRatio, 0.01))
        encoder.setRenderPipelineState(state)
        encoder.setVertexBuffer(pointBuffer, offset: 0, index: 0)
        encoder.setVertexBytes(&cfg, length: MemoryLayout<MeniscusConfig>.stride, index: 1)
        // 6 vertices per segment — two triangles forming the spread quad.
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: segmentCount * 6)
    }

    /// Reset the surface at track change (the `CymaticSandGeometry` precedent).
    public func reset() {
        for i in current.indices { current[i] = 0; previous[i] = 0 }
        elapsed = 0
    }

    // MARK: - Wave step

    /// One step of the standard two-buffer wave propagation on a torus.
    ///
    /// Written from first principles, not transcribed (D-116 bullet 1). The
    /// discrete wave equation `h(t+1) = 2h(t) − h(t−1) + c²∇²h` with the 4-neighbour
    /// Laplacian `∇²h ≈ Σn − 4h` and `c² = ½` collapses to
    /// `h(t+1) = 2·mean(neighbours) − h(t−1)`; the damping factor is what makes it
    /// water rather than a lossless membrane.
    private func stepWave() {
        let side = configuration.gridN
        guard side > 2 else { return }
        let damping = configuration.damping

        current.withUnsafeBufferPointer { curBuf in
            previous.withUnsafeMutableBufferPointer { prevBuf in
                guard let src = curBuf.baseAddress, let dst = prevBuf.baseAddress else { return }
                for row in 0..<side {
                    // Torus wrap — the source simulates on a torus, so ripples
                    // leaving one edge re-enter at the other rather than reflecting.
                    let up = ((row + side - 1) % side) * side
                    let down = ((row + 1) % side) * side
                    let here = row * side
                    for col in 0..<side {
                        let left = (col + side - 1) % side
                        let right = (col + 1) % side
                        let mean = (src[here + left] + src[here + right]
                                    + src[up + col] + src[down + col]) * 0.25
                        // `dst` (the PREVIOUS field) is overwritten in place with the
                        // NEW height: after the swap below it becomes `current` and the
                        // old `current` becomes `previous`. No third buffer.
                        dst[here + col] = (2 * mean - dst[here + col]) * damping
                    }
                }
            }
        }
        swap(&current, &previous)
    }

    // MARK: - Serialization

    /// Walk the grid in serpentine row order and write the path samples the vertex
    /// shader consumes: display height (sim + the MEN.2a placeholder swell) and the
    /// slope term the shading reads.
    ///
    /// The slope is `h − s`, where `s` is a one-sample-lagged IIR of the height
    /// taken ALONG THE PATH — the source's own construction (`MENISCUS_PLAN.md`
    /// §3), and the reason crests read near-white while the trough two samples away
    /// reads near-black (trait T3, reference `07`).
    private func serializeSerpentinePath() {
        let side = configuration.gridN
        guard side > 0 else { return }
        let lag = configuration.slopeLag
        let swell = configuration.swellAmplitude
        let clock = elapsed
        let span = Float(max(side - 1, 1))

        let ptr = pointBuffer.contents().bindMemory(to: MeniscusPoint.self, capacity: pointCount)
        var smoothed: Float = 0
        var index = 0

        for row in 0..<side {
            let rowBase = row * side
            let reversed = (row % 2) == 1
            let rowFrac = Float(row) / span
            for step in 0..<side {
                let col = reversed ? (side - 1 - step) : step
                let colFrac = Float(col) / span

                // MEN.2a PLACEHOLDER ONLY (task 6) — a standing swell added at DISPLAY
                // time, never into the sim state, so the wave field MEN.2b inherits is
                // untouched and this is one expression to delete.
                //
                // THREE wavelengths, not one. A single long wave gives the plate a
                // smooth tilt with near-constant slope everywhere, and a constant slope
                // is a flat grey sheet under T3's shading — "a soft, evenly-lit version
                // of this looks like fabric, not water" (reference README, `07`). The
                // mid and short terms put crests and troughs a couple of samples apart
                // so the shading has something to resolve. Temporal rates stay slow:
                // §7 R6's recovery for a swell that reads frozen is MORE SPATIAL
                // VARIATION, never a faster swell.
                let swellTerm = swell * (
                    sin(colFrac * 2.1 + clock * 0.31) * cos(rowFrac * 1.6 - clock * 0.23)
                    + 0.55 * sin((colFrac * 5.3 - rowFrac * 4.1) + clock * 0.19)
                    + 0.30 * cos((colFrac * 9.7 + rowFrac * 8.3) - clock * 0.27))

                let height = current[rowBase + col] + swellTerm
                smoothed += (height - smoothed) * lag
                ptr[index] = MeniscusPoint(height: height, slope: height - smoothed)
                index += 1
            }
        }
    }

    // MARK: - Helpers

    /// Heading as a BOUNDED oscillation rather than a free drift. A free drift walks
    /// back into the raster-closing angle within seconds, so the heading has to be
    /// bounded, not merely re-centred (see `yawSwing`).
    private var currentYaw: Float {
        let omega = 2 * Float.pi / max(configuration.yawPeriod, 0.001)
        return configuration.yawCentre + configuration.yawSwing * sin(elapsed * omega)
    }

    private func makeConfig(aspect: Float) -> MeniscusConfig {
        MeniscusConfig(
            gridN: UInt32(configuration.gridN),
            pointCount: UInt32(pointCount),
            spreadMode: UInt32(configuration.spreadMode),
            spread: configuration.spread,
            yaw: currentYaw,
            // Low oblique (trait T2) — never top-down, never edge-on. Held fixed at
            // MEN.2a; the source's angle integration arrives at MEN.2b.
            //
            // The pitch must stay UNDER the vertical half-FOV `atan(0.5 / focal)`, or
            // the horizon leaves the frame and the ground plane can never be seen —
            // which is exactly what the MEN.2a first render did (0.38 rad against a
            // 0.32 rad half-FOV). At focal 1.0 the half-FOV is 0.46 rad, so 0.30 puts
            // the horizon about a fifth of the way down the frame and leaves the dark
            // void between horizon and plate that carries trait T5.
            pitch: 0.30,
            // FRAMING. References `01` and `02` fill the frame — the plate's near
            // corner runs off the edge. At the MEN.2a values (1.90 / 0.90) the plate
            // sat small and centred with dead frame all round it. Closer and lower
            // pushes the near edge past the bottom and the near corners past the
            // sides, while the far edge still lands below the horizon so the dark void
            // that carries trait T5 survives.
            camDist: 1.45,
            camHeight: 0.72,
            focal: 1.0,
            heightScale: configuration.heightScale,
            slopeGain: configuration.slopeGain,
            aspect: aspect,
            brightness: 1.0,
            lightDir: 0.6)
    }
}

// MARK: - Errors

public enum MeniscusError: Error, Sendable {
    case bufferAllocationFailed
    case functionNotFound(String)
}
