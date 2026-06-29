// MultiPassFlashHarnessTests — CLEAN.7.6c. The faithful multi-pass / feedback half of
// the photosensitivity flash-safety gate (GAP-9). It closes the four certified presets
// the single-pass FeatureVector harness (`PhotosensitivityCertificationTests`) renders
// static because their music response arrives through multi-pass rendering:
//
//   - Lumen Mosaic — ray_march + post_process + the 4-light CPU follower (slot 8)
//   - Dragon Bloom — mv_warp feedback (strands-on-top + a per-beat display pulse)
//   - Fata Morgana — mv_warp feedback (bespoke blur → warp → shapes → mirage path)
//   - Skein        — mv_warp feedback (cream canvas-hold + per-stem paint + wet sheen)
//
// Each is driven over the shared worst-case beat + stem train, its rendered full-frame
// WCAG relative luminance is measured by `FlashAnalyzer`, and the Harding/WCAG 2.3.1
// ≤ 3 flashes/s limit is asserted. Over-limit ⇒ a P1 safety finding to bring to Matt,
// NOT a number to tune away — the certified beat-luminance motion was hand-built safe
// (D-157 bounded per-beat footprint + steady global luminance; D-158).
//
// FAITHFULNESS (kickoff): the live render paths are driven HEADLESS, not reimplemented
// (FA #66). rayMarch marches the live 128-step budget (BUG-034: `sceneParamsB.z`
// defaults to 1.0). mv_warp runs the real feedback chain with persistence — each frame's
// composite becomes the next frame's history via the production swap, no per-frame clear.
// Lumen's follower is ticked and a real palette is loaded (an unloaded palette renders
// black cells — BUG-016 — which would falsely read static). A degraded render that
// happens to read safe is a false pass, so the responsiveness guard FAILS LOUD on a
// static frame rather than asserting it safe (the CLEAN.0 / CLEAN.7.6 rule).
//
// GPU test — manual-closeout suite, not the CI fast gate (like the rest of the
// photosensitivity gate). Drive + luminance primitives are shared with the single-pass
// gate via `FlashHarnessSupport`.

import Testing
import Metal
@testable import Renderer
@testable import Presets
@testable import Shared

// MARK: - MultiPassFlashHarnessTests

@Suite("Photosensitivity Multi-Pass Flash Harness (Harding / WCAG 2.3.1, CLEAN.7.6c)")
@MainActor
struct MultiPassFlashHarnessTests {

    /// 16:9 keeps Fata Morgana's aspect-driven shape placement faithful, and is small
    /// enough that 180 frames × 4 presets run in the manual suite. The Harding metric is
    /// the full-frame MEAN luminance, which is scale-invariant for global pumping, so a
    /// modest render size is faithful for the flash signal.
    private static let width = 320
    private static let height = 180

    // MARK: - Gate (one test per preset → its own evidence line + assertion)

    @Test("Lumen Mosaic is flash-safe (rayMarch + follower, real headless render)")
    func lumenMosaicIsFlashSafe() throws {
        assertFlashSafe(name: "Lumen Mosaic", luma: try renderLumenMosaic())
    }

    @Test("Dragon Bloom is flash-safe (mv_warp feedback, real headless render)")
    func dragonBloomIsFlashSafe() throws {
        assertFlashSafe(name: "Dragon Bloom", luma: try renderMVWarp(presetName: "Dragon Bloom"))
    }

    @Test("Fata Morgana is flash-safe (mv_warp bespoke, real headless render)")
    func fataMorganaIsFlashSafe() throws {
        assertFlashSafe(name: "Fata Morgana", luma: try renderFataMorgana())
    }

    @Test("Skein is flash-safe (mv_warp canvas-hold + follower, real headless render)")
    func skeinIsFlashSafe() throws {
        assertFlashSafe(name: "Skein", luma: try renderMVWarp(presetName: "Skein"))
    }

    @Test("Nacre is flash-safe (mv_warp feedback, downbeat camera push, real headless render)")
    func nacreIsFlashSafe() throws {
        assertFlashSafe(name: "Nacre", luma: try renderNacre())
    }

