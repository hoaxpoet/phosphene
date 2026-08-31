// WitchlightStrokeAccumulationTest — the multi-frame gate for Witchlight's whole subject.
//
// WHY THIS EXISTS. Witchlight's subject is an ACCUMULATING TRAIL: the visible figure at
// any instant is exactly the last 30 s of harmonic motion (WITCHLIGHT_DESIGN §3.3). A
// single-frame test proves nothing about that. The reference README names the failure
// class directly — "The frozen ribbon: a stroke that stops accumulating (input stalls, or
// the trail's age window exceeds the emission rate) reads as a static decoration.
// `RouteCoverageTests` catches a dead route; a *stalled* one needs the multi-frame
// harness." This is that harness, and it is written BEFORE the look work rather than
// after, per the preset-session discipline rule.
//
// DISPATCH PATH EXERCISED — the same sequence `RenderPipeline.drawParticleMode` runs for
// every `feedback + particles` preset, and the sequence Filigree's flash entry uses:
//
//   per frame:  WitchlightStroke.update(features:stemFeatures:commandBuffer:)   [the tick]
//               → render encoder → preset triangle (`witchlight_sky_fragment`)   [backdrop]
//               → WitchlightStroke.render(encoder:features:)                     [4 draws]
//
// No per-frame clear of preset state, no fresh geometry per frame: one `WitchlightStroke`
// lives across the whole run, which is what makes this a temporal test rather than 1 288
// independent single-frame tests.
//
// DRIVE — the real committed fixtures via `WitchlightFixtureDrive`, never synthetic
// envelopes (FA #27), and carrying every declared route (the FLY.6 / Faraday trap).
//
// METRIC — the ribbon's own footprint, isolated by differencing each composite frame
// against a sky-only render of the SAME frame. That is what "the trail accumulated" means
// in pixels; measuring the composite alone would let a bright star field mask a dead
// ribbon. A stalled trail flattens the growth curve and trips `trailGrewOnScreen`.

import Testing
import Foundation
import Metal
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import Renderer
@testable import Presets
@testable import Shared

// MARK: - WitchlightStrokeAccumulationTest

@Suite("Witchlight multi-frame trail accumulation")
@MainActor
struct WitchlightStrokeAccumulationTest {

    /// 480×270 keeps the gate fast. `WITCHLIGHT_W`/`WITCHLIGHT_H` raise it for look review —
    /// bead size is a fraction of frame height, so judging the ribbon's grain at 270 px tall
    /// judges it at a resolution nobody will ever watch it at.
    private static let width = Int(ProcessInfo.processInfo.environment["WITCHLIGHT_W"] ?? "") ?? 480
    private static let height = Int(ProcessInfo.processInfo.environment["WITCHLIGHT_H"] ?? "") ?? 270
    /// Render (not tick) every Nth frame. The path advances on EVERY frame; only the
    /// pixel measurement is sampled, so the temporal behaviour is unabridged.
    private static let renderStride = 24

    // MARK: - The gate

    @Test("the trail accumulates over 30 s of real music, in the buffer and on screen",
          arguments: WitchlightFixtureDrive.tracks)
    func trailAccumulates(track: String) throws {
        let drive = try WitchlightFixtureDrive.load(track, aspect: Float(Self.width) / Float(Self.height))
        #expect(drive.features.count > 900, "\(track): fixture too short to reach the 30 s trail window")

        let ctx = try MetalContext()
        let lib = try ShaderLibrary(context: ctx)
        let loader = PresetLoader(device: ctx.device, pixelFormat: ctx.pixelFormat, loadBuiltIn: true)
        let preset = try #require(loader.presets.first { $0.descriptor.name == "Witchlight" },
                                  "Witchlight did not load through the real PresetLoader")
        // WL.3 spike: WITCHLIGHT_MODE=curvature swaps the steer model (default = shipped).
        var tuning = WitchlightTuning()
        switch ProcessInfo.processInfo.environment["WITCHLIGHT_MODE"] {
        case "curvature": tuning.steerMode = .curvature
        case "deviation": tuning.steerMode = .curvatureDeviation
        default: break
        }
        if let gain = Float(ProcessInfo.processInfo.environment["WITCHLIGHT_C"] ?? "") {
            tuning.curvatureGain = gain
        }
        let stroke = try WitchlightStroke(
            device: ctx.device, library: lib.library,
            configuration: WitchlightConfiguration(tuning: tuning), pixelFormat: ctx.pixelFormat)

        let composite = try Self.makeTexture(ctx)
        let skyOnly = try Self.makeTexture(ctx)
        let audio = try Self.makeAudioBuffers(ctx)

