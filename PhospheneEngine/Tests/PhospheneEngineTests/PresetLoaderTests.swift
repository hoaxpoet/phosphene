// PresetLoaderTests — Tests for shader discovery, compilation, cycling, and hot-reload.
// Uses temporary directories with test .metal files to avoid bundle resource dependency.

import Testing
import Foundation
import Metal
@testable import Presets
@testable import Shared

// MARK: - Shader Compilation Tests

@Test func presetLoaderCompilesValidShader() throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
        throw PresetTestError.noMetalDevice
    }

    let tempDir = try makeTempPresetDirectory(shaders: [
        ("TestShader", testFragmentShader, testSidecar(name: "TestShader"))
    ])
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let loader = PresetLoader(device: device, pixelFormat: .bgra8Unorm_srgb, watchDirectory: tempDir, loadBuiltIn: false)

    #expect(loader.presets.count == 1, "Expected 1 preset, got \(loader.presets.count)")
    #expect(loader.presets[0].descriptor.name == "TestShader")
}

@Test func presetLoaderDiscoversMultipleShaders() throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
        throw PresetTestError.noMetalDevice
    }

    let tempDir = try makeTempPresetDirectory(shaders: [
        ("Alpha", testFragmentShader, testSidecar(name: "Alpha", family: "geometric")),
        ("Beta", testFragmentShader, testSidecar(name: "Beta", family: "hypnotic")),
        ("Gamma", testFragmentShader, testSidecar(name: "Gamma", family: "particles")),
    ])
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let loader = PresetLoader(device: device, pixelFormat: .bgra8Unorm_srgb, watchDirectory: tempDir, loadBuiltIn: false)

    #expect(loader.presets.count == 3, "Expected 3 presets, got \(loader.presets.count)")
    // Presets should be sorted alphabetically by name.
    #expect(loader.presets[0].descriptor.name == "Alpha")
    #expect(loader.presets[1].descriptor.name == "Beta")
    #expect(loader.presets[2].descriptor.name == "Gamma")
}

@Test func presetLoaderRejectsInvalidShader() throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
        throw PresetTestError.noMetalDevice
    }

    let badShader = "this is not valid metal code"
    let tempDir = try makeTempPresetDirectory(shaders: [
        ("Good", testFragmentShader, testSidecar(name: "Good")),
        ("Bad", badShader, testSidecar(name: "Bad")),
    ])
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let loader = PresetLoader(device: device, pixelFormat: .bgra8Unorm_srgb, watchDirectory: tempDir, loadBuiltIn: false)

    // Only the valid shader should load.
    #expect(loader.presets.count == 1, "Invalid shader should be skipped, got \(loader.presets.count) presets")
    #expect(loader.presets[0].descriptor.name == "Good")
}

@Test func presetLoaderHandlesNoSidecar() throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
        throw PresetTestError.noMetalDevice
    }

    // Create a .metal file without a .json sidecar — should use defaults.
    let tempDir = try makeTempPresetDirectory(shaders: [
        ("NoSidecar", testFragmentShader, nil),
    ])
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let loader = PresetLoader(device: device, pixelFormat: .bgra8Unorm_srgb, watchDirectory: tempDir, loadBuiltIn: false)

    #expect(loader.presets.count == 1)
    #expect(loader.presets[0].descriptor.name == "NoSidecar", "Should derive name from filename")
    #expect(loader.presets[0].descriptor.family == nil, "Default family is nil (D-123)")
}

@Test func presetLoaderHandlesEmptyDirectory() throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
        throw PresetTestError.noMetalDevice
    }

    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("phosphene-test-empty-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let loader = PresetLoader(device: device, pixelFormat: .bgra8Unorm_srgb, watchDirectory: tempDir, loadBuiltIn: false)

    #expect(loader.presets.isEmpty, "Empty directory with no built-in should have 0 presets")
    #expect(loader.currentPreset == nil, "Should have no current preset")
}

// MARK: - Preset Cycling Tests

