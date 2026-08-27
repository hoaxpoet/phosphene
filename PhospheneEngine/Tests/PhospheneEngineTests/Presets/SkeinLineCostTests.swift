// SkeinLineCostTests — what Skein actually costs, and why the frame-budget harness cannot see it
// (BUG-107).
//
// **The gap this measures.** `PresetFrameBudgetTests` reports Skein at **15.60 ms** at 3840×2160 —
// 0.8× the median preset, one of the cheapest in the roster. Live, the same preset at the same
// resolution ramps to **~170 ms** (≈6 fps) over ~50 s and plateaus, twice, on two sessions
// (`2026-08-27T13-24-37Z` and `2026-08-27T14-33-03Z`).
//
// Reading the shader explains the discrepancy: the whole pour-line layer sits behind
// `if (int(st.breakCount) > 0)`, and the frame-budget harness binds a ZEROED slot-6 buffer. With
// no colour breakpoints there is no committed pour, so the line is never drawn — the harness has
// been measuring Skein with its most expensive layer switched off. Inside that layer,
// `kSkeinTailFrames = 40` tail iterations each call `skeinLineLookupAt`, which scans the
// breakpoint ring (up to `kSkeinMaxBreaks = 16`) — so the cost also GROWS as a track accumulates
// dominant-stem switches, which is the ramp's shape.
//
// This test binds a synthetic `SkeinUniforms` — no audio, no `SkeinState`, just bytes — and times
// the real `skein_geometry_fragment` at several breakpoint counts. That is the seam Skein has
// never had: a way to render its marks with a KNOWN painter state.
//
// Run:
//   PHOSPHENE_SKEIN_COST=1 swift test --package-path PhospheneEngine --filter SkeinLineCostTests

import Foundation
import Metal
import Testing
@testable import Presets
@testable import Renderer
@testable import Shared

@Suite("Skein line-layer cost (BUG-107, env-gated)")
struct SkeinLineCostTests {

    // No hand-mirrored layout here: the real `SkeinHeaderGPU` / `SkeinBreakGPU` / `SkeinTailGPU`
    // are used directly, and the tail is filled by the production `SkeinState.resolveTail`. A
    // test that re-declares a GPU struct's layout can drift from it silently, which is precisely
    // the class of bug the stride guards elsewhere in this repo exist to catch.

    private static let maxBursts = 48
    private static let maxBreaks = 16
    private static let groundStride = 16     // float4
    private static let tailSamples = 41      // BUG-107 — kSkeinTailFrames + 1

    /// Build the slot-6 buffer with `breaks` colour breakpoints laid across the painter clock.
    private static func makeUniforms(device: MTLDevice, breaks: Int) -> MTLBuffer? {
        let burstStride = MemoryLayout<SkeinBurstGPU>.stride
        let breakStride = MemoryLayout<SkeinBreakGPU>.stride
        let tailStride  = MemoryLayout<SkeinTailGPU>.stride
        let total = MemoryLayout<SkeinHeaderGPU>.stride
                  + maxBursts * burstStride + maxBreaks * breakStride
                  + groundStride + tailSamples * tailStride
        guard let buf = device.makeBuffer(length: total, options: .storageModeShared) else { return nil }
        memset(buf.contents(), 0, total)

        var header = SkeinHeaderGPU(
            painterTau: 12.0, painterTauStep: 1.0 / 60.0,
            seedPhaseX: 0.31, seedPhaseY: 0.72,
            lineColR: 0.6, lineColG: 0.2, lineColB: 0.1,
            lineFlow: 0.5, lineVisc: 0.5, jitter: 0.1,
            burstCount: 0, seed: 12345, breakCount: UInt32(breaks),
            locusEnable: 0, pad2: 0, pad3: 0)
        buf.contents().copyMemory(from: &header, byteCount: MemoryLayout<SkeinHeaderGPU>.size)

        // Breakpoints ascend through the tail the shader walks (tau − 40·dτ … tau) — the worst
        // case the live path reaches once a track has accumulated dominant-stem switches.
        var ring: [SkeinBreakGPU] = []
        for i in 0..<min(breaks, maxBreaks) {
            let frac = Float(i) / Float(max(breaks - 1, 1))
            ring.append(SkeinBreakGPU(
                tauStart: 12.0 - (1.0 - frac) * 0.67,
                colR: frac, colG: 1.0 - frac, colB: 0.5,
                offX: 0.01 * frac, offY: -0.01 * frac))
        }
        let breakBase = buf.contents()
            .advanced(by: MemoryLayout<SkeinHeaderGPU>.stride + maxBursts * burstStride)
            .bindMemory(to: SkeinBreakGPU.self, capacity: maxBreaks)
        for (i, bk) in ring.enumerated() { breakBase[i] = bk }

        // BUG-107: the fragment reads a PRE-RESOLVED tail table instead of recomputing the painter
        // path and scanning the ring per pixel, so fill it through the production resolver.
        let tailPtr = buf.contents()
            .advanced(by: MemoryLayout<SkeinHeaderGPU>.stride
                          + maxBursts * burstStride + maxBreaks * breakStride + groundStride)
            .bindMemory(to: SkeinTailGPU.self, capacity: tailSamples)
        SkeinState.resolveTail(into: tailPtr, header: header, breaks: ring)
        return buf
    }

