// GlazeMVWarpAccumulationTest — Glaze (jelly showoff parade port) production-pipeline test.
//
// Modelled on NacreMVWarpAccumulationTest. Per the preset session checklist: a preset with
// a temporal feedback contract must be tested on the SAME dispatch path the live app uses
// (warp → comp → swap), not single-frame `pipelineState` checks.
//
// ── GLAZE.2a (STUB) ─────────────────────────────────────────────────────────────────
//   1. Static guards: the .metal declares scene + warp + comp + mv_warp fns; the .json
//      declares the right passes (cheap regression sentries against a silent drop).
//   2. Compile/load guard: the preset loads with its custom warp + comp pipelines.
//   3. Accumulation gate (ALWAYS run): drive `renderGlaze` ≥60 frames at silence through
//      the live dispatch path; assert the field stays NON-BLACK (D-019 — the seed sustains
//      it) and never WHITES OUT (the HDR-feedback trip-wire).
//   4. Reduced-motion gate (BUG-061): the .rgba16Float direct pipeline must not be rendered
//      to the 8-bit drawable — `renderGlazeReducedMotion` uses the comp (drawable) pipeline.
//   5. Env-gated PNG diag (GLAZE_MVWARP_DIAG=1): contact frames for the M7 pre-check.
//   Synthetic energy is DEV-PREVIEW ONLY (FA #27) — real-audio behaviour is Matt's live M7.

import Testing
import Foundation
import Metal
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import Renderer
@testable import Presets
@testable import Shared

@Suite("Glaze mv_warp port (GLAZE.2a)")
struct GlazeMVWarpAccumulationTest {

    private static let deltaTime: Float = 1.0 / 60.0

    // MARK: - Static-source guards (cheap regression sentries; no GPU)

    @Test("Glaze.metal declares the scene, custom warp, custom comp, and both mv_warp functions")
    func test_metalSource_declaresRequiredFunctions() throws {
        let src = try String(contentsOf: Self.shaderURL("Glaze.metal"), encoding: .utf8)
        for fn in ["glaze_fragment(",
                   "glaze_warp_fragment(",
                   "glaze_comp_fragment(",
                   "MVWarpPerFrame mvWarpPerFrame(",
                   "float2 mvWarpPerVertex("] {
            #expect(src.contains(fn), "Glaze.metal missing \(fn)")
        }
    }