@Test func presetLoaderCycleForward() throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
        throw PresetTestError.noMetalDevice
    }

    let tempDir = try makeTempPresetDirectory(shaders: [
        ("A", testFragmentShader, testSidecar(name: "A")),
        ("B", testFragmentShader, testSidecar(name: "B")),
        ("C", testFragmentShader, testSidecar(name: "C")),
    ])
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let loader = PresetLoader(device: device, pixelFormat: .bgra8Unorm_srgb, watchDirectory: tempDir, loadBuiltIn: false)

    #expect(loader.currentPreset?.descriptor.name == "A")

    let b = loader.nextPreset()
    #expect(b?.descriptor.name == "B")

    let c = loader.nextPreset()
    #expect(c?.descriptor.name == "C")

    // Wrap around.
    let a = loader.nextPreset()
    #expect(a?.descriptor.name == "A", "Should wrap from last to first")
}

@Test func presetLoaderCycleBackward() throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
        throw PresetTestError.noMetalDevice
    }

    let tempDir = try makeTempPresetDirectory(shaders: [
        ("A", testFragmentShader, testSidecar(name: "A")),
        ("B", testFragmentShader, testSidecar(name: "B")),
        ("C", testFragmentShader, testSidecar(name: "C")),
    ])
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let loader = PresetLoader(device: device, pixelFormat: .bgra8Unorm_srgb, watchDirectory: tempDir, loadBuiltIn: false)

    #expect(loader.currentPreset?.descriptor.name == "A")

    // Going backward from index 0 should wrap to last.
    let c = loader.previousPreset()
    #expect(c?.descriptor.name == "C", "Should wrap from first to last")

    let b = loader.previousPreset()
    #expect(b?.descriptor.name == "B")
}

@Test func presetLoaderSelectByName() throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
        throw PresetTestError.noMetalDevice
    }

    let tempDir = try makeTempPresetDirectory(shaders: [
        ("Alpha", testFragmentShader, testSidecar(name: "Alpha")),
        ("Beta", testFragmentShader, testSidecar(name: "Beta")),
        ("Gamma", testFragmentShader, testSidecar(name: "Gamma")),
    ])
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let loader = PresetLoader(device: device, pixelFormat: .bgra8Unorm_srgb, watchDirectory: tempDir, loadBuiltIn: false)

    let idx = loader.selectPreset(named: "Beta")
    #expect(idx == 1, "Beta should be at index 1")
    #expect(loader.currentPreset?.descriptor.name == "Beta")

    let missing = loader.selectPreset(named: "DoesNotExist")
    #expect(missing == nil, "Should return nil for unknown preset")
    #expect(loader.currentPreset?.descriptor.name == "Beta", "Index should not change on failed select")
}

// MARK: - Pipeline State Validation

@Test func presetLoaderPipelineStateIsUsable() throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
        throw PresetTestError.noMetalDevice
    }

    let tempDir = try makeTempPresetDirectory(shaders: [
        ("Test", testFragmentShader, testSidecar(name: "Test")),
    ])
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let loader = PresetLoader(device: device, pixelFormat: .bgra8Unorm_srgb, watchDirectory: tempDir, loadBuiltIn: false)

    guard let preset = loader.currentPreset else {
        throw PresetTestError.noPresetLoaded
    }

    // Verify the pipeline state can be used to create a render encoder.
    // This catches mismatches between vertex/fragment function signatures and buffer layouts.
    let textureDesc = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .bgra8Unorm_srgb, width: 64, height: 64, mipmapped: false)
    textureDesc.usage = .renderTarget
    guard let texture = device.makeTexture(descriptor: textureDesc),
          let queue = device.makeCommandQueue(),
          let cmdBuf = queue.makeCommandBuffer() else {
        throw PresetTestError.metalSetupFailed
    }

    let rpd = MTLRenderPassDescriptor()
    rpd.colorAttachments[0].texture = texture
    rpd.colorAttachments[0].loadAction = .clear
    rpd.colorAttachments[0].storeAction = .store
    rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)

    guard let encoder = cmdBuf.makeRenderCommandEncoder(descriptor: rpd) else {
        throw PresetTestError.metalSetupFailed
    }

    // This is the actual test: can we set the pipeline state and draw without error?
    encoder.setRenderPipelineState(preset.pipelineState)
    encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    encoder.endEncoding()
    cmdBuf.commit()
    cmdBuf.waitUntilCompleted()

    #expect(cmdBuf.status == .completed, "Command buffer should complete successfully, got \(cmdBuf.status.rawValue)")
}

