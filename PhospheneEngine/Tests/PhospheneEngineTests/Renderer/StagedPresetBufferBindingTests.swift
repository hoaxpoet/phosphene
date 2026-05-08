// StagedPresetBufferBindingTests — Regression for V.7.7B engine fix.
//
// Asserts that `RenderPipeline.encodeStage` binds the per-preset fragment
// buffer set via `setDirectPresetFragmentBuffer` (slot 6) when dispatching a
// staged-composition stage. The legacy mv_warp / direct paths consult these
// fields; V.7.7A's staged scaffold did not, which silently delivered zeros to
// staged Arachne's WORLD + COMPOSITE fragments. V.7.7B closes that gap; this
// test prevents the regression from reappearing under future refactors.
//
// Approach:
//   1. Inline-compile a synthetic 1-stage shader that reads slot 6 and writes
//      the sentinel value as the red channel.
//   2. Configure RenderPipeline staged runtime with that single non-final stage
//      (writesToDrawable=false) so `setStagedRuntime` allocates the offscreen
//      target.
//   3. Allocate a sentinel MTLBuffer carrying a known float and bind via
//      `setDirectPresetFragmentBuffer`.
//   4. Drive `encodeStage` directly against the offscreen texture (test seam:
//      `encodeStage` is `internal` for exactly this purpose).
//   5. Read back the offscreen texture and assert R-channel ≈ sentinel.
//
// See `prompts/V.7.7B-prompt.md` §SCOPE Sub-item 3.

import Testing
import Metal
@testable import Renderer
@testable import Shared

private enum BindingTestError: Error {
    case metalSetupFailed
    case shaderCompileFailed
    case textureAllocationFailed
    case bufferAllocationFailed
    case commandBufferFailed
    case encoderCreationFailed
    case stagedTextureMissing
}

private let kSentinelShader = """
#include <metal_stdlib>
using namespace metal;

struct VOut {
    float4 position [[position]];
    float2 uv;
};

vertex VOut sentinel_vertex(uint vid [[vertex_id]]) {
    float2 pts[3] = { float2(-1, -1), float2(3, -1), float2(-1, 3) };
    VOut o;
    o.position = float4(pts[vid], 0.0, 1.0);
    o.uv = (pts[vid] + 1.0) * 0.5;
    return o;
}

// Reads the per-preset fragment buffer at slot 6 (V.7.7B contract) and
// writes the sentinel as the red channel. If the binding is missing the
// fragment reads zero (Metal's documented behaviour) and the test fails.
fragment float4 sentinel_fragment(
    VOut in [[stage_in]],
    constant float* preset [[buffer(6)]]
) {
    return float4(preset[0], 0.0, 0.0, 1.0);
}
"""

@Suite("StagedPresetBufferBinding")
struct StagedPresetBufferBindingTests {

    // MARK: - Helpers

    private func makeRenderPipeline(context: MetalContext) throws -> RenderPipeline {
        let library = try ShaderLibrary(context: context)
        let floatStride = MemoryLayout<Float>.stride
        guard
            let fftBuf = context.makeSharedBuffer(length: 512 * floatStride),
            let waveBuf = context.makeSharedBuffer(length: 2048 * floatStride)
        else {
            throw BindingTestError.bufferAllocationFailed
        }
        return try RenderPipeline(
            context: context,
            shaderLibrary: library,
            fftBuffer: fftBuf,
            waveformBuffer: waveBuf
        )
    }

    private func makeSentinelStage(
        context: MetalContext,
        targetFormat: MTLPixelFormat
    ) throws -> StagedStageSpec {
        let options = MTLCompileOptions()
        options.languageVersion = .version3_0
        let library: MTLLibrary
        do {
            library = try context.device.makeLibrary(source: kSentinelShader, options: options)
        } catch {
            throw BindingTestError.shaderCompileFailed
        }
        guard let vfn = library.makeFunction(name: "sentinel_vertex"),
              let ffn = library.makeFunction(name: "sentinel_fragment") else {
            throw BindingTestError.shaderCompileFailed
        }
        let psoDesc = MTLRenderPipelineDescriptor()
        psoDesc.vertexFunction = vfn
        psoDesc.fragmentFunction = ffn
        psoDesc.colorAttachments[0].pixelFormat = targetFormat
        let pso = try context.device.makeRenderPipelineState(descriptor: psoDesc)
        return StagedStageSpec(
            name: "sentinel",
            pipelineState: pso,
            samples: [],
            writesToDrawable: false
        )
    }

