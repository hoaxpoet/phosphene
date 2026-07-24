// FractalFlyByBudgetProbeTests — FD.1 task-3 performance gate.
//
// Measures Fractal Fly-By's per-preset GPU cost at 1920×1080 through the LIVE
// ray-march dispatch path (RayMarchPipeline.render: G-buffer → lighting →
// composite → post-process), adapted from RayMarchPathHarnessTemplate (QG.4,
// D-182 — copy-adapt the paradigm template, do not reinvent) with the
// GPU-timestamp timing method from NimbusBudgetProbeTests.
//
// WHY THIS RUNS BEFORE ANY BEAUTY WORK: the Mandelbox distance estimator is
// evaluated up to 139× per hit pixel by the shared preamble — 128 march steps
// + 6 for the central-differences normal + 5 for the AO cone — and each
// evaluation runs FFB_ITERS fold iterations. That product is the whole budget
// risk, and it is knowable now, before materials/god-rays/fog exist.
//
// GATE (PG_FD_FRACTAL_DESCENT.md §A8): Tier-2 p95 ≤ 7 ms at 1080p. Over budget
// ⇒ STOP AND REPORT; the concept is re-scoped or cut, not tuned toward budget
// across increments.
//
// Env-gated `FFB_BUDGET=1` so it stays out of the default `swift test` run.
//
// Invocation:
//   FFB_BUDGET=1 swift test --package-path PhospheneEngine \
//       --filter FractalFlyByBudgetProbe

import Testing
import Foundation
import Metal
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import Renderer
@testable import Presets
@testable import Shared

// MARK: - FractalFlyByBudgetProbeTests

@Suite("FractalFlyByBudgetProbe")
@MainActor
struct FractalFlyByBudgetProbeTests {

    private static let width = 1920
    private static let height = 1080
    private static let warmupFrames = 10
    private static let measuredFrames = 60
    private static let subjectName = "Fractal Fly-By"
    private static let tier2CeilingMs = 7.0

    /// Known-good ray-march control. Lumen Mosaic is CERTIFIED with a declared
    /// `complexity_cost.tier2` of 3.7 ms, so measuring it through this same probe
    /// says whether a given number means "this preset is expensive" or "this probe
    /// over-reads" (it also pins which hardware tier the run is on).
    private static let controlName = "Lumen Mosaic"
    private static let controlDeclaredTier2Ms = 3.7

    @Test("ray-march control: Lumen Mosaic through the same probe (FFB_BUDGET=1)")
    func test_controlBudgetProbe() throws {
        guard ProcessInfo.processInfo.environment["FFB_BUDGET"] == "1" else {
            print("[FDBudget] FFB_BUDGET not set — skipping")
            return
        }
        let stats = try measure(presetNamed: Self.controlName)
        print(String(format: """
            [FDBudget] CONTROL %@ — declared complexity_cost.tier2 = %.1f ms
            [FDBudget]   p50=%.3f  p95=%.3f ms  (ratio measured/declared = %.2f×)
            """, Self.controlName, Self.controlDeclaredTier2Ms,
            stats.p50, stats.p95, stats.p95 / Self.controlDeclaredTier2Ms))
    }