        // Contact-sheet dump: WITCHLIGHT_FRAMES=/path swift test --filter Witchlight
        let outputDirectory = ProcessInfo.processInfo.environment["WITCHLIGHT_FRAMES"].map {
            URL(fileURLWithPath: $0).appendingPathComponent(track)
        }
        if let outputDirectory {
            try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        }

        var beadCounts: [Int] = []
        var ribbonPixels: [Int] = []
        var ribbonEnergy: [Double] = []
        var lastComposite = [UInt8]()

        for i in 0..<drive.features.count {
            var structure = StructuralPrediction()
            structure.sectionIndex = drive.sectionIndex[i]
            stroke.path.ingestStructure(structure)

            guard let cmd = ctx.commandQueue.makeCommandBuffer() else { continue }
            stroke.update(features: drive.features[i], stemFeatures: drive.stems[i], commandBuffer: cmd)

            let sampled = (i % Self.renderStride == 0) || i == drive.features.count - 1
            guard sampled else { cmd.commit(); continue }

            // Sky + ribbon (the live sequence), then sky alone (the reference).
            Self.encode(cmd, into: composite, preset: preset, audio: audio,
                        features: drive.features[i], stems: drive.stems[i], stroke: stroke)
            Self.encode(cmd, into: skyOnly, preset: preset, audio: audio,
                        features: drive.features[i], stems: drive.stems[i], stroke: nil)
            cmd.commit()
            cmd.waitUntilCompleted()
            #expect(cmd.status == .completed, "\(track): frame \(i) failed to render")

            if let outputDirectory { Self.writePNG(Self.read(composite), to: outputDirectory,
                                                   name: "\(track)_\(String(format: "%05d", i)).png") }
            let withRibbon = Self.read(composite)
            let without = Self.read(skyOnly)
            let footprint = Self.footprint(withRibbon, without)
            beadCounts.append(stroke.path.beads.count)
            ribbonPixels.append(footprint.pixels)
            ribbonEnergy.append(footprint.energy)
            lastComposite = withRibbon
        }

        try Self.report(track: track, stroke: stroke, drive: drive,
                        beadCounts: beadCounts, ribbonPixels: ribbonPixels, ribbonEnergy: ribbonEnergy)

