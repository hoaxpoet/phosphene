// FractalTreeMeshRenderTest — the render + contact-sheet harness for Fractal Tree (FTR.2).
//
// WHY THIS EXISTS. `PresetVisualReviewTests.renderPresetVisualReview` refuses mesh
// presets outright (`guard !preset.descriptor.passes.contains(.meshShader)`), so before
// this file there was NO way to see a rendered Fractal Tree frame from a test — and
// `PRESET_SESSION_CHECKLIST.md` Part 1 §6 requires a contact sheet BEFORE the first
// tuning commit. FTR.2 cannot produce its before-image without this.
//
// DISPATCH PATH EXERCISED — the same object → mesh → fragment dispatch production runs:
//
//   MeshGenerator(device:pipelineState:configuration:)   [wrapping PresetLoader's pipeline]
//     → draw(encoder:features:)                          [drawMeshThreadgroups on apple8+]
//
// It stops short of `RenderPipeline.drawWithMeshShader`, which additionally binds
// StemFeatures at FRAGMENT buffer(3) and the noise textures at 4–8. Fractal Tree reads
// none of those, so the omission changes nothing it can observe. (Worth recording, since
// D-212 says buffer(3) is "never set" on the mesh path: that is true of the object and
// mesh stages via `MeshGenerator.draw`, but the FRAGMENT stage IS bound by
// `drawWithMeshShader`. Only the object/mesh half is missing — FTR.4 scope.)
//
// DRIVE — real music, never hand-authored envelopes (FA #27). Frames come from the
// bundled `route_coverage` fixtures, sampled at percentiles of the primitive under
// review, plus an explicit all-zero frame for the D-037 silence check.

import Testing
import Foundation
import Metal
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import Renderer
@testable import Presets
@testable import PresetSessionReplay
@testable import Shared

// MARK: - FractalTreeMeshRenderTest

@Suite("Fractal Tree mesh render")
struct FractalTreeMeshRenderTest {

    private static let width = 640
    private static let height = 480

    /// Fixture the contact sheet is drawn from. `love_rehab` is the most dynamic of the
    /// three on the primitives FTR.2 routes from.
    private static let driveTrack = "love_rehab"

    // MARK: - The gate

