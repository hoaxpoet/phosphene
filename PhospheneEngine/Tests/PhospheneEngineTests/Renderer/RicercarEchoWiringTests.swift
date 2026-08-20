// RicercarEchoWiringTests — the regression gate for RICERCAR-WIRE.1.
//
// Ricercar's app geometry changed from `RicercarFlowGeometry` (FL.10 particle flow-field) to
// `RicercarEchoGeometry` (onset-driven gestural marks). The echo prototype had lived in a test
// harness for six weeks — `RicercarFluidVideoHarness`, env-gated behind `RICERCAR_ECHO=1`, so
// it ran in CI exactly never. Wiring it into the app without an ungated test would have kept
// that property: the app would build, the preset would resolve, and nobody would find out the
// shader had stopped compiling until Matt selected Ricercar and got nothing.
//
// So this proves the three things the wiring actually depends on, through the PRODUCTION
// ShaderLibrary rather than a test-local one:
//   1. `RicercarEcho.metal` compiles and its pipelines build.
//   2. Marks are DRAWN — onsets in, lit pixels out.
//   3. The instrument-family colour path is live: `StemFeatures.*Activity` reaches the picture.
//
// It does NOT judge the look — that is Matt's eye on the real-audio video, per the preset's
// own rule that the gate is the rendered clip and not a metric.

import Testing
import Metal
import Foundation
@testable import Renderer
@testable import Shared

// MARK: - RicercarEchoWiringTests

@Suite("Ricercar echo — app wiring (RICERCAR-WIRE.1)")
struct RicercarEchoWiringTests {

    private enum E: Error { case setup, render }
    static let w = 640, h = 360

    // MARK: - Harness

    private func target(_ ctx: MetalContext) throws -> MTLTexture {
        let d = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: ctx.pixelFormat, width: Self.w, height: Self.h, mipmapped: false)
        d.usage = [.renderTarget, .shaderRead]
        guard let t = ctx.device.makeTexture(descriptor: d) else { throw E.setup }
        return t
    }

    /// Drive one frame and return the framebuffer.
    private func frame(_ geo: RicercarEchoGeometry, _ f: FeatureVector, _ s: StemFeatures,
                       _ tex: MTLTexture, _ ctx: MetalContext) throws -> [UInt8] {
        guard let cmd = ctx.commandQueue.makeCommandBuffer() else { throw E.setup }
        geo.update(features: f, stemFeatures: s, commandBuffer: cmd)
        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = tex
        rpd.colorAttachments[0].loadAction = .clear
        rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0.015, green: 0.017, blue: 0.04, alpha: 1)
        rpd.colorAttachments[0].storeAction = .store
        guard let enc = cmd.makeRenderCommandEncoder(descriptor: rpd) else { throw E.render }
        geo.render(encoder: enc, features: f)
        enc.endEncoding()
        cmd.commit()
        cmd.waitUntilCompleted()
        var px = [UInt8](repeating: 0, count: Self.w * Self.h * 4)
        tex.getBytes(&px, bytesPerRow: Self.w * 4,
                     from: MTLRegionMake2D(0, 0, Self.w, Self.h), mipmapLevel: 0)
        return px
    }

    /// Pixels meaningfully above the clear colour — i.e. something was drawn.
    private func litPixels(_ px: [UInt8]) -> Int {
        var n = 0
        for i in stride(from: 0, to: px.count, by: 4) {
            let lum = 0.299 * Double(px[i + 2]) + 0.587 * Double(px[i + 1]) + 0.114 * Double(px[i])
            if lum > 40 { n += 1 }
        }
        return n
    }

    /// A rising band level produces the RELATIVE local transient the onset detector fires on.
    /// The detector is deliberately relative, so a step from quiet to loud is what it wants.
    private func drive(frames: Int, onsetEvery: Int) -> [FeatureVector] {
        (0..<frames).map { i in
            let hit = (i % onsetEvery) < 2
            var f = FeatureVector(bass: hit ? 0.85 : 0.06,
                                  mid: hit ? 0.80 : 0.05,
                                  treble: hit ? 0.70 : 0.04,
                                  time: Float(i) / 60.0, deltaTime: 1.0 / 60.0)
            f.trackElapsedS = Float(i) / 60.0
            f.aspectRatio = Float(Self.w) / Float(Self.h)
            return f
        }
    }

    private func stem(strings: Float = 0, brass: Float = 0) -> StemFeatures {
        var s = StemFeatures.zero
        s.stringsActivity = strings; s.stringsActivityDev = strings
        s.brassActivity = brass; s.brassActivityDev = brass
        return s
    }

    // MARK: - Tests

    /// 1 + 2. The shader compiles through the production library and onsets put marks on screen.
    @Test("the echo geometry builds from the production library and draws marks on onsets")
    func buildsAndDraws() throws {
        let ctx = try MetalContext()
        let lib = try ShaderLibrary(context: ctx)
        let geo = try RicercarEchoGeometry(
            device: ctx.device, library: lib.library,
            configuration: RicercarEchoConfiguration(width: Self.w, height: Self.h),
            pixelFormat: ctx.pixelFormat)
        let tex = try target(ctx)

        var peak = 0
        for f in drive(frames: 240, onsetEvery: 20) {
            peak = max(peak, litPixels(try frame(geo, f, stem(strings: 0.8), tex, ctx)))
        }
        #expect(peak > 200, "no marks drawn over 240 frames of onsets — peak lit \(peak); either RicercarEcho.metal stopped compiling or the onset path is dead")
    }

    /// 3. The instrument-family colour path reaches the picture. Two runs identical except for
    /// WHICH family is active must not render the same pixels — if they do, `StemFeatures`
    /// activity is being read and then dropped somewhere before the colour, which is exactly
    /// the failure mode that hid for six weeks behind absent PANNs weights (family: 0 windows
    /// → colour silently falls back and every render looks plausible).
    @Test("instrument-family activity changes the picture, not just the inputs")
    func familyColourReachesThePicture() throws {
        let ctx = try MetalContext()
        let lib = try ShaderLibrary(context: ctx)
        let tex = try target(ctx)

        func run(_ s: StemFeatures) throws -> [UInt8] {
            let geo = try RicercarEchoGeometry(
                device: ctx.device, library: lib.library,
                configuration: RicercarEchoConfiguration(width: Self.w, height: Self.h),
                pixelFormat: ctx.pixelFormat)
            var last = [UInt8]()
            for f in drive(frames: 180, onsetEvery: 20) { last = try frame(geo, f, s, tex, ctx) }
            return last
        }

        let strings = try run(stem(strings: 0.9))
        let brass = try run(stem(brass: 0.9))

        // Compare the colour BALANCE rather than pixel equality: mark placement is driven by the
        // same deterministic onset stream in both runs, so a colour difference shows up as a
        // channel-ratio difference across the whole frame.
        func balance(_ px: [UInt8]) -> Double {
            var r = 0.0, b = 0.0
            for i in stride(from: 0, to: px.count, by: 4) { b += Double(px[i]); r += Double(px[i + 2]) }
            return b > 0 ? r / b : 0
        }
        let bs = balance(strings), bb = balance(brass)
        #expect(abs(bs - bb) > 0.02, "strings and brass render the same colour balance (\(bs) vs \(bb)) — family activity is not reaching the marks' colour")
    }
}
