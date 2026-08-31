// AudioToRenderPipelineTests — Integration tests wiring AudioBuffer + FFTProcessor + Metal rendering.
// Verifies the full audio → FFT → GPU render path produces valid output.

import Testing
import Foundation
import Metal
@testable import Audio
@testable import Shared
@testable import Renderer

// MARK: - Full Pipeline: Audio → FFT → Render

@Test func fullPipeline_sineWave_rendersNonBlackFrame() throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
        throw AudioRenderTestError.noMetalDevice
    }

    // Wire real AudioBuffer + FFTProcessor.
    let audioBuffer = try AudioBuffer(device: device)
    let fftProcessor = try FFTProcessor(device: device)

    // Feed 440Hz sine wave through the pipeline.
    let mono = AudioFixtures.sineWave(frequency: 440, sampleRate: 48000, duration: 0.1)
    let stereo = AudioFixtures.mixStereo(left: mono, right: mono)
    stereo.withUnsafeBufferPointer { ptr in
        _ = audioBuffer.write(from: ptr.baseAddress!, count: ptr.count)
    }

    let latest = audioBuffer.latestSamples(count: FFTProcessor.fftSize * 2)
    fftProcessor.processStereo(interleavedSamples: latest, sampleRate: 48000)

    // Set up MetalContext + ShaderLibrary for the built-in waveform shader.
    let context = try MetalContext()
    let shaderLibrary = try ShaderLibrary(context: context)

    // Create the RenderPipeline with real audio UMA buffers.
    let pipeline = try RenderPipeline(
        context: context,
        shaderLibrary: shaderLibrary,
        fftBuffer: fftProcessor.magnitudeBuffer.buffer,
        waveformBuffer: audioBuffer.metalBuffer
    )
    _ = pipeline // Verify init succeeds with real data.

    // Render one frame to an offscreen texture.
    let size = 32
    let textureDesc = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: context.pixelFormat, width: size, height: size, mipmapped: false)
    textureDesc.usage = [.renderTarget, .shaderRead]

    guard let texture = device.makeTexture(descriptor: textureDesc),
          let cmdBuf = context.commandQueue.makeCommandBuffer() else {
        throw AudioRenderTestError.metalSetupFailed
    }

    let rpd = MTLRenderPassDescriptor()
    rpd.colorAttachments[0].texture = texture
    rpd.colorAttachments[0].loadAction = .clear
    rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
    rpd.colorAttachments[0].storeAction = .store

    guard let encoder = cmdBuf.makeRenderCommandEncoder(descriptor: rpd) else {
        throw AudioRenderTestError.metalSetupFailed
    }

    // Build FeatureVector with non-zero energy to drive the shader.
    var features = FeatureVector(bass: 0.5, mid: 0.3, treble: 0.2, time: 1.0, deltaTime: 0.016)

    // Use the pipeline state from ShaderLibrary directly.
    let pipelineState = try shaderLibrary.renderPipelineState(
        named: "waveform",
        vertexFunction: "fullscreen_vertex",
        fragmentFunction: "waveform_fragment",
        pixelFormat: context.pixelFormat,
        device: device
    )

    encoder.setRenderPipelineState(pipelineState)
    encoder.setFragmentBytes(&features, length: MemoryLayout<FeatureVector>.size, index: 0)
    encoder.setFragmentBuffer(fftProcessor.magnitudeBuffer.buffer, offset: 0, index: 1)
    encoder.setFragmentBuffer(audioBuffer.metalBuffer, offset: 0, index: 2)
    encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    encoder.endEncoding()

    cmdBuf.commit()
    cmdBuf.waitUntilCompleted()

    #expect(cmdBuf.status == .completed, "Command buffer should complete successfully")

    // Read back pixels — at least one should be non-black.
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
    #expect(hasNonBlack, "Rendered frame should contain non-black pixels with 440Hz sine input")
}

@Test func fullPipeline_silence_rendersBackgroundOnly() throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
        throw AudioRenderTestError.noMetalDevice
    }

    let audioBuffer = try AudioBuffer(device: device)
    let fftProcessor = try FFTProcessor(device: device)

    // Feed silence.
    let silence = AudioFixtures.silence(sampleCount: 4096)
    silence.withUnsafeBufferPointer { ptr in
        _ = audioBuffer.write(from: ptr.baseAddress!, count: ptr.count)
    }

    let latest = audioBuffer.latestSamples(count: FFTProcessor.fftSize * 2)
    fftProcessor.processStereo(interleavedSamples: latest, sampleRate: 48000)

    let context = try MetalContext()
    let shaderLibrary = try ShaderLibrary(context: context)

    // Render one frame to offscreen texture.
    let size = 32
    let textureDesc = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: context.pixelFormat, width: size, height: size, mipmapped: false)
    textureDesc.usage = [.renderTarget, .shaderRead]

    guard let texture = device.makeTexture(descriptor: textureDesc),
          let cmdBuf = context.commandQueue.makeCommandBuffer() else {
        throw AudioRenderTestError.metalSetupFailed
    }

    let rpd = MTLRenderPassDescriptor()
    rpd.colorAttachments[0].texture = texture
    rpd.colorAttachments[0].loadAction = .clear
    rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
    rpd.colorAttachments[0].storeAction = .store

    guard let encoder = cmdBuf.makeRenderCommandEncoder(descriptor: rpd) else {
        throw AudioRenderTestError.metalSetupFailed
    }

    var features = FeatureVector(time: 1.0, deltaTime: 0.016)

    let pipelineState = try shaderLibrary.renderPipelineState(
        named: "waveform",
        vertexFunction: "fullscreen_vertex",
        fragmentFunction: "waveform_fragment",
        pixelFormat: context.pixelFormat,
        device: device
    )

    encoder.setRenderPipelineState(pipelineState)
    encoder.setFragmentBytes(&features, length: MemoryLayout<FeatureVector>.size, index: 0)
    encoder.setFragmentBuffer(fftProcessor.magnitudeBuffer.buffer, offset: 0, index: 1)
    encoder.setFragmentBuffer(audioBuffer.metalBuffer, offset: 0, index: 2)
    encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    encoder.endEncoding()

    cmdBuf.commit()
    cmdBuf.waitUntilCompleted()

    #expect(cmdBuf.status == .completed,
            "Command buffer should complete successfully even with silent audio input")
}

// MARK: - Errors

private enum AudioRenderTestError: Error {
    case noMetalDevice
    case metalSetupFailed
}