    @Test("Glaze.json declares passes: [\"direct\", \"mv_warp\"] and fragment_function glaze_fragment")
    func test_json_declaresDirectAndMVWarp() throws {
        let data = try Data(contentsOf: Self.shaderURL("Glaze.json"))
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json?["passes"] as? [String] == ["direct", "mv_warp"],
                "Glaze.json must declare passes: [\"direct\", \"mv_warp\"].")
        #expect((json?["fragment_function"] as? String) == "glaze_fragment",
                "Glaze.json fragment_function must be glaze_fragment (drives glaze_* warp/comp auto-selection).")
    }

    // MARK: - Compile + custom-comp wiring (GPU; worktree-runnable — no external fixtures)

    @Test("Glaze loads and its mv_warp pipelines compile (custom warp + comp auto-selected)")
    func test_presetCompilesAndWiresCustomComp() throws {
        let ctx = try MetalContext()
        let loader = PresetLoader(device: ctx.device, pixelFormat: ctx.pixelFormat, loadBuiltIn: true)
        guard let preset = loader.presets.first(where: { $0.descriptor.name == "Glaze" }) else {
            Issue.record("Glaze preset not loaded — Glaze.metal failed to compile, or the bundle resource wasn't copied.")
            return
        }
        #expect(preset.descriptor.passes.contains(.mvWarp),
                "Glaze descriptor must include the mv_warp pass.")
        #expect(preset.mvWarpPipelines != nil,
                "Glaze.mvWarpPipelines is nil — the .metal failed to compile (incl. glaze_comp_fragment) or passes are misconfigured.")
    }

    // MARK: - Blur pyramid (GLAZE.2b.1): the 3-level pyramid allocates + compiles

    @Test("Glaze allocates a 3-level blur pyramid (¼ + ⅛ + 1⁄16 res) and compiles glaze_blur_fragment")
    @MainActor
    func test_blurPyramid_allocatesThreeLevels() throws {
        guard let ctx = try? MetalContext() else { Issue.record("No Metal device"); return }
        let lib = try ShaderLibrary(context: ctx)
        let floatStride = MemoryLayout<Float>.stride
        guard let fft = ctx.makeSharedBuffer(length: 512 * floatStride),
              let wav = ctx.makeSharedBuffer(length: 2048 * floatStride) else {
            Issue.record("buffer alloc failed"); return
        }
        let pipeline = try RenderPipeline(context: ctx, shaderLibrary: lib, fftBuffer: fft, waveformBuffer: wav)
        let loader = PresetLoader(device: ctx.device, pixelFormat: ctx.pixelFormat, loadBuiltIn: true)
        guard let preset = loader.presets.first(where: { $0.descriptor.name == "Glaze" }),
              let mvWarp = preset.mvWarpPipelines else { Issue.record("Glaze not loaded"); return }
        #expect(mvWarp.blurState != nil, "Glaze must compile glaze_blur_fragment (the pyramid pipeline)")
        let bundle = MVWarpPipelineBundle(
            warpState: mvWarp.warpState, composeState: mvWarp.composeState, blitState: mvWarp.blitState,
            pixelFormat: ctx.pixelFormat, feedbackFormat: .rgba16Float,
            blurState: mvWarp.blurState, isGlaze: true)
        pipeline.setupMVWarp(bundle: bundle, size: CGSize(width: 256, height: 256))
        let state = pipeline.mvWarpState
        // Progressive downsample (¼, ⅛, 1⁄16 of 256) — wider blur → smoother gel membranes
        // (the Nacre "narrow blur → flecks, wide → membranes" lesson; GLAZE.2b.2 tuning).
        #expect(state?.blurTexture?.width == 64, "blur1 should be ¼-res (got \(state?.blurTexture?.width ?? -1))")
        #expect(state?.blurTexture2?.width == 32, "blur2 should be ⅛-res (got \(state?.blurTexture2?.width ?? -1))")
        #expect(state?.blurTexture3?.width == 16, "blur3 should be 1⁄16-res (got \(state?.blurTexture3?.width ?? -1))")
    }

    // MARK: - Accumulation gate (ALWAYS run): live dispatch path, non-black + no white-out

    @Test("Glaze field stays alive (non-black) and never whites out over 64 silence frames")
    @MainActor
    func test_accumulation_silenceStaysAliveNoWhiteout() throws {
        guard let ctx = try? MetalContext() else {
            Issue.record("No Metal device — cannot run the accumulation gate"); return
        }
        guard let display = try Self.runGlaze(ctx: ctx, width: 192, height: 128, frames: 64, energy: 0) else {
            Issue.record("Glaze render setup failed"); return
        }
        let stats = Self.frameStats(display)
        // Non-black: the palette-tinted, silence-floored seed sustains the field (D-019).
        #expect(stats.meanLuma > 0.01,
                "Glaze silence field is ~black (meanLuma \(stats.meanLuma)) — the seed/feedback isn't sustaining.")
        // No white-out: the HDR-feedback trip-wire. Most pixels saturating ⇒ over-accumulation.
        #expect(stats.saturatedFraction < 0.85,
                "Glaze field whites out (\(Int(stats.saturatedFraction * 100))% saturated) — over-accumulation.")
    }

    // MARK: - GLAZE.3 anchor route (STEMS → spring anchor → swirl-poke); Matt M7 2026-06-27

    /// Drive `computeGlazeUniforms` for `frames` frames at a CONSTANT stem level (the route reads
    /// the bass/other stem deviations + the four stem Rels) and return the final spring state.
    /// Resets the spring + EMAs first so runs are independent. CPU-only — no GPU dispatch.
    @MainActor
    private static func driveAnchor(_ pipeline: RenderPipeline, frames: Int,
                                    bassStemDev: Float = 0, otherStemDev: Float = 0,
                                    fullnessRel: Float = 0) -> GlazeSpring {
        pipeline.glazeSpring = GlazeSpring()   // also zeroes the anchor-drive EMAs
        var stems = StemFeatures.zero
        stems.bassEnergyDev = bassStemDev; stems.otherEnergyDev = otherStemDev
        stems.drumsEnergyRel = fullnessRel; stems.bassEnergyRel = fullnessRel
        stems.vocalsEnergyRel = fullnessRel; stems.otherEnergyRel = fullnessRel
        for i in 0..<frames {
            var f = FeatureVector.zero
            f.deltaTime = deltaTime
            f.time = Float(i) * deltaTime
            _ = pipeline.computeGlazeUniforms(features: f, stems: stems)
        }
        return pipeline.glazeSpring
    }

    @MainActor
    private static func makePipeline(_ ctx: MetalContext) throws -> RenderPipeline? {
        let lib = try ShaderLibrary(context: ctx)
        let floatStride = MemoryLayout<Float>.stride
        guard let fft = ctx.makeSharedBuffer(length: 512 * floatStride),
              let wav = ctx.makeSharedBuffer(length: 2048 * floatStride) else { return nil }
        return try RenderPipeline(context: ctx, shaderLibrary: lib, fftBuffer: fft, waveformBuffer: wav)
    }

    /// Mechanism gate (always run): the stem anchor routing fires in the right directions —
    /// the bass stem swings the tail one way, the OTHER (guitar/synth) stem the other (opposite
    /// directions of the one anchor axis), and stem fullness lifts it. Deterministic; the identical
    /// idle sine runs in every case, so the only difference is the stem term. No real-audio claim
    /// (FA #27) — that's the session-replay test below + Matt's live M7.
    @Test("GLAZE.3: bass stem swings the anchor one way, the other stem the other, fullness lifts it")
    @MainActor
    func test_anchorRoute_directionalDeflection() throws {
        guard let ctx = try? MetalContext() else { Issue.record("No Metal device"); return }
        guard let pipeline = try Self.makePipeline(ctx) else { Issue.record("pipeline setup failed"); return }

        let frames = 300
        let bassRun = Self.driveAnchor(pipeline, frames: frames, bassStemDev: 1.0)
        let otherRun = Self.driveAnchor(pipeline, frames: frames, otherStemDev: 1.0)
        let silentRun = Self.driveAnchor(pipeline, frames: frames)
        let energyRun = Self.driveAnchor(pipeline, frames: frames, fullnessRel: 0.8)

        // Lateral swing: the bass + other stems pull the tail to OPPOSITE sides of the one axis.
        #expect(bassRun.x4 - otherRun.x4 > 0.05,
                "bass/other stems should split the tail laterally (bass x4=\(bassRun.x4), other x4=\(otherRun.x4))")
        // Lift: stem fullness raises the anchor → the tail rides clear of the silence (gravity) rest.
        #expect(energyRun.y4 - silentRun.y4 > 0.02,
                "stem fullness should lift the tail above the silence rest (energy y4=\(energyRun.y4), silent y4=\(silentRun.y4))")
    }

    /// Session-replay evidence (env-gated GLAZE_SESSION_CSV=<stems.csv>): drive the REAL recorded
    /// STEMS through the route and confirm the jelly actually moves on music — the FA #27-compliant
    /// evidence the closeout cites (synthetic envelopes don't prove real-audio firing). stems.csv
    /// carries all four stems' Rel/Dev, so the full bass↔other route is driven from real data.
    @Test("GLAZE.3: real-session replay — the anchor moves on recorded stems (env-gated)")
    @MainActor
    func test_anchorRoute_realSessionReplay() throws {
        guard let csvPath = ProcessInfo.processInfo.environment["GLAZE_SESSION_CSV"] else {
            print("GlazeMVWarpAccumulationTest: GLAZE_SESSION_CSV not set, skipping real-session replay")
            return
        }
        guard let stemRows = Self.sessionAudioRows(path: csvPath), !stemRows.isEmpty else {
            Issue.record("Could not parse \(csvPath) (expected stems.csv with bass/otherEnergyDev + Rels)"); return
        }
        guard let ctx = try? MetalContext() else { Issue.record("No Metal device"); return }
        guard let pipeline = try Self.makePipeline(ctx) else { Issue.record("pipeline setup failed"); return }
        pipeline.glazeSpring = GlazeSpring()   // also zeroes the anchor-drive EMAs

        var pokeXs: [Float] = []; var tailYs: [Float] = []; var maxOtherDev: Float = 0
        for (i, sf) in stemRows.enumerated() {
            var fv = FeatureVector.zero
            fv.deltaTime = Self.deltaTime; fv.time = Float(i) * Self.deltaTime
            let uni = pipeline.computeGlazeUniforms(features: fv, stems: sf)
            pokeXs.append(uni.pokeCenter.x); tailYs.append(pipeline.glazeSpring.y4)
            maxOtherDev = max(maxOtherDev, sf.otherEnergyDev)
        }
        let xMin = pokeXs.min() ?? 0, xMax = pokeXs.max() ?? 0
        let yMin = tailYs.min() ?? 0, yMax = tailYs.max() ?? 0
        print("[glaze_replay] frames=\(pokeXs.count) maxOtherDev=\(maxOtherDev) " +
              "pokeX=[\(xMin),\(xMax)] span=\(xMax - xMin) tailY=[\(yMin),\(yMax)] span=\(yMax - yMin)")
        // The jelly must sweep a meaningful fraction of the field on real music (not a static point).
        #expect(xMax - xMin > 0.05, "anchor barely moved on real stems (pokeX span \(xMax - xMin)) — route not firing")
        #expect(yMax - yMin > 0.02, "tail lift barely moved on real stems (tailY span \(yMax - yMin))")
    }

    // MARK: - Reduced-motion regression (BUG-061: 16-float direct pipeline → 8-bit drawable)

    @Test("Glaze reduced-motion frame renders to the 8-bit drawable format without a format mismatch")
    @MainActor
    func test_reducedMotion_rendersToDrawableFormatNoMismatch() throws {
        guard let ctx = try? MetalContext() else {
            Issue.record("No Metal device — cannot run the reduced-motion gate"); return
        }
        let display = try Self.runGlaze(ctx: ctx, width: 192, height: 128, frames: 3,
                                        energy: 0, reducedMotion: true)
        #expect(display != nil, "Glaze reduced-motion render setup failed")
    }

    // MARK: - Env-gated PNG diag (the M7 pre-check; render BEFORE tuning)

    @Test("Glaze render diag (env-gated GLAZE_MVWARP_DIAG=1)")
    @MainActor
    func test_glazeRender_diag() throws {
        guard ProcessInfo.processInfo.environment["GLAZE_MVWARP_DIAG"] == "1" else {
            print("GlazeMVWarpAccumulationTest: GLAZE_MVWARP_DIAG not set, skipping render diag")
            return
        }
        let ctx = try MetalContext()
        let wPix = ProcessInfo.processInfo.environment["GLAZE_W"].flatMap { Int($0) } ?? 1280
        let hPix = ProcessInfo.processInfo.environment["GLAZE_H"].flatMap { Int($0) } ?? 720
        let frames = ProcessInfo.processInfo.environment["GLAZE_FRAMES"].flatMap { Int($0) } ?? 120
        // DEV PREVIEW ONLY (FA #27): with no real session in the worktree, GLAZE_ENERGY
        // injects a constant band energy so the seed can be eyeballed. Real-audio = Matt's M7.
        let energy = ProcessInfo.processInfo.environment["GLAZE_ENERGY"].flatMap { Float($0) } ?? 0
        // GLAZE.3: GLAZE_SESSION_CSV=<stems.csv> drives the STEM route from a REAL recorded
        // session (the FA #27-correct render evidence for the audio coupling).
        let audio = ProcessInfo.processInfo.environment["GLAZE_SESSION_CSV"].flatMap { Self.sessionAudioRows(path: $0) }
        if let audio { print("[glaze_diag] driving \(audio.count) real-session stem frames") }
        guard let display = try Self.runGlaze(ctx: ctx, width: wPix, height: hPix,
                                              frames: frames, energy: energy, audio: audio) else {
            Issue.record("Glaze render setup failed"); return
        }
        let outDir = FileManager.default.temporaryDirectory.appendingPathComponent("glaze_mvwarp_diag")
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        let url = outDir.appendingPathComponent("glaze_frame\(frames).png")
        try Self.writePNG(display, to: url)
        let st = Self.frameStats(display)   // wash-out metric: meanLuma ↑ = brighter/washed
        print("[glaze_diag] wrote \(url.path) (\(wPix)×\(hPix), \(frames) frames) meanLuma=\(st.meanLuma) saturated=\(st.saturatedFraction)")
    }

    // MARK: - Shared render driver (live dispatch path — FA #66, no reimplemented encode)

    /// Drive the REAL `RenderPipeline.renderGlaze` for `frames` frames into an offscreen
    /// drawable-format texture and return it. Silence-driven (worktree-safe; synthetic
    /// `energy` is dev-preview only). Returns nil on setup failure.
    @MainActor
    static func runGlaze(ctx: MetalContext, width: Int, height: Int, frames: Int,
                         energy: Float, reducedMotion: Bool = false,
                         audio: [StemFeatures]? = nil) throws -> MTLTexture? {
        let lib = try ShaderLibrary(context: ctx)
        let texMgr = try TextureManager(context: ctx, shaderLibrary: lib)
        let floatStride = MemoryLayout<Float>.stride
        guard let fft = ctx.makeSharedBuffer(length: 512 * floatStride),
              let wav = ctx.makeSharedBuffer(length: 2048 * floatStride) else { return nil }
        let pipeline = try RenderPipeline(context: ctx, shaderLibrary: lib, fftBuffer: fft, waveformBuffer: wav)
        pipeline.setTextureManager(texMgr)
        let loader = PresetLoader(device: ctx.device, pixelFormat: ctx.pixelFormat, loadBuiltIn: true)
        guard let preset = loader.presets.first(where: { $0.descriptor.name == "Glaze" }),
              let mvWarp = preset.mvWarpPipelines else { return nil }

        let size = CGSize(width: width, height: height)
        pipeline.currentDrawableSize = size
        // Feedback in HDR .rgba16Float (matches PresetLoader.feedbackFormat for Glaze);
        // the comp target stays the drawable format. isGlaze routes the draw branch.
        let bundle = MVWarpPipelineBundle(
            warpState: mvWarp.warpState,
            composeState: mvWarp.composeState,
            blitState: mvWarp.blitState,
            pixelFormat: ctx.pixelFormat,
            feedbackFormat: .rgba16Float,
            blurState: mvWarp.blurState,   // GLAZE.2b.1: the glaze_blur pipeline (3-level pyramid)
            isGlaze: true)
        pipeline.setupMVWarp(bundle: bundle, size: size)
        pipeline.setMVWarpDecay(preset.descriptor.decay)

        let fbDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: ctx.pixelFormat, width: width, height: height, mipmapped: false)
        fbDesc.usage = [.renderTarget, .shaderRead]
        fbDesc.storageMode = .shared
        guard let display = ctx.device.makeTexture(descriptor: fbDesc) else { return nil }

        for i in 0..<frames {
            var feat = FeatureVector.zero
            feat.deltaTime = deltaTime
            feat.time = Float(i) * deltaTime
            feat.bass = energy; feat.mid = energy; feat.treble = energy   // dev preview only
            // GLAZE.3 render evidence: drive the STEM route from a REAL session's stems.csv (the
            // synthetic `energy` knob can't — the route reads the separated stems, not the bands).
            var stems = StemFeatures.zero
            if let audio, !audio.isEmpty { stems = audio[min(i, audio.count - 1)] }
            guard let cmd = ctx.commandQueue.makeCommandBuffer(),
                  let warpState = pipeline.mvWarpState else { return display }
            if reducedMotion {
                pipeline.renderGlazeReducedMotion(commandBuffer: cmd, features: feat,
                                                  warpState: warpState, target: display)
            } else {
                pipeline.renderGlaze(commandBuffer: cmd, features: feat, stemFeatures: stems,
                                     warpState: warpState, target: display)
            }
            cmd.commit(); cmd.waitUntilCompleted()
            if let err = cmd.error {
                Issue.record("Glaze frame \(i) command buffer error (format mismatch?): \(err)")
                return display
            }
        }
        return display
    }

    // MARK: - Frame analysis

    struct FrameStats { var meanLuma: Float; var saturatedFraction: Float }

    /// Mean luma + fraction of near-saturated pixels of an 8-bit BGRA target.
    static func frameStats(_ tex: MTLTexture) -> FrameStats {
        let w = tex.width, h = tex.height
        var px = [UInt8](repeating: 0, count: w * h * 4)
        tex.getBytes(&px, bytesPerRow: w * 4, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        var lumaSum: Double = 0, sat = 0
        for i in stride(from: 0, to: px.count, by: 4) {
            let b = Float(px[i]) / 255, g = Float(px[i + 1]) / 255, r = Float(px[i + 2]) / 255
            let luma = 0.299 * r + 0.587 * g + 0.114 * b
            lumaSum += Double(luma)
            if r > 0.96 && g > 0.96 && b > 0.96 { sat += 1 }
        }
        let n = w * h
        return FrameStats(meanLuma: Float(lumaSum / Double(n)), saturatedFraction: Float(sat) / Float(n))
    }

    // MARK: - PNG writer (8-bit BGRA target; reused from the Nacre diag)

    static func writePNG(_ tex: MTLTexture, to url: URL) throws {
        let w = tex.width, h = tex.height
        var px = [UInt8](repeating: 0, count: w * h * 4)
        tex.getBytes(&px, bytesPerRow: w * 4, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        let cs = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard let provider = CGDataProvider(data: Data(px) as CFData),
              let img = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32,
                                bytesPerRow: w * 4, space: cs,
                                bitmapInfo: CGBitmapInfo(rawValue: info),
                                provider: provider, decode: nil, shouldInterpolate: false,
                                intent: .defaultIntent),
              let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw GlazeDiagError.pngFailed }
        CGImageDestinationAddImage(dest, img, nil)
        guard CGImageDestinationFinalize(dest) else { throw GlazeDiagError.pngFailed }
    }

    enum GlazeDiagError: Error { case pngFailed }

    // MARK: - Helpers

    /// Parse a recorded `stems.csv` into per-frame `StemFeatures` carrying the GLAZE.3 stem-drive
    /// fields: bass/other `EnergyDev` (the lateral swing) + the four `EnergyRel`s (the lift
    /// fullness). Columns located by NAME (schema-drift-tolerant). nil on missing file/columns.
    static func sessionAudioRows(path: String) -> [StemFeatures]? {
        guard let csv = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        var lines = csv.split(separator: "\n").map(String.init)
        guard lines.count > 1 else { return nil }
        let header = lines.removeFirst().split(separator: ",").map(String.init)
        func col(_ n: String) -> Int? { header.firstIndex(of: n) }
        guard let iBd = col("bassEnergyDev"), let iOd = col("otherEnergyDev"),
              let iDr = col("drumsEnergyRel"), let iBr = col("bassEnergyRel"),
              let iVr = col("vocalsEnergyRel"), let iOr = col("otherEnergyRel") else { return nil }
        return lines.compactMap { line -> StemFeatures? in
            let f = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            guard f.count > iOr else { return nil }
            func v(_ i: Int) -> Float { i < f.count ? (Float(f[i]) ?? 0) : 0 }
            var s = StemFeatures.zero
            s.bassEnergyDev = v(iBd); s.otherEnergyDev = v(iOd)
            s.drumsEnergyRel = v(iDr); s.bassEnergyRel = v(iBr)
            s.vocalsEnergyRel = v(iVr); s.otherEnergyRel = v(iOr)
            return s
        }
    }

    private static func shaderURL(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // /Presets/
            .deletingLastPathComponent()   // /PhospheneEngineTests/
            .deletingLastPathComponent()   // /Tests/
            .deletingLastPathComponent()   // /PhospheneEngine/
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("PhospheneEngine/Sources/Presets/Shaders/\(name)")
    }
}
