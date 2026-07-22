// MultiPassRenderHarness — the shared headless render of every certified preset's REAL
// multi-pass / feedback / follower path, driven by an INJECTED per-frame train and a
// generic per-frame pixel reducer.
//
// Extracted from MultiPassFlashHarnessTests (CLEAN.7.6c) at QG.3.1 so two consumers share
// ONE faithful render (FA #66 — drive the live paths, never reimplement):
//   - the photosensitivity flash gate drives a synthetic worst-case beat train and reduces
//     each frame to WCAG relative luminance (flash-rate analysis);
//   - the QG.3 coupling report drives the REAL reconstructed-fixture train (FA #27) and
//     reduces each frame to a luma field (frame-to-frame visual delta vs. energy).
//
// The render bodies are byte-identical to the pre-extraction flash harness — the mv_warp
// feedback swap, the rayMarch 128-step budget, the ticked followers, the settle windows.
// A change here changes BOTH gates; keep the live-path fidelity notes intact.

import Testing
import Metal
@testable import Renderer
@testable import Presets
@testable import Shared

// MARK: - MultiPassRenderHarness

@MainActor
struct MultiPassRenderHarness {

    /// 16:9. 320×180 keeps aspect-driven placement faithful and is small enough for the
    /// multi-preset sweeps. Mean/field luma is scale-invariant for the signals measured.
    let width: Int
    let height: Int

    init(width: Int = 320, height: Int = 180) {
        self.width = width
        self.height = height
    }

    /// The certified presets this harness renders through their real multi-pass path.
    /// (The three single-pass presets — Ferrofluid Ocean, Murmuration, Nimbus — read their
    /// response through one fragment + optional follower and are rendered by the single-pass
    /// harness; see PhotosensitivityCertificationTests / CouplingReportTests.)
    static let multiPassPresets = [
        "Lumen Mosaic", "Dragon Bloom", "Fata Morgana", "Skein", "Nacre",
        "Floret", "Glaze", "Filigree", "Mitosis", "Cytokinesis", "Cymatic Resonance"
    ]

    /// Render `presetName` over `features`/`stems` (row-aligned), returning `reduce(bgra)`
    /// for each measured frame. Dispatches to the preset's real render path. `settle`
    /// warm frames run first without capture (particle grow-in); default 0.
    func render<T>(
        preset presetName: String,
        features: [FeatureVector],
        stems: [StemFeatures],
        settle: Int = 0,
        reduce: (_ bgra: [UInt8]) -> T
    ) throws -> [T] {
        switch presetName {
        case "Filigree":     return try renderFiligree(features, stems, settle: settle, reduce)
        case "Cymatic Resonance": return try renderCymaticSand(features, stems, settle: settle, reduce)
        case "Mitosis":      return try renderMitosis(features, stems, reduce)
        case "Cytokinesis":  return try renderCytokinesis(features, stems, reduce)
        case "Lumen Mosaic": return try renderLumenMosaic(features, stems, reduce)
        case "Fata Morgana": return try renderBespokeMVWarp("Fata Morgana", features, stems, reduce)
        case "Nacre":        return try renderBespokeMVWarp("Nacre", features, stems, reduce)
        case "Floret":       return try renderBespokeMVWarp("Floret", features, stems, reduce)
        case "Glaze":        return try renderBespokeMVWarp("Glaze", features, stems, reduce)
        case "Dragon Bloom", "Skein": return try renderMVWarp(presetName, features, stems, reduce)
        default:
            throw HarnessError.presetNotFound("\(presetName) is not a multi-pass harness preset")
        }
    }

    // MARK: - Render: particle (Filigree — settles the trail first)

