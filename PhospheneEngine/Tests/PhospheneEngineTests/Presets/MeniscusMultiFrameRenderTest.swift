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
import AVFoundation
@testable import Audio
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

    /// Mean |Δheight| across the path PER SIMULATION FRAME, below which the surface is
    /// judged frozen.
    ///
    /// MEASURED ON THE SURFACE STATE, NOT ON PIXELS. The first version of this gate
    /// differenced composite frames and PASSED its own negative control
    /// (`MENISCUS_SWELL=0`, a dead flat field, scored 1.56 against a 0.35 floor)
    /// because the camera drifts every frame — so a frozen surface still moved pixels.
    /// A pixel metric under a moving camera cannot tell a live surface from a dead one,
    /// which is precisely the "frozen ribbon" class this harness exists to catch.
    ///
    /// PER FRAME, NOT PER CAPTURE. The second version divided nothing by the capture
    /// stride, so the measured value scaled with `MENISCUS_STRIDE` — it passed at the
    /// default 15, passed wider at 50, and FAILED at stride 1 on an identical preset.
    /// A gate whose verdict depends on a diagnostic knob is not a gate. The rate is
    /// stride-invariant; the floor sits an order of magnitude under the measured
    /// ~3.4e-4 and far above the exact 0 a frozen field produces.
    private static let motionFloor: Double = 0.00008

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
        // MEN.2b: freeze the camera for a still comparison. `MENISCUS_STILL=1` stops the
        // tumble and the distance oscillation so a frame can be diffed without the
        // camera moving underneath it.
        if ProcessInfo.processInfo.environment["MENISCUS_STILL"] == "1" {
            configuration.tumbleRate = 0
            configuration.camDistSwing = 0
        }
        if let dist = Float(ProcessInfo.processInfo.environment["MENISCUS_DIST"] ?? "") {
            configuration.camDistCentre = dist
        }
        if let gain = Float(ProcessInfo.processInfo.environment["MENISCUS_SLOPE_GAIN"] ?? "") {
            configuration.slopeGain = gain
        }
        // MEN.2b: `MENISCUS_TRACK=<fixture>` drives the render from REAL MUSIC through
        // the production FFT, which is the only way to see the ported drops — at silence
        // there is no spectrum and the surface falls back to the placeholder swell.
        let drive = try Self.makeAudioDrive(ctx, track: ProcessInfo.processInfo.environment["MENISCUS_TRACK"])
        let stemDrive: [StemFeatures]? = try ProcessInfo.processInfo.environment["MENISCUS_STEMS"]
            .map { try WitchlightFixtureDrive.load($0).stems }
        let surface = try MeniscusSurface(
            device: ctx.device, library: lib.library,
            configuration: configuration, pixelFormat: ctx.pixelFormat,
            spectrum: drive?.spectrum)

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
        var intensitySamples: [(Double, Double)] = []

        for frame in 0..<Self.frameCount {
            var features = FeatureVector()
            features.time = Float(frame) * dt
            features.deltaTime = dt
            features.aspectRatio = Float(Self.width) / Float(Self.height)
            var stems = StemFeatures.zero
            if let drive { drive.advance(frame: frame, into: &features) }
            // MEN.3: real stems for the stem-region placement. `MENISCUS_STEMS=<fixture>`
            // uses the committed route-coverage stems rather than synthesis (FA #27).
            if let stemDrive, frame < stemDrive.count { stems = stemDrive[frame] }

            guard let cmd = ctx.commandQueue.makeCommandBuffer() else { continue }
            surface.update(features: features, stemFeatures: stems, commandBuffer: cmd)
            stepMilliseconds.append(surface.lastStepMilliseconds)
            // EVERY frame, not only captured ones: the reference smoothing below uses a
            // per-frame constant, and sampling at the capture stride silently turned a
            // 0.35 s envelope into an effective 5 s one — the comparison, not the route,
            // was what scored 0.51.
            intensitySamples.append((Double(surface.surfaceIntensity),
                                     Double((features.bass + features.mid + features.treble) / 3)))

            let sampled = frame % Self.captureStride == 0 || frame == Self.frameCount - 1
            Self.encode(cmd, into: target, preset: preset, audio: audio,
                        features: features, surface: surface)
            if sampled {
                // Same geometry, backdrop only — since MEN.2b the backdrop is drawn by
                // the geometry, so passing `nil` here would remove the entire scene and
                // the metric would stop isolating the line surface.
                surface.backdropOnlyForDiagnostics = true
                Self.encode(cmd, into: backdropOnly, preset: preset, audio: audio,
                            features: features, surface: surface)
                surface.backdropOnlyForDiagnostics = false
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
                // Normalised to a PER-SIMULATION-FRAME rate so the gate reads the same
                // at any capture stride.
                heightDeltas.append(
                    Self.meanAbsoluteHeightDelta(heights, previousHeights) / Double(Self.captureStride))
            }
            previousPixels = pixels
            previousHeights = heights
            if let outputDirectory {
                Self.writePNG(pixels, to: outputDirectory,
                              name: "meniscus_\(String(format: "%05d", frame)).png")
            }
        }

        // T4: the source is a CALM field with one or two active ripple systems. This
        // measures how much of the grid is actually moving — the trait, directly.
        let finalHeights = Self.readHeights(surface)
        let peak = finalHeights.map { abs($0) }.max() ?? 0
        let rms = (finalHeights.map { Double($0 * $0) }.reduce(0, +) / Double(max(finalHeights.count, 1))).squareRoot()
        let disturbed = Double(finalHeights.filter { abs($0) > max(peak * 0.15, 1e-4) }.count)
                      / Double(max(finalHeights.count, 1))
        Self.report(lumas: lumas, pixelDeltas: pixelDeltas, heightDeltas: heightDeltas,
                    concentration: (disturbed, rms, Double(peak)),
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
            the surface is frozen: mean |Δheight| per frame \
            \(String(format: "%.6f", meanHeightDelta)) is under the \(Self.motionFloor) floor. \
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
        // An ABSOLUTE floor, not a fraction of the frame. The question this gate asks is
        // "did the line surface reach the screen at all" — a fraction of frame area
        // silently also encodes how THICK the lines are, so narrowing the spread to stop
        // the raster welding shut (MEN.3) tripped it at 1562 px on a perfectly good
        // render. Presence is what is being gated; line weight is a look decision and
        // does not belong in it.
        #expect(smallestFootprint > 400, """
            the surface's on-screen footprint fell to \(smallestFootprint) px — the line \
            geometry is not reaching the encoder, or it is projecting off-frame. The height \
            field can be perfectly alive while nothing is drawn.
            """)

        // --- (d) §5's loudness row reaches the SURFACE --------------------------------
        // Matt, live 2026-08-04: "nothing tied to the intensity of the music, so the drops
        // look the same regardless of whether the music is quiet / loud". Only asserted
        // when the drive actually varies the loudness — at silence there is nothing to
        // correlate against and the check would be vacuous.
        if intensitySamples.count > 8 {
            // Compare against a SIMILARLY SMOOTHED loudness. §5 puts this row on a ~1 s
            // timescale, so the envelope lags on purpose; scoring it against instantaneous
            // loudness would count that intended lag as a failure. Smoothing both sides
            // isolates "does the route work" from "does it lag", which is the question.
            var smoothed = 0.0
            let loudValues = intensitySamples.map { sample -> Double in
                smoothed += (sample.1 - smoothed) * 0.05
                return smoothed
            }
            let spread = (loudValues.max() ?? 0) - (loudValues.min() ?? 0)
            if spread > 0.05 {
                let amp = intensitySamples.map(\.0)
                // SPEARMAN (rank) correlation, not Pearson. `surfaceIntensity` clamps at
                // its ceiling on purpose, and a monotone nonlinearity depresses Pearson
                // while the behaviour is exactly right — measured 0.70 against a 0.70 bar
                // purely from the clamp and the intended lag. Ranking is invariant to any
                // monotone transform, so it scores the thing actually being asserted:
                // does a louder passage produce a bigger-amplitude surface.
                func ranks(_ values: [Double]) -> [Double] {
                    let order = values.indices.sorted { values[$0] < values[$1] }
                    var out = [Double](repeating: 0, count: values.count)
                    for (rank, index) in order.enumerated() { out[index] = Double(rank) }
                    return out
                }
                let meanAmpRaw = amp.reduce(0, +) / Double(amp.count)
                let rankedAmp = ranks(amp), rankedLoud = ranks(loudValues)
                let meanA = rankedAmp.reduce(0, +) / Double(rankedAmp.count)
                let meanL = rankedLoud.reduce(0, +) / Double(rankedLoud.count)
                let cov = zip(rankedAmp, rankedLoud).map { ($0 - meanA) * ($1 - meanL) }.reduce(0, +)
                let sdA = rankedAmp.map { ($0 - meanA) * ($0 - meanA) }.reduce(0, +).squareRoot()
                let sdL = rankedLoud.map { ($0 - meanL) * ($0 - meanL) }.reduce(0, +).squareRoot()
                let r = cov / max(sdA * sdL, 1e-9)
                print(String(format: "[meniscus-intensity] Spearman r=%+.3f · intensity %.2f..%.2f (mean %.2f) · loudness %.2f..%.2f",
                             r, amp.min() ?? 0, amp.max() ?? 0, meanAmpRaw, loudValues.min() ?? 0, loudValues.max() ?? 0))
                #expect(r > 0.7, """
                    surface amplitude tracks loudness at only r=\(String(format: "%.2f", r)). \
                    §5: "the whole sheet is calmer in quiet passages and choppier in loud \
                    ones" — without it the surface looks identical loud or quiet, which is \
                    what Matt reported live.
                    """)
            }
        }

        // --- (e) the frame is a real image, not a constant field ---------------------
        #expect(Self.isNonConstant(previousPixels), "the final frame is a constant field")
    }

    // MARK: - Real-music drive

    /// Decodes a committed fixture and republishes its spectrum through the production
    /// `FFTProcessor` each frame, into the same `.storageModeShared` buffer shape the app
    /// hands the geometry. Band energies are derived from that spectrum so the camera and
    /// the brightness gate respond too — coarse, but taken from the real signal rather
    /// than hand-authored (FA #27).
    final class AudioDrive {
        let spectrum: UMABuffer<Float>
        private let samples: [Float]
        private let sampleRate: Float
        private let fft: FFTProcessor
        private let hop: Int

        init(ctx: MetalContext, url: URL) throws {
            let file = try AVAudioFile(forReading: url)
            let format = file.processingFormat
            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length)),
                  let _ = try? file.read(into: buffer),
                  let channel = buffer.floatChannelData?[0] else {
                throw MeniscusHarnessError.setupFailed("decode \(url.lastPathComponent)")
            }
            samples = Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
            sampleRate = Float(format.sampleRate)
            hop = Int(sampleRate / 60)
            fft = try FFTProcessor(device: ctx.device)
            spectrum = fft.magnitudeBuffer
        }

        func advance(frame: Int, into features: inout FeatureVector) {
            let start = (frame * hop) % max(samples.count - FFTProcessor.fftSize, 1)
            _ = fft.process(samples: Array(samples[start..<(start + FFTProcessor.fftSize)]),
                            sampleRate: sampleRate)
            let bins = fft.magnitudeBuffer.pointer
            func band(_ lo: Int, _ hi: Int) -> Float {
                var total: Float = 0
                for i in lo..<hi { total += bins[i] }
                return min(1, total / Float(hi - lo) * 40)
            }
            features.bass = band(1, 20)
            features.mid = band(20, 90)
            features.treble = band(90, 300)
            features.bassDev = features.bass
            features.beatComposite = features.bass
        }
    }

    private static func makeAudioDrive(_ ctx: MetalContext, track: String?) throws -> AudioDrive? {
        guard let track else { return nil }
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/tempo/\(track).m4a")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw MeniscusHarnessError.setupFailed("fixture \(url.path) — run Scripts/fetch_tempo_fixtures.sh")
        }
        return try AudioDrive(ctx: ctx, url: url)
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
        concentration: (disturbed: Double, rms: Double, peak: Double),
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
            format: "[meniscus-t4] disturbed %.0f%% of grid · rms %.3f · peak %.3f\n"
                  + "[meniscus-motion] surface |Δheight|/frame %.6f (GATED) · composite Δpx mean %.3f "
                  + "(evidence only — includes camera drift)",
            concentration.disturbed * 100, concentration.rms, concentration.peak,
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
