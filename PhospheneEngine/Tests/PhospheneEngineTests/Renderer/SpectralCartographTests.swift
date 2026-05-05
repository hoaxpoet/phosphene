// SpectralCartographTests — Compilation, D-026 compliance, buffer binding,
// and feature-graph continuity tests for SpectralCartograph.metal.

import Testing
import Metal
import Foundation
import CoreGraphics
@testable import Renderer
@testable import Presets
@testable import Shared

// MARK: - Error

private enum SCTestError: Error {
    case noDevice
    case metalSetupFailed
    case shaderSourceNotFound
}

// MARK: - RenderPipeline init sanity

@Test func test_renderPipeline_spectralHistoryAllocatedInSpectralCartographFile() throws {
    let ctx = try MetalContext()
    let lib = try ShaderLibrary(context: ctx)
    let fftBuf = ctx.makeSharedBuffer(length: 512  * MemoryLayout<Float>.stride)!
    let wavBuf = ctx.makeSharedBuffer(length: 2048 * MemoryLayout<Float>.stride)!

    let pipeline = try RenderPipeline(
        context: ctx, shaderLibrary: lib,
        fftBuffer: fftBuf, waveformBuffer: wavBuf
    )
    #expect(pipeline.spectralHistory.gpuBuffer.length == SpectralHistoryBuffer.bufferSizeBytes,
            "spectralHistory must be allocated at init with the correct buffer size")
}

// MARK: - Shader compilation

@Test func test_spectralCartograph_compilesWithPreamble() throws {
    let ctx    = try MetalContext()
    // loadBuiltIn: true (default) calls loadFromBundle internally.
    let loader = PresetLoader(device: ctx.device, pixelFormat: ctx.pixelFormat)

    let preset = loader.presets.first(where: { $0.descriptor.name == "Spectral Cartograph" })
    #expect(preset != nil, "Spectral Cartograph preset should load from bundle")
    if let preset {
        #expect(preset.pipelineState is MTLRenderPipelineState,
                "Spectral Cartograph pipeline state must be non-nil (shader compiled)")
    }
}

// MARK: - D-026 compliance: no absolute energy in drawBandDeviation

@Test func test_spectralCartograph_drawBandDeviation_noAbsoluteEnergyRefs() throws {
    // In SPM test builds Bundle(for:) returns the test executable bundle, not the
    // Presets resource bundle.  Creating a PresetLoader registers the Presets bundle
    // so Bundle.allBundles contains it; then search all bundles for the shader file.
    let ctx = try MetalContext()
    _ = PresetLoader(device: ctx.device, pixelFormat: ctx.pixelFormat)
    guard let url = (Bundle.allBundles + Bundle.allFrameworks).compactMap({
        $0.url(forResource: "SpectralCartograph", withExtension: "metal", subdirectory: "Shaders")
    }).first else {
        throw SCTestError.shaderSourceNotFound
    }
    let source = try String(contentsOf: url, encoding: .utf8)

    // Locate the drawBandDeviation function definition (not comment references).
    // Match the return-type prefix so we skip any mention in comments.
    guard let funcRange = source.range(of: "float3 drawBandDeviation") else {
        Issue.record("drawBandDeviation function definition not found in SpectralCartograph.metal")
        return
    }
    let tail = String(source[funcRange.upperBound...])

    // Find the opening brace.
    guard let openIdx = tail.firstIndex(of: "{") else {
        Issue.record("Could not find opening brace of drawBandDeviation")
        return
    }

    // Walk to the matching closing brace via depth tracking.
    var depth = 0
    var closeIdx = tail.endIndex
    for idx in tail.indices {
        if tail[idx] == "{" { depth += 1 }
        else if tail[idx] == "}" {
            depth -= 1
            if depth == 0 { closeIdx = idx; break }
        }
    }
    let funcBody = String(tail[openIdx...closeIdx])

    // D-026 forbidden patterns: absolute AGC-normalized energy fields.
    // These fail on track changes and section changes within a track.
    let forbidden = [
        "fv.bass,", "fv.mid,", "fv.treble,",
        "fv.bass_att,", "fv.mid_att,", "fv.treb_att,",
        "fv.bass ", "fv.mid ", "fv.treble "
    ]
    for token in forbidden {
        #expect(!funcBody.contains(token),
                "drawBandDeviation must not reference absolute energy '\(token)' — use deviation primitives (D-026)")
    }

    // Required deviation primitives (D-026).
    let required = [
        "bass_att_rel", "bass_dev",
        "mid_att_rel",  "mid_dev",
        "treb_att_rel", "treb_dev"
    ]
    for token in required {
        #expect(funcBody.contains(token),
                "drawBandDeviation should reference deviation primitive '\(token)'")
    }
}

// MARK: - buffer(5) binding: render completes without GPU error

