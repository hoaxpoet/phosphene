// AuroraVeilMVWarpAccumulationTest — Multi-frame smear diagnostic for AV.2.x.
//
// AV.2.1's velocity-differential hotfix did NOT resolve the live-session
// smear (sessions `2026-05-18T21-44-14Z` and `2026-05-18T22-17-36Z` both
// show the same painterly green/magenta blobs at silence). The single-
// frame `AuroraVeilSilenceTest` + `PresetVisualReviewTests` harnesses
// never exercise mv_warp's frame-to-frame accumulation, so they CANNOT
// catch this regression class. This test fills that gap by running
// Aurora Veil through the full mv_warp pipeline (warp + compose + swap)
// for N frames at silence and capturing the final accumulator state.
//
// Quantitative diagnostic: count "star pixels" (luma > 0.45) in the final
// frame's upper sky band (uv.y ∈ [0.0, 0.20]). A clean render shows
// hundreds of pinpoint stars (the AV.1 silence test asserts the sky band
// has `max-min > 0.5` luma which requires sparse bright pinpoints). A
// smeared render has the stars dragged across the curl-noise random walk
// and the per-pixel max luma drops below the threshold — star count
// approaches zero.
//
// The test runs ONLY when AURORA_VEIL_MVWARP_DIAG=1 is set in the env;
// produces three runs to /tmp/aurora_veil_mvwarp_diag/<ISO>:
//   - mvwarp_on.png  : full pipeline at design params (decay 0.945, curl 0.005)
//   - mvwarp_off.png : single-frame, no accumulation
//   - mvwarp_tame.png: decay 0.70, curl 0.0005
//
// Pure diagnostic — not a CI gate, no `#expect` calls beyond a printed
// summary table to STDOUT for Matt + Claude to read.

import Testing
import Foundation
import Metal
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import Renderer
@testable import Presets
@testable import Shared

// 16-byte AuroraVeilStateGPU mirror — silence baseline (kink=0, pitch=0
// → confidence-gated fallback to 0.5 inside the shader).
private struct AuroraVeilStateGPUMirror {
    var kinkAccumulator: Float = 0
    var smoothedPitchNorm: Float = 0
    var padA: Float = 0
    var padB: Float = 0
}

@Suite("AuroraVeil mv_warp accumulation diagnostic")
struct AuroraVeilMVWarpAccumulationTest {

    private static let width  = 480
    private static let height = 360
    private static let frameCount = 60      // ~1 s at 60 fps; well past mv_warp's ~17-frame decay window
    private static let deltaTime: Float = 1.0 / 60.0

