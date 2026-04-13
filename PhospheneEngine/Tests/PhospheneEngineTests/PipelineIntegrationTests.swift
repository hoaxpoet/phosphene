// PipelineIntegrationTests — End-to-end tests verifying the audio → FFT → GPU → shader pipeline.
// These tests synthesize audio data and verify it flows through the full pipeline
// to produce non-trivial rendering output.

import Testing
import Foundation
import Metal
@testable import Audio
@testable import Shared
@testable import Renderer
@testable import Presets

// MARK: - Audio → FFT → GPU Buffer Integration

@Test func audioToFFTToGPUPipeline() throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
        throw IntegrationTestError.noMetalDevice
    }

    let audioBuffer = try AudioBuffer(device: device)
    let fftProcessor = try FFTProcessor(device: device)

    // Synthesize a 440Hz sine wave (interleaved stereo, 48kHz).
    let sampleRate: Float = 48000
    let frequency: Float = 440
    let frameCount = 2048
    var stereoSamples = [Float](repeating: 0, count: frameCount * 2)
    for i in 0..<frameCount {
        let sample = sinf(2.0 * .pi * frequency * Float(i) / sampleRate)
        stereoSamples[i * 2] = sample       // L
        stereoSamples[i * 2 + 1] = sample   // R
    }

    // Write samples through the same path the audio callback uses.
    stereoSamples.withUnsafeBufferPointer { ptr in
        audioBuffer.write(from: ptr.baseAddress!, count: ptr.count)
    }

    #expect(audioBuffer.totalWritten > 0, "AudioBuffer should have received samples")
    #expect(audioBuffer.currentRMS > 0.1, "RMS should be non-trivial for a sine wave, got \(audioBuffer.currentRMS)")

    // Extract latest samples and run FFT — same path as the audio callback.
    let latest = audioBuffer.latestSamples(count: FFTProcessor.fftSize * 2)
    #expect(!latest.isEmpty, "Should extract samples from the ring buffer")

    let result = fftProcessor.processStereo(interleavedSamples: latest, sampleRate: sampleRate)

    #expect(result.dominantMagnitude > 0.01,
            "FFT should detect non-zero magnitude, got \(result.dominantMagnitude)")
    #expect(abs(result.dominantFrequency - frequency) < result.binResolution * 2,
            "FFT should detect ~440Hz, got \(result.dominantFrequency)Hz")

    // Verify the GPU-readable magnitude buffer has non-zero data.
    var maxMag: Float = 0
    for i in 0..<FFTProcessor.binCount {
        maxMag = max(maxMag, fftProcessor.magnitudeBuffer[i])
    }
    #expect(maxMag > 0.01, "FFT magnitude buffer (GPU-readable) should contain non-zero values, max=\(maxMag)")
}

@Test func silenceProducesZeroMagnitudes() throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
        throw IntegrationTestError.noMetalDevice
    }

    let audioBuffer = try AudioBuffer(device: device)
    let fftProcessor = try FFTProcessor(device: device)

    // Write silence.
    let silence = [Float](repeating: 0, count: 4096)
    silence.withUnsafeBufferPointer { ptr in
        audioBuffer.write(from: ptr.baseAddress!, count: ptr.count)
    }

    let latest = audioBuffer.latestSamples(count: FFTProcessor.fftSize * 2)
    fftProcessor.processStereo(interleavedSamples: latest, sampleRate: 48000)

    #expect(audioBuffer.currentRMS == 0, "RMS of silence should be 0")
    #expect(fftProcessor.latestResult.dominantMagnitude == 0,
            "FFT of silence should produce zero magnitude")
}

// MARK: - Full Render Pipeline Integration

