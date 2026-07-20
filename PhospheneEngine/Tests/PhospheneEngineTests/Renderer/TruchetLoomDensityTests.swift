// TruchetLoomDensityTests — PG.4.1 density-mapping + smoothing + drift gates.
//
// Exercises the SAME direct-pass dispatch the live app uses (fullscreen preset
// fragment, FeatureVector at buffer(0), SpectralHistory at buffer(5)) across
// multiple frames, driving the smoothed-flux HERO through the real
// `SpectralHistoryBuffer.append()` write path — not a hand-poked uniform.
//
// Gates:
//   1. Density hero: a low-flux run renders a COARSE weave and a high-flux run
//      renders a SUBDIVIDED (higher edge-density) weave — busyness → nesting.
//   2. Smoothing / no-flicker: a spiky per-frame flux produces a bounded
//      frame-to-frame change in the smoothed level (the raw flux would jump 1.0).
//   3. Drift: two frames at the same density but different f.time differ (flow).
//
// RENDER_VISUAL=1 also writes a flux-sweep contact strip (level 0→3) to
// /tmp/phosphene_visual/<stamp>/ so the subdivision morph can be eyeballed.

import Testing
import Metal
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import Renderer
@testable import Presets
@testable import Shared

@Suite("Truchet Loom density mapping (PG.4.1)")
struct TruchetLoomDensityTests {

    private static let width = 512
    private static let height = 512

    // MARK: - Helpers

    private func truchetPreset() throws -> PresetLoader.LoadedPreset {
        guard let preset = _acceptanceFixture.presets.first(where: {
            $0.descriptor.name == "Truchet Loom"
        }) else {
            throw TLError.presetMissing
        }
        return preset
    }

    /// Render the Truchet direct fragment into a BGRA buffer. `hist` is the
    /// SpectralHistory buffer bound at slot 5 (carries the smoothed-flux EMA).
    private func render(
        preset: PresetLoader.LoadedPreset,
        context: MetalContext,
        features: inout FeatureVector,
        hist: MTLBuffer,
        width: Int = width,
        height: Int = height
    ) throws -> [UInt8] {
        let texDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: context.pixelFormat, width: width, height: height, mipmapped: false)
        texDesc.usage = [.renderTarget, .shaderRead]
        texDesc.storageMode = .shared
        guard let texture = context.device.makeTexture(descriptor: texDesc) else { throw TLError.metal }

        let floatStride = MemoryLayout<Float>.stride
        guard
            let fft = context.makeSharedBuffer(length: 512 * floatStride),
            let wav = context.makeSharedBuffer(length: 2048 * floatStride)
        else { throw TLError.metal }
        _ = fft.contents().initializeMemory(as: UInt8.self, repeating: 0, count: 512 * floatStride)
        _ = wav.contents().initializeMemory(as: UInt8.self, repeating: 0, count: 2048 * floatStride)

        features.aspectRatio = Float(width) / Float(height)

        guard let cmd = context.commandQueue.makeCommandBuffer() else { throw TLError.metal }
        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = texture
        rpd.colorAttachments[0].loadAction = .clear
        rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        rpd.colorAttachments[0].storeAction = .store
        guard let enc = cmd.makeRenderCommandEncoder(descriptor: rpd) else { throw TLError.metal }
        enc.setRenderPipelineState(preset.pipelineState)
        enc.setFragmentBytes(&features, length: MemoryLayout<FeatureVector>.size, index: 0)
        enc.setFragmentBuffer(fft, offset: 0, index: 1)
        enc.setFragmentBuffer(wav, offset: 0, index: 2)
        enc.setFragmentBuffer(hist, offset: 0, index: 5)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
        cmd.commit()
        cmd.waitUntilCompleted()
        guard cmd.status == .completed else { throw TLError.metal }

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        texture.getBytes(&pixels, bytesPerRow: width * 4,
                         from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        return pixels
    }

    /// A SpectralHistory buffer whose smoothed-flux EMA has converged to `target`
    /// by replaying the real `append()` write path for ~2 s of frames.
    private func historyConverged(to target: Float, context: MetalContext) -> SpectralHistoryBuffer {
        let history = SpectralHistoryBuffer(device: context.device)
        var fv = FeatureVector.zero
        fv.spectralFlux = target
        fv.deltaTime = 1.0 / 60.0
        for _ in 0..<180 { history.append(features: fv, stems: .zero) }
        return history
    }

    private func luma(_ px: [UInt8], _ i: Int) -> Double {
        // BGRA byte order.
        0.114 * Double(px[i]) + 0.587 * Double(px[i + 1]) + 0.299 * Double(px[i + 2])
    }

    /// Mean absolute luma gradient — a resolution-stable proxy for how much fine
    /// path detail the frame carries. A subdivided weave has more, finer arcs →
    /// more edges per row → a higher score.
    private func edgeDensity(_ px: [UInt8], width: Int = width, height: Int = height) -> Double {
        var sum = 0.0
        for y in 0..<height {
            for x in 0..<(width - 1) {
                let i = (y * width + x) * 4
                sum += abs(luma(px, i + 4) - luma(px, i))
            }
        }
        return sum / Double(width * height)
    }

    private func meanAbsDiff(_ a: [UInt8], _ b: [UInt8]) -> Double {
        var sum = 0.0
        for i in stride(from: 0, to: a.count, by: 4) {
            sum += abs(luma(a, i) - luma(b, i))
        }
        return sum / Double(a.count / 4)
    }

    // MARK: - 1. Density hero