    // MARK: - Tests

    @Test("encodeStage binds directPresetFragmentBuffer at slot 6")
    func encodeStage_bindsDirectPresetFragmentBuffer() throws {
        let ctx = try MetalContext()
        let pipeline = try makeRenderPipeline(context: ctx)
        let stage = try makeSentinelStage(context: ctx, targetFormat: .rgba16Float)

        // Configure the staged runtime — allocates a 16×16 offscreen target.
        let size = CGSize(width: 16, height: 16)
        pipeline.setStagedRuntime([stage], drawableSize: size)
        guard let target = pipeline.stagedTexture(named: "sentinel") else {
            throw BindingTestError.stagedTextureMissing
        }

        // Sentinel buffer: bright red so the readback is unambiguous.
        let sentinel: Float = 0.789
        guard let sentinelBuf = ctx.makeSharedBuffer(length: MemoryLayout<Float>.stride) else {
            throw BindingTestError.bufferAllocationFailed
        }
        sentinelBuf.contents().bindMemory(to: Float.self, capacity: 1).pointee = sentinel
        pipeline.setDirectPresetFragmentBuffer(sentinelBuf)

        // Drive encodeStage directly via a fresh render encoder.
        guard let cmd = ctx.commandQueue.makeCommandBuffer() else {
            throw BindingTestError.commandBufferFailed
        }
        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = target
        rpd.colorAttachments[0].loadAction = .clear
        rpd.colorAttachments[0].clearColor =
            MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        rpd.colorAttachments[0].storeAction = .store
        guard let enc = cmd.makeRenderCommandEncoder(descriptor: rpd) else {
            throw BindingTestError.encoderCreationFailed
        }
        var fv = FeatureVector()
        let stems = StemFeatures.zero
        pipeline.encodeStage(stage: stage,
                             encoder: enc,
                             features: &fv,
                             stemFeatures: stems,
                             textures: [:])
        enc.endEncoding()

        // Blit offscreen .private texture → shared so we can `getBytes`.
        let sharedDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float,
            width: 16, height: 16, mipmapped: false)
        sharedDesc.usage = [.shaderRead]
        sharedDesc.storageMode = .shared
        guard let shared = ctx.device.makeTexture(descriptor: sharedDesc),
              let blit = cmd.makeBlitCommandEncoder() else {
            throw BindingTestError.textureAllocationFailed
        }
        blit.copy(from: target, sourceSlice: 0, sourceLevel: 0,
                  sourceOrigin: MTLOriginMake(0, 0, 0),
                  sourceSize: MTLSizeMake(16, 16, 1),
                  to: shared, destinationSlice: 0, destinationLevel: 0,
                  destinationOrigin: MTLOriginMake(0, 0, 0))
        blit.endEncoding()
        cmd.commit()
        cmd.waitUntilCompleted()