    @Test("Fractal Tree renders a non-black tree across the drive range")
    func rendersAcrossDriveRange() throws {
        let ctx = try MetalContext()
        let loader = PresetLoader(device: ctx.device, pixelFormat: ctx.pixelFormat,
                                  loadBuiltIn: true)
        let preset = try #require(loader.presets.first { $0.descriptor.name == "Fractal Tree" },
                                  "Fractal Tree did not load through the real PresetLoader")
        #expect(preset.descriptor.passes.contains(.meshShader),
                "Fractal Tree must still be a mesh preset for this harness to mean anything")

        let generator = MeshGenerator(
            device: ctx.device,
            pipelineState: preset.pipelineState,
            configuration: .init(maxVerticesPerMeshlet: 252,
                                 maxPrimitivesPerMeshlet: 126,
                                 meshThreadCount: preset.descriptor.meshThreadCount))

        let drives = try Self.driveFrames()
        let target = try Self.makeTexture(ctx)
        let outputDirectory = try Self.makeOutputDirectory()
        var frames: [(label: String, pixels: [UInt8])] = []

        for drive in drives {
            guard let cmd = ctx.commandQueue.makeCommandBuffer() else { continue }
            Self.encode(cmd, into: target, generator: generator, features: drive.features)
            cmd.commit()
            cmd.waitUntilCompleted()
            #expect(cmd.status == .completed, "frame '\(drive.label)' failed to render")

            let pixels = Self.read(target)
            frames.append((drive.label, pixels))
            if let outputDirectory {
                Self.writePNG(pixels, to: outputDirectory,
                              name: "fractal_tree_\(drive.label).png")
            }
        }

        // Evidence, always printed — this is the measured-swing surface FTR.2 reports
        // against, standing in for the QG.5 response band Fractal Tree cannot reach.
        for (label, pixels) in frames {
            print(String(format: "[fractal-tree] %-10s luma %.5f  ink %.4f  width %.4f  hue %.1f°",
                         (label as NSString).utf8String!, Self.meanLuma(pixels),
                         Self.inkFraction(pixels), Self.canopyWidth(pixels),
                         Self.meanHue(pixels)))
        }
        if let outputDirectory {
            Self.writeContactSheet(frames, to: outputDirectory)
            print("[fractal-tree] contact sheet: \(outputDirectory.path)/contact_sheet.png")
        }

        // --- (a) silence is never black (D-037) ---------------------------------------
        let silence = try #require(frames.first { $0.label == "silence" })
        #expect(Self.meanLuma(silence.pixels) > 0.004, """
            Fractal Tree renders black at silence (mean luma \
            \(String(format: "%.5f", Self.meanLuma(silence.pixels)))). D-037: every preset \
            renders a non-black silence state, and the reference README calls for "a sparse, \
            still, non-black tree — trunk plus the first two generations".
            """)

        // --- (b) the drive actually changes the image ---------------------------------
        // Without this the harness would pass on a preset whose audio routes are all dead
        // — which is precisely the FTR.2 defect. Compares the quietest and loudest drive
        // frames; if routing works, they must not be near-identical.
        let quiet = try #require(frames.first { $0.label == "p05" })
        let loud = try #require(frames.first { $0.label == "p95" })
        let delta = Self.meanAbsoluteDelta(quiet.pixels, loud.pixels)
        print(String(format: "[fractal-tree] p05→p95 mean |Δpixel| = %.3f (0–255)", delta))
        #expect(delta > 0.5, """
            the p05 and p95 drive frames are nearly identical (mean |Δpixel| \
            \(String(format: "%.3f", delta)) of 255) — the preset barely responds to the \
            music across its own dynamic range. This is the FTR.2 defect measured at the \
            pixel level.
            """)
    }

    /// Renders CONSECUTIVE frames spanning about two beats, so the taps can be seen as a
    /// sequence rather than inferred. The hero route is a temporal effect — a contact
    /// sheet of energy-ranked stills is structurally incapable of showing it, which is
    /// how FTR.2 shipped a motion regression past every visual check it had.
    @Test("beat strip: consecutive frames across two beats (RENDER_VISUAL=1)")
    func beatStrip() throws {
        guard let outputDirectory = try Self.makeOutputDirectory() else { return }

        let ctx = try MetalContext()
        let loader = PresetLoader(device: ctx.device, pixelFormat: ctx.pixelFormat,
                                  loadBuiltIn: true)
        let preset = try #require(loader.presets.first { $0.descriptor.name == "Fractal Tree" })
        let generator = MeshGenerator(
            device: ctx.device, pipelineState: preset.pipelineState,
            configuration: .init(maxVerticesPerMeshlet: 252, maxPrimitivesPerMeshlet: 126,
                                 meshThreadCount: preset.descriptor.meshThreadCount))

        let base = try #require(
            Bundle.module.url(forResource: "route_coverage", withExtension: nil))
        let series = try SessionColumnSeries.load(
            directory: base.appendingPathComponent(Self.driveTrack))
        guard let time = series.floatSeries("time"),
              let phase = series.floatSeries("beatPhase01") else { return }

        // Start just before a beat boundary so the strip opens on the attack.
        let warm = (0..<min(time.count, phase.count)).filter { (time[$0] ?? 0) >= 10.0 }
        guard let start = warm.first(where: { row in
            guard let next = warm.first(where: { $0 == row + 1 }) else { return false }
            return (phase[next] ?? 0) < (phase[row] ?? 0) - 0.5
        }) else { return }

        let target = try Self.makeTexture(ctx)
        var frames: [(label: String, pixels: [UInt8])] = []
        // Every 4th frame over ~2 beats at 60 fps.
        for step in stride(from: 0, to: 72, by: 6) {
            let row = min(start + step, warm.last ?? start)
            var fv = Self.features(series, row: row)
            fv.aspectRatio = Float(Self.width) / Float(Self.height)
            guard let cmd = ctx.commandQueue.makeCommandBuffer() else { continue }
            Self.encode(cmd, into: target, generator: generator, features: fv)
            cmd.commit()
            cmd.waitUntilCompleted()
            frames.append(("t\(step)", Self.read(target)))
        }
        Self.writeContactSheet(frames, to: outputDirectory, name: "beat_strip.png")
        print("[fractal-tree] beat strip: \(outputDirectory.path)/beat_strip.png")
    }

    // MARK: - Motion

    /// The gate that would have caught the FTR.2 regression before Matt saw it.
    ///
    /// FTR.2 shipped a canopy that sat at its floor 82 % of the time and then jumped 21
    /// branches at once. Every still-based check passed, because a still cannot tell
    /// "moves in small steps constantly" from "slams between two extremes". Matt's
    /// verdict live was *"either too excited or completely inert … fingers are not
    /// really visible."* So this measures the CHARACTER of the motion, not its presence:
    /// how often the silhouette changes, and by how much when it does.
    ///
    /// The reference character is the pre-FTR.2 preset Matt described as fingers tapping:
    /// changes on ~12 % of frames, average jump ~2 branches, almost never at the floor.
    @Test("the canopy drifts in small steps and the taps fire per beat")
    func motionCharacterIsFingersNotSlams() throws {
        let base = try #require(
            Bundle.module.url(forResource: "route_coverage", withExtension: nil))
        let series = try SessionColumnSeries.load(
            directory: base.appendingPathComponent(Self.driveTrack))
        guard let time = series.floatSeries("time"),
              let bassRel = series.floatSeries("bassRel"),
              // The BAR clock. `pulse_phase01` is documented as a 4-beat cycle but
              // measures identically to `beat_phase01` on every recorded source, so
              // the bar rate has to come from here (recorded in permille).
              let beatPhase = series.floatSeries("barPhase01_permille") else {
            throw FractalTreeHarnessError.setupFailed("time/bassRel/barPhase01 absent")
        }

        // The shader's own arithmetic, mirrored — this is what the geometry sees.
        // `amp` is 1 here: the fixtures are music throughout, and the silence gate is
        // covered by the D-037 assertion in the render test.
        let rows = (0..<min(time.count, bassRel.count)).filter { (time[$0] ?? 0) >= 10.0 }
        let counts = rows.map { row -> Int in
            let reach = 1.0 / (1.0 + exp(-Double(bassRel[row] ?? 0) * 3.0))
            return min(7 + Int(10.0 + reach * 50.0), 63)
        }

        // (e) DEPTH TIERS. Matt: "I never see beyond three levels of branches." A tier
        // exists only above a threshold count — d4 > 15, d5 > 31 — and because leaf hue
        // is keyed to depth, losing tiers also costs colour. FTR.3 reached d5 on 23% of
        // frames against the old preset's 38%; this asserts the deep tier is routinely
        // on screen rather than occasional.
        let deepest5 = 100 * Double(counts.filter { $0 > 31 }.count) / Double(counts.count)
        let deepest4 = 100 * Double(counts.filter { $0 > 15 }.count) / Double(counts.count)
        print(String(format: "[fractal-tree/tiers] depth-5 on %.1f%% of frames, depth-4+ on %.1f%%",
                     deepest5, deepest4))
        #expect(deepest4 > 90, """
            the canopy reaches depth 4 on only \(String(format: "%.1f", deepest4))% of \
            frames — the tree spends its time as a stub, which is both the "never see \
            beyond three levels" complaint and, because hue is keyed to depth, half the \
            "not colourful enough" one.
            """)
        let seconds = Double((time[rows.last!] ?? 0) - (time[rows.first!] ?? 0))

        let steps = zip(counts, counts.dropFirst()).map { abs($1 - $0) }
        let moved = steps.filter { $0 > 0 }
        let changeRate = 100 * Double(moved.count) / Double(steps.count)
        let meanJump = moved.isEmpty ? 0 : Double(moved.reduce(0, +)) / Double(moved.count)
        let atFloor = 100 * Double(counts.filter { $0 <= 9 }.count) / Double(counts.count)

        // Taps fire once per beat — count beat-phase wraps.
        let phases = rows.compactMap { beatPhase[$0] }.map { $0 / 1000 }   // permille → 0…1
        let beats = zip(phases, phases.dropFirst()).filter { $1 < $0 - 0.5 }.count

        print("""
            [fractal-tree/motion] \(counts.count) frames over \
            \(String(format: "%.1f", seconds)) s — canopy changes on \
            \(String(format: "%.1f", changeRate))% of frames, mean jump \
            \(String(format: "%.1f", meanJump)), at floor \
            \(String(format: "%.1f", atFloor))%; taps fire on \(beats) beats = \
            \(String(format: "%.2f", Double(beats) / max(seconds, 1)))/s
            """)

        // (a) NOT INERT. FTR.2 sat at the floor 82% of the time.
        #expect(atFloor < 25, """
            the canopy sits at its floor \(String(format: "%.1f", atFloor))% of the time — \
            this is the FTR.2 "completely inert" failure. A transient driver like \
            bass_dev does exactly this; the canopy needs a CONTINUOUS one.
            """)

        // (b) NOT SLAMMING. FTR.2 averaged a 21.5-branch jump; the preset Matt liked
        // averaged 1.9. Above ~8 the silhouette teleports instead of growing.
        #expect(meanJump < 8, """
            the canopy moves \(String(format: "%.1f", meanJump)) branches per change — \
            this is the FTR.2 "too excited" failure. Individual branches must appear a \
            few at a time for the motion to read as fingers rather than as a jump cut.
            """)

        // (c) ACTUALLY MOVING. A perfectly smooth driver that never changes the integer
        // count would pass (a) and (b) trivially.
        #expect(changeRate > 5, """
            the canopy changes on only \(String(format: "%.1f", changeRate))% of frames — \
            too static to read as alive.
            """)

        // (d) THE HERO FIRES, ON THE BAR. Matt cut the rate to once per bar because
        // per-beat was "much too active with drums". Both bounds matter: no clock at all
        // means no rhythm, and drifting back toward the beat rate re-breaks it.
        let rate = Double(beats) / max(seconds, 1)
        #expect(rate > 0.15, """
            only \(beats) bars in \(String(format: "%.1f", seconds)) s — the per-branch \
            taps have no clock to fire on.
            """)
        #expect(rate < 1.0, """
            taps fire \(String(format: "%.2f", rate))/s — back at beat rate rather than \
            bar rate, which is the "much too active with drums" failure.
            """)
    }

    // MARK: - Drive

    private struct Drive {
        let label: String
        let features: FeatureVector
    }

    /// Silence plus four real-music frames, chosen at percentiles of `bass` so the sheet
    /// spans the track's actual dynamic range rather than three arbitrary rows.
    private static func driveFrames() throws -> [Drive] {
        var out = [Drive(label: "silence", features: Self.baseFeatures())]

        let base = try #require(
            Bundle.module.url(forResource: "route_coverage", withExtension: nil),
            "route_coverage fixtures not bundled — check Package.swift resources")
        let series = try SessionColumnSeries.load(
            directory: base.appendingPathComponent(driveTrack))

        // Rank frames by `bass`, then pick at percentiles. Warmup rows are dropped: the
        // first ~10 s is AGC/EMA settling, not music (D-212's method).
        guard let time = series.floatSeries("time"),
              let bass = series.floatSeries("bass") else {
            throw FractalTreeHarnessError.setupFailed("time/bass columns absent from \(driveTrack)")
        }
        let warm = (0..<min(time.count, bass.count)).filter { (time[$0] ?? 0) >= 10.0 }
        let ranked = warm.sorted { (bass[$0] ?? 0) < (bass[$1] ?? 0) }
        guard !ranked.isEmpty else {
            throw FractalTreeHarnessError.setupFailed("no post-warmup frames in \(driveTrack)")
        }

        for (label, p) in [("p05", 0.05), ("p50", 0.50), ("p95", 0.95), ("peak", 1.0)] {
            let row = ranked[min(Int(Double(ranked.count - 1) * p), ranked.count - 1)]
            out.append(Drive(label: label, features: Self.features(series, row: row)))
        }

        // Two frames ranked by HARMONY instead of energy. Without these the sheet cannot
        // show the hue route at all: sampling by bass holds the harmonic phase roughly
        // constant, so the leaf colour looks static when it is in fact tracking a
        // primitive this axis does not vary. One route, one sampling axis.
        if let tonal = series.floatSeries("tonal_phase_fifths") {
            let byTonal = warm.filter { $0 < tonal.count }
                .sorted { (tonal[$0] ?? 0) < (tonal[$1] ?? 0) }
            if let low = byTonal.first, let high = byTonal.last {
                out.append(Drive(label: "harm-lo", features: Self.features(series, row: low)))
                out.append(Drive(label: "harm-hi", features: Self.features(series, row: high)))
            }
        }
        return out
    }

    /// Build a FeatureVector from one fixture row.
    ///
    /// Every field Fractal Tree reads — before AND after the FTR.2 rebuild — is populated
    /// here. A field left at zero reads as a dead route when it is really an unmapped
    /// harness column, which is the trap that made Faraday's coupling look broken
    /// (r = −0.019 against a true +0.868). If FTR.5 routes a new primitive, add it here in
    /// the same commit.
    private static func features(_ s: SessionColumnSeries, row: Int) -> FeatureVector {
        var f = baseFeatures()
        func value(_ column: String) -> Float {
            guard let series = s.floatSeries(column), row < series.count else { return 0 }
            return series[row] ?? 0
        }
        // Shipped routing.
        f.bassAtt = value("bass_att")
        f.midAtt = value("mid_att")
        f.trebleAtt = value("treble_att")
        f.spectralCentroid = value("spectralCentroid")
        f.beatBass = value("beatBass")
        // FTR.2 routing.
        f.bassDev = value("bassDev")
        f.bassRel = value("bassRel")
        f.spectralFlux = value("spectralFlux")
        f.tonalPhaseFifths = value("tonal_phase_fifths")
        f.arousal = value("arousal")
        // FTR.3 per-branch activation. Leaving these at zero silently pins the canopy
        // to its 7-branch silence floor and fires no taps at all — the harness would
        // then report the hero route as dead when it is only unmapped. This is the
        // Faraday failure (a route measured at r = −0.019 that was really +0.868), and
        // it is why the drive builder must be updated in the SAME commit as any new route.
        f.beatPhase01 = value("beatPhase01")
        f.pulsePhase01 = value("pulse_phase01")
        f.pulseAmp01 = value("pulse_amp01")
        f.pulseBeatIndex = value("pulse_beat_index")
        // The bar clock the taps actually fire on. Recorded in permille.
        f.barPhase01 = value("barPhase01_permille") / 1000
        f.beatsPerBar = value("beatsPerBar")
        // Context the shader reads directly.
        f.bass = value("bass")
        f.mid = value("mid")
        f.treble = value("treble")
        f.time = value("time")
        return f
    }

    private static func baseFeatures() -> FeatureVector {
        var f = FeatureVector()
        f.deltaTime = 1.0 / 60.0
        f.aspectRatio = Float(width) / Float(height)
        return f
    }

    // MARK: - Encode

    private static func encode(_ cmd: MTLCommandBuffer, into texture: MTLTexture,
                               generator: MeshGenerator, features: FeatureVector) {
        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = texture
        rpd.colorAttachments[0].loadAction = .clear
        rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        rpd.colorAttachments[0].storeAction = .store
        guard let enc = cmd.makeRenderCommandEncoder(descriptor: rpd) else { return }
        generator.draw(encoder: enc, features: features)
        enc.endEncoding()
    }

    // MARK: - Measurement

    private static func meanLuma(_ bgra: [UInt8]) -> Double {
        guard !bgra.isEmpty else { return 0 }
        var total = 0.0
        for i in stride(from: 0, to: bgra.count, by: 4) {
            total += (0.114 * Double(bgra[i]) + 0.587 * Double(bgra[i + 1])
                      + 0.299 * Double(bgra[i + 2])) / 255.0
        }
        return total / Double(bgra.count / 4)
    }

    /// Circular mean hue over lit pixels, in degrees. Hue is an ANGLE — a linear mean
    /// puts the average of 350° and 10° at 180°, the opposite colour — so this sums unit
    /// vectors and takes the argument (the FBS hue-angle lesson).
    private static func meanHue(_ bgra: [UInt8]) -> Double {
        var sumX = 0.0, sumY = 0.0
        for i in stride(from: 0, to: bgra.count, by: 4) {
            let b = Double(bgra[i]) / 255, g = Double(bgra[i + 1]) / 255
            let r = Double(bgra[i + 2]) / 255
            let maxC = max(r, g, b), minC = min(r, g, b)
            guard maxC > 0.05, maxC - minC > 0.02 else { continue }
            let d = maxC - minC
            var h: Double
            if maxC == r { h = (g - b) / d } else if maxC == g { h = 2 + (b - r) / d }
            else { h = 4 + (r - g) / d }
            h *= 60
            if h < 0 { h += 360 }
            sumX += cos(h * .pi / 180)
            sumY += sin(h * .pi / 180)
        }
        guard sumX != 0 || sumY != 0 else { return 0 }
        let a = atan2(sumY, sumX) * 180 / .pi
        return a < 0 ? a + 360 : a
    }

    /// Width of the tree's bounding box, as a fraction of the frame. The direct visual
    /// quantity the branch-spread route drives — ink fraction conflates it with size.
    private static func canopyWidth(_ bgra: [UInt8]) -> Double {
        var minX = width, maxX = -1
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                guard Int(bgra[i]) + Int(bgra[i + 1]) + Int(bgra[i + 2]) > 24 else { continue }
                if x < minX { minX = x }
                if x > maxX { maxX = x }
            }
        }
        return maxX < minX ? 0 : Double(maxX - minX + 1) / Double(width)
    }

    /// Fraction of pixels the tree actually covers — the silhouette's screen footprint.
    /// Mean luma alone cannot separate "a bigger tree" from "a brighter one".
    private static func inkFraction(_ bgra: [UInt8]) -> Double {
        guard !bgra.isEmpty else { return 0 }
        var lit = 0
        for i in stride(from: 0, to: bgra.count, by: 4)
        where Int(bgra[i]) + Int(bgra[i + 1]) + Int(bgra[i + 2]) > 24 { lit += 1 }
        return Double(lit) / Double(bgra.count / 4)
    }

    private static func meanAbsoluteDelta(_ a: [UInt8], _ b: [UInt8]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var total = 0.0
        for i in a.indices where i % 4 != 3 { total += Double(abs(Int(a[i]) - Int(b[i]))) }
        return total / Double(a.count / 4 * 3)
    }

    // MARK: - Output

    private static func makeTexture(_ ctx: MetalContext) throws -> MTLTexture {
        let d = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: ctx.pixelFormat, width: width, height: height, mipmapped: false)
        d.usage = [.renderTarget, .shaderRead]
        d.storageMode = .shared
        guard let t = ctx.device.makeTexture(descriptor: d) else {
            throw FractalTreeHarnessError.setupFailed("output texture")
        }
        return t
    }

    /// `RENDER_VISUAL=1` dumps frames where `Scripts/compare_render.sh` looks for them.
    /// Returns nil when not dumping, so the gate costs nothing in a normal run.
    private static func makeOutputDirectory() throws -> URL? {
        guard ProcessInfo.processInfo.environment["RENDER_VISUAL"] == "1" else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let url = URL(fileURLWithPath: "/tmp/phosphene_visual")
            .appendingPathComponent("fractal_tree_\(formatter.string(from: Date()))")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func writePNG(_ bgra: [UInt8], to directory: URL, name: String) {
        writeImage(bgra, width: width, height: height,
                   to: directory.appendingPathComponent(name))
    }

    /// One horizontal strip, drive frames left to right. The whole point is seeing the
    /// range in a single image — a folder of PNGs does not show a flat response.
    private static func writeContactSheet(_ frames: [(label: String, pixels: [UInt8])],
                                          to directory: URL,
                                          name: String = "contact_sheet.png") {
        guard !frames.isEmpty else { return }
        let sheetWidth = width * frames.count
        var sheet = [UInt8](repeating: 0, count: sheetWidth * height * 4)
        for (index, frame) in frames.enumerated() {
            for y in 0..<height {
                let src = y * width * 4
                let dst = (y * sheetWidth + index * width) * 4
                for i in 0..<(width * 4) { sheet[dst + i] = frame.pixels[src + i] }
            }
        }
        writeImage(sheet, width: sheetWidth, height: height,
                   to: directory.appendingPathComponent(name))
    }

    private static func writeImage(_ bgra: [UInt8], width w: Int, height h: Int, to url: URL) {
        var rgba = bgra
        for i in stride(from: 0, to: rgba.count, by: 4) { rgba.swapAt(i, i + 2) }
        guard let provider = CGDataProvider(data: Data(rgba) as CFData),
              let image = CGImage(
                width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: w * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent),
              let destination = CGImageDestinationCreateWithURL(
                url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
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

enum FractalTreeHarnessError: Error {
    case setupFailed(String)
}
