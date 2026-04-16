// FerrofluidOceanVisualTests — Visual regression tests for the Ferrofluid Ocean preset.
//
// Renders the shader across 8 audio states (silence → full stems active) and writes
// PNGs to $TMPDIR/PhospheneFerrofluidOceanVisualTests/ for visual inspection.
//
// Tests verify: shader compilation, non-trivial pixel output, HDR values for bloom.

import Metal
import MetalKit
import XCTest
@testable import Presets
@testable import Renderer
@testable import Shared

final class FerrofluidOceanVisualTests: XCTestCase {

    private var device: MTLDevice!
    private var loader: PresetLoader!

    override func setUpWithError() throws {
        device = MTLCreateSystemDefaultDevice()
        try XCTSkipIf(device == nil, "No Metal device")
        loader = PresetLoader(device: device, pixelFormat: .bgra8Unorm_srgb)
    }

    // MARK: - Shader Compilation

    func testFerrofluidOceanShaderCompiles() throws {
        let preset = try XCTUnwrap(
            loader.presets.first { $0.descriptor.name == "Ferrofluid Ocean" },
            "Ferrofluid Ocean preset not found in built-in presets"
        )
        XCTAssertNotNil(preset.pipelineState)
        XCTAssertTrue(preset.descriptor.usePostProcess)
    }

    // MARK: - Audio State Rendering

    func testRenderAllAudioStates() throws {
        let preset = try XCTUnwrap(
            loader.presets.first { $0.descriptor.name == "Ferrofluid Ocean" }
        )

        let context = try MetalContext()
        let shaderLib = try ShaderLibrary(context: context)
        let chain = try PostProcessChain(context: context, shaderLibrary: shaderLib)

        let width = 512, height = 288
        chain.allocateTextures(width: width, height: height)

        let outputDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm_srgb,
            width: width, height: height,
            mipmapped: false
        )
        outputDesc.usage = [.renderTarget, .shaderRead]
        outputDesc.storageMode = .shared
        let outputTexture = device.makeTexture(descriptor: outputDesc)!

        // Create dummy FFT + waveform buffers
        let fftBuf = device.makeBuffer(
            length: 512 * MemoryLayout<Float>.size, options: .storageModeShared
        )!
        let wavBuf = device.makeBuffer(
            length: 2048 * MemoryLayout<Float>.size, options: .storageModeShared
        )!

        // 8 audio states simulating progression from silence to full stems active
        let states: [(String, FeatureVector, StemFeatures)] = [
            ("01_silence", makeFeatures(time: 1.0), makeStemFeatures()),
            ("02_bass_only", makeFeatures(time: 5.0, bass: 0.6), makeStemFeatures(bassE: 0.6)),
            ("03_vocals_enter",
             makeFeatures(time: 15.0, bass: 0.5, mid: 0.5),
             makeStemFeatures(bassE: 0.5, vocalsE: 0.5)),
            ("04_full_chorus",
             makeFeatures(time: 30.0, bass: 0.8, mid: 0.7, treble: 0.5),
             makeStemFeatures(bassE: 0.8, vocalsE: 0.7, drumsB: 0.9, drumsE: 0.6)),
            ("05_drum_flash",
             makeFeatures(time: 35.0, bass: 0.5, mid: 0.3, beatBass: 0.8),
             makeStemFeatures(bassE: 0.5, vocalsE: 0.3, drumsB: 1.0, drumsE: 0.8)),
            ("06_ambient_low",
             makeFeatures(time: 45.0, bass: 0.2, mid: 0.15, treble: 0.1),
             makeStemFeatures(bassE: 0.2, vocalsE: 0.15)),
            ("07_ultrawide",
             makeFeatures(time: 20.0, bass: 0.6, mid: 0.5, aspect: 2.35),
             makeStemFeatures(bassE: 0.6, vocalsE: 0.5)),
            ("08_portrait",
             makeFeatures(time: 20.0, bass: 0.6, mid: 0.5, aspect: 0.5625),
             makeStemFeatures(bassE: 0.6, vocalsE: 0.5))
        ]

        let outDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("PhospheneFerrofluidOceanVisualTests")
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        for (name, var features, stems) in states {
            guard let cmdBuf = context.commandQueue.makeCommandBuffer() else { continue }
            chain.render(
                scenePipelineState: preset.pipelineState,
                features: &features,
                fftBuffer: fftBuf,
                waveformBuffer: wavBuf,
                stemFeatures: stems,
                outputTexture: outputTexture,
                commandBuffer: cmdBuf
            )
            cmdBuf.commit()
            cmdBuf.waitUntilCompleted()

            let url = outDir.appendingPathComponent("\(name).png")
            writeTextureToPNG(outputTexture, url: url)
        }

        print("Ferrofluid Ocean visual test PNGs written to: \(outDir.path)")

