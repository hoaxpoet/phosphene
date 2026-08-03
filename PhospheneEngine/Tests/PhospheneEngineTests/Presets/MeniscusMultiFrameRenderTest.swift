// MeniscusMultiFrameRenderTest — the multi-frame gate for the Meniscus surface (MEN.2a).
//
// WHY THIS EXISTS. Meniscus's subject is a SIMULATION: the visible frame is one step
// of a wave field that only means anything in sequence. A single-frame test proves the
// shader compiles and nothing else — it cannot tell a live surface from a frozen one,
// and "frozen" is the specific failure `MENISCUS_PLAN.md` §7 R6 names (a swell slow
// enough to read as calm also reads as dead). Written BEFORE the geometry, per the
// production-pipeline testing obligation.
//
// DISPATCH PATH EXERCISED — the encode sequence `RenderPipeline.drawParticleMode` runs
// for every `feedback + particles` preset:
//
//   per frame:  MeniscusSurface.update(features:stemFeatures:commandBuffer:)   [the sim step]
//               → render encoder → preset triangle (`meniscus_ground_fragment`) [backdrop]
//               → MeniscusSurface.render(encoder:features:)                     [the surface]
//
// WHAT THIS DOES AND DOES NOT VERIFY. It drives the same encode ORDER and the same
// pipeline states production uses, with one `MeniscusSurface` living across the whole
// run — which is what makes it a temporal test rather than 60 independent ones. It does
// NOT go through `RenderPipeline.renderFrame` itself, so the pass-routing decision
// (`passes: ["feedback","particles"]` → `drawParticleMode`) is covered by
// `ParticleDispatchRegistryTests` + `PresetLoaderSidecarTests`, not here.
//
// DRIVE — silence. MEN.2a has no audio coupling at all, so a fixture drive would add
// nothing; FA #27 bites when synthetic envelopes stand in for real music, and here
// there is no music to stand in for.

import Testing
import Foundation
import Metal
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import Renderer
@testable import Presets
@testable import Shared

// MARK: - MeniscusMultiFrameRenderTest

@Suite("Meniscus multi-frame surface render")
@MainActor
struct MeniscusMultiFrameRenderTest {

    private static let width = Int(ProcessInfo.processInfo.environment["MENISCUS_W"] ?? "") ?? 640
    private static let height = Int(ProcessInfo.processInfo.environment["MENISCUS_H"] ?? "") ?? 480
    /// `deltaTime` is clamped to 1/30 s inside `update` (production behaviour — a
    /// stalled frame must not explode the sim), so spanning more seconds means more
    /// frames, not a bigger step. The contact-sheet run raises this.
    private static let frameCount =
        Int(ProcessInfo.processInfo.environment["MENISCUS_FRAMES"] ?? "") ?? 90
    /// Write a PNG every Nth frame. 90 frames at 60 fps = 1.5 s of sim; the contact
    /// sheet needs ≥ 6 frames spanning ≥ 4 s, so the dump run raises `MENISCUS_DT`.
    private static let captureStride =
        Int(ProcessInfo.processInfo.environment["MENISCUS_STRIDE"] ?? "") ?? 15

    /// Mean |Δheight| across the path between consecutive captured frames, below which
    /// the surface is judged frozen.
    ///
    /// THIS IS MEASURED ON THE SURFACE STATE, NOT ON PIXELS, and that is the whole
    /// point. The first version of this gate differenced composite frames and PASSED
    /// its own negative control (`MENISCUS_SWELL=0`, a dead flat field, scored 1.56
    /// against a 0.35 floor) because the camera drifts every frame — so a completely
    /// frozen surface still moved pixels. A pixel metric under a moving camera cannot
    /// tell a live surface from a dead one, which is precisely the "frozen ribbon"
    /// class this harness exists to catch.
    private static let motionFloor: Double = 0.002

    // MARK: - The gate

    @Test("the surface renders non-black and keeps moving across 90 frames at silence")
    func surfaceRendersAndMoves() throws {
        let ctx = try MetalContext()
        let lib = try ShaderLibrary(context: ctx)
        let loader = PresetLoader(device: ctx.device, pixelFormat: ctx.pixelFormat, loadBuiltIn: true)
        let preset = try #require(loader.presets.first { $0.descriptor.name == "Meniscus" },
                                  "Meniscus did not load through the real PresetLoader")