    @Test("Floret is flash-safe (mv_warp feedback, bass-kick ripple + swirl + downbeat push, real headless render)")
    func floretIsFlashSafe() throws {
        assertFlashSafe(name: "Floret", luma: try renderFloret())
    }

    @Test("Glaze is flash-safe (mv_warp feedback + GLAZE.6 glossy bloom, real headless render)")
    func glazeIsFlashSafe() throws {
        assertFlashSafe(name: "Glaze", luma: try renderGlaze())
    }

    // MARK: - Assertion (shared)

    /// Print the per-preset evidence line (the closeout all-7 table is these four plus the
    /// single-pass gate's three) and assert flash-safety. Fails LOUD on a static render —
    /// a static frame is never asserted "safe" (that would be a vacuous pass for a safety
    /// gate); it means the harness did not reach the preset's real response.
    private func assertFlashSafe(name: String, luma: [Double]) {
        let report = FlashAnalyzer.analyze(relativeLuminance: luma, fps: FlashHarnessSupport.fps)
        let lo = luma.min() ?? 0, hi = luma.max() ?? 0
        let range = hi - lo
        let mean = luma.reduce(0, +) / Double(max(luma.count, 1))
        let responded = range >= FlashHarnessSupport.responsiveLumaRange

        print(String(
            format: "[flash-safety] %@: %@ | peak %.2f flashes/s (%d transitions) — %@ | luma %.3f…%.3f (Δ%.3f, mean %.3f) [limit 3.0]",
            name, responded ? "MEASURED" : "UNMEASURED(static)",
            report.peakFlashesPerSecond, report.transitionCount,
            report.isSafe ? "SAFE" : "UNSAFE", lo, hi, range, mean))

        #expect(
            responded,
            """
            '\(name)' rendered static (Δ\(String(format: "%.4f", range))) under the worst-case beat+stem train — \
            the harness is not reaching its real multi-pass response, so the measurement is INVALID (not safe). \
            Fix the harness setup; do not weaken this guard.
            """)
        #expect(
            report.isSafe,
            """
            '\(name)' peaks at \(String(format: "%.2f", report.peakFlashesPerSecond)) flashes/s (limit 3) under a \
            \(String(format: "%.1f", FlashHarnessSupport.accentHz)) Hz worst-case beat train — exceeds Harding/WCAG 2.3.1. \
            P1 safety finding: bring to Matt, do NOT tune away (the certified motion was hand-built safe, D-157/D-158).
            """)
    }

    // MARK: - Render: ray-march (Lumen Mosaic)

    /// Lumen Mosaic — `ray_march` + `post_process`. Composes a standalone
    /// `RayMarchPipeline` (the BUG-034 production-parity pattern: live 128-step budget,
    /// IBL, post-process chain) and ticks the real `LumenPatternEngine` follower into
    /// slot 8 each frame. A real palette is loaded so the cells are not black (BUG-016).
    private func renderLumenMosaic() throws -> [Double] {
        let ctx = try MetalContext()
        let lib = try ShaderLibrary(context: ctx)
        guard let preset = _acceptanceFixture.presets.first(where: { $0.descriptor.name == "Lumen Mosaic" }) else {
            throw FlashHarnessError.presetNotFound("Lumen Mosaic")
        }
        guard let gbufferState = preset.rayMarchPipelineState else {
            throw FlashHarnessError.setupFailed("Lumen Mosaic rayMarchPipelineState missing")
        }

        let pipeline = try RayMarchPipeline(context: ctx, shaderLibrary: lib)
        pipeline.allocateTextures(width: Self.width, height: Self.height)
        var scene = preset.descriptor.makeSceneUniforms()         // sceneParamsB.z default 1.0 ⇒ 128 steps
        scene.sceneParamsA.y = Float(Self.width) / Float(Self.height)
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

        guard let engine = LumenPatternEngine(device: ctx.device) else {
            throw FlashHarnessError.setupFailed("LumenPatternEngine allocation")
        }
        engine.setPalette(LumenMosaicPaletteLibrary.all[0])       // a real (non-black) palette — else BUG-016 static

        let floatStride = MemoryLayout<Float>.stride
        guard let fft = ctx.makeSharedBuffer(length: 512 * floatStride),
              let wav = ctx.makeSharedBuffer(length: 2048 * floatStride) else {
            throw FlashHarnessError.setupFailed("audio buffers")
        }
        let outTex = try makeOutputTexture(ctx)

        let drive = FlashHarnessSupport.worstCaseBeatTrain()
        let stems = FlashHarnessSupport.worstCaseStemTrain()
        return try renderLoop(ctx, outTex) { i, pixels in
            var fv = drive[i]
            let stem = stems[i]
            engine.tick(features: fv, stems: stem)                // advance the 4-light beat-locked dance
            guard let cmd = ctx.commandQueue.makeCommandBuffer() else { throw FlashHarnessError.renderFailed }
            pipeline.render(
                gbufferPipelineState: gbufferState,
                features: &fv,
                fftBuffer: fft, waveformBuffer: wav,
                stemFeatures: stem,
                outputTexture: outTex,
                commandBuffer: cmd,
                noiseTextures: noise,
                iblManager: ibl,
                postProcessChain: postChain,
                presetFragmentBuffer3: engine.patternBuffer)
            try commit(cmd, outTex, into: &pixels)
        }
    }

    // MARK: - Render: generic mv_warp (Dragon Bloom, Skein)

    /// Drive a generic mv_warp feedback preset (Dragon Bloom / Skein) through the real
    /// `RenderPipeline.renderMVWarpToTexture` seam — the same warp → strands/marks-on-top
    /// → blit(+post +beat-pulse) → swap chain the live app runs, minus the present.
    /// Feedback persists across frames via the production swap (no per-frame clear).
    private func renderMVWarp(presetName: String) throws -> [Double] {
        let ctx = try MetalContext()
        let lib = try ShaderLibrary(context: ctx)
        let noise = try TextureManager(context: ctx, shaderLibrary: lib)
        let floatStride = MemoryLayout<Float>.stride
        guard let fft = ctx.makeSharedBuffer(length: 512 * floatStride),
              let wav = ctx.makeSharedBuffer(length: 2048 * floatStride) else {
            throw FlashHarnessError.setupFailed("audio buffers")
        }
        let pipeline = try RenderPipeline(context: ctx, shaderLibrary: lib, fftBuffer: fft, waveformBuffer: wav)
        pipeline.setTextureManager(noise)
        guard let preset = _acceptanceFixture.presets.first(where: { $0.descriptor.name == presetName }) else {
            throw FlashHarnessError.presetNotFound(presetName)
        }
        let size = CGSize(width: Self.width, height: Self.height)
        pipeline.currentDrawableSize = size
        try configureMVWarp(pipeline: pipeline, preset: preset, context: ctx, size: size)

        // Skein follower (Skein.ENGINE.1.2): paint state → slot-6 overlay buffer + the
        // per-track cream ground + per-frame wetness decay (the sheen the flash signal
        // reads). Other generic mv_warp presets (Dragon Bloom) carry no follower — their
        // strands are stem-driven through the vertex shader from the stem train.
        let skein: SkeinState?
        if presetName == "Skein" {
            guard let state = SkeinState(device: ctx.device, seed: 42) else {
                throw FlashHarnessError.setupFailed("SkeinState allocation")
            }
            pipeline.setDirectPresetFragmentBuffer(state.skeinBuffer)   // slot 6
            let g = state.groundLinear
            pipeline.setMVWarpCanvasGround(SIMD4<Double>(Double(g.x), Double(g.y), Double(g.z), 1))
            pipeline.clearMVWarpCanvasToGround()
            skein = state
        } else {
            skein = nil
        }

        let outTex = try makeOutputTexture(ctx)
        let drive = FlashHarnessSupport.worstCaseBeatTrain()
        let stems = FlashHarnessSupport.worstCaseStemTrain()
        return try renderLoop(ctx, outTex) { i, pixels in
            var fv = drive[i]
            let stem = stems[i]
            if let skein {
                skein.tick(deltaTime: fv.deltaTime, features: fv, stems: stem)
                pipeline.setMVWarpWetnessDecay(skein.wetnessDecay)
            }
            // Re-fetch each frame: the swap inside renderMVWarpToTexture rotates the
            // stored warp/compose textures, so a snapshot captured once goes stale.
            guard let cmd = ctx.commandQueue.makeCommandBuffer(),
                  let warpState = pipeline.mvWarpState else { throw FlashHarnessError.renderFailed }
            pipeline.renderMVWarpToTexture(
                commandBuffer: cmd,
                target: outTex,
                features: &fv,
                stemFeatures: stem,
                activePipeline: preset.pipelineState,
                warpState: warpState,
                sceneAlreadyRendered: false)
            try commit(cmd, outTex, into: &pixels)
        }
    }

    // MARK: - Render: Fata Morgana (bespoke mv_warp)

    /// Fata Morgana — `direct` + `mv_warp` with the bespoke `renderFataMorgana` path
    /// (blur → custom warp → shapes → mirage comp → swap). That production method is
    /// already target-agnostic, so the harness drives it byte-for-byte like the live app.
    private func renderFataMorgana() throws -> [Double] {
        let ctx = try MetalContext()
        let lib = try ShaderLibrary(context: ctx)
        let noise = try TextureManager(context: ctx, shaderLibrary: lib)
        let floatStride = MemoryLayout<Float>.stride
        guard let fft = ctx.makeSharedBuffer(length: 512 * floatStride),
              let wav = ctx.makeSharedBuffer(length: 2048 * floatStride) else {
            throw FlashHarnessError.setupFailed("audio buffers")
        }
        let pipeline = try RenderPipeline(context: ctx, shaderLibrary: lib, fftBuffer: fft, waveformBuffer: wav)
        pipeline.setTextureManager(noise)
        guard let preset = _acceptanceFixture.presets.first(where: { $0.descriptor.name == "Fata Morgana" }) else {
            throw FlashHarnessError.presetNotFound("Fata Morgana")
        }
        let size = CGSize(width: Self.width, height: Self.height)
        pipeline.currentDrawableSize = size
        try configureMVWarp(pipeline: pipeline, preset: preset, context: ctx, size: size)
        pipeline.fataGlowSeedJitter = 0   // deterministic (production re-rolls per activation)

        let outTex = try makeOutputTexture(ctx)
        let drive = FlashHarnessSupport.worstCaseBeatTrain()
        let stems = FlashHarnessSupport.worstCaseStemTrain()
        return try renderLoop(ctx, outTex) { i, pixels in
            guard let cmd = ctx.commandQueue.makeCommandBuffer(),
                  let warpState = pipeline.mvWarpState else { throw FlashHarnessError.renderFailed }
            pipeline.renderFataMorgana(
                commandBuffer: cmd,
                features: drive[i],
                stemFeatures: stems[i],
                warpState: warpState,
                target: outTex)
            try commit(cmd, outTex, into: &pixels)
        }
    }

    // MARK: - Render: Nacre (bespoke mv_warp, NACRE.4)

    /// Nacre — `direct` + `mv_warp` with the bespoke `renderNacre` path (custom warp → comp →
    /// swap; HDR .rgba16Float feedback). The worst-case train drives `barPhase01` (line ~82),
    /// so the NACRE.4 downbeat camera push fires and IS measured (not a push-less render).
    private func renderNacre() throws -> [Double] {
        let ctx = try MetalContext()
        let lib = try ShaderLibrary(context: ctx)
        let noise = try TextureManager(context: ctx, shaderLibrary: lib)
        let floatStride = MemoryLayout<Float>.stride
        guard let fft = ctx.makeSharedBuffer(length: 512 * floatStride),
              let wav = ctx.makeSharedBuffer(length: 2048 * floatStride) else {
            throw FlashHarnessError.setupFailed("audio buffers")
        }
        let pipeline = try RenderPipeline(context: ctx, shaderLibrary: lib, fftBuffer: fft, waveformBuffer: wav)
        pipeline.setTextureManager(noise)
        guard let preset = _acceptanceFixture.presets.first(where: { $0.descriptor.name == "Nacre" }) else {
            throw FlashHarnessError.presetNotFound("Nacre")
        }
        let size = CGSize(width: Self.width, height: Self.height)
        pipeline.currentDrawableSize = size
        try configureMVWarp(pipeline: pipeline, preset: preset, context: ctx, size: size)

        let outTex = try makeOutputTexture(ctx)
        let drive = FlashHarnessSupport.worstCaseBeatTrain()
        let stems = FlashHarnessSupport.worstCaseStemTrain()
        return try renderLoop(ctx, outTex) { i, pixels in
            guard let cmd = ctx.commandQueue.makeCommandBuffer(),
                  let warpState = pipeline.mvWarpState else { throw FlashHarnessError.renderFailed }
            pipeline.renderNacre(
                commandBuffer: cmd,
                features: drive[i],
                stemFeatures: stems[i],
                warpState: warpState,
                target: outTex)
            try commit(cmd, outTex, into: &pixels)
        }
    }

    // MARK: - Render: Floret (bespoke mv_warp, FLORET.4)

    /// Floret — `direct` + `mv_warp` with the bespoke `renderFloret` path (z² warp → 3-fold
    /// radial-pulse comp → swap; HDR .rgba16Float). The worst-case train drives `barPhase01`
    /// (→ the downbeat camera push) AND `bassDev` (→ the bass-kick radial ripple, at the accent
    /// Hz — so the new motion is stressed in the flash danger band, not a kick-less render).
    private func renderFloret() throws -> [Double] {
        let ctx = try MetalContext()
        let lib = try ShaderLibrary(context: ctx)
        let noise = try TextureManager(context: ctx, shaderLibrary: lib)
        let floatStride = MemoryLayout<Float>.stride
        guard let fft = ctx.makeSharedBuffer(length: 512 * floatStride),
              let wav = ctx.makeSharedBuffer(length: 2048 * floatStride) else {
            throw FlashHarnessError.setupFailed("audio buffers")
        }
        let pipeline = try RenderPipeline(context: ctx, shaderLibrary: lib, fftBuffer: fft, waveformBuffer: wav)
        pipeline.setTextureManager(noise)
        guard let preset = _acceptanceFixture.presets.first(where: { $0.descriptor.name == "Floret" }) else {
            throw FlashHarnessError.presetNotFound("Floret")
        }
        let size = CGSize(width: Self.width, height: Self.height)
        pipeline.currentDrawableSize = size
        try configureMVWarp(pipeline: pipeline, preset: preset, context: ctx, size: size)

        let outTex = try makeOutputTexture(ctx)
        let drive = FlashHarnessSupport.worstCaseBeatTrain()
        let stems = FlashHarnessSupport.worstCaseStemTrain()
        return try renderLoop(ctx, outTex) { i, pixels in
            guard let cmd = ctx.commandQueue.makeCommandBuffer(),
                  let warpState = pipeline.mvWarpState else { throw FlashHarnessError.renderFailed }
            pipeline.renderFloret(
                commandBuffer: cmd,
                features: drive[i],
                stemFeatures: stems[i],
                warpState: warpState,
                target: outTex)
            try commit(cmd, outTex, into: &pixels)
        }
    }

    // MARK: - Render: Glaze (bespoke mv_warp, GLAZE.3–6)

    /// Glaze — `direct` + `mv_warp`, the bespoke `renderGlaze` path (blur pyramid → custom warp →
    /// comp → swap; HDR .rgba16Float feedback). The worst-case stem train drives the per-stem routes
    /// (bass/other lateral, drums punch, vocals glow) and the GLAZE.6 bloom, so the brightness signal
    /// the analyzer reads is the real audio-driven one — the uplift-B flash check.
    private func renderGlaze() throws -> [Double] {
        let ctx = try MetalContext()
        let lib = try ShaderLibrary(context: ctx)
        let noise = try TextureManager(context: ctx, shaderLibrary: lib)
        let floatStride = MemoryLayout<Float>.stride
        guard let fft = ctx.makeSharedBuffer(length: 512 * floatStride),
              let wav = ctx.makeSharedBuffer(length: 2048 * floatStride) else {
            throw FlashHarnessError.setupFailed("audio buffers")
        }
        let pipeline = try RenderPipeline(context: ctx, shaderLibrary: lib, fftBuffer: fft, waveformBuffer: wav)
        pipeline.setTextureManager(noise)
        guard let preset = _acceptanceFixture.presets.first(where: { $0.descriptor.name == "Glaze" }),
              let mvWarp = preset.mvWarpPipelines else {
            throw FlashHarnessError.presetNotFound("Glaze")
        }
        let size = CGSize(width: Self.width, height: Self.height)
        pipeline.currentDrawableSize = size
        let bundle = MVWarpPipelineBundle(
            warpState: mvWarp.warpState, composeState: mvWarp.composeState, blitState: mvWarp.blitState,
            pixelFormat: ctx.pixelFormat, feedbackFormat: .rgba16Float,
            blurState: mvWarp.blurState, isGlaze: true)
        pipeline.setupMVWarp(bundle: bundle, size: size)
        pipeline.setMVWarpDecay(preset.descriptor.decay)

        let outTex = try makeOutputTexture(ctx)
        let drive = FlashHarnessSupport.worstCaseBeatTrain()
        let stems = FlashHarnessSupport.worstCaseStemTrain()
        return try renderLoop(ctx, outTex) { i, pixels in
            guard let cmd = ctx.commandQueue.makeCommandBuffer(),
                  let warpState = pipeline.mvWarpState else { throw FlashHarnessError.renderFailed }
            pipeline.renderGlaze(
                commandBuffer: cmd,
                features: drive[i],
                stemFeatures: stems[i],
                warpState: warpState,
                target: outTex)
            try commit(cmd, outTex, into: &pixels)
        }
    }

    // MARK: - mv_warp setup (mirrors VisualizerEngine+Presets applyPreset, MV-2)

    /// Reproduce the app's per-preset mv_warp wiring: build the pipeline bundle (with the
    /// preset's feedback format + canvas-clear ground), set decay, wire the marks-on-top
    /// overlay (Dragon Bloom strands / Skein disc) with its chromatic + comp + beat-pulse,
    /// and attach Fata Morgana's custom-shape pipelines (nil for the others).
    private func configureMVWarp(
        pipeline: RenderPipeline,
        preset: PresetLoader.LoadedPreset,
        context ctx: MetalContext,
        size: CGSize
    ) throws {
        let desc = preset.descriptor
        guard let warp = preset.mvWarpPipelines else {
            throw FlashHarnessError.setupFailed("\(desc.name) mvWarpPipelines missing")
        }
        // Fata Morgana feeds back in LINEAR .bgra8Unorm (butterchurn parity); Nacre in HDR
        // .rgba16Float (NACRE.4); the rest use the drawable format. MUST match the format the
        // pipelines were compiled for.
        let feedbackFormat: MTLPixelFormat
        switch desc.name {
        case "Fata Morgana": feedbackFormat = .bgra8Unorm
        case "Nacre":        feedbackFormat = .rgba16Float
        case "Floret":       feedbackFormat = .rgba16Float
        default:             feedbackFormat = ctx.pixelFormat
        }
        // Skein's cream canvas-hold ground is the held feedback clear; black for the rest.
        let canvasClear = desc.marks?.canvasClear.map {
            SIMD4<Double>(Double($0.x), Double($0.y), Double($0.z), 1)
        } ?? SIMD4<Double>(0, 0, 0, 1)
        let bundle = MVWarpPipelineBundle(
            warpState: warp.warpState,
            composeState: warp.composeState,
            blitState: warp.blitState,
            pixelFormat: ctx.pixelFormat,
            feedbackFormat: feedbackFormat,
            blurState: warp.blurState,                // non-nil ⇒ Fata Morgana fata branch
            isNacre: desc.name == "Nacre",            // ⇒ drawWithNacre branch (NACRE.4)
            isFloret: desc.name == "Floret",          // ⇒ drawWithFloret branch (FLORET.4)
            canvasClearColor: canvasClear)
        pipeline.setupMVWarp(bundle: bundle, size: size)
        pipeline.setMVWarpDecay(desc.decay)

        if let geoState = warp.sceneGeometryState, let marks = desc.marks {
            pipeline.setSceneGeometry(
                geoState,
                vertexCount: marks.vertexCount,
                instanceCount: marks.instanceCount,
                primitive: Self.primitiveType(marks.primitive))
            pipeline.setMVWarpChromatic(marks.chromatic)
            pipeline.setMVWarpPost(
                invert: marks.comp.invert,
                echo: marks.comp.echo,
                gamma: marks.comp.gamma,
                beatPulse: marks.beatPulse)
        } else {
            pipeline.setSceneGeometry(nil, vertexCount: 0, instanceCount: 0, primitive: .lineStrip)
            pipeline.setMVWarpChromatic(0)
            pipeline.setMVWarpPost(invert: 0, echo: 0, gamma: 1)
        }
        pipeline.setFataShapePipelines(additive: warp.shapeAdditiveState, normal: warp.shapeNormalState)
    }

    /// `marks.primitive` string → `MTLPrimitiveType` (mirrors VisualizerEngine+Presets'
    /// private `mvWarpMarksPrimitive`).
    private static func primitiveType(_ name: String) -> MTLPrimitiveType {
        switch name {
        case "point":          return .point
        case "line":           return .line
        case "line_strip":     return .lineStrip
        case "triangle":       return .triangle
        case "triangle_strip": return .triangleStrip
        default:               return .triangle
        }
    }

    // MARK: - Render loop / readback plumbing

    /// Drive `body` once per frame of the worst-case train, reading the output texture's
    /// full-frame mean WCAG luminance after each. `body` encodes + commits the frame and
    /// fills `pixels` (via `commit`).
    private func renderLoop(
        _ ctx: MetalContext,
        _ outTex: MTLTexture,
        _ body: (_ frame: Int, _ pixels: inout [UInt8]) throws -> Void
    ) throws -> [Double] {
        let frameCount = Int(FlashHarnessSupport.driveSeconds * FlashHarnessSupport.fps)
        var pixels = [UInt8](repeating: 0, count: Self.width * Self.height * 4)
        var luma: [Double] = []
        luma.reserveCapacity(frameCount)
        for i in 0..<frameCount {
            try body(i, &pixels)
            luma.append(FlashHarnessSupport.meanRelativeLuminance(pixels))
        }
        return luma
    }

    /// Commit + wait, then read the rendered BGRA back into `pixels`.
    private func commit(_ cmd: MTLCommandBuffer, _ outTex: MTLTexture, into pixels: inout [UInt8]) throws {
        cmd.commit()
        cmd.waitUntilCompleted()
        guard cmd.status == .completed else { throw FlashHarnessError.renderFailed }
        outTex.getBytes(&pixels, bytesPerRow: Self.width * 4,
                        from: MTLRegionMake2D(0, 0, Self.width, Self.height), mipmapLevel: 0)
    }

    private func makeOutputTexture(_ ctx: MetalContext) throws -> MTLTexture {
        let d = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: ctx.pixelFormat, width: Self.width, height: Self.height, mipmapped: false)
        d.usage = [.renderTarget, .shaderRead]
        d.storageMode = .shared
        guard let t = ctx.device.makeTexture(descriptor: d) else {
            throw FlashHarnessError.setupFailed("output texture allocation")
        }
        return t
    }

    private enum FlashHarnessError: Error {
        case presetNotFound(String)
        case setupFailed(String)
        case renderFailed
    }
}