    @Test("Fractal Fly-By per-preset GPU cost @ 1920×1080 (FFB_BUDGET=1)")
    func test_fractalDescentBudgetProbe() throws {
        guard ProcessInfo.processInfo.environment["FFB_BUDGET"] == "1" else {
            print("[FDBudget] FFB_BUDGET not set — skipping")
            return
        }
        let stats = try measure(presetNamed: Self.subjectName)
        let (p50, p95, p99, mean) = (stats.p50, stats.p95, stats.p99, stats.mean)

        print(String(format: """
            [FDBudget] %@ @ %dx%d — live ray_march (G-buffer→lighting→composite→post)
            [FDBudget]   min=%.3f  p50=%.3f  mean=%.3f  p95=%.3f  p99=%.3f  max=%.3f ms
            [FDBudget]   VERDICT: p95 %.3f ms vs %.1f ms Tier-2 ceiling — %@
            """,
            Self.subjectName, Self.width, Self.height,
            stats.min, p50, mean, p95, p99, stats.max,
            p95, Self.tier2CeilingMs, p95 <= Self.tier2CeilingMs ? "WITHIN" : "OVER"))

        #expect(p95 <= Self.tier2CeilingMs, """
            FD.1 task-3 performance gate FAILED: p95 \(String(format: "%.3f", p95)) ms exceeds the \
            \(Self.tier2CeilingMs) ms Tier-2 ceiling at \(Self.width)×\(Self.height). \
            Per §A8 this is STOP AND REPORT — the concept is re-scoped or cut, not tuned \
            toward budget across increments.
            """)
    }

    /// Dumps three frames spanning one full descent octave, so the iteration-cap
    /// decision (§9 DECISION-NEEDED 3: "reduce ambition vs cut the preset") can be
    /// made against what it actually looks like rather than against a number.
    /// Run once per FFB_ITERS value; the PNGs are the comparison.
    @Test("descent contact sheet (FFB_BUDGET=1, FFB_RENDER=1)")
    func test_descentContactSheet() throws {
        guard ProcessInfo.processInfo.environment["FFB_BUDGET"] == "1",
              ProcessInfo.processInfo.environment["FFB_RENDER"] == "1" else {
            print("[FDBudget] FFB_RENDER not set — skipping contact sheet")
            return
        }
        let dir = URL(fileURLWithPath: ProcessInfo.processInfo.environment["FFB_RENDER_DIR"]
                      ?? NSTemporaryDirectory().appending("ffb_frames"))
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // Descent phases across one octave. FFB_PHASES overrides (comma-separated)
        // to sweep direction/coverage, e.g. FFB_PHASES="0.05,0.35,0.65,0.95".
        let phases: [Float] = ProcessInfo.processInfo.environment["FFB_PHASES"]
            .map { $0.split(separator: ",").compactMap { Float($0) } }
            .flatMap { $0.isEmpty ? nil : $0 } ?? [0.0, 0.33, 0.66]
        for (i, phase) in phases.enumerated() {
            let px = try renderSingle(presetNamed: Self.subjectName, descentPhase: phase / 0.45)
            let url = dir.appendingPathComponent(String(format: "descent_%02d_phase%.2f.png", i, phase))
            try writePNG(bgra: px, width: Self.width, height: Self.height, to: url)
            print("[FDBudget] wrote \(url.path)")
        }
    }

    /// Motion sequence exercising BOTH heroes over one descent, dumped as a frame
    /// run for motion_gate.sh + eyeball review (the Truchet lesson: still sheets
    /// hide temporal defects). Energy envelope drives descent SPEED (the per-frame
    /// accumulatedAudioTime increment scales with a synthetic quiet→build→drop→tail
    /// energy curve); a bass swell at the drop drives the fold-open. Verifies the
    /// fall accelerates with energy, near-stops in the quiet, and the fold opens on
    /// the bass — as a real position/structure delta across frames, not a still.
    @Test("descent motion sequence (FFB_BUDGET=1, FFB_MOTION=1)")
    func test_descentMotionSequence() throws {
        guard ProcessInfo.processInfo.environment["FFB_BUDGET"] == "1",
              ProcessInfo.processInfo.environment["FFB_MOTION"] == "1" else {
            print("[FDBudget] FFB_MOTION not set — skipping motion sequence")
            return
        }
        let dir = URL(fileURLWithPath: ProcessInfo.processInfo.environment["FFB_RENDER_DIR"]
                      ?? NSTemporaryDirectory().appending("ffb_motion"))
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // MFX.1: the pipeline is built ONCE and every frame renders through it, so
        // MetalFX accumulates temporal history exactly as production does. Building
        // a fresh pipeline per frame (as renderSingle does) resets that history and
        // would silently measure TAA-off.
        let ctx = try MetalContext()
        let lib = try ShaderLibrary(context: ctx)
        let loader = PresetLoader(device: ctx.device, pixelFormat: ctx.pixelFormat, loadBuiltIn: true)
        guard let preset = loader.presets.first(where: { $0.descriptor.name == Self.subjectName }),
              let gbufferState = preset.rayMarchPipelineState else {
            throw HarnessError.presetNotFound(Self.subjectName)
        }
        let pipeline = try RayMarchPipeline(context: ctx, shaderLibrary: lib)
        // FFB_NO_TAA=1 renders the identical motion path with the temporal resolve
        // OFF — the A/B that shows whether MetalFX actually removes the shimmer.
        let taaOff = ProcessInfo.processInfo.environment["FFB_NO_TAA"] == "1"
        // MFX.1 production parity: the MetalFX flags decide the render size and the
        // working-set allocation, so they MUST be set before allocateTextures.
        pipeline.metalFXEnabled = preset.descriptor.usesMetalFXTemporal && !taaOff
        pipeline.metalFXRenderScale = preset.descriptor.effectiveRenderScale
        pipeline.motionPipelineState = preset.motionPipelineState
        pipeline.allocateTextures(width: Self.width, height: Self.height)
        pipeline.ssgiEnabled = preset.descriptor.passes.contains(.ssgi)
        print("[FDBudget] MetalFX ready = \(pipeline.metalFXReady) (enabled=\(pipeline.metalFXEnabled), motionPipeline=\(preset.motionPipelineState != nil))")

        let ibl = try IBLManager(context: ctx, shaderLibrary: lib)
        let noise = try? TextureManager(context: ctx, shaderLibrary: lib)
        var postChain: PostProcessChain?
        if preset.descriptor.passes.contains(.postProcess) {
            let chain = try PostProcessChain(context: ctx, shaderLibrary: lib)
            chain.allocateTextures(width: Self.width, height: Self.height)
            postChain = chain
        }
        let buffers = try HarnessTemplateCore.makeSilenceBuffers(ctx)
        let outTex = try HarnessTemplateCore.makeCaptureTexture(ctx, width: Self.width, height: Self.height)

        let frames = 90
        var phase: Float = 0            // monotonic descent phase (∫ energy dt)
        var prevPhase: Float = 0
        for i in 0..<frames {
            let u = Float(i) / Float(frames - 1)          // 0..1 over the sequence
            // Synthetic energy: quiet intro → build → drop → sustained tail.
            let energy: Float = u < 0.25 ? 0.05
                : u < 0.5 ? (0.05 + (u - 0.25) / 0.25 * 0.85)
                : 0.9
            prevPhase = phase
            // REAL playback rate: accumulatedAudioTime advances ~0.1/s on a loud
            // track, so at 60 fps phase moves ~0.00075/frame. An earlier version of
            // this harness used 0.05/frame — ~60× too fast — which made every frame
            // a disocclusion and understated what temporal accumulation can do.
            phase += energy * 0.0017                      // faster when loud (HERO #1)
            // Bass swell centred on the drop (u≈0.5) → fold opens (HERO #2).
            let swell: Float = max(0, 1.0 - abs(u - 0.5) / 0.12) * 2.4

            var scene = preset.descriptor.makeSceneUniforms()
            scene.sceneParamsA.x = phase / 0.45           // accumulatedAudioTime
            scene.sceneParamsA.y = Float(Self.width) / Float(Self.height)
            scene.lightingParams.z = prevPhase / 0.45     // MFX.1 previous-frame time
            pipeline.sceneUniforms = scene

            var features = HarnessTemplateCore.silenceFeature(frame: i)
            features.bassAttRel = swell
            guard let cmd = ctx.commandQueue.makeCommandBuffer() else {
                throw HarnessError.commandBufferFailed
            }
            pipeline.render(
                gbufferPipelineState: gbufferState,
                features: &features,
                fftBuffer: buffers.fft, waveformBuffer: buffers.waveform,
                stemFeatures: .zero,
                outputTexture: outTex,
                commandBuffer: cmd,
                noiseTextures: noise,
                iblManager: ibl,
                postProcessChain: postChain)
            cmd.commit()
            cmd.waitUntilCompleted()
            guard cmd.status == .completed else { throw HarnessError.renderFailed }

            if i == 5 {
                print("[FDBudget] frame5: resolveDidRun=\(pipeline.metalFXResolveDidRun) "
                      + "mfxMs=\(pipeline.lastMetalFXPassMs) jitter=\(pipeline.currentJitter)")
            }
            let px = HarnessTemplateCore.readBGRA(outTex, width: Self.width, height: Self.height)
            let url = dir.appendingPathComponent(String(format: "ffb_%03d.png", i))
            try writePNG(bgra: px, width: Self.width, height: Self.height, to: url)
        }
        print("[FDBudget] wrote \(frames) motion frames to \(dir.path)")
    }

    /// Renders one frame at an explicit descent phase + fold swell, returns BGRA.
    /// `sceneParamsA.x` (accumulated audio time, the descent driver) and
    /// `bassAttRel` (the fold driver) are normally written by the live path, which
    /// this probe bypasses — so both are set here directly.
    private func renderSingle(presetNamed name: String,
                              descentPhase: Float,
                              foldSwell: Float = 0) throws -> [UInt8] {
        let ctx = try MetalContext()
        let lib = try ShaderLibrary(context: ctx)
        let loader = PresetLoader(device: ctx.device, pixelFormat: ctx.pixelFormat, loadBuiltIn: true)
        guard let preset = loader.presets.first(where: { $0.descriptor.name == name }),
              let gbufferState = preset.rayMarchPipelineState else {
            throw HarnessError.presetNotFound(name)
        }
        let pipeline = try RayMarchPipeline(context: ctx, shaderLibrary: lib)
        // MFX.1 production parity: the MetalFX flags decide the render size and the
        // working-set allocation, so they MUST be set before allocateTextures.
        pipeline.metalFXEnabled = preset.descriptor.usesMetalFXTemporal
        pipeline.metalFXRenderScale = preset.descriptor.effectiveRenderScale
        pipeline.motionPipelineState = preset.motionPipelineState
        pipeline.allocateTextures(width: Self.width, height: Self.height)
        var scene = preset.descriptor.makeSceneUniforms()
        scene.sceneParamsA.x = descentPhase      // HERO #1: descent driver (energy-time)
        scene.sceneParamsA.y = Float(Self.width) / Float(Self.height)
        pipeline.sceneUniforms = scene
        pipeline.ssgiEnabled = preset.descriptor.passes.contains(.ssgi)
        // MFX.1: exercise the real MetalFX path when the preset opts in, so the
        // probe measures/renders what production does.

        let ibl = try IBLManager(context: ctx, shaderLibrary: lib)
        let noise = try? TextureManager(context: ctx, shaderLibrary: lib)
        var postChain: PostProcessChain?
        if preset.descriptor.passes.contains(.postProcess) {
            let chain = try PostProcessChain(context: ctx, shaderLibrary: lib)
            chain.allocateTextures(width: Self.width, height: Self.height)
            postChain = chain
        }
        let buffers = try HarnessTemplateCore.makeSilenceBuffers(ctx)
        let outTex = try HarnessTemplateCore.makeCaptureTexture(ctx, width: Self.width, height: Self.height)

        var features = HarnessTemplateCore.silenceFeature(frame: 0)
        features.bassAttRel = foldSwell          // HERO #2: fold-open driver
        guard let cmd = ctx.commandQueue.makeCommandBuffer() else { throw HarnessError.commandBufferFailed }
        pipeline.render(
            gbufferPipelineState: gbufferState,
            features: &features,
            fftBuffer: buffers.fft, waveformBuffer: buffers.waveform,
            stemFeatures: .zero,
            outputTexture: outTex,
            commandBuffer: cmd,
            noiseTextures: noise,
            iblManager: ibl,
            postProcessChain: postChain)
        cmd.commit()
        cmd.waitUntilCompleted()
        guard cmd.status == .completed else { throw HarnessError.renderFailed }
        return HarnessTemplateCore.readBGRA(outTex, width: Self.width, height: Self.height)
    }

    private func writePNG(bgra: [UInt8], width: Int, height: Int, to url: URL) throws {
        guard let cs = CGColorSpace(name: CGColorSpace.sRGB) else {
            throw HarnessError.setupFailed("colorspace")
        }
        let bi = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue
                              | CGBitmapInfo.byteOrder32Little.rawValue)
        var copy = bgra
        let cg = copy.withUnsafeMutableBytes { (ptr: UnsafeMutableRawBufferPointer) -> CGImage? in
            guard let base = ptr.baseAddress,
                  let c = CGContext(data: base, width: width, height: height, bitsPerComponent: 8,
                                    bytesPerRow: width * 4, space: cs, bitmapInfo: bi.rawValue) else { return nil }
            return c.makeImage()
        }
        guard let img = cg,
              let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw HarnessError.setupFailed("png destination")
        }
        CGImageDestinationAddImage(dest, img, nil)
        guard CGImageDestinationFinalize(dest) else { throw HarnessError.setupFailed("png finalize") }
    }

    // MARK: - Measurement

    private struct Stats {
        let min: Double, p50: Double, mean: Double, p95: Double, p99: Double, max: Double
    }

    private func measure(presetNamed name: String) throws -> Stats {
        let ctx = try MetalContext()
        print("[FDBudget] device: \(ctx.device.name)")
        let lib = try ShaderLibrary(context: ctx)
        let loader = PresetLoader(device: ctx.device, pixelFormat: ctx.pixelFormat, loadBuiltIn: true)
        guard let preset = loader.presets.first(where: { $0.descriptor.name == name }) else {
            throw HarnessError.presetNotFound(name)
        }
        guard let gbufferState = preset.rayMarchPipelineState else {
            throw HarnessError.setupFailed("\(name) rayMarchPipelineState missing — not a ray-march preset?")
        }

        // Live pipeline, production parity (BUG-034): the same seam the renderer
        // drives, at the live 128-step budget (sceneParamsB.z default 1.0).
        let pipeline = try RayMarchPipeline(context: ctx, shaderLibrary: lib)
        // MFX.1 production parity: the MetalFX flags decide the render size and the
        // working-set allocation, so they MUST be set before allocateTextures.
        pipeline.metalFXEnabled = preset.descriptor.usesMetalFXTemporal
        pipeline.metalFXRenderScale = preset.descriptor.effectiveRenderScale
        pipeline.motionPipelineState = preset.motionPipelineState
        pipeline.allocateTextures(width: Self.width, height: Self.height)
        var scene = preset.descriptor.makeSceneUniforms()
        scene.sceneParamsA.y = Float(Self.width) / Float(Self.height)
        // sceneParamsB.z is the live FrameBudgetManager step multiplier (D-057):
        // 1.0 = 128 march steps, 0.5 = 64 (what §A8 assumed), floor 0.25 = 32.
        if let mult = ProcessInfo.processInfo.environment["FFB_STEP_MULT"].flatMap(Float.init) {
            scene.sceneParamsB.z = mult
            print(String(format: "[FDBudget] step multiplier %.2f → %d march steps", mult, Int(128.0 * mult)))
        }
        pipeline.sceneUniforms = scene
        pipeline.ssgiEnabled = preset.descriptor.passes.contains(.ssgi)
        // MFX.1: exercise the real MetalFX path when the preset opts in, so the
        // probe measures/renders what production does.

        let ibl = try IBLManager(context: ctx, shaderLibrary: lib)
        let noise = try? TextureManager(context: ctx, shaderLibrary: lib)
        let postChain: PostProcessChain?
        if preset.descriptor.passes.contains(.postProcess) {
            let chain = try PostProcessChain(context: ctx, shaderLibrary: lib)
            chain.allocateTextures(width: Self.width, height: Self.height)
            postChain = chain
        } else {
            postChain = nil
        }

        let buffers = try HarnessTemplateCore.makeSilenceBuffers(ctx)
        let outTex = try HarnessTemplateCore.makeCaptureTexture(ctx, width: Self.width, height: Self.height)

        // One frame of the live path; returns its GPU wall-clock window in ms.
        func renderFrame(_ i: Int) throws -> Double {
            var features = HarnessTemplateCore.silenceFeature(frame: i)
            guard let cmd = ctx.commandQueue.makeCommandBuffer() else {
                throw HarnessError.commandBufferFailed
            }
            pipeline.render(
                gbufferPipelineState: gbufferState,
                features: &features,
                fftBuffer: buffers.fft, waveformBuffer: buffers.waveform,
                stemFeatures: .zero,
                outputTexture: outTex,
                commandBuffer: cmd,
                noiseTextures: noise,
                iblManager: ibl,
                postProcessChain: postChain)
            cmd.commit()
            cmd.waitUntilCompleted()
            guard cmd.status == .completed else { throw HarnessError.renderFailed }
            return (cmd.gpuEndTime - cmd.gpuStartTime) * 1000.0
        }

        for i in 0..<Self.warmupFrames { _ = try renderFrame(i) }

        var samples: [Double] = []
        samples.reserveCapacity(Self.measuredFrames)
        for i in 0..<Self.measuredFrames {
            samples.append(try renderFrame(Self.warmupFrames + i))
        }

        // Sanity: the probe must be measuring a real render, not a no-op that
        // returned early (allocateTextures guard) and timed an empty buffer.
        let pixels = HarnessTemplateCore.readBGRA(outTex, width: Self.width, height: Self.height)
        #expect(HarnessTemplateCore.isNonConstant(pixels), """
            composite for \(name) is constant — the probe is not reaching a real render, \
            so the timings are meaningless
            """)

        let sorted = samples.sorted()
        func pct(_ q: Double) -> Double { sorted[min(sorted.count - 1, Int(q * Double(sorted.count)))] }
        return Stats(min: sorted.first ?? 0,
                     p50: pct(0.50),
                     mean: samples.reduce(0, +) / Double(samples.count),
                     p95: pct(0.95),
                     p99: pct(0.99),
                     max: sorted.last ?? 0)
    }
}
