// KineticSculptureTests — Visual integration tests for the Kinetic Sculpture preset.
//
// Verifies:
//   1. Shader compiles as a ray march preset (G-buffer pipeline state non-nil).
//   2. Renders non-black output to an offscreen HDR texture with active audio.
//   3. Lit texture (rgba16Float) contains no NaN or Inf values.
//
// All tests render to 256×144 offscreen textures.  No display or window required.

import Metal
import XCTest
@testable import Presets
@testable import Renderer
@testable import Shared

// MARK: - KineticSculptureTests

final class KineticSculptureTests: XCTestCase {

    // MARK: - Test Infrastructure

    private var device: MTLDevice!
    private var loader: PresetLoader!
    private var context: MetalContext!
    private var shaderLib: ShaderLibrary!
    private var pipeline: RayMarchPipeline!

    private let testWidth  = 256
    private let testHeight = 144

    override func setUpWithError() throws {
        device    = MTLCreateSystemDefaultDevice()
        try XCTSkipIf(device == nil, "No Metal device available — skipping GPU tests")
        context   = try MetalContext()
        shaderLib = try ShaderLibrary(context: context)
        pipeline  = try RayMarchPipeline(context: context, shaderLibrary: shaderLib)
        pipeline.allocateTextures(width: testWidth, height: testHeight)
        pipeline.sceneUniforms = makeSceneUniforms()
        loader    = PresetLoader(device: device, pixelFormat: .bgra8Unorm)
    }

    // MARK: - Test 1: Shader Compilation

    /// Verifies the preset is discovered, compiles cleanly, and declares
    /// both ray_march and post_process passes.
    func test_kineticSculptureShaderCompilesAsRayMarchPreset() throws {
        let preset = try XCTUnwrap(
            loader.presets.first { $0.descriptor.name == "Kinetic Sculpture" },
            "Kinetic Sculpture not found; ensure KineticSculpture.metal is in the Shaders/ bundle"
        )
        XCTAssertNotNil(preset.rayMarchPipelineState,
            "Kinetic Sculpture must have a non-nil ray march G-buffer pipeline state")
        XCTAssertTrue(preset.descriptor.passes.contains(.rayMarch),
            "Kinetic Sculpture descriptor must include .rayMarch in passes")
        XCTAssertTrue(preset.descriptor.passes.contains(.postProcess),
            "Kinetic Sculpture descriptor must include .postProcess in passes")
    }

    // MARK: - Test 2: Non-Black Offscreen Output

    /// Renders the preset with active audio (bass 0.7, beat pulse 0.0) and
    /// asserts that at least 200 bytes in the output texture are non-trivially
    /// non-zero (> 5 out of 255), confirming geometry is visible.
    func test_kineticSculptureRendersNonBlackOutputWithActiveAudio() throws {
        let gbufferState = try ksGBufferState()
        let chain        = try PostProcessChain(context: context, shaderLibrary: shaderLib)
        chain.allocateTextures(width: testWidth, height: testHeight)
        let outputTex    = try makeOutputTexture()

        var features = makeFeatures(time: 5.0, bass: 0.7, mid: 0.5, sub: 0.6, accum: 2.5)
        let stems    = makeStemFeatures(bassE: 0.7, vocalsE: 0.4, drumsB: 0.8, drumsE: 0.5)

        try renderOneFrame(gbufferState: gbufferState, chain: chain,
                           outputTex: outputTex, features: &features, stems: stems)

        var raw = [UInt8](repeating: 0, count: testWidth * testHeight * 4)
        outputTex.getBytes(
            &raw,
            bytesPerRow: testWidth * 4,
            from: MTLRegionMake2D(0, 0, testWidth, testHeight),
            mipmapLevel: 0
        )
        let nonZero = raw.reduce(0) { $0 + ($1 > 5 ? 1 : 0) }
        XCTAssertGreaterThan(
            nonZero, 200,
            "Kinetic Sculpture should produce visible (non-black) output; got \(nonZero) non-zero bytes"
        )
    }

    // MARK: - Test 3: No NaN / Inf in Lit Texture

    /// Renders a frame and inspects every Float16 value in the HDR lit texture
    /// (rgba16Float).  Any NaN indicates degenerate SDF geometry; any Inf
    /// indicates a divide-by-zero in Cook-Torrance BRDF evaluation.
    func test_kineticSculptureLitTextureContainsNoNaNOrInf() throws {
        let gbufferState = try ksGBufferState()
        let chain        = try PostProcessChain(context: context, shaderLibrary: shaderLib)
        chain.allocateTextures(width: testWidth, height: testHeight)
        let outputTex    = try makeOutputTexture()

        var features = makeFeatures(time: 10.0, bass: 0.5, mid: 0.4, sub: 0.4, accum: 1.5)
        let stems    = StemFeatures.zero

        try renderOneFrame(gbufferState: gbufferState, chain: chain,
                           outputTex: outputTex, features: &features, stems: stems)

        let litTex = try XCTUnwrap(
            pipeline.litTexture,
            "litTexture must be allocated after a render pass"
        )

        var pixels = [Float16](repeating: 0, count: testWidth * testHeight * 4)
        litTex.getBytes(
            &pixels,
            bytesPerRow: testWidth * 4 * MemoryLayout<Float16>.stride,
            from: MTLRegionMake2D(0, 0, testWidth, testHeight),
            mipmapLevel: 0
        )

        let hasNaN = pixels.contains { Float($0).isNaN }
        let hasInf = pixels.contains { Float($0).isInfinite }
        XCTAssertFalse(
            hasNaN,
            "Lit texture must not contain NaN — check for degenerate SDF or PBR singularity"
        )
        XCTAssertFalse(
            hasInf,
            "Lit texture must not contain Inf — check for divide-by-zero in Cook-Torrance BRDF"
        )
    }
}