@Test func presetLoaderPipelineStateMatchesBufferLayout() throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
        throw PresetTestError.noMetalDevice
    }

    let tempDir = try makeTempPresetDirectory(shaders: [
        ("Test", testFragmentShaderWithAudioReading, testSidecar(name: "Test")),
    ])
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let loader = PresetLoader(device: device, pixelFormat: .bgra8Unorm_srgb, watchDirectory: tempDir, loadBuiltIn: false)

    guard let preset = loader.currentPreset else {
        throw PresetTestError.noPresetLoaded
    }

    // Create mock audio buffers matching the expected layout.
    guard let fftBuffer = device.makeBuffer(length: 512 * MemoryLayout<Float>.stride, options: .storageModeShared),
          let waveformBuffer = device.makeBuffer(length: 2048 * MemoryLayout<Float>.stride, options: .storageModeShared) else {
        throw PresetTestError.metalSetupFailed
    }

    // Write known test data into the buffers.
    let fftPtr = fftBuffer.contents().bindMemory(to: Float.self, capacity: 512)
    for i in 0..<512 { fftPtr[i] = Float(i) / 512.0 }

    let wavePtr = waveformBuffer.contents().bindMemory(to: Float.self, capacity: 2048)
    for i in 0..<2048 { wavePtr[i] = sinf(Float(i) * 0.01) }

    // Render a frame with the preset pipeline and audio buffers.
    let textureDesc = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .bgra8Unorm_srgb, width: 64, height: 64, mipmapped: false)
    textureDesc.usage = .renderTarget
    guard let texture = device.makeTexture(descriptor: textureDesc),
          let queue = device.makeCommandQueue(),
          let cmdBuf = queue.makeCommandBuffer() else {
        throw PresetTestError.metalSetupFailed
    }

    let rpd = MTLRenderPassDescriptor()
    rpd.colorAttachments[0].texture = texture
    rpd.colorAttachments[0].loadAction = .clear
    rpd.colorAttachments[0].storeAction = .store

    guard let encoder = cmdBuf.makeRenderCommandEncoder(descriptor: rpd) else {
        throw PresetTestError.metalSetupFailed
    }

    var features = FeatureVector(time: 1.0, deltaTime: 0.016)
    encoder.setRenderPipelineState(preset.pipelineState)
    encoder.setFragmentBytes(&features, length: MemoryLayout<FeatureVector>.size, index: 0)
    encoder.setFragmentBuffer(fftBuffer, offset: 0, index: 1)
    encoder.setFragmentBuffer(waveformBuffer, offset: 0, index: 2)
    encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    encoder.endEncoding()

    cmdBuf.commit()
    cmdBuf.waitUntilCompleted()

    #expect(cmdBuf.status == .completed,
            "Rendering with audio buffers bound should succeed, got status \(cmdBuf.status.rawValue)")
}

// MARK: - Bundle Resource Tests

@Test func presetLoaderFindsBuiltInPresets() throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
        throw PresetTestError.noMetalDevice
    }

    // Create a loader with no watchDirectory — only loads from bundle.
    let loader = PresetLoader(device: device, pixelFormat: .bgra8Unorm_srgb)

    #expect(loader.presets.count >= 3,
            "Expected at least 3 built-in presets (Waveform, Plasma, Nebula), got \(loader.presets.count)")

    let names = loader.presets.map(\.descriptor.name)
    #expect(names.contains("Waveform"), "Built-in Waveform preset not found. Available: \(names)")
    #expect(names.contains("Plasma"), "Built-in Plasma preset not found. Available: \(names)")
    #expect(names.contains("Nebula"), "Built-in Nebula preset not found. Available: \(names)")
}

