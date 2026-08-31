// PresetContrastCertificationTests — Verify that overlay text has ≥4.5:1 WCAG contrast
// against any production preset frame when the `OverlayBackdropStyle` is applied. (U.9 Part C)
//
// Design contract:
//   `OverlayBackdropStyle` = .ultraThinMaterial (blur-averages preset) + Color.black.opacity(0.45).
//   The blur is approximated here as the mean luma of the rendered frame.
//   After the 0.55 alpha blend with black, white text must achieve ≥4.5:1 WCAG contrast.
//
// WCAG relative luminance formula:
//   sRGB → linear: c ≤ 0.04045 → c/12.92; else ((c+0.055)/1.055)^2.4
//   L = 0.2126R + 0.7152G + 0.0722B  (linearised)
//   contrast(L1, L2) = (max+0.05) / (min+0.05)   where L_white = 1.0 → 1.05 numerator
//
// Mesh-shader presets are skipped (cannot drawPrimitives).
// Post-process presets: pixel values are clamped at uint8 boundary — test is valid.

import Testing
import Metal
@testable import Renderer
@testable import Presets
@testable import Shared

// MARK: - PresetContrastCertificationTests

@Suite("Preset Contrast Certification Tests")
struct PresetContrastCertificationTests {

    // MARK: - Fixtures (same three as PresetAcceptanceTests)

    private var steadyFixture: FeatureVector {
        FeatureVector(bass: 0.50, mid: 0.50, treble: 0.50, time: 3.0, deltaTime: 0.016)
    }
    private var beatHeavyFixture: FeatureVector {
        var fv = FeatureVector(bass: 0.80, mid: 0.50, treble: 0.50, beatBass: 1.0, time: 5.0, deltaTime: 0.016)
        fv.bassRel = 0.60
        fv.bassDev = 0.60
        return fv
    }
    private var quietFixture: FeatureVector {
        var fv = FeatureVector(bass: 0.15, mid: 0.15, treble: 0.15, time: 2.0, deltaTime: 0.016)
        fv.bassRel = -0.70
        fv.midRel  = -0.70
        fv.trebRel = -0.70
        return fv
    }

    // MARK: - Invariant: white text contrast ≥ 4.5:1 after overlayBackdrop

