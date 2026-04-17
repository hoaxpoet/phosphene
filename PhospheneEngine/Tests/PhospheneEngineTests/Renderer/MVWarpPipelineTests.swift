// MVWarpPipelineTests — GPU tests for the MV-2 per-vertex feedback warp pass (D-027).
//
// Two tests verify the warp pipeline's core invariants:
//
//   1. Identity warp (zoom=1, rot=0, decay=1, warp=0): with no UV displacement and
//      decay=1, the compose pass adds nothing (alpha = 1−1 = 0) and the warp pass
//      samples at identity UV, so the output preserves the seeded warp texture content.
//
//   2. Accumulation (zoom=1.005, decay=0.99, 10 frames): each frame blends (1−0.99)=0.01
//      of the scene into the warp texture. After 10 frames the red channel must have
//      dropped by >0.01 from its initial value of 1.0 (expected Δ ≈ 0.096 at convergence).
//
// Tests compile minimal Metal source containing the preset-defined mvWarpPerFrame /
// mvWarpPerVertex functions, build the three warp pipeline states from the compiled
// library, and run GPU render passes on shared-storage textures for CPU readback.

import XCTest
import Metal
@testable import Renderer
@testable import Presets
@testable import Shared

// MARK: - MVWarpPipelineTests

final class MVWarpPipelineTests: XCTestCase {

    private var context: MetalContext!

    override func setUpWithError() throws {
        context = try MetalContext()
    }

    // MARK: - Warp Source Templates

    /// Identity: UV passthrough, no zoom, no rotation. decay=1 → compose adds nothing.
    private static let identityWarpSource = """
    MVWarpPerFrame mvWarpPerFrame(constant FeatureVector& f,
                                  constant StemFeatures&  stems,
                                  constant SceneUniforms& s) {
        MVWarpPerFrame pf;
        pf.zoom = 1.0; pf.rot = 0.0; pf.decay = 1.0; pf.warp = 0.0;
        pf.cx = 0.0; pf.cy = 0.0; pf.dx = 0.0; pf.dy = 0.0;
        pf.sx = 1.0; pf.sy = 1.0;
        pf.q1 = 0.0; pf.q2 = 0.0; pf.q3 = 0.0; pf.q4 = 0.0;
        pf.q5 = 0.0; pf.q6 = 0.0; pf.q7 = 0.0; pf.q8 = 0.0;
        return pf;
    }
    float2 mvWarpPerVertex(float2 uv, float rad, float ang,
                           thread const MVWarpPerFrame& pf,
                           constant FeatureVector& f,
                           constant StemFeatures& stems) {
        float2 centre = float2(0.5 + pf.cx, 0.5 + pf.cy);
        float2 p = uv - centre;
        float cosR = cos(pf.rot), sinR = sin(pf.rot);
        float2 rotated = float2(p.x * cosR - p.y * sinR, p.x * sinR + p.y * cosR);
        return centre + rotated / pf.zoom + float2(pf.dx, pf.dy);
    }
    """

    /// Accumulating: zoom=1.005, decay=0.99 — scene bleeds into warp each frame.
    private static let accumulatingWarpSource = """
    MVWarpPerFrame mvWarpPerFrame(constant FeatureVector& f,
                                  constant StemFeatures&  stems,
                                  constant SceneUniforms& s) {
        MVWarpPerFrame pf;
        pf.zoom = 1.005; pf.rot = 0.0; pf.decay = 0.99; pf.warp = 0.0;
        pf.cx = 0.0; pf.cy = 0.0; pf.dx = 0.0; pf.dy = 0.0;
        pf.sx = 1.0; pf.sy = 1.0;
        pf.q1 = 0.0; pf.q2 = 0.0; pf.q3 = 0.0; pf.q4 = 0.0;
        pf.q5 = 0.0; pf.q6 = 0.0; pf.q7 = 0.0; pf.q8 = 0.0;
        return pf;
    }
    float2 mvWarpPerVertex(float2 uv, float rad, float ang,
                           thread const MVWarpPerFrame& pf,
                           constant FeatureVector& f,
                           constant StemFeatures& stems) {
        float2 centre = float2(0.5 + pf.cx, 0.5 + pf.cy);
        float2 p = uv - centre;
        float cosR = cos(pf.rot), sinR = sin(pf.rot);
        float2 rotated = float2(p.x * cosR - p.y * sinR, p.x * sinR + p.y * cosR);
        return centre + rotated / pf.zoom + float2(pf.dx, pf.dy);
    }
    """

