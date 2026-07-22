// CymaticResonanceVisualTests — production-path render + embodiment + perf gate
// for the Cymatic Resonance preset (CR.1).
//
// Cymatic Resonance is `direct` + `post_process` with slot-6 CPU state — a path
// no prior preset used, so its dispatch (runScenePass → bright → blur → composite,
// with the mode-ladder state bound at fragment buffer 6 via `presetFragmentBuffer`)
// has no coverage in the name-keyed PresetVisualReview harness (whose plain direct
// path renders to the drawable format, mismatching CR's `.rgba16Float` scene-pass
// pipeline). This suite exercises the REAL `PostProcessChain.render(...)` path
// (PRESET_SESSION_CHECKLIST Part 2 — "same dispatch path the live app uses"):
//
//   • Embodiment: brightness (spectral centroid) climbs the mode ladder → a FINER
//     figure (more nodal ridges); a bass drop (bass_dev) snaps to a SIMPLE figure.
//     Verified as a real GEOMETRIC change (ridge coverage + structural pixel diff),
//     not a colour shift.
//   • Silence (D-037): zero energy → non-black but calm (the dim fundamental).
//   • Performance: GPU time (cmdBuf.gpuEndTime−gpuStartTime) over N frames at
//     1080p, p50/p95/p99 — the full direct+bloom+composite chain.
//   • RENDER_VISUAL=1: writes the maquette contact-sheet fixtures + a motion
//     sequence to /tmp/phosphene_visual/<ts>/ for compare_render.sh / motion_gate.sh.

import Testing
import Metal
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Foundation
@testable import Renderer
@testable import Presets
@testable import Shared

@Suite("Cymatic Resonance")
struct CymaticResonanceVisualTests {

    // Assertion renders are modest; perf renders at 1080p (see perf test).
    static let renderW = 960
    static let renderH = 640
    static let outputRoot = "/tmp/phosphene_visual"

    // MARK: - Fixture construction

    private func features(centroid: Float, bassDev: Float, time: Float, width: Int, height: Int) -> FeatureVector {
        var f = FeatureVector(time: time, deltaTime: 1.0 / 60.0)
        f.spectralCentroid = centroid
        f.bassDev = bassDev
        f.aspectRatio = Float(width) / Float(height)
        return f
    }

    private func stems(energy: Float) -> StemFeatures {
        var s = StemFeatures.zero
        s.drumsEnergy = energy
        s.bassEnergy = energy
        s.vocalsEnergy = energy
        s.otherEnergy = energy
        return s
    }

    private func cymaticPreset() -> PresetLoader.LoadedPreset? {
        _acceptanceFixture.presets.first { $0.descriptor.name == "Cymatic Resonance" }
    }

    // MARK: - Production-path render

    /// Tick the state to convergence for (centroid, bassDev, energy), then render
    /// one frame through the real PostProcessChain. Returns BGRA8 pixels + the
    /// GPU time in ms.
    private func renderConverged(
        preset: PresetLoader.LoadedPreset,
        context: MetalContext,
        chain: PostProcessChain,
        centroid: Float,
        bassDev: Float,
        energy: Float,
        convergeFrames: Int,
        width: Int,
        height: Int
    ) throws -> (pixels: [UInt8], gpuMs: Double) {
        guard let state = CymaticResonanceState(device: context.device) else {
            throw CRTestError.stateAllocationFailed
        }
        let stm = stems(energy: energy)
        // Converge the EMAs at bassDev 0 (steady brightness) …
        var t: Float = 0
        for _ in 0..<convergeFrames {
            t += 1.0 / 60.0
            state.tick(deltaTime: 1.0 / 60.0, features: features(centroid: centroid, bassDev: 0, time: t, width: width, height: height), stems: stm)
        }
        // … then, if this is a drop, let the fast snap envelope attack.
        if bassDev > 0.01 {
            for _ in 0..<10 {
                t += 1.0 / 60.0
                state.tick(deltaTime: 1.0 / 60.0, features: features(centroid: centroid, bassDev: bassDev, time: t, width: width, height: height), stems: stm)
            }
        }
        var fv = features(centroid: centroid, bassDev: bassDev, time: t, width: width, height: height)
        return try renderFrame(preset: preset, context: context, chain: chain,
                               stateBuffer: state.stateBuffer, features: &fv,
                               stems: stm, width: width, height: height)
    }

