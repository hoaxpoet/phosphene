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

    /// Mirrors `SkeinHeaderGPU` in Skein.metal — 16 floats / 64 bytes.
    private struct HeaderMirror {
        var painterTau: Float = 12.0
        var painterTauStep: Float = 1.0 / 60.0
        var seedPhaseX: Float = 0.31
        var seedPhaseY: Float = 0.72
        var lineColR: Float = 0.6
        var lineColG: Float = 0.2
        var lineColB: Float = 0.1
        var lineFlow: Float = 0.5
        var lineVisc: Float = 0.5
        var jitter: Float = 0.1
        var burstCount: UInt32 = 0
        var seed: UInt32 = 12345
        var breakCount: UInt32 = 0
        var locusEnable: Float = 0
        var pad2: Float = 0
        var pad3: Float = 0
    }

    /// Mirrors `SkeinBreakGPU` — 6 floats / 24 bytes.
    private struct BreakMirror {
        var tauStart: Float
        var colR: Float, colG: Float, colB: Float
        var offX: Float, offY: Float
    }

    private static let maxBursts = 48
    private static let maxBreaks = 16
    private static let burstStride = 48      // 12 floats
    private static let breakStride = 24      // 6 floats

    /// Build the slot-6 buffer with `breaks` colour breakpoints laid across the painter clock.
    private static func makeUniforms(device: MTLDevice, breaks: Int) -> MTLBuffer? {
        let total = 64 + maxBursts * burstStride + maxBreaks * breakStride
        guard let buf = device.makeBuffer(length: total, options: .storageModeShared) else { return nil }
        memset(buf.contents(), 0, total)

        var header = HeaderMirror()
        header.breakCount = UInt32(breaks)
        buf.contents().copyMemory(from: &header, byteCount: MemoryLayout<HeaderMirror>.size)

        // Breakpoints ascend through the tail the shader walks (tau − 40·dτ … tau), which is the
        // range `skeinLineLookupAt` scans — the worst case the live path reaches once a track has
        // accumulated switches.
        let base = buf.contents().advanced(by: 64 + maxBursts * burstStride)
        for i in 0..<min(breaks, maxBreaks) {
            let frac = Float(i) / Float(max(breaks - 1, 1))
            var bk = BreakMirror(
                tauStart: 12.0 - (1.0 - frac) * 0.67,          // spread over the 40-frame tail
                colR: frac, colG: 1.0 - frac, colB: 0.5,
                offX: 0.01 * frac, offY: -0.01 * frac)
            base.advanced(by: i * breakStride)
                .copyMemory(from: &bk, byteCount: MemoryLayout<BreakMirror>.size)
        }
        return buf
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

        // 2. Cost grows with the breakpoint count, which is the live ramp's mechanism: a track
        //    accumulates dominant-stem switches, and skeinLineLookupAt scans them once per tail
        //    frame per fragment (40 × up to 16, at 8.3 M fragments).
        #expect(full > one * 2, """
                cost stopped growing with the breakpoint count (\(one) → \(full) ms). If a fix \
                hoisted the per-fragment breakpoint scan, that is the intended outcome — update \
                this expectation and BUG-107 together.
                """)
    }
}
