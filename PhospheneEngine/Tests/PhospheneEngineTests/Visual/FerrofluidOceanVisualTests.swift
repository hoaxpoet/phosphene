// FerrofluidOceanVisualTests — V.9 Session 1 minimal harness.
//
// Two gates only at Session 1 (per FERROFLUID_OCEAN_CLAUDE_CODE_PROMPTS.md
// acceptance gates §1, §2, §3):
//
//   1. testFerrofluidOceanShaderCompiles — preset loads and the ray-march
//      G-buffer pipeline state is non-nil. Failed Approach #44 (silent Metal
//      compile drop) is gated by this assertion in combination with
//      `PresetLoaderCompileFailureTest` (preset count remains 15).
//
//   2. testFerrofluidOceanRendersFourFixtures — preset renders successfully
//      at the four standard fixtures (silence / steady-mid / beat-heavy /
//      quiet) and produces non-black, non-clipped output. Visual quality is
//      NOT a Session 1 gate; quality verification lives in Sessions 2–5.
//
//   3. testFerrofluidOceanIndependenceStatesReachable — D-124(d) independence
//      contract: calm-body-with-spikes (low arousal + high bass_dev) and
//      agitated-body-without-spikes (high arousal + low bass_dev) produce
//      visibly distinct frames. Pixel diff > threshold, no golden hash lock.
//
// All three tests share the deferred-ray-march render path (`RayMarchPipeline`
// driven directly), the same path used by PresetVisualReviewTests for pure
// ray-march presets.

import Metal
import XCTest
@testable import Presets
@testable import Renderer
@testable import Shared

final class FerrofluidOceanVisualTests: XCTestCase {

    private var device: MTLDevice!
    private var loader: PresetLoader!

    private static let renderWidth  = 384
    private static let renderHeight = 216

    override func setUpWithError() throws {
        device = MTLCreateSystemDefaultDevice()
        try XCTSkipIf(device == nil, "No Metal device")
        loader = PresetLoader(device: device, pixelFormat: .bgra8Unorm_srgb)
    }

    // MARK: - Gate 1: shader compiles

    func testFerrofluidOceanShaderCompiles() throws {
        let preset = try XCTUnwrap(
            loader.presets.first { $0.descriptor.name == "Ferrofluid Ocean" },
            "Ferrofluid Ocean preset not found — Metal compile likely silently dropped (Failed Approach #44)"
        )
        XCTAssertTrue(preset.descriptor.useRayMarch,
                      "V.9 Session 1 redirect expects passes to contain 'ray_march'")
        XCTAssertTrue(preset.descriptor.usePostProcess,
                      "V.9 Session 1 redirect expects passes to contain 'post_process'")
        XCTAssertNotNil(preset.pipelineState,
                        "Preset pipelineState must be non-nil after compilation")
        XCTAssertNotNil(preset.rayMarchPipelineState,
                        "Ray-march G-buffer state must be non-nil for a ray_march preset")
    }

    // MARK: - Gate 2: 4-fixture render

    func testFerrofluidOceanRendersFourFixtures() throws {
        let outDir = try makeOutputDirectory(suffix: "fixtures")
        let preset = try requirePreset()

        let fixtures: [(name: String, features: FeatureVector, stems: StemFeatures)] = [
            ("01_silence",     fixtureSilence(),     stemsZero()),
            ("02_steady_mid",  fixtureSteadyMid(),   stemsMid()),
            ("03_beat_heavy",  fixtureBeatHeavy(),   stemsBeatHeavy()),
            ("04_quiet",       fixtureQuiet(),       stemsQuiet())
        ]

        for fixture in fixtures {
            var features = fixture.features
            let stems    = fixture.stems
            let pixels   = try renderDeferredRayMarch(preset: preset,
                                                     features: &features,
                                                     stems: stems)
            try writePNG(bgraPixels: pixels,
                         width: Self.renderWidth, height: Self.renderHeight,
                         to: outDir.appendingPathComponent("\(fixture.name).png"))

            // Non-trivial output: at least some pixels with luminance above the
            // near-black floor. Threshold low enough that the calm silence state
            // (which is intentionally dark) still satisfies; high enough that an
            // all-black render fails.
            let lit = pixels.enumerated().reduce(0) { acc, idx in
                idx.offset % 4 == 3 ? acc : (acc + (idx.element > 5 ? 1 : 0))
            }
            XCTAssertGreaterThan(
                lit, 100,
                "Fixture '\(fixture.name)' produced effectively all-black output")

            // Not clipped to full white: at least one pixel below 250 in some
            // channel. (A constant-white frame would also fail visual review.)
            var anyUnderClipped = false
            for i in stride(from: 0, to: pixels.count, by: 4) where pixels[i] < 250 || pixels[i + 1] < 250 || pixels[i + 2] < 250 {
                anyUnderClipped = true
                break
            }
            XCTAssertTrue(anyUnderClipped,
                          "Fixture '\(fixture.name)' rendered fully clipped — unexpected")
        }

        print("[FerrofluidOcean V.9 Session 1] fixtures written to: \(outDir.path)")
    }

