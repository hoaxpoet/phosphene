// MeniscusSurface — the serpentine projected line-strip water surface.
//
// A `ParticleGeometry` sibling (D-097) for Meniscus. Owns the height field, the
// two-buffer wave step, and the line + backdrop pipelines. Per frame: advance the
// camera (`MeniscusCamera`) → step the sim → serialize the grid into ONE serpentine
// path → draw the backdrop, then each path segment as a sideways-spread quad.
//
// WHY CPU, NOT COMPUTE (MEN.2a task 1c). The wave step is trivially parallel but also
// trivially small: §7 R4 says raising the resolution CLOSES the raster gaps that make
// the preset legible, so the grid can never grow to where a dispatch pays for itself —
// and drop placement is CPU-derived, so a drop stays a single `+=` with no upload path.
// Precedent: `MitosisGen2Geometry` (CPU) vs `CymaticSandGeometry` (compute).
//
// SERPENTINE LIVES ON THE CPU. The serialization loop emits points in traversal order
// (alternate rows reversed), so the vertex shader indexes the buffer linearly and
// carries no boustrophedon logic. The rounded turnaround caps at the margins
// (reference `07`, trait T1) fall out of the ordering; they are not drawn specially.
//
// MEN.2b PORTED the source's camera, hue rotation and volume brightness gate
// (`MeniscusCamera`), its cepstral drop placement (`MeniscusDrops`), and its damping.
// The damping is worth singling out: it is the source's frame-rate-normalised `dec_med`
// (~0.97 at 60 fps), not the 0.995 MEN.2a guessed, and that 6x difference is what makes
// the surface read as a CALM field with one or two active ripple systems (T4) instead of
// agitated everywhere — localisation is a property of damping, not of impact strength.
//
// See `docs/presets/MENISCUS_PLAN.md` §3 (decode) and §9 (corrections from the oracle).

import Metal
import Shared
import os.log

private let meniscusLogger = Logger(subsystem: "com.phosphene.renderer", category: "Meniscus")

// MARK: - MeniscusSurface

public final class MeniscusSurface: ParticleGeometry, @unchecked Sendable {

    public let configuration: MeniscusConfiguration
    /// The surface is one coupled field — there is nothing to decimate, so the
    /// budget governor's fraction is accepted and ignored (the `CymaticSand`
    /// precedent).
    public var activeParticleFraction: Float = 1.0

    /// Draw the backdrop but SKIP the line surface. Diagnostic only, for the harness's
    /// footprint metric: since MEN.2b the backdrop is drawn from here rather than from
    /// the preset fragment, so "render without the geometry" no longer isolates the
    /// surface — it removes the whole scene. This restores a meaningful reference frame.
    public var backdropOnlyForDiagnostics = false

    /// Serpentine-ordered path samples, consumed directly by the vertex shader.
    public let pointBuffer: MTLBuffer
    private let linePipeline: MTLRenderPipelineState?
    private let backdropPipeline: MTLRenderPipelineState?

    // Height field — two buffers, ping-ponged by the wave step.
    internal var current: [Float]
    internal var previous: [Float]

    // Clock, and the ported camera (MeniscusCamera.swift).
    internal var elapsed: Float = 0
    /// Continuous per-band envelopes driving the living swell (MEN.4c).
    internal var bandSwell = SIMD3<Float>(0, 0, 0)
    internal var camera = MeniscusCamera()
    private var drops = MeniscusDrops()
    private var stemDrops = MeniscusStemDrops()
    /// The live FFT magnitudes — the SAME `.storageModeShared` UMA buffer the
    /// fragment stages bind at slot 1, read here on the CPU. nil ⇒ no drops.
    private let spectrum: UMABuffer<Float>?

    /// Wall-clock milliseconds the most recent `update` spent in the wave step +
    /// serialization. Read by `MeniscusMultiFrameRenderTest` for the task-1c
    /// frame-budget evidence.
    public private(set) var lastStepMilliseconds: Double = 0

