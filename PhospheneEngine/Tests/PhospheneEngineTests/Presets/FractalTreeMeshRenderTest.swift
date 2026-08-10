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
@testable import DSP
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

    /// Render a CONTIGUOUS frame sequence driven by a REAL session capture, so the
    /// preset can be watched in motion on the audio Matt actually reviewed.
    ///
    /// WHY THIS EXISTS. Eight rounds of this preset shipped on numbers and 7-frame still
    /// sheets. "Too much movement" and "the colour is flashing" are TEMPORAL properties
    /// that a still sheet cannot show by construction — the same gap that let Truchet
    /// Loom pass still-review and jitter in live M7 (D-194). Measuring a driver's
    /// turns/s is not the same as seeing what it does to the frame.
    ///
    ///   FT_SESSION=~/Documents/phosphene_sessions/<id> \
    ///   RENDER_VISUAL=1 swift test --package-path PhospheneEngine --filter sessionSequence
    ///
    /// Writes numbered PNGs plus strips of consecutive frames. Reader is the eyes (D-064).
    @Test("session sequence: contiguous frames from a real capture (FT_SESSION=<dir>)")
    func sessionSequence() throws {
        // The MEASUREMENT runs whenever FT_SESSION is set; only PNG writing needs
        // RENDER_VISUAL. Coupling the assertion to the image flag made this silently skip
        // — a gate that quietly does not run is worse than no gate, and it is the second
        // time this harness has hidden its own verdict (the other was the fixed stride).
        guard let dir = ProcessInfo.processInfo.environment["FT_SESSION"] else { return }
        let outputDirectory = try Self.makeOutputDirectory()
        let csv = URL(fileURLWithPath: (dir as NSString).expandingTildeInPath)
            .appendingPathComponent("features.csv")
        let rows = try Self.loadSessionRows(csv)

        // RECOMPUTE engine-derived fields from the AUDIO rather than trusting the
        // recorded columns. A capture holds whatever the build that recorded it produced,
        // so replaying it straight validates the OLD engine — which is how the τ6 s
        // density looked unchanged here after it had already been fixed. Density is
        // recomputed through the real SpectralAnalyzer; everything else still comes from
        // the CSV, which is correct for fields the engine has not changed.
        let densityByTime = (try? Self.recomputeDensity(
            wav: csv.deletingLastPathComponent().appendingPathComponent("raw_tap.wav"))) ?? []
        if densityByTime.isEmpty {
            print("[fractal-tree/sequence] no raw_tap.wav — using RECORDED density (may be stale)")
        }
        guard !rows.isEmpty else {
            throw FractalTreeHarnessError.setupFailed("no usable rows in \(csv.path)")
        }

        let ctx = try MetalContext()
        let loader = PresetLoader(device: ctx.device, pixelFormat: ctx.pixelFormat,
                                  loadBuiltIn: true)
        let preset = try #require(loader.presets.first { $0.descriptor.name == "Fractal Tree" })
        let generator = MeshGenerator(
            device: ctx.device, pipelineState: preset.pipelineState,
            configuration: .init(maxVerticesPerMeshlet: 252, maxPrimitivesPerMeshlet: 126,
                                 meshThreadCount: preset.descriptor.meshThreadCount))
        let target = try Self.makeTexture(ctx)

        // SPAN THE WHOLE CAPTURE BY DEFAULT. The first version of this harness used a
        // fixed stride of 3, which at 96 frames covered 288 source rows — under five
        // seconds of a 29-second capture. It rendered a tree that never changed, and I
        // read that as "the preset is static" when it was the sampling window. An
        // instrument that silently shows you a sliver is worse than no instrument.
        // FT_STRIDE forces a fixed stride when a close-up of fast motion is wanted.
        let maxFrames = Int(ProcessInfo.processInfo.environment["FT_FRAMES"] ?? "") ?? 96
        let stride = Int(ProcessInfo.processInfo.environment["FT_STRIDE"] ?? "")
            ?? Swift.max(1, rows.count / maxFrames)
        print(String(format: "[fractal-tree/sequence] %d rows spanning %.1f s, stride %d",
                     rows.count, (rows.last?["time"] ?? 0) - (rows.first?["time"] ?? 0), stride))
        var fifths = FifthsSmoother()
        var flickerFifths = FifthsSmoother()
        var strip: [(label: String, pixels: [UInt8])] = []
        var hues: [Double] = []
        var times: [Double] = []
        var widths: [Double] = []
        var heights: [Double] = []
        var inks: [Double] = []

        for (index, row) in rows.enumerated() where index % stride == 0 {
            if strip.count >= maxFrames { break }
            var fv = Self.featuresFromSession(row, fifths: &fifths)
            Self.applyRecomputedDensity(densityByTime, at: row["time"] ?? 0, to: &fv)
            fv.aspectRatio = Float(Self.width) / Float(Self.height)
            guard let cmd = ctx.commandQueue.makeCommandBuffer() else { continue }
            Self.encode(cmd, into: target, generator: generator, features: fv)
            cmd.commit()
            cmd.waitUntilCompleted()
            let pixels = Self.read(target)
            strip.append(("f\(index)", pixels))
            hues.append(Self.meanHue(pixels))
            inks.append(Self.inkFraction(pixels))
            times.append(row["time"] ?? 0)
            widths.append(Self.canopyWidth(pixels))
            heights.append(Self.canopyHeight(pixels))
        }

        // FLICKER IS MEASURED ON ADJACENT FRAMES, ALWAYS — never on the sampled strip.
        //
        // The strip is deliberately spread across the whole capture so growth is visible,
        // which means consecutive strip frames can be a third of a second apart. A hue
        // step measured across THAT is not flicker, it is just the palette moving; the
        // first version of this reported 62.9° at stride 3 and 157.4° at stride 18 for
        // the identical build. A metric whose verdict depends on a diagnostic knob is
        // not a metric (the Meniscus stride lesson). So flicker gets its own stride-1
        // window, rendered separately.
        var adjacentHues: [Double] = []
        for row in rows.prefix(90) {
            var fv = Self.featuresFromSession(row, fifths: &flickerFifths)
            fv.aspectRatio = Float(Self.width) / Float(Self.height)
            guard let cmd = ctx.commandQueue.makeCommandBuffer() else { continue }
            Self.encode(cmd, into: target, generator: generator, features: fv)
            cmd.commit()
            cmd.waitUntilCompleted()
            adjacentHues.append(Self.meanHue(Self.read(target)))
        }
        let hueJumps = zip(adjacentHues, adjacentHues.dropFirst()).map { a, b -> Double in
            let d = abs(b - a); return min(d, 360 - d)
        }
        let inkSpan = (inks.max() ?? 0) - (inks.min() ?? 0)

        // THE EVENT. `FT_EVENT` names the audio-time of a section change; the tree's
        // footprint must be materially larger after it. This assertion maps directly onto
        // Matt's report — "there is no jump in growth when the distorted guitar kicks in" —
        // rather than onto a driver's statistics, which is the gap that let eight rounds
        // ship with green numbers and a preset that did not do the thing.
        if let event = Double(ProcessInfo.processInfo.environment["FT_EVENT"] ?? "") {
            func meanInk(_ range: ClosedRange<Double>) -> Double {
                let picked = zip(times, inks).filter { range.contains($0.0) }.map(\.1)
                return picked.isEmpty ? 0 : picked.reduce(0, +) / Double(picked.count)
            }
            func meanWidth(_ range: ClosedRange<Double>) -> Double {
                let picked = zip(times, widths).filter { range.contains($0.0) }.map(\.1)
                return picked.isEmpty ? 0 : picked.reduce(0, +) / Double(picked.count)
            }
            let beforeInk = meanInk(event - 4...event)
            let afterInk = meanInk(event...event + 4)
            func meanHeight(_ range: ClosedRange<Double>) -> Double {
                let picked = zip(times, heights).filter { range.contains($0.0) }.map(\.1)
                return picked.isEmpty ? 0 : picked.reduce(0, +) / Double(picked.count)
            }
            let beforeWidth = meanWidth(event - 4...event)
            let afterWidth = meanWidth(event...event + 4)
            let beforeHeight = meanHeight(event - 4...event)
            let afterHeight = meanHeight(event...event + 4)
            print(String(format: "[fractal-tree/event] HEIGHT %.4f -> %.4f (%.2fx)",
                         beforeHeight, afterHeight, afterHeight / Swift.max(beforeHeight, 1e-6)))
            print(String(format: "[fractal-tree/event] width %.4f -> %.4f (%.2fx)",
                         beforeWidth, afterWidth, afterWidth / Swift.max(beforeWidth, 1e-6)))
            print(String(format: "[fractal-tree/event] across %.1f s — footprint %.4f -> %.4f (%.2fx)",
                         event, beforeInk, afterInk, afterInk / Swift.max(beforeInk, 1e-6)))
            // ASSERT ON WIDTH, report footprint alongside. Matt's words are "I expect the
            // tree to grow OUTWARD", which is extent; ink conflates extent with density,
            // so a canopy that thickens without spreading would pass on ink and fail him.
            // Both are printed so a future change cannot quietly trade one for the other.
            // ASSERT ON HEIGHT. Matt's definition is literal: "shoot up = trunk
            // elongates, next level of branches appears." Width and footprint are what I
            // optimised for eight rounds while the trunk never moved.
            #expect(afterHeight > beforeHeight * 1.15, """
                the tree reached \(beforeHeight) -> \(afterHeight) up the frame across the \
                arrival at \(event) s. Under 1.15x the trunk did not elongate, which is \
                half of "shoot up" and the thing that has failed every round.
                """)
            #expect(afterWidth > beforeWidth * 1.05, """
                the canopy spread \(beforeWidth) -> \(afterWidth) across the section change \
                at \(event) s (footprint \(beforeInk) -> \(afterInk)). Under 1.15x this is \
                the "there is no jump in growth when the distorted guitar kicks in" failure, \
                whatever the driver statistics say.
                """)
        }
        print("""
            [fractal-tree/sequence] \(strip.count) frames — FLICKER (adjacent frames) \
            hue step median \(String(format: "%.2f", Self.median(hueJumps)))° max \
            \(String(format: "%.1f", hueJumps.max() ?? 0))°; GROWTH across the capture: \
            ink \(String(format: "%.4f", inks.min() ?? 0)) → \
            \(String(format: "%.4f", inks.max() ?? 0)) (span \
            \(String(format: "%.4f", inkSpan)))
            """)
        if let outputDirectory {
            for chunk in Swift.stride(from: 0, to: strip.count, by: 8) {
                let slice = Array(strip[chunk..<Swift.min(chunk + 8, strip.count)])
                Self.writeContactSheet(slice, to: outputDirectory,
                                       name: String(format: "seq_%03d.png", chunk))
            }
            print("[fractal-tree] sequence strips: \(outputDirectory.path)")
        }
    }

    /// Parse a recorded `features.csv` into rows keyed by column name, dropping the
    /// malformed startup lines a live capture can contain.
    private static func loadSessionRows(_ url: URL) throws -> [[String: Double]] {
        let text = try String(contentsOf: url, encoding: .utf8)
        var lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        guard !lines.isEmpty else { return [] }
        let header = lines.removeFirst().split(separator: ",", omittingEmptySubsequences: false)
            .map(String.init)
        var out: [[String: Double]] = []
        for line in lines {
            let parts = line.split(separator: ",", omittingEmptySubsequences: false)
            guard parts.count == header.count else { continue }
            var row: [String: Double] = [:]
            for (key, value) in zip(header, parts) { row[key] = Double(value) }
            guard let time = row["time"], time >= 15 else { continue }
            out.append(row)
        }
        return out
    }

    /// Same field set as the fixture drive — kept together so a new route is added to
    /// both in one edit, which is the trap that has bitten three times already.
    /// Vector-domain EMA mirroring `TonalAnalyzer.smoothPhaseFifths`. A recorded capture
    /// holds the RAW phase, so replaying it straight would still show the pre-fix flashing
    /// no matter what the engine now does. Kept in lockstep with the analyzer's alpha.
    private struct FifthsSmoother {
        private var re: Float = 0
        private var im: Float = 0
        private var seeded = false
        mutating func callAsFunction(_ raw: Float) -> Float {
            let alpha: Float = 0.065
            let (rawRe, rawIm) = (cos(raw), sin(raw))
            if !seeded {
                re = rawRe; im = rawIm; seeded = true
            } else {
                re = alpha * rawRe + (1 - alpha) * re
                im = alpha * rawIm + (1 - alpha) * im
            }
            return atan2(im, re)
        }
    }

    private static func featuresFromSession(_ row: [String: Double],
                                            fifths: inout FifthsSmoother) -> FeatureVector {
        var f = baseFeatures()
        func value(_ column: String) -> Float { Float(row[column] ?? 0) }
        f.bass = value("bass"); f.mid = value("mid"); f.treble = value("treble")
        f.bassAtt = value("bass_att"); f.midAtt = value("mid_att"); f.trebleAtt = value("treble_att")
        f.spectralCentroid = value("spectralCentroid"); f.spectralFlux = value("spectralFlux")
        f.beatBass = value("beatBass"); f.beatMid = value("beatMid")
        f.bassDev = value("bassDev"); f.bassRel = value("bassRel"); f.midRel = value("mid_rel")
        f.tonalPhaseFifths = value("tonal_phase_fifths")
        f.tonalPhaseFifths = fifths(value("tonal_phase_fifths"))
        f.arousal = value("arousal")
        f.beatPhase01 = value("beatPhase01"); f.pulsePhase01 = value("pulse_phase01")
        f.pulseAmp01 = value("pulse_amp01"); f.pulseBeatIndex = value("pulse_beat_index")
        f.barPhase01 = value("barPhase01_permille") / 1000; f.beatsPerBar = value("beatsPerBar")
        f.spectralDensity = value("spectral_density")
        f.spectralDensitySlow = value("spectral_density_slow")
        f.time = value("time")
        return f
    }

    /// Run the REAL `SpectralAnalyzer` over the capture's audio, returning
    /// (audioTime, density, densitySlow) at the ~10 Hz analysis rate.
    private static func recomputeDensity(wav: URL) throws -> [(Double, Float, Float, Float)] {
        let samples = try SpectralDensityRealAudioTests.loadFloatWavMonoShared(wav)
        guard !samples.isEmpty else { return [] }
        let analyzer = SpectralAnalyzer(binCount: 512, sampleRate: 48000, fftSize: 1024)
        let hop = 4800
        var out: [(Double, Float, Float, Float)] = []
        var start = 0
        while start + 1024 <= samples.count {
            let frame = Array(samples[start..<(start + 1024)])
            let result = analyzer.process(
                magnitudes: try SpectralDensityRealAudioTests.magnitudesShared(of: frame),
                deltaTime: Float(hop) / 48000)
            out.append((Double(start) / 48000, result.density, result.smoothedDensity, result.surge))
            start += hop
        }
        return out
    }

    /// The capture's `time` column and the audio share an origin at recording start.
    private static func applyRecomputedDensity(_ table: [(Double, Float, Float, Float)],
                                               at time: Double,
                                               to fv: inout FeatureVector) {
        guard !table.isEmpty else { return }
        let index = Swift.min(Swift.max(Int(time * 10), 0), table.count - 1)
        fv.spectralDensity = table[index].1
        fv.spectralDensitySlow = table[index].2
        fv.spectralSurge = table[index].3
    }

    private static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let s = values.sorted()
        return s[s.count / 2]
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
    @Test("the tree grows with energy and the fine tips follow the melodic line")
    func motionCharacterIsGrowthPlusMelody() throws {
        let base = try #require(
            Bundle.module.url(forResource: "route_coverage", withExtension: nil))
        let series = try SessionColumnSeries.load(
            directory: base.appendingPathComponent(Self.driveTrack))
        guard let time = series.floatSeries("time"),
              let arousal = series.floatSeries("arousal"),
              let beatMid = series.floatSeries("beatMid") else {
            throw FractalTreeHarnessError.setupFailed("time/arousal/beatMid absent")
        }

        // The shader's own arithmetic, mirrored. `amp` is 1: the fixtures are music
        // throughout, and the silence gate is covered by the D-037 render assertion.
        let rows = (0..<min(time.count, arousal.count)).filter { (time[$0] ?? 0) >= 10.0 }
        let melody = rows.map { Double(beatMid[$0] ?? 0) / (Double(beatMid[$0] ?? 0) + 2.2) }
        let growthEnv = rows.map { min(max((Double(arousal[$0] ?? 0) - 0.10) / 0.58, 0), 1) }
        let structure = rows.map { row -> Int in
            let reach = min(max((Double(arousal[row] ?? 0) - 0.10) / 0.58, 0), 1)
            return Int(4.0 + reach * 18.0)
        }
        let tips = zip(melody, growthEnv).map { m, g -> Int in
            let t = min(max(g / 0.35, 0), 1)
            return Int(m * 26.0 * (t * t * (3 - 2 * t)))
        }
        let counts = zip(structure, tips).map { min(7 + $0 + $1, 63) }
        let seconds = Double((time[rows.last!] ?? 0) - (time[rows.first!] ?? 0))

        let steps = zip(counts, counts.dropFirst()).map { abs($1 - $0) }
        let moved = steps.filter { $0 > 0 }
        let changeRate = 100 * Double(moved.count) / Double(steps.count)
        let meanJump = moved.isEmpty ? 0 : Double(moved.reduce(0, +)) / Double(moved.count)

        // How LINE-LIKE the melodic driver is: a melody changes direction several times
        // a second. A signal that only ramps is an envelope, not a tune.
        let deltas = zip(melody, melody.dropFirst()).map { $1 - $0 }.filter { $0 != 0 }
        let flips = zip(deltas, deltas.dropFirst()).filter { $0 * $1 < 0 }.count
        let flipRate = Double(flips) / max(seconds, 1)

        let tipSpread = (tips.max() ?? 0) - (tips.min() ?? 0)
        let sorted = counts.sorted()
        print("""
            [fractal-tree/motion] \(counts.count) frames over \
            \(String(format: "%.1f", seconds)) s — count p05 \(sorted[sorted.count / 20]) \
            p50 \(sorted[sorted.count / 2]) p95 \(sorted[sorted.count * 19 / 20]); \
            changes on \(String(format: "%.1f", changeRate))% of frames, mean jump \
            \(String(format: "%.1f", meanJump)); melodic tips span \(tipSpread) branches, \
            line turns \(String(format: "%.2f", flipRate))/s
            """)

        // (a) NOT INERT and (b) NOT SLAMMING — the two failures Matt named in FTR.2
        // ("either too excited or completely inert").
        //
        // **FTR.6 LOWERED BOTH OF THESE TO SHIP, AND MATT SAW THE DEFECT THEY EXIST TO
        // CATCH.** The floor went 20 → 8 and `tipSpread` 5 → 3, with a paragraph of
        // justification each. The rule is that a red gate is the gate working and the
        // floor is never the thing that moves; the build measured `tipSpread` 3, which
        // was the harness saying, correctly, that the tip layer had stopped swinging.
        // Restored 2026-08-07 with the revert. Do not lower them again — if a design
        // cannot clear them, that is the design's verdict, not the gate's.
        #expect(changeRate > 20, """
            the canopy changes on only \(String(format: "%.1f", changeRate))% of frames — \
            too static to read as growing with the music.
            """)
        #expect(meanJump < 8, """
            the canopy moves \(String(format: "%.1f", meanJump)) branches per change — \
            branches must appear a few at a time, not teleport.
            """)

        // (c) THE MELODY IS A REAL LAYER. If the tips barely span anything, the melodic
        // route exists in the manifest and not on screen.
        // (c2) THE DEEPEST TIER MUST CROSS IN AND OUT. This is the mechanism itself:
        // d5 starts at count 31, and the original preset straddled that line so the
        // smallest branches were always appearing and disappearing. A version that
        // parks above it measures well and shows nothing — the first attempt at this
        // route sat at d5 94 % and had no flicker at all.
        let d5 = counts.map { $0 > 31 }
        let crossings = zip(d5, d5.dropFirst()).filter { $0 != $1 }.count
        let crossRate = Double(crossings) / max(seconds, 1)
        let d5Share = 100 * Double(d5.filter { $0 }.count) / Double(d5.count)
        print(String(format: "[fractal-tree/tips] depth-5 present %.0f%% of frames, crossing in/out %.2f times/s",
                     d5Share, crossRate))
        #expect(d5Share > 5 && d5Share < 75, """
            depth-5 is present on \(String(format: "%.0f", d5Share))% of frames — either \
            parked (nothing left to flicker) or absent (Matt: "I never see beyond three \
            levels"). The tier has to be IN PLAY for the tips to read as following.
            """)
        #expect(crossRate > 0.5, """
            the deepest tier crosses in/out only \(String(format: "%.2f", crossRate))/s — \
            too rare to read as the fine branches tracking the tune.
            """)

        #expect(tipSpread >= 5, """
            the melodic tip layer spans only \(tipSpread) branches — too small a share of \
            the canopy for "the tiny branches are following the melody" to be visible.
            """)

        // (d0) THE GROWTH LAYER MUST NOT BOUNCE. Matt: "the growth is jerky - the trunk
        // is constantly moving up and down with the beat, killing any concept that the
        // tree is growing." bass_rel wobbled 5.88 times/s with a median step of 17% of
        // its range; arousal manages 0.52/s and 0.1%. Trunk length reads this directly,
        // so a fast driver here is visible as bouncing.
        let growth = rows.map { min(max((Double(arousal[$0] ?? 0) - 0.10) / 0.58, 0), 1) }
        let gd = zip(growth, growth.dropFirst()).map { $1 - $0 }.filter { $0 != 0 }
        let gTurns = Double(zip(gd, gd.dropFirst()).filter { $0 * $1 < 0 }.count) / max(seconds, 1)
        print(String(format: "[fractal-tree/growth] trunk driver turns %.2f/s", gTurns))
        #expect(gTurns < 2.0, """
            the growth driver changes direction \(String(format: "%.2f", gTurns))/s — fast
            enough that the trunk will visibly bounce, which is the exact failure Matt
            named ("the trunk is constantly moving up and down with the beat"). Growth
            must come from a section-scale signal.
            """)

        // (d) IT FOLLOWS A LINE, NOT AN ENVELOPE. This is the assertion that rules out
        // the harmonic axis I measured and rejected: tonal_phase_thirds jumps a median
        // 18.6% of the circle per update, so it cannot be followed. A melodic contour
        // turns several times a second.
        #expect(flipRate > 2.0, """
            the melodic driver changes direction only \(String(format: "%.2f", flipRate))/s — \
            that is an envelope, not a line. Branches keyed to it will read as swelling \
            together rather than following a tune.
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
        // DYN.1. The route_coverage fixtures predate the field, so these read 0 here and
        // the density lift contributes nothing in the harness — the growth still measures
        // via arousal. Once the fixtures are re-captured these become live and the lift
        // is exercised; until then this is a KNOWN blind spot, stated rather than implied.
        f.spectralDensity = value("spectral_density")
        f.spectralDensitySlow = value("spectral_density_slow")
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

    /// Height of the tree: how far up the frame the topmost lit pixel reaches.
    ///
    /// THE metric for "the trunk elongates", which is half of Matt's definition of
    /// "shoot up". Footprint and width both improved across eight rounds while this did
    /// not move, and he rejected every one of them — measuring the wrong quantity is how
    /// a preset passes its gates and fails the person looking at it.
    private static func canopyHeight(_ bgra: [UInt8]) -> Double {
        for y in 0..<height {
            for x in 0..<width where Int(bgra[(y * width + x) * 4])
                + Int(bgra[(y * width + x) * 4 + 1])
                + Int(bgra[(y * width + x) * 4 + 2]) > 24 {
                return Double(height - y) / Double(height)
            }
        }
        return 0
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
