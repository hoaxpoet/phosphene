// PresetVisualReviewTests — On-demand visual review harness for Phosphene presets.
//
// Renders a named preset at 1920×1280 for three audio fixtures (silence, steady
// mid-energy, beat-heavy), encodes each frame to PNG, and (for Arachne only)
// composes a contact sheet alongside the four must-pass references.
//
// Gated behind RENDER_VISUAL=1 so it stays out of normal CI / `swift test` runs.
//
// Invocation:
//   RENDER_VISUAL=1 swift test --package-path PhospheneEngine \
//       --filter PresetVisualReview
//
// Output: /tmp/phosphene_visual/<ISO8601>/<preset>_{silence,mid,beat}.png
//         /tmp/phosphene_visual/<ISO8601>/<preset>_contact_sheet.png  (Arachne only)
//
// See V.7.6.1 in docs/ENGINEERING_PLAN.md and D-072 in docs/DECISIONS.md.

import Testing
import Metal
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import AppKit
import simd
@testable import Renderer
@testable import Presets
@testable import Shared

// MARK: - Suite

@Suite("PresetVisualReview")
struct PresetVisualReviewTests {

    // MARK: - Fixtures

    private var silenceFixture: FeatureVector {
        FeatureVector(time: 1.0, deltaTime: 1.0 / 60.0)
    }

    private var midFixture: FeatureVector {
        FeatureVector(bass: 0.50, mid: 0.50, treble: 0.50, time: 3.0, deltaTime: 1.0 / 60.0)
    }

    private var beatFixture: FeatureVector {
        var fv = FeatureVector(bass: 0.80, mid: 0.50, treble: 0.50,
                               beatBass: 1.0, time: 5.0, deltaTime: 1.0 / 60.0)
        fv.bassRel = 0.60
        fv.bassDev = 0.60
        return fv
    }

    // MARK: - Constants

    private static let renderWidth = 1920
    private static let renderHeight = 1280
    private static let outputRoot = "/tmp/phosphene_visual"

    private static let arachneReferenceRelPaths: [(label: String, path: String)] = [
        ("Ref 01", "docs/VISUAL_REFERENCES/arachne/01_macro_dewy_web_on_dark.jpg"),
        ("Ref 04", "docs/VISUAL_REFERENCES/arachne/04_specular_silk_fiber_highlight.jpg"),
        ("Ref 05", "docs/VISUAL_REFERENCES/arachne/05_lighting_backlit_atmosphere.jpg"),
        ("Ref 08", "docs/VISUAL_REFERENCES/arachne/08_palette_bioluminescent_organism.jpg"),
    ]

    private static let driftMotesReferenceRelPath: (label: String, path: String) =
        ("Ref 01: dust motes light shaft",
         "docs/VISUAL_REFERENCES/drift_motes/01_atmosphere_dust_motes_light_shaft.jpg")

    // MARK: - Tests

    /// Pass-separated capture for staged-composition presets (V.ENGINE.1).
    /// Renders one PNG per stage per fixture so harness reviewers can inspect
    /// the WORLD pass alone, the COMPOSITE pass, and any intermediate stages.
    /// Setting `RENDER_STAGE=<name>` limits output to a single stage.
    @Test("Render staged preset per-stage PNGs (RENDER_VISUAL=1)",
          arguments: ["Staged Sandbox", "Arachne"])
    func renderStagedPresetPerStage(_ presetName: String) throws {
        guard ProcessInfo.processInfo.environment["RENDER_VISUAL"] == "1" else {
            print("[PresetVisualReview] RENDER_VISUAL not set, skipping staged \(presetName)")
            return
        }
        let stageFilter = ProcessInfo.processInfo.environment["RENDER_STAGE"]

        let ctx = try MetalContext()
        guard let preset = _acceptanceFixture.presets.first(where: {
            $0.descriptor.name == presetName
        }) else {
            print("[PresetVisualReview] preset '\(presetName)' not found, skipping")
            return
        }
        guard !preset.stages.isEmpty else {
            print("[PresetVisualReview] preset '\(presetName)' has no staged compilation, skipping")
            return
        }

        let outputDir = try makeOutputDirectory()
        print("[PresetVisualReview] staged output dir: \(outputDir.path)")

        // Warm an ArachneState so the staged WORLD + COMPOSITE fragments can
        // read mood / web / spider buffers at slots 6 / 7. Other staged
        // presets (e.g. "Staged Sandbox") need no per-preset state.
        let arachneState: ArachneState? = {
            guard presetName == "Arachne" else { return nil }
            guard let state = ArachneState(device: ctx.device, seed: 42) else { return nil }
            let warmFV = FeatureVector(bass: 0.5, mid: 0.5, treble: 0.5,
                                       time: 1.0, deltaTime: 1.0 / 60.0)
            for _ in 0..<30 { state.tick(features: warmFV, stems: .zero) }
            return state
        }()

        let fixtures: [(name: String, fv: FeatureVector)] = [
            ("silence", silenceFixture),
            ("mid", midFixture),
            ("beat", beatFixture),
        ]

        for fixture in fixtures {
            var fv = fixture.fv
            let stagePixels = try renderStagedFrame(preset: preset,
                                                    context: ctx,
                                                    features: &fv,
                                                    arachneState: arachneState)
            for (stageName, pixels) in stagePixels {
                if let stageFilter, stageFilter != stageName { continue }
                let safeName = presetName.replacingOccurrences(of: " ", with: "_")
                let url = outputDir.appendingPathComponent(
                    "\(safeName)_\(fixture.name)_\(stageName).png")
                try writePNG(bgraPixels: pixels,
                             width: Self.renderWidth, height: Self.renderHeight,
                             to: url)
                print("[PresetVisualReview] wrote \(url.lastPathComponent)")
            }
        }
    }