    private func renderFiligree<T>(_ drive: [FeatureVector], _ stems: [StemFeatures],
                                   settle: Int, _ reduce: (_ bgra: [UInt8]) -> T) throws -> [T] {
        let ctx = try MetalContext()
        let lib = try ShaderLibrary(context: ctx)
        let geo = try PhysarumGeometry(device: ctx.device, library: lib.library,
                                       configuration: PhysarumConfiguration(), pixelFormat: ctx.pixelFormat)
        let tex = try makeOutputTexture(ctx)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        // Settle the web first so we measure the steady response, not the initial grow-in.
        for i in 0..<settle {
            guard let cmd = ctx.commandQueue.makeCommandBuffer() else { continue }
            geo.update(features: drive[i % drive.count], stemFeatures: stems[i % stems.count], commandBuffer: cmd)
            cmd.commit(); cmd.waitUntilCompleted()
        }
        var out: [T] = []
        out.reserveCapacity(drive.count)
        for i in 0..<drive.count {
            guard let cmd = ctx.commandQueue.makeCommandBuffer() else { continue }
            geo.update(features: drive[i], stemFeatures: stems[i], commandBuffer: cmd)
            let rpd = clearRPD(tex)
            guard let enc = cmd.makeRenderCommandEncoder(descriptor: rpd) else { continue }
            geo.render(encoder: enc, features: drive[i])
            enc.endEncoding()
            try commit(cmd, tex, into: &pixels)
            out.append(reduce(pixels))
        }
        return out
    }

    // MARK: - Render: particle (Cymatic Resonance — vibrating-sand Chladni sim)

    private func renderCymaticSand<T>(_ drive: [FeatureVector], _ stems: [StemFeatures],
                                      settle: Int, _ reduce: (_ bgra: [UInt8]) -> T) throws -> [T] {
        let ctx = try MetalContext()
        let lib = try ShaderLibrary(context: ctx)
        let geo = try CymaticSandGeometry(device: ctx.device, library: lib.library,
                                          configuration: CymaticSandConfiguration(), pixelFormat: ctx.pixelFormat)
        // The display cover-fit divides by aspectRatio — set it to the output aspect so
        // the sand fills the frame (an unset 0 would crop everything to black = static).
        let aspect = Float(width) / Float(height)
        func withAspect(_ i: Int) -> FeatureVector { var f = drive[i]; f.aspectRatio = aspect; return f }
        let tex = try makeOutputTexture(ctx)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for i in 0..<settle {   // settle so the sand forms the figure before we measure
            guard let cmd = ctx.commandQueue.makeCommandBuffer() else { continue }
            geo.update(features: withAspect(i % drive.count), stemFeatures: stems[i % stems.count], commandBuffer: cmd)
            cmd.commit(); cmd.waitUntilCompleted()
        }
        var out: [T] = []
        out.reserveCapacity(drive.count)
        for i in 0..<drive.count {
            guard let cmd = ctx.commandQueue.makeCommandBuffer() else { continue }
            let f = withAspect(i)
            geo.update(features: f, stemFeatures: stems[i], commandBuffer: cmd)
            let rpd = clearRPD(tex)
            guard let enc = cmd.makeRenderCommandEncoder(descriptor: rpd) else { continue }
            geo.render(encoder: enc, features: f)
            enc.endEncoding()
            try commit(cmd, tex, into: &pixels)
            out.append(reduce(pixels))
        }
        return out
    }

    // MARK: - Render: particle (Mitosis / Cytokinesis — geometry-driven RD / cell colony)

    private func renderMitosis<T>(_ drive: [FeatureVector], _ stems: [StemFeatures],
                                  _ reduce: (_ bgra: [UInt8]) -> T) throws -> [T] {
        let ctx = try MetalContext()
        let lib = try ShaderLibrary(context: ctx)
        let geo = try MitosisGeometry(device: ctx.device, library: lib.library,
                                      configuration: MitosisConfiguration(), pixelFormat: ctx.pixelFormat)
        return try particleLoop(ctx, drive, stems, reduce) { i, enc in geo.render(encoder: enc, features: drive[i]) }
            update: { i, cmd in geo.update(features: drive[i], stemFeatures: stems[i], commandBuffer: cmd) }
    }

    private func renderCytokinesis<T>(_ drive: [FeatureVector], _ stems: [StemFeatures],
                                      _ reduce: (_ bgra: [UInt8]) -> T) throws -> [T] {
        let ctx = try MetalContext()
        let lib = try ShaderLibrary(context: ctx)
        let geo = try MitosisGen2Geometry(device: ctx.device, library: lib.library,
                                          configuration: MitosisGen2Configuration(), pixelFormat: ctx.pixelFormat)
        return try particleLoop(ctx, drive, stems, reduce) { i, enc in geo.render(encoder: enc, features: drive[i]) }
            update: { i, cmd in geo.update(features: drive[i], stemFeatures: stems[i], commandBuffer: cmd) }
    }

