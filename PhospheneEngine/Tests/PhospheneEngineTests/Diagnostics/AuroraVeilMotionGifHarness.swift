// AuroraVeilMotionGifHarness — watch the aurora DANCE (env-gated).
//
// Matt M7 (2026-07-14): "dancing diaphanous ribbons" is a MOTION property; a
// still cannot show it. This harness renders `aurora_fragment` over a time
// window, driving a synthetic musical envelope (a mid-activity swell so the
// curtain ripple visibly surges + settles) and a fixed bar phase (so the
// half-bar star blink fires), and writes an animated GIF via ImageIO — no
// ffmpeg, no external audio. It is NOT a real-music validation (that's the
// live M7 / a real-audio harness); it exists so the MOTION character can be
// eyeballed frame-to-frame while iterating the shader.
//
//   AURORA_GIF=1 swift test --package-path PhospheneEngine --filter AuroraVeilMotionGifHarness
// Output: /tmp/aurora_motion/aurora_dance.gif  (+ f0000.png … for frame reads)

import Testing
import Metal
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import Renderer
@testable import Presets
@testable import Shared

@Suite("Aurora Veil motion — dance GIF (env-gated)")
struct AuroraVeilMotionGifHarness {

    private enum E: Error { case setup, render }
    static let W = 640, H = 360
    static let fps = 24
    static let seconds = 6.0
    static let bpm = 120.0            // 4/4 → bar = 2 s → half-bar blink every 1 s

    @Test("Render Aurora Veil dancing → animated GIF")
    func renderDanceGif() throws {
        guard ProcessInfo.processInfo.environment["AURORA_GIF"] == "1" else {
            print("AuroraVeilMotionGifHarness: AURORA_GIF not set — skipping"); return
        }
        guard MTLCreateSystemDefaultDevice() != nil else {
            print("AuroraVeilMotionGifHarness: no Metal device — skipping"); return
        }
        let ctx = try MetalContext()
        let loader = PresetLoader(device: ctx.device, pixelFormat: ctx.pixelFormat, loadBuiltIn: true)
        guard let preset = loader.presets.first(where: { $0.descriptor.name == "Aurora Veil" }) else {
            print("AuroraVeilMotionGifHarness: Aurora Veil not found — skipping"); return
        }
        guard let avState = AuroraVeilState(device: ctx.device) else { throw E.setup }

        let dir = URL(fileURLWithPath: "/tmp/aurora_motion")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let floatStride = MemoryLayout<Float>.stride
        guard
            let fftBuf = ctx.makeSharedBuffer(length: 512 * floatStride),
            let wavBuf = ctx.makeSharedBuffer(length: 2048 * floatStride),
            let stemBuf = ctx.makeSharedBuffer(length: MemoryLayout<StemFeatures>.size),
            let histBuf = ctx.makeSharedBuffer(length: 4096 * floatStride)
        else { throw E.setup }

        let td = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: ctx.pixelFormat, width: Self.W, height: Self.H, mipmapped: false)
        td.usage = [.renderTarget, .shaderRead]; td.storageMode = .shared
        guard let tex = ctx.device.makeTexture(descriptor: td) else { throw E.setup }

        let frameCount = Int(Self.seconds * Double(Self.fps))
        let dt = Float(1.0 / Double(Self.fps))
        let barPeriod = Float(60.0 / Self.bpm * 4.0)   // seconds per bar (4/4)

        // GIF destination.
        let gifURL = dir.appendingPathComponent("aurora_dance.gif")
        guard let gif = CGImageDestinationCreateWithURL(
            gifURL as CFURL, UTType.gif.identifier as CFString, frameCount, nil) else { throw E.setup }
        let gifProps = [kCGImagePropertyGIFDictionary as String:
                            [kCGImagePropertyGIFLoopCount as String: 0]] as CFDictionary
        CGImageDestinationSetProperties(gif, gifProps)
        let frameProps = [kCGImagePropertyGIFDictionary as String:
                            [kCGImagePropertyGIFDelayTime as String: 1.0 / Double(Self.fps)]] as CFDictionary