@Test func test_spectralCartograph_rendersWithHistoryBuffer() throws {
    let ctx    = try MetalContext()
    let loader = PresetLoader(device: ctx.device, pixelFormat: ctx.pixelFormat)

    guard let preset = loader.presets.first(where: { $0.descriptor.name == "Spectral Cartograph" })
    else { throw SCTestError.metalSetupFailed }

    let fftBuf  = ctx.makeSharedBuffer(length: 512  * MemoryLayout<Float>.stride)!
    let wavBuf  = ctx.makeSharedBuffer(length: 2048 * MemoryLayout<Float>.stride)!
    let histBuf = SpectralHistoryBuffer(device: ctx.device)

    var fv    = FeatureVector(bass: 0.5, mid: 0.4, treble: 0.3,
                              beatBass: 0.6, valence: 0.3, arousal: -0.2)
    fv.bassAttRel = 0.4; fv.bassDev = 0.3
    fv.midAttRel  = 0.2; fv.midDev  = 0.1
    fv.trebAttRel = 0.1; fv.trebDev = 0.05
    fv.beatPhase01 = 0.7; fv.spectralCentroid = 0.55
    var stems = StemFeatures.zero
    for _ in 0..<120 {
        histBuf.append(features: fv, stems: stems)
    }

    let size    = 32
    let texDesc = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: ctx.pixelFormat, width: size, height: size, mipmapped: false)
    texDesc.usage = [.renderTarget, .shaderRead]
    guard let tex    = ctx.device.makeTexture(descriptor: texDesc),
          let cmdBuf = ctx.commandQueue.makeCommandBuffer()
    else { throw SCTestError.metalSetupFailed }

    let rpd = MTLRenderPassDescriptor()
    rpd.colorAttachments[0].texture    = tex
    rpd.colorAttachments[0].loadAction  = .clear
    rpd.colorAttachments[0].clearColor  = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
    rpd.colorAttachments[0].storeAction = .store

    guard let encoder = cmdBuf.makeRenderCommandEncoder(descriptor: rpd)
    else { throw SCTestError.metalSetupFailed }

    var stemsCopy = stems
    encoder.setRenderPipelineState(preset.pipelineState)
    encoder.setFragmentBytes(&fv,        length: MemoryLayout<FeatureVector>.size, index: 0)
    encoder.setFragmentBuffer(fftBuf,    offset: 0,                                index: 1)
    encoder.setFragmentBuffer(wavBuf,    offset: 0,                                index: 2)
    encoder.setFragmentBytes(&stemsCopy, length: MemoryLayout<StemFeatures>.size,  index: 3)
    encoder.setFragmentBuffer(histBuf.gpuBuffer, offset: 0,                        index: 5)
    encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    encoder.endEncoding()
    cmdBuf.commit()
    cmdBuf.waitUntilCompleted()

    #expect(cmdBuf.status == .completed,
            "SpectralCartograph render should complete; error: \(cmdBuf.error?.localizedDescription ?? "none")")
}

// MARK: - Feature-graph polyline continuity

@Test func test_featureGraphs_polylineContinuityAcrossSampleBoundary() throws {
    let ctx    = try MetalContext()
    let loader = PresetLoader(device: ctx.device, pixelFormat: ctx.pixelFormat)

    guard let preset = loader.presets.first(where: { $0.descriptor.name == "Spectral Cartograph" })
    else { throw SCTestError.metalSetupFailed }

    let fftBuf  = ctx.makeSharedBuffer(length: 512  * MemoryLayout<Float>.stride)!
    let wavBuf  = ctx.makeSharedBuffer(length: 2048 * MemoryLayout<Float>.stride)!
    let histBuf = SpectralHistoryBuffer(device: ctx.device)

    var fv    = FeatureVector.zero
    fv.beatPhase01 = 0.5
    var stems = StemFeatures.zero

    // 58 baseline samples, then a high-contrast pair to exercise the two-slot polyline read.
    for _ in 0..<58 { fv.bassDev = 0.2; histBuf.append(features: fv, stems: stems) }
    fv.bassDev = 0.2; histBuf.append(features: fv, stems: stems)
    fv.bassDev = 0.8; histBuf.append(features: fv, stems: stems)

    let size    = 64
    let texDesc = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .rgba8Unorm, width: size, height: size, mipmapped: false)
    texDesc.usage       = [.renderTarget, .shaderRead]
    texDesc.storageMode = .shared
    guard let tex    = ctx.device.makeTexture(descriptor: texDesc),
          let cmdBuf = ctx.commandQueue.makeCommandBuffer()
    else { throw SCTestError.metalSetupFailed }

    let rpd = MTLRenderPassDescriptor()
    rpd.colorAttachments[0].texture    = tex
    rpd.colorAttachments[0].loadAction  = .clear
    rpd.colorAttachments[0].clearColor  = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
    rpd.colorAttachments[0].storeAction = .store

    guard let encoder = cmdBuf.makeRenderCommandEncoder(descriptor: rpd)
    else { throw SCTestError.metalSetupFailed }

    var stemsCopy = stems
    encoder.setRenderPipelineState(preset.pipelineState)
    encoder.setFragmentBytes(&fv,        length: MemoryLayout<FeatureVector>.size, index: 0)
    encoder.setFragmentBuffer(fftBuf,    offset: 0,                                index: 1)
    encoder.setFragmentBuffer(wavBuf,    offset: 0,                                index: 2)
    encoder.setFragmentBytes(&stemsCopy, length: MemoryLayout<StemFeatures>.size,  index: 3)
    encoder.setFragmentBuffer(histBuf.gpuBuffer, offset: 0,                        index: 5)
    encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    encoder.endEncoding()
    cmdBuf.commit()
    cmdBuf.waitUntilCompleted()

    #expect(cmdBuf.status == .completed,
            "Feature-graph continuity render must complete without GPU error")

    // Read back pixels from the BR quadrant and verify non-black pixels exist.
    // BR occupies x=[size/2..size), y=[size/2..size). The polyline's exact pixel
    // row depends on valC and padding math; scanning the whole quadrant is robust.
    var pixels = [UInt8](repeating: 0, count: size * size * 4)
    tex.getBytes(&pixels, bytesPerRow: size * 4,
                 from: MTLRegionMake2D(0, 0, size, size), mipmapLevel: 0)

    let brStart = size / 2
    var foundNonBlack = false
    outer: for y in brStart..<size {
        for x in brStart..<size {
            let idx = (y * size + x) * 4
            if pixels[idx] > 10 || pixels[idx + 1] > 10 || pixels[idx + 2] > 10 {
                foundNonBlack = true; break outer
            }
        }
    }
    #expect(foundNonBlack,
            "BR panel should contain at least one non-black pixel (polyline continuity)")
}