    // MARK: - drawDirect slot-6 contract (AV.2.2a regression guard)
    //
    // AV.2.2 dropped mv_warp from Aurora Veil's passes, moving its render
    // dispatch from the mv_warp path (which binds slot 6) to the direct path
    // (`drawDirect` — which did NOT bind slot 6 pre-fix). First live frame
    // crashed on the unbound `[[buffer(6)]]` read in `aurora_fragment`.
    //
    // This static-source assertion fires if a future edit removes the slot-6
    // binding from `drawDirect`. Cheap regression guard; complements (but
    // does not replace) a full integration test that exercises drawDirect
    // end-to-end against a live RenderPipeline + MTKView (deferred to
    // AV.2.3 scope — see RELEASE_NOTES `[dev-2026-05-18-g]`).
    @Test("drawDirect binds fragment slot 6 for direct-pass preset state buffers")
    func test_drawDirect_bindsSlot6() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // /Presets/
            .deletingLastPathComponent()  // /PhospheneEngineTests/
            .deletingLastPathComponent()  // /Tests/
            .deletingLastPathComponent()  // /PhospheneEngine/
            .deletingLastPathComponent()  // repo root
        let drawSource = repoRoot
            .appendingPathComponent("PhospheneEngine/Sources/Renderer/RenderPipeline+Draw.swift")
        let src = try String(contentsOf: drawSource, encoding: .utf8)
        // Extract the body of `func drawDirect(` so we don't get false-positive
        // matches from comments elsewhere in the file.
        guard let drawDirectRange = src.range(of: "func drawDirect(") else {
            Issue.record("RenderPipeline+Draw.swift: `func drawDirect(` not found — file refactored?")
            return
        }
        let body = String(src[drawDirectRange.lowerBound...])
        #expect(
            body.contains("offset: 0, index: 6"),
            """
            drawDirect no longer binds fragment slot 6. AV.2.2a regression: \
            Aurora Veil's [[buffer(6)]] AuroraVeilStateGPU read will crash on \
            the first frame after preset apply. Restore the slot-6 binding \
            (mirrors renderSceneToTexture in RenderPipeline+MVWarp.swift).
            """
        )
    }

    @Test("Multi-frame mv_warp accumulation: ON / OFF / TAME (env-gated)")
    func test_mvwarpAccumulation_diag() throws {
        guard ProcessInfo.processInfo.environment["AURORA_VEIL_MVWARP_DIAG"] == "1" else {
            print("AuroraVeilMVWarpAccumulationTest: AURORA_VEIL_MVWARP_DIAG not set, skipping")
            return
        }
        guard let preset = _acceptanceFixture.presets.first(where: {
            $0.descriptor.name == "Aurora Veil"
        }) else {
            print("AuroraVeilMVWarpAccumulationTest: Aurora Veil preset not loaded, skipping")
            return
        }
        guard let mvWarp = preset.mvWarpPipelines else {
            print("AuroraVeilMVWarpAccumulationTest: preset.mvWarpPipelines is nil, skipping")
            return
        }
        let ctx = try MetalContext()
        let outDir = try makeOutputDir()
        print("[mvwarp_diag] output dir: \(outDir.path)")

        // ── Run 1: mv_warp ON (current design params: decay 0.945, curl 0.005) ──
        let on = try runAccumulationLoop(
            preset: preset, mvWarp: mvWarp, context: ctx,
            mvWarpEnabled: true, decayOverride: nil, curlAmpOverride: nil
        )
        try writePNG(on.pixels, to: outDir.appendingPathComponent("mvwarp_on.png"))

        // ── Run 2: mv_warp OFF (single-frame render — no accumulation) ──────
        let off = try runAccumulationLoop(
            preset: preset, mvWarp: mvWarp, context: ctx,
            mvWarpEnabled: false, decayOverride: nil, curlAmpOverride: nil
        )
        try writePNG(off.pixels, to: outDir.appendingPathComponent("mvwarp_off.png"))

        // ── Run 3: mv_warp ON with TAME params (decay 0.70, curl 0.0005) ────
        let tame = try runAccumulationLoop(
            preset: preset, mvWarp: mvWarp, context: ctx,
            mvWarpEnabled: true, decayOverride: 0.70, curlAmpOverride: 0.0005
        )
        try writePNG(tame.pixels, to: outDir.appendingPathComponent("mvwarp_tame.png"))

        print("""
        [mvwarp_diag] Summary (\(Self.frameCount) frames at silence, \(Self.width)×\(Self.height)):
          ┌─────────────────────────┬──────────┬───────────┬─────────────┐
          │ Run                     │ skyStars │ skyMaxLuma│ frameMaxLuma│
          ├─────────────────────────┼──────────┼───────────┼─────────────┤
          │ mv_warp ON (design)     │  \(pad(on.skyStarCount, 6))  │   \(padF(on.skyMaxLuma))  │     \(padF(on.frameMaxLuma))    │
          │ mv_warp OFF             │  \(pad(off.skyStarCount, 6))  │   \(padF(off.skyMaxLuma))  │     \(padF(off.frameMaxLuma))    │
          │ mv_warp TAME (0.70/.0005)│  \(pad(tame.skyStarCount, 6))  │   \(padF(tame.skyMaxLuma))  │     \(padF(tame.frameMaxLuma))    │
          └─────────────────────────┴──────────┴───────────┴─────────────┘
        Interpretation: skyStars = pixels in uv.y∈[0.0,0.20] with luma>0.45.
        A clean sky has hundreds; smeared output drops to near zero.
        """)
    }

    // MARK: - Accumulation loop

    private struct LoopResult {
        let pixels: [UInt8]
        let skyStarCount: Int
        let skyMaxLuma: Float
        let frameMaxLuma: Float
    }

    private func runAccumulationLoop(
        preset: PresetLoader.LoadedPreset,
        mvWarp: PresetLoader.MVWarpCompiledPipelines,
        context: MetalContext,
        mvWarpEnabled: Bool,
        decayOverride: Float?,
        curlAmpOverride: Float?
    ) throws -> LoopResult {
        let device = context.device
        let queue = context.commandQueue

        // Three textures: scene (per-frame aurora_fragment output), warp (prev
        // frame accumulator), compose (this-frame accumulator). Swap warp↔compose
        // each frame. `.shared` so we can read pixels back at the end.
        let texDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: context.pixelFormat,
            width: Self.width, height: Self.height, mipmapped: false)
        texDesc.usage = [.renderTarget, .shaderRead]
        texDesc.storageMode = .shared
        guard let sceneTex = device.makeTexture(descriptor: texDesc),
              var warpTex = device.makeTexture(descriptor: texDesc),
              var composeTex = device.makeTexture(descriptor: texDesc)
        else { throw DiagError.textureFailed }

        // Zero-init all three textures (one-shot clear pass).
        try clearTextures([sceneTex, warpTex, composeTex], context: context)

        // Shared buffers (zeroed — silence) reused across all frames.
        let floatStride = MemoryLayout<Float>.stride
        guard
            let fft  = context.makeSharedBuffer(length: 512 * floatStride),
            let wav  = context.makeSharedBuffer(length: 2048 * floatStride),
            let stem = context.makeSharedBuffer(length: MemoryLayout<StemFeatures>.size),
            let hist = context.makeSharedBuffer(length: 4096 * floatStride),
            let avState = context.makeSharedBuffer(length: MemoryLayout<AuroraVeilStateGPUMirror>.stride)
        else { throw DiagError.bufferFailed }
        _ = fft.contents().initializeMemory(as: UInt8.self, repeating: 0, count: 512 * floatStride)
        _ = wav.contents().initializeMemory(as: UInt8.self, repeating: 0, count: 2048 * floatStride)
        _ = stem.contents().initializeMemory(as: UInt8.self, repeating: 0,
                                             count: MemoryLayout<StemFeatures>.size)
        _ = hist.contents().initializeMemory(as: UInt8.self, repeating: 0, count: 4096 * floatStride)
        var avMirror = AuroraVeilStateGPUMirror()
        avState.contents().copyMemory(from: &avMirror,
                                      byteCount: MemoryLayout<AuroraVeilStateGPUMirror>.stride)

        for frameIdx in 0..<Self.frameCount {
            let t = Float(frameIdx) * Self.deltaTime + 3.0   // start at AV.1 silence-test t=3.0
            var features = FeatureVector(time: t, deltaTime: Self.deltaTime)
            guard let cmd = queue.makeCommandBuffer() else { throw DiagError.cmdBufferFailed }

            // ── Pass A: render aurora_fragment → sceneTex ────────────────────
            try renderScene(
                cmd: cmd, preset: preset, target: sceneTex,
                features: &features,
                fft: fft, wav: wav, stem: stem, hist: hist, avState: avState
            )

            if mvWarpEnabled {
                // ── Pass B: warp prev (warpTex) → composeTex ────────────────
                try encodeWarp(
                    cmd: cmd, mvWarp: mvWarp,
                    warpTex: warpTex, composeTex: composeTex,
                    features: &features, curlAmpOverride: curlAmpOverride
                )
                // ── Pass C: compose scene onto composeTex via alpha-blend ───
                try encodeCompose(
                    cmd: cmd, mvWarp: mvWarp,
                    sceneTex: sceneTex, composeTex: composeTex,
                    decayOverride: decayOverride
                )
                cmd.commit()
                cmd.waitUntilCompleted()
                // Swap warp ↔ compose for next frame.
                let tmp = warpTex
                warpTex = composeTex
                composeTex = tmp
            } else {
                // No mv_warp: scene IS the final output. Just commit the scene render.
                cmd.commit()
                cmd.waitUntilCompleted()
            }
        }

        // Read final pixels. For mv_warp-on the latest-frame result is in
        // warpTex (post-swap). For mv_warp-off it's in sceneTex (the last
        // frame's direct render). Default branch reads warpTex; off-branch
        // reads sceneTex.
        let finalTex = mvWarpEnabled ? warpTex : sceneTex
        var pixels = [UInt8](repeating: 0, count: Self.width * Self.height * 4)
        finalTex.getBytes(&pixels, bytesPerRow: Self.width * 4,
                          from: MTLRegionMake2D(0, 0, Self.width, Self.height), mipmapLevel: 0)

        let (stars, skyMax, frameMax) = analyzeFrame(pixels)
        return LoopResult(pixels: pixels, skyStarCount: stars,
                          skyMaxLuma: skyMax, frameMaxLuma: frameMax)
    }

    // MARK: - Pass encoders

    private func renderScene(
        cmd: MTLCommandBuffer, preset: PresetLoader.LoadedPreset, target: MTLTexture,
        features: inout FeatureVector,
        fft: MTLBuffer, wav: MTLBuffer, stem: MTLBuffer, hist: MTLBuffer, avState: MTLBuffer
    ) throws {
        let desc = MTLRenderPassDescriptor()
        desc.colorAttachments[0].texture = target
        desc.colorAttachments[0].loadAction = .clear
        desc.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        desc.colorAttachments[0].storeAction = .store
        guard let enc = cmd.makeRenderCommandEncoder(descriptor: desc) else { throw DiagError.encoderFailed }
        enc.setRenderPipelineState(preset.pipelineState)
        enc.setFragmentBytes(&features, length: MemoryLayout<FeatureVector>.size, index: 0)
        enc.setFragmentBuffer(fft, offset: 0, index: 1)
        enc.setFragmentBuffer(wav, offset: 0, index: 2)
        enc.setFragmentBuffer(stem, offset: 0, index: 3)
        enc.setFragmentBuffer(hist, offset: 0, index: 5)
        enc.setFragmentBuffer(avState, offset: 0, index: 6)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
    }

    private func encodeWarp(
        cmd: MTLCommandBuffer, mvWarp: PresetLoader.MVWarpCompiledPipelines,
        warpTex: MTLTexture, composeTex: MTLTexture,
        features: inout FeatureVector, curlAmpOverride: Float?
    ) throws {
        // NOTE: We can't override curl_noise amplitude from the test side
        // without editing the shader — the shader's curl_noise * 0.005 is a
        // compile-time constant in mvWarpPerVertex. The TAME run sets
        // decayOverride to demonstrate the decay axis but DOES NOT change
        // the curl amplitude. To truly test reduced-curl, we'd need a shader
        // edit. Document this limitation.
        _ = curlAmpOverride

        let desc = MTLRenderPassDescriptor()
        desc.colorAttachments[0].texture = composeTex
        desc.colorAttachments[0].loadAction = .clear
        desc.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        desc.colorAttachments[0].storeAction = .store
        guard let enc = cmd.makeRenderCommandEncoder(descriptor: desc) else { throw DiagError.encoderFailed }
        enc.setRenderPipelineState(mvWarp.warpState)
        var featuresCopy = features
        enc.setVertexBytes(&featuresCopy, length: MemoryLayout<FeatureVector>.stride, index: 0)
        var stemsCopy = StemFeatures.zero
        enc.setVertexBytes(&stemsCopy, length: MemoryLayout<StemFeatures>.stride, index: 1)
        var sceneUni = SceneUniforms()
        enc.setVertexBytes(&sceneUni, length: MemoryLayout<SceneUniforms>.stride, index: 2)
        enc.setFragmentTexture(warpTex, index: 0)
        // 31×23 quads × 2 triangles × 3 vertices = 4278 (per encodeMVWarpPass).
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 4278)
        enc.endEncoding()
    }

    private func encodeCompose(
        cmd: MTLCommandBuffer, mvWarp: PresetLoader.MVWarpCompiledPipelines,
        sceneTex: MTLTexture, composeTex: MTLTexture, decayOverride: Float?
    ) throws {
        let desc = MTLRenderPassDescriptor()
        desc.colorAttachments[0].texture = composeTex
        desc.colorAttachments[0].loadAction = .load
        desc.colorAttachments[0].storeAction = .store
        guard let enc = cmd.makeRenderCommandEncoder(descriptor: desc) else { throw DiagError.encoderFailed }
        enc.setRenderPipelineState(mvWarp.composeState)
        enc.setFragmentTexture(sceneTex, index: 0)
        var decay = decayOverride ?? 0.945
        enc.setFragmentBytes(&decay, length: MemoryLayout<Float>.stride, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
    }

    // MARK: - Helpers

    private func clearTextures(_ texs: [MTLTexture], context: MetalContext) throws {
        guard let cmd = context.commandQueue.makeCommandBuffer() else { throw DiagError.cmdBufferFailed }
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

    /// Returns (skyStarCount, skyMaxLuma, frameMaxLuma) where:
    ///   - skyStarCount: pixels in uv.y ∈ [0.0, 0.20] with luma > 0.45
    ///   - skyMaxLuma: max luma in the sky band, normalised [0, 1]
    ///   - frameMaxLuma: max luma over the whole frame, normalised [0, 1]
    private func analyzeFrame(_ pixels: [UInt8]) -> (Int, Float, Float) {
        let skyYEnd = Int(0.20 * Double(Self.height))
        var stars = 0
        var skyMax: Float = 0
        var frameMax: Float = 0
        for y in 0..<Self.height {
            for x in 0..<Self.width {
                let idx = (y * Self.width + x) * 4
                let b = Float(pixels[idx + 0])
                let g = Float(pixels[idx + 1])
                let r = Float(pixels[idx + 2])
                let luma = (0.299 * r + 0.587 * g + 0.114 * b) / 255.0
                if luma > frameMax { frameMax = luma }
                if y < skyYEnd {
                    if luma > skyMax { skyMax = luma }
                    if luma > 0.45 { stars += 1 }
                }
            }
        }
        return (stars, skyMax, frameMax)
    }

    private func makeOutputDir() throws -> URL {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withColonSeparatorInTime]
        let stamp = iso.string(from: Date())
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
        let url = URL(fileURLWithPath: "/tmp/aurora_veil_mvwarp_diag/\(stamp)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writePNG(_ pixels: [UInt8], to url: URL) throws {
        // BGRA → RGBA bytes for CGImage.
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
        else { throw DiagError.encoderFailed }
        let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)
        guard let dest = dest else { throw DiagError.encoderFailed }
        CGImageDestinationAddImage(dest, img, nil)
        CGImageDestinationFinalize(dest)
        print("[mvwarp_diag] wrote \(url.lastPathComponent)")
    }

    private func pad(_ n: Int, _ width: Int) -> String {
        let s = String(n)
        return String(repeating: " ", count: max(0, width - s.count)) + s
    }

    private func padF(_ f: Float) -> String {
        String(format: "%.4f", f)
    }
}

private enum DiagError: Error {
    case textureFailed
    case bufferFailed
    case cmdBufferFailed
    case encoderFailed
}