    private func renderFrame(
        preset: PresetLoader.LoadedPreset,
        context: MetalContext,
        chain: PostProcessChain,
        stateBuffer: MTLBuffer,
        features: inout FeatureVector,
        stems: StemFeatures,
        width: Int,
        height: Int
    ) throws -> (pixels: [UInt8], gpuMs: Double) {
        chain.allocateTextures(width: width, height: height)

        let floatStride = MemoryLayout<Float>.stride
        guard
            let fftBuf = context.makeSharedBuffer(length: 512 * floatStride),
            let wavBuf = context.makeSharedBuffer(length: 2048 * floatStride)
        else { throw CRTestError.bufferAllocationFailed }

        let outDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: context.pixelFormat, width: width, height: height, mipmapped: false)
        outDesc.usage = [.renderTarget, .shaderRead]
        outDesc.storageMode = .shared
        guard let outTex = context.device.makeTexture(descriptor: outDesc) else {
            throw CRTestError.textureAllocationFailed
        }

        guard let cmdBuf = context.commandQueue.makeCommandBuffer() else {
            throw CRTestError.commandBufferFailed
        }
        chain.render(
            scenePipelineState: preset.pipelineState,
            features: &features,
            fftBuffer: fftBuf,
            waveformBuffer: wavBuf,
            stemFeatures: stems,
            outputTexture: outTex,
            commandBuffer: cmdBuf,
            noiseTextures: nil,
            presetFragmentBuffer: stateBuffer
        )
        cmdBuf.commit()
        cmdBuf.waitUntilCompleted()
        guard cmdBuf.status == .completed else { throw CRTestError.renderFailed }
        let gpuMs = (cmdBuf.gpuEndTime - cmdBuf.gpuStartTime) * 1000.0

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        outTex.getBytes(&pixels, bytesPerRow: width * 4,
                        from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        return (pixels, gpuMs)
    }

    // MARK: - Pixel metrics (BGRA8, premultipliedFirst little-endian → [B,G,R,A])

    private func luma(_ px: [UInt8], _ p: Int) -> Float {
        let b = Float(px[4 * p + 0]), g = Float(px[4 * p + 1]), r = Float(px[4 * p + 2])
        return 0.114 * b + 0.587 * g + 0.299 * r
    }

    /// Fraction of pixels above a luminance floor — a proxy for ridge coverage
    /// (a finer Chladni figure has more nodal lines → more lit pixels).
    private func litFraction(_ px: [UInt8], threshold: Float = 45) -> Double {
        let count = px.count / 4
        var lit = 0
        for p in 0..<count where luma(px, p) > threshold { lit += 1 }
        return Double(lit) / Double(count)
    }

    /// Mean absolute per-channel pixel difference (0…255) — structural change.
    private func meanAbsDiff(_ a: [UInt8], _ b: [UInt8]) -> Double {
        precondition(a.count == b.count)
        var acc: Int = 0
        for i in 0..<a.count { acc += abs(Int(a[i]) - Int(b[i])) }
        return Double(acc) / Double(a.count)
    }

    private func maxLuma(_ px: [UInt8]) -> Float {
        var m: Float = 0
        for p in 0..<(px.count / 4) { m = max(m, luma(px, p)) }
        return m
    }

    private func meanLuma(_ px: [UInt8]) -> Double {
        let count = px.count / 4
        var acc: Double = 0
        for p in 0..<count { acc += Double(luma(px, p)) }
        return acc / Double(count)
    }

