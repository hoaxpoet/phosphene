// TruchetLoomRhythmColourTests — PG.4.2 rhythm + colour gates.
//
// Exercises the live direct-pass path with SpectralHistory (buffer 5) carrying the
// flux EMA (slot 3390) + the beat_index counter (slot 3391), and FeatureVector
// (buffer 0) carrying beat_phase01 / pulse_amp01 / spectral_centroid / bass_dev.
//
// Gates:
//   1. Per-beat flips fire — and only when pulse_amp01 gates them on (cold-start /
//      silence at pulse_amp01 = 0 shows the static PG.4.1 weave).
//   2. Flips EVOLVE beat to beat (different beat_index → a different re-routed subset).
//   3. Steady global luminance across a beat (D-157 — flips swap orientation, they
//      don't add or remove net ink).
//   4. Hue teams shift with spectral_centroid (colour, not motion).
//   5. bass_dev drives a bounded glow on the freshly-subdivided ribbons.

import Testing
import Metal
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import Renderer
@testable import Presets
@testable import Shared

@Suite("Truchet Loom rhythm + colour (PG.4.2)")
struct TruchetLoomRhythmColourTests {

    private static let width = 512
    private static let height = 512

    // MARK: - Helpers

    private func preset() throws -> PresetLoader.LoadedPreset {
        guard let p = _acceptanceFixture.presets.first(where: { $0.descriptor.name == "Truchet Loom" })
        else { throw TLRCError.presetMissing }
        return p
    }

    /// A SpectralHistory buffer with the flux EMA + beat_index slots written directly.
    private func history(flux: Float, beatIndex: Float, ctx: MetalContext) -> MTLBuffer {
        let buf = ctx.makeSharedBuffer(length: 4096 * MemoryLayout<Float>.stride)!
        _ = buf.contents().initializeMemory(as: UInt8.self, repeating: 0,
                                             count: 4096 * MemoryLayout<Float>.stride)
        let ptr = buf.contents().assumingMemoryBound(to: Float.self)
        ptr[SpectralHistoryBuffer.offsetFluxSmoothed] = flux
        ptr[SpectralHistoryBuffer.offsetBeatIndex] = beatIndex
        return buf
    }

