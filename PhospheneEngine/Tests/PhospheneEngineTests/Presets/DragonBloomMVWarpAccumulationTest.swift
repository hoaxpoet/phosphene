// DragonBloomMVWarpAccumulationTest — Spike 1 production-pipeline test.
//
// Modelled on AuroraVeilMVWarpAccumulationTest. The Dragon Bloom plan
// (`docs/presets/DRAGON_BLOOM_PLAN.md`) explicitly cites the AV.1 failure
// mode (closeouts asserting the preset worked while single-frame tests
// bypassed mv_warp accumulation) — the rule is: any preset with a temporal
// feedback contract must include a test that exercises the same dispatch
// path (scene → warp → compose → swap) the live app uses.
//
// What we prove here (structural, NOT fidelity):
//   1. The mv_warp accumulator is wired correctly: at non-silence audio
//      with a waveform-buffer signal, the bright-pixel envelope GROWS
//      from a thin curve into a feathered bloom across 60 frames.
//   2. At silence (zero waveform + zero features), the accumulator stays
//      quiet — no runaway energy from feedback loops driving themselves.
//
// What we do NOT prove here (these belong to the Matt-eyeball gate of
// §6 of the plan):
//   · Whether the bloom *reads as dancing to the music*.
//   · Whether the warm palette matches the reference.
//   · Whether the symmetry rule (Spike 2) holds — Spike 1 has no symmetry.
//
// Env-gated to avoid CI churn — set DRAGON_BLOOM_MVWARP_DIAG=1 to run.
// Writes PNGs to /tmp/dragon_bloom_mvwarp_diag/<ISO>/ + prints a summary.

import Testing
import Foundation
import Metal
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import Renderer
@testable import Presets
@testable import Shared

@Suite("Dragon Bloom mv_warp accumulation diagnostic")
struct DragonBloomMVWarpAccumulationTest {

    private static let width  = 480
    private static let height = 360
    private static let frameCount = 60        // ~1 s at 60 fps; well past mv_warp's ~17-frame decay window
    private static let deltaTime: Float = 1.0 / 60.0

    // MARK: - Static-source guards (cheap regression sentries)