@Test func presetRendersProdcuesNonBlackOutput() throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
        throw IntegrationTestError.noMetalDevice
    }

    // Synthesize audio data.
    let fftBuffer = try createMockFFTBuffer(device: device, frequency: 440)
    let waveformBuffer = try createMockWaveformBuffer(device: device, frequency: 440)

    // Create a preset loader and get a pipeline state.
    let tempDir = try makeTempPresetDir(shaders: [
        ("TestViz", audioReactiveShader, """
        {"name": "TestViz", "family": "waveform"}
        """)
    ])
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let loader = PresetLoader(device: device, pixelFormat: .bgra8Unorm_srgb, watchDirectory: tempDir, loadBuiltIn: false)
    guard let preset = loader.currentPreset else {
        throw IntegrationTestError.noPresetLoaded
    }

    // Render to a small texture.
    let size = 32
    let textureDesc = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .bgra8Unorm_srgb, width: size, height: size, mipmapped: false)
    textureDesc.usage = [.renderTarget, .shaderRead]
    guard let texture = device.makeTexture(descriptor: textureDesc),
          let queue = device.makeCommandQueue(),
          let cmdBuf = queue.makeCommandBuffer() else {
        throw IntegrationTestError.metalSetupFailed
    }

    let rpd = MTLRenderPassDescriptor()
    rpd.colorAttachments[0].texture = texture
    rpd.colorAttachments[0].loadAction = .clear
    rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
    rpd.colorAttachments[0].storeAction = .store

    guard let encoder = cmdBuf.makeRenderCommandEncoder(descriptor: rpd) else {
        throw IntegrationTestError.metalSetupFailed
    }

    var features = FeatureVector(bass: 0.5, mid: 0.3, treble: 0.2, time: 1.0, deltaTime: 0.016)
    encoder.setRenderPipelineState(preset.pipelineState)
    encoder.setFragmentBytes(&features, length: MemoryLayout<FeatureVector>.size, index: 0)
    encoder.setFragmentBuffer(fftBuffer, offset: 0, index: 1)
    encoder.setFragmentBuffer(waveformBuffer, offset: 0, index: 2)
    encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    encoder.endEncoding()

    cmdBuf.commit()
    cmdBuf.waitUntilCompleted()

    #expect(cmdBuf.status == .completed, "Render should succeed")

    // Read back pixels and verify they're not all black.
    let bytesPerRow = size * 4
    var pixelData = [UInt8](repeating: 0, count: size * size * 4)
    texture.getBytes(&pixelData, bytesPerRow: bytesPerRow,
                     from: MTLRegionMake2D(0, 0, size, size), mipmapLevel: 0)

    var hasNonBlack = false
    for i in stride(from: 0, to: pixelData.count, by: 4) {
        let r = pixelData[i]
        let g = pixelData[i + 1]
        let b = pixelData[i + 2]
        if r > 5 || g > 5 || b > 5 {
            hasNonBlack = true
            break
        }
    }
    #expect(hasNonBlack, "Shader output should contain non-black pixels when audio data is present")
}

@Test func renderPipelineStateSwitch() throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
        throw IntegrationTestError.noMetalDevice
    }

    let ctx = try MetalContext()
    let lib = try ShaderLibrary(context: ctx)
    guard let fftBuf = device.makeBuffer(length: 512 * 4, options: .storageModeShared),
          let wavBuf = device.makeBuffer(length: 2048 * 4, options: .storageModeShared) else {
        throw IntegrationTestError.metalSetupFailed
    }

    let pipeline = try RenderPipeline(
        context: ctx, shaderLibrary: lib,
        fftBuffer: fftBuf, waveformBuffer: wavBuf
    )

    // Create a second pipeline state from a preset.
    let tempDir = try makeTempPresetDir(shaders: [
        ("Alt", audioReactiveShader, """
        {"name": "Alt"}
        """)
    ])
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let loader = PresetLoader(device: device, pixelFormat: ctx.pixelFormat, watchDirectory: tempDir)
    guard let preset = loader.currentPreset else {
        throw IntegrationTestError.noPresetLoaded
    }

    // Switch pipeline state — should not crash.
    pipeline.setActivePipelineState(preset.pipelineState)
    // If we get here without a crash, the switch succeeded.
    #expect(true, "Pipeline state switch should succeed without crash")
}

// MARK: - FeatureVector Layout Consistency

