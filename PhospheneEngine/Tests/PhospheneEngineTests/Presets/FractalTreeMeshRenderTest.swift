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
@testable import Audio
@testable import DSP
@testable import Shared

// MARK: - FractalTreeMeshRenderTest

@Suite("Fractal Tree mesh render")
struct FractalTreeMeshRenderTest {

    // FTR.14 — resolution is a KNOB because it changes what "frozen" means. Sub-pixel geometry
    // motion cannot alter a rasterised pixel, so a 640x480 harness reports frames as frozen
    // that are visibly moving at the 1080p the app renders at. `FT_RES=1920x1080` measures the
    // shipping resolution; the default stays 640x480 so every existing golden and contact sheet
    // is unchanged.
    private static let renderSize: (width: Int, height: Int) = {
        guard let spec = ProcessInfo.processInfo.environment["FT_RES"],
              case let parts = spec.lowercased().split(separator: "x"), parts.count == 2,
              let w = Int(parts[0]), let h = Int(parts[1]), w > 0, h > 0 else {
            return (640, 480)
        }
        return (w, h)
    }()
    private static var width: Int { renderSize.width }
    private static var height: Int { renderSize.height }

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
            // FTR.14 — LET THE GLIDE SETTLE BEFORE CAPTURING. The beat-driven vector now chases
            // its target over ~a quarter of a beat instead of snapping, so ONE draw per drive
            // condition captures the first ~10 % of the journey from the PREVIOUS condition, not
            // the tree at this energy. Uncaught, that is not a cosmetic problem: it collapsed
            // this suite's own p05→p95 response measurement from 0.944 to 0.048 and would have
            // made every contact sheet a picture of a tree mid-transition.
            //
            // Settling is also the honest model of playback — real audio holds an energy for far
            // longer than one frame. 40 frames at 1/60 s is ~0.67 s, several time constants.
            generator.renderDeltaOverride = 1.0 / 60.0
            for _ in 0..<40 {
                generator.advanceBeatHoldForSettling(drive.features, stems: drive.stems)
            }
            guard let cmd = ctx.commandQueue.makeCommandBuffer() else { continue }
            Self.encode(cmd, into: target, generator: generator,
                        features: drive.features, stems: drive.stems)
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
            Self.encode(cmd, into: target, generator: generator,
                        features: fv, stems: Self.stems(series, row: row))
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
        // FTR.4/FTR.8 — the tips are a stem route now, so the sequence must carry the
        // session's own stems.csv or it renders the hero route silent.
        let stemRows = (try? Self.loadSessionRows(
            csv.deletingLastPathComponent().appendingPathComponent("stems.csv"),
            dropBeforeSeconds: nil)) ?? []
        let stemOffset = (try? Self.leadingRowsDropped(csv)) ?? 0
        if stemRows.isEmpty {
            print("[fractal-tree/sequence] no stems.csv — the guitar tips route will read ZERO")
        } else {
            let rate = stemRows.compactMap { $0["otherOnsetRate"] }
            let live = rate.filter { $0 > 0 }.count
            print(String(format: "[fractal-tree/sequence] stems: %d rows, offset %d, otherOnsetRate non-zero on %.0f%%",
                         stemRows.count, stemOffset, 100 * Double(live) / Double(max(rate.count, 1))))
        }