        // MEN.2a task 1a A/B: MENISCUS_SPREAD_MODE=1 swaps the sideways spread from
        // screen-space X (the source's axis) to the segment's screen-space normal.
        var configuration = MeniscusConfiguration()
        if let mode = Int(ProcessInfo.processInfo.environment["MENISCUS_SPREAD_MODE"] ?? "") {
            configuration.spreadMode = mode
        }
        // MEN.2a §6 / R4: grid resolution is an authoring decision made from a contact
        // sheet, so the sweep is drivable without an edit.
        if let grid = Int(ProcessInfo.processInfo.environment["MENISCUS_GRID"] ?? "") {
            configuration.gridN = grid
        }
        // NEGATIVE CONTROL. `MENISCUS_SWELL=0` removes the only thing moving the
        // surface at MEN.2a, so the run SHOULD trip the motion floor. That is how this
        // gate is shown to be wired to something real rather than passing vacuously —
        // a stronger check than watching it fail before the preset existed, which only
        // proves the preset did not exist.
        if let swell = Float(ProcessInfo.processInfo.environment["MENISCUS_SWELL"] ?? "") {
            configuration.swellAmplitude = swell
        }
        // MEN.2a §9 DECISION-NEEDED: how soft the lines read is exactly this number,
        // so the soft/crisp comparison is a re-run rather than an edit.
        if let spread = Float(ProcessInfo.processInfo.environment["MENISCUS_SPREAD"] ?? "") {
            configuration.spread = spread
        }
        let surface = try MeniscusSurface(
            device: ctx.device, library: lib.library,
            configuration: configuration, pixelFormat: ctx.pixelFormat)

        let target = try Self.makeTexture(ctx)
        // Backdrop-only render of the SAME frame. Differencing against it isolates the
        // surface's own footprint from the ground/sky, so a bright backdrop cannot mask
        // a surface that never reached the encoder (the Witchlight precedent).
        let backdropOnly = try Self.makeTexture(ctx)
        let audio = try Self.makeAudioBuffers(ctx)
        let outputDirectory = try Self.makeOutputDirectory()

        // Silence, with only the clock advancing. `MENISCUS_DT` stretches the per-frame
        // step so a contact sheet can span several seconds without rendering 300 frames.
        let dt = Float(ProcessInfo.processInfo.environment["MENISCUS_DT"] ?? "") ?? (1.0 / 60.0)

        var previousPixels: [UInt8] = []
        var previousHeights: [Float] = []
        var pixelDeltas: [Double] = []
        var heightDeltas: [Double] = []
        var footprints: [Int] = []
        var lumas: [Double] = []
        var stepMilliseconds: [Double] = []

        for frame in 0..<Self.frameCount {
            var features = FeatureVector()
            features.time = Float(frame) * dt
            features.deltaTime = dt
            features.aspectRatio = Float(Self.width) / Float(Self.height)

            guard let cmd = ctx.commandQueue.makeCommandBuffer() else { continue }
            surface.update(features: features, stemFeatures: .zero, commandBuffer: cmd)
            stepMilliseconds.append(surface.lastStepMilliseconds)

            let sampled = frame % Self.captureStride == 0 || frame == Self.frameCount - 1
            Self.encode(cmd, into: target, preset: preset, audio: audio,
                        features: features, surface: surface)
            if sampled {
                Self.encode(cmd, into: backdropOnly, preset: preset, audio: audio,
                            features: features, surface: nil)
            }
            cmd.commit()
            cmd.waitUntilCompleted()
            #expect(cmd.status == .completed, "frame \(frame) failed to render")

            guard sampled else { continue }
            let pixels = Self.read(target)
            let heights = Self.readHeights(surface)
            lumas.append(Self.meanLuma(pixels))
            footprints.append(Self.footprint(pixels, Self.read(backdropOnly)))
            if !previousPixels.isEmpty {
                pixelDeltas.append(Self.meanAbsoluteDelta(pixels, previousPixels))
                heightDeltas.append(Self.meanAbsoluteHeightDelta(heights, previousHeights))
            }
            previousPixels = pixels
            previousHeights = heights
            if let outputDirectory {
                Self.writePNG(pixels, to: outputDirectory,
                              name: "meniscus_\(String(format: "%05d", frame)).png")
            }
        }

        Self.report(lumas: lumas, pixelDeltas: pixelDeltas, heightDeltas: heightDeltas,
                    footprints: footprints, stepMilliseconds: stepMilliseconds,
                    surface: surface, outputDirectory: outputDirectory)

