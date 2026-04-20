// RenderPipelineTests — Unit tests for the Metal render pipeline.

import Testing
import Metal
import MetalKit
@testable import Renderer
@testable import Shared

@Test func test_init_withValidDevice_createsPipelineState() throws {
    let ctx = try MetalContext()
    let lib = try ShaderLibrary(context: ctx)
    let fftBuf = ctx.makeSharedBuffer(length: 512 * MemoryLayout<Float>.stride)!
    let wavBuf = ctx.makeSharedBuffer(length: 2048 * MemoryLayout<Float>.stride)!

    let pipeline = try RenderPipeline(
        context: ctx, shaderLibrary: lib,
        fftBuffer: fftBuf, waveformBuffer: wavBuf
    )

    // If we get here without throwing, the pipeline state was created successfully.
    #expect(pipeline is RenderPipeline)
}

@Test func test_bindFFTBuffer_bufferIsAccessible() throws {
    let ctx = try MetalContext()
    let fftBuf = ctx.makeSharedBuffer(length: 512 * MemoryLayout<Float>.stride)!

    // Write known data to the FFT buffer.
    let ptr = fftBuf.contents().bindMemory(to: Float.self, capacity: 512)
    for i in 0..<512 {
        ptr[i] = Float(i) / 512.0
    }

    // Verify the data is accessible (same pointer — UMA zero-copy).
    #expect(ptr[0] == 0.0)
    #expect(abs(ptr[255] - 255.0 / 512.0) < 0.001)
    #expect(fftBuf.length == 512 * MemoryLayout<Float>.stride)
}

@Test func test_bindWaveformBuffer_bufferIsAccessible() throws {
    let ctx = try MetalContext()
    let wavBuf = ctx.makeSharedBuffer(length: 2048 * MemoryLayout<Float>.stride)!

    // Write known waveform data.
    let ptr = wavBuf.contents().bindMemory(to: Float.self, capacity: 2048)
    for i in 0..<2048 {
        ptr[i] = sinf(Float(i) * 0.01)
    }

    // Verify accessibility.
    #expect(wavBuf.length == 2048 * MemoryLayout<Float>.stride)
    #expect(ptr[0] == sinf(0))
    #expect(abs(ptr[100] - sinf(1.0)) < 0.001)
}

@Test func test_draw_withStubFFT_producesNonBlackOutput() throws {
    let ctx = try MetalContext()
    let lib = try ShaderLibrary(context: ctx)
    let device = ctx.device

    // Create FFT buffer with non-zero magnitudes.
    let fftBuf = ctx.makeSharedBuffer(length: 512 * MemoryLayout<Float>.stride)!
    let fftPtr = fftBuf.contents().bindMemory(to: Float.self, capacity: 512)
    for i in 0..<512 {
        fftPtr[i] = 0.3  // Uniform energy across all bins.
    }

    // Create waveform buffer with a sine wave.
    let wavBuf = ctx.makeSharedBuffer(length: 2048 * MemoryLayout<Float>.stride)!
    let wavPtr = wavBuf.contents().bindMemory(to: Float.self, capacity: 2048)
    for i in 0..<2048 {
        wavPtr[i] = sinf(Float(i) * 0.05) * 0.5
    }

    // Render to an offscreen texture.
    let size = 32
    let texDesc = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: ctx.pixelFormat, width: size, height: size, mipmapped: false)
    texDesc.usage = [.renderTarget, .shaderRead]
    guard let texture = device.makeTexture(descriptor: texDesc),
          let cmdBuf = ctx.commandQueue.makeCommandBuffer() else {
        throw RenderPipelineTestError.metalSetupFailed
    }

    let rpd = MTLRenderPassDescriptor()
    rpd.colorAttachments[0].texture = texture
    rpd.colorAttachments[0].loadAction = .clear
    rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
    rpd.colorAttachments[0].storeAction = .store

    guard let encoder = cmdBuf.makeRenderCommandEncoder(descriptor: rpd) else {
        throw RenderPipelineTestError.metalSetupFailed
    }

    let pipelineState = try lib.renderPipelineState(
        named: "waveform",
        vertexFunction: "fullscreen_vertex",
        fragmentFunction: "waveform_fragment",
        pixelFormat: ctx.pixelFormat,
        device: device
    )

    var features = FeatureVector(bass: 0.5, mid: 0.3, treble: 0.2, time: 1.0, deltaTime: 0.016)

    encoder.setRenderPipelineState(pipelineState)
    encoder.setFragmentBytes(&features, length: MemoryLayout<FeatureVector>.size, index: 0)
    encoder.setFragmentBuffer(fftBuf, offset: 0, index: 1)
    encoder.setFragmentBuffer(wavBuf, offset: 0, index: 2)
    encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    encoder.endEncoding()

    cmdBuf.commit()
    cmdBuf.waitUntilCompleted()

    #expect(cmdBuf.status == .completed, "Render command buffer should complete without error")
    #expect(cmdBuf.error == nil, "Render should produce no error")

    // Read back pixels and verify not all black.
    let bytesPerRow = size * 4
    var pixelData = [UInt8](repeating: 0, count: size * size * 4)
    texture.getBytes(&pixelData, bytesPerRow: bytesPerRow,
                     from: MTLRegionMake2D(0, 0, size, size), mipmapLevel: 0)

    var hasNonBlack = false
    for i in stride(from: 0, to: pixelData.count, by: 4) {
        if pixelData[i] > 5 || pixelData[i + 1] > 5 || pixelData[i + 2] > 5 {
            hasNonBlack = true
            break
        }
    }
    #expect(hasNonBlack, "Shader output should contain non-black pixels with non-zero FFT data")
}

@Test func test_renderPipeline_spectralHistoryAllocated() throws {
    let ctx = try MetalContext()
    let lib = try ShaderLibrary(context: ctx)
    let fftBuf = ctx.makeSharedBuffer(length: 512 * MemoryLayout<Float>.stride)!
    let wavBuf = ctx.makeSharedBuffer(length: 2048 * MemoryLayout<Float>.stride)!

    let pipeline = try RenderPipeline(
        context: ctx, shaderLibrary: lib,
        fftBuffer: fftBuf, waveformBuffer: wavBuf
    )

    #expect(pipeline.spectralHistory.gpuBuffer.length == SpectralHistoryBuffer.bufferSizeBytes,
            "spectralHistory must be allocated at init with the correct buffer size")
}

enum RenderPipelineTestError: Error {
    case metalSetupFailed
}