    // MARK: - Helpers

    /// Compile shaderPreamble + mvWarpPreamble + preset-defined warp source.
    private func compileWarpLibrary(warpSource: String) throws -> MTLLibrary {
        let fullSource = PresetLoader.shaderPreamble
            + "\n\n" + PresetLoader.mvWarpPreamble
            + "\n\n" + warpSource
        return try context.device.makeLibrary(source: fullSource, options: nil)
    }

    private struct WarpPipelineStates {
        let warp: MTLRenderPipelineState
        let compose: MTLRenderPipelineState
        let blit: MTLRenderPipelineState
    }

    private func buildPipelineStates(library: MTLLibrary, pixelFormat: MTLPixelFormat) throws -> WarpPipelineStates {
        let warpVertex  = try XCTUnwrap(library.makeFunction(name: "mvWarp_vertex"))
        let warpFrag    = try XCTUnwrap(library.makeFunction(name: "mvWarp_fragment"))
        let composeFrag = try XCTUnwrap(library.makeFunction(name: "mvWarp_compose_fragment"))
        let blitFrag    = try XCTUnwrap(library.makeFunction(name: "mvWarp_blit_fragment"))
        let fullscreenV = try XCTUnwrap(library.makeFunction(name: "fullscreen_vertex"))

        let warpDesc = MTLRenderPipelineDescriptor()
        warpDesc.vertexFunction   = warpVertex
        warpDesc.fragmentFunction = warpFrag
        warpDesc.colorAttachments[0].pixelFormat = pixelFormat
        let warpState = try context.device.makeRenderPipelineState(descriptor: warpDesc)

        let composeDesc = MTLRenderPipelineDescriptor()
        composeDesc.vertexFunction   = fullscreenV
        composeDesc.fragmentFunction = composeFrag
        let ca = composeDesc.colorAttachments[0]!
        ca.pixelFormat                 = pixelFormat
        ca.isBlendingEnabled           = true
        ca.sourceRGBBlendFactor        = .sourceAlpha
        ca.destinationRGBBlendFactor   = .one
        ca.sourceAlphaBlendFactor      = .zero
        ca.destinationAlphaBlendFactor = .one
        let composeState = try context.device.makeRenderPipelineState(descriptor: composeDesc)

        let blitDesc = MTLRenderPipelineDescriptor()
        blitDesc.vertexFunction   = fullscreenV
        blitDesc.fragmentFunction = blitFrag
        blitDesc.colorAttachments[0].pixelFormat = pixelFormat
        let blitState = try context.device.makeRenderPipelineState(descriptor: blitDesc)

        return WarpPipelineStates(warp: warpState, compose: composeState, blit: blitState)
    }