        // --- (a) no frame is black (D-037) ------------------------------------------
        let darkest = try #require(lumas.min())
        #expect(darkest > 0.004, """
            a captured frame is black (mean luma \(String(format: "%.5f", darkest))). \
            D-037: silence must never render black, and the reference set carries the \
            failure explicitly as anti-reference 06 — the SOURCE does this and Meniscus \
            must not. Both layers should contribute: the ground fragment alone clears \
            the floor even before the surface draws.
            """)

        // --- (b) the SURFACE is not frozen (camera-independent) ----------------------
        #expect(!heightDeltas.isEmpty, "no inter-frame deltas were captured")
        let meanHeightDelta = heightDeltas.reduce(0, +) / Double(max(heightDeltas.count, 1))
        #expect(meanHeightDelta > Self.motionFloor, """
            the surface is frozen: mean |Δheight| across the path \
            \(String(format: "%.5f", meanHeightDelta)) is under the \(Self.motionFloor) floor. \
            Either the wave step is not advancing, or the serialization is not reaching the \
            point buffer, or the placeholder swell is too slow to read as alive \
            (`MENISCUS_PLAN.md` §7 R6 — the recovery is MORE SPATIAL VARIATION at the same \
            temporal rate, never a faster swell). Note this measures the surface STATE, so a \
            drifting camera cannot mask a dead field.
            """)

        // --- (c) the surface actually reached the screen ------------------------------
        // (b) alone would pass with the geometry never drawn — the CPU/GPU split the
        // Witchlight harness names ("the buffer may be accumulating while the render is
        // not"). Differencing against the backdrop-only render closes it.
        let smallestFootprint = try #require(footprints.min())
        #expect(smallestFootprint > Self.width * Self.height / 100, """
            the surface's on-screen footprint fell to \(smallestFootprint) px — the line \
            geometry is not reaching the encoder, or it is projecting off-frame. The height \
            field can be perfectly alive while nothing is drawn.
            """)

        // --- (d) the frame is a real image, not a constant field ---------------------
        #expect(Self.isNonConstant(previousPixels), "the final frame is a constant field")
    }

    // MARK: - Encode one frame (mirrors drawParticleMode)

    private static func encode(
        _ cmd: MTLCommandBuffer, into texture: MTLTexture,
        preset: PresetLoader.LoadedPreset, audio: (fft: MTLBuffer, waveform: MTLBuffer),
        features: FeatureVector, surface: MeniscusSurface?
    ) {
        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = texture
        rpd.colorAttachments[0].loadAction = .clear
        rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        rpd.colorAttachments[0].storeAction = .store
        guard let enc = cmd.makeRenderCommandEncoder(descriptor: rpd) else { return }
        var f = features
        var s = StemFeatures.zero
        enc.setRenderPipelineState(preset.pipelineState)
        enc.setFragmentBytes(&f, length: MemoryLayout<FeatureVector>.stride, index: 0)
        enc.setFragmentBuffer(audio.fft, offset: 0, index: 1)
        enc.setFragmentBuffer(audio.waveform, offset: 0, index: 2)
        enc.setFragmentBytes(&s, length: MemoryLayout<StemFeatures>.stride, index: 3)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        surface?.render(encoder: enc, features: features)
        enc.endEncoding()
    }

    // MARK: - Measurement

    /// The serialized path heights — the surface's own state, read straight out of the
    /// buffer the vertex shader consumes.
    private static func readHeights(_ surface: MeniscusSurface) -> [Float] {
        let ptr = surface.pointBuffer.contents()
            .bindMemory(to: MeniscusPoint.self, capacity: surface.pointCount)
        return (0..<surface.pointCount).map { ptr[$0].height }
    }

    /// Mean absolute per-channel difference, in 0–255 units. Reported as evidence, not
    /// asserted on: it conflates surface motion with camera drift.
    private static func meanAbsoluteDelta(_ a: [UInt8], _ b: [UInt8]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var total = 0.0
        for i in a.indices where i % 4 != 3 { total += Double(abs(Int(a[i]) - Int(b[i]))) }
        return total / Double(a.count / 4 * 3)
    }

    private static func meanAbsoluteHeightDelta(_ a: [Float], _ b: [Float]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var total = 0.0
        for i in a.indices { total += Double(abs(a[i] - b[i])) }
        return total / Double(a.count)
    }

    /// Pixels where the composite differs from the backdrop-only render — the surface's
    /// on-screen footprint.
    private static func footprint(_ withSurface: [UInt8], _ without: [UInt8]) -> Int {
        guard withSurface.count == without.count else { return 0 }
        var pixels = 0
        for i in stride(from: 0, to: withSurface.count, by: 4) {
            let magnitude = abs(Int(withSurface[i]) - Int(without[i]))
                + abs(Int(withSurface[i + 1]) - Int(without[i + 1]))
                + abs(Int(withSurface[i + 2]) - Int(without[i + 2]))
            if magnitude > 6 { pixels += 1 }
        }
        return pixels
    }

    private static func meanLuma(_ bgra: [UInt8]) -> Double {
        guard !bgra.isEmpty else { return 0 }
        var sum = 0.0
        for i in stride(from: 0, to: bgra.count, by: 4) {
            sum += (0.0722 * Double(bgra[i]) + 0.7152 * Double(bgra[i + 1]) + 0.2126 * Double(bgra[i + 2])) / 255.0
        }
        return sum / Double(bgra.count / 4)
    }

    private static func isNonConstant(_ bgra: [UInt8]) -> Bool {
        guard let first = bgra.first else { return false }
        return bgra.contains { $0 != first }
    }

    // MARK: - Evidence

    private static func report(
        lumas: [Double], pixelDeltas: [Double], heightDeltas: [Double],
        footprints: [Int], stepMilliseconds: [Double],
        surface: MeniscusSurface, outputDirectory: URL?
    ) {
        func mean(_ values: [Double]) -> Double {
            values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
        }
        print(String(
            format: "[meniscus] %d×%d grid · %d path samples · %d segments · spreadMode %d",
            surface.configuration.gridN, surface.configuration.gridN,
            surface.pointCount, surface.segmentCount, surface.configuration.spreadMode))
        print(String(
            format: "[meniscus] luma %.4f–%.4f · surface footprint %d–%d px",
            lumas.min() ?? 0, lumas.max() ?? 0, footprints.min() ?? 0, footprints.max() ?? 0))
        print(String(
            format: "[meniscus-motion] surface |Δheight| mean %.5f (GATED) · composite Δpx mean %.3f "
                  + "(evidence only — includes camera drift)",
            mean(heightDeltas), mean(pixelDeltas)))
        // MEN.2a task 1c evidence: the CPU wave step + serialization cost, which is the
        // whole basis for not putting the sim on the GPU.
        let sorted = stepMilliseconds.sorted()
        let median = sorted.isEmpty ? 0 : sorted[sorted.count / 2]
        print(String(
            format: "[meniscus-budget] CPU step+serialize: median %.4f ms, max %.4f ms over %d frames",
            median, sorted.last ?? 0, stepMilliseconds.count))
        if let outputDirectory {
            print("[meniscus] frames: \(outputDirectory.path)")
        }
    }

    // MARK: - Metal plumbing

    private static func makeTexture(_ ctx: MetalContext) throws -> MTLTexture {
        let d = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: ctx.pixelFormat, width: width, height: height, mipmapped: false)
        d.usage = [.renderTarget, .shaderRead]
        d.storageMode = .shared
        guard let t = ctx.device.makeTexture(descriptor: d) else {
            throw MeniscusHarnessError.setupFailed("output texture")
        }
        return t
    }

    private static func makeAudioBuffers(_ ctx: MetalContext) throws -> (fft: MTLBuffer, waveform: MTLBuffer) {
        let stride = MemoryLayout<Float>.stride
        guard let fft = ctx.makeSharedBuffer(length: 512 * stride),
              let waveform = ctx.makeSharedBuffer(length: 2048 * stride) else {
            throw MeniscusHarnessError.setupFailed("audio buffers")
        }
        return (fft, waveform)
    }

    /// `RENDER_VISUAL=1` dumps frames where `Scripts/compare_render.sh meniscus` looks
    /// for them: a fresh timestamped dir under `/tmp/phosphene_visual`, frames named
    /// `meniscus_*.png`. Returns nil when not dumping, so the gate costs nothing.
    private static func makeOutputDirectory() throws -> URL? {
        guard ProcessInfo.processInfo.environment["RENDER_VISUAL"] == "1" else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let url = URL(fileURLWithPath: "/tmp/phosphene_visual")
            .appendingPathComponent("meniscus_\(formatter.string(from: Date()))")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func writePNG(_ bgra: [UInt8], to directory: URL, name: String) {
        var rgba = bgra
        for i in stride(from: 0, to: rgba.count, by: 4) { rgba.swapAt(i, i + 2) }
        guard let provider = CGDataProvider(data: Data(rgba) as CFData),
              let image = CGImage(
                width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent),
              let destination = CGImageDestinationCreateWithURL(
                directory.appendingPathComponent(name) as CFURL,
                UTType.png.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
    }

    private static func read(_ texture: MTLTexture) -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        texture.getBytes(&pixels, bytesPerRow: width * 4,
                         from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        return pixels
    }
}

// MARK: - Errors

enum MeniscusHarnessError: Error {
    case setupFailed(String)
}
