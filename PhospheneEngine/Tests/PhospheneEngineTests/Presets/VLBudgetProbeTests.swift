// VLBudgetProbeTests — Volumetric Lithograph per-preset GPU cost.
//
// WHY: Matt's live session 2026-07-24T14-47-41Z measured VL at **1.0 fps
// (median 986.6 ms/frame)** while Staged Sandbox held 59.9 fps in the same
// window — so it is VL, not the machine and not the stem-separation load.
// Against the ~5 ms Tier-2 ceiling that is ~200x over budget. This probe is the
// instrument for the fix: measure, change, re-measure.
//
// Copy-adapted from FractalFlyByBudgetProbeTests (same live RayMarchPipeline
// seam, same Lumen Mosaic control so a number can be read as "VL is expensive"
// rather than "the probe over-reads").
//
// Env-gated: VL_BUDGET=1

import Testing
import Foundation
import Metal
import simd
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import Renderer
@testable import Presets
@testable import Shared

@Suite("Volumetric Lithograph budget probe (env-gated)")
@MainActor
struct VLBudgetProbeTests {

    // FLY.5: default to the size Matt actually watches (windowed ~1067×750), not
    // 1080p. Rendering at higher resolution than production made every offline
    // check look cleaner than the live app — the divergence that hid four rounds
    // of aliasing. VL_W / VL_H override (perf gate still measured at 1920×1080).
    private static let width  = Int(ProcessInfo.processInfo.environment["VL_W"] ?? "") ?? 1067
    private static let height = Int(ProcessInfo.processInfo.environment["VL_H"] ?? "") ?? 750
    private static let warmupFrames = 10
    private static let measuredFrames = 60
    private static let subjectName = "Volumetric Lithograph"
    // REGRESSION gate, not an aspiration. Measured on this probe (M2 Pro, the
    // 1067x750 default = Matt's actual window):
    //     v9.4 baseline ................  7.6 ms
    //     VL-PSY.1 as shipped .......... 1120.0 ms   <- the defect
    //     VL-PSY.2 after the fix .......  9.7 ms
    // VL has NEVER met the ~5 ms SHADER_CRAFT budget, so gating at 5 would fail
    // on day one and teach nothing. 12 ms catches a real regression with margin
    // over today's 9.7 while staying far below the 1120 ms class of failure.
    private static let tier2CeilingMs = 12.0

    /// Known-good ray-march control. Lumen Mosaic is CERTIFIED with a declared
    /// `complexity_cost.tier2` of 3.7 ms, so measuring it through this same probe
    /// says whether a given number means "this preset is expensive" or "this probe
    /// over-reads" (it also pins which hardware tier the run is on).
    private static let controlName = "Lumen Mosaic"
    private static let controlDeclaredTier2Ms = 3.7

    @Test("ray-march control: Lumen Mosaic through the same probe (VL_BUDGET=1)")
    func test_controlBudgetProbe() throws {
        guard ProcessInfo.processInfo.environment["VL_BUDGET"] == "1" else {
            print("[VLBudget] VL_BUDGET not set — skipping")
            return
        }
        let stats = try measure(presetNamed: Self.controlName)
        print(String(format: """
            [VLBudget] CONTROL %@ — declared complexity_cost.tier2 = %.1f ms
            [VLBudget]   p50=%.3f  p95=%.3f ms  (ratio measured/declared = %.2f×)
            """, Self.controlName, Self.controlDeclaredTier2Ms,
            stats.p50, stats.p95, stats.p95 / Self.controlDeclaredTier2Ms))
    }

    @Test("Volumetric Lithograph per-preset GPU cost (VL_BUDGET=1)")
    func test_vlBudgetProbe() throws {
        guard ProcessInfo.processInfo.environment["VL_BUDGET"] == "1" else {
            print("[VLBudget] VL_BUDGET not set — skipping")
            return
        }
        let stats = try measure(presetNamed: Self.subjectName)
        let (p50, p95, p99, mean) = (stats.p50, stats.p95, stats.p99, stats.mean)

        print(String(format: """
            [VLBudget] %@ @ %dx%d — live ray_march (G-buffer→lighting→composite→post)
            [VLBudget]   min=%.3f  p50=%.3f  mean=%.3f  p95=%.3f  p99=%.3f  max=%.3f ms
            [VLBudget]   VERDICT: p95 %.3f ms vs %.1f ms Tier-2 ceiling — %@
            """,
            Self.subjectName, Self.width, Self.height,
            stats.min, p50, mean, p95, p99, stats.max,
            p95, Self.tier2CeilingMs, p95 <= Self.tier2CeilingMs ? "WITHIN" : "OVER"))

        #expect(p95 <= Self.tier2CeilingMs, """
            VL performance gate FAILED: p95 \(String(format: "%.3f", p95)) ms exceeds the \
            \(Self.tier2CeilingMs) ms Tier-2 ceiling at \(Self.width)×\(Self.height). \
            Per §A8 this is STOP AND REPORT — the concept is re-scoped or cut, not tuned \
            toward budget across increments.
            """)
    }

    /// Dumps three frames spanning one full descent octave, so the iteration-cap
    /// decision (§9 DECISION-NEEDED 3: "reduce ambition vs cut the preset") can be
    /// made against what it actually looks like rather than against a number.
    /// Run once per FFB_ITERS value; the PNGs are the comparison.
            @Test("camera basis does not accumulate jitter drift (VL_BUDGET=1)")
    func test_jitterDoesNotAccumulate() throws {
        guard ProcessInfo.processInfo.environment["VL_BUDGET"] == "1" else { return }
        let ctx = try MetalContext()
        let lib = try ShaderLibrary(context: ctx)
        let loader = PresetLoader(device: ctx.device, pixelFormat: ctx.pixelFormat, loadBuiltIn: true)
        guard let preset = loader.presets.first(where: { $0.descriptor.name == Self.subjectName }) else {
            throw HarnessError.presetNotFound(Self.subjectName)
        }
        let pipeline = try RayMarchPipeline(context: ctx, shaderLibrary: lib)
        pipeline.metalFXEnabled = preset.descriptor.usesMetalFXTemporal
        pipeline.metalFXRenderScale = preset.descriptor.effectiveRenderScale
        pipeline.motionPipelineState = preset.motionPipelineState
        pipeline.allocateTextures(width: Self.width, height: Self.height)

        var scene = preset.descriptor.makeSceneUniforms()
        scene.sceneParamsA.y = Float(Self.width) / Float(Self.height)
        pipeline.sceneUniforms = scene
        let original = simd_normalize(SIMD3(scene.cameraForward.x, scene.cameraForward.y, scene.cameraForward.z))

        for _ in 0..<600 {
            pipeline.applyJitter(width: Self.width, height: Self.height)
            pipeline.metalFX?.advanceFrame()
        }
        let fwd = pipeline.sceneUniforms.cameraForward
        let drift = simd_length(simd_normalize(SIMD3(fwd.x, fwd.y, fwd.z)) - original)
        print(String(format: "[FFBBudget] camera-forward drift after 600 frames: %.6f", drift))
        #expect(drift < 0.002, """
            Camera forward drifted \(drift) after 600 frames — jitter is accumulating. \
            applyJitter must offset from the stored UNJITTERED basis, never the live value.
            """)
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
        print("[VLBudget] device: \(ctx.device.name)")
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
            print(String(format: "[VLBudget] step multiplier %.2f → %d march steps", mult, Int(128.0 * mult)))
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