    // MARK: - Gate 3: independence states reachable (D-124(d))

    func testFerrofluidOceanIndependenceStatesReachable() throws {
        let outDir = try makeOutputDirectory(suffix: "independence")
        let preset = try requirePreset()

        // Calm body + tall spikes: low arousal, no drum accent, strong bass dev.
        var calmWithSpikes = fixtureSilence()
        calmWithSpikes.arousal = -0.5
        var stemsCalmSpikes = StemFeatures()
        stemsCalmSpikes.bassEnergy = 0.6     // makes warmup blend cross over
        stemsCalmSpikes.bassEnergyDev = 0.4

        // Agitated body + flat surface: high arousal, drum accent, no bass dev.
        var agitatedNoSpikes = fixtureSilence()
        agitatedNoSpikes.arousal = 0.5
        var stemsAgitated = StemFeatures()
        stemsAgitated.drumsEnergy = 0.6
        stemsAgitated.drumsEnergyDev = 0.3

        var calmFV     = calmWithSpikes
        var agitatedFV = agitatedNoSpikes
        let pixelsCalm     = try renderDeferredRayMarch(preset: preset, features: &calmFV, stems: stemsCalmSpikes)
        let pixelsAgitated = try renderDeferredRayMarch(preset: preset, features: &agitatedFV, stems: stemsAgitated)

        try writePNG(bgraPixels: pixelsCalm,
                     width: Self.renderWidth, height: Self.renderHeight,
                     to: outDir.appendingPathComponent("a_calm_body_with_spikes.png"))
        try writePNG(bgraPixels: pixelsAgitated,
                     width: Self.renderWidth, height: Self.renderHeight,
                     to: outDir.appendingPathComponent("b_agitated_body_no_spikes.png"))

        // The two frames should be measurably distinct — they share no audio
        // routing primitive. Sum absolute pixel difference and require it to
        // exceed a modest threshold (1 / 255 average per channel pixel).
        precondition(pixelsCalm.count == pixelsAgitated.count)
        var diff: UInt64 = 0
        for i in 0 ..< pixelsCalm.count where i % 4 != 3 {
            diff &+= UInt64(abs(Int(pixelsCalm[i]) - Int(pixelsAgitated[i])))
        }
        let pixelChannels = UInt64(pixelsCalm.count / 4 * 3)
        // Average channel difference (out of 255). Even at low absolute values,
        // 0.5 average is well above noise (typical pure-noise diff is < 0.05).
        let avg = Double(diff) / Double(pixelChannels)
        XCTAssertGreaterThan(
            avg, 0.5,
            "Independence states produced near-identical frames (avg channel diff = \(avg))")

        print("[FerrofluidOcean V.9 Session 1] independence frames written to: \(outDir.path) (avg diff = \(avg))")
    }

    // MARK: - Render

    private func renderDeferredRayMarch(
        preset: PresetLoader.LoadedPreset,
        features: inout FeatureVector,
        stems: StemFeatures
    ) throws -> [UInt8] {
        let context       = try MetalContext()
        let shaderLibrary = try ShaderLibrary(context: context)
        let pipeline      = try RayMarchPipeline(context: context,
                                                 shaderLibrary: shaderLibrary)
        pipeline.allocateTextures(width: Self.renderWidth, height: Self.renderHeight)

        var sceneUniforms = preset.descriptor.makeSceneUniforms()
        sceneUniforms.sceneParamsA.y = Float(Self.renderWidth) / Float(Self.renderHeight)
        pipeline.sceneUniforms = sceneUniforms

        let floatStride = MemoryLayout<Float>.stride
        let fftBuf = try XCTUnwrap(context.makeSharedBuffer(length: 512 * floatStride))
        let wavBuf = try XCTUnwrap(context.makeSharedBuffer(length: 2048 * floatStride))

        let outDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: context.pixelFormat,
            width: Self.renderWidth, height: Self.renderHeight, mipmapped: false)
        outDesc.usage = [.renderTarget, .shaderRead]
        outDesc.storageMode = .shared
        let outTex = try XCTUnwrap(context.device.makeTexture(descriptor: outDesc))

        let cmdBuf = try XCTUnwrap(context.commandQueue.makeCommandBuffer())
        let gbufferState = try XCTUnwrap(
            preset.rayMarchPipelineState,
            "Ferrofluid Ocean missing rayMarchPipelineState — Session 1 expects ray_march pass")