    // Pure-ray-march presets (passes contain `.rayMarch` and NOT `.mvWarp`)
    // dispatch through `renderDeferredRayMarchFrame`, which composes a
    // standalone `RayMarchPipeline` to run G-buffer → lighting → composite.
    // Mv_warp ray-march presets (Volumetric Lithograph) and direct presets
    // (Gossamer, Drift Motes) continue down `renderFrame`. Without this
    // dispatch, pure-ray-march presets would bind a 3-attachment G-buffer
    // pipeline state to a 1-attachment encoder — a Metal format mismatch
    // that produces raw G-buffer output instead of the deferred lit result.
    @Test("Render preset to PNGs + contact sheet (RENDER_VISUAL=1)",
          arguments: ["Arachne", "Gossamer", "Volumetric Lithograph", "Drift Motes", "Lumen Mosaic"])
    func renderPresetVisualReview(_ presetName: String) throws {
        guard ProcessInfo.processInfo.environment["RENDER_VISUAL"] == "1" else {
            print("[PresetVisualReview] RENDER_VISUAL not set, skipping \(presetName)")
            return
        }

        let ctx = try MetalContext()
        guard let preset = _acceptanceFixture.presets.first(where: {
            $0.descriptor.name == presetName
        }) else {
            print("[PresetVisualReview] preset '\(presetName)' not found, skipping")
            return
        }
        guard !preset.descriptor.passes.contains(.meshShader) else {
            print("[PresetVisualReview] '\(presetName)' is mesh-shader, skipping")
            return
        }

        let outputDir = try makeOutputDirectory()
        print("[PresetVisualReview] output dir: \(outputDir.path)")

        // Per-preset state (currently only Arachne needs warmed buffers at 6/7).
        let arachneState: ArachneState? = {
            guard presetName == "Arachne" else { return nil }
            guard let state = ArachneState(device: ctx.device, seed: 42) else { return nil }
            let warmFV = FeatureVector(bass: 0.5, mid: 0.5, treble: 0.5,
                                       time: 1.0, deltaTime: 1.0 / 60.0)
            for _ in 0..<30 { state.tick(features: warmFV, stems: .zero) }
            return state
        }()

        let fixtures: [(name: String, fv: FeatureVector)] = [
            ("silence", silenceFixture),
            ("mid", midFixture),
            ("beat", beatFixture),
        ]

        var midPNGURL: URL?
        for index in 0..<fixtures.count {
            var fv = fixtures[index].fv
            let pixels = try renderFrame(preset: preset, context: ctx,
                                         arachneState: arachneState, features: &fv)
            let url = outputDir.appendingPathComponent(
                "\(presetName.replacingOccurrences(of: " ", with: "_"))_\(fixtures[index].name).png"
            )
            try writePNG(bgraPixels: pixels,
                         width: Self.renderWidth, height: Self.renderHeight,
                         to: url)
            print("[PresetVisualReview] wrote \(url.lastPathComponent)")
            if fixtures[index].name == "mid" { midPNGURL = url }
        }

        // Contact sheet — preset-specific layouts.
        if presetName == "Arachne", let midURL = midPNGURL {
            let sheetURL = outputDir.appendingPathComponent("Arachne_contact_sheet.png")
            try buildArachneContactSheet(renderedMidPNG: midURL, to: sheetURL)
            print("[PresetVisualReview] wrote \(sheetURL.lastPathComponent)")
        }
        if presetName == "Drift Motes", let midURL = midPNGURL {
            let sheetURL = outputDir.appendingPathComponent("Drift_Motes_contact_sheet.png")
            try buildDriftMotesContactSheet(renderedMidPNG: midURL, to: sheetURL)
            print("[PresetVisualReview] wrote \(sheetURL.lastPathComponent)")
        }
    }