    // MARK: - Embodiment: bright → fine, dim → simple, drop → snap-to-simple

    @Test("Embodiment: brightness climbs the mode ladder; a bass drop snaps to simple")
    func embodiment() throws {
        guard let ctx = try? MetalContext() else { return }   // no Metal device (CI) → skip
        guard let preset = cymaticPreset() else {
            Issue.record("Cymatic Resonance preset not loaded"); return
        }
        let chain = try PostProcessChain(context: ctx, shaderLibrary: ShaderLibrary(context: ctx))
        let w = Self.renderW, h = Self.renderH

        // Warmup held equal (energy present) so the ONLY variable is the figure.
        let dim   = try renderConverged(preset: preset, context: ctx, chain: chain,
                                        centroid: 0.15, bassDev: 0, energy: 0.5, convergeFrames: 200, width: w, height: h)
        let bright = try renderConverged(preset: preset, context: ctx, chain: chain,
                                         centroid: 0.88, bassDev: 0, energy: 0.5, convergeFrames: 200, width: w, height: h)
        let drop  = try renderConverged(preset: preset, context: ctx, chain: chain,
                                        centroid: 0.88, bassDev: 0.95, energy: 0.5, convergeFrames: 200, width: w, height: h)

        let dimLit = litFraction(dim.pixels)
        let brightLit = litFraction(bright.pixels)
        let dropLit = litFraction(drop.pixels)
        print("[CR embodiment] litFraction dim=\(dimLit) bright=\(brightLit) drop=\(dropLit)")
        print("[CR embodiment] meanAbsDiff dim↔bright=\(meanAbsDiff(dim.pixels, bright.pixels)) bright↔drop=\(meanAbsDiff(bright.pixels, drop.pixels))")

        // Bright is a FINER figure → strictly more ridge coverage than dim.
        #expect(brightLit > dimLit,
                "bright figure should have more ridge coverage than dim (bright=\(brightLit), dim=\(dimLit))")
        // The change is GEOMETRIC, not a colour shift: dim and bright differ structurally.
        #expect(meanAbsDiff(dim.pixels, bright.pixels) > 3.0,
                "dim and bright figures should differ structurally, not just in colour")
        // A bass drop snaps the ladder DOWN → simpler than the bright figure it came from.
        #expect(dropLit < brightLit,
                "a bass drop should snap to a simpler figure (drop=\(dropLit), bright=\(brightLit))")
        #expect(meanAbsDiff(bright.pixels, drop.pixels) > 3.0,
                "the snap should be a visible restructure, not a colour shift")
    }

    // MARK: - Silence (D-037): non-black but calm

    @Test("Silence is non-black but calm (D-037 fundamental)")
    func silenceNonBlack() throws {
        guard let ctx = try? MetalContext() else { return }
        guard let preset = cymaticPreset() else {
            Issue.record("Cymatic Resonance preset not loaded"); return
        }
        let chain = try PostProcessChain(context: ctx, shaderLibrary: ShaderLibrary(context: ctx))
        let silence = try renderConverged(preset: preset, context: ctx, chain: chain,
                                          centroid: 0.0, bassDev: 0, energy: 0.0, convergeFrames: 200,
                                          width: Self.renderW, height: Self.renderH)
        let mx = maxLuma(silence.pixels)
        let mean = meanLuma(silence.pixels)
        print("[CR silence] maxLuma=\(mx) meanLuma=\(mean)")
        #expect(mx > 4.0, "silence must be non-black (D-037): some emissive/floor is visible")
        #expect(mean < 60.0, "silence must be calm, not a bright field (meanLuma=\(mean))")
    }

    // MARK: - Performance (full direct+bloom+composite chain GPU time at 1080p)

    @Test("Performance: p50/p95/p99 GPU time at 1080p (CR_PERF=1)")
    func performance() throws {
        // GPU-time measurement is meaningless under the default 16-way parallel test
        // run — queue contention inflates the wall-clock GPU time ~9× (2.6 ms solo →
        // ~23 ms contended). Env-gate the assertion out of the default/closeout run
        // (the RENDER_VISUAL / HARNESS_TEMPLATES precedent); run solo with CR_PERF=1
        // for the real figure. Widening the ceiling would mask real regressions —
        // deterministic isolation is the fix, not a bigger budget
        // ([[feedback_deterministic_tests_over_budget_widening]]).
        guard ProcessInfo.processInfo.environment["CR_PERF"] == "1" else {
            print("[CR perf] CR_PERF not set — skipping (run solo: CR_PERF=1 swift test --filter 'Performance')")
            return
        }
        guard let ctx = try? MetalContext() else { return }
        guard let preset = cymaticPreset() else {
            Issue.record("Cymatic Resonance preset not loaded"); return
        }
        let chain = try PostProcessChain(context: ctx, shaderLibrary: ShaderLibrary(context: ctx))
        let w = 1920, h = 1080
        guard let state = CymaticResonanceState(device: ctx.device) else {
            throw CRTestError.stateAllocationFailed
        }
        let stm = stems(energy: 0.5)
        // Steady beat-heavy state (mid-bright, snap active) — the busy figure.
        var t: Float = 0
        for _ in 0..<200 { t += 1.0 / 60.0; state.tick(deltaTime: 1.0 / 60.0, features: features(centroid: 0.7, bassDev: 0.6, time: t, width: w, height: h), stems: stm) }

        var samples: [Double] = []
        for _ in 0..<50 {
            t += 1.0 / 60.0
            state.tick(deltaTime: 1.0 / 60.0, features: features(centroid: 0.7, bassDev: 0.6, time: t, width: w, height: h), stems: stm)
            var fv = features(centroid: 0.7, bassDev: 0.6, time: t, width: w, height: h)
            let r = try renderFrame(preset: preset, context: ctx, chain: chain,
                                    stateBuffer: state.stateBuffer, features: &fv, stems: stm, width: w, height: h)
            samples.append(r.gpuMs)
        }
        samples.sort()
        func pct(_ p: Double) -> Double { samples[min(samples.count - 1, Int(p * Double(samples.count)))] }
        let p50 = pct(0.50), p95 = pct(0.95), p99 = pct(0.99)
        print(String(format: "[CR perf] 1080p full-chain GPU ms — p50=%.3f p95=%.3f p99=%.3f (n=%d)", p50, p95, p99, samples.count))
        // Generous regression ceiling (Tier-2 direct budget is 7 ms for the fragment
        // alone; this includes bright+blur+composite and is expected ≪ 12 ms).
        #expect(p95 < 12.0, "1080p full-chain p95 GPU time \(p95) ms exceeds the regression ceiling")
    }

    // MARK: - RENDER_VISUAL=1: contact-sheet fixtures + motion sequence

    @Test("Render maquette frames + motion sequence (RENDER_VISUAL=1)")
    func renderVisual() throws {
        guard ProcessInfo.processInfo.environment["RENDER_VISUAL"] == "1" else {
            print("[CR RENDER_VISUAL] not set, skipping"); return
        }
        guard let ctx = try? MetalContext() else { return }
        guard let preset = cymaticPreset() else {
            Issue.record("Cymatic Resonance preset not loaded"); return
        }
        let chain = try PostProcessChain(context: ctx, shaderLibrary: ShaderLibrary(context: ctx))
        let dir = try makeOutputDirectory()
        print("[CR RENDER_VISUAL] output dir: \(dir.path)")
        let w = Self.renderW, h = Self.renderH

        // Contact-sheet fixtures — the figure across the excitation + brightness range.
        let fixtures: [(String, Float, Float, Float)] = [   // label, centroid, bassDev, energy
            ("silence", 0.0, 0.0, 0.0),
            ("dim",     0.15, 0.0, 0.5),
            ("mid",     0.5, 0.0, 0.5),
            ("bright",  0.88, 0.0, 0.5),
            ("drop",    0.88, 0.95, 0.5)
        ]
        for (label, c, bd, e) in fixtures {
            let r = try renderConverged(preset: preset, context: ctx, chain: chain,
                                        centroid: c, bassDev: bd, energy: e, convergeFrames: 200, width: w, height: h)
            let url = dir.appendingPathComponent("cymatic_resonance_\(label).png")
            try writePNG(bgra: r.pixels, width: w, height: h, to: url)
            print("[CR RENDER_VISUAL] wrote \(url.lastPathComponent)")
        }

        // Motion sequence — a slow brightness ramp (climb the ladder) then a drop
        // (snap-to-simple), rendered as a contiguous sequence for motion_gate.sh.
        guard let seqState = CymaticResonanceState(device: ctx.device) else {
            throw CRTestError.stateAllocationFailed
        }
        let stm = stems(energy: 0.5)
        let seqCount = 60
        var t: Float = 0
        // Prime a few frames at low brightness.
        for _ in 0..<30 { t += 1.0 / 60.0; seqState.tick(deltaTime: 1.0 / 60.0, features: features(centroid: 0.1, bassDev: 0, time: t, width: w, height: h), stems: stm) }
        for i in 0..<seqCount {
            // Ramp centroid 0.1 → 0.9 over the first 3/4, then fire a drop.
            let frac = Float(i) / Float(seqCount)
            let centroid = 0.1 + 0.8 * min(frac / 0.75, 1.0)
            let bassDev: Float = (i >= 44 && i < 50) ? 0.95 : 0.0
            t += 1.0 / 60.0
            seqState.tick(deltaTime: 1.0 / 60.0, features: features(centroid: centroid, bassDev: bassDev, time: t, width: w, height: h), stems: stm)
            var fv = features(centroid: centroid, bassDev: bassDev, time: t, width: w, height: h)
            let r = try renderFrame(preset: preset, context: ctx, chain: chain,
                                    stateBuffer: seqState.stateBuffer, features: &fv, stems: stm, width: w, height: h)
            let url = dir.appendingPathComponent(String(format: "cymatic_resonance_seq_%04d.png", i))
            try writePNG(bgra: r.pixels, width: w, height: h, to: url)
        }
        print("[CR RENDER_VISUAL] wrote \(seqCount) sequence frames (cymatic_resonance_seq_*.png)")
    }

    // MARK: - Output helpers

    private func makeOutputDirectory() throws -> URL {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withYear, .withMonth, .withDay, .withTime]
        let stamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let url = URL(fileURLWithPath: Self.outputRoot).appendingPathComponent(stamp)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writePNG(bgra: [UInt8], width: Int, height: Int, to url: URL) throws {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { throw CRTestError.pngWriteFailed }
        let bitmapInfo = CGBitmapInfo(rawValue:
            CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        var copy = bgra
        let cg = copy.withUnsafeMutableBytes { (ptr: UnsafeMutableRawBufferPointer) -> CGImage? in
            guard let base = ptr.baseAddress,
                  let c = CGContext(data: base, width: width, height: height, bitsPerComponent: 8,
                                    bytesPerRow: width * 4, space: colorSpace, bitmapInfo: bitmapInfo.rawValue)
            else { return nil }
            return c.makeImage()
        }
        guard let image = cg else { throw CRTestError.pngWriteFailed }
        let type = UTType.png.identifier as CFString
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, type, 1, nil) else { throw CRTestError.pngWriteFailed }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { throw CRTestError.pngWriteFailed }
    }
}

// MARK: - Errors

private enum CRTestError: Error {
    case stateAllocationFailed
    case bufferAllocationFailed
    case textureAllocationFailed
    case commandBufferFailed
    case renderFailed
    case pngWriteFailed
}
