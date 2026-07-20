// KineticSculptureMotionGifHarness — watch the sculpture TURN (env-gated).
//
// KSRB.1 gate. The thin-strand feasibility spike (2026-07-19) cleared the form
// on every measure except one, and that one is a MOTION property a still cannot
// show: steeply foreshortened strands below ~2 px can stipple, and stipple that
// crawls frame-to-frame reads as shimmer. The spike inferred this from static
// coverage analysis and flagged "confirm with a rotating-camera sequence
// through the real pipeline" as the outstanding caveat. This harness is that
// confirmation, and it is also how Matt judges the silhouette in motion rather
// than from a frozen frame (the AuroraVeilMotionGifHarness precedent).
//
//   KS_GIF=1 swift test --package-path PhospheneEngine --filter KineticSculptureMotionGifHarness
// Output: /tmp/ks_motion/kinetic_sculpture.gif  (+ f0000.png … for frame reads)
//
// NOT a music validation — Kinetic Sculpture has no audio routing until KSRB.3,
// so this drives a silent FeatureVector and only advances `time` (the slow
// gallery orbit). Real musical feel is the later live M7.
//
// RESOLUTION CAVEAT (read before judging shimmer): this renders below 1080p, and
// the shader's distance-fatten floor is calibrated so a strand holds ~2 px AT
// 1080p. A pixel subtends more angle here, so strands are relatively THINNER in
// pixel terms than in production — any shimmer visible in this GIF is a
// conservative, worse-than-production read. Clean here means clean shipped.

import Testing
import Metal
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import Renderer
@testable import Presets
@testable import Shared

@Suite("Kinetic Sculpture motion — orbit GIF (env-gated)")
struct KineticSculptureMotionGifHarness {

    private enum E: Error { case setup, render }
    static let W = 720, H = 405
    static let fps = 20
    static let seconds = 6.0

    @Test("Render Kinetic Sculpture turning → animated GIF")
    func renderOrbitGif() throws {
        guard ProcessInfo.processInfo.environment["KS_GIF"] == "1" else {
            print("KineticSculptureMotionGifHarness: KS_GIF not set — skipping"); return
        }
        guard MTLCreateSystemDefaultDevice() != nil else {
            print("KineticSculptureMotionGifHarness: no Metal device — skipping"); return
        }
        let ctx = try MetalContext()
        let loader = PresetLoader(device: ctx.device, pixelFormat: ctx.pixelFormat, loadBuiltIn: true)
        guard let preset = loader.presets.first(where: { $0.descriptor.name == "Kinetic Sculpture" }) else {
            print("KineticSculptureMotionGifHarness: Kinetic Sculpture not found — skipping"); return
        }
        guard let gbufferState = preset.rayMarchPipelineState else { throw E.setup }

        let dir = URL(fileURLWithPath: "/tmp/ks_motion")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // Hoist the whole deferred stack out of the frame loop — allocating a
        // RayMarchPipeline per frame (as the single-shot visual review does)
        // would dominate wall time over 120 frames.
        let shaderLibrary = try ShaderLibrary(context: ctx)
        let pipeline = try RayMarchPipeline(context: ctx, shaderLibrary: shaderLibrary)
        pipeline.allocateTextures(width: Self.W, height: Self.H)

        var sceneUniforms = preset.descriptor.makeSceneUniforms()
        sceneUniforms.sceneParamsA.y = Float(Self.W) / Float(Self.H)
        pipeline.sceneUniforms = sceneUniforms
        pipeline.ssgiEnabled = preset.descriptor.passes.contains(.ssgi)

        let iblManager = try IBLManager(context: ctx, shaderLibrary: shaderLibrary)
        let ppChain: PostProcessChain?
        if preset.descriptor.passes.contains(.postProcess) {
            let chain = try PostProcessChain(context: ctx, shaderLibrary: shaderLibrary)
            chain.allocateTextures(width: Self.W, height: Self.H)
            ppChain = chain
        } else {
            ppChain = nil
        }

        let floatStride = MemoryLayout<Float>.stride
        guard
            let fftBuf = ctx.makeSharedBuffer(length: 512 * floatStride),
            let wavBuf = ctx.makeSharedBuffer(length: 2048 * floatStride)
        else { throw E.setup }

        let outDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: ctx.pixelFormat, width: Self.W, height: Self.H, mipmapped: false)
        outDesc.usage = [.renderTarget, .shaderRead]
        outDesc.storageMode = .shared
        guard let outTex = ctx.device.makeTexture(descriptor: outDesc) else { throw E.setup }

        let frameCount = Int(Self.seconds * Double(Self.fps))
        let dt = Float(1.0 / Double(Self.fps))

        let gifURL = dir.appendingPathComponent("kinetic_sculpture.gif")
        guard let gif = CGImageDestinationCreateWithURL(
            gifURL as CFURL, UTType.gif.identifier as CFString, frameCount, nil) else { throw E.setup }
        CGImageDestinationSetProperties(gif, [kCGImagePropertyGIFDictionary as String:
            [kCGImagePropertyGIFLoopCount as String: 0]] as CFDictionary)
        let frameProps = [kCGImagePropertyGIFDictionary as String:
            [kCGImagePropertyGIFDelayTime as String: 1.0 / Double(Self.fps)]] as CFDictionary

        for i in 0..<frameCount {
            let t = Float(i) * dt
            // Silent feature vector — only `time` advances, driving the orbit.
            // KSRB.3 replaces this with real energy/downbeat coupling.
            var fv = FeatureVector(bass: 0.0, mid: 0.0, treble: 0.0, time: t, deltaTime: dt)

            guard let cmdBuf = ctx.commandQueue.makeCommandBuffer() else { throw E.render }
            pipeline.render(
                gbufferPipelineState: gbufferState,
                features: &fv,
                fftBuffer: fftBuf,
                waveformBuffer: wavBuf,
                stemFeatures: .zero,
                outputTexture: outTex,
                commandBuffer: cmdBuf,
                noiseTextures: nil,
                iblManager: iblManager,
                postProcessChain: ppChain,
                presetFragmentBuffer3: nil,
                presetHeightTexture: nil
            )
            cmdBuf.commit(); cmdBuf.waitUntilCompleted()
            guard cmdBuf.status == .completed else { throw E.render }

            var px = [UInt8](repeating: 0, count: Self.W * Self.H * 4)
            outTex.getBytes(&px, bytesPerRow: Self.W * 4,
                            from: MTLRegionMake2D(0, 0, Self.W, Self.H), mipmapLevel: 0)
            guard let img = Self.cgImage(bgra: px, w: Self.W, h: Self.H) else { throw E.render }
            CGImageDestinationAddImage(gif, img, frameProps)
            if i % 10 == 0 {
                Self.writePNG(img, to: dir.appendingPathComponent(String(format: "f%04d.png", i)))
            }
        }
        #expect(CGImageDestinationFinalize(gif), "GIF encode failed")
        print("[ks_gif] wrote \(gifURL.path) (\(frameCount) frames @ \(Self.fps) fps)")
    }

    // MARK: - Image helpers

    private static func cgImage(bgra: [UInt8], w: Int, h: Int) -> CGImage? {
        var rgba = bgra
        for i in stride(from: 0, to: rgba.count, by: 4) {
            rgba.swapAt(i, i + 2)   // BGRA -> RGBA
        }
        guard let provider = CGDataProvider(data: Data(rgba) as CFData) else { return nil }
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false,
                       intent: .defaultIntent)
    }

    private static func writePNG(_ img: CGImage, to url: URL) {
        guard let dest = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, img, nil)
        CGImageDestinationFinalize(dest)
    }
}