        pipeline.render(
            gbufferPipelineState: gbufferState,
            features: &features,
            fftBuffer: fftBuf,
            waveformBuffer: wavBuf,
            stemFeatures: stems,
            outputTexture: outTex,
            commandBuffer: cmdBuf,
            noiseTextures: nil,
            iblManager: nil,
            postProcessChain: nil,
            presetFragmentBuffer3: nil
        )
        cmdBuf.commit()
        cmdBuf.waitUntilCompleted()
        XCTAssertEqual(cmdBuf.status, .completed,
                       "Render command buffer failed: \(String(describing: cmdBuf.error))")

        var pixels = [UInt8](repeating: 0,
                             count: Self.renderWidth * Self.renderHeight * 4)
        outTex.getBytes(&pixels,
                        bytesPerRow: Self.renderWidth * 4,
                        from: MTLRegionMake2D(0, 0, Self.renderWidth, Self.renderHeight),
                        mipmapLevel: 0)
        return pixels
    }

    // MARK: - Helpers

    private func requirePreset() throws -> PresetLoader.LoadedPreset {
        try XCTUnwrap(
            loader.presets.first { $0.descriptor.name == "Ferrofluid Ocean" },
            "Ferrofluid Ocean preset not found")
    }

    private func makeOutputDirectory(suffix: String) throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("PhospheneFerrofluidOceanV9Session1")
            .appendingPathComponent(suffix)
        try FileManager.default.createDirectory(at: url,
                                                withIntermediateDirectories: true)
        return url
    }

    private func writePNG(bgraPixels: [UInt8],
                          width: Int, height: Int,
                          to url: URL) throws {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width, height: height, mipmapped: false)
        desc.usage = [.shaderRead]
        desc.storageMode = .shared
        let tex = try XCTUnwrap(device.makeTexture(descriptor: desc))
        bgraPixels.withUnsafeBytes { bytes in
            tex.replace(region: MTLRegionMake2D(0, 0, width, height),
                        mipmapLevel: 0,
                        withBytes: bytes.baseAddress!,
                        bytesPerRow: width * 4)
        }
        _ = writeTextureToPNG(tex, url: url)
    }

    // MARK: - Fixtures

    private func fixtureSilence() -> FeatureVector {
        FeatureVector(
            time: 1.0, deltaTime: 1.0 / 60.0,
            aspectRatio: Float(Self.renderWidth) / Float(Self.renderHeight),
            accumulatedAudioTime: 1.0
        )
    }

    private func fixtureSteadyMid() -> FeatureVector {
        var fv = FeatureVector(
            bass: 0.5, mid: 0.5, treble: 0.4,
            bassAtt: 0.5, midAtt: 0.5, trebleAtt: 0.4,
            arousal: 0.0,
            time: 5.0, deltaTime: 1.0 / 60.0,
            aspectRatio: Float(Self.renderWidth) / Float(Self.renderHeight),
            accumulatedAudioTime: 5.0
        )
        fv.bassAttRel = 0.0
        return fv
    }

    private func fixtureBeatHeavy() -> FeatureVector {
        var fv = FeatureVector(
            bass: 0.75, mid: 0.55, treble: 0.45,
            bassAtt: 0.7, midAtt: 0.55, trebleAtt: 0.45,
            beatBass: 0.85, beatComposite: 0.6,
            arousal: 0.6,
            time: 10.0, deltaTime: 1.0 / 60.0,
            aspectRatio: Float(Self.renderWidth) / Float(Self.renderHeight),
            accumulatedAudioTime: 10.0
        )
        fv.bassAttRel = 0.4
        return fv
    }

    private func fixtureQuiet() -> FeatureVector {
        var fv = FeatureVector(
            bass: 0.3, mid: 0.25, treble: 0.2,
            bassAtt: 0.3, midAtt: 0.25, trebleAtt: 0.2,
            arousal: -0.3,
            time: 15.0, deltaTime: 1.0 / 60.0,
            aspectRatio: Float(Self.renderWidth) / Float(Self.renderHeight),
            accumulatedAudioTime: 15.0
        )
        fv.bassAttRel = -0.2
        return fv
    }

    private func stemsZero() -> StemFeatures { .zero }

    private func stemsMid() -> StemFeatures {
        var s = StemFeatures(vocalsEnergy: 0.4,
                             drumsEnergy: 0.4,
                             bassEnergy: 0.4,
                             otherEnergy: 0.3)
        s.bassEnergyDev = 0.1
        s.drumsEnergyDev = 0.1
        return s
    }

    private func stemsBeatHeavy() -> StemFeatures {
        var s = StemFeatures(vocalsEnergy: 0.5,
                             drumsEnergy: 0.7, drumsBeat: 0.9,
                             bassEnergy: 0.7,
                             otherEnergy: 0.4)
        s.bassEnergyDev = 0.4
        s.drumsEnergyDev = 0.35
        return s
    }

    private func stemsQuiet() -> StemFeatures {
        StemFeatures(vocalsEnergy: 0.15,
                     drumsEnergy: 0.15,
                     bassEnergy: 0.15,
                     otherEnergy: 0.1)
    }
}