    /// §5's loudness → wave-amplitude coupling, on its own ~1 s timescale. Floored so
    /// quiet passages still ripple faintly rather than flattening (D-037 in spirit).
    public var surfaceIntensity: Float {
        let floor = configuration.stemIntensityFloor
        return floor + (1 - floor) * min(camera.volumeEnvelope / 0.45, 2.0)
    }

    /// Diagnostics: drops stamped on the most recent update, and their summed force.
    public var lastDropCount: Int { drops.lastDropCount }
    public var lastDropForce: Float { drops.lastDropForce }
    /// MEN.3 diagnostics: impact sites, and the per-region breakdown
    /// (drums / bass / vocals / other) the legibility test reads.
    public var lastStemSites: [Int] { stemDrops.lastSites }
    public var lastPerRegion: [Int] { stemDrops.lastPerRegion }

    public var pointCount: Int { configuration.gridN * configuration.gridN }
    /// Segments joining consecutive path samples. Each becomes one spread quad.
    public var segmentCount: Int { max(0, pointCount - 1) }

    public init(
        device: MTLDevice,
        library: MTLLibrary,
        configuration: MeniscusConfiguration = .init(),
        pixelFormat: MTLPixelFormat? = nil,
        spectrum: UMABuffer<Float>? = nil
    ) throws {
        self.configuration = configuration
        self.spectrum = spectrum
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

            // Backdrop: opaque, no blending — it replaces the preset fragment's output
            // wholesale, because it is the layer that has to see the live camera.
            guard let bvfn = library.makeFunction(name: "meniscus_backdrop_vertex"),
                  let bffn = library.makeFunction(name: "meniscus_backdrop_fragment") else {
                throw MeniscusError.functionNotFound("meniscus_backdrop_vertex/_fragment")
            }
            let bdesc = MTLRenderPipelineDescriptor()
            bdesc.vertexFunction = bvfn
            bdesc.fragmentFunction = bffn
            bdesc.colorAttachments[0]?.pixelFormat = pixelFormat
            self.backdropPipeline = try device.makeRenderPipelineState(descriptor: bdesc)
        } else {
            self.linePipeline = nil
            self.backdropPipeline = nil
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

        camera.advance(features: features, dt: dt, configuration: configuration)
        // Drops BEFORE the wave step, so an impact stamped this frame propagates on the
        // very next one rather than sitting still for a frame.
        if configuration.dropsEnabled, configuration.stemPlacement {
            // MEN.3 — the divergence axis. Each instrument owns a region of the surface.
            stemDrops.step(
                stems: stemFeatures,
                features: features,
                field: &current,
                dt: dt,
                configuration: configuration)
        } else if configuration.dropsEnabled, let spectrum {
            drops.step(
                spectrum: UnsafeBufferPointer(spectrum.pointer),
                field: &current,
                side: configuration.gridN,
                dt: dt,
                configuration: configuration)
        }
        // THE CONTINUOUS DRIVER (MEN.4c) — INTO THE SIM, not onto the display.
        let alpha = 1 - exp(-dt / 0.25)
        bandSwell.x += (min(max(features.bass, 0), 1.5) - bandSwell.x) * alpha
        bandSwell.y += (min(max(features.mid, 0), 1.5) * 3 - bandSwell.y) * alpha
        bandSwell.z += (min(max(features.treble, 0), 1.5) * 8 - bandSwell.z) * alpha
        driveContinuously(dt: dt)
        stepWave(dt: dt)
        serializeSerpentinePath(intensity: surfaceIntensity)

        lastStepMilliseconds = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
    }