    /// Allocate a shared-storage texture for CPU readback.
    private func makeTexture(width: Int, height: Int, pixelFormat: MTLPixelFormat) throws -> MTLTexture {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat, width: width, height: height, mipmapped: false)
        desc.usage       = [.renderTarget, .shaderRead]
        desc.storageMode = .shared
        return try XCTUnwrap(context.device.makeTexture(descriptor: desc))
    }

    /// Fill a shared-storage `.rgba8Unorm` texture with a solid colour.
    private func fill(_ tex: MTLTexture, r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        let bytesPerRow = tex.width * 4
        var pixels = [UInt8](repeating: 0, count: tex.height * bytesPerRow)
        for i in stride(from: 0, to: pixels.count, by: 4) {
            pixels[i] = r; pixels[i+1] = g; pixels[i+2] = b; pixels[i+3] = a
        }
        tex.replace(
            region: MTLRegionMake2D(0, 0, tex.width, tex.height),
            mipmapLevel: 0,
            withBytes: &pixels,
            bytesPerRow: bytesPerRow
        )
    }

    /// Read RGBA of the centre pixel from a shared `.rgba8Unorm` texture (values in [0,1]).
    private func centrePixel(_ tex: MTLTexture) -> (r: Float, g: Float, b: Float, a: Float) {
        var px = [UInt8](repeating: 0, count: 4)
        tex.getBytes(&px,
                     bytesPerRow: tex.width * 4,
                     from: MTLRegionMake2D(tex.width / 2, tex.height / 2, 1, 1),
                     mipmapLevel: 0)
        return (Float(px[0]) / 255, Float(px[1]) / 255, Float(px[2]) / 255, Float(px[3]) / 255)
    }

    /// Zero-filled UMA buffer sized for `count` floats.
    private func zeroBuffer(count: Int) -> MTLBuffer {
        context.device.makeBuffer(
            length: MemoryLayout<Float>.stride * count, options: .storageModeShared)!
    }

    /// Run one warp frame (3 passes). After completion, copies composeTex → warpTex
    /// so the next frame starts from the accumulated result.
    private func runWarpFrame(
        states: WarpPipelineStates,
        warpTex: MTLTexture,
        composeTex: MTLTexture,
        sceneTex: MTLTexture,
        outputTex: MTLTexture,
        fvBuf: MTLBuffer,
        stemBuf: MTLBuffer,
        sceneBuf: MTLBuffer,
        decay: Float
    ) {
        guard let cmd = context.commandQueue.makeCommandBuffer() else { return }

        // Pass 1 – warp grid: sample warpTex at per-vertex warped UV × decay → composeTex.
        let warpRPD = MTLRenderPassDescriptor()
        warpRPD.colorAttachments[0].texture     = composeTex
        warpRPD.colorAttachments[0].loadAction  = .clear
        warpRPD.colorAttachments[0].storeAction = .store
        warpRPD.colorAttachments[0].clearColor  = MTLClearColorMake(0, 0, 0, 0)
        if let enc = cmd.makeRenderCommandEncoder(descriptor: warpRPD) {
            enc.setRenderPipelineState(states.warp)
            enc.setVertexBuffer(fvBuf,   offset: 0, index: 0)
            enc.setVertexBuffer(stemBuf, offset: 0, index: 1)
            enc.setVertexBuffer(sceneBuf, offset: 0, index: 2)
            enc.setFragmentTexture(warpTex, index: 0)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 4278)
            enc.endEncoding()
        }

        // Pass 2 – compose: blend sceneTex onto composeTex with alpha = (1 - decay).
        var dec = decay
        let composeRPD = MTLRenderPassDescriptor()
        composeRPD.colorAttachments[0].texture     = composeTex
        composeRPD.colorAttachments[0].loadAction  = .load
        composeRPD.colorAttachments[0].storeAction = .store
        if let enc = cmd.makeRenderCommandEncoder(descriptor: composeRPD) {
            enc.setRenderPipelineState(states.compose)
            enc.setFragmentTexture(sceneTex, index: 0)
            enc.setFragmentBytes(&dec, length: MemoryLayout<Float>.size, index: 0)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            enc.endEncoding()
        }

        // Pass 3 – blit composeTex → outputTex (the "drawable").
        let blitRPD = MTLRenderPassDescriptor()
        blitRPD.colorAttachments[0].texture     = outputTex
        blitRPD.colorAttachments[0].loadAction  = .dontCare
        blitRPD.colorAttachments[0].storeAction = .store
        if let enc = cmd.makeRenderCommandEncoder(descriptor: blitRPD) {
            enc.setRenderPipelineState(states.blit)
            enc.setFragmentTexture(composeTex, index: 0)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            enc.endEncoding()
        }

        cmd.commit()
        cmd.waitUntilCompleted()

        // Advance: copy composeTex → warpTex for the next frame's warp pass.
        if let advance = context.commandQueue.makeCommandBuffer(),
           let blitEnc = advance.makeBlitCommandEncoder() {
            blitEnc.copy(
                from: composeTex,
                sourceSlice: 0, sourceLevel: 0,
                sourceOrigin: MTLOriginMake(0, 0, 0),
                sourceSize: MTLSizeMake(composeTex.width, composeTex.height, 1),
                to: warpTex,
                destinationSlice: 0, destinationLevel: 0,
                destinationOrigin: MTLOriginMake(0, 0, 0)
            )
            blitEnc.endEncoding()
            advance.commit()
            advance.waitUntilCompleted()
        }
    }

    // MARK: - Test 1: Identity Warp Preserves Warp Texture

    /// Identity warp (zoom=1, rot=0, decay=1) must preserve the warp texture unchanged.
    ///
    /// With decay=1 the compose alpha = (1 − 1) = 0 → scene contributes nothing.
    /// The warp pass samples warpTex at identity UV, so composeTex = warpTex × 1.
    /// The blit copies composeTex → output, which must therefore equal the seeded red.
    func test_identityWarp_preservesWarpTextureContent() throws {
        let lib    = try compileWarpLibrary(warpSource: Self.identityWarpSource)
        let states = try buildPipelineStates(library: lib, pixelFormat: .rgba8Unorm)

        let w = 16, h = 16
        let warpTex    = try makeTexture(width: w, height: h, pixelFormat: .rgba8Unorm)
        let composeTex = try makeTexture(width: w, height: h, pixelFormat: .rgba8Unorm)
        let sceneTex   = try makeTexture(width: w, height: h, pixelFormat: .rgba8Unorm)
        let outputTex  = try makeTexture(width: w, height: h, pixelFormat: .rgba8Unorm)

        fill(warpTex,  r: 255, g: 0,   b: 0,   a: 255)  // red
        fill(sceneTex, r: 0,   g: 0,   b: 255, a: 255)  // blue

        let fvBuf   = zeroBuffer(count: 48)   // FeatureVector (48 floats = 192 bytes)
        let stemBuf = zeroBuffer(count: 64)   // StemFeatures  (64 floats = 256 bytes, MV-3)
        let scenBuf = zeroBuffer(count: 32)   // SceneUniforms (8 × float4 = 128 bytes)

        runWarpFrame(states: states, warpTex: warpTex, composeTex: composeTex,
                     sceneTex: sceneTex, outputTex: outputTex,
                     fvBuf: fvBuf, stemBuf: stemBuf, sceneBuf: scenBuf, decay: 1.0)

        let px = centrePixel(outputTex)
        XCTAssertGreaterThan(px.r, 0.80,
            "Identity warp (decay=1) must preserve red warp content — got R=\(px.r)")
        XCTAssertLessThan(px.b, 0.20,
            "Identity warp (decay=1) must not mix in scene blue — got B=\(px.b)")
    }

    // MARK: - Test 2: Accumulation Bleeds Scene into Warp over 10 Frames

    /// Accumulation (zoom=1.005, decay=0.99) over 10 frames: each frame contributes
    /// (1 − 0.99) = 0.01 of the scene into the warp texture.
    ///
    /// Starting from warpTex = solid red (R=1.0), scene = solid blue, after 10 frames:
    ///   R_final ≈ 0.99^10 × 1.0 ≈ 0.904  →  Δ ≈ 0.096 >> 0.01 threshold.
    func test_accumulation_bleedsSceneIntoWarpAfter10Frames() throws {
        let lib    = try compileWarpLibrary(warpSource: Self.accumulatingWarpSource)
        let states = try buildPipelineStates(library: lib, pixelFormat: .rgba8Unorm)

        let w = 16, h = 16
        let warpTex    = try makeTexture(width: w, height: h, pixelFormat: .rgba8Unorm)
        let composeTex = try makeTexture(width: w, height: h, pixelFormat: .rgba8Unorm)
        let sceneTex   = try makeTexture(width: w, height: h, pixelFormat: .rgba8Unorm)
        let outputTex  = try makeTexture(width: w, height: h, pixelFormat: .rgba8Unorm)

        fill(warpTex,  r: 255, g: 0, b: 0,   a: 255)  // red
        fill(sceneTex, r: 0,   g: 0, b: 255, a: 255)  // blue

        let fvBuf   = zeroBuffer(count: 48)
        let stemBuf = zeroBuffer(count: 64)   // StemFeatures (64 floats = 256 bytes, MV-3)
        let scenBuf = zeroBuffer(count: 32)

        let initialR = centrePixel(warpTex).r  // ≈ 1.0

        for _ in 0..<10 {
            runWarpFrame(states: states, warpTex: warpTex, composeTex: composeTex,
                         sceneTex: sceneTex, outputTex: outputTex,
                         fvBuf: fvBuf, stemBuf: stemBuf, sceneBuf: scenBuf, decay: 0.99)
        }

        let finalR = centrePixel(outputTex).r
        let delta  = initialR - finalR

        XCTAssertGreaterThan(delta, 0.01,
            "After 10 frames at decay=0.99 the red channel must drop by >0.01 (got Δ=\(delta)); "
            + "expected ≈0.096 (0.99^10 decay of scene bleeding in)")
    }
}