    /// Speed means nothing if the paint moved. The hoist replaced a per-fragment computation of
    /// the painter path with a per-frame table, so the failure mode it introduces is a table that
    /// is mis-offset, mis-strided or stale — none of which the cost numbers would reveal, because
    /// a garbage table still costs the same to read.
    ///
    /// This renders the marks at a known painter state and asserts the paint lands where
    /// `SkeinState.painterPosition` says the painter is. If the table's byte layout drifts from
    /// `SkeinTailGPU` in Skein.metal, the line moves or vanishes and this goes red.
    @Test("The pre-resolved tail puts the paint where the painter actually is (BUG-107)")
    func hoistedTailDrawsInTheRightPlace() throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else { return }
        let ctx = try MetalContext()
        let loader = PresetLoader(device: ctx.device, pixelFormat: ctx.pixelFormat, loadBuiltIn: true)
        guard let skein = loader.presets.first(where: { $0.descriptor.name == "Skein" }),
              let marks = skein.mvWarpPipelines?.sceneGeometryState,
              let uniforms = Self.makeUniforms(device: ctx.device, breaks: 1) else {
            Issue.record("Skein marks pipeline unavailable"); return
        }

        let (w, h) = (512, 512)
        let td = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: w, height: h, mipmapped: false)
        td.usage = [.renderTarget, .shaderRead]; td.storageMode = .shared
        guard let tex = ctx.device.makeTexture(descriptor: td) else { Issue.record("no texture"); return }

        let floatStride = MemoryLayout<Float>.stride
        guard let fft = ctx.makeSharedBuffer(length: 512 * floatStride),
              let wav = ctx.makeSharedBuffer(length: 2048 * floatStride),
              let stem = ctx.makeSharedBuffer(length: MemoryLayout<StemFeatures>.size),
              let hist = ctx.makeSharedBuffer(length: 4096 * floatStride) else { return }

        var fv = FeatureVector(time: 12.0, deltaTime: 1.0 / 60.0)
        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = tex
        rpd.colorAttachments[0].loadAction = .clear
        rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        rpd.colorAttachments[0].storeAction = .store
        guard let cmd = queue.makeCommandBuffer(),
              let enc = cmd.makeRenderCommandEncoder(descriptor: rpd) else { return }
        enc.setRenderPipelineState(marks)
        enc.setFragmentBytes(&fv, length: MemoryLayout<FeatureVector>.size, index: 0)
        enc.setFragmentBuffer(fft, offset: 0, index: 1)
        enc.setFragmentBuffer(wav, offset: 0, index: 2)
        enc.setFragmentBuffer(stem, offset: 0, index: 3)
        enc.setFragmentBuffer(hist, offset: 0, index: 5)
        enc.setFragmentBuffer(uniforms, offset: 0, index: 6)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
        cmd.commit(); cmd.waitUntilCompleted()

        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        pixels.withUnsafeMutableBytes { dst in
            tex.getBytes(dst.baseAddress!, bytesPerRow: w * 4,
                         from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        }

        // Centroid of painted coverage (alpha), in uv.
        var sum = SIMD2<Double>(0, 0)
        var weight = 0.0
        for y in 0..<h {
            for x in 0..<w {
                let a = Double(pixels[(y * w + x) * 4 + 3]) / 255.0
                if a > 0.25 {
                    sum += SIMD2<Double>(Double(x) / Double(w), Double(y) / Double(h)) * a
                    weight += a
                }
            }
        }
        #expect(weight > 0, """
                nothing was painted at breakCount=1. Either the tail table is not reaching the \
                fragment (offset/stride drift against SkeinTailGPU) or the line layer is gated off.
                """)
        guard weight > 0 else { return }
        let centroid = sum / weight

        // The painter's own path over the drawn tail, from the production resolver.
        let tip = SkeinState.painterPosition(t: 12.0, phx: 0.31, phy: 0.72)
        let mid = SkeinState.painterPosition(t: 12.0 - 20.0 / 60.0, phx: 0.31, phy: 0.72)
        let expected = SIMD2<Double>(Double(tip.x + mid.x) * 0.5, Double(tip.y + mid.y) * 0.5)
        // uv.y is flipped on screen (the shader draws with y = 0 at the top).
        let dx = abs(centroid.x - expected.x)
        let dy = abs((1.0 - centroid.y) - expected.y)
        #expect(dx < 0.20 && dy < 0.20, """
                paint centroid (\(centroid.x), \(1.0 - centroid.y)) is far from the painter's \
                own path midpoint (\(expected.x), \(expected.y)). The pre-resolved tail is \
                describing a different path than the fragment is drawing.
                """)
    }

    @Test("Measure Skein's fragment cost against the breakpoint count (BUG-107)")
    func measureLineCost() throws {
        guard ProcessInfo.processInfo.environment["PHOSPHENE_SKEIN_COST"] == "1" else {
            print("SkeinLineCostTests: PHOSPHENE_SKEIN_COST not set, skipping"); return
        }
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else {
            print("SkeinLineCostTests: no Metal device, skipping"); return
        }
        let ctx = try MetalContext()
        let loader = PresetLoader(device: ctx.device, pixelFormat: ctx.pixelFormat, loadBuiltIn: true)
        guard let skein = loader.presets.first(where: { $0.descriptor.name == "Skein" }) else {
            Issue.record("Skein not found"); return
        }
        // The marks overlay, NOT `skein.pipelineState`. The first version of this harness timed
        // the base direct pass and reported 0.34 ms flat at 4K for every breakpoint count — a
        // number that says only "this is not the shader that draws the paint".
        // `mvWarpPipelines.sceneGeometryState` is the `<prefix>_geometry_fragment` overlay
        // (D-143), where the pour line and the bursts are actually drawn.
        guard let marks = skein.mvWarpPipelines?.sceneGeometryState else {
            Issue.record("Skein has no scene-geometry (marks) pipeline — nothing to time")
            return
        }

        let (w, h) = (3840, 2160)
        let td = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: ctx.pixelFormat, width: w, height: h, mipmapped: false)
        td.usage = [.renderTarget, .shaderRead]; td.storageMode = .private
        guard let tex = ctx.device.makeTexture(descriptor: td) else { Issue.record("no texture"); return }

        let floatStride = MemoryLayout<Float>.stride
        guard let fft = ctx.makeSharedBuffer(length: 512 * floatStride),
              let wav = ctx.makeSharedBuffer(length: 2048 * floatStride),
              let stem = ctx.makeSharedBuffer(length: MemoryLayout<StemFeatures>.size),
              let hist = ctx.makeSharedBuffer(length: 4096 * floatStride)
        else { Issue.record("no buffers"); return }

        func timeFrames(breaks: Int, frames: Int) -> Double {
            guard let uniforms = Self.makeUniforms(device: ctx.device, breaks: breaks) else { return .nan }
            var samples: [Double] = []
            for _ in 0..<frames {
                var fv = FeatureVector(time: 12.0, deltaTime: 1.0 / 60.0)
                let rpd = MTLRenderPassDescriptor()
                rpd.colorAttachments[0].texture = tex
                rpd.colorAttachments[0].loadAction = .clear
                rpd.colorAttachments[0].storeAction = .store
                guard let cmd = queue.makeCommandBuffer(),
                      let enc = cmd.makeRenderCommandEncoder(descriptor: rpd) else { return .nan }
                enc.setRenderPipelineState(marks)
                enc.setFragmentBytes(&fv, length: MemoryLayout<FeatureVector>.size, index: 0)
                enc.setFragmentBuffer(fft, offset: 0, index: 1)
                enc.setFragmentBuffer(wav, offset: 0, index: 2)
                enc.setFragmentBuffer(stem, offset: 0, index: 3)
                enc.setFragmentBuffer(hist, offset: 0, index: 5)
                enc.setFragmentBuffer(uniforms, offset: 0, index: 6)
                enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
                enc.endEncoding()
                cmd.commit(); cmd.waitUntilCompleted()
                samples.append((cmd.gpuEndTime - cmd.gpuStartTime) * 1000)
            }
            // Min of N warm samples: contention can only ADD time to a GPU submit, so the minimum
            // is the clean estimate (CLEAN.7.9 → 7.14, the deterministic-over-budget-widening rule).
            return samples.dropFirst(2).min() ?? .nan
        }

        print("")
        print("=== SKEIN FRAGMENT COST @ \(w)×\(h) (min of 6 warm frames) ===")
        var results: [(Int, Double)] = []
        for breaks in [0, 1, 2, 4, 8, 16] {
            let ms = timeFrames(breaks: breaks, frames: 8)
            results.append((breaks, ms))
            let note = breaks == 0 ? "   ← what PresetFrameBudgetTests measures (no committed pour)" : ""
            print(String(format: "  breakCount=%2d  %8.2f ms%@", breaks, ms, note))
        }
        print("=== END ===")
        print("")

        // Both findings, asserted so neither can quietly stop being true.
        let zero = results.first(where: { $0.0 == 0 })?.1 ?? .nan
        let one  = results.first(where: { $0.0 == 1 })?.1 ?? .nan
        let full = results.first(where: { $0.0 == 16 })?.1 ?? .nan

        // 1. The frame-budget harness measures this layer SWITCHED OFF. A zero-breakpoint
        //    reading is not Skein's cost, and must never again be quoted as one.
        #expect(one > zero * 5, """
                breakCount 0→1 barely changed cost (\(zero) → \(one) ms). The line layer is \
                supposed to be gated on breakCount > 0; if it is not, PresetFrameBudgetTests is \
                no longer blind and BUG-107 needs re-measuring.
                """)

        // 2. Cost NO LONGER grows with the breakpoint count. Before the BUG-107 hoist this
        //    asserted the opposite — the growth WAS the defect, 17.06 → 55.65 ms from 1 to 16
        //    breakpoints, because skeinLineLookupAt scanned the ring once per tail frame per
        //    fragment. With the tail resolved once per frame the fragment does no scanning at
        //    all, so the curve is flat (mildly decreasing: more pours mean more skipped bridge
        //    segments, hence fewer segment-distance evaluations).
        #expect(full <= one * 1.25, """
                cost is growing with the breakpoint count again (\(one) → \(full) ms). The tail \
                table is resolved once per frame precisely so the fragment never scans the ring; \
                if this is red, something reintroduced per-fragment lookup.
                """)
    }
}
