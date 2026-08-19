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
        "Floret", "Glaze", "Filigree", "Mitosis", "Cytokinesis", "Cymatic Resonance",
        "Volumetric Lithograph", "Witchlight", "Meniscus", "Stave",
        // PERF.7 — the first MESH-SHADER preset the harness can drive (object → mesh →
        // fragment). Everything above is fragment-stage work; this one emits geometry, so its
        // cost scales with branch count rather than pixel count, which is exactly why it needs
        // its own row rather than an assumption.
        "Fractal Tree",
        // PERF.8 — the four `direct` presets: one fullscreen fragment each, no per-preset Swift
        // state, so one generic path covers all of them. PERF.7's survey named these as the
        // cheapest remaining paradigm and this is that work.
        "Nebula", "Plasma", "Spectral Cartograph", "Waveform"
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
        case "Witchlight":   return try renderWitchlight(features, stems, settle: settle, reduce)
        case "Meniscus":     return try renderMeniscus(features, stems, settle: settle, reduce)
        case "Stave":        return try renderStave(features, stems, settle: settle, reduce)
        case "Mitosis":      return try renderMitosis(features, stems, reduce)
        case "Cytokinesis":  return try renderCytokinesis(features, stems, reduce)
        case "Lumen Mosaic": return try renderLumenMosaic(features, stems, reduce)
        case "Volumetric Lithograph": return try renderVolumetricLithograph(features, stems, reduce)
        case "Fata Morgana": return try renderBespokeMVWarp("Fata Morgana", features, stems, reduce)
        case "Nacre":        return try renderBespokeMVWarp("Nacre", features, stems, reduce)
        case "Floret":       return try renderBespokeMVWarp("Floret", features, stems, reduce)
        case "Glaze":        return try renderBespokeMVWarp("Glaze", features, stems, reduce)
        case "Dragon Bloom", "Skein": return try renderMVWarp(presetName, features, stems, reduce)
        case "Fractal Tree": return try renderMeshPreset(presetName, features, stems,
                                                         settle: settle, reduce)
        case "Nebula", "Plasma", "Spectral Cartograph", "Waveform":
            return try renderDirectPreset(presetName, features, stems, reduce)
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

    // MARK: - Render: particle (Witchlight — harmonic stroke over its own sky)

    /// Witchlight is the only particle preset here whose BACKDROP is audio-driven too (star
    /// parallax + bloom hue), so the flash measure has to include it: measuring the ribbon
    /// against a black clear would under-report the frame's mean luminance and hand the
    /// safety gate an easier signal than the one that ships. This mirrors
    /// `RenderPipeline.drawParticleMode` — preset triangle first, then the four ribbon draws.
    private func renderWitchlight<T>(_ drive: [FeatureVector], _ stems: [StemFeatures],
                                     settle: Int, _ reduce: (_ bgra: [UInt8]) -> T) throws -> [T] {
        let ctx = try MetalContext()
        let lib = try ShaderLibrary(context: ctx)
        guard let preset = _acceptanceFixture.presets.first(where: { $0.descriptor.name == "Witchlight" }) else {
            throw HarnessError.presetNotFound("Witchlight")
        }
        let geo = try WitchlightStroke(device: ctx.device, library: lib.library,
                                       configuration: WitchlightConfiguration(), pixelFormat: ctx.pixelFormat)
        let floatStride = MemoryLayout<Float>.stride
        guard let fft = ctx.makeSharedBuffer(length: 512 * floatStride),
              let wav = ctx.makeSharedBuffer(length: 2048 * floatStride) else {
            throw HarnessError.setupFailed("audio buffers")
        }
        let aspect = Float(width) / Float(height)
        func withAspect(_ i: Int) -> FeatureVector { var f = drive[i]; f.aspectRatio = aspect; return f }

        let tex = try makeOutputTexture(ctx)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        // Grow the trail in before measuring: the flash question is about the STEADY ribbon
        // plus its head flare, not about the first few beads appearing on an empty field.
        for i in 0..<settle {
            guard let cmd = ctx.commandQueue.makeCommandBuffer() else { continue }
            geo.update(features: withAspect(i % drive.count), stemFeatures: stems[i % stems.count],
                       commandBuffer: cmd)
            cmd.commit(); cmd.waitUntilCompleted()
        }
        var out: [T] = []
        out.reserveCapacity(drive.count)
        for i in 0..<drive.count {
            guard let cmd = ctx.commandQueue.makeCommandBuffer() else { continue }
            var features = withAspect(i)
            var stem = stems[i]
            geo.update(features: features, stemFeatures: stem, commandBuffer: cmd)
            let rpd = clearRPD(tex)
            guard let enc = cmd.makeRenderCommandEncoder(descriptor: rpd) else { continue }
            enc.setRenderPipelineState(preset.pipelineState)
            enc.setFragmentBytes(&features, length: MemoryLayout<FeatureVector>.stride, index: 0)
            enc.setFragmentBuffer(fft, offset: 0, index: 1)
            enc.setFragmentBuffer(wav, offset: 0, index: 2)
            enc.setFragmentBytes(&stem, length: MemoryLayout<StemFeatures>.stride, index: 3)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            geo.render(encoder: enc, features: features)
            enc.endEncoding()
            try commit(cmd, tex, into: &pixels)
            out.append(reduce(pixels))
        }
        return out
    }

    // MARK: - Render: particle (Stave — beaded traces + tint wash over its own ruled field)

    /// Stave reads ONE thing: the engine's waveform buffer. No FeatureVector route, no stems.
    /// So the worst case has to be built IN THAT BUFFER — a broadband signal whose envelope is
    /// slammed between silence and full scale at the accent rate. That is the largest
    /// whole-frame luminance swing the preset can produce, because the frame brightens when
    /// the bands sum toward white and the fan opens.
    ///
    /// Mirrors `RenderPipeline.drawParticleMode`: preset ground triangle, then the dispersion
    /// into the same encoder. The settle window lets the 20 s per-band level tracker warm in,
    /// so what is measured is the steady preset rather than its gains converging.
    private func renderStave<T>(_ drive: [FeatureVector], _ stems: [StemFeatures],
                                settle: Int, _ reduce: (_ bgra: [UInt8]) -> T) throws -> [T] {
        let ctx = try MetalContext()
        let lib = try ShaderLibrary(context: ctx)
        guard let preset = _acceptanceFixture.presets.first(where: { $0.descriptor.name == "Stave" }) else {
            throw HarnessError.presetNotFound("Stave")
        }
        let floatStride = MemoryLayout<Float>.stride
        let sampleCount = 1024
        guard let fft = ctx.makeSharedBuffer(length: 512 * floatStride),
              let wav = ctx.makeSharedBuffer(length: sampleCount * 2 * floatStride) else {
            throw HarnessError.setupFailed("audio buffers")
        }
        let geo = try StaveTrace(device: ctx.device, library: lib.library, waveform: wav,
                                 configuration: StaveConfiguration(sampleCount: sampleCount, sampleRate: 48_000),
                                 pixelFormat: ctx.pixelFormat)
        let wavePtr = wav.contents().bindMemory(to: Float.self, capacity: sampleCount * 2)
        // Publish the primitive the way RenderPipeline does — the harness bypasses it, and
        // without this the fan reads zero and the flash measure would be of a flat wave.
        var occupancy = WaveformOccupancy()

        // Deterministic broadband noise — a fixed LCG, so the gate measures the same signal on
        // every run. Real music is not noise, but noise is the densest possible spectrum and
        // therefore the brightest frame this preset can draw.
        var lcg: UInt32 = 0x5EED
        func nextNoise() -> Float {
            lcg = 1_664_525 &* lcg &+ 1_013_904_223
            return Float(Int32(bitPattern: lcg)) / Float(Int32.max)
        }
        /// Fill the buffer at `envelope` amplitude.
        func fill(_ envelope: Float) {
            for i in 0..<sampleCount {
                let v = nextNoise() * envelope
                wavePtr[2 * i] = v
                wavePtr[2 * i + 1] = v
            }
        }
        // Envelope gated at the accent rate: full scale for half a period, silence for half.
        let period = FlashHarnessSupport.fps / FlashHarnessSupport.accentHz
        func envelope(_ i: Int) -> Float {
            (Double(i).truncatingRemainder(dividingBy: period) < period / 2) ? 0.9 : 0.0
        }

        let aspect = Float(width) / Float(height)
        func withAspect(_ i: Int) -> FeatureVector { var f = drive[i]; f.aspectRatio = aspect; return f }

        let tex = try makeOutputTexture(ctx)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for i in 0..<settle {
            guard let cmd = ctx.commandQueue.makeCommandBuffer() else { continue }
            fill(envelope(i))
            var warm = withAspect(i % drive.count)
            occupancy.advance(waveform: wavePtr, frames: sampleCount, deltaTime: warm.deltaTime)
            warm.waveformOccupancy = occupancy.value
            geo.update(features: warm, stemFeatures: .zero, commandBuffer: cmd)
            cmd.commit(); cmd.waitUntilCompleted()
        }
        var out: [T] = []
        out.reserveCapacity(drive.count)
        for i in 0..<drive.count {
            guard let cmd = ctx.commandQueue.makeCommandBuffer() else { continue }
            fill(envelope(settle + i))
            var features = withAspect(i)
            occupancy.advance(waveform: wavePtr, frames: sampleCount, deltaTime: features.deltaTime)
            features.waveformOccupancy = occupancy.value
            var stem = StemFeatures.zero
            geo.update(features: features, stemFeatures: stem, commandBuffer: cmd)
            let rpd = clearRPD(tex)
            guard let enc = cmd.makeRenderCommandEncoder(descriptor: rpd) else { continue }
            enc.setRenderPipelineState(preset.pipelineState)
            enc.setFragmentBytes(&features, length: MemoryLayout<FeatureVector>.stride, index: 0)
            enc.setFragmentBuffer(fft, offset: 0, index: 1)
            enc.setFragmentBuffer(wav, offset: 0, index: 2)
            enc.setFragmentBytes(&stem, length: MemoryLayout<StemFeatures>.stride, index: 3)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            geo.render(encoder: enc, features: features)
            enc.endEncoding()
            try commit(cmd, tex, into: &pixels)
            out.append(reduce(pixels))
        }
        return out
    }

    // MARK: - Render: particle (Meniscus — wave surface over its own ground/sky)

    /// Meniscus, like Witchlight, draws an audio-driven BACKDROP as well as its geometry:
    /// `meniscus_ground_fragment` carries the ground and sky, and its brightness gate is
    /// volume-driven. Measuring the surface against a black clear would under-report the
    /// frame's mean luminance and hand the safety gate an easier signal than ships.
    ///
    /// Mirrors `RenderPipeline.drawParticleMode`: sim step inside the command buffer, then
    /// the preset triangle, then the surface. The settle window matters here — the wave
    /// field integrates, so the first frames are a field growing from flat rather than the
    /// steady surface whose flash behaviour is the question.
    private func renderMeniscus<T>(_ drive: [FeatureVector], _ stems: [StemFeatures],
                                   settle: Int, _ reduce: (_ bgra: [UInt8]) -> T) throws -> [T] {
        let ctx = try MetalContext()
        let lib = try ShaderLibrary(context: ctx)
        guard let preset = _acceptanceFixture.presets.first(where: { $0.descriptor.name == "Meniscus" }) else {
            throw HarnessError.presetNotFound("Meniscus")
        }
        let geo = try MeniscusSurface(device: ctx.device, library: lib.library,
                                      configuration: MeniscusConfiguration(), pixelFormat: ctx.pixelFormat)
        let floatStride = MemoryLayout<Float>.stride
        guard let fft = ctx.makeSharedBuffer(length: 512 * floatStride),
              let wav = ctx.makeSharedBuffer(length: 2048 * floatStride) else {
            throw HarnessError.setupFailed("audio buffers")
        }
        let aspect = Float(width) / Float(height)
        func withAspect(_ i: Int) -> FeatureVector { var f = drive[i]; f.aspectRatio = aspect; return f }

        let tex = try makeOutputTexture(ctx)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for i in 0..<settle {
            guard let cmd = ctx.commandQueue.makeCommandBuffer() else { continue }
            geo.update(features: withAspect(i % drive.count), stemFeatures: stems[i % stems.count],
                       commandBuffer: cmd)
            cmd.commit(); cmd.waitUntilCompleted()
        }
        var out: [T] = []
        out.reserveCapacity(drive.count)
        for i in 0..<drive.count {
            guard let cmd = ctx.commandQueue.makeCommandBuffer() else { continue }
            var features = withAspect(i)
            var stem = stems[i]
            geo.update(features: features, stemFeatures: stem, commandBuffer: cmd)
            let rpd = clearRPD(tex)
            guard let enc = cmd.makeRenderCommandEncoder(descriptor: rpd) else { continue }
            enc.setRenderPipelineState(preset.pipelineState)
            enc.setFragmentBytes(&features, length: MemoryLayout<FeatureVector>.stride, index: 0)
            enc.setFragmentBuffer(fft, offset: 0, index: 1)
            enc.setFragmentBuffer(wav, offset: 0, index: 2)
            enc.setFragmentBytes(&stem, length: MemoryLayout<StemFeatures>.stride, index: 3)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            geo.render(encoder: enc, features: features)
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

    // MARK: - Render: ray-march, no follower (Volumetric Lithograph)

    // VL is the Lumen ray_march path minus the 4-light follower, plus the two
    // drives VL's world rides that a static-scene render would omit: the per-frame
    // `sceneParamsA.x = accumulatedAudioTime` (fold rotation + terrain phase) and
    // the sidecar camera dolly. Without them the flash measure would be on a
    // frozen frame — a vacuous "safe" the assertion explicitly rejects.
    private func renderVolumetricLithograph<T>(_ drive: [FeatureVector], _ stems: [StemFeatures],
                                               _ reduce: (_ bgra: [UInt8]) -> T) throws -> [T] {
        let ctx = try MetalContext()
        let lib = try ShaderLibrary(context: ctx)
        guard let preset = _acceptanceFixture.presets.first(where: { $0.descriptor.name == "Volumetric Lithograph" }) else {
            throw HarnessError.presetNotFound("Volumetric Lithograph")
        }
        guard let gbufferState = preset.rayMarchPipelineState else {
            throw HarnessError.setupFailed("Volumetric Lithograph rayMarchPipelineState missing")
        }
        let pipeline = try RayMarchPipeline(context: ctx, shaderLibrary: lib)
        pipeline.allocateTextures(width: width, height: height)
        var scene = preset.descriptor.makeSceneUniforms()
        scene.sceneParamsA.y = Float(width) / Float(height)
        pipeline.sceneUniforms = scene
        pipeline.ssgiEnabled = preset.descriptor.passes.contains(.ssgi)
        pipeline.cameraDollySpeed = preset.descriptor.sceneDollySpeed   // the forward flight

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
        let floatStride = MemoryLayout<Float>.stride
        guard let fft = ctx.makeSharedBuffer(length: 512 * floatStride),
              let wav = ctx.makeSharedBuffer(length: 2048 * floatStride) else {
            throw HarnessError.setupFailed("audio buffers")
        }
        let outTex = try makeOutputTexture(ctx)
        var audioTime: Float = 0
        return try renderLoop(drive, ctx, outTex, reduce) { i, pixels in
            var fv = drive[i]
            let stem = stems[i]
            // Advance the energy-gated animation clock exactly as RenderPipeline does.
            audioTime += max(0, fv.bass) * (1.0 / 60.0)
            fv.accumulatedAudioTime = audioTime
            pipeline.sceneUniforms.sceneParamsA.x = audioTime
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
                postProcessChain: postChain)
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

    // MARK: - Render: mesh shader (Fractal Tree — object → mesh → fragment)

    /// Render a mesh-shader preset through `PresetLoader` + `MeshGenerator`, the same objects
    /// `RenderPipeline` uses live.
    ///
    /// ★★ WHY THIS NEEDS A LIVE DRIVE AND THE OTHER PATHS DO NOT. `PresetFrameBudgetTests.drive`
    /// builds its vectors with `FeatureVector(bass:mid:treble:time:deltaTime:)`, whose
    /// `pulseAmp01` is **0** — and `pulseAmp01` is Fractal Tree's silence GATE (D-037). Rendered
    /// from that drive the preset draws its 7-branch silent figure, roughly a quarter of the
    /// geometry it emits during playback, and the recorded budget would have been a number for a
    /// frame nobody ever sees. A gate that measures a preset in a state it never occupies is the
    /// same failure mode as not measuring it: it reads green and proves nothing.
    ///
    /// So the drive is topped up here, per preset, with the fields that put THIS preset in the
    /// state it holds during playback. `openTheGates` documents each one and why.
    ///
    /// ⚠ The same hazard applies to any other gate-driven preset added to this harness later —
    /// check what its silence gate reads before recording a baseline for it.
    private func renderMeshPreset<T>(_ presetName: String,
                                     _ drive: [FeatureVector],
                                     _ stems: [StemFeatures],
                                     settle: Int,
                                     _ reduce: (_ bgra: [UInt8]) -> T) throws -> [T] {
        let ctx = try MetalContext()
        let loader = PresetLoader(device: ctx.device, pixelFormat: ctx.pixelFormat,
                                 loadBuiltIn: true)
        guard let preset = loader.presets.first(where: { $0.descriptor.name == presetName }) else {
            throw HarnessError.presetNotFound("\(presetName) did not load through PresetLoader")
        }
        guard preset.descriptor.passes.contains(.meshShader) else {
            throw HarnessError.setupFailed("\(presetName) is not a mesh preset")
        }
        let generator = MeshGenerator(
            device: ctx.device,
            pipelineState: preset.pipelineState,
            configuration: .init(maxVerticesPerMeshlet: 252,
                                 maxPrimitivesPerMeshlet: 126,
                                 meshThreadCount: preset.descriptor.meshThreadCount))
        // DETERMINISTIC CLOCK. `MeshGenerator.nextRenderDelta` reads the wall clock by default,
        // which offline is the harness's own render speed — so the glides and `DancePhase` would
        // advance at a rate set by how contended the machine is, and a slow frame would converge
        // a glide in one step. Timing a preset whose geometry depends on how fast it is being
        // timed is circular; the capture's own delta is what FTR.14 established here.
        generator.renderDeltaOverride = 1.0 / 60.0

        let live = drive.map { Self.openTheGates($0) }
        let target = try makeOutputTexture(ctx)

        // Settle unTIMED and unCAPTURED, but through the real holds — the growth stepper and all
        // three glides carry state, so a first frame drawn cold measures a sapling mid-grow-in
        // (FTR.32) rather than the tree the gate is meant to watch.
        for index in 0..<settle {
            generator.advanceBeatHoldForSettling(live[index % live.count],
                                                 stems: stems[index % stems.count])
        }

        return try renderLoop(live, ctx, target, reduce) { frame, pixels in
            guard let cmd = ctx.commandQueue.makeCommandBuffer() else {
                throw HarnessError.renderFailed
            }
            guard let enc = cmd.makeRenderCommandEncoder(descriptor: clearRPD(target)) else {
                throw HarnessError.renderFailed
            }
            generator.draw(encoder: enc, features: live[frame], stems: stems[frame])
            enc.endEncoding()
            try commit(cmd, target, into: &pixels)
        }
    }

    /// Put a drive vector into the state a preset holds DURING PLAYBACK.
    ///
    /// Each field here is one that reads zero from the shared drive and would otherwise leave the
    /// preset in a state it never occupies on real audio:
    ///
    ///   - `pulseAmp01 = 1` — the silence gate. 0 means "nothing is playing" and collapses
    ///     Fractal Tree to 7 branches. Measured live it sits at 1.000 on 98.7 % of frames
    ///     (WL.1), so 1 is the honest steady state, not a flattering one.
    ///   - `trackElapsedS = 60` — past FTR.32's 2.5 s canopy grow-in, so the tree is full.
    ///   - `beatsPerBar = 4` + a `beatPhase01` ramp — `DancePhase` returns 0 until a grid exists
    ///     (the cold-start phase contract), which would freeze the gait and the tips. The ramp
    ///     runs at the drive's own 60 Hz so the phase advances a realistic amount per frame.
    ///   - `spectralSectionRatio = 1.2` — the density rank FTR.33's `ArrivalStep` quantises;
    ///     ×0.5 that is 0.6, a middle tier, so the geometry sits mid-range rather than at either
    ///     extreme of its branch count.
    ///   - `spectralSurge` / `spectralDensity` / `bassDev` / `spectralFlux` — the remaining
    ///     routes (musicGate, dance gain, branch spread). Left at zero the spread sits at its
    ///     minimum and the canopy is narrower than it ever is live.
    ///
    /// Deliberately NOT extreme: this is a regression baseline, so it wants the preset's typical
    /// cost. Driving every field to 1.0 would record a worst case and then fail the gate the
    /// first time a normal passage came in under it.
    private static func openTheGates(_ vector: FeatureVector) -> FeatureVector {
        var out = vector
        out.pulseAmp01 = 1
        out.trackElapsedS = 60
        out.beatsPerBar = 4
        out.beatPhase01 = (vector.time * 1.5).truncatingRemainder(dividingBy: 1.0)
        out.spectralSectionRatio = 1.2
        out.spectralSurge = 0.5
        out.spectralDensity = 0.25
        out.bassDev = 0.3
        out.spectralFlux = 0.4
        return out
    }

    // MARK: - Render: direct (one fullscreen fragment — Nebula / Plasma / Cartograph / Waveform)

    /// Render a `direct`-pass preset exactly as `RenderPipeline.encodePresetVisualization` does.
    ///
    /// One generic path covers all four because a direct preset is one fullscreen fragment with no
    /// per-preset Swift state — the property that made this the cheapest paradigm to add after
    /// PERF.7's mesh path. **Every binding that call site makes is made here**, because an
    /// unbound buffer does not fail loudly: a preset reading slot 2 when nothing is bound there
    /// samples zeros and costs less than it does live, and the recorded budget would quietly be a
    /// number for a cheaper frame than production draws. That is the same hazard as timing Fractal
    /// Tree with its silence gate shut (PERF.7), in a form no assertion on one preset can catch.
    ///
    /// So: FeatureVector at 0, FFT magnitudes at 1, waveform at 2, StemFeatures at 3, spectral
    /// history at 5, and the real generated noise textures — `Spectral Cartograph` samples two of
    /// them, and reading an unbound texture is free where sampling a real one is not.
    private func renderDirectPreset<T>(_ presetName: String,
                                       _ drive: [FeatureVector],
                                       _ stems: [StemFeatures],
                                       _ reduce: (_ bgra: [UInt8]) -> T) throws -> [T] {
        let ctx = try MetalContext()
        let lib = try ShaderLibrary(context: ctx)
        let loader = PresetLoader(device: ctx.device, pixelFormat: ctx.pixelFormat,
                                 loadBuiltIn: true)
        guard let preset = loader.presets.first(where: { $0.descriptor.name == presetName }) else {
            throw HarnessError.presetNotFound("\(presetName) did not load through PresetLoader")
        }
        let floatStride = MemoryLayout<Float>.stride
        guard let fft = ctx.makeSharedBuffer(length: 512 * floatStride),
              let wav = ctx.makeSharedBuffer(length: 2048 * floatStride) else {
            throw HarnessError.setupFailed("fft/waveform buffers")
        }
        // Deterministic broadband content, same reasoning as the Stave path: a fixed LCG so the
        // gate measures the same signal every run, and dense enough that no early-out in a
        // spectrum-reading preset can make the frame artificially cheap.
        var seed: UInt64 = 0x9E3779B97F4A7C15
        func nextNoise() -> Float {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Float(Int32(truncatingIfNeeded: seed >> 33)) / Float(Int32.max)
        }
        let fftPtr = fft.contents().assumingMemoryBound(to: Float.self)
        for bin in 0..<512 { fftPtr[bin] = abs(nextNoise()) * (1.0 - Float(bin) / 640.0) }
        let wavPtr = wav.contents().assumingMemoryBound(to: Float.self)
        for sample in 0..<2048 { wavPtr[sample] = nextNoise() * 0.6 }

        let history = SpectralHistoryBuffer(device: ctx.device)
        // The real generated textures, not placeholders — see the note above.
        let textures = try TextureManager(context: ctx, shaderLibrary: lib)
        let target = try makeOutputTexture(ctx)

        return try renderLoop(drive, ctx, target, reduce) { frame, pixels in
            guard let cmd = ctx.commandQueue.makeCommandBuffer() else {
                throw HarnessError.renderFailed
            }
            guard let enc = cmd.makeRenderCommandEncoder(descriptor: clearRPD(target)) else {
                throw HarnessError.renderFailed
            }
            var features = drive[frame]
            var stem = stems[frame]
            enc.setRenderPipelineState(preset.pipelineState)
            enc.setFragmentBytes(&features, length: MemoryLayout<FeatureVector>.size, index: 0)
            enc.setFragmentBuffer(fft, offset: 0, index: 1)
            enc.setFragmentBuffer(wav, offset: 0, index: 2)
            enc.setFragmentBytes(&stem, length: MemoryLayout<StemFeatures>.size, index: 3)
            enc.setFragmentBuffer(history.gpuBuffer, offset: 0, index: 5)
            textures.bindTextures(to: enc)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            enc.endEncoding()
            try commit(cmd, target, into: &pixels)
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
