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
    private var current: [Float]
    private var previous: [Float]

    // Clock, and the ported camera (MeniscusCamera.swift).
    private var elapsed: Float = 0
    private var camera = MeniscusCamera()
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
    private func serializeSerpentinePath(intensity: Float) {
        // THE SWELL IS THE SILENCE STATE, NOT A CONSTANT BED.
        //
        // MEN.2a introduced it as "a placeholder to satisfy D-037 … keep it cheap and keep
        // it removable", and it was never removed when real drops arrived. Measured:
        // autonomous swell amplitude 0.0540 against 0.0001 from the entire audio path —
        // the placeholder is 540x everything the music does, so the music contributed
        // ~0 % of what was on screen. That is exactly Matt's "a movie playing with
        // background music", and it is why four rounds of drop-TIMING work changed nothing
        // a viewer could see: the drops were correct and inaudible under it.
        //
        // It now fades out as the music comes up, so it does what §4 actually specifies —
        // "silence / cold start: a slow standing swell … never black" — and nothing more.
        let swellGate = max(0, 1 - camera.volumeEnvelope * configuration.swellFadeRate)
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
                let swellTerm = swell * swellGate * (
                    sin(colFrac * 2.1 + clock * 0.31) * cos(rowFrac * 1.6 - clock * 0.23)
                    + 0.55 * sin((colFrac * 5.3 - rowFrac * 4.1) + clock * 0.19)
                    + 0.30 * cos((colFrac * 9.7 + rowFrac * 8.3) - clock * 0.27))

                // §5's loudness row applied where it belongs: to WAVE AMPLITUDE, so the
                // whole sheet is calmer in quiet passages and choppier in loud ones.
                // Scaling only per-drop force (the first attempt) barely moved the needle
                // — per-hit deviation variance swamps it, r=0.13. The sheet's amplitude is
                // a global, visible property and it is what §5 actually names.
                let height = (current[rowBase + col] + swellTerm) * intensity
                smoothed += (height - smoothed) * lag
                ptr[index] = MeniscusPoint(height: height, slope: height - smoothed)
                index += 1
            }
        }
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
