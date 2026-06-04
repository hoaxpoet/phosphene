// NimbusBudgetProbeTests — NB.1 macro-only per-preset GPU budget probe.
//
// Measures Nimbus's per-preset GPU cost at 1920×1080 using the wall-clock GPU
// timestamps (MTLCommandBuffer.gpuStartTime / gpuEndTime — the same pattern as
// UtilityPerformanceHarness and the FrameBudgetManager timing path). One
// fullscreen direct-fragment pass per command buffer; the GPU window of that
// command buffer is the per-preset cost.
//
// Gated behind NIMBUS_BUDGET=1 so it stays out of normal CI / `swift test`.
//
// Invocation:
//   NIMBUS_BUDGET=1 swift test --package-path PhospheneEngine \
//       --filter NimbusBudgetProbe
//
// NB.1 budget gate (DESIGN §6 / README Gate 0): Tier 2 per-preset GPU ≤ 7 ms at
// 1920×1080. If the macro-only body already exceeds that, STOP and report — a
// march that can't fit at the maquette stage won't fit certified.

import Testing
import Metal
@testable import Presets
@testable import Renderer
import Shared

@Suite("NimbusBudgetProbe")
struct NimbusBudgetProbeTests {

    @Test("Nimbus per-preset GPU cost @ 1920×1080 (NIMBUS_BUDGET=1)")
    func test_nimbusBudgetProbe() throws {
        guard ProcessInfo.processInfo.environment["NIMBUS_BUDGET"] == "1" else {
            print("[NimbusBudget] NIMBUS_BUDGET not set — skipping")
            return
        }
        let ctx: MetalContext
        do { ctx = try MetalContext() } catch {
            print("[NimbusBudget] no Metal context — skipping"); return
        }
        let device = ctx.device
        let queue = ctx.commandQueue

        let width = 1920, height = 1080
        let pixelFormat: MTLPixelFormat = .bgra8Unorm_srgb

        // Real production compile path: PresetLoader auto-discovers + compiles Nimbus.
        let loader = PresetLoader(device: device, pixelFormat: pixelFormat)
        guard let nimbus = loader.presets.first(where: { $0.descriptor.name == "Nimbus" }) else {
            Issue.record("Nimbus preset not found — shader failed to compile or auto-discover")
            return
        }

        // Production binds noiseVolume at fragment texture(6) on the direct path
        // (RenderPipeline+Draw.bindNoiseTextures). Bind the SAME texture here so the
        // probe measures the real cost — FA #66 test/prod parity.
        guard let lib = try? ShaderLibrary(context: ctx),
              let texMgr = try? TextureManager(context: ctx, shaderLibrary: lib) else {
            Issue.record("could not build noiseVolume — probe would mis-measure"); return
        }
        let noiseVolume = texMgr.noiseVolume

        // Steady-mid fixture (DESIGN §6 / NB.1 plan). aspectRatio defaults to
        // 1.777 = the 1920×1080 measurement aspect, so the framing matches.
        var features = FeatureVector(bass: 0.5, mid: 0.5, treble: 0.5,
                                     time: 3.0, deltaTime: 1.0 / 60.0)

        // Measure per-preset GPU ms at a given resolution via the command-buffer
        // GPU timestamp window (one fullscreen direct-fragment pass per frame).
        func measure(_ w: Int, _ h: Int) -> (min: Double, p50: Double, mean: Double, p95: Double, max: Double)? {
            let td = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: pixelFormat, width: w, height: h, mipmapped: false)
            td.usage = [.renderTarget, .shaderRead]
            td.storageMode = .private
            guard let target = device.makeTexture(descriptor: td) else { return nil }

            func renderOneFrame() -> Double {
                let rpd = MTLRenderPassDescriptor()
                rpd.colorAttachments[0].texture = target
                rpd.colorAttachments[0].loadAction = .clear
                rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
                rpd.colorAttachments[0].storeAction = .store
                guard let cmd = queue.makeCommandBuffer(),
                      let enc = cmd.makeRenderCommandEncoder(descriptor: rpd) else { return 0 }
                enc.setRenderPipelineState(nimbus.pipelineState)
                enc.setFragmentBytes(&features, length: MemoryLayout<FeatureVector>.size, index: 0)
                enc.setFragmentTexture(noiseVolume, index: 6)
                enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
                enc.endEncoding()
                cmd.commit()
                cmd.waitUntilCompleted()
                return (cmd.gpuEndTime - cmd.gpuStartTime) * 1000.0   // ms
            }

            let warmup = 40, measured = 160
            for _ in 0..<warmup { _ = renderOneFrame() }
            var s: [Double] = []; s.reserveCapacity(measured)
            for _ in 0..<measured { s.append(renderOneFrame()) }
            s.sort()
            return (s.first ?? 0, s[s.count / 2], s.reduce(0, +) / Double(s.count),
                    s[Int(Double(s.count) * 0.95)], s.last ?? 0)
        }

        // Full-res (the Tier-2 budget reference) and the half-res-march projection
        // (DESIGN §6's planned headroom lever, before the NB.8 MetalFX upscale cost).
        if let full = measure(width, height) {
            print(String(format:
                "[NimbusBudget] FULL 1920x1080  min=%.3f  p50=%.3f  mean=%.3f  p95=%.3f  max=%.3f ms",
                full.min, full.p50, full.mean, full.p95, full.max))
            let ratio = full.p50 / 7.0
            print(String(format:
                "[NimbusBudget] VERDICT(full): p50 %.2f ms = %.2fx the 7.0 ms Tier-2 ceiling — %@",
                full.p50, ratio, full.p50 <= 7.0 ? "WITHIN" : "OVER (DESIGN §6: full-1080p march not expected to fit — lever is half-res+MetalFX, NB.8)"))
        }
        if let half = measure(width / 2, height / 2) {
            print(String(format:
                "[NimbusBudget] HALF 960x540 (march only, no MetalFX)  min=%.3f  p50=%.3f  mean=%.3f  p95=%.3f  max=%.3f ms",
                half.min, half.p50, half.mean, half.p95, half.max))
            print(String(format:
                "[NimbusBudget] VERDICT(half-march): p50 %.2f ms vs 7.0 ms ceiling — %@ (projection only; MetalFX upscale + NB.2–7 detail/lighting/embers add on top)",
                half.p50, half.p50 <= 7.0 ? "UNDER" : "OVER"))
        }
        // Reporter only — the 7 ms gate is a human/closeout judgement at NB.1 and
        // becomes an automated assertion on the final half-res cost at NB.8.
    }
}