        // RECOMPUTE engine-derived fields from the AUDIO rather than trusting the
        // recorded columns. A capture holds whatever the build that recorded it produced,
        // so replaying it straight validates the OLD engine — which is how the τ6 s
        // density looked unchanged here after it had already been fixed. Density is
        // recomputed through the real SpectralAnalyzer; everything else still comes from
        // the CSV, which is correct for fields the engine has not changed.
        // A `LoudnessProfile` is a PER-TRACK distribution, so recomputing the section ratio
        // is only valid for a single-track capture. Measured across a two-track session it
        // ranks every moment against the wrong distribution and the canopy collapses to a
        // sapling — observed on `2026-08-11T16-41-39Z` (Cherub Rock + Carry The Zero): growth
        // span 0.0202 on a single-track capture against 0.0036 on that one, with the SAME
        // build. Detected from the session log rather than guessed.
        let trackCount = Self.trackCount(inSessionAt: csv.deletingLastPathComponent())
        if trackCount > 1 {
            print("""
                [fractal-tree/sequence] \(trackCount)-track capture — section ratio REPLAYED \
                from the recording, not recomputed (a loudness profile is per track). A \
                post-FTR.9 verdict needs a single-track capture.
                """)
        }
        // FTR.10 — RECOMPUTE IS NOW OPT-IN, and this is a correction to FTR.9.1 rather than a
        // convenience. The recompute measures the `LoudnessProfile` from the TAP; the live
        // path measures it from the local FILE (DYN.1c). On `2026-08-11T18-26-52Z` the two
        // disagree by 11×: recomputed surge tops out at 0.073 against the recording's 0.802,
        // which drives `musicGate` to ~0.03 and renders a permanent sapling. The FTR.10
        // before/after A/B came back identical on that footing — both builds pinned — and it
        // took an A/B to notice, because a pinned tree still renders a plausible picture.
        // Replay is right whenever the capture postdates the engine change under review;
        // FT_RECOMPUTE=1 is for when it does not, which is what FTR.9.1 was written for.
        let densityByTime = ProcessInfo.processInfo.environment["FT_RECOMPUTE"] == "1"
            ? ((try? Self.recomputeDensity(
                wav: csv.deletingLastPathComponent().appendingPathComponent("raw_tap.wav"))) ?? [])
            : []
        if densityByTime.isEmpty {
            print("[fractal-tree/sequence] drivers REPLAYED from features.csv (FT_RECOMPUTE=1 to recompute)")
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
        // FT_SKIP — start the strip N seconds into the capture. The motion gate needs a
        // stride-1 close-up, and at stride 1 the first frames are the first four seconds,
        // which is exactly the `BeatHold` warm-up: a window that shows only the fallback
        // path would be reviewed as "the trunk still slides".
        let skipSeconds = Double(ProcessInfo.processInfo.environment["FT_SKIP"] ?? "") ?? 0
        print(String(format: "[fractal-tree/sequence] %d rows spanning %.1f s, stride %d",
                     rows.count, (rows.last?["time"] ?? 0) - (rows.first?["time"] ?? 0), stride))
        var fifths = FifthsSmoother()
        var flickerFifths = FifthsSmoother()
        var strip: [(label: String, pixels: [UInt8])] = []
        var hues: [Double] = []
        var times: [Double] = []
        var widths: [Double] = []
        var heights: [Double] = []
        var steppingFrames = 0
        var inks: [Double] = []

        for (index, row) in rows.enumerated() {
            if strip.count >= maxFrames { break }
            var fv = Self.featuresFromSession(row, fifths: &fifths)
            Self.applyRecomputedDensity(densityByTime, at: row["time"] ?? 0, to: &fv,
                                        includeSectionRatio: trackCount == 1)
            fv.aspectRatio = Float(Self.width) / Float(Self.height)
            // FTR.10 — the strip is subsampled, the BEAT HOLD is not. `MeshGenerator` advances
            // its snapshot inside `draw`, so a harness that only draws every Nth row would
            // feed the hold an aliased phase and measure a clock that does not exist live.
            // Every skipped row goes through the same object, un-drawn.
            // FTR.14 — drive the glide from the CAPTURE's frame delta, not the harness's
            // wall clock. `MeshGenerator.nextRenderDelta` reads real time by default, which
            // offline is the speed this test renders at; measured that way a contiguous window
            // read 73 of 95 frames pixel-frozen purely because a slow harness frame produced a
            // large delta, converged the glide in one frame and then had nothing to move
            // toward until the next 10 Hz target. Injecting the capture's own delta is what
            // makes the offline pixels representative of the app's.
            generator.renderDeltaOverride = index > 0
                ? Float(min(max((rows[index]["wallclock_s"] ?? 0)
                                - (rows[index - 1]["wallclock_s"] ?? 0), 1.0 / 240.0), 1.0 / 15.0))
                : Float(1.0 / 60.0)
            guard index % stride == 0, (row["time"] ?? 0) >= skipSeconds + (rows.first?["time"] ?? 0) else {
                generator.advanceBeatHold(fv)
                continue
            }
            guard let cmd = ctx.commandQueue.makeCommandBuffer() else { continue }
            Self.encode(cmd, into: target, generator: generator, features: fv,
                        stems: Self.sessionStems(stemRows, index: index + stemOffset))
            cmd.commit()
            cmd.waitUntilCompleted()
            let pixels = Self.read(target)
            strip.append(("f\(index)", pixels))
            hues.append(Self.meanHue(pixels))
            inks.append(Self.inkFraction(pixels))
            times.append(row["time"] ?? 0)
            widths.append(Self.canopyWidth(pixels))
            heights.append(Self.canopyHeight(pixels))
            if generator.beatHoldIsStepping { steppingFrames += 1 }
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
        for (flickerIndex, row) in rows.prefix(90).enumerated() {
            var fv = Self.featuresFromSession(row, fifths: &flickerFifths)
            fv.aspectRatio = Float(Self.width) / Float(Self.height)
            guard let cmd = ctx.commandQueue.makeCommandBuffer() else { continue }
            Self.encode(cmd, into: target, generator: generator, features: fv,
                        stems: Self.sessionStems(stemRows, index: flickerIndex + stemOffset))
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
        // FTR.10 — WAS THE HOLD ACTUALLY ON, and what did the frames do.
        //
        // NO PIXEL METRIC ON THIS PRESET ISOLATES THE TRUNK, and that is worth stating rather
        // than working around, because two of them were built here before the reason was
        // understood. `motion_gate.sh`'s whole-frame difference came back 2.26 against 2.18 —
        // the tips and the hue dominate it. A centre-column scan for the top of the bark
        // column came back turning MORE often with the hold on (5.68/s against 4.13/s), which
        // reads as a refutation and is not one: the two depth-1 branches start AT the trunk
        // top and overlap the centre column, and their length carries `tap` — up to
        // 1 + 0.02 + 0.40·0.2² = 3.6 %, about 2 px at this resolution. A column scan measures
        // the trunk plus a 2 px tip wobble, and at 33 px of total travel the wobble wins.
        //
        // So the split is: the trunk's stillness is established in the DRIVER domain by
        // `trunkStepsOnTheBeat` (exact shader arithmetic, 1.64 → 0.52 turns/s), the GPU's
        // reading of buffer(4) by `objectStageReadsTheBeatHeldVector` (canopy 0.42 against
        // 0.92 — a 2× difference no wobble explains), and the temporal CHARACTER by the
        // motion gate plus a reader. What this block adds is the one thing those cannot: that
        // the hold was engaged at all while these frames were rendered. A fallback path
        // renders a perfectly plausible tree, so "the trunk still slides" and "the hold never
        // engaged" look identical from the outside.
        let strippedSeconds = (times.last ?? 0) - (times.first ?? 0)
        func report(_ label: String, _ values: [Double]) -> String {
            let deltas = zip(values, values.dropFirst()).map { $1 - $0 }.filter { $0 != 0 }
            let flips = zip(deltas, deltas.dropFirst()).filter { $0 * $1 < 0 }.count
            let held = 100 * Double(deltas.count == 0 ? 1 : 1 - Double(deltas.count)
                                    / Double(Swift.max(values.count - 1, 1)))
            return String(format: "%@ %.4f…%.4f, turns %.2f/s, unchanged on %.0f%% of frames",
                          label, values.min() ?? 0, values.max() ?? 0,
                          Double(flips) / Swift.max(strippedSeconds, 1), held)
        }
        print(String(format: "[fractal-tree/trunk] beat hold engaged on %.0f%% of %d rendered frames over %.1f s",
                     100 * Double(steppingFrames) / Double(Swift.max(strip.count, 1)),
                     strip.count, strippedSeconds))
        print("[fractal-tree/trunk] \(report("canopy top", heights)) — tips-dominated, see above")

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
            // INDIVIDUAL frames as well, named for `Scripts/motion_gate.sh` to glob
            // (`<slug>_seq_*.png`). The contact sheets are for reading eight stills at
            // once; the gate needs the sequence itself, and pointing it at a directory of
            // COMPOSITES would have it measure sheet-to-sheet difference and call an
            // eight-frame jump "motion". PG.MG / D-195.
            for (index, frame) in strip.enumerated() {
                Self.writePNG(frame.pixels, to: outputDirectory,
                              name: String(format: "fractal_tree_seq_%05d.png", index))
            }
            print("[fractal-tree] sequence strips + frames: \(outputDirectory.path)")
        }
    }

    // MARK: - FTR.10 — the stepped trunk

    /// What the trunk does across a real capture, before and after the beat hold.
    ///
    /// Matt, 2026-08-11 (`2026-08-11T18-26-52Z`): *"The trunk is moving too much, which
    /// unfortunately makes the motion of the tips difficult to see."* This reports the two
    /// numbers that claim is about — how often the trunk changes direction, and how far it
    /// travels — for the continuous build and for the held one, on the same rows.
    ///
    /// **Span is asserted as tightly as rate.** A smoother would also cut the turn rate, and
    /// would do it by throwing away the range Matt spent DYN.1e–DYN.4 asking for ("a 10 %
    /// band … nothing to see"). A sample-and-hold keeps the range by construction; this
    /// assertion is what makes that a checked property rather than a claim.
    ///
    ///   FT_SESSION=~/Documents/phosphene_sessions/<id> \
    ///   swift test --package-path PhospheneEngine --filter trunkStepsOnTheBeat
    @Test("FTR.10: the trunk holds between beats and steps on them (FT_SESSION=<dir>)")
    func trunkStepsOnTheBeat() throws {
        guard let dir = ProcessInfo.processInfo.environment["FT_SESSION"] else { return }
        let session = URL(fileURLWithPath: (dir as NSString).expandingTildeInPath)
        let csv = session.appendingPathComponent("features.csv")
        let rows = try Self.loadSessionRows(csv)
        guard !rows.isEmpty else {
            throw FractalTreeHarnessError.setupFailed("no usable rows in \(csv.path)")
        }
        // FTR.9.1 — a `LoudnessProfile` is per track, so recomputing the section ratio across
        // a multi-track capture ranks every moment against the wrong distribution and the
        // canopy collapses to a sapling. Refuse rather than report a fiction.
        let trackCount = Self.trackCount(inSessionAt: session)
        guard trackCount <= 1 else {
            throw FractalTreeHarnessError.setupFailed("""
                \(trackCount)-track capture — the trunk report needs a single-track session \
                (a LoudnessProfile is per track; FTR.9.1).
                """)
        }
        // REPLAYED, NOT RECOMPUTED — and that is the opposite of what the sequence harness
        // does, so it needs a reason. `recomputeDensity` exists because a capture holds
        // whatever build recorded it (FTR.9.1). But it measures the `LoudnessProfile` from the
        // TAP, where the live path measures it from the local FILE (DYN.1c), and on this
        // capture the two disagree hard: recomputed surge tops out at 0.073 against the
        // recording's 0.802, which drives `musicGate` to ~0.03 and pins the trunk flat.
        // The recording here postdates FTR.9, so its columns ARE the current engine's — the
        // condition `recomputeDensity` was written to protect against does not hold.
        // `FT_RECOMPUTE=1` forces the other path when the capture is genuinely old.
        // FTR.24 — FT_ACCENT_FROM_TAP=1: recompute ONLY `spectral_level_rise` and replay every
        // other column. Neither existing path can measure the accent on Matt's own capture:
        // a REPLAY feeds 0 for a column recorded before the field existed, and a full
        // RECOMPUTE measures the LoudnessProfile from the tap instead of the file, which pins
        // this capture's surge at 0.073 against the recording's 0.802 and flattens the base
        // the accent sits on. So take the one field the recording cannot carry from the tap,
        // and take the rest from the recording, which is the current engine's own output.
        let accentFromTap = ProcessInfo.processInfo.environment["FT_ACCENT_FROM_TAP"] == "1"
        let recompute = ProcessInfo.processInfo.environment["FT_RECOMPUTE"] == "1"
        let densityByTime = (recompute || accentFromTap)
            ? ((try? Self.recomputeDensity(
                wav: session.appendingPathComponent("raw_tap.wav"))) ?? [])
            : []
        let inputMode = recompute ? "RECOMPUTED from raw_tap.wav"
            : accentFromTap ? "replayed from features.csv, spectral_level_rise FROM THE TAP (FTR.24)"
            : "replayed from features.csv"
        print("[fractal-tree/inputs] drivers \(inputMode)")

        let stemRows = (try? Self.loadSessionRows(
            session.appendingPathComponent("stems.csv"), dropBeforeSeconds: nil)) ?? []
        let stemOffset = (try? Self.leadingRowsDropped(csv)) ?? 0
        if stemRows.isEmpty {
            print("[fractal-tree/trunk] no stems.csv — the tips layer will read ZERO")
        }

        var fifths = FifthsSmoother()
        // FTR.14 — the same GLIDING hold `MeshGenerator` installs in production. A hard
        // `BeatHold()` here would measure a build that no longer ships.
        // FTR.24 — the CONTINUOUS-target hold FTR.23 tuned, matching `MeshGenerator` exactly.
        // This line read `glideBeats: 0.25` (FTR.14's latched glide) for two increments after
        // production moved on, so every trunk figure printed here described a build that had
        // already been replaced. Same class as the FifthsSmoother divergence FTR.19 found.
        var hold = BeatHold(continuousGlideBeats: 0.12, beatSpeedBoost: 1.0)
        var sectionHold = BeatHold(glideSeconds: 2.0)
        var reachTerm: [Float] = []
        var surgeTerm: [Float] = []
        var continuous: [Float] = []
        var stepped: [Float] = []
        // FTR.11 — the two layers FTR.10 left running. Matt's words were "the trunk AND
        // branches", and reporting only the trunk is how an increment ships having fixed the
        // smallest of the three moving things: on `2026-08-11T23-52-49Z` the trunk was held at
        // 0.66 turns/s while the count turned 4.08 and the spread 5.48.
        var countLive: [Float] = []
        var countHeld: [Float] = []
        var spreadLive: [Float] = []
        var spreadHeld: [Float] = []
        var tips: [Float] = []
        // The count MINUS the tips. Without this row "count (HELD) 3.46/s" is unreadable:
        // the tips are inside the count and are deliberately still live, so the residual
        // could be a frame that never settled or a frame that is perfectly still under a
        // busy tip layer. Those call for opposite next moves.
        var frameOnlyLive: [Float] = []
        var frameOnly: [Float] = []
        var steppingFrames = 0
        // FTR.12d — WHEN the hold engages, per frame. Matt's M7 on this capture was
        // *"looks best at the beginning of playback then transitions to the stuttering,
        // robotic look"*, and a whole-track turn rate cannot show a transition. This is the
        // column that can: the hold has a cold start (it needs a bar clock plus 8 stable beat
        // intervals), so the opening seconds run CONTINUOUS and then switch to STEPPED.
        var stepping: [Bool] = []
        // FTR.12e — PER-BAR HOLD, emulated for measurement only (no production change).
        // Matt's call on the M7 was *"steps, but slower — on the bar"*, and before building
        // that there is a risk worth measuring: the tree still has to reach the same places,
        // so 4x fewer steps means each step carries ~4x more. For a COUNT of branches that is
        // fewer, BIGGER pops — possibly more stuttering, not less. Mirrors `BeatHold.update`
        // exactly, substituting the bar clock for the beat clock, and reuses the real hold's
        // `isStepping` for the trust gate so only the boundary differs.
        var barHeld = FeatureVector()
        var lastBarPhase: Float = 0
        var trunkBar: [Float] = []
        var countBar: [Float] = []
        var spreadBar: [Float] = []
        var frameOnlyBar: [Float] = []
        for (index, row) in rows.enumerated() {
            var fv = Self.featuresFromSession(row, fifths: &fifths)
            if accentFromTap {
                Self.applyRecomputedLevelRise(densityByTime, at: row["time"] ?? 0, to: &fv)
            } else {
                Self.applyRecomputedDensity(densityByTime, at: row["time"] ?? 0, to: &fv,
                                            includeSectionRatio: true)
            }
            let stems = Self.sessionStems(stemRows, index: index + stemOffset)
            hold.offerStems(stems)
            // FTR.14 — REAL RENDER DELTAS, and this is the correction that matters most in this
            // file. FTR.13 was validated by a harness that fed no render clock at all, so it
            // measured the interpolated value rather than how often the value actually ARRIVED,
            // and it reported "0 spike frames / mean step 0.75 branches" for a build that
            // rendered two jumps and four dead ticks per beat. `wallclock_s` is the render
            // cadence the app really ran at (~59 rows/s), so the glide advances here exactly as
            // it does live.
            let renderDelta = index > 0
                ? Float(max((rows[index]["wallclock_s"] ?? 0) - (rows[index - 1]["wallclock_s"] ?? 0),
                            1.0 / 240.0))
                : Float(1.0 / 60.0)
            let held = hold.update(fv, renderDeltaTime: min(renderDelta, 1.0 / 15.0))
            let stemsHeld = hold.glidingStemFeatures
            let section = sectionHold.update(fv, renderDeltaTime: min(renderDelta, 1.0 / 15.0))
            if hold.isStepping { steppingFrames += 1 }
            stepping.append(hold.isStepping)
            let growth = Self.growth(fv)
            reachTerm.append(growth.reach * 0.13)
            surgeTerm.append(growth.surge * 0.32)
            continuous.append(Self.trunkLength(fv))
            stepped.append(Self.trunkLength(held, section: section))
            // FTR.13 — FRACTIONAL counts. The shader scales the frontier branch's length by the
            // fraction, so the visible canopy is the fractional value; an integer mirror would
            // report a pop the shader no longer draws.
            countLive.append(Self.branchCountF(frame: fv, live: fv, stems: stems,
                                               stemsHeld: stems))
            countHeld.append(Self.branchCountF(frame: held, live: fv, stems: stems,
                                               stemsHeld: stemsHeld))
            spreadLive.append(Self.spreadDegrees(fv))
            spreadHeld.append(Self.spreadDegrees(held))
            tips.append(Self.tipBranchesF(frame: held, live: fv, stems: stems,
                                          stemsHeld: stemsHeld))
            frameOnlyLive.append(Self.branchCountF(frame: fv, live: fv, stems: stems,
                                                   stemsHeld: stems)
                                 - Self.tipBranchesF(frame: fv, live: fv, stems: stems,
                                                     stemsHeld: stems))
            frameOnly.append(Self.branchCountF(frame: held, live: fv, stems: stems,
                                               stemsHeld: stemsHeld)
                             - Self.tipBranchesF(frame: held, live: fv, stems: stems,
                                                 stemsHeld: stemsHeld))

            let barWrapped = fv.barPhase01 < lastBarPhase - 0.25
            lastBarPhase = fv.barPhase01
            if barWrapped || !hold.isStepping { barHeld = fv }
            trunkBar.append(Self.trunkLength(barHeld))
            countBar.append(Self.branchCountF(frame: barHeld, live: fv, stems: stems,
                                              stemsHeld: stemsHeld))
            spreadBar.append(Self.spreadDegrees(barHeld))
            frameOnlyBar.append(Self.branchCountF(frame: barHeld, live: fv, stems: stems,
                                                  stemsHeld: stemsHeld)
                                - Self.tipBranchesF(frame: barHeld, live: fv, stems: stems,
                                                    stemsHeld: stemsHeld))
        }
        let seconds = (rows.last?["time"] ?? 0) - (rows.first?["time"] ?? 0)
        // TURNS PER BEAT is the UNIT THE TRUNK BAR IS ASSERTED IN (FTR.12c, Matt's call
        // 2026-08-12), because a beat-held signal can only change ON a beat — its per-second
        // turn rate therefore carries the tempo as a factor, and an absolute per-second floor
        // is silently stricter on fast songs for no musical reason. Seven Nation Army (124 BPM)
        // measured 0.66/s against Carry The Zero's (94 BPM) 0.52/s, which is 0.32/beat on BOTH.
        // Per second is still printed for every row, because the continuously-driven rows
        // (tips, and the "continuous" comparators) are NOT beat-held and their natural unit is
        // still per second.
        var wraps = 0
        var previousPhase: Double = 0
        for row in rows {
            let phase = row["beatPhase01"] ?? 0
            if phase < previousPhase - 0.25 { wraps += 1 }
            previousPhase = phase
        }
        let beatsPerSecond = Double(wraps) / Swift.max(seconds, 1)

        // THE TEMPO THIS UNIT DIVIDES BY MUST BE CROSS-CHECKED, or a red gate goes green for
        // the wrong reason. `beatPhase01` is derived from wrap counting, and a stalled phase is
        // a measured failure mode in this repo — one real 171 BPM session wrapped 24 times
        // where 614 were due. A stall makes `beatsPerSecond` tiny, which inflates turns/beat
        // and would fail LOUDLY; the dangerous direction is the opposite one, but either way
        // the honest response to an untrustworthy denominator is to refuse the measurement
        // rather than report a number in a unit that does not apply. `grid_bpm` is the
        // installed grid's own tempo and is independent of the phase clock.
        let gridBPMs = rows.compactMap { $0["grid_bpm"] }.filter { $0 > 20 && $0 < 300 }.sorted()
        guard !gridBPMs.isEmpty else {
            throw FractalTreeHarnessError.setupFailed("""
                no usable grid_bpm in \(csv.path) — turns/beat has no trustworthy denominator.
                """)
        }
        let gridBeatsPerSecond = gridBPMs[gridBPMs.count / 2] / 60
        let tempoAgreement = beatsPerSecond / Swift.max(gridBeatsPerSecond, 1e-6)
        guard tempoAgreement > 0.9, tempoAgreement < 1.1 else {
            throw FractalTreeHarnessError.setupFailed("""
                beatPhase01 wraps imply \(String(format: "%.3f", beatsPerSecond)) beats/s but \
                grid_bpm says \(String(format: "%.3f", gridBeatsPerSecond)) — a \
                \(String(format: "%.0f%%", 100 * tempoAgreement)) match. The phase clock is \
                not tracking this capture's grid, so turns/beat cannot be measured on it. \
                Fix the capture or the clock; do not reach for the per-second unit, which \
                carries the tempo (FTR.12c).
                """)
        }

        // Both span statistics, because they disagree by ~2× on this capture and the FTR.10
        // spec quotes the narrower one. p05→p95 is the honest "how far does it travel in
        // normal playback"; min→max includes the intro's climb out of the floor.
        func line(_ label: String, _ values: [Float]) -> String {
            let turns = Self.turnsPerSecond(values, seconds: seconds)
            return String(format: "  %-22@ span %.3f (p05→p95 %.3f)   turns %.2f/s  %.2f/beat",
                          label as NSString, Self.span(values), Self.percentileSpan(values),
                          turns, turns / Swift.max(beatsPerSecond, 1e-6))
        }
        print("""

        ── FTR.10 TRUNK ───────────────────────────────────────────────────
        session       \(session.lastPathComponent)   \(rows.count) rows / \
        \(String(format: "%.1f", seconds)) s
        hold engaged  \(String(format: "%.0f%%", 100 * Double(steppingFrames) / Double(rows.count))) \
        of frames
        tempo         \(String(format: "%.1f", beatsPerSecond * 60)) BPM from beatPhase01 wraps \
        vs \(String(format: "%.1f", gridBeatsPerSecond * 60)) from grid_bpm \
        (\(String(format: "%.0f%%", 100 * tempoAgreement)) — the turns/beat denominator)
        \(line("reach x 0.13", reachTerm))
        \(line("surge x 0.32", surgeTerm))
        \(line("trunk (continuous)", continuous))
        \(line("trunk (HELD)", stepped))
        \(line("count (continuous)", countLive))
        \(line("count (HELD)", countHeld))
        \(line("spread° (continuous)", spreadLive))
        \(line("spread° (HELD)", spreadHeld))
        \(line("  frame count, cont.", frameOnlyLive))
        \(line("  frame count, HELD", frameOnly))
        \(line("tips (always live)", tips))
        ───────────────────────────────────────────────────────────────────
        """)

        // FTR.12d — THE TRANSITION, which is what Matt's M7 describes and no whole-track
        // statistic can show. Split every layer by hold state and report both halves. If the
        // CONTINUOUS half is the one that reads better, the feature FTR.10/FTR.11 built is the
        // thing he is objecting to, and that is a product decision, not a tuning miss.
        let firstStepping = stepping.firstIndex(of: true)
        let playback = rows.map { $0["playback_time_s"] ?? $0["time"] ?? 0 }
        let framesPerSecond = Double(rows.count) / Swift.max(seconds, 1)

        var barWraps = 0
        var previousBarPhase: Double = 0
        for row in rows {
            let phase = (row["barPhase01_permille"] ?? 0) / 1000
            if phase < previousBarPhase - 0.25 { barWraps += 1 }
            previousBarPhase = phase
        }
        let barsPerSecond = Double(barWraps) / Swift.max(seconds, 1)

        /// One `layer × hold` row: how OFTEN it changes and how BIG each change is.
        /// Step size is measured only across frames where the value actually changed, so a
        /// held signal's long still stretches do not dilute it toward zero.
        func stepLine(_ label: String, _ values: [Float], _ hold: String) -> String {
            var deltas: [Float] = []
            for (a, b) in zip(values, values.dropFirst()) where a != b { deltas.append(abs(b - a)) }
            let perSecond = Double(deltas.count) / Swift.max(seconds, 1)
            let mean = deltas.isEmpty ? 0 : deltas.reduce(0, +) / Float(deltas.count)
            return "  " + label.padding(toLength: 24, withPad: " ", startingAt: 0)
                + hold.padding(toLength: 8, withPad: " ", startingAt: 0)
                + String(format: "%8.2f   %9.3f   %9.3f", perSecond, mean, deltas.max() ?? 0)
        }
        func splitLine(_ label: String, _ values: [Float]) -> String {
            func rate(_ want: Bool) -> String {
                let picked = zip(values, stepping).filter { $0.1 == want }.map(\.0)
                guard picked.count > 2 else { return "     —" }
                let turns = Self.turnsPerSecond(picked, seconds: Double(picked.count) / framesPerSecond)
                return String(format: "%5.2f/s %5.2f/beat",
                              turns, turns / Swift.max(beatsPerSecond, 1e-6))
            }
            return "  " + label.padding(toLength: 22, withPad: " ", startingAt: 0)
                + "cont " + rate(false) + "   held " + rate(true)
        }
        print("""
          hold engages at playback \(firstStepping.map { String(format: "%.1f s", playback[$0]) } ?? "never") \
        (\(stepping.filter { !$0 }.count) of \(rows.count) frames run continuous, \
        \(String(format: "%.1f s", Double(stepping.filter { !$0 }.count) / framesPerSecond)))
          BEFORE vs AFTER the hold engages — the transition Matt's M7 describes:
        \(splitLine("trunk", stepped))
        \(splitLine("frame count", frameOnly))
        \(splitLine("spread°", spreadHeld))
        \(splitLine("tips (never held)", tips))
        """)

        // FTR.12e — STEP SIZE, which is the quantity the whole FTR.10/FTR.11 arc never
        // measured. Every bar so far has been a turn RATE, and a rate cannot distinguish "holds
        // still then snaps" from "drifts" — it is why the frame read as calm at 0.30 turns/beat
        // while Matt saw the whole canopy stuttering. For a COUNT of branches the size of each
        // change is the thing that pops, and slowing the clock trades rate for size.
        // FTR.14b — TAU SWEEP. τ = 1/4 beat left ~49 of 95 rendered frames pixel-frozen in the
        // busiest passage, and the mechanism is convergence: the target is beat-latched, so it
        // only moves every ~38 render frames, and an exponential with τ = 0.25 beat closes 98 %
        // of the gap in two-thirds of a beat. Whatever is left is below a pixel. To never freeze,
        // τ must be large enough that the glide has NOT caught up when the next target lands.
        // The cost is lag and span compression (DYN.1e shipped a 10 % band Matt could not see),
        // so both are reported next to the freeze number and the choice is made on the table.
        //
        // "Still" here uses a PERCEPTUAL epsilon, not float inequality: one pixel of trunk at
        // 1080p is ~1/540 of clip space. Float inequality is what reported 0.005 frozen for a
        // build whose pixels were frozen on half of frames.
        func sweepLine(_ tau: Float) -> String {
            var probe = BeatHold(glideBeats: tau)
            var trunkSeries: [Float] = []
            var localFifths = FifthsSmoother()
            for (index, row) in rows.enumerated() {
                var fv = Self.featuresFromSession(row, fifths: &localFifths)
                Self.applyRecomputedDensity(densityByTime, at: row["time"] ?? 0, to: &fv,
                                            includeSectionRatio: true)
                let delta = index > 0
                    ? Float(min(max((rows[index]["wallclock_s"] ?? 0)
                                    - (rows[index - 1]["wallclock_s"] ?? 0), 1.0 / 240.0),
                                1.0 / 15.0))
                    : Float(1.0 / 60.0)
                trunkSeries.append(Self.trunkLength(probe.update(fv, renderDeltaTime: delta)))
            }
            let epsilon: Float = 1.0 / 540.0
            let still = zip(trunkSeries, trunkSeries.dropFirst())
                .filter { abs($1 - $0) < epsilon }.count
            let frozen = Double(still) / Double(trunkSeries.count - 1)
            let turns = Self.turnsPerSecond(trunkSeries, seconds: seconds)
                / Swift.max(beatsPerSecond, 1e-6)
            return String(format: "    τ %.2f beat   frozen %.3f   span %.3f (p05→p95 %.3f)   %.2f turns/beat",
                          tau, frozen, Self.span(trunkSeries),
                          Self.percentileSpan(trunkSeries), turns)
        }
        // FTR.14c — BURSTINESS, which is what "dancing the robot" actually is.
        //
        // Two metrics have now failed on this question and both failures are instructive.
        // Per-frame float inequality said 0.005 frozen for a build whose pixels were static on
        // half of frames. Per-frame PIXEL identity then said ~0.95 frozen at every τ — because a
        // trunk crossing 0.34 of clip space over a hundred seconds moves sub-pixel per frame
        // whatever it does, so "did this frame differ from the last" cannot separate smooth slow
        // motion from a freeze. A five-second pan is sub-pixel per frame too.
        //
        // The eye integrates motion over roughly 100 ms, so that is the window to measure in.
        // A robot puts all of its displacement into a few windows and none into the rest; smooth
        // motion spreads it evenly. So: total displacement per 100 ms window, then (a) the share
        // of windows with essentially none, and (b) the coefficient of variation across windows.
        // Low CV = even = smooth. High CV plus many empty windows = jump-hold-jump.
        func burstiness(_ values: [Float], label: String) -> String {
            let perWindow = Int((0.100 * framesPerSecond).rounded())
            guard perWindow > 1, values.count > perWindow * 4 else { return "    \(label): too short" }
            var travel: [Float] = []
            var index = 0
            while index + perWindow < values.count {
                var sum: Float = 0
                for k in index..<(index + perWindow) { sum += abs(values[k + 1] - values[k]) }
                travel.append(sum)
                index += perWindow
            }
            let mean = travel.reduce(0, +) / Float(travel.count)
            let variance = travel.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Float(travel.count)
            let cv = mean > 0 ? variance.squareRoot() / mean : 0
            let empty = Double(travel.filter { $0 < mean * 0.05 }.count) / Double(travel.count)
            return String(format: "    %-22@ empty windows %.3f   CV %.2f   mean travel %.4f",
                          label as NSString, empty, cv, mean)
        }
        print("  BURSTINESS per 100 ms window — a robot is bursty, smooth motion is even:")
        print(burstiness(continuous, label: "continuous (live)"))
        print(burstiness(stepped, label: "GLIDE (shipping)"))
        var hardProbe = BeatHold()
        var hardFifths = FifthsSmoother()
        var hardTrunk: [Float] = []
        for row in rows {
            var fv = Self.featuresFromSession(row, fifths: &hardFifths)
            Self.applyRecomputedDensity(densityByTime, at: row["time"] ?? 0, to: &fv,
                                        includeSectionRatio: true)
            hardTrunk.append(Self.trunkLength(hardProbe.update(fv)))
        }
        print(burstiness(hardTrunk, label: "HARD HOLD (FTR.10)"))

        print("  TAU SWEEP — trunk, perceptual epsilon (1 px at 1080p). Continuous span = \(String(format: "%.3f", Self.span(continuous))).")
        for tau in [Float(0.25), 0.40, 0.55, 0.70, 0.85] { print(sweepLine(tau)) }

        // FTR.14 — THE FREEZE FRACTION: the share of RENDERED frames on which a layer did not
        // change at all. This is the number that would have caught FTR.13 and did not exist:
        // its "smooth ease" left the canopy motionless on ~91 % of rendered frames, because a
        // 1/3-beat ease off a 10 Hz `beatPhase01` is 2.1 samples of motion and 4.3 of stillness.
        // Matt saw that as *"dancing the robot"*; every metric in this file agreed with the
        // build because they all measured turn RATE or step SIZE, and a freeze has a low rate
        // and a small step. A rate says how often direction changes, a size says how far — only
        // this says whether anything is moving AT ALL.
        func frozenFraction(_ values: [Float]) -> Double {
            guard values.count > 1 else { return 1 }
            let still = zip(values, values.dropFirst()).filter { $0 == $1 }.count
            return Double(still) / Double(values.count - 1)
        }
        print("""
          FROZEN FRACTION — share of rendered frames with NO change (FTR.13 read ~0.91 here)
            trunk        \(String(format: "%.3f", frozenFraction(stepped)))
            frame count  \(String(format: "%.3f", frozenFraction(frameOnly)))
            spread°      \(String(format: "%.3f", frozenFraction(spreadHeld)))
            tips         \(String(format: "%.3f", frozenFraction(tips)))
        """)
        print("""
          STEP SIZE vs STEP RATE, per-beat hold against a per-bar hold (\(String(format: "%.2f", beatsPerSecond / Swift.max(barsPerSecond, 1e-6))) beats/bar measured)
          A rate cannot tell "snaps" from "drifts". For a branch COUNT, size is what pops.
          layer                    hold    changes/s   mean step    max step
        \(stepLine("trunk", stepped, "beat"))
        \(stepLine("trunk", trunkBar, "bar"))
        \(stepLine("frame count", frameOnly, "beat"))
        \(stepLine("frame count", frameOnlyBar, "bar"))
        \(stepLine("spread°", spreadHeld, "beat"))
        \(stepLine("spread°", spreadBar, "bar"))
        \(stepLine("count incl. tips", countHeld, "beat"))
        \(stepLine("count incl. tips", countBar, "bar"))
        \(stepLine("tips", tips, "live"))
        """)

        // WHERE the trunk moves, in 5 s buckets. A motion-gate window picked without this is
        // picked blind: the span above is a whole-track figure, and most 10 s windows of a
        // rock track sit inside one section where the trunk barely moves at all. Reviewing
        // one of those and concluding "the trunk looks the same either way" is a false
        // negative about the increment, not a finding about it.
        let times = rows.map { $0["time"] ?? 0 }
        print("  trunk by 5 s bucket (continuous → held):")
        for mark in Swift.stride(from: times.first ?? 0, to: times.last ?? 0, by: 5.0) {
            let window = zip(times, zip(continuous, stepped))
                .filter { $0.0 >= mark && $0.0 < mark + 5 }.map(\.1)
            guard !window.isEmpty else { continue }
            let cont = window.map(\.0)
            let hold = window.map(\.1)
            print(String(format: "  %6.1f s  %.3f→%.3f (Δ%.3f)   held %.3f→%.3f  %@",
                         mark, cont.min() ?? 0, cont.max() ?? 0, Self.span(cont),
                         hold.min() ?? 0, hold.max() ?? 0,
                         String(repeating: "▉", count: Int((Self.span(cont) * 200).rounded()))))
        }

        // THE BAR IS TURNS PER BEAT (FTR.12c, Matt's call 2026-08-12). It was `<= 0.6` per
        // SECOND, which went red on Seven Nation Army (0.66/s) and green on Carry The Zero
        // (0.52/s) — but per BEAT both measure 0.32, because a beat-held value can only change
        // ON a beat, so the per-second unit carries the tempo and the bar was silently stricter
        // on faster songs for no musical reason.
        //
        // THE BAR ITSELF IS UNCHANGED, ONLY RE-EXPRESSED. It was calibrated on Carry The Zero
        // at 94.1 BPM = 1.568 beats/s, so `0.6/s ÷ 1.568 = 0.383/beat`. 0.38 is that same bar
        // in the new unit, on the same track, with the same headroom it always had — not a
        // widened budget. Both captures pass at 0.32/beat, which is why the unit change is
        // safe to make: it is not converting a red to a green by moving the line, it is
        // removing a tempo factor that was never meant to be in it. (Changing a metric in the
        // increment it goes red is the FTR.6 failure — which is exactly why FTR.11 left it red
        // and this is a separate commit that changes nothing else.)
        let heldTurnsPerSecond = Self.turnsPerSecond(stepped, seconds: seconds)
        let heldTurnsPerBeat = heldTurnsPerSecond / Swift.max(beatsPerSecond, 1e-6)
        #expect(heldTurnsPerBeat <= 0.38, """
            the held trunk turns \(String(format: "%.2f", heldTurnsPerBeat))/beat \
            (\(String(format: "%.2f", heldTurnsPerSecond))/s at \
            \(String(format: "%.1f", beatsPerSecond * 60)) BPM). Matt's complaint is motion, \
            and this preset's own rule is that anything past ~1 turn/s reads as the tree \
            bouncing rather than growing; a stepped trunk has to be well under it, not \
            marginally under. Do NOT widen this bar — re-derive it from the tempo if the \
            unit is ever questioned again (FTR.12c).
            """)
        let ratio = Double(Self.span(stepped) / Swift.max(Self.span(continuous), 1e-6))
        #expect(ratio > 0.9, """
            the held trunk spans \(String(format: "%.3f", Self.span(stepped))) against the \
            continuous \(String(format: "%.3f", Self.span(continuous))) — \
            \(String(format: "%.0f%%", 100 * ratio)) of the range. Losing range to buy \
            stillness is the DYN.1e failure ("neither grew nor receded"), and it is what a \
            smoother would have done here.
            """)
        // FTR.11 — THE TWO LAYERS FTR.10 LEFT RUNNING. Asserted as RATIOS against the
        // continuous build measured in the same run, not as absolute floors: a per-second
        // floor carries the tempo (see the turns/beat note above), and these two would then
        // need recalibrating per track, which is how a gate stops meaning anything.
        let frameRatio = Self.turnsPerSecond(frameOnly, seconds: seconds)
            / Swift.max(Self.turnsPerSecond(frameOnlyLive, seconds: seconds), 1e-6)
        #expect(frameRatio < 0.5, """
            the branch count's FRAME term turns \(String(format: "%.0f%%", 100 * frameRatio)) \
            as often held as continuous. This is the layer Matt named second ("the trunk and \
            branches") and the one FTR.10 left at 4.08/s while reporting the trunk fixed.
            """)
        let spreadRatio = Self.turnsPerSecond(spreadHeld, seconds: seconds)
            / Swift.max(Self.turnsPerSecond(spreadLive, seconds: seconds), 1e-6)
        #expect(spreadRatio < 0.5, """
            the branch spread turns \(String(format: "%.0f%%", 100 * spreadRatio)) as often \
            held as continuous. `spectral_flux` made this the fastest term in the preset \
            (5.48/s, against the trunk's 0.66).
            """)
        // THE TIPS: ALIVE, BUT BEAT-MATCHED — a TWO-SIDED bar, and the replacement for a
        // one-sided floor that Matt's instruction turned into a contradiction.
        //
        // THE PREVIOUS FORM AND WHY IT IS GONE, stated rather than quietly relaxed (the FTR.6
        // failure was lowering a gate's floor to ship). It read `tipTurns > 1.5`/s, written when
        // the tips were the only continuously-moving layer and the risk was that someone froze
        // them. Matt's M7 on FTR.11 inverted that risk: *"the tips probably are still moving too
        // fast if they change 2x per beat — should be beat matched."* Measured, they were turning
        // 2.05/beat. A floor of 1.5/s is ~0.9–1.0 turns/BEAT at 94–124 BPM, so the old gate
        // required almost exactly the behaviour he rejected. It is not being loosened; it is
        // being replaced with the bar the instruction implies.
        //
        // The original concern is still gated, by the lower bound: the tips must not FREEZE.
        // Measured after FTR.13 they sit at 0.49–0.56 turns/beat across three captures, so both
        // bounds carry real headroom — this is not a bar drawn around a measurement.
        let tipTurnsPerBeat = Self.turnsPerSecond(tips, seconds: seconds)
            / Swift.max(beatsPerSecond, 1e-6)
        #expect(tipTurnsPerBeat > 0.15, """
            the tips turn only \(String(format: "%.2f", tipTurnsPerBeat))/beat — beat-matched \
            must not mean frozen. With the frame stepping too, tips that stop make the preset \
            a slideshow, which is the opposite of Matt's original "hard to see" complaint.
            """)
        #expect(tipTurnsPerBeat <= 1.0, """
            the tips turn \(String(format: "%.2f", tipTurnsPerBeat))/beat. Matt asked for them \
            beat-matched after measuring 2.05/beat live and calling it stuttering; a \
            beat-matched layer cannot change more than once per beat by definition. Do NOT \
            raise this bar — if a tip layer needs to move faster than the beat, that is a \
            routing decision and his.
            """)

        // FTR.14c — NOTHING MAY BE BURSTY. This is the gate for "dancing the robot", and it is
        // the third metric attempted on that question — the two it replaces are recorded above
        // because both PASSED the build Matt rejected. The bar is set from a measured separation
        // between two references on this very capture, not drawn around the shipping number:
        //
        //   hard hold (the rejected look)   empty 0.817   CV 3.51
        //   continuous (the preferred look) empty 0.083   CV 1.81
        //   glide (shipping)                empty 0.101   CV 1.64
        //
        // A metric that cannot separate the first row from the second is not evidence, whatever
        // it reports for the third. If a future build fails this, do NOT relax it: an empty
        // window means the geometry gave the eye nothing for 100 ms, which is the complaint.
        let perWindow = Int((0.100 * framesPerSecond).rounded())
        for (label, series) in [("trunk", stepped), ("frame count", frameOnly),
                                ("spread", spreadHeld)] {
            guard series.count > perWindow * 4 else { continue }
            var travel: [Float] = []
            var index = 0
            while index + perWindow < series.count {
                var sum: Float = 0
                for k in index..<(index + perWindow) { sum += abs(series[k + 1] - series[k]) }
                travel.append(sum)
                index += perWindow
            }
            let mean = travel.reduce(0, +) / Float(travel.count)
            let empty = Double(travel.filter { $0 < mean * 0.05 }.count) / Double(travel.count)
            #expect(empty < 0.35, """
                \(label) gave the eye NOTHING in \(String(format: "%.0f%%", 100 * empty)) of \
                100 ms windows. The hard hold Matt rejected three times measures 0.82 here and \
                the continuous look he prefers measures 0.08 — this bar is the difference \
                between them. The beat may set the destination; it may not set the stillness.
                """)
        }

        #expect(steppingFrames > rows.count / 2, """
            the hold engaged on only \(steppingFrames) of \(rows.count) frames — on a capture \
            with a healthy cached grid it should hold for nearly the whole body of the track. \
            Below half, this report is measuring the fallback path, not the feature.
            """)
    }

    /// The shader's `fractal_growth()`, mirrored (FractalTree.metal).
    ///
    /// A Swift copy of shader arithmetic is exactly the drift that let FTR.6 ship a
    /// regression past a green harness, so the mirror is kept honest two ways: it is the
    /// ONLY copy in this file, and `objectStageReadsTheBeatHeldVector` proves through the
    /// real pipeline that the GPU is reading the held vector this report models.
    private static func growth(_ f: FeatureVector,
                               section: FeatureVector? = nil,
                               accent: Float = 0) -> (reach: Float, surge: Float) {
        func saturate(_ v: Float) -> Float { Swift.min(Swift.max(v, 0), 1) }
        func smoothstep(_ e0: Float, _ e1: Float, _ v: Float) -> Float {
            let t = saturate((v - e0) / (e1 - e0))
            return t * t * (3 - 2 * t)
        }
        let arousalReach = saturate((f.arousal - 0.10) / 0.58)
        let fullness = saturate(f.spectralSectionRatio * 0.5)
        let gate = smoothstep(0.05, 0.30, saturate(f.spectralSurge))

        // FTR.24 — TWO DIVERGENCES FIXED HERE, both found while wiring the size accent.
        //
        // 1. `section` was declared and NEVER READ. FTR.18's whole shipped change is the
        //    bounded limiter correction `level + max(0, density - level) * inverted`, taken
        //    from the section glide — so from FTR.18 to FTR.23 this mirror modelled a size
        //    term the shader had stopped using, and every trunk figure in the report was of
        //    the uncorrected build. When `section` is nil the correction is simply absent,
        //    which is the honest answer for a caller that has no section vector to give.
        // 2. FTR.24's accent term was here for one day and is gone with its consumer (Matt:
        //    *"herky-jerky … looks defective"*); the `accent` parameter is kept because the
        //    FT_ACCENT_FROM_TAP probe still measures what a future consumer WOULD see.
        let level = saturate(f.spectralSurge)
        let corrected: Float
        if let section {
            let density = saturate(section.spectralDensity / (section.spectralDensity + 0.22))
            let inverted = 1 - smoothstep(0.15, 0.40, level)
            corrected = saturate(level + Swift.max(0, density - level) * inverted)
        } else {
            corrected = level
        }
        return (saturate(Swift.max(0.10 * arousalReach, fullness) * gate), corrected)
    }

    /// The shader's `trunk_len` (FractalTree.metal), mirrored — see ``growth(_:)``.
    private static func trunkLength(_ f: FeatureVector,
                                    section: FeatureVector? = nil,
                                    accent: Float = 0) -> Float {
        let g = growth(f, section: section, accent: accent)
        return 0.27 + g.reach * 0.13 + g.surge * 0.32
    }

    /// The shader's branch-count arithmetic, mirrored — see ``growth(_:)``.
    ///
    /// `frame` is the vector the FRAME terms read (beat-held since FTR.11), `live` the one
    /// the tips read. Passing the same vector for both gives the pre-FTR.11 continuous
    /// build, which is what makes the before/after column in the report an A/B rather than
    /// two separate runs.
    /// FTR.13 — FRACTIONAL, mirroring the shader's `countF`. Rounding here would hide the very
    /// thing the grow-in was built to fix: the shader renders `ceil(countF)` slots and scales
    /// the frontier branch's LENGTH by `countF - bid`, so the visible canopy changes
    /// continuously where an integer count popped. An `Int` mirror reports the pop that the
    /// shader no longer draws.
    private static func branchCountF(frame: FeatureVector, live: FeatureVector,
                                     stems: StemFeatures, stemsHeld: StemFeatures) -> Float {
        let g = growth(frame)
        let lift = clamp((frame.spectralDensity / max(frame.spectralDensitySlow, 1e-4) - 1) * 1.1)
        let amp = clamp(live.pulseAmp01)
        let base = (4.0 + g.reach * 18.0) * amp
        let section = (lift * 8.0 + g.surge * 26.0) * amp
        let tips = tipBranchesF(frame: frame, live: live, stems: stems, stemsHeld: stemsHeld)
        return Swift.min(7 + base + section + tips, 63)
    }

    private static func branchCount(frame: FeatureVector, live: FeatureVector,
                                    stems: StemFeatures) -> Int {
        Int(branchCountF(frame: frame, live: live, stems: stems, stemsHeld: stems).rounded(.up))
    }

    /// The tips term alone.
    ///
    /// FTR.13 — both halves read the HELD side (`stemsHeld`, and `frame` for `beat_mid`), which
    /// is what "beat matched" means. `stems` stays live for the D-019 arrival gate only: that
    /// asks "have the stems converged yet", and reading a beat-held copy would pin it at zero
    /// until the first beat lands.
    private static func tipBranchesF(frame: FeatureVector, live: FeatureVector,
                                     stems: StemFeatures, stemsHeld: StemFeatures) -> Float {
        let rate = stemsHeld.otherOnsetRate
        let residueActivity = rate / (rate + 18.0)
        let stemEnergy = stems.vocalsEnergy + stems.drumsEnergy + stems.bassEnergy + stems.otherEnergy
        let alive = smoothstep(0.02, 0.06, stemEnergy)
        let melody = (1 - alive) * (frame.beatMid / (frame.beatMid + 2.2)) + alive * residueActivity
        return melody * 26.0 * clamp(live.pulseAmp01)
            * smoothstep(0.03, 0.15, growth(frame).reach)
    }

    private static func tipBranches(frame: FeatureVector, live: FeatureVector,
                                    stems: StemFeatures) -> Int {
        Int(tipBranchesF(frame: frame, live: live, stems: stems, stemsHeld: stems))
    }

    /// Branch spread in degrees — the fastest-moving term in the preset before FTR.11.
    private static func spreadDegrees(_ f: FeatureVector) -> Float {
        let flux = clamp((f.spectralFlux - 0.10) / 0.85)
        return (0.35 + flux * 0.24) * 180 / .pi
    }

    private static func clamp(_ v: Float) -> Float { Swift.min(Swift.max(v, 0), 1) }

    private static func smoothstep(_ e0: Float, _ e1: Float, _ v: Float) -> Float {
        let t = clamp((v - e0) / (e1 - e0))
        return t * t * (3 - 2 * t)
    }

    private static func span(_ values: [Float]) -> Float {
        (values.max() ?? 0) - (values.min() ?? 0)
    }

    private static func percentileSpan(_ values: [Float]) -> Float {
        guard values.count > 20 else { return span(values) }
        let sorted = values.sorted()
        return sorted[sorted.count * 19 / 20] - sorted[sorted.count / 20]
    }

    /// Direction changes per second — the metric FTR.9 reported the canopy in, and the one
    /// the preset's "faster than ~1 turn/s reads as bouncing" rule is written against.
    private static func turnsPerSecond(_ values: [Float], seconds: Double) -> Double {
        let deltas = zip(values, values.dropFirst()).map { $1 - $0 }.filter { $0 != 0 }
        let flips = zip(deltas, deltas.dropFirst()).filter { $0 * $1 < 0 }.count
        return Double(flips) / Swift.max(seconds, 1)
    }

    /// FTR.10 — proof that the OBJECT stage reads the beat-held FeatureVector at buffer(4).
    ///
    /// Binding a buffer and the GPU reading it are different claims (FTR.4's lesson, and the
    /// five months `vocalsPitchConfidence` sat dead while closeouts said otherwise). This
    /// drives the REAL `MeshGenerator` with a steady synthetic beat clock until the hold
    /// engages, then renders a frame whose LIVE surge has jumped — mid-beat, so the held
    /// vector still carries the old value. The tree must render at its OLD height. A
    /// generator that never saw the clock renders the same live frame taller.
    @Test("the object stage reads the beat-held FeatureVector at buffer(4) (FTR.10)")
    func objectStageReadsTheBeatHeldVector() throws {
        let ctx = try MetalContext()
        let loader = PresetLoader(device: ctx.device, pixelFormat: ctx.pixelFormat,
                                  loadBuiltIn: true)
        let preset = try #require(loader.presets.first { $0.descriptor.name == "Fractal Tree" })
        let target = try Self.makeTexture(ctx)

        func makeGenerator() -> MeshGenerator {
            MeshGenerator(device: ctx.device, pipelineState: preset.pipelineState,
                          configuration: .init(maxVerticesPerMeshlet: 252,
                                               maxPrimitivesPerMeshlet: 126,
                                               meshThreadCount: preset.descriptor.meshThreadCount))
        }
        /// A frame on a steady 120 BPM grid. `surge` and the section ratio are what the trunk
        /// reads; `pulse_amp01` keeps the silence gate open.
        func frame(time: Float, surge: Float) -> FeatureVector {
            var f = Self.baseFeatures()
            f.time = time
            f.beatPhase01 = (time.truncatingRemainder(dividingBy: 0.5)) / 0.5
            f.barPhase01 = (time.truncatingRemainder(dividingBy: 2.0)) / 2.0
            f.beatsPerBar = 4
            f.pulseAmp01 = 1
            f.arousal = 0.6
            f.spectralSurge = surge
            f.spectralSectionRatio = surge * 2
            return f
        }

        // Ten seconds of quiet, steady beats at the ~10 Hz analysis rate — twenty beats,
        // enough for the hold to engage after eight consistent intervals.
        let warm = makeGenerator()
        for tick in 0...101 { warm.advanceBeatHold(frame(time: Float(tick) * 0.1, surge: 0.10)) }

        // t = 10.25 s is mid-beat (the last beat was 10.0, the last fed frame 10.1): the live
        // surge slams to 1.0 but the held vector still carries the 0.10 sampled on the beat,
        // so the trunk must still be short. Feeding a frame that itself crossed a beat would
        // re-sample the hold and prove nothing.
        let loud = frame(time: 10.25, surge: 1.0)
        func render(_ generator: MeshGenerator) throws -> [UInt8] {
            guard let cmd = ctx.commandQueue.makeCommandBuffer() else {
                throw FractalTreeHarnessError.setupFailed("no command buffer")
            }
            Self.encode(cmd, into: target, generator: generator, features: loud, stems: .zero)
            cmd.commit()
            cmd.waitUntilCompleted()
            return Self.read(target)
        }
        let heldFrame = try render(warm)
        let freshFrame = try render(makeGenerator())

        let heldHeight = Self.canopyHeight(heldFrame)
        let freshHeight = Self.canopyHeight(freshFrame)
        print(String(format: "[fractal-tree/hold] canopy height held %.4f vs unheld %.4f",
                     heldHeight, freshHeight))
        #expect(heldHeight < freshHeight * 0.95, """
            the tree rendered the same height (\(heldHeight) vs \(freshHeight)) whether or not \
            the beat hold had engaged. Either buffer(4) is not bound on the object stage or \
            the shader is not reading it — the trunk is still sliding with the live surge and \
            everything this increment reports is measuring a mirror, not the GPU.
            """)
    }

    /// Parse a recorded `features.csv` into rows keyed by column name, dropping the
    /// malformed startup lines a live capture can contain.
    /// StemFeatures for one row of a recorded session's `stems.csv` (FTR.4/FTR.8).
    ///
    /// The sequence harness drives from a real capture, and the tips are now a stem route —
    /// passing `.zero` here would render the hero route silent and report it dead, the
    /// Faraday trap. Rows are index-aligned: `SessionRecorder` writes features.csv and
    /// stems.csv one row per render frame from the same tick.
    private static func sessionStems(_ rows: [[String: Double]], index: Int) -> StemFeatures {
        guard index < rows.count else { return .zero }
        let row = rows[index]
        func value(_ key: String) -> Float { Float(row[key] ?? 0) }
        var st = StemFeatures.zero
        st.otherOnsetRate = value("otherOnsetRate")
        st.vocalsEnergy = value("vocalsEnergy")
        st.drumsEnergy = value("drumsEnergy")
        st.bassEnergy = value("bassEnergy")
        st.otherEnergy = value("otherEnergy")
        return st
    }

    /// - Parameter dropBeforeSeconds: skip rows before this `time`. **`stems.csv` has no
    ///   `time` column**, so a loader that filters on one unconditionally returns ZERO rows
    ///   for it — which is exactly what happened the first time the sequence harness tried
    ///   to read stems, and is why `sessionStems` warns rather than silently rendering the
    ///   hero route at zero. Pass nil for stems and align with `leadingRowsDropped`.
    private static func loadSessionRows(_ url: URL,
                                        dropBeforeSeconds: Double? = 15) throws -> [[String: Double]] {
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
            if let cutoff = dropBeforeSeconds {
                guard let time = row["time"], time >= cutoff else { continue }
            }
            out.append(row)
        }
        return out
    }

    /// How many leading rows the features loader dropped, so `stems.csv` — loaded unfiltered
    /// — can be indexed alongside it. `SessionRecorder` writes both files one row per render
    /// frame from the same tick, so a constant offset is the whole alignment.
    private static func leadingRowsDropped(_ url: URL) throws -> Int {
        let all = try loadSessionRows(url, dropBeforeSeconds: nil)
        let kept = try loadSessionRows(url)
        return max(all.count - kept.count, 0)
    }

    /// Same field set as the fixture drive — kept together so a new route is added to
    /// both in one edit, which is the trap that has bitten three times already.
    /// Vector-domain EMA mirroring `TonalAnalyzer.smoothPhaseFifths`. A recorded capture
    /// holds the RAW phase, so replaying it straight would still show the pre-fix flashing
    /// no matter what the engine now does. Kept in lockstep with the analyzer's alpha.
    /// ⚠ FTR.19 — THIS NO LONGER SMOOTHS, AND THAT IS THE FIX.
    ///
    /// Until FTR.19 this applied a circular EMA to `tonal_phase_fifths` while PRODUCTION read the
    /// field raw, so every offline render and contact sheet showed a smooth hue drift (p95 2.8° per
    /// analysis update) while the shipping build jumped up to 180° roughly 1.5 times a second —
    /// Matt's *"colour changes feel glitchy, not intentional."* A harness that quietly repairs an
    /// input is not replaying the production path.
    ///
    /// The smoothing now lives in `MeshGenerator` (`CircularPhaseSmoother`, D-209), which is where
    /// production does it, so this must pass the value through untouched or renders would be
    /// double-smoothed and once again disagree with the app.
    private struct FifthsSmoother {
        mutating func callAsFunction(_ raw: Float) -> Float { raw }
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
        // DYN.2/FTR.9 — the canopy's own two drivers, which this builder did not carry until
        // FTR.10. Every caller happened to overwrite them from `applyRecomputedDensity`, so
        // the omission was invisible; a caller that did not would have measured a trunk pinned
        // at its silence floor and called the route dead.
        f.spectralSurge = value("spectral_surge")
        f.spectralSectionRatio = value("spectral_section_ratio")
        f.spectralLevelRise = value("spectral_level_rise")   // FTR.24; 0 on older captures
        f.time = value("time")
        return f
    }

    /// Run the REAL `SpectralAnalyzer` over the capture's audio, returning
    /// (audioTime, density, densitySlow) at the ~10 Hz analysis rate.
    /// Recomputed density fields for a capture, INCLUDING the section ratio (FTR.9).
    ///
    /// The ratio was the one field this recompute did not carry, so the sequence replayed
    /// whatever the recording's build wrote — which after FTR.9 means the OLD, unsmoothed
    /// value, and a motion gate that measures the behaviour the increment just changed. A
    /// `LoudnessProfile` is measured from the capture itself so the ratio takes its RANKED
    /// branch; without one it silently falls back to the DYN.2b live EMA and the whole
    /// canopy reads wrong.
    private static func recomputeDensity(wav: URL) throws -> [(Double, Float, Float, Float, Float, Float)] {
        let samples = try SpectralDensityRealAudioTests.loadFloatWavMonoShared(wav)
        guard !samples.isEmpty else { return [] }
        let analyzer = SpectralAnalyzer(binCount: 512, sampleRate: 48000, fftSize: 1024)
        analyzer.setLoudnessProfile(LoudnessProfile.measure(samples: samples, sampleRate: 48000))
        let hop = 4800
        var out: [(Double, Float, Float, Float, Float, Float)] = []
        var start = 0
        while start + 1024 <= samples.count {
            let frame = Array(samples[start..<(start + 1024)])
            let result = analyzer.process(
                magnitudes: try SpectralDensityRealAudioTests.magnitudesShared(of: frame),
                deltaTime: Float(hop) / 48000)
            // FTR.24 — `levelRise` rides along. A capture recorded before the field existed
            // has no column for it, so a REPLAYED run feeds ZERO and the accent is invisible:
            // exactly the harness-carries-every-route trap that hid the FTR.19 hue defect for
            // 17 increments. FT_RECOMPUTE=1 is the only way to see the accent on an old capture.
            out.append((Double(start) / 48000, result.density, result.smoothedDensity,
                        result.surge, result.sectionRatio, result.levelRise))
            start += hop
        }
        return out
    }

    /// The capture's `time` column and the audio share an origin at recording start.
    private static func applyRecomputedDensity(_ table: [(Double, Float, Float, Float, Float, Float)],
                                               at time: Double,
                                               to fv: inout FeatureVector,
                                               includeSectionRatio: Bool) {
        guard !table.isEmpty else { return }
        let index = Swift.min(Swift.max(Int(time * 10), 0), table.count - 1)
        fv.spectralDensity = table[index].1
        fv.spectralDensitySlow = table[index].2
        fv.spectralSurge = table[index].3
        // FTR.9 — the canopy's own driver, but only where a single-track profile is valid.
        if includeSectionRatio { fv.spectralSectionRatio = table[index].4 }
        fv.spectralLevelRise = table[index].5   // FTR.24
    }

    /// FTR.24 — the accent field ALONE, for `FT_ACCENT_FROM_TAP=1`. Same table, same lookup,
    /// deliberately touching nothing else: the point is to leave the recording's own base
    /// untouched while giving the one column it predates.
    private static func applyRecomputedLevelRise(
        _ table: [(Double, Float, Float, Float, Float, Float)],
        at time: Double,
        to fv: inout FeatureVector
    ) {
        guard !table.isEmpty else { return }
        let index = Swift.min(Swift.max(Int(time * 10), 0), table.count - 1)
        fv.spectralLevelRise = table[index].5
    }

    /// Distinct tracks in a recorded session, from its log. Zero when the log is absent —
    /// treated as "unknown", i.e. do not recompute.
    private static func trackCount(inSessionAt directory: URL) -> Int {
        guard let log = try? String(contentsOf: directory.appendingPathComponent("session.log"),
                                    encoding: .utf8) else { return 0 }
        var titles = Set<String>()
        for line in log.split(separator: "\n") where line.contains("track='") {
            guard let start = line.range(of: "track='"),
                  let end = line[start.upperBound...].firstIndex(of: "'") else { continue }
            titles.insert(String(line[start.upperBound..<end]))
        }
        return titles.count
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
              let beatMid = series.floatSeries("beatMid"),
              let onsetRate = series.floatSeries("otherOnsetRate") else {
            throw FractalTreeHarnessError.setupFailed("time/arousal/beatMid/otherOnsetRate absent")
        }

        // The shader's own arithmetic, mirrored. `amp` is 1: the fixtures are music
        // throughout, and the silence gate is covered by the D-037 render assertion.
        let rows = (0..<min(time.count, arousal.count)).filter { (time[$0] ?? 0) >= 10.0 }
        // FTR.8 — mirror the SHIPPED driver. The tips read the guitar's onset rate through
        // `r/(r+6.5)`; modelling the retired `beat_mid` knee here would measure a build that
        // no longer exists, which is how FTR.6 shipped a regression past a green harness.
        // Stems are alive across this fixture, so the D-019 crossfade sits at the guitar end.
        let melody = rows.map { Double(onsetRate[$0] ?? 0) / (Double(onsetRate[$0] ?? 0) + 18.0) }
        _ = beatMid
        let growthEnv = rows.map { min(max((Double(arousal[$0] ?? 0) - 0.10) / 0.58, 0), 1) }
        let structure = rows.map { row -> Int in
            let reach = min(max((Double(arousal[row] ?? 0) - 0.10) / 0.58, 0), 1)
            return Int(4.0 + reach * 18.0)
        }
        // FTR.9 — mirror the SHIPPED gate, smoothstep(0.03, 0.15).
        let tips = zip(melody, growthEnv).map { m, g -> Int in
            let t = min(max((g - 0.03) / 0.12, 0), 1)
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

    /// FTR.4 — proof that the OBJECT stage reads `StemFeatures` at buffer(3).
    ///
    /// Binding a buffer and the GPU reading it are different claims, and only the second one
    /// matters. This renders the SAME `FeatureVector` twice, changing nothing but
    /// `other_onset_rate`, and requires the pixels to differ. If the object binding were
    /// missing or landed on the wrong slot, both frames would be identical and every stem
    /// route on every future mesh preset would be silently dead — the class of failure that
    /// left `vocalsPitchConfidence` at 0 % for five months while closeouts claimed it worked.
    @Test("the object stage reads StemFeatures at buffer(3) (FTR.4)")
    func objectStageReceivesStems() throws {
        let ctx = try MetalContext()
        let loader = PresetLoader(device: ctx.device, pixelFormat: ctx.pixelFormat,
                                  loadBuiltIn: true)
        let preset = try #require(loader.presets.first { $0.descriptor.name == "Fractal Tree" })
        let generator = MeshGenerator(
            device: ctx.device, pipelineState: preset.pipelineState,
            configuration: .init(maxVerticesPerMeshlet: 252, maxPrimitivesPerMeshlet: 126,
                                 meshThreadCount: preset.descriptor.meshThreadCount))
        let target = try Self.makeTexture(ctx)

        // A frame the growth gate lets the tips through on: the tips are multiplied by
        // `smoothstep(0, 0.35, reach)`, so with a dead canopy this test would pass for the
        // wrong reason (both frames identically empty).
        var features = Self.baseFeatures()
        features.arousal = 0.65
        features.spectralSectionRatio = 1.6
        features.spectralSurge = 0.9
        features.pulseAmp01 = 1
        features.aspectRatio = Float(Self.width) / Float(Self.height)

        func render(onsetRate: Float) throws -> [UInt8] {
            var stems = StemFeatures.zero
            // Stems must read ALIVE or the D-019 crossfade holds the tips on `beat_mid` and
            // the guitar value never reaches the count.
            stems.vocalsEnergy = 0.05; stems.drumsEnergy = 0.05
            stems.bassEnergy = 0.05; stems.otherEnergy = 0.05
            stems.otherOnsetRate = onsetRate
            let cmd = try #require(ctx.commandQueue.makeCommandBuffer())
            Self.encode(cmd, into: target, generator: generator, features: features, stems: stems)
            cmd.commit()
            cmd.waitUntilCompleted()
            #expect(cmd.status == .completed)
            return Self.read(target)
        }

        let quiet = try render(onsetRate: 0.3)
        let busy = try render(onsetRate: 6.0)
        #expect(quiet.count == busy.count && !quiet.isEmpty)
        let differing = zip(quiet, busy).filter { $0 != $1 }.count
        #expect(differing > 0, """
            a 20× change in other_onset_rate produced a byte-identical frame. The object \
            stage is not reading StemFeatures at buffer(3) — binding it is not the same as \
            the GPU consuming it, and every mesh stem route depends on this.
            """)
        // And the busier guitar must produce MORE tree, not merely a different one.
        let quietInk = quiet.enumerated().filter { $0.offset % 4 != 3 && $0.element > 24 }.count
        let busyInk = busy.enumerated().filter { $0.offset % 4 != 3 && $0.element > 24 }.count
        #expect(busyInk > quietInk, """
            busy guitar drew \(busyInk) lit subpixels against quiet's \(quietInk) — the route \
            reaches the GPU but points the wrong way.
            """)
    }

    // MARK: - Drive

    private struct Drive {
        let label: String
        let features: FeatureVector
        let stems: StemFeatures
    }

    /// Build the StemFeatures the preset reads from one fixture row (FTR.4/FTR.8).
    ///
    /// `SessionColumnSeries.floatSeries` falls through to stems.csv, so these come from the
    /// same fixture rows as the FeatureVector — real separated stems on real music, not a
    /// hand-authored envelope (FA #27). Only the fields Fractal Tree consumes are populated;
    /// `other_onset_rate` is the hero route and the four energies drive the D-019 warmup
    /// crossfade, so a zero there would silently hold the tips on their cold-start driver.
    private static func stems(_ s: SessionColumnSeries, row: Int) -> StemFeatures {
        func value(_ column: String) -> Float {
            guard let series = s.floatSeries(column), row < series.count else { return 0 }
            return series[row] ?? 0
        }
        var st = StemFeatures.zero
        st.otherOnsetRate = value("otherOnsetRate")
        st.vocalsEnergy = value("vocalsEnergy")
        st.drumsEnergy = value("drumsEnergy")
        st.bassEnergy = value("bassEnergy")
        st.otherEnergy = value("otherEnergy")
        return st
    }

    /// Silence plus four real-music frames, chosen at percentiles of `bass` so the sheet
    /// spans the track's actual dynamic range rather than three arbitrary rows.
    private static func driveFrames() throws -> [Drive] {
        // Silence must include SILENT STEMS: with stems at zero the D-019 crossfade holds
        // the tips on their cold-start driver, which is exactly the state a real track's
        // first seconds are in, and the D-037 non-black floor has to survive it.
        var out = [Drive(label: "silence", features: Self.baseFeatures(), stems: .zero)]

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
            out.append(Drive(label: label, features: Self.features(series, row: row),
                             stems: Self.stems(series, row: row)))
        }

        // Two frames ranked by HARMONY instead of energy. Without these the sheet cannot
        // show the hue route at all: sampling by bass holds the harmonic phase roughly
        // constant, so the leaf colour looks static when it is in fact tracking a
        // primitive this axis does not vary. One route, one sampling axis.
        if let tonal = series.floatSeries("tonal_phase_fifths") {
            let byTonal = warm.filter { $0 < tonal.count }
                .sorted { (tonal[$0] ?? 0) < (tonal[$1] ?? 0) }
            if let low = byTonal.first, let high = byTonal.last {
                out.append(Drive(label: "harm-lo", features: Self.features(series, row: low),
                                 stems: Self.stems(series, row: low)))
                out.append(Drive(label: "harm-hi", features: Self.features(series, row: high),
                                 stems: Self.stems(series, row: high)))
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

    /// FTR.4/FTR.8 — `stems` is not optional here on purpose. The tips now read
    /// `stems.other_onset_rate`, and a harness that let it default to `.zero` would drive the
    /// hero route with silence and then report it dead. That is the Faraday failure (a route
    /// measured at r = −0.019 that was really +0.868) and the reason the drive builder must
    /// be updated in the SAME commit as any new route.
    private static func encode(_ cmd: MTLCommandBuffer, into texture: MTLTexture,
                               generator: MeshGenerator, features: FeatureVector,
                               stems: StemFeatures) {
        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = texture
        rpd.colorAttachments[0].loadAction = .clear
        rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        rpd.colorAttachments[0].storeAction = .store
        guard let enc = cmd.makeRenderCommandEncoder(descriptor: rpd) else { return }
        generator.draw(encoder: enc, features: features, stems: stems)
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