// MARK: - Private Helpers

private extension KineticSculptureTests {

    // MARK: Pipeline

    func ksGBufferState() throws -> MTLRenderPipelineState {
        let preset = try XCTUnwrap(
            loader.presets.first { $0.descriptor.name == "Kinetic Sculpture" },
            "Kinetic Sculpture preset not found in bundle"
        )
        return try XCTUnwrap(
            preset.rayMarchPipelineState,
            "Kinetic Sculpture rayMarchPipelineState must be non-nil"
        )
    }

    // MARK: Texture / Buffer Allocation

    func makeOutputTexture() throws -> MTLTexture {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm_srgb,
            width: testWidth, height: testHeight,
            mipmapped: false
        )
        desc.usage       = [.renderTarget, .shaderRead]
        desc.storageMode = .shared
        return try XCTUnwrap(
            device.makeTexture(descriptor: desc),
            "Failed to allocate \(testWidth)×\(testHeight) output texture"
        )
    }

    func makeZeroBuffer(count: Int) throws -> MTLBuffer {
        let buf = try XCTUnwrap(
            device.makeBuffer(
                length: count * MemoryLayout<Float>.stride,
                options: .storageModeShared
            ),
            "Failed to allocate buffer of \(count) floats"
        )
        memset(buf.contents(), 0, buf.length)
        return buf
    }

    // MARK: Render

    func renderOneFrame(
        gbufferState: MTLRenderPipelineState,
        chain: PostProcessChain,
        outputTex: MTLTexture,
        features: inout FeatureVector,
        stems: StemFeatures
    ) throws {
        let fftBuf  = try makeZeroBuffer(count: 512)
        let waveBuf = try makeZeroBuffer(count: 2048)

        guard let cmdBuf = context.commandQueue.makeCommandBuffer() else {
            throw KSTestError.commandBufferFailed
        }

        pipeline.render(
            gbufferPipelineState: gbufferState,
            features: &features,
            fftBuffer: fftBuf,
            waveformBuffer: waveBuf,
            stemFeatures: stems,
            outputTexture: outputTex,
            commandBuffer: cmdBuf,
            noiseTextures: nil,
            postProcessChain: chain
        )
        cmdBuf.commit()
        cmdBuf.waitUntilCompleted()

        if let error = cmdBuf.error {
            throw KSTestError.gpuError(error)
        }
    }

    // MARK: Feature Factories

    func makeFeatures(
        time: Float,
        bass: Float = 0, mid: Float = 0,
        sub: Float = 0, accum: Float = 0
    ) -> FeatureVector {
        FeatureVector(
            bass: bass, mid: mid, treble: mid * 0.5,
            bassAtt: bass * 0.7, midAtt: mid * 0.7, trebleAtt: mid * 0.35,
            subBass: sub, lowBass: bass * 0.6,
            lowMid: mid * 0.5, midHigh: mid * 0.35,
            highMid: mid * 0.2, high: mid * 0.15,
            beatBass: 0, beatMid: 0, beatTreble: 0, beatComposite: 0,
            spectralCentroid: 0.35, spectralFlux: mid * 0.2,
            valence: 0, arousal: bass * 0.5,
            time: time, deltaTime: 1.0 / 60.0,
            aspectRatio: Float(testWidth) / Float(testHeight),
            accumulatedAudioTime: accum
        )
    }

    func makeStemFeatures(
        bassE: Float = 0, vocalsE: Float = 0,
        drumsB: Float = 0, drumsE: Float = 0
    ) -> StemFeatures {
        StemFeatures(
            vocalsEnergy: vocalsE, vocalsBand0: vocalsE * 0.5,
            vocalsBand1: vocalsE * 0.3, vocalsBeat: 0,
            drumsEnergy: drumsE, drumsBand0: drumsE * 0.6,
            drumsBand1: drumsE * 0.4, drumsBeat: drumsB,
            bassEnergy: bassE, bassBand0: bassE * 0.7,
            bassBand1: bassE * 0.5, bassBeat: 0,
            otherEnergy: 0, otherBand0: 0, otherBand1: 0, otherBeat: 0
        )
    }

    // MARK: Scene Uniforms

    func makeSceneUniforms() -> SceneUniforms {
        // Camera at (0, 0, -5) looking along +Z — lattice (cell size 2.0) is
        // centred at origin so the first geometry hit is at roughly z ≈ -1.
        var uniforms = SceneUniforms()
        uniforms.cameraOriginAndFov        = SIMD4(0, 0, -5, Float.pi / 4)
        uniforms.cameraForward             = SIMD4(0, 0,  1, 0)
        uniforms.cameraRight               = SIMD4(1, 0,  0, 0)
        uniforms.cameraUp                  = SIMD4(0, 1,  0, 0)
        uniforms.lightPositionAndIntensity = SIMD4(4, 7, -4, 3.5)
        uniforms.lightColor                = SIMD4(1, 0.96, 0.88, 0)
        uniforms.sceneParamsA              = SIMD4(0, Float(testWidth) / Float(testHeight), 0.1, 20)
        uniforms.sceneParamsB              = SIMD4(15, 20, 0.06, 0)
        return uniforms
    }
}

// MARK: - Test Errors

private enum KSTestError: Error {
    case commandBufferFailed
    case gpuError(Error)
}