    @Test("Busy music (high smoothed flux) subdivides the weave; sparse stays coarse")
    func densityMapsToSubdivision() throws {
        let ctx = try MetalContext()
        let preset = try truchetPreset()

        let low = historyConverged(to: 0.05, context: ctx)   // sparse
        let high = historyConverged(to: 0.75, context: ctx)  // busy

        var fvLow = FeatureVector.zero;  fvLow.time = 2.0
        var fvHigh = FeatureVector.zero; fvHigh.time = 2.0

        let pxLow = try render(preset: preset, context: ctx, features: &fvLow, hist: low.gpuBuffer)
        let pxHigh = try render(preset: preset, context: ctx, features: &fvHigh, hist: high.gpuBuffer)

        let dLow = edgeDensity(pxLow)
        let dHigh = edgeDensity(pxHigh)
        print("[TruchetLoom] edgeDensity  low(flux=0.05)=\(dLow)  high(flux=0.75)=\(dHigh)  ratio=\(dHigh / dLow)")

        // Busy must carry visibly more fine detail than sparse — the density hero.
        #expect(dHigh > dLow * 1.30,
                "Density hero dead: high-flux edge density \(dHigh) not > 1.30× low-flux \(dLow)")
        // Both must be non-black (D-037 floor + a live weave at either end).
        #expect(dLow > 0.5, "Coarse weave is nearly flat — expected visible arcs")
    }

    // MARK: - 2. Smoothing / no-flicker

    @Test("Smoothed flux level is bounded frame-to-frame under a spiky input")
    func smoothingBoundsFrameJerk() throws {
        let ctx = try MetalContext()
        let history = SpectralHistoryBuffer(device: ctx.device)
        let ptr = history.gpuBuffer.contents().assumingMemoryBound(to: Float.self)

        var prev = ptr[SpectralHistoryBuffer.offsetFluxSmoothed]
        var maxDelta: Float = 0
        var fv = FeatureVector.zero
        fv.deltaTime = 1.0 / 60.0
        // Worst case: full-scale flux alternating every frame (raw jump = 1.0/frame).
        for i in 0..<120 {
            fv.spectralFlux = (i % 2 == 0) ? 1.0 : 0.0
            history.append(features: fv, stems: .zero)
            let now = ptr[SpectralHistoryBuffer.offsetFluxSmoothed]
            maxDelta = max(maxDelta, abs(now - prev))
            prev = now
        }
        print("[TruchetLoom] max smoothed-flux frame delta under alternating 0/1 = \(maxDelta) (raw would be 1.0)")

        // τ≈0.35 s at 60 fps ⇒ α≈0.047 ⇒ step ≤ α·1.0. Well under a tenth of the raw jump.
        #expect(maxDelta < 0.06,
                "Smoother too loose: frame delta \(maxDelta) — the level would flicker")
        #expect(maxDelta > 0.0, "Smoother inert — flux never reached the level slot")
    }

    // MARK: - 3. Drift

    @Test("Weave drifts continuously over time at constant density")
    func driftsOverTime() throws {
        let ctx = try MetalContext()
        let preset = try truchetPreset()
        let hist = historyConverged(to: 0.3, context: ctx)   // constant density

        var fv0 = FeatureVector.zero; fv0.time = 0.0
        var fv1 = FeatureVector.zero; fv1.time = 3.0
        let a = try render(preset: preset, context: ctx, features: &fv0, hist: hist.gpuBuffer)
        let b = try render(preset: preset, context: ctx, features: &fv1, hist: hist.gpuBuffer)

        let diff = meanAbsDiff(a, b)
        print("[TruchetLoom] drift mean abs luma diff (t=0 vs t=3) = \(diff)")
        #expect(diff > 3.0, "No drift: frames at t=0 and t=3 are near-identical (\(diff))")
    }

    // MARK: - 4. Flux-sweep contact strip (RENDER_VISUAL=1)

    @Test("Flux-sweep contact strip (RENDER_VISUAL=1)")
    func renderFluxSweep() throws {
        guard ProcessInfo.processInfo.environment["RENDER_VISUAL"] == "1" else { return }
        let ctx = try MetalContext()
        let preset = try truchetPreset()

        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let dir = URL(fileURLWithPath: "/tmp/phosphene_visual/\(stamp)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // Sweep smoothed-flux directly across its [0,1] range so the level walks
        // 0.4 → 3.0 and the subdivision morph is visible frame to frame.
        for flux in stride(from: Float(0.0), through: 1.0, by: 0.2) {
            let history = historyConverged(to: flux, context: ctx)
            var fv = FeatureVector.zero; fv.time = 2.0
            let px = try render(preset: preset, context: ctx,
                                features: &fv, hist: history.gpuBuffer,
                                width: 900, height: 900)
            let url = dir.appendingPathComponent(String(format: "TruchetLoom_flux_%.1f.png", flux))
            try writePNG(bgra: px, width: 900, height: 900, to: url)
            print("[TruchetLoom] wrote \(url.lastPathComponent)")
        }
    }

    // MARK: - PNG

    private func writePNG(bgra: [UInt8], width: Int, height: Int, to url: URL) throws {
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let info = CGBitmapInfo(rawValue:
            CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        var data = bgra
        guard let ctx = CGContext(data: &data, width: width, height: height,
                                  bitsPerComponent: 8, bytesPerRow: width * 4,
                                  space: cs, bitmapInfo: info.rawValue),
              let img = ctx.makeImage(),
              let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw TLError.metal }
        CGImageDestinationAddImage(dest, img, nil)
        guard CGImageDestinationFinalize(dest) else { throw TLError.metal }
    }
}

private enum TLError: Error { case presetMissing, metal }
