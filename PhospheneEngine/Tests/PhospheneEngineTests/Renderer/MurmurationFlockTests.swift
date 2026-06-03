// MurmurationFlockTests — Phase MM.2 flock-engine harness.
//
// Exercises the REAL dispatch path (reset → bin → boids compute, then the point
// render) per the "test in production-grade pipeline" rule — single-frame
// shader-state checks are not sufficient for a temporal-behaviour preset.
//
// Two always-on assertions:
//   1. The engine library compiles + all `murmuration_*` pipelines build
//      (constructing the geometry compiles the MSL — a syntax error in
//      MurmurationFlock.metal fails the whole engine library here).
//   2. The SILENCE BASELINE is cohesive, bounded, flying, and core-dense — the
//      MM.2 gate. No audio coupling yet.
//
// Under RENDER_VISUAL=1 it also renders the flock over a dusk-sky clear and
// writes PNG frames to tools/murmuration_reference/frames/mm2_silence_*.png for
// Matt's visual review (the load-bearing M-gate for "reads as a murmuration").

import Testing
import Metal
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Foundation
@testable import Renderer
@testable import Shared

// MARK: - Helpers

private enum FlockTestError: Error { case metalSetupFailed, renderFailed, pngFailed }

private func silenceFeatures(time: Float) -> FeatureVector {
    FeatureVector(time: time, deltaTime: 1.0 / 60.0)
}

@discardableResult
private func stepFlock(
    _ geometry: MurmurationFlockGeometry,
    time: Float,
    queue: MTLCommandQueue
) throws -> MTLCommandBuffer {
    guard let cmd = queue.makeCommandBuffer() else { throw FlockTestError.metalSetupFailed }
    geometry.update(features: silenceFeatures(time: time), stemFeatures: .zero, commandBuffer: cmd)
    cmd.commit()
    cmd.waitUntilCompleted()
    return cmd
}

private struct FlockMetrics {
    let count: Int
    let centroid: SIMD3<Float>
    let rmsRadius: Float
    let maxRadius: Float
    let coreFraction: Float       // fraction of birds within 0.5 × 95th-pctile radius
    let meanSpeed: Float
    let anyNonFinite: Bool

    static func measure(_ geometry: MurmurationFlockGeometry) -> FlockMetrics {
        let count = geometry.configuration.particleCount
        let ptr = geometry.birdBuffer.contents().bindMemory(to: MurmurationBird.self, capacity: count)
        var c = SIMD3<Float>(0, 0, 0)
        var speed: Float = 0
        var bad = false
        for i in 0..<count {
            let b = ptr[i]
            let p = SIMD3<Float>(b.positionX, b.positionY, b.positionZ)
            if !p.x.isFinite || !p.y.isFinite || !p.z.isFinite { bad = true }
            c += p
            speed += (SIMD3<Float>(b.velocityX, b.velocityY, b.velocityZ)).magnitude3
        }
        let n = Float(count)
        c /= n
        var dists = [Float](); dists.reserveCapacity(count)
        var sumSq: Float = 0
        for i in 0..<count {
            let b = ptr[i]
            let d = SIMD3<Float>(b.positionX, b.positionY, b.positionZ) - c
            let dist = d.magnitude3
            dists.append(dist)
            sumSq += dist * dist
        }
        dists.sort()
        let p95 = dists[min(count - 1, Int(0.95 * Float(count)))]
        let half = 0.5 * p95
        var core = 0
        for d in dists where d <= half { core += 1 }
        return FlockMetrics(
            count: count,
            centroid: c,
            rmsRadius: (sumSq / n).squareRoot(),
            maxRadius: dists.last ?? 0,
            coreFraction: Float(core) / n,
            meanSpeed: speed / n,
            anyNonFinite: bad
        )
    }
}

private extension SIMD3 where Scalar == Float {
    var magnitude3: Float { (x * x + y * y + z * z).squareRoot() }
}

// MARK: - Tests

@Suite("Murmuration flock engine (MM.2)")
struct MurmurationFlockTests {

    @Test("Engine library compiles + flock pipelines build")
    func test_compilesAndBuilds() throws {
        let ctx = try MetalContext()
        let lib = try ShaderLibrary(context: ctx)
        // Constructing the geometry compiles murmuration_reset_cells / _bin /
        // _boids — a MSL error in MurmurationFlock.metal throws here.
        _ = try MurmurationFlockGeometry(
            device: ctx.device, library: lib.library,
            configuration: .init(particleCount: 2_000)
        )
    }