@Test func featureVectorLayoutMatchesShaderExpectation() throws {
    // The shader preamble (in PresetLoader) defines FeatureVector as 32 floats = 128 bytes
    // (Increment 3.15: added accumulatedAudioTime + 7 padding floats).
    // This test verifies the Swift FeatureVector matches that layout exactly.
    #expect(MemoryLayout<FeatureVector>.size == 128,
            "FeatureVector must be 128 bytes (32 floats), got \(MemoryLayout<FeatureVector>.size)")

    // Verify specific field offsets by writing known values and reading as float array.
    guard let device = MTLCreateSystemDefaultDevice() else {
        throw IntegrationTestError.noMetalDevice
    }
    guard let buffer = device.makeBuffer(length: 128, options: .storageModeShared) else {
        throw IntegrationTestError.metalSetupFailed
    }

    var features = FeatureVector(
        bass: 0.8, mid: 0.5, treble: 0.3,
        time: 42.0, deltaTime: 0.016
    )

    memcpy(buffer.contents(), &features, 128)
    let floats = buffer.contents().bindMemory(to: Float.self, capacity: 32)

    #expect(floats[0] == 0.8, "bass should be at offset 0")
    #expect(floats[1] == 0.5, "mid should be at offset 1")
    #expect(floats[2] == 0.3, "treble should be at offset 2")
    #expect(floats[20] == 42.0, "time should be at offset 20")
    #expect(floats[21] == 0.016, "deltaTime should be at offset 21")
}

// MARK: - Helpers

enum IntegrationTestError: Error {
    case noMetalDevice
    case noPresetLoaded
    case metalSetupFailed
}

/// Creates a UMA buffer with mock FFT magnitude data resembling a sine wave at the given frequency.
private func createMockFFTBuffer(device: MTLDevice, frequency: Float, sampleRate: Float = 48000) throws -> MTLBuffer {
    guard let buffer = device.makeBuffer(length: 512 * MemoryLayout<Float>.stride, options: .storageModeShared) else {
        throw IntegrationTestError.metalSetupFailed
    }

    let ptr = buffer.contents().bindMemory(to: Float.self, capacity: 512)
    let binResolution = sampleRate / 1024.0
    let targetBin = Int(frequency / binResolution)

    for i in 0..<512 {
        // Gaussian centered on the target bin.
        let distance = Float(abs(i - targetBin))
        ptr[i] = 0.5 * exp(-distance * distance / 8.0)
    }

    return buffer
}

/// Creates a UMA buffer with mock interleaved stereo waveform data.
private func createMockWaveformBuffer(device: MTLDevice, frequency: Float, sampleRate: Float = 48000) throws -> MTLBuffer {
    guard let buffer = device.makeBuffer(length: 2048 * MemoryLayout<Float>.stride, options: .storageModeShared) else {
        throw IntegrationTestError.metalSetupFailed
    }

    let ptr = buffer.contents().bindMemory(to: Float.self, capacity: 2048)
    for i in 0..<1024 {
        let sample = sinf(2.0 * .pi * frequency * Float(i) / sampleRate) * 0.5
        ptr[i * 2] = sample       // L
        ptr[i * 2 + 1] = sample   // R
    }

    return buffer
}

/// Audio-reactive test shader that produces visible output proportional to FFT data.
private let audioReactiveShader = """
fragment float4 preset_fragment(VertexOut in [[stage_in]],
                                constant FeatureVector& features [[buffer(0)]],
                                constant float* fftMagnitudes [[buffer(1)]],
                                constant float* waveformData [[buffer(2)]]) {
    float2 uv = in.uv;

    // Sum FFT energy — should produce non-zero value with test data.
    float energy = 0.0;
    for (int i = 0; i < 512; i++) {
        energy += fftMagnitudes[i];
    }
    energy = saturate(energy / 512.0 * 8.0);

    // Read waveform sample.
    int idx = int(uv.x * 2047.0);
    float sample = abs(waveformData[idx]);

    // Combine into a visible color.
    float3 color = hsv2rgb(float3(uv.x + features.time * 0.1, 0.8, energy + sample * 0.3 + 0.1));
    return float4(min(color, float3(1.0)), 1.0);
}
"""

private func makeTempPresetDir(shaders: [(name: String, metal: String, json: String)]) throws -> URL {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("phosphene-integration-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    for shader in shaders {
        try shader.metal.write(to: tempDir.appendingPathComponent("\(shader.name).metal"),
                               atomically: true, encoding: .utf8)
        try shader.json.write(to: tempDir.appendingPathComponent("\(shader.name).json"),
                              atomically: true, encoding: .utf8)
    }

    return tempDir
}