        // --- The trail exists in the buffer and reached its window -------------------
        //
        // The floor is derived from the window the path is ACTUALLY carrying, not from a
        // fixed 1020: `there_there` contains a section boundary, and contracting the age
        // window by 30 % is the declared `trail_contraction` behaviour, not a stall. A
        // constant floor would have made a working route look like a defect.
        let finalBeads = try #require(beadCounts.last)
        let expectedBeads = Int(stroke.path.trailWindow * stroke.configuration.tuning.emissionHz)
        let floor = Int(Double(min(expectedBeads, drive.features.count)) * 0.85)
        #expect(finalBeads >= floor, """
            \(track): the trail stalled at \(finalBeads) beads after \(drive.features.count) frames \
            (~30 s of real music); the current \(String(format: "%.1f", stroke.path.trailWindow)) s window \
            at \(stroke.configuration.tuning.emissionHz) Hz should hold ~\(expectedBeads). This is the \
            "frozen ribbon" failure the reference README names — emission stopped, or the age window is \
            expiring beads faster than the pen lays them.
            """)
        let quarter = beadCounts[beadCounts.count / 4]
        #expect(finalBeads > quarter, "\(track): bead count did not grow past its quarter-way value")

        // --- The trail is visible on screen and GREW there ---------------------------
        let earlyPixels = ribbonPixels[ribbonPixels.count / 10]
        let latePixels = try #require(ribbonPixels.dropLast(2).max())
        #expect(earlyPixels > 0, "\(track): the ribbon drew nothing at all — the geometry never reached the encoder")
        #expect(latePixels > earlyPixels * 2, """
            \(track): the ribbon's on-screen footprint did not grow (\(earlyPixels) → \(latePixels) px). \
            The buffer may be accumulating while the render is not — exactly the split a CPU-only \
            assertion would miss, and the one that caught beads going sub-pixel under the auto-fit.
            """)

        // --- The composite is a real frame, not a degenerate one ---------------------
        #expect(Self.meanLuma(lastComposite) > 0.002, "\(track): final composite is black (D-037)")
        #expect(Self.isNonConstant(lastComposite), "\(track): final composite is a constant field")
    }

    // MARK: - Encode one frame (mirrors drawParticleMode)

    private static func encode(
        _ cmd: MTLCommandBuffer, into texture: MTLTexture,
        preset: PresetLoader.LoadedPreset, audio: (fft: MTLBuffer, waveform: MTLBuffer),
        features: FeatureVector, stems: StemFeatures, stroke: WitchlightStroke?
    ) {
        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = texture
        rpd.colorAttachments[0].loadAction = .clear
        rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        rpd.colorAttachments[0].storeAction = .store
        guard let enc = cmd.makeRenderCommandEncoder(descriptor: rpd) else { return }
        var f = features
        var s = stems
        enc.setRenderPipelineState(preset.pipelineState)
        enc.setFragmentBytes(&f, length: MemoryLayout<FeatureVector>.stride, index: 0)
        enc.setFragmentBuffer(audio.fft, offset: 0, index: 1)
        enc.setFragmentBuffer(audio.waveform, offset: 0, index: 2)
        enc.setFragmentBytes(&s, length: MemoryLayout<StemFeatures>.stride, index: 3)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        stroke?.render(encoder: enc, features: features)
        enc.endEncoding()
    }

    // MARK: - Measurement

    /// Pixels the ribbon changed, and how much light it added. Differencing against a
    /// sky-only render of the same frame isolates the subject from the backdrop.
    private static func footprint(_ withRibbon: [UInt8], _ without: [UInt8]) -> (pixels: Int, energy: Double) {
        var pixels = 0
        var energy = 0.0
        for i in stride(from: 0, to: withRibbon.count, by: 4) {
            let deltaB = Int(withRibbon[i]) - Int(without[i])
            let deltaG = Int(withRibbon[i + 1]) - Int(without[i + 1])
            let deltaR = Int(withRibbon[i + 2]) - Int(without[i + 2])
            let magnitude = abs(deltaB) + abs(deltaG) + abs(deltaR)
            if magnitude > 6 { pixels += 1 }
            energy += Double(magnitude) / 765.0
        }
        return (pixels, energy)
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
        track: String, stroke: WitchlightStroke, drive: WitchlightFixtureDrive.Drive,
        beadCounts: [Int], ribbonPixels: [Int], ribbonEnergy: [Double]
    ) throws {
        let path = stroke.path
        print(String(
            format: "[witchlight-accum] %@: %d frames · beads %d→%d · ribbon %d→%d px · energy %.1f→%.1f",
            track, drive.features.count, beadCounts.first ?? 0, beadCounts.last ?? 0,
            ribbonPixels.first ?? 0, ribbonPixels.last ?? 0,
            ribbonEnergy.first ?? 0, ribbonEnergy.last ?? 0))
        // WITCHLIGHT_DESIGN §3.1(b) requires WL.2 to report the clamp fraction per capture:
        // > 80 % means the figure has degenerated to a circle and `steerGain` comes down.
        print(String(
            format: "[witchlight-steer] %@: turn-rate clamp %.1f %% of frames · turns %d · promotions %d "
                  + "· flares %d · sections %d · viewScale %.2f",
            track, path.clampedFraction * 100, path.turnCount, path.promotionCount,
            path.flareCount, path.sectionEventCount, path.viewScale))
        print(String(
            format: "[witchlight-travel] %@: phase travelled %.2f rad (%.2f circles) → heading turned %.2f rad "
                  + "(%.2f circles) at k=%.2f",
            track, path.phaseTravel, path.phaseTravel / (2 * .pi),
            path.headingTravel, path.headingTravel / (2 * .pi), stroke.configuration.tuning.steerGain))
        print(String(format: "[witchlight-shape] %@: heading monotonicity %.2f (1 = one-way spiral, 0 = reversing)",
                     track, path.headingMonotonicity))
    }

    // MARK: - Metal plumbing

    private static func makeTexture(_ ctx: MetalContext) throws -> MTLTexture {
        let d = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: ctx.pixelFormat, width: width, height: height, mipmapped: false)
        d.usage = [.renderTarget, .shaderRead]
        d.storageMode = .shared
        guard let t = ctx.device.makeTexture(descriptor: d) else {
            throw WitchlightHarnessError.setupFailed("output texture")
        }
        return t
    }

    private static func makeAudioBuffers(_ ctx: MetalContext) throws -> (fft: MTLBuffer, waveform: MTLBuffer) {
        let stride = MemoryLayout<Float>.stride
        guard let fft = ctx.makeSharedBuffer(length: 512 * stride),
              let waveform = ctx.makeSharedBuffer(length: 2048 * stride) else {
            throw WitchlightHarnessError.setupFailed("audio buffers")
        }
        return (fft, waveform)
    }

    /// BGRA8 → PNG. Diagnostic only; nothing in the gate depends on it.
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
                directory.appendingPathComponent(name) as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
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

enum WitchlightHarnessError: Error {
    case setupFailed(String)
}