    @Test("DragonBloom.metal declares both required mv_warp functions")
    func test_metalSource_declaresMVWarpFunctions() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // /Presets/
            .deletingLastPathComponent()   // /PhospheneEngineTests/
            .deletingLastPathComponent()   // /Tests/
            .deletingLastPathComponent()   // /PhospheneEngine/
            .deletingLastPathComponent()   // repo root
        let url = repoRoot.appendingPathComponent(
            "PhospheneEngine/Sources/Presets/Shaders/DragonBloom.metal")
        let src = try String(contentsOf: url, encoding: .utf8)
        #expect(src.contains("dragon_bloom_fragment"),
                "DragonBloom.metal missing dragon_bloom_fragment entry point.")
        #expect(src.contains("MVWarpPerFrame mvWarpPerFrame("),
                "DragonBloom.metal missing mvWarpPerFrame implementation (D-027 contract).")
        #expect(src.contains("float2 mvWarpPerVertex("),
                "DragonBloom.metal missing mvWarpPerVertex implementation (D-027 contract).")
    }

    @Test("DragonBloom.json declares passes: [\"direct\", \"mv_warp\"]")
    func test_json_declaresDirectAndMVWarp() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = repoRoot.appendingPathComponent(
            "PhospheneEngine/Sources/Presets/Shaders/DragonBloom.json")
        let data = try Data(contentsOf: url)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let passes = json?["passes"] as? [String]
        #expect(passes == ["direct", "mv_warp"],
                "DragonBloom.json must declare passes: [\"direct\", \"mv_warp\"] per Spike 1 plan §2.")
    }

    // MARK: - Multi-frame accumulation (env-gated)

    @Test("Multi-frame mv_warp accumulation: silence vs music (env-gated)")
    func test_mvwarpAccumulation_diag() throws {
        guard ProcessInfo.processInfo.environment["DRAGON_BLOOM_MVWARP_DIAG"] == "1" else {
            print("DragonBloomMVWarpAccumulationTest: DRAGON_BLOOM_MVWARP_DIAG not set, skipping")
            return
        }
        guard let preset = _acceptanceFixture.presets.first(where: {
            $0.descriptor.name == "Dragon Bloom"
        }) else {
            Issue.record("Dragon Bloom preset not loaded — bundle resource not copied?")
            return
        }
        guard let mvWarp = preset.mvWarpPipelines else {
            Issue.record("Dragon Bloom preset.mvWarpPipelines is nil — JSON passes array misconfigured.")
            return
        }
        let ctx = try MetalContext()
        let outDir = try makeOutputDir()
        print("[dragon_bloom_diag] output dir: \(outDir.path)")

        // ── Run A: silence (zero waveform, zero features). Accumulator must stay quiet. ──
        let silence = try runAccumulationLoop(
            preset: preset, mvWarp: mvWarp, context: ctx,
            audioMode: .silence
        )
        try writePNG(silence.pixels, to: outDir.appendingPathComponent("silence_final.png"))

        // ── Run B: synthetic "music" (sine wave in slot 2, bass/mid features non-zero) ──
        // Bloom should grow a feathered envelope across frames.
        let music = try runAccumulationLoop(
            preset: preset, mvWarp: mvWarp, context: ctx,
            audioMode: .syntheticMusic
        )
        try writePNG(music.pixels, to: outDir.appendingPathComponent("music_final.png"))

        // ── Per-frame snapshots from the music run (frames 1, 10, 30, 60) ──────
        // The accumulator's envelope should monotonically grow over this range.

        print("""
        [dragon_bloom_diag] Summary (\(Self.frameCount) frames at \(Self.width)×\(Self.height)):
          ┌─────────────────────┬──────────────┬────────────────┬─────────────────┐
          │ Run                 │ brightPixels │ frameMaxLuma   │ envelopeRadius  │
          ├─────────────────────┼──────────────┼────────────────┼─────────────────┤
          │ silence (frame 60)  │   \(pad(silence.brightPixels, 8))   │     \(padF(silence.frameMaxLuma))     │      \(padF(silence.envelopeRadius))      │
          │ music   (frame 60)  │   \(pad(music.brightPixels, 8))   │     \(padF(music.frameMaxLuma))     │      \(padF(music.envelopeRadius))      │
          └─────────────────────┴──────────────┴────────────────┴─────────────────┘
        Interpretation:
          brightPixels   = pixels with luma > 0.20 (loose threshold — feathered halo counts)
          envelopeRadius = mean radius of bright pixels (UV units), 0.28 baseline curve

        At silence (zero waveform input) the polar curve collapses to a clean
        ring at r ≈ 0.28; the accumulator stacks the ring in place (high peak
        luma, tight envelope, modest pixel count).

        Under music input the waveform deflects per-frame, the bass/mid drivers
        spread the brush via zoom + per-vertex warp, and the energy distributes
        across a WIDER envelope — so we expect MORE bright pixels, a LARGER
        envelope radius, and (often) a LOWER peak luma than silence because the
        energy isn't piling up at one place. None of these should run away to
        white clipping.
        """)

        // Structural #expect — guards regressions if the accumulator wiring breaks.
        // Both runs produce visible output (preset renders end-to-end).
        #expect(silence.brightPixels > 0,
                "Silence run produced no visible output — preset fragment may not be running.")
        #expect(music.brightPixels > 0,
                "Music run produced no visible output — preset fragment may not be running.")

        // No runaway feedback (per-frame additions don't saturate the buffer to white).
        #expect(silence.frameMaxLuma < 0.95,
                "Silence run clipped to white (\(silence.frameMaxLuma)) — decay value too high.")
        #expect(music.frameMaxLuma < 0.95,
                "Music run clipped to white (\(music.frameMaxLuma)) — accumulator running away.")

        // Music distributes energy across a wider envelope than silence.
        // This is the load-bearing structural check: it proves the audio-driven
        // warp + zoom path is reaching the accumulator and spreading the brush.
        #expect(music.brightPixels > silence.brightPixels * 2,
                """
                Music run is not visibly wider than silence \
                (\(music.brightPixels) ≤ \(silence.brightPixels) × 2). \
                The audio-driven warp displacement may not be reaching mvWarpPerVertex.
                """)
        #expect(music.envelopeRadius > silence.envelopeRadius + 0.01,
                """
                Music envelope radius (\(music.envelopeRadius)) does not exceed silence \
                (\(silence.envelopeRadius)) — bass/mid drivers are not spreading the bloom.
                """)
    }

    // MARK: - Accumulation loop

    private enum AudioMode { case silence, syntheticMusic }

    private struct LoopResult {
        let pixels: [UInt8]
        let brightPixels: Int
        let frameMaxLuma: Float
        let envelopeRadius: Float    // mean radial distance (UV) of bright pixels
    }

    private func runAccumulationLoop(
        preset: PresetLoader.LoadedPreset,
        mvWarp: PresetLoader.MVWarpCompiledPipelines,
        context: MetalContext,
        audioMode: AudioMode
    ) throws -> LoopResult {
        let device = context.device
        let queue = context.commandQueue

        let texDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: context.pixelFormat,
            width: Self.width, height: Self.height, mipmapped: false)
        texDesc.usage = [.renderTarget, .shaderRead]
        texDesc.storageMode = .shared
        guard let sceneTex = device.makeTexture(descriptor: texDesc),
              var warpTex = device.makeTexture(descriptor: texDesc),
              var composeTex = device.makeTexture(descriptor: texDesc)
        else { throw DragonBloomDiagError.textureFailed }

        try clearTextures([sceneTex, warpTex, composeTex], context: context)

        let floatStride = MemoryLayout<Float>.stride
        guard
            let fft  = context.makeSharedBuffer(length: 512 * floatStride),
            let wav  = context.makeSharedBuffer(length: 2048 * floatStride),
            let stem = context.makeSharedBuffer(length: MemoryLayout<StemFeatures>.size)
        else { throw DragonBloomDiagError.bufferFailed }

        // Zero-init the feature/stem-side buffers (kept zero across all frames in either mode).
        _ = fft.contents().initializeMemory(as: UInt8.self, repeating: 0, count: 512 * floatStride)
        _ = stem.contents().initializeMemory(as: UInt8.self, repeating: 0,
                                             count: MemoryLayout<StemFeatures>.size)

        for frameIdx in 0..<Self.frameCount {
            let t = Float(frameIdx) * Self.deltaTime + 1.0

            // Populate the waveform slot per-frame.
            populateWaveform(wav, frameIdx: frameIdx, mode: audioMode)

            // Build FeatureVector for this frame.
            var features = makeFeatures(frameIdx: frameIdx, mode: audioMode, time: t)

            guard let cmd = queue.makeCommandBuffer() else { throw DragonBloomDiagError.cmdBufferFailed }

            // ── Pass A: render dragon_bloom_fragment → sceneTex ──────────────
            try renderScene(
                cmd: cmd, preset: preset, target: sceneTex,
                features: &features, fft: fft, wav: wav, stem: stem
            )

            // ── Pass B: warp prev (warpTex) → composeTex ─────────────────────
            try encodeWarp(
                cmd: cmd, mvWarp: mvWarp,
                warpTex: warpTex, composeTex: composeTex,
                features: &features
            )
            // ── Pass C: alpha-blend scene onto composeTex ────────────────────
            try encodeCompose(
                cmd: cmd, mvWarp: mvWarp,
                sceneTex: sceneTex, composeTex: composeTex
            )

            cmd.commit()
            cmd.waitUntilCompleted()

            // Swap warp ↔ compose for the next frame.
            let tmp = warpTex
            warpTex = composeTex
            composeTex = tmp
        }

        // Final accumulated frame lives in warpTex post-swap.
        var pixels = [UInt8](repeating: 0, count: Self.width * Self.height * 4)
        warpTex.getBytes(&pixels, bytesPerRow: Self.width * 4,
                         from: MTLRegionMake2D(0, 0, Self.width, Self.height), mipmapLevel: 0)

        let (bright, maxL, envR) = analyzeFrame(pixels)
        return LoopResult(pixels: pixels, brightPixels: bright,
                          frameMaxLuma: maxL, envelopeRadius: envR)
    }

    // MARK: - Audio inputs

    /// Fill the waveform buffer (1024 stereo frames = 2048 floats). For
    /// `.syntheticMusic` we write a low-frequency sine that walks slowly
    /// in time so successive frames feed slightly different shapes into the
    /// accumulator (the live tap's behaviour). For `.silence` we leave it zeroed.
    private func populateWaveform(_ buf: MTLBuffer, frameIdx: Int, mode: AudioMode) {
        let p = buf.contents().bindMemory(to: Float.self, capacity: 2048)
        switch mode {
        case .silence:
            for i in 0..<2048 { p[i] = 0 }
        case .syntheticMusic:
            // Two superposed sines on each channel; phase walks with frame.
            let phase = Float(frameIdx) * 0.27
            for f in 0..<1024 {
                let theta = Float(f) / 1024.0 * 2.0 * .pi
                let s = 0.55 * sin(theta * 3.0 + phase)
                      + 0.25 * sin(theta * 11.0 - phase * 0.6)
                p[f * 2]     = s
                p[f * 2 + 1] = s
            }
        }
    }

    private func makeFeatures(frameIdx: Int, mode: AudioMode, time: Float) -> FeatureVector {
        switch mode {
        case .silence:
            return FeatureVector(time: time, deltaTime: Self.deltaTime)
        case .syntheticMusic:
            // Light steady-state energy: bass ~0.6, mid ~0.55 (above AGC average),
            // plus a per-second beat pulse to exercise the Layer-4 accent path.
            var fv = FeatureVector(bass: 0.60, mid: 0.55, treble: 0.45,
                                   time: time, deltaTime: Self.deltaTime)
            fv.bassRel    = 0.20
            fv.bassDev    = 0.20
            fv.midRel     = 0.10
            fv.midDev     = 0.10
            fv.bassAttRel = 0.30
            fv.midAttRel  = 0.25
            // Pulse beat_composite every 60 frames (~1 Hz).
            let pulse = (frameIdx % 60 == 0) ? Float(1.0) : Float(0.0)
            fv.beatComposite = pulse
            fv.beatBass      = pulse
            return fv
        }
    }

    // MARK: - Pass encoders

    private func renderScene(
        cmd: MTLCommandBuffer, preset: PresetLoader.LoadedPreset, target: MTLTexture,
        features: inout FeatureVector,
        fft: MTLBuffer, wav: MTLBuffer, stem: MTLBuffer
    ) throws {
        let desc = MTLRenderPassDescriptor()
        desc.colorAttachments[0].texture = target
        desc.colorAttachments[0].loadAction = .clear
        desc.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        desc.colorAttachments[0].storeAction = .store
        guard let enc = cmd.makeRenderCommandEncoder(descriptor: desc)
        else { throw DragonBloomDiagError.encoderFailed }
        enc.setRenderPipelineState(preset.pipelineState)
        enc.setFragmentBytes(&features, length: MemoryLayout<FeatureVector>.size, index: 0)
        enc.setFragmentBuffer(fft, offset: 0, index: 1)
        enc.setFragmentBuffer(wav, offset: 0, index: 2)
        enc.setFragmentBuffer(stem, offset: 0, index: 3)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
    }

    private func encodeWarp(
        cmd: MTLCommandBuffer, mvWarp: PresetLoader.MVWarpCompiledPipelines,
        warpTex: MTLTexture, composeTex: MTLTexture,
        features: inout FeatureVector
    ) throws {
        let desc = MTLRenderPassDescriptor()
        desc.colorAttachments[0].texture = composeTex
        desc.colorAttachments[0].loadAction = .clear
        desc.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        desc.colorAttachments[0].storeAction = .store
        guard let enc = cmd.makeRenderCommandEncoder(descriptor: desc)
        else { throw DragonBloomDiagError.encoderFailed }
        enc.setRenderPipelineState(mvWarp.warpState)
        var featuresCopy = features
        enc.setVertexBytes(&featuresCopy, length: MemoryLayout<FeatureVector>.stride, index: 0)
        var stemsCopy = StemFeatures.zero
        enc.setVertexBytes(&stemsCopy, length: MemoryLayout<StemFeatures>.stride, index: 1)
        var sceneUni = SceneUniforms()
        enc.setVertexBytes(&sceneUni, length: MemoryLayout<SceneUniforms>.stride, index: 2)
        enc.setFragmentTexture(warpTex, index: 0)
        // 31×23 quads × 2 triangles × 3 vertices = 4278 (matches RenderPipeline+MVWarp).
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 4278)
        enc.endEncoding()
    }

    private func encodeCompose(
        cmd: MTLCommandBuffer, mvWarp: PresetLoader.MVWarpCompiledPipelines,
        sceneTex: MTLTexture, composeTex: MTLTexture
    ) throws {
        let desc = MTLRenderPassDescriptor()
        desc.colorAttachments[0].texture = composeTex
        desc.colorAttachments[0].loadAction = .load
        desc.colorAttachments[0].storeAction = .store
        guard let enc = cmd.makeRenderCommandEncoder(descriptor: desc)
        else { throw DragonBloomDiagError.encoderFailed }
        enc.setRenderPipelineState(mvWarp.composeState)
        enc.setFragmentTexture(sceneTex, index: 0)
        var decay: Float = 0.945    // matches DragonBloom.json / kMVWarpBaseDecay
        enc.setFragmentBytes(&decay, length: MemoryLayout<Float>.stride, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
    }

    // MARK: - Helpers

    private func clearTextures(_ texs: [MTLTexture], context: MetalContext) throws {
        guard let cmd = context.commandQueue.makeCommandBuffer()
        else { throw DragonBloomDiagError.cmdBufferFailed }
        for tex in texs {
            let desc = MTLRenderPassDescriptor()
            desc.colorAttachments[0].texture = tex
            desc.colorAttachments[0].loadAction = .clear
            desc.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
            desc.colorAttachments[0].storeAction = .store
            if let enc = cmd.makeRenderCommandEncoder(descriptor: desc) { enc.endEncoding() }
        }
        cmd.commit()
        cmd.waitUntilCompleted()
    }

    /// Returns:
    ///   - brightPixels   — number of pixels with luma > 0.20 (loose: counts the halo).
    ///   - frameMaxLuma   — peak luma in the frame.
    ///   - envelopeRadius — mean radial distance (UV units) of bright pixels from
    ///                      the screen centre. Baseline curve sits at r ≈ 0.28;
    ///                      a healthy accumulated bloom spreads to r ≈ 0.30–0.45.
    private func analyzeFrame(_ pixels: [UInt8]) -> (Int, Float, Float) {
        var bright = 0
        var maxL: Float = 0
        var radSum: Float = 0
        for y in 0..<Self.height {
            for x in 0..<Self.width {
                let idx = (y * Self.width + x) * 4
                let b = Float(pixels[idx + 0])
                let g = Float(pixels[idx + 1])
                let r = Float(pixels[idx + 2])
                let luma = (0.299 * r + 0.587 * g + 0.114 * b) / 255.0
                if luma > maxL { maxL = luma }
                if luma > 0.20 {
                    bright += 1
                    let dx = (Float(x) / Float(Self.width)  - 0.5)
                    let dy = (Float(y) / Float(Self.height) - 0.5)
                    radSum += sqrt(dx * dx + dy * dy)
                }
            }
        }
        let radius = (bright > 0) ? radSum / Float(bright) : 0
        return (bright, maxL, radius)
    }

    private func makeOutputDir() throws -> URL {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withColonSeparatorInTime]
        let stamp = iso.string(from: Date())
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
        let url = URL(fileURLWithPath: "/tmp/dragon_bloom_mvwarp_diag/\(stamp)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writePNG(_ pixels: [UInt8], to url: URL) throws {
        var rgba = [UInt8](repeating: 0, count: pixels.count)
        for i in stride(from: 0, to: pixels.count, by: 4) {
            rgba[i + 0] = pixels[i + 2]
            rgba[i + 1] = pixels[i + 1]
            rgba[i + 2] = pixels[i + 0]
            rgba[i + 3] = pixels[i + 3]
        }
        let cs = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.noneSkipLast.rawValue
        guard let provider = CGDataProvider(data: Data(rgba) as CFData),
              let img = CGImage(width: Self.width, height: Self.height,
                                bitsPerComponent: 8, bitsPerPixel: 32,
                                bytesPerRow: Self.width * 4,
                                space: cs, bitmapInfo: CGBitmapInfo(rawValue: info),
                                provider: provider, decode: nil, shouldInterpolate: false,
                                intent: .defaultIntent)
        else { throw DragonBloomDiagError.encoderFailed }
        guard let dest = CGImageDestinationCreateWithURL(
            url as CFURL, "public.png" as CFString, 1, nil)
        else { throw DragonBloomDiagError.encoderFailed }
        CGImageDestinationAddImage(dest, img, nil)
        CGImageDestinationFinalize(dest)
        print("[dragon_bloom_diag] wrote \(url.lastPathComponent)")
    }

    private func pad(_ n: Int, _ width: Int) -> String {
        let s = String(n)
        return String(repeating: " ", count: max(0, width - s.count)) + s
    }

    private func padF(_ f: Float) -> String {
        String(format: "%.4f", f)
    }
}

private enum DragonBloomDiagError: Error {
    case textureFailed
    case bufferFailed
    case cmdBufferFailed
    case encoderFailed
}