    @Test("Silence baseline: cohesive, bounded, flying, core-dense, no fragmentation")
    func test_silenceBaseline() throws {
        let ctx = try MetalContext()
        let lib = try ShaderLibrary(context: ctx)
        let cfg = MurmurationFlockConfiguration()
        let geo = try MurmurationFlockGeometry(device: ctx.device, library: lib.library, configuration: cfg)

        // Run 30 s (the MM.2b fragmentation split appeared ~25 s in, so the
        // earlier 4 s test missed it). Sample core density throughout — a split
        // drops it because the centroid falls into the empty gap between clusters.
        var t: Float = 0
        var prevCentroid = SIMD3<Float>(0, 0, 0)
        var minCore: Float = 1
        var maxR: Float = 0
        var maxCentroidDist: Float = 0      // |centroid| from origin — must stay on-screen
        var sawDrift = false
        var lastMeanSpeed: Float = 0
        var lastBad = false
        for frame in 0..<1800 {
            try stepFlock(geo, time: t, queue: ctx.commandQueue); t += 1.0 / 60.0
            if frame % 120 == 0 && frame > 120 {       // sample every 2 s after settle
                let m = FlockMetrics.measure(geo)
                minCore = min(minCore, m.coreFraction)
                maxR = max(maxR, m.maxRadius)
                maxCentroidDist = max(maxCentroidDist, m.centroid.magnitude3)
                lastMeanSpeed = m.meanSpeed
                lastBad = lastBad || m.anyNonFinite
                if (m.centroid - prevCentroid).magnitude3 > 0.002 { sawDrift = true }
                prevCentroid = m.centroid
            }
        }
        print("""
        [MM.2 silence/30s] count=\(cfg.particleCount) \
        minCoreFrac=\(String(format: "%.3f", minCore)) \
        maxR=\(String(format: "%.3f", maxR)) \
        maxCentroidDist=\(String(format: "%.3f", maxCentroidDist)) \
        meanSpeed=\(String(format: "%.3f", lastMeanSpeed)) drift=\(sawDrift)
        """)

        #expect(!lastBad, "positions must stay finite over 30 s")
        #expect(maxR < cfg.worldHalfSpan * 1.6, "flock must not disperse past the world, maxR=\(maxR)")
        #expect(lastMeanSpeed > cfg.minSpeed * 0.7, "birds must keep flying")
        #expect(sawDrift, "flock should drift (not frozen)")
        // No fragmentation: core density must stay denser-than-uniform for the
        // WHOLE 30 s. A persistent split would drop minCore toward 0.
        #expect(minCore > 0.16, "flock must stay one cohesive mass (no split), minCoreFrac=\(minCore)")
        // Stays on-screen: the flock must not wander off into the distance.
        #expect(maxCentroidDist < 0.8, "flock must stay framed (centroid near origin), got \(maxCentroidDist)")
    }

    @Test("Render silence-baseline frames (RENDER_VISUAL=1)")
    func test_renderSilenceFrames() throws {
        guard ProcessInfo.processInfo.environment["RENDER_VISUAL"] == "1" else {
            print("[MM.2] RENDER_VISUAL not set — skipping frame render")
            return
        }
        let ctx = try MetalContext()
        let lib = try ShaderLibrary(context: ctx)
        let cfg = MurmurationFlockConfiguration()
        let geo = try MurmurationFlockGeometry(
            device: ctx.device, library: lib.library, configuration: cfg,
            pixelFormat: ctx.pixelFormat
        )

        let w = 960, h = 540
        let texDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: ctx.pixelFormat, width: w, height: h, mipmapped: false)
        texDesc.usage = [.renderTarget, .shaderRead]
        texDesc.storageMode = .shared
        guard let tex = ctx.device.makeTexture(descriptor: texDesc) else { throw FlockTestError.renderFailed }

        let outDir = Self.repoRoot()
            .appendingPathComponent("tools/murmuration_reference/frames", isDirectory: true)
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        var t: Float = 0
        // Settle.
        for _ in 0..<180 { try stepFlock(geo, time: t, queue: ctx.commandQueue); t += 1.0 / 60.0 }
        // Capture 6 frames spread over ~24 s (so late frames cover the window
        // where MM.2b used to fragment).
        for frame in 0..<6 {
            for _ in 0..<240 { try stepFlock(geo, time: t, queue: ctx.commandQueue); t += 1.0 / 60.0 }
            try renderFrame(geo: geo, features: silenceFeatures(time: t), tex: tex, ctx: ctx)
            let pixels = readBack(tex, w: w, h: h)
            let url = outDir.appendingPathComponent(String(format: "mm2_silence_%02d.png", frame))
            try writePNG(bgra: pixels, w: w, h: h, to: url)
            print("[MM.2] wrote \(url.path)")
        }
    }

    // MARK: - Render helpers

    private func renderFrame(
        geo: MurmurationFlockGeometry, features: FeatureVector, tex: MTLTexture, ctx: MetalContext
    ) throws {
        guard let cmd = ctx.commandQueue.makeCommandBuffer() else { throw FlockTestError.renderFailed }
        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = tex
        rpd.colorAttachments[0].loadAction = .clear
        // Dusk-sky clear for contrast (the real sky fragment lands in MM.4).
        rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0.55, green: 0.62, blue: 0.72, alpha: 1)
        rpd.colorAttachments[0].storeAction = .store
        guard let enc = cmd.makeRenderCommandEncoder(descriptor: rpd) else { throw FlockTestError.renderFailed }
        geo.render(encoder: enc, features: features)
        enc.endEncoding()
        cmd.commit()
        cmd.waitUntilCompleted()
        guard cmd.status == .completed else { throw FlockTestError.renderFailed }
    }

    private func readBack(_ tex: MTLTexture, w: Int, h: Int) -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        tex.getBytes(&pixels, bytesPerRow: w * 4, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        return pixels
    }

    private static func repoRoot() -> URL {
        // .../PhospheneEngine/Tests/PhospheneEngineTests/Renderer/<this>.swift
        var u = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { u.deleteLastPathComponent() }
        return u
    }

    private func writePNG(bgra: [UInt8], w: Int, h: Int, to url: URL) throws {
        guard let cs = CGColorSpace(name: CGColorSpace.sRGB) else { throw FlockTestError.pngFailed }
        let info = CGBitmapInfo(rawValue:
            CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        var copy = bgra
        let image: CGImage? = copy.withUnsafeMutableBytes { ptr in
            guard let base = ptr.baseAddress,
                  let cg = CGContext(data: base, width: w, height: h, bitsPerComponent: 8,
                                     bytesPerRow: w * 4, space: cs, bitmapInfo: info.rawValue)
            else { return nil }
            return cg.makeImage()
        }
        guard let cgImage = image,
              let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw FlockTestError.pngFailed }
        CGImageDestinationAddImage(dest, cgImage, nil)
        guard CGImageDestinationFinalize(dest) else { throw FlockTestError.pngFailed }
    }
}