        // Verify non-trivial output: at least some pixels should be non-black
        for (name, var features, stems) in states {
            guard let cmdBuf = context.commandQueue.makeCommandBuffer() else { continue }
            chain.render(
                scenePipelineState: preset.pipelineState,
                features: &features,
                fftBuffer: fftBuf,
                waveformBuffer: wavBuf,
                stemFeatures: stems,
                outputTexture: outputTexture,
                commandBuffer: cmdBuf
            )
            cmdBuf.commit()
            cmdBuf.waitUntilCompleted()

            var pixels = [UInt8](repeating: 0, count: width * height * 4)
            outputTexture.getBytes(
                &pixels,
                bytesPerRow: width * 4,
                from: MTLRegionMake2D(0, 0, width, height),
                mipmapLevel: 0
            )
            let nonZero = pixels.reduce(0) { $0 + ($1 > 5 ? 1 : 0) }
            XCTAssertGreaterThan(
                nonZero, 100,
                "State '\(name)' produced nearly all-black output"
            )
        }
    }

    // MARK: - HDR Output

    func testHDROutputExceedsSDR() throws {
        let preset = try XCTUnwrap(
            loader.presets.first { $0.descriptor.name == "Ferrofluid Ocean" }
        )

        let context = try MetalContext()
        let shaderLib = try ShaderLibrary(context: context)
        let chain = try PostProcessChain(context: context, shaderLibrary: shaderLib)

        let width = 256, height = 144
        chain.allocateTextures(width: width, height: height)

        // Render with drum flash active → should produce HDR values in scene texture
        var features = makeFeatures(time: 30.0, bass: 0.7, mid: 0.5, beatBass: 0.8)
        let stems = makeStemFeatures(bassE: 0.7, vocalsE: 0.5, drumsB: 1.0, drumsE: 0.8)
        let sceneTexture = chain.sceneTexture!

        let fftBuf = device.makeBuffer(
            length: 512 * MemoryLayout<Float>.size, options: .storageModeShared
        )!
        let wavBuf = device.makeBuffer(
            length: 2048 * MemoryLayout<Float>.size, options: .storageModeShared
        )!
        let outputDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm_srgb,
            width: width, height: height,
            mipmapped: false
        )
        outputDesc.usage = [.renderTarget, .shaderRead]
        outputDesc.storageMode = .shared
        let outputTexture = device.makeTexture(descriptor: outputDesc)!

        guard let cmdBuf = context.commandQueue.makeCommandBuffer() else {
            XCTFail("Failed to create command buffer")
            return
        }
        chain.render(
            scenePipelineState: preset.pipelineState,
            features: &features,
            fftBuffer: fftBuf,
            waveformBuffer: wavBuf,
            stemFeatures: stems,
            outputTexture: outputTexture,
            commandBuffer: cmdBuf
        )
        cmdBuf.commit()
        cmdBuf.waitUntilCompleted()

        // Read the HDR scene texture (rgba16Float) — check for values > 1.0
        var hdrPixels = [UInt16](repeating: 0, count: width * height * 4)
        sceneTexture.getBytes(
            &hdrPixels,
            bytesPerRow: width * 4 * MemoryLayout<UInt16>.size,
            from: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0
        )

        // Count pixels with any channel > 1.0 (Half float: exponent > 15)
        var hdrCount = 0
        for i in stride(from: 0, to: hdrPixels.count, by: 4) {
            for c in 0 ..< 3 {
                let half = hdrPixels[i + c]
                let exponent = (half >> 10) & 0x1F
                if exponent > 15 { hdrCount += 1; break }
            }
        }

        XCTAssertGreaterThan(
            hdrCount, 10,
            "Drum flash should produce HDR (>1.0) pixels for bloom. Found \(hdrCount)."
        )
    }

    // MARK: - Helpers

    private func makeFeatures(
        time: Float,
        bass: Float = 0, mid: Float = 0, treble: Float = 0,
        beatBass: Float = 0, aspect: Float = 1.778
    ) -> FeatureVector {
        FeatureVector(
            bass: bass, mid: mid, treble: treble,
            bassAtt: bass * 0.7, midAtt: mid * 0.7, trebleAtt: treble * 0.7,
            subBass: bass * 0.8, lowBass: bass * 0.6,
            lowMid: mid * 0.5, midHigh: mid * 0.3,
            highMid: treble * 0.5, high: treble * 0.3,
            beatBass: beatBass, beatMid: 0, beatTreble: 0, beatComposite: beatBass * 0.5,
            spectralCentroid: 0.4, spectralFlux: mid * 0.3,
            valence: 0, arousal: bass,
            time: time, deltaTime: 1.0 / 60.0,
            aspectRatio: aspect
        )
    }

    private func makeStemFeatures(
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
}