    public func render(encoder: MTLRenderCommandEncoder, features: FeatureVector) {
        guard let state = linePipeline, segmentCount > 0 else { return }
        var cfg = makeConfig(aspect: max(features.aspectRatio, 0.01))

        // Backdrop FIRST, over whatever the preset fragment drew. It lives here rather
        // than in the preset fragment because it needs the LIVE camera: the particle
        // path binds no per-preset buffer, so MEN.2a mirrored the camera constants by
        // hand — survivable with a fixed camera, and immediately wrong once it tumbles.
        if let backdrop = backdropPipeline {
            encoder.setRenderPipelineState(backdrop)
            encoder.setFragmentBytes(&cfg, length: MemoryLayout<MeniscusConfig>.stride, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        }

        guard !backdropOnlyForDiagnostics else { return }
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
        camera.reset()
        drops.reset()
        stemDrops.reset()
    }

    // MARK: - Wave step

    /// One step of the standard two-buffer wave propagation on a torus.
    ///
    /// Written from first principles, not transcribed (D-116 bullet 1). The
    /// discrete wave equation `h(t+1) = 2h(t) − h(t−1) + c²∇²h` with the 4-neighbour
    /// Laplacian `∇²h ≈ Σn − 4h` and `c² = ½` collapses to
    /// `h(t+1) = 2·mean(neighbours) − h(t−1)`; the damping factor is what makes it
    /// water rather than a lossless membrane.
    private func stepWave(dt: Float) {
        let side = configuration.gridN
        guard side > 2 else { return }
        // DAMPING IS THE SOURCE'S `dec_med` = 1 - 0.06*30/fps, frame-rate normalised —
        // read from the source, not guessed. MEN.2a used 0.995, which decays to 1/e over
        // ~200 frames (3.3 s); dec_med is ~0.97 at 60 fps, ~33 frames (0.55 s). That 6x
        // difference is why the field stayed agitated EVERYWHERE regardless of drop
        // force: ripples crossed the whole torus before dying. Localisation — T4, "at any
        // moment most of the surface is quiet and one or two regions are actively
        // rippling" — is a property of the DAMPING, not of the impact strength.
        let fps = max(1 / max(dt, 1e-5), 1)
        let damping = configuration.damping * (1 - 1.8 / fps)

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
                        // SOFT CEILING (MEN.4c). The continuous drive adds a spatial
                        // pattern every frame, which is RESONANT FORCING: energy piles up
                        // at fixed antinodes without bound, and the render showed it as
                        // long spears shooting off the sheet — the surface tearing, not
                        // water. `tanh` leaves everything under the ceiling untouched and
                        // only bends the extremes, so ripple shape is unchanged and only
                        // the runaway is caught.
                        let updated = (2 * mean - dst[here + col]) * damping
                        let ceiling = configuration.heightCeiling
                        dst[here + col] = ceiling > 0
                            ? ceiling * tanh(updated / ceiling)
                            : updated
                    }
                }
            }
        }
        swap(&current, &previous)
    }

    // MARK: - Helpers

    private func makeConfig(aspect: Float) -> MeniscusConfig {
        let dist = camera.distance(configuration: configuration)
        // SPREAD AS A FRACTION OF PROJECTED ROW SPACING. The plate spans ~2 world
        // units, so it covers about `2 * focal / dist` in NDC, and one row is that over
        // `gridN`. Deriving the spread from that makes it scale-free: it tracks camera
        // distance (which is what the source's proximity-scaled dilation does) AND grid
        // resolution, so neither a dolly nor the still-open §6 resolution decision can
        // weld the raster shut.
        let rowSpacing = (2 * 1.0 / max(dist, 0.4)) / Float(max(configuration.gridN, 1))
        let spread = configuration.spreadTracksDistance
            ? configuration.spread * rowSpacing
            : configuration.spread
        return MeniscusConfig(
            gridN: UInt32(configuration.gridN),
            pointCount: UInt32(pointCount),
            spreadMode: UInt32(configuration.spreadMode),
            spread: spread,
            angleX: camera.angles.x,
            angleY: camera.angles.y,
            angleZ: camera.angles.z,
            camDist: dist,
            // The camera rides above the plate; the tumble carries the attitude, so
            // this only has to lift the eye off the water plane.
            camHeight: 0.72,
            focal: 1.0,
            heightScale: configuration.heightScale,
            slopeGain: configuration.slopeGain,
            aspect: aspect,
            brightness: camera.brightness,
            // Hue and brightness are camera-derived — see MeniscusCamera.
            hue: camera.hueTurns)
    }
}

// MARK: - Errors

public enum MeniscusError: Error, Sendable {
    case bufferAllocationFailed
    case functionNotFound(String)
}
