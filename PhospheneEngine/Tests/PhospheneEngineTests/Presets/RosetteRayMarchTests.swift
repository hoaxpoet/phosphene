// RosetteRayMarchTests — the permanent multi-frame harness for Rosette (WHIT.2b).
//
// Replaces RosetteMVWarpAccumulationTest.swift, retired when Rosette converted from a
// flat 2D `direct + mv_warp` marks-on-top preset to a `ray_march` preset (Matt, live,
// right after the 2D version's continuity fix: "The final preset should also be 3D, not
// 2D, to take better advantage of the latest Apple processors"). Exercises the real
// production ray-march dispatch — `RayMarchPipeline.render` with Rosette's compiled
// `sceneSDF`/`sceneMaterial` (D-021 contract) — the same pattern
// `MultiPassRenderHarness.renderVolumetricLithograph` uses for the simplest existing
// ray-march preset.
//
// Tests:
//   - test_rosette_nonDegenerate — ALWAYS RUNS. Regression guard: the default render is
//     not a flat/empty frame.
//   - test_rosette_harmonyCoupling — tonalConsonance changes figure tightness; bassDev
//     changes stroke brightness.
//   - test_rosette_rotationAndSymmetryCoupling — tonalPhaseFifths rotates the figure;
//     harmonicFlux steps the symmetry order (settled, past WHIT.2a's transition window).
//   - test_rosette_curveIsContinuousAtHighA — BUG-104 regression guard, re-verified in 3D:
//     the swept tube at the loose/tangle end of the morph has no branch-lock gaps.
//   - test_rosette_visualDump — env-gated (ROSETTE_RAYMARCH_DIAG=1), for human tuning.

import Testing
import Foundation
import Metal
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import Renderer
@testable import Presets
@testable import Shared

@Suite("Rosette ray-march harness (WHIT.2b)")
struct RosetteRayMarchTests {

    private static let width = 960
    private static let height = 540

    // Must match Rosette.metal's kRosetteAMin / kRosetteAMax / kRosettePeriod
    // (triangle-wave morph clock — constant rate, no easing, §9.4).
    private static let aMin: Double = 0.05
    private static let aMax: Double = 1.80
    private static let period: Double = 30.0

    private static func timeForA(_ a: Double) -> Double {
        let tri = max(0.0, min(1.0, (a - aMin) / (aMax - aMin)))
        return tri * period / 2.0
    }

    // MARK: - Always-on regression guards