        // Read back centre pixel — every pixel is identical for this shader.
        var pixel = [Float16](repeating: 0, count: 4)
        shared.getBytes(&pixel,
                        bytesPerRow: 16 * MemoryLayout<Float16>.stride * 4,
                        from: MTLRegionMake2D(8, 8, 1, 1),
                        mipmapLevel: 0)
        let red = Float(pixel[0])
        #expect(abs(red - sentinel) < 0.01,
                "encodeStage must bind directPresetFragmentBuffer at slot 6 — expected R≈\(sentinel), got \(red). If R≈0 the buffer is unbound and the V.7.7B engine fix has regressed.")
    }

    @Test("encodeStage binds directPresetFragmentBuffer2 at slot 7")
    func encodeStage_bindsDirectPresetFragmentBuffer2() throws {
        // Same plumbing — different slot. Uses a slot-7 sentinel shader so
        // both buffer(6) and buffer(7) bindings are independently regression-
        // locked. (Without this the buffer(7) line in the engine fix could
        // silently regress without buffer(6) tests catching it.)
        let ctx = try MetalContext()
        let pipeline = try makeRenderPipeline(context: ctx)

        let slot7Shader = kSentinelShader
            .replacingOccurrences(of: "[[buffer(6)]]", with: "[[buffer(7)]]")
        let options = MTLCompileOptions()
        options.languageVersion = .version3_0
        let library = try ctx.device.makeLibrary(source: slot7Shader, options: options)
        guard let vfn = library.makeFunction(name: "sentinel_vertex"),
              let ffn = library.makeFunction(name: "sentinel_fragment") else {
            throw BindingTestError.shaderCompileFailed
        }
        let psoDesc = MTLRenderPipelineDescriptor()
        psoDesc.vertexFunction = vfn
        psoDesc.fragmentFunction = ffn
        psoDesc.colorAttachments[0].pixelFormat = .rgba16Float
        let pso = try ctx.device.makeRenderPipelineState(descriptor: psoDesc)
        let stage = StagedStageSpec(name: "sentinel7",
                                    pipelineState: pso,
                                    samples: [],
                                    writesToDrawable: false)

        let size = CGSize(width: 16, height: 16)
        pipeline.setStagedRuntime([stage], drawableSize: size)
        guard let target = pipeline.stagedTexture(named: "sentinel7") else {
            throw BindingTestError.stagedTextureMissing
        }

        let sentinel: Float = 0.456
        guard let sentinelBuf = ctx.makeSharedBuffer(length: MemoryLayout<Float>.stride) else {
            throw BindingTestError.bufferAllocationFailed
        }
        sentinelBuf.contents().bindMemory(to: Float.self, capacity: 1).pointee = sentinel
        pipeline.setDirectPresetFragmentBuffer2(sentinelBuf)

        guard let cmd = ctx.commandQueue.makeCommandBuffer() else {
            throw BindingTestError.commandBufferFailed
        }
        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = target
        rpd.colorAttachments[0].loadAction = .clear
        rpd.colorAttachments[0].clearColor =
            MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        rpd.colorAttachments[0].storeAction = .store
        guard let enc = cmd.makeRenderCommandEncoder(descriptor: rpd) else {
            throw BindingTestError.encoderCreationFailed
        }
        var fv = FeatureVector()
        let stems = StemFeatures.zero
        pipeline.encodeStage(stage: stage,
                             encoder: enc,
                             features: &fv,
                             stemFeatures: stems,
                             textures: [:])
        enc.endEncoding()

        let sharedDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float,
            width: 16, height: 16, mipmapped: false)
        sharedDesc.usage = [.shaderRead]
        sharedDesc.storageMode = .shared
        guard let shared = ctx.device.makeTexture(descriptor: sharedDesc),
              let blit = cmd.makeBlitCommandEncoder() else {
            throw BindingTestError.textureAllocationFailed
        }
        blit.copy(from: target, sourceSlice: 0, sourceLevel: 0,
                  sourceOrigin: MTLOriginMake(0, 0, 0),
                  sourceSize: MTLSizeMake(16, 16, 1),
                  to: shared, destinationSlice: 0, destinationLevel: 0,
                  destinationOrigin: MTLOriginMake(0, 0, 0))
        blit.endEncoding()
        cmd.commit()
        cmd.waitUntilCompleted()

        var pixel = [Float16](repeating: 0, count: 4)
        shared.getBytes(&pixel,
                        bytesPerRow: 16 * MemoryLayout<Float16>.stride * 4,
                        from: MTLRegionMake2D(8, 8, 1, 1),
                        mipmapLevel: 0)
        let red = Float(pixel[0])
        #expect(abs(red - sentinel) < 0.01,
                "encodeStage must bind directPresetFragmentBuffer2 at slot 7 — expected R≈\(sentinel), got \(red).")
    }
}
