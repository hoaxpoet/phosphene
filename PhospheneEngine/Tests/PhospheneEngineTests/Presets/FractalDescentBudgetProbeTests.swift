// FractalDescentBudgetProbeTests — FD.1 task-3 performance gate.
//
// Measures Fractal Descent's per-preset GPU cost at 1920×1080 through the LIVE
// ray-march dispatch path (RayMarchPipeline.render: G-buffer → lighting →
// composite → post-process), adapted from RayMarchPathHarnessTemplate (QG.4,
// D-182 — copy-adapt the paradigm template, do not reinvent) with the
// GPU-timestamp timing method from NimbusBudgetProbeTests.
//
// WHY THIS RUNS BEFORE ANY BEAUTY WORK: the Mandelbox distance estimator is
// evaluated up to 139× per hit pixel by the shared preamble — 128 march steps
// + 6 for the central-differences normal + 5 for the AO cone — and each
// evaluation runs FD_ITERS fold iterations. That product is the whole budget
// risk, and it is knowable now, before materials/god-rays/fog exist.
//
// GATE (PG_FD_FRACTAL_DESCENT.md §A8): Tier-2 p95 ≤ 7 ms at 1080p. Over budget
// ⇒ STOP AND REPORT; the concept is re-scoped or cut, not tuned toward budget
// across increments.
//
// Env-gated `FD_BUDGET=1` so it stays out of the default `swift test` run.
//
// Invocation:
//   FD_BUDGET=1 swift test --package-path PhospheneEngine \
//       --filter FractalDescentBudgetProbe

import Testing
import Foundation
import Metal
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import Renderer
@testable import Presets
@testable import Shared

// MARK: - FractalDescentBudgetProbeTests

@Suite("FractalDescentBudgetProbe")
@MainActor
struct FractalDescentBudgetProbeTests {

    private static let width = 1920
    private static let height = 1080
    private static let warmupFrames = 10
    private static let measuredFrames = 60
    private static let subjectName = "Fractal Descent"
    private static let tier2CeilingMs = 7.0

    /// Known-good ray-march control. Lumen Mosaic is CERTIFIED with a declared
    /// `complexity_cost.tier2` of 3.7 ms, so measuring it through this same probe
    /// says whether a given number means "this preset is expensive" or "this probe
    /// over-reads" (it also pins which hardware tier the run is on).
    private static let controlName = "Lumen Mosaic"
    private static let controlDeclaredTier2Ms = 3.7

    @Test("ray-march control: Lumen Mosaic through the same probe (FD_BUDGET=1)")
    func test_controlBudgetProbe() throws {
        guard ProcessInfo.processInfo.environment["FD_BUDGET"] == "1" else {
            print("[FDBudget] FD_BUDGET not set — skipping")
            return
        }
        let stats = try measure(presetNamed: Self.controlName)
        print(String(format: """
            [FDBudget] CONTROL %@ — declared complexity_cost.tier2 = %.1f ms
            [FDBudget]   p50=%.3f  p95=%.3f ms  (ratio measured/declared = %.2f×)
            """, Self.controlName, Self.controlDeclaredTier2Ms,
            stats.p50, stats.p95, stats.p95 / Self.controlDeclaredTier2Ms))
    }

    @Test("Fractal Descent per-preset GPU cost @ 1920×1080 (FD_BUDGET=1)")
    func test_fractalDescentBudgetProbe() throws {
        guard ProcessInfo.processInfo.environment["FD_BUDGET"] == "1" else {
            print("[FDBudget] FD_BUDGET not set — skipping")
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
    /// Run once per FD_ITERS value; the PNGs are the comparison.
    @Test("descent contact sheet (FD_BUDGET=1, FD_RENDER=1)")
    func test_descentContactSheet() throws {
        guard ProcessInfo.processInfo.environment["FD_BUDGET"] == "1",
              ProcessInfo.processInfo.environment["FD_RENDER"] == "1" else {
            print("[FDBudget] FD_RENDER not set — skipping contact sheet")
            return
        }
        let dir = URL(fileURLWithPath: ProcessInfo.processInfo.environment["FD_RENDER_DIR"]
                      ?? NSTemporaryDirectory().appending("fd_frames"))
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // 0.0 / 0.33 / 0.66 of one self-similar octave — the wrap point is 1.0,
        // so frame 0 and a hypothetical frame 1.0 are the same structure.
        let phases: [Float] = [0.0, 0.33, 0.66]
        for (i, phase) in phases.enumerated() {
            let px = try renderSingle(presetNamed: Self.subjectName, audioPhase: phase / 0.12)
            let url = dir.appendingPathComponent(String(format: "descent_%02d_phase%.2f.png", i, phase))
            try writePNG(bgra: px, width: Self.width, height: Self.height, to: url)
            print("[FDBudget] wrote \(url.path)")
        }
    }

    /// Renders one frame at an explicit descent phase and returns BGRA bytes.
    /// `sceneParamsA.x` (accumulated audio time) is normally written by
    /// RenderPipeline+RayMarch, which this probe bypasses — so it is set here
    /// directly, which is also why the timing runs above all sit at phase 0.
    private func renderSingle(presetNamed name: String, audioPhase: Float) throws -> [UInt8] {
        let ctx = try MetalContext()
        let lib = try ShaderLibrary(context: ctx)
        let loader = PresetLoader(device: ctx.device, pixelFormat: ctx.pixelFormat, loadBuiltIn: true)
        guard let preset = loader.presets.first(where: { $0.descriptor.name == name }),
              let gbufferState = preset.rayMarchPipelineState else {
            throw HarnessError.presetNotFound(name)
        }
        let pipeline = try RayMarchPipeline(context: ctx, shaderLibrary: lib)
        pipeline.allocateTextures(width: Self.width, height: Self.height)
        var scene = preset.descriptor.makeSceneUniforms()
        scene.sceneParamsA.x = audioPhase
        scene.sceneParamsA.y = Float(Self.width) / Float(Self.height)
        pipeline.sceneUniforms = scene
        pipeline.ssgiEnabled = preset.descriptor.passes.contains(.ssgi)

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
        pipeline.allocateTextures(width: Self.width, height: Self.height)
        var scene = preset.descriptor.makeSceneUniforms()
        scene.sceneParamsA.y = Float(Self.width) / Float(Self.height)
        // sceneParamsB.z is the live FrameBudgetManager step multiplier (D-057):
        // 1.0 = 128 march steps, 0.5 = 64 (what §A8 assumed), floor 0.25 = 32.
        if let mult = ProcessInfo.processInfo.environment["FD_STEP_MULT"].flatMap(Float.init) {
            scene.sceneParamsB.z = mult
            print(String(format: "[FDBudget] step multiplier %.2f → %d march steps", mult, Int(128.0 * mult)))
        }
        pipeline.sceneUniforms = scene
        pipeline.ssgiEnabled = preset.descriptor.passes.contains(.ssgi)

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