@Test func presetLoaderBuiltInPresetsHaveValidPipelines() throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
        throw PresetTestError.noMetalDevice
    }

    let loader = PresetLoader(device: device, pixelFormat: .bgra8Unorm_srgb)

    for preset in loader.presets {
        // Post-process presets are compiled for .rgba16Float (HDR scene texture);
        // all others use the standard drawable format.
        let targetFormat: MTLPixelFormat = preset.descriptor.usePostProcess
            ? .rgba16Float : .bgra8Unorm_srgb

        // Verify each built-in preset can render a frame.
        let textureDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: targetFormat, width: 16, height: 16, mipmapped: false)
        textureDesc.usage = .renderTarget
        guard let texture = device.makeTexture(descriptor: textureDesc),
              let queue = device.makeCommandQueue(),
              let cmdBuf = queue.makeCommandBuffer() else {
            throw PresetTestError.metalSetupFailed
        }

        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = texture
        rpd.colorAttachments[0].loadAction = .clear
        rpd.colorAttachments[0].storeAction = .store

        guard let encoder = cmdBuf.makeRenderCommandEncoder(descriptor: rpd) else {
            throw PresetTestError.metalSetupFailed
        }

        var features = FeatureVector(time: 0, deltaTime: 0.016)
        guard let fftBuf = device.makeBuffer(length: 512 * 4, options: .storageModeShared),
              let wavBuf = device.makeBuffer(length: 2048 * 4, options: .storageModeShared) else {
            throw PresetTestError.metalSetupFailed
        }

        encoder.setRenderPipelineState(preset.pipelineState)
        encoder.setFragmentBytes(&features, length: MemoryLayout<FeatureVector>.size, index: 0)
        encoder.setFragmentBuffer(fftBuf, offset: 0, index: 1)
        encoder.setFragmentBuffer(wavBuf, offset: 0, index: 2)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        cmdBuf.commit()
        cmdBuf.waitUntilCompleted()

        #expect(cmdBuf.status == .completed,
                "Preset '\(preset.descriptor.name)' failed to render: status \(cmdBuf.status.rawValue)")
    }
}

// MARK: - Helpers

enum PresetTestError: Error {
    case noMetalDevice
    case noPresetLoaded
    case metalSetupFailed
}

/// Minimal fragment shader that compiles successfully with the PresetLoader preamble.
private let testFragmentShader = """
fragment float4 preset_fragment(VertexOut in [[stage_in]],
                                constant FeatureVector& features [[buffer(0)]],
                                constant float* fftMagnitudes [[buffer(1)]],
                                constant float* waveformData [[buffer(2)]]) {
    float2 uv = in.uv;
    float t = features.time;
    float3 color = hsv2rgb(float3(uv.x + t * 0.1, 0.8, 0.6));
    return float4(color, 1.0);
}
"""

/// Fragment shader that reads from all three buffer bindings to verify layout.
private let testFragmentShaderWithAudioReading = """
fragment float4 preset_fragment(VertexOut in [[stage_in]],
                                constant FeatureVector& features [[buffer(0)]],
                                constant float* fftMagnitudes [[buffer(1)]],
                                constant float* waveformData [[buffer(2)]]) {
    float2 uv = in.uv;
    // Read from FeatureVector.
    float t = features.time;
    float bass = features.bass;
    // Read from FFT buffer.
    int bin = int(uv.x * 511.0);
    float mag = fftMagnitudes[bin];
    // Read from waveform buffer.
    int sampleIdx = int(uv.x * 2047.0);
    float sample = waveformData[sampleIdx];
    // Combine to produce a visible result.
    float3 color = float3(mag, abs(sample), bass + t * 0.001);
    return float4(min(color, float3(1.0)), 1.0);
}
"""

private func testSidecar(name: String, family: String = "waveform") -> String {
    """
    {"name": "\(name)", "family": "\(family)", "duration": 30, "decay": 0.95}
    """
}

/// Creates a temporary directory with .metal and optional .json files for testing.
private func makeTempPresetDirectory(shaders: [(name: String, metalSource: String, jsonSidecar: String?)]) throws -> URL {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("phosphene-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    for shader in shaders {
        let metalURL = tempDir.appendingPathComponent("\(shader.name).metal")
        try shader.metalSource.write(to: metalURL, atomically: true, encoding: .utf8)

        if let json = shader.jsonSidecar {
            let jsonURL = tempDir.appendingPathComponent("\(shader.name).json")
            try json.write(to: jsonURL, atomically: true, encoding: .utf8)
        }
    }

    return tempDir
}