    @Test(
        "White text achieves WCAG 4.5:1 contrast over any preset frame + overlayBackdrop (steady fixture)",
        arguments: _acceptanceFixture.presets
    )
    func test_whiteTextContrast_steadyFixture(_ preset: PresetLoader.LoadedPreset) throws {
        guard !preset.descriptor.passes.contains(.meshShader) else { return }
        let ctx = try MetalContext()
        var fixture = steadyFixture
        let pixels = try contrastRenderFrame(preset: preset, features: &fixture, context: ctx)
        let contrast = whiteTextContrastRatio(afterOverlayBackdrop: pixels)
        #expect(
            contrast >= 4.5,
            """
            '\(preset.descriptor.name)' steady: contrast \(String(format: "%.2f", contrast)):1 \
            < 4.5:1 minimum for overlay text
            """
        )
    }

    @Test(
        "White text achieves WCAG 4.5:1 contrast over any preset frame + overlayBackdrop (beat-heavy fixture)",
        arguments: _acceptanceFixture.presets
    )
    func test_whiteTextContrast_beatHeavyFixture(_ preset: PresetLoader.LoadedPreset) throws {
        guard !preset.descriptor.passes.contains(.meshShader) else { return }
        let ctx = try MetalContext()
        var fixture = beatHeavyFixture
        let pixels = try contrastRenderFrame(preset: preset, features: &fixture, context: ctx)
        let contrast = whiteTextContrastRatio(afterOverlayBackdrop: pixels)
        #expect(
            contrast >= 4.5,
            """
            '\(preset.descriptor.name)' beat-heavy: contrast \(String(format: "%.2f", contrast)):1 \
            < 4.5:1 minimum for overlay text
            """
        )
    }

    @Test(
        "White text achieves WCAG 4.5:1 contrast over any preset frame + overlayBackdrop (quiet fixture)",
        arguments: _acceptanceFixture.presets
    )
    func test_whiteTextContrast_quietFixture(_ preset: PresetLoader.LoadedPreset) throws {
        guard !preset.descriptor.passes.contains(.meshShader) else { return }
        let ctx = try MetalContext()
        var fixture = quietFixture
        let pixels = try contrastRenderFrame(preset: preset, features: &fixture, context: ctx)
        let contrast = whiteTextContrastRatio(afterOverlayBackdrop: pixels)
        #expect(
            contrast >= 4.5,
            """
            '\(preset.descriptor.name)' quiet: contrast \(String(format: "%.2f", contrast)):1 \
            < 4.5:1 minimum for overlay text
            """
        )
    }

    // MARK: - Rendering

    private let renderSize = 64

    /// Renders one frame reusing the PresetAcceptanceTests infrastructure.
    private func contrastRenderFrame(
        preset: PresetLoader.LoadedPreset,
        features: inout FeatureVector,
        context: MetalContext
    ) throws -> [UInt8] {
        let size = renderSize
        let texDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: context.pixelFormat, width: size, height: size, mipmapped: false)
        texDesc.usage = [.renderTarget, .shaderRead]
        texDesc.storageMode = .shared
        guard let texture = context.device.makeTexture(descriptor: texDesc) else {
            throw ContrastTestError.textureAllocationFailed
        }
        let floatStride = MemoryLayout<Float>.stride
        guard
            let fft  = context.makeSharedBuffer(length: 512 * floatStride),
            let wav  = context.makeSharedBuffer(length: 2048 * floatStride),
            let stem = context.makeSharedBuffer(length: MemoryLayout<StemFeatures>.size),
            let hist = context.makeSharedBuffer(length: 4096 * floatStride),
            let slot = context.makeSharedBuffer(length: 1024)
        else { throw ContrastTestError.bufferAllocationFailed }
        _ = stem.contents().initializeMemory(as: UInt8.self, repeating: 0, count: MemoryLayout<StemFeatures>.size)
        _ = hist.contents().initializeMemory(as: UInt8.self, repeating: 0, count: 4096 * floatStride)
        _ = slot.contents().initializeMemory(as: UInt8.self, repeating: 0, count: 1024)

        var scene: MTLBuffer?
        if preset.descriptor.passes.contains(.rayMarch),
           let buf = context.makeSharedBuffer(length: MemoryLayout<SceneUniforms>.size) {
            var su = preset.descriptor.makeSceneUniforms()
            buf.contents().copyMemory(from: &su, byteCount: MemoryLayout<SceneUniforms>.size)
            scene = buf
        }
        guard let cmdBuf = context.commandQueue.makeCommandBuffer() else {
            throw ContrastTestError.commandBufferFailed
        }
        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture      = texture
        rpd.colorAttachments[0].loadAction   = .clear
        rpd.colorAttachments[0].clearColor   = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        rpd.colorAttachments[0].storeAction  = .store
        guard let encoder = cmdBuf.makeRenderCommandEncoder(descriptor: rpd) else {
            throw ContrastTestError.encoderCreationFailed
        }
        encoder.setRenderPipelineState(preset.pipelineState)
        encoder.setFragmentBytes(&features, length: MemoryLayout<FeatureVector>.size, index: 0)
        encoder.setFragmentBuffer(fft,  offset: 0, index: 1)
        encoder.setFragmentBuffer(wav,  offset: 0, index: 2)
        encoder.setFragmentBuffer(stem, offset: 0, index: 3)
        if let sceneBuf = scene { encoder.setFragmentBuffer(sceneBuf, offset: 0, index: 4) }
        encoder.setFragmentBuffer(hist, offset: 0, index: 5)
        encoder.setFragmentBuffer(slot, offset: 0, index: 6)
        encoder.setFragmentBuffer(slot, offset: 0, index: 7)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        cmdBuf.commit()
        cmdBuf.waitUntilCompleted()
        guard cmdBuf.status == .completed else { throw ContrastTestError.renderFailed }
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        texture.getBytes(&pixels, bytesPerRow: size * 4,
                         from: MTLRegionMake2D(0, 0, size, size), mipmapLevel: 0)
        return pixels
    }

    // MARK: - Contrast Calculation

    /// Simulates `overlayBackdrop` (blur → mean luma + black@0.45) then computes WCAG
    /// contrast ratio of white text against the resulting background.
    ///
    /// The vibrancy blur is modelled as the mean pixel value across the full frame.
    /// Backdrop blending: `effective = mean × (1 − 0.45) = mean × 0.55`.
    private func whiteTextContrastRatio(afterOverlayBackdrop pixels: [UInt8]) -> Float {
        let pixelCount = pixels.count / 4
        guard pixelCount > 0 else { return 21.0 }

        // Step 1: mean sRGB per channel (BGRA format: B=0, G=1, R=2, A=3).
        var sumR: Double = 0, sumG: Double = 0, sumB: Double = 0
        for i in stride(from: 0, to: pixels.count, by: 4) {
            sumB += Double(pixels[i])
            sumG += Double(pixels[i + 1])
            sumR += Double(pixels[i + 2])
        }
        let n = Double(pixelCount)
        let meanR = sumR / n / 255.0
        let meanG = sumG / n / 255.0
        let meanB = sumB / n / 255.0

        // Step 2: simulate overlayBackdrop — 45% black blend over the mean colour.
        let blendFactor = 1.0 - 0.45   // = 0.55
        let backdropR = meanR * blendFactor
        let backdropG = meanG * blendFactor
        let backdropB = meanB * blendFactor

        // Step 3: WCAG relative luminance of the effective backdrop.
        func linearise(_ c: Double) -> Double {
            c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        let L_backdrop = 0.2126 * linearise(backdropR)
                       + 0.7152 * linearise(backdropG)
                       + 0.0722 * linearise(backdropB)

        // Step 4: WCAG contrast of white (L=1.0) against backdrop.
        let L_white: Double = 1.0
        let contrast = (L_white + 0.05) / (L_backdrop + 0.05)
        return Float(contrast)
    }

    enum ContrastTestError: Error {
        case textureAllocationFailed
        case bufferAllocationFailed
        case commandBufferFailed
        case encoderCreationFailed
        case renderFailed
    }
}