    @Test("Rosette: default render is non-degenerate")
    func test_rosette_nonDegenerate() throws {
        let pixels = try render(time: Self.timeForA(0.5))
        let (minL, maxL) = lumaRange(pixels)
        #expect(maxL - minL > 20,
                "Rosette default render is degenerate — luma range \(minL)-\(maxL), expected visible geometry")
    }

    @Test("Rosette: tonalConsonance sets figure tightness; bassDev boosts stroke presence")
    func test_rosette_harmonyCoupling() throws {
        let t0 = Self.timeForA(0.9)
        let atFloor = try render(time: t0, consonance: 0.0)
        let atP99 = try render(time: t0, consonance: 0.32)
        let diff = meanAbsDiff(atFloor, atP99)
        // Threshold calibrated against the actual 3D render (measured ~1.54): unlike the
        // retired 2D test's fullscreen fragment, most of a ray-marched frame is unlit void
        // + the two (unaffected-by-tightness) wing tubes, so the tightness-only delta is a
        // smaller fraction of the whole frame's meanAbsDiff. 1.0 sits comfortably below the
        // measured value and above float noise.
        #expect(diff > 1.0,
                "Rosette at t0=\(t0): consonance 0.0 vs 0.32 renders are near-identical (meanAbsDiff=\(diff)) — tonalConsonance may not be reaching the tightness mapping")

        let dim = try render(time: t0, consonance: 0.15, bassDev: 0.0)
        let bright = try render(time: t0, consonance: 0.15, bassDev: 1.0)
        #expect(meanLuma(bright) > meanLuma(dim),
                "Rosette bassDev=1.0 mean luma is not brighter than bassDev=0.0 — stroke_presence may not be reaching bassDev")
    }

    @Test("Rosette: tonalPhaseFifths rotates the figure; harmonicFlux steps the symmetry order")
    func test_rosette_rotationAndSymmetryCoupling() throws {
        let t0 = Self.timeForA(0.9)
        let unrotated = try render(time: t0, consonance: 0.15, tonalPhaseFifths: 0)
        let rotated = try render(time: t0, consonance: 0.15, tonalPhaseFifths: .pi / 2)
        let rotDiff = meanAbsDiff(unrotated, rotated)
        #expect(rotDiff > 2.0,
                "Rosette at t0=\(t0): tonalPhaseFifths=0 vs pi/2 renders are near-identical (meanAbsDiff=\(rotDiff)) — morph_position may not be reaching the figure rotation")

        // symmetry_order_step needs WHIT.2a's transition to settle (a single-tick render
        // can't observe it — the transition's first frame reports the pre-step value by
        // design). settleTicks(...) advances a state well past transitionDurationSeconds.
        let stateFive = try settledState(harmonicFluxOnFirstTick: 0)
        let stateSix = try settledState(harmonicFluxOnFirstTick: 1.0)
        #expect(stateFive.currentSymmetryN == RosetteState.symmetrySequence[0])
        #expect(stateSix.currentSymmetryN == RosetteState.symmetrySequence[1])
        let orderFive = try render(time: t0, consonance: 0.15, externalState: stateFive)
        let orderSix = try render(time: t0, consonance: 0.15, externalState: stateSix)
        let stepDiff = meanAbsDiff(orderFive, orderSix)
        // Threshold calibrated the same way as the tightness check above (measured ~1.74).
        #expect(stepDiff > 1.0,
                "Rosette at t0=\(t0): settled 5-fold vs settled 6-fold renders are near-identical (meanAbsDiff=\(stepDiff)) — symmetry_order_step may not be reaching rosetteDist's n")
    }

    @Test("Rosette: the tangle-state swept tube is continuous, no branch-lock gaps (BUG-104, re-verified in 3D)")
    func test_rosette_curveIsContinuousAtHighA() throws {
        // The tangle state (a=1.80) is where the pre-BUG-104 search used to lock onto a
        // single curve branch and leave gaps in the stroke — confirmed live via the 2D
        // fragment's diagnostic dump. `rosetteDist` (the fixed version) is reused
        // unmodified for the 3D tube's 2D distance component, so this exercises the exact
        // same code path at the exact same worst-case `a`.
        let pixels = try render(time: Self.period / 2.0)
        let (minL, maxL) = lumaRange(pixels)
        #expect(maxL - minL > 20,
                "Rosette tangle-state (a=1.80) render is degenerate — luma range \(minL)-\(maxL); rosetteDist may be locking onto a single curve branch again (BUG-104)")
    }

    // MARK: - Env-gated visual dump (human tuning)

    @Test("Rosette: visual dump for human review (env-gated)")
    func test_rosette_visualDump() throws {
        guard ProcessInfo.processInfo.environment["ROSETTE_RAYMARCH_DIAG"] == "1" else {
            print("RosetteRayMarchTests: ROSETTE_RAYMARCH_DIAG not set, skipping")
            return
        }
        let outDir = try makeOutputDir("rosette_raymarch_diag")
        print("[rosette-diag] output dir: \(outDir.path)")
        let targets: [(String, Double)] = [
            ("pentagon_a015", Self.timeForA(0.15)),
            ("star_a030", Self.timeForA(0.30)),
            ("petals_a075", Self.timeForA(0.75)),
            ("tangle_a180", Self.period / 2.0),
        ]
        for (name, t) in targets {
            let pixels = try render(time: t, width: 1920, height: 1080)
            try writePNG(pixels, width: 1920, height: 1080, to: outDir.appendingPathComponent("\(name).png"))
        }
    }

    // MARK: - Render (real ray-march dispatch, RayMarchPipeline.render)

    private func settledState(harmonicFluxOnFirstTick: Float) throws -> RosetteState {
        guard let device = MTLCreateSystemDefaultDevice(), let state = RosetteState(device: device) else {
            throw DiagError.setupFailed
        }
        let dt: Float = 1.0 / 60.0
        var fv = FeatureVector(time: 0, deltaTime: dt)
        fv.harmonicFlux = harmonicFluxOnFirstTick
        state.tick(deltaTime: dt, features: fv)
        let settleFrames = Int((RosetteState.transitionDurationSeconds / dt).rounded(.up)) + 5
        for _ in 1..<settleFrames {
            state.tick(deltaTime: dt, features: FeatureVector(time: 0, deltaTime: dt))
        }
        return state
    }

    private func render(
        time: Double, width: Int = RosetteRayMarchTests.width, height: Int = RosetteRayMarchTests.height,
        consonance: Float = 0, bassDev: Float = 0, midAttRel: Float = 0,
        tonalPhaseFifths: Float = 0, harmonicFlux: Float = 0,
        externalState: RosetteState? = nil
    ) throws -> [UInt8] {
        let ctx = try MetalContext()
        let lib = try ShaderLibrary(context: ctx)
        guard let preset = _acceptanceFixture.presets.first(where: { $0.descriptor.name == "Rosette" }) else {
            throw DiagError.presetNotFound
        }
        guard let gbufferState = preset.rayMarchPipelineState else {
            throw DiagError.setupFailed
        }
        let pipeline = try RayMarchPipeline(context: ctx, shaderLibrary: lib)
        pipeline.allocateTextures(width: width, height: height)
        var scene = preset.descriptor.makeSceneUniforms()
        scene.sceneParamsA.y = Float(width) / Float(height)
        pipeline.sceneUniforms = scene
        pipeline.ssgiEnabled = preset.descriptor.passes.contains(.ssgi)

        let ibl = try IBLManager(context: ctx, shaderLibrary: lib)
        let noise = try? TextureManager(context: ctx, shaderLibrary: lib)
        let floatStride = MemoryLayout<Float>.stride
        guard let fft = ctx.makeSharedBuffer(length: 512 * floatStride),
              let wav = ctx.makeSharedBuffer(length: 2048 * floatStride) else {
            throw DiagError.setupFailed
        }
        let texDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: ctx.pixelFormat, width: width, height: height, mipmapped: false)
        texDesc.usage = [.renderTarget, .shaderRead]
        texDesc.storageMode = .shared
        guard let outTex = ctx.device.makeTexture(descriptor: texDesc) else {
            throw DiagError.setupFailed
        }

        var fv = FeatureVector(time: Float(time), deltaTime: 1.0 / 60.0)
        fv.tonalConsonance = consonance
        fv.bassDev = bassDev
        fv.midAttRel = midAttRel
        fv.tonalPhaseFifths = tonalPhaseFifths
        fv.harmonicFlux = harmonicFlux

        // A fresh state per call + a single tick means the smoother is seeded straight
        // from this call's `tonalPhaseFifths` (no cross-frame carryover to worry about in
        // a single-frame test) — same convention the retired 2D harness used. Callers
        // observing the symmetry-order transition pass an already-settled `externalState`.
        let state: RosetteState
        if let externalState {
            state = externalState
        } else {
            guard let fresh = RosetteState(device: ctx.device) else { throw DiagError.setupFailed }
            state = fresh
            state.tick(deltaTime: 1.0 / 60.0, features: fv)
        }

        guard let cmd = ctx.commandQueue.makeCommandBuffer() else { throw DiagError.setupFailed }
        pipeline.render(
            gbufferPipelineState: gbufferState,
            features: &fv,
            fftBuffer: fft, waveformBuffer: wav,
            stemFeatures: StemFeatures.zero,
            outputTexture: outTex,
            commandBuffer: cmd,
            noiseTextures: noise,
            iblManager: ibl,
            postProcessChain: nil,
            presetFragmentBuffer1: state.rosetteBuffer
        )
        cmd.commit()
        cmd.waitUntilCompleted()

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        outTex.getBytes(&pixels, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        return pixels
    }

    // MARK: - Helpers

    private func lumaRange(_ pixels: [UInt8]) -> (Float, Float) {
        var minL: Float = 255, maxL: Float = 0
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let b = Float(pixels[i]), g = Float(pixels[i + 1]), r = Float(pixels[i + 2])
            let luma = 0.114 * b + 0.587 * g + 0.299 * r
            if luma < minL { minL = luma }
            if luma > maxL { maxL = luma }
        }
        return (minL, maxL)
    }

    private func meanLuma(_ pixels: [UInt8]) -> Double {
        var sum: Double = 0
        var n = 0
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let b = Double(pixels[i]), g = Double(pixels[i + 1]), r = Double(pixels[i + 2])
            sum += 0.114 * b + 0.587 * g + 0.299 * r
            n += 1
        }
        return sum / Double(n)
    }

    private func meanAbsDiff(_ a: [UInt8], _ b: [UInt8]) -> Double {
        var sum: Double = 0
        for i in 0..<a.count { sum += Double(abs(Int(a[i]) - Int(b[i]))) }
        return sum / Double(a.count)
    }

    private func makeOutputDir(_ name: String) throws -> URL {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withColonSeparatorInTime]
        let stamp = iso.string(from: Date())
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
        let url = URL(fileURLWithPath: "/tmp/\(name)/\(stamp)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writePNG(_ pixels: [UInt8], width: Int, height: Int, to url: URL) throws {
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
              let img = CGImage(width: width, height: height,
                                bitsPerComponent: 8, bitsPerPixel: 32,
                                bytesPerRow: width * 4,
                                space: cs, bitmapInfo: CGBitmapInfo(rawValue: info),
                                provider: provider, decode: nil, shouldInterpolate: false,
                                intent: .defaultIntent)
        else { throw DiagError.setupFailed }
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
            throw DiagError.setupFailed
        }
        CGImageDestinationAddImage(dest, img, nil)
        CGImageDestinationFinalize(dest)
    }
}

private enum DiagError: Error {
    case presetNotFound
    case setupFailed
}