        // Stems ON so stemMix→1 (enables the star blink); a mild steady bed.
        var stems = StemFeatures.zero
        stems.vocalsEnergy = 0.1; stems.drumsEnergy = 0.1
        stems.bassEnergy = 0.1;   stems.otherEnergy = 0.1
        stemBuf.contents().copyMemory(from: &stems, byteCount: MemoryLayout<StemFeatures>.size)

        for i in 0..<frameCount {
            let t = Float(i) * dt
            // Musical envelope: a swell every ~2 s so the ripple surges + calms.
            // midAttRel in roughly [-0.4, +0.95] → midActivity in [0.3, 0.98].
            let swell = 0.55 + 0.45 * sin(Double(t) * 2.0 * Double.pi / 2.0)
            var fv = FeatureVector(bass: 0.5, mid: Float(swell), treble: 0.4,
                                   time: t, deltaTime: dt)
            fv.midAttRel = Float(swell) * 1.4 - 0.45
            fv.barPhase01 = (t.truncatingRemainder(dividingBy: barPeriod)) / barPeriod
            fv.beatsPerBar = 4
            // A bass transient near each downbeat so the brightness breathes too.
            fv.bassDev = fv.barPhase01 < 0.12 ? 0.7 : 0.05

            avState.tick(deltaTime: dt, features: fv, stems: stems)

            guard let cmd = ctx.commandQueue.makeCommandBuffer() else { throw E.render }
            let rpd = MTLRenderPassDescriptor()
            rpd.colorAttachments[0].texture = tex
            rpd.colorAttachments[0].loadAction = .clear
            rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
            rpd.colorAttachments[0].storeAction = .store
            guard let enc = cmd.makeRenderCommandEncoder(descriptor: rpd) else { throw E.render }
            enc.setRenderPipelineState(preset.pipelineState)
            enc.setFragmentBytes(&fv, length: MemoryLayout<FeatureVector>.size, index: 0)
            enc.setFragmentBuffer(fftBuf, offset: 0, index: 1)
            enc.setFragmentBuffer(wavBuf, offset: 0, index: 2)
            enc.setFragmentBuffer(stemBuf, offset: 0, index: 3)
            enc.setFragmentBuffer(histBuf, offset: 0, index: 5)
            enc.setFragmentBuffer(avState.stateBuffer, offset: 0, index: 6)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            enc.endEncoding()
            cmd.commit(); cmd.waitUntilCompleted()
            guard cmd.status == .completed else { throw E.render }

            var px = [UInt8](repeating: 0, count: Self.W * Self.H * 4)
            tex.getBytes(&px, bytesPerRow: Self.W * 4,
                         from: MTLRegionMake2D(0, 0, Self.W, Self.H), mipmapLevel: 0)
            guard let img = Self.cgImage(bgra: px, w: Self.W, h: Self.H) else { throw E.render }
            CGImageDestinationAddImage(gif, img, frameProps)
            // Also dump a few PNGs for direct frame inspection.
            if i % 6 == 0 { Self.writePNG(img, to: dir.appendingPathComponent(String(format: "f%04d.png", i))) }
        }
        #expect(CGImageDestinationFinalize(gif), "GIF encode failed")
        print("[aurora_gif] wrote \(gifURL.path) (\(frameCount) frames @ \(Self.fps) fps)")
    }

    // BGRA bytes → CGImage (RGBA).
    private static func cgImage(bgra: [UInt8], w: Int, h: Int) -> CGImage? {
        var rgba = [UInt8](repeating: 0, count: bgra.count)
        for i in stride(from: 0, to: bgra.count, by: 4) {
            rgba[i] = bgra[i + 2]; rgba[i + 1] = bgra[i + 1]; rgba[i + 2] = bgra[i]; rgba[i + 3] = 255
        }
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let provider = CGDataProvider(data: Data(rgba) as CFData) else { return nil }
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: w * 4, space: cs,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    private static func writePNG(_ img: CGImage, to url: URL) {
        guard let dest = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, img, nil)
        _ = CGImageDestinationFinalize(dest)
    }
}