    // MARK: - Output directory

    private func makeOutputDirectory() throws -> URL {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withYear, .withMonth, .withDay, .withTime]
        let stamp = formatter.string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let url = URL(fileURLWithPath: Self.outputRoot)
            .appendingPathComponent(stamp)
        try FileManager.default.createDirectory(at: url,
                                                withIntermediateDirectories: true)
        return url
    }

    // MARK: - Render

    private func renderFrame(
        preset: PresetLoader.LoadedPreset,
        context: MetalContext,
        arachneState: ArachneState?,
        features: inout FeatureVector
    ) throws -> [UInt8] {
        // Dispatch: pure-ray-march presets go through the deferred pipeline so
        // the harness captures actual lit output rather than raw G-buffer.
        // Mv_warp ray-march presets stay on the warp path below (their
        // `pipelineState` is the warp pipeline, not the G-buffer state).
        let passes = preset.descriptor.passes
        if passes.contains(.rayMarch) && !passes.contains(.mvWarp) {
            return try renderDeferredRayMarchFrame(preset: preset,
                                                    context: context,
                                                    features: &features)
        }

        let width = Self.renderWidth
        let height = Self.renderHeight

        let texDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: context.pixelFormat,
            width: width, height: height, mipmapped: false)
        texDesc.usage = [.renderTarget, .shaderRead]
        texDesc.storageMode = .shared
        guard let texture = context.device.makeTexture(descriptor: texDesc) else {
            throw VisualReviewError.textureAllocationFailed
        }

        let floatStride = MemoryLayout<Float>.stride
        guard
            let fftBuf = context.makeSharedBuffer(length: 512 * floatStride),
            let wavBuf = context.makeSharedBuffer(length: 2048 * floatStride),
            let stemBuf = context.makeSharedBuffer(length: MemoryLayout<StemFeatures>.size),
            let histBuf = context.makeSharedBuffer(length: 4096 * floatStride)
        else { throw VisualReviewError.bufferAllocationFailed }
        _ = stemBuf.contents().initializeMemory(as: UInt8.self, repeating: 0,
                                                count: MemoryLayout<StemFeatures>.size)
        _ = histBuf.contents().initializeMemory(as: UInt8.self, repeating: 0,
                                                count: 4096 * floatStride)

        var sceneBuf: MTLBuffer?
        if preset.descriptor.passes.contains(.rayMarch),
           let buf = context.makeSharedBuffer(length: MemoryLayout<SceneUniforms>.size) {
            var su = preset.descriptor.makeSceneUniforms()
            buf.contents().copyMemory(from: &su, byteCount: MemoryLayout<SceneUniforms>.size)
            sceneBuf = buf
        }

        guard let cmdBuf = context.commandQueue.makeCommandBuffer() else {
            throw VisualReviewError.commandBufferFailed
        }
        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = texture
        rpd.colorAttachments[0].loadAction = .clear
        rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        rpd.colorAttachments[0].storeAction = .store
        guard let encoder = cmdBuf.makeRenderCommandEncoder(descriptor: rpd) else {
            throw VisualReviewError.encoderCreationFailed
        }

        encoder.setRenderPipelineState(preset.pipelineState)
        encoder.setFragmentBytes(&features, length: MemoryLayout<FeatureVector>.size, index: 0)
        encoder.setFragmentBuffer(fftBuf, offset: 0, index: 1)
        encoder.setFragmentBuffer(wavBuf, offset: 0, index: 2)
        encoder.setFragmentBuffer(stemBuf, offset: 0, index: 3)
        if let sceneBuf = sceneBuf {
            encoder.setFragmentBuffer(sceneBuf, offset: 0, index: 4)
        }
        encoder.setFragmentBuffer(histBuf, offset: 0, index: 5)

        if let arachneState = arachneState {
            encoder.setFragmentBuffer(arachneState.webBuffer, offset: 0, index: 6)
            encoder.setFragmentBuffer(arachneState.spiderBuffer, offset: 0, index: 7)
        }

        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        cmdBuf.commit()
        cmdBuf.waitUntilCompleted()
        guard cmdBuf.status == .completed else { throw VisualReviewError.renderFailed }

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        texture.getBytes(&pixels, bytesPerRow: width * 4,
                         from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        return pixels
    }

    // MARK: - Render (deferred ray-march)

    /// Render a pure-ray-march preset (passes contain `.rayMarch` and NOT
    /// `.mvWarp`) by composing a standalone `RayMarchPipeline` and running the
    /// full G-buffer → lighting → composite sequence. Returns BGRA pixels
    /// matching what the production app would draw, modulo:
    ///
    /// - **No IBL textures bound.** `iblManager` is nil; the lighting fragment's
    ///   IBL samples return zero (the documented unbound-texture behaviour on
    ///   Apple Silicon). matID == 1 emission paths are unaffected (they only
    ///   read IBL for the small ambient floor `irradiance × 0.05 × ao`); matID
    ///   == 0 paths fall back to the `albedo × 0.04 × ao` clamp at
    ///   RayMarch.metal:280. Acceptable for visual review of LM.1 (matID == 1).
    /// - **No noise textures, no SSGI, no bloom, no post-process chain.**
    ///   `RayMarchPipeline.render(...)` runs G-buffer → lighting → ACES
    ///   composite and stops. SSGI / bloom would only matter for matID == 0
    ///   presets that depend on them (Glass Brutalist's cyan glass bleed,
    ///   for example) — out of scope until those land in the @Test args list.
    /// - **Slot 8 (`presetFragmentBuffer3`) unbound.** LM.1 doesn't use it;
    ///   LM.2 will populate `LumenPatternState` and the harness will need to
    ///   construct a representative buffer. For LM.1 the static-backlight
    ///   path is independent of slot 8.
    private func renderDeferredRayMarchFrame(
        preset: PresetLoader.LoadedPreset,
        context: MetalContext,
        features: inout FeatureVector
    ) throws -> [UInt8] {
        let width  = Self.renderWidth
        let height = Self.renderHeight

        guard let gbufferState = preset.rayMarchPipelineState else {
            throw VisualReviewError.preconditionFailed(
                "preset '\(preset.descriptor.name)' missing rayMarchPipelineState")
        }

        let shaderLibrary = try ShaderLibrary(context: context)
        let pipeline = try RayMarchPipeline(context: context,
                                            shaderLibrary: shaderLibrary)
        pipeline.allocateTextures(width: width, height: height)

        // SceneUniforms — same construction as production. Override aspect
        // ratio to match the harness render dimensions; audioTime stays at 0.
        var sceneUniforms = preset.descriptor.makeSceneUniforms()
        sceneUniforms.sceneParamsA.y = Float(width) / Float(height)
        pipeline.sceneUniforms = sceneUniforms

        let floatStride = MemoryLayout<Float>.stride
        guard
            let fftBuf = context.makeSharedBuffer(length: 512 * floatStride),
            let wavBuf = context.makeSharedBuffer(length: 2048 * floatStride)
        else { throw VisualReviewError.bufferAllocationFailed }

        let outDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: context.pixelFormat,
            width: width, height: height, mipmapped: false)
        outDesc.usage = [.renderTarget, .shaderRead]
        outDesc.storageMode = .shared
        guard let outTex = context.device.makeTexture(descriptor: outDesc) else {
            throw VisualReviewError.textureAllocationFailed
        }

        guard let cmdBuf = context.commandQueue.makeCommandBuffer() else {
            throw VisualReviewError.commandBufferFailed
        }

        pipeline.render(
            gbufferPipelineState: gbufferState,
            features: &features,
            fftBuffer: fftBuf,
            waveformBuffer: wavBuf,
            stemFeatures: .zero,
            outputTexture: outTex,
            commandBuffer: cmdBuf,
            noiseTextures: nil,
            iblManager: nil,
            postProcessChain: nil,
            presetFragmentBuffer3: nil
        )

        cmdBuf.commit()
        cmdBuf.waitUntilCompleted()
        guard cmdBuf.status == .completed else { throw VisualReviewError.renderFailed }

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        outTex.getBytes(&pixels, bytesPerRow: width * 4,
                         from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        return pixels
    }

    // MARK: - Render (staged)

    /// Render a staged preset stage-by-stage. Returns BGRA pixel arrays keyed
    /// by stage name so the caller can write one PNG per stage.
    ///
    /// Implementation: stage 0..N-2 are rendered into per-stage `.rgba16Float`
    /// offscreen textures (the same textures stage N samples). For PNG output
    /// each stage is also re-rendered into a parallel BGRA texture so it can
    /// be encoded as 8-bit. Final stage (N-1) renders directly into BGRA.
    private func renderStagedFrame(
        preset: PresetLoader.LoadedPreset,
        context: MetalContext,
        features: inout FeatureVector,
        arachneState: ArachneState? = nil
    ) throws -> [(stage: String, pixels: [UInt8])] {
        let width = Self.renderWidth
        let height = Self.renderHeight

        let floatStride = MemoryLayout<Float>.stride
        guard
            let fftBuf = context.makeSharedBuffer(length: 512 * floatStride),
            let waveBuf = context.makeSharedBuffer(length: 2048 * floatStride),
            let stemBuf = context.makeSharedBuffer(length: MemoryLayout<StemFeatures>.size),
            let histBuf = context.makeSharedBuffer(length: 4096 * floatStride)
        else { throw VisualReviewError.bufferAllocationFailed }
        _ = stemBuf.contents().initializeMemory(as: UInt8.self, repeating: 0,
                                                count: MemoryLayout<StemFeatures>.size)
        _ = histBuf.contents().initializeMemory(as: UInt8.self, repeating: 0,
                                                count: 4096 * floatStride)

        // One offscreen `.rgba16Float` texture per non-final stage (used by
        // later stages that name it in `samples`).
        var offscreen: [String: MTLTexture] = [:]
        for stage in preset.stages where !stage.writesToDrawable {
            let desc = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba16Float,
                width: width, height: height, mipmapped: false)
            desc.usage = [.renderTarget, .shaderRead]
            desc.storageMode = .private
            guard let tex = context.device.makeTexture(descriptor: desc) else {
                throw VisualReviewError.textureAllocationFailed
            }
            offscreen[stage.name] = tex
        }

        // Encode the staged dispatch into a single command buffer.
        guard let cmd = context.commandQueue.makeCommandBuffer() else {
            throw VisualReviewError.commandBufferFailed
        }
        for stage in preset.stages where !stage.writesToDrawable {
            guard let target = offscreen[stage.name] else { continue }
            try encodeStagePass(stage: stage, target: target, commandBuffer: cmd,
                                features: &features,
                                fft: fftBuf, wave: waveBuf, stems: stemBuf, hist: histBuf,
                                samples: offscreen,
                                arachneState: arachneState)
        }
        cmd.commit()
        cmd.waitUntilCompleted()

        // Read each stage back as BGRA pixels for PNG export.
        var result: [(stage: String, pixels: [UInt8])] = []
        // 1) Each non-final stage: re-render into a BGRA shared texture so we can `getBytes`.
        for stage in preset.stages where !stage.writesToDrawable {
            let bgra = try makeShared8BitTexture(device: context.device,
                                                 format: context.pixelFormat,
                                                 width: width, height: height)
            // Build a one-off pipeline that runs the same fragment but writes to BGRA.
            let bgraPipeline = try makeBGRAPipeline(for: stage,
                                                     preset: preset,
                                                     context: context)
            guard let cb = context.commandQueue.makeCommandBuffer() else {
                throw VisualReviewError.commandBufferFailed
            }
            try encodeStagePass(stage: stage,
                                explicitPipeline: bgraPipeline,
                                target: bgra,
                                commandBuffer: cb,
                                features: &features,
                                fft: fftBuf, wave: waveBuf, stems: stemBuf, hist: histBuf,
                                samples: offscreen,
                                arachneState: arachneState)
            cb.commit()
            cb.waitUntilCompleted()
            result.append((stage.name, readBGRA(bgra, width: width, height: height)))
        }
        // 2) Final stage: render directly into a BGRA shared texture.
        if let finalStage = preset.stages.last, finalStage.writesToDrawable {
            let bgra = try makeShared8BitTexture(device: context.device,
                                                 format: context.pixelFormat,
                                                 width: width, height: height)
            guard let cb = context.commandQueue.makeCommandBuffer() else {
                throw VisualReviewError.commandBufferFailed
            }
            try encodeStagePass(stage: finalStage,
                                target: bgra,
                                commandBuffer: cb,
                                features: &features,
                                fft: fftBuf, wave: waveBuf, stems: stemBuf, hist: histBuf,
                                samples: offscreen,
                                arachneState: arachneState)
            cb.commit()
            cb.waitUntilCompleted()
            result.append((finalStage.name, readBGRA(bgra, width: width, height: height)))
        }
        return result
    }

    private func encodeStagePass(
        stage: PresetLoader.LoadedStage,
        explicitPipeline: MTLRenderPipelineState? = nil,
        target: MTLTexture,
        commandBuffer: MTLCommandBuffer,
        features: inout FeatureVector,
        fft: MTLBuffer, wave: MTLBuffer, stems: MTLBuffer, hist: MTLBuffer,
        samples: [String: MTLTexture],
        arachneState: ArachneState? = nil
    ) throws {
        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = target
        rpd.colorAttachments[0].loadAction = .clear
        rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        rpd.colorAttachments[0].storeAction = .store
        guard let enc = commandBuffer.makeRenderCommandEncoder(descriptor: rpd) else {
            throw VisualReviewError.encoderCreationFailed
        }
        enc.setRenderPipelineState(explicitPipeline ?? stage.pipelineState)
        enc.setFragmentBytes(&features, length: MemoryLayout<FeatureVector>.size, index: 0)
        enc.setFragmentBuffer(fft, offset: 0, index: 1)
        enc.setFragmentBuffer(wave, offset: 0, index: 2)
        enc.setFragmentBuffer(stems, offset: 0, index: 3)
        enc.setFragmentBuffer(hist, offset: 0, index: 5)
        // Per-preset fragment buffers — mirrors RenderPipeline+Staged.encodeStage
        // (slot 6 = ArachneWebGPU pool, slot 7 = ArachneSpiderGPU). Required for
        // V.7.7B's staged Arachne fragments to read mood / web / spider state.
        if let arachneState = arachneState {
            enc.setFragmentBuffer(arachneState.webBuffer, offset: 0, index: 6)
            enc.setFragmentBuffer(arachneState.spiderBuffer, offset: 0, index: 7)
        }
        for (offset, name) in stage.samples.enumerated() {
            guard let tex = samples[name] else { continue }
            enc.setFragmentTexture(tex, index: kStagedSampledTextureFirstSlot + offset)
        }
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
    }

    /// Build a BGRA-target pipeline for an intermediate stage so the harness
    /// can write its output to PNG. Recompiles the preset shader file once
    /// per call; only used for `RENDER_VISUAL=1` runs.
    private func makeBGRAPipeline(
        for stage: PresetLoader.LoadedStage,
        preset: PresetLoader.LoadedPreset,
        context: MetalContext
    ) throws -> MTLRenderPipelineState {
        // BUG-002: `Bundle.module` here resolves the *test* target's bundle, which
        // has no `Shaders` resource — the harness was silently failing the staged
        // preset PNG export. `PresetLoader.bundledShadersURL` reaches the same
        // Presets-module resource bundle the loader uses internally.
        guard let bundleShaders = PresetLoader.bundledShadersURL else {
            throw VisualReviewError.cgImageFailed
        }
        let metalURL = bundleShaders.appendingPathComponent(
            preset.descriptor.shaderFileName)
        let source = try String(contentsOf: metalURL, encoding: .utf8)
        let fullSource = PresetLoader.shaderPreamble + "\n\n" + source
        let options = MTLCompileOptions()
        options.fastMathEnabled = true
        options.languageVersion = .version3_1
        let library = try context.device.makeLibrary(source: fullSource, options: options)

        guard let descStage = preset.descriptor.stages.first(where: { $0.name == stage.name }),
              let vertexFn = library.makeFunction(name: preset.descriptor.vertexFunction),
              let fragmentFn = library.makeFunction(name: descStage.fragmentFunction) else {
            throw VisualReviewError.cgImageFailed
        }
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vertexFn
        desc.fragmentFunction = fragmentFn
        desc.colorAttachments[0].pixelFormat = context.pixelFormat
        return try context.device.makeRenderPipelineState(descriptor: desc)
    }

    private func makeShared8BitTexture(
        device: MTLDevice,
        format: MTLPixelFormat,
        width: Int, height: Int
    ) throws -> MTLTexture {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: format, width: width, height: height, mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .shared
        guard let tex = device.makeTexture(descriptor: desc) else {
            throw VisualReviewError.textureAllocationFailed
        }
        return tex
    }

    private func readBGRA(_ texture: MTLTexture, width: Int, height: Int) -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        texture.getBytes(&pixels, bytesPerRow: width * 4,
                         from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        return pixels
    }

    // MARK: - PNG encoding

    private func writePNG(bgraPixels: [UInt8],
                          width: Int, height: Int,
                          to url: URL) throws {
        guard let cgImage = makeCGImage(bgraPixels: bgraPixels,
                                        width: width, height: height) else {
            throw VisualReviewError.cgImageFailed
        }
        try writeCGImage(cgImage, to: url)
    }

    private func makeCGImage(bgraPixels: [UInt8],
                             width: Int, height: Int) -> CGImage? {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let bitmapInfo = CGBitmapInfo(rawValue:
            CGImageAlphaInfo.premultipliedFirst.rawValue
            | CGBitmapInfo.byteOrder32Little.rawValue)
        var copy = bgraPixels
        return copy.withUnsafeMutableBytes { (ptr: UnsafeMutableRawBufferPointer) -> CGImage? in
            guard let base = ptr.baseAddress else { return nil }
            guard let ctx = CGContext(data: base,
                                      width: width, height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: width * 4,
                                      space: colorSpace,
                                      bitmapInfo: bitmapInfo.rawValue) else { return nil }
            return ctx.makeImage()
        }
    }

    private func writeCGImage(_ image: CGImage, to url: URL) throws {
        let type: CFString
        if #available(macOS 11.0, *) { type = UTType.png.identifier as CFString }
        else { type = "public.png" as CFString }
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, type, 1, nil) else {
            throw VisualReviewError.pngWriteFailed
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else {
            throw VisualReviewError.pngWriteFailed
        }
    }

    // MARK: - Contact sheet (Arachne only)

    private func buildArachneContactSheet(renderedMidPNG: URL, to outURL: URL) throws {
        let sheetW = Self.renderWidth
        let sheetH = Self.renderHeight
        let topHalfH = sheetH / 2
        let cellW = sheetW / 4
        let cellH = sheetH / 2

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            throw VisualReviewError.cgImageFailed
        }
        let bitmapInfo = CGBitmapInfo(rawValue:
            CGImageAlphaInfo.premultipliedFirst.rawValue
            | CGBitmapInfo.byteOrder32Little.rawValue)
        guard let ctx = CGContext(data: nil,
                                  width: sheetW, height: sheetH,
                                  bitsPerComponent: 8,
                                  bytesPerRow: sheetW * 4,
                                  space: colorSpace,
                                  bitmapInfo: bitmapInfo.rawValue) else {
            throw VisualReviewError.cgImageFailed
        }

        // Black background.
        ctx.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: sheetW, height: sheetH))

        // Top half: rendered output letterboxed to fit (1920×640).
        if let renderedImage = loadCGImage(from: renderedMidPNG) {
            let topRect = CGRect(x: 0, y: cellH, width: sheetW, height: topHalfH)
            drawLetterboxed(image: renderedImage, in: topRect, ctx: ctx)
        }

        // Bottom half: 4 references each in a 480×640 cell.
        let projectRoot = projectRootURL()
        for (index, ref) in Self.arachneReferenceRelPaths.enumerated() {
            let url = projectRoot.appendingPathComponent(ref.path)
            let rect = CGRect(x: index * cellW, y: 0,
                              width: cellW, height: cellH)
            if let img = loadCGImage(from: url) {
                drawLetterboxed(image: img, in: rect, ctx: ctx)
            }
        }

        // Labels — render via NSGraphicsContext bridging to CGContext.
        let nsContext = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsContext

        let labels: [(text: String, originX: Int, originY: Int)] = [
            ("Render: steady-mid", 12, sheetH - 24),
        ] + Self.arachneReferenceRelPaths.enumerated().map { index, ref in
            (ref.label, index * cellW + 12, cellH - 24)
        }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14),
            .foregroundColor: NSColor.white,
            .backgroundColor: NSColor(red: 0, green: 0, blue: 0, alpha: 0.7),
        ]
        for label in labels {
            let attributed = NSAttributedString(string: " \(label.text) ", attributes: attrs)
            attributed.draw(at: NSPoint(x: label.originX, y: label.originY))
        }
        NSGraphicsContext.restoreGraphicsState()

        guard let cgImage = ctx.makeImage() else {
            throw VisualReviewError.cgImageFailed
        }
        try writeCGImage(cgImage, to: outURL)
    }

    // MARK: - Contact sheet (Drift Motes)

    /// Top half = rendered output (steady-mid fixture); bottom half =
    /// `01_atmosphere_dust_motes_light_shaft.jpg` reference. Single-reference
    /// stacked layout — Drift Motes' reference set is one image (DM.0 spec).
    private func buildDriftMotesContactSheet(renderedMidPNG: URL, to outURL: URL) throws {
        let sheetW = Self.renderWidth
        let sheetH = Self.renderHeight
        let halfH = sheetH / 2

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            throw VisualReviewError.cgImageFailed
        }
        let bitmapInfo = CGBitmapInfo(rawValue:
            CGImageAlphaInfo.premultipliedFirst.rawValue
            | CGBitmapInfo.byteOrder32Little.rawValue)
        guard let ctx = CGContext(data: nil,
                                  width: sheetW, height: sheetH,
                                  bitsPerComponent: 8,
                                  bytesPerRow: sheetW * 4,
                                  space: colorSpace,
                                  bitmapInfo: bitmapInfo.rawValue) else {
            throw VisualReviewError.cgImageFailed
        }

        ctx.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: sheetW, height: sheetH))

        // Top half: rendered output.
        if let renderedImage = loadCGImage(from: renderedMidPNG) {
            let topRect = CGRect(x: 0, y: halfH, width: sheetW, height: halfH)
            drawLetterboxed(image: renderedImage, in: topRect, ctx: ctx)
        }

        // Bottom half: single reference image, full-width letterboxed.
        let projectRoot = projectRootURL()
        let refURL = projectRoot.appendingPathComponent(
            Self.driftMotesReferenceRelPath.path)
        if let refImage = loadCGImage(from: refURL) {
            let botRect = CGRect(x: 0, y: 0, width: sheetW, height: halfH)
            drawLetterboxed(image: refImage, in: botRect, ctx: ctx)
        }

        let nsContext = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsContext

        let labels: [(text: String, originX: Int, originY: Int)] = [
            ("Render: steady-mid (DM.3 — emission-rate scaling + dispersion shock)",
             12, sheetH - 24),
            (Self.driftMotesReferenceRelPath.label, 12, halfH - 24),
        ]
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14),
            .foregroundColor: NSColor.white,
            .backgroundColor: NSColor(red: 0, green: 0, blue: 0, alpha: 0.7),
        ]
        for label in labels {
            let attributed = NSAttributedString(string: " \(label.text) ", attributes: attrs)
            attributed.draw(at: NSPoint(x: label.originX, y: label.originY))
        }
        NSGraphicsContext.restoreGraphicsState()

        guard let cgImage = ctx.makeImage() else {
            throw VisualReviewError.cgImageFailed
        }
        try writeCGImage(cgImage, to: outURL)
    }

    private func loadCGImage(from url: URL) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }

    /// Draw `image` into `rect` preserving aspect ratio (letterboxed in black).
    private func drawLetterboxed(image: CGImage, in rect: CGRect, ctx: CGContext) {
        let srcW = CGFloat(image.width)
        let srcH = CGFloat(image.height)
        let scale = min(rect.width / srcW, rect.height / srcH)
        let drawW = srcW * scale
        let drawH = srcH * scale
        let drawX = rect.origin.x + (rect.width - drawW) / 2
        let drawY = rect.origin.y + (rect.height - drawH) / 2
        ctx.draw(image, in: CGRect(x: drawX, y: drawY,
                                   width: drawW, height: drawH))
    }

    /// Walk up from `#filePath` to the project root (4 levels:
    /// PhospheneEngine/Tests/PhospheneEngineTests/Renderer/<file> → repo root).
    private func projectRootURL(file: String = #filePath) -> URL {
        var url = URL(fileURLWithPath: file)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return url
    }
}

// MARK: - Errors

private enum VisualReviewError: Error {
    case textureAllocationFailed
    case bufferAllocationFailed
    case commandBufferFailed
    case encoderCreationFailed
    case renderFailed
    case cgImageFailed
    case pngWriteFailed
    case preconditionFailed(String)
}