    private func render(_ preset: PresetLoader.LoadedPreset, ctx: MetalContext,
                        features: inout FeatureVector, hist: MTLBuffer) throws -> [UInt8] {
        let td = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: ctx.pixelFormat, width: Self.width, height: Self.height, mipmapped: false)
        td.usage = [.renderTarget, .shaderRead]; td.storageMode = .shared
        guard let tex = ctx.device.makeTexture(descriptor: td) else { throw TLRCError.metal }
        let fs = MemoryLayout<Float>.stride
        guard let fft = ctx.makeSharedBuffer(length: 512 * fs),
              let wav = ctx.makeSharedBuffer(length: 2048 * fs) else { throw TLRCError.metal }
        _ = fft.contents().initializeMemory(as: UInt8.self, repeating: 0, count: 512 * fs)
        _ = wav.contents().initializeMemory(as: UInt8.self, repeating: 0, count: 2048 * fs)
        features.aspectRatio = 1.0
        guard let cmd = ctx.commandQueue.makeCommandBuffer() else { throw TLRCError.metal }
        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = tex
        rpd.colorAttachments[0].loadAction = .clear
        rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        rpd.colorAttachments[0].storeAction = .store
        guard let enc = cmd.makeRenderCommandEncoder(descriptor: rpd) else { throw TLRCError.metal }
        enc.setRenderPipelineState(preset.pipelineState)
        enc.setFragmentBytes(&features, length: MemoryLayout<FeatureVector>.size, index: 0)
        enc.setFragmentBuffer(fft, offset: 0, index: 1)
        enc.setFragmentBuffer(wav, offset: 0, index: 2)
        enc.setFragmentBuffer(hist, offset: 0, index: 5)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding(); cmd.commit(); cmd.waitUntilCompleted()
        guard cmd.status == .completed else { throw TLRCError.metal }
        var px = [UInt8](repeating: 0, count: Self.width * Self.height * 4)
        tex.getBytes(&px, bytesPerRow: Self.width * 4,
                     from: MTLRegionMake2D(0, 0, Self.width, Self.height), mipmapLevel: 0)
        return px
    }

    private func luma(_ p: [UInt8], _ i: Int) -> Double {
        0.114 * Double(p[i]) + 0.587 * Double(p[i + 1]) + 0.299 * Double(p[i + 2])
    }
    private func meanLuma(_ p: [UInt8]) -> Double {
        var s = 0.0; for i in stride(from: 0, to: p.count, by: 4) { s += luma(p, i) }
        return s / Double(p.count / 4)
    }
    private func meanAbsDiff(_ a: [UInt8], _ b: [UInt8]) -> Double {
        var s = 0.0; for i in stride(from: 0, to: a.count, by: 4) { s += abs(luma(a, i) - luma(b, i)) }
        return s / Double(a.count / 4)
    }
    /// Mean hue angle (radians, chroma-weighted) — a colour-shift proxy.
    private func meanHueVector(_ p: [UInt8]) -> (x: Double, y: Double) {
        var vx = 0.0, vy = 0.0
        for i in stride(from: 0, to: p.count, by: 4) {
            let b = Double(p[i]) / 255, g = Double(p[i + 1]) / 255, r = Double(p[i + 2]) / 255
            let mx = max(r, g, b), mn = min(r, g, b), c = mx - mn
            if c < 0.05 { continue }
            var h = 0.0
            if mx == r { h = ((g - b) / c).truncatingRemainder(dividingBy: 6) }
            else if mx == g { h = (b - r) / c + 2 }
            else { h = (r - g) / c + 4 }
            h *= .pi / 3
            vx += c * cos(h); vy += c * sin(h)
        }
        return (vx, vy)
    }

    // MARK: - 1. Flips fire, gated by pulse_amp01

    @Test("Per-beat flips fire only when pulse_amp01 gates them on")
    func flipsGatedByPulseAmp() throws {
        let ctx = try MetalContext(); let p = try preset()
        let hist = history(flux: 0.0, beatIndex: 4, ctx: ctx)   // coarse; flips act on level-0 tiles

        var fvGated = FeatureVector.zero; fvGated.beatPhase01 = 0.7; fvGated.pulseAmp01 = 0.0
        var fvLive  = FeatureVector.zero; fvLive.beatPhase01  = 0.7; fvLive.pulseAmp01  = 1.0
        let gated = try render(p, ctx: ctx, features: &fvGated, hist: hist)
        let live  = try render(p, ctx: ctx, features: &fvLive,  hist: hist)

        let diff = meanAbsDiff(gated, live)
        print("[TruchetLoom PG.4.2] flip diff (pulse 0 vs 1) = \(diff)")
        #expect(diff > 2.0, "Flips did not fire when pulse_amp01 = 1 (diff \(diff))")
    }

    // MARK: - 2. Flips evolve beat to beat

    @Test("Re-routed subset evolves with beat_index")
    func flipsEvolveWithBeatIndex() throws {
        let ctx = try MetalContext(); let p = try preset()
        var fv = FeatureVector.zero; fv.beatPhase01 = 0.9; fv.pulseAmp01 = 1.0
        let a = try render(p, ctx: ctx, features: &fv, hist: history(flux: 0.0, beatIndex: 5, ctx: ctx))
        let b = try render(p, ctx: ctx, features: &fv, hist: history(flux: 0.0, beatIndex: 6, ctx: ctx))
        let diff = meanAbsDiff(a, b)
        print("[TruchetLoom PG.4.2] beat-to-beat evolution diff = \(diff)")
        #expect(diff > 2.0, "Consecutive beats re-route the same tiles (diff \(diff)) — not evolving")
    }

    // MARK: - 3. Steady global luminance across a beat (D-157)

    @Test("Global luminance stays steady across a beat (D-157)")
    func steadyLuminanceAcrossBeat() throws {
        let ctx = try MetalContext(); let p = try preset()
        let hist = history(flux: 0.0, beatIndex: 3, ctx: ctx)
        var lumas: [Double] = []
        for step in 0...8 {
            var fv = FeatureVector.zero
            fv.beatPhase01 = Float(step) / 8.0
            fv.pulseAmp01 = 1.0
            lumas.append(meanLuma(try render(p, ctx: ctx, features: &fv, hist: hist)))
        }
        let lo = lumas.min()!, hi = lumas.max()!, mean = lumas.reduce(0, +) / Double(lumas.count)
        let swing = (hi - lo) / mean
        print("[TruchetLoom PG.4.2] beat luminance swing = \(swing) (lo \(lo) hi \(hi) mean \(mean))")
        // Flips swap orientation (same ink); the only swing is the mid-flip crossfade
        // ghosting. Bounded well under a strobe (D-157 steady-luminance).
        #expect(swing < 0.18, "Beat luminance swing \(swing) too large — reads as a pulse/strobe, not a re-route")
    }

    // MARK: - 4. Hue teams shift with spectral_centroid

    @Test("Hue teams shift with spectral_centroid")
    func hueShiftsWithCentroid() throws {
        let ctx = try MetalContext(); let p = try preset()
        let hist = history(flux: 0.4, beatIndex: 0, ctx: ctx)   // some subdivision so ribbons are plentiful
        var fvLo = FeatureVector.zero; fvLo.spectralCentroid = 0.05
        var fvHi = FeatureVector.zero; fvHi.spectralCentroid = 0.80
        let lo = meanHueVector(try render(p, ctx: ctx, features: &fvLo, hist: hist))
        let hi = meanHueVector(try render(p, ctx: ctx, features: &fvHi, hist: hist))
        let d = hypot(lo.x - hi.x, lo.y - hi.y)
        print("[TruchetLoom PG.4.2] hue-vector shift low→high centroid = \(d)")
        #expect(d > 1.0, "Hue teams did not move with spectral_centroid (shift \(d))")
    }

    // MARK: - 5. bass_dev glow

    @Test("bass_dev drives a bounded glow on subdivided ribbons")
    func bassDevGlow() throws {
        let ctx = try MetalContext(); let p = try preset()
        let hist = history(flux: 0.9, beatIndex: 0, ctx: ctx)   // deep subdivision → high depthShade
        var fvOff = FeatureVector.zero
        var fvOn  = FeatureVector.zero; fvOn.bassDev = 1.0
        let off = meanLuma(try render(p, ctx: ctx, features: &fvOff, hist: hist))
        let on  = meanLuma(try render(p, ctx: ctx, features: &fvOn,  hist: hist))
        print("[TruchetLoom PG.4.2] glow luma off=\(off) on=\(on) delta=\(on - off)")
        // Subtle by design (a bounded accent on high-depth ribbons, whole-frame mean);
        // must be present + positive + bounded (not a strobe).
        #expect(on > off + 0.3, "bass_dev glow produced no brightening (\(off) → \(on))")
        #expect(on - off < 40.0, "Glow is unbounded — exceeds the D-157 bounded-accent budget")
    }
    // MARK: - 6. RENDER_VISUAL sheet

    @Test("PG.4.2 visual sheet — beat flips + hue teams + glow (RENDER_VISUAL=1)")
    func renderSheet() throws {
        guard ProcessInfo.processInfo.environment["RENDER_VISUAL"] == "1" else { return }
        let ctx = try MetalContext(); let p = try preset()
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let dir = URL(fileURLWithPath: "/tmp/phosphene_visual/\(stamp)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        func write(_ px: [UInt8], _ name: String) throws {
            let cs = CGColorSpace(name: CGColorSpace.sRGB)!
            let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue
                                    | CGBitmapInfo.byteOrder32Little.rawValue)
            var d = px
            guard let c = CGContext(data: &d, width: Self.width, height: Self.height,
                                    bitsPerComponent: 8, bytesPerRow: Self.width * 4,
                                    space: cs, bitmapInfo: info.rawValue), let img = c.makeImage(),
                  let dst = CGImageDestinationCreateWithURL(
                    dir.appendingPathComponent(name) as CFURL, UTType.png.identifier as CFString, 1, nil)
            else { throw TLRCError.metal }
            CGImageDestinationAddImage(dst, img, nil); _ = CGImageDestinationFinalize(dst)
            print("[TruchetLoom PG.4.2] wrote \(name)")
        }
        // Beat-flip sequence across one beat, subdivided weave (flux 0.5), pulse on.
        let hist = history(flux: 0.5, beatIndex: 7, ctx: ctx)
        for step in [0, 2, 4, 6] {
            var fv = FeatureVector.zero
            fv.beatPhase01 = Float(step) / 8.0; fv.pulseAmp01 = 1.0; fv.spectralCentroid = 0.4
            try write(try render(p, ctx: ctx, features: &fv, hist: hist),
                      String(format: "TruchetLoom_beat_phase_%.2f.png", Float(step) / 8.0))
        }
        // Hue-team variants at two centroids + a glow frame.
        for cen in [Float(0.1), 0.5, 0.9] {
            var fv = FeatureVector.zero; fv.spectralCentroid = cen
            try write(try render(p, ctx: ctx, features: &fv, hist: history(flux: 0.6, beatIndex: 0, ctx: ctx)),
                      String(format: "TruchetLoom_hue_centroid_%.1f.png", cen))
        }
        var glowFv = FeatureVector.zero; glowFv.bassDev = 1.2; glowFv.spectralCentroid = 0.5
        try write(try render(p, ctx: ctx, features: &glowFv, hist: history(flux: 0.9, beatIndex: 0, ctx: ctx)),
                  "TruchetLoom_glow_bassdev.png")
    }
}

private enum TLRCError: Error { case presetMissing, metal }