    /// Shared update→render→reduce loop for the geometry-driven particle presets.
    private func particleLoop<T>(
        _ ctx: MetalContext, _ drive: [FeatureVector], _ stems: [StemFeatures],
        _ reduce: (_ bgra: [UInt8]) -> T,
        render: (_ i: Int, _ enc: MTLRenderCommandEncoder) -> Void,
        update: (_ i: Int, _ cmd: MTLCommandBuffer) -> Void
    ) throws -> [T] {
        let tex = try makeOutputTexture(ctx)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        var out: [T] = []
        out.reserveCapacity(drive.count)
        for i in 0..<drive.count {
            guard let cmd = ctx.commandQueue.makeCommandBuffer() else { continue }
            update(i, cmd)
            let rpd = clearRPD(tex)
            guard let enc = cmd.makeRenderCommandEncoder(descriptor: rpd) else { continue }
            render(i, enc)
            enc.endEncoding()
            try commit(cmd, tex, into: &pixels)
            out.append(reduce(pixels))
        }
        return out
    }

    // MARK: - Render: ray-march + follower (Lumen Mosaic)

    private func renderLumenMosaic<T>(_ drive: [FeatureVector], _ stems: [StemFeatures],
                                      _ reduce: (_ bgra: [UInt8]) -> T) throws -> [T] {
        let ctx = try MetalContext()
        let lib = try ShaderLibrary(context: ctx)
        guard let preset = _acceptanceFixture.presets.first(where: { $0.descriptor.name == "Lumen Mosaic" }) else {
            throw HarnessError.presetNotFound("Lumen Mosaic")
        }
        guard let gbufferState = preset.rayMarchPipelineState else {
            throw HarnessError.setupFailed("Lumen Mosaic rayMarchPipelineState missing")
        }
        let pipeline = try RayMarchPipeline(context: ctx, shaderLibrary: lib)
        pipeline.allocateTextures(width: width, height: height)
        var scene = preset.descriptor.makeSceneUniforms()          // sceneParamsB.z default 1.0 ⇒ 128 steps
        scene.sceneParamsA.y = Float(width) / Float(height)
        pipeline.sceneUniforms = scene
        pipeline.ssgiEnabled = preset.descriptor.passes.contains(.ssgi)

        let ibl = try IBLManager(context: ctx, shaderLibrary: lib)
        let noise = try? TextureManager(context: ctx, shaderLibrary: lib)
        let postChain: PostProcessChain?
        if preset.descriptor.passes.contains(.postProcess) {
            let chain = try PostProcessChain(context: ctx, shaderLibrary: lib)
            chain.allocateTextures(width: width, height: height)
            postChain = chain
        } else {
            postChain = nil
        }
        guard let engine = LumenPatternEngine(device: ctx.device) else {
            throw HarnessError.setupFailed("LumenPatternEngine allocation")
        }
        engine.setPalette(LumenMosaicPaletteLibrary.all[0])        // a real (non-black) palette — else BUG-016 static

        let floatStride = MemoryLayout<Float>.stride
        guard let fft = ctx.makeSharedBuffer(length: 512 * floatStride),
              let wav = ctx.makeSharedBuffer(length: 2048 * floatStride) else {
            throw HarnessError.setupFailed("audio buffers")
        }
        let outTex = try makeOutputTexture(ctx)
        return try renderLoop(drive, ctx, outTex, reduce) { i, pixels in
            var fv = drive[i]
            let stem = stems[i]
            engine.tick(features: fv, stems: stem)                 // advance the 4-light beat-locked dance
            guard let cmd = ctx.commandQueue.makeCommandBuffer() else { throw HarnessError.renderFailed }
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

    private func renderMVWarp<T>(_ presetName: String, _ drive: [FeatureVector], _ stems: [StemFeatures],
                                 _ reduce: (_ bgra: [UInt8]) -> T) throws -> [T] {
        let ctx = try MetalContext()
        let lib = try ShaderLibrary(context: ctx)
        let noise = try TextureManager(context: ctx, shaderLibrary: lib)
        let floatStride = MemoryLayout<Float>.stride
        guard let fft = ctx.makeSharedBuffer(length: 512 * floatStride),
              let wav = ctx.makeSharedBuffer(length: 2048 * floatStride) else {
            throw HarnessError.setupFailed("audio buffers")
        }
        let pipeline = try RenderPipeline(context: ctx, shaderLibrary: lib, fftBuffer: fft, waveformBuffer: wav)
        pipeline.setTextureManager(noise)
        guard let preset = _acceptanceFixture.presets.first(where: { $0.descriptor.name == presetName }) else {
            throw HarnessError.presetNotFound(presetName)
        }
        let size = CGSize(width: width, height: height)
        pipeline.currentDrawableSize = size
        try configureMVWarp(pipeline: pipeline, preset: preset, context: ctx, size: size)

        let skein: SkeinState?
        if presetName == "Skein" {
            guard let state = SkeinState(device: ctx.device, seed: 42) else {
                throw HarnessError.setupFailed("SkeinState allocation")
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
        return try renderLoop(drive, ctx, outTex, reduce) { i, pixels in
            var fv = drive[i]
            let stem = stems[i]
            if let skein {
                skein.tick(deltaTime: fv.deltaTime, features: fv, stems: stem)
                pipeline.setMVWarpWetnessDecay(skein.wetnessDecay)
            }
            guard let cmd = ctx.commandQueue.makeCommandBuffer(),
                  let warpState = pipeline.mvWarpState else { throw HarnessError.renderFailed }
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

    // MARK: - Render: bespoke mv_warp (Fata Morgana / Nacre / Floret / Glaze)

    private func renderBespokeMVWarp<T>(_ presetName: String, _ drive: [FeatureVector], _ stems: [StemFeatures],
                                        _ reduce: (_ bgra: [UInt8]) -> T) throws -> [T] {
        let ctx = try MetalContext()
        let lib = try ShaderLibrary(context: ctx)
        let noise = try TextureManager(context: ctx, shaderLibrary: lib)
        let floatStride = MemoryLayout<Float>.stride
        guard let fft = ctx.makeSharedBuffer(length: 512 * floatStride),
              let wav = ctx.makeSharedBuffer(length: 2048 * floatStride) else {
            throw HarnessError.setupFailed("audio buffers")
        }
        let pipeline = try RenderPipeline(context: ctx, shaderLibrary: lib, fftBuffer: fft, waveformBuffer: wav)
        pipeline.setTextureManager(noise)
        guard let preset = _acceptanceFixture.presets.first(where: { $0.descriptor.name == presetName }) else {
            throw HarnessError.presetNotFound(presetName)
        }
        let size = CGSize(width: width, height: height)
        pipeline.currentDrawableSize = size

        if presetName == "Glaze" {
            guard let mvWarp = preset.mvWarpPipelines else { throw HarnessError.presetNotFound("Glaze") }
            let bundle = MVWarpPipelineBundle(
                warpState: mvWarp.warpState, composeState: mvWarp.composeState, blitState: mvWarp.blitState,
                pixelFormat: ctx.pixelFormat, feedbackFormat: .rgba16Float,
                blurState: mvWarp.blurState, isGlaze: true)
            pipeline.setupMVWarp(bundle: bundle, size: size)
            pipeline.setMVWarpDecay(preset.descriptor.decay)
        } else {
            try configureMVWarp(pipeline: pipeline, preset: preset, context: ctx, size: size)
            if presetName == "Fata Morgana" { pipeline.fataGlowSeedJitter = 0 }   // deterministic
        }

        let outTex = try makeOutputTexture(ctx)
        return try renderLoop(drive, ctx, outTex, reduce) { i, pixels in
            guard let cmd = ctx.commandQueue.makeCommandBuffer(),
                  let warpState = pipeline.mvWarpState else { throw HarnessError.renderFailed }
            switch presetName {
            case "Fata Morgana":
                pipeline.renderFataMorgana(commandBuffer: cmd, features: drive[i], stemFeatures: stems[i],
                                           warpState: warpState, target: outTex)
            case "Nacre":
                pipeline.renderNacre(commandBuffer: cmd, features: drive[i], stemFeatures: stems[i],
                                     warpState: warpState, target: outTex)
            case "Floret":
                pipeline.renderFloret(commandBuffer: cmd, features: drive[i], stemFeatures: stems[i],
                                      warpState: warpState, target: outTex)
            case "Glaze":
                pipeline.renderGlaze(commandBuffer: cmd, features: drive[i], stemFeatures: stems[i],
                                     warpState: warpState, target: outTex)
            default:
                throw HarnessError.presetNotFound(presetName)
            }
            try commit(cmd, outTex, into: &pixels)
        }
    }

    // MARK: - mv_warp setup (mirrors VisualizerEngine+Presets applyPreset, MV-2)

    private func configureMVWarp(
        pipeline: RenderPipeline, preset: PresetLoader.LoadedPreset,
        context ctx: MetalContext, size: CGSize
    ) throws {
        let desc = preset.descriptor
        guard let warp = preset.mvWarpPipelines else {
            throw HarnessError.setupFailed("\(desc.name) mvWarpPipelines missing")
        }
        let feedbackFormat: MTLPixelFormat
        switch desc.name {
        case "Fata Morgana": feedbackFormat = .bgra8Unorm
        case "Nacre":        feedbackFormat = .rgba16Float
        case "Floret":       feedbackFormat = .rgba16Float
        default:             feedbackFormat = ctx.pixelFormat
        }
        let canvasClear = desc.marks?.canvasClear.map {
            SIMD4<Double>(Double($0.x), Double($0.y), Double($0.z), 1)
        } ?? SIMD4<Double>(0, 0, 0, 1)
        let bundle = MVWarpPipelineBundle(
            warpState: warp.warpState,
            composeState: warp.composeState,
            blitState: warp.blitState,
            pixelFormat: ctx.pixelFormat,
            feedbackFormat: feedbackFormat,
            blurState: warp.blurState,
            isNacre: desc.name == "Nacre",
            isFloret: desc.name == "Floret",
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
                invert: marks.comp.invert, echo: marks.comp.echo,
                gamma: marks.comp.gamma, beatPulse: marks.beatPulse)
        } else {
            pipeline.setSceneGeometry(nil, vertexCount: 0, instanceCount: 0, primitive: .lineStrip)
            pipeline.setMVWarpChromatic(0)
            pipeline.setMVWarpPost(invert: 0, echo: 0, gamma: 1)
        }
        pipeline.setFataShapePipelines(additive: warp.shapeAdditiveState, normal: warp.shapeNormalState)
    }

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

    private func renderLoop<T>(
        _ drive: [FeatureVector], _ ctx: MetalContext, _ outTex: MTLTexture,
        _ reduce: (_ bgra: [UInt8]) -> T,
        _ body: (_ frame: Int, _ pixels: inout [UInt8]) throws -> Void
    ) throws -> [T] {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        var out: [T] = []
        out.reserveCapacity(drive.count)
        for i in 0..<drive.count {
            try body(i, &pixels)
            out.append(reduce(pixels))
        }
        return out
    }

    private func clearRPD(_ tex: MTLTexture) -> MTLRenderPassDescriptor {
        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = tex
        rpd.colorAttachments[0].loadAction = .clear
        rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        rpd.colorAttachments[0].storeAction = .store
        return rpd
    }

    private func commit(_ cmd: MTLCommandBuffer, _ outTex: MTLTexture, into pixels: inout [UInt8]) throws {
        cmd.commit()
        cmd.waitUntilCompleted()
        guard cmd.status == .completed else { throw HarnessError.renderFailed }
        outTex.getBytes(&pixels, bytesPerRow: width * 4,
                        from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
    }

    private func makeOutputTexture(_ ctx: MetalContext) throws -> MTLTexture {
        let d = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: ctx.pixelFormat, width: width, height: height, mipmapped: false)
        d.usage = [.renderTarget, .shaderRead]
        d.storageMode = .shared
        guard let t = ctx.device.makeTexture(descriptor: d) else {
            throw HarnessError.setupFailed("output texture allocation")
        }
        return t
    }

    enum HarnessError: Error {
        case presetNotFound(String)
        case setupFailed(String)
        case renderFailed
    }
}