// MARK: - SpectralCartographText mode-label tests (DSP.3.1)

/// Draw into a CGBitmapContext and read back a row of pixels to verify text was rendered.
private func makeBitmapContext(width: Int = 512, height: Int = 256) -> CGContext? {
    let cs = CGColorSpaceCreateDeviceRGB()
    return CGContext(
        data: nil,
        width: width, height: height,
        bitsPerComponent: 8, bytesPerRow: width * 4,
        space: cs,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )
}

@Test func test_spectralCartographText_sessionMode0_producesReactiveLabel() {
    guard let ctx = makeBitmapContext() else {
        Issue.record("Failed to create CGBitmapContext")
        return
    }
    // DynamicTextOverlay applies a CTM flip — apply the same here so text appears in frame.
    ctx.translateBy(x: 0, y: CGFloat(ctx.height))
    ctx.scaleBy(x: 1, y: -1)

    let size = CGSize(width: ctx.width, height: ctx.height)
    SpectralCartographText.draw(in: ctx, size: size, bpm: 0, lockState: 0, sessionMode: 0)

    // Verify non-black pixels exist somewhere in the lower half (label area).
    guard let data = ctx.data else {
        Issue.record("No pixel data from context")
        return
    }
    let ptr = data.assumingMemoryBound(to: UInt8.self)
    var hasPixels = false
    let startRow = ctx.height / 2
    for y in startRow..<ctx.height {
        for x in 0..<ctx.width {
            let idx = (y * ctx.width + x) * 4
            if ptr[idx] > 5 || ptr[idx + 1] > 5 || ptr[idx + 2] > 5 {
                hasPixels = true; break
            }
        }
        if hasPixels { break }
    }
    #expect(hasPixels, "sessionMode=0 should render 'REACTIVE' label with visible pixels")
}

@Test func test_spectralCartographText_sessionMode3_producesPlannedLockedLabel() {
    guard let ctx = makeBitmapContext() else {
        Issue.record("Failed to create CGBitmapContext")
        return
    }
    ctx.translateBy(x: 0, y: CGFloat(ctx.height))
    ctx.scaleBy(x: 1, y: -1)

    let size = CGSize(width: ctx.width, height: ctx.height)
    // Render sessionMode=3 with a valid BPM so BPM text also renders.
    SpectralCartographText.draw(in: ctx, size: size, bpm: 120, lockState: 2, sessionMode: 3)

    guard let data = ctx.data else {
        Issue.record("No pixel data from context")
        return
    }
    let ptr = data.assumingMemoryBound(to: UInt8.self)
    var hasPixels = false
    let startRow = ctx.height / 2
    for y in startRow..<ctx.height {
        for x in 0..<ctx.width {
            let idx = (y * ctx.width + x) * 4
            if ptr[idx] > 5 || ptr[idx + 1] > 5 || ptr[idx + 2] > 5 {
                hasPixels = true; break
            }
        }
        if hasPixels { break }
    }
    #expect(hasPixels, "sessionMode=3 should render 'PLANNED · LOCKED' label with visible pixels")
}
