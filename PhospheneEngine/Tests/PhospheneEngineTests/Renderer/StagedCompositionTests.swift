// StagedCompositionTests — Always-on regression for the V.ENGINE.1
// staged-composition scaffold (per-preset multipass DAG with named offscreen
// textures sampled across passes).
//
// These tests avoid `MTKView`. They drive `PresetLoader` + the staged-stage
// pipelines directly so the scaffold can be exercised in headless `swift test`
// runs without a Metal-capable display.

import Testing
import Metal
import simd
@testable import Renderer
@testable import Presets
@testable import Shared

@Suite("StagedComposition")
struct StagedCompositionTests {

    // MARK: - Discovery

    @Test("StagedSandbox loads with two compiled stages")
    func stagedSandboxLoadsWithTwoStages() throws {
        let ctx = try MetalContext()
        let loader = PresetLoader(device: ctx.device, pixelFormat: ctx.pixelFormat)
        guard let sandbox = loader.presets.first(where: {
            $0.descriptor.name == "Staged Sandbox"
        }) else {
            Issue.record("StagedSandbox preset not found in bundle")
            return
        }

        #expect(sandbox.descriptor.passes.contains(.staged))
        #expect(sandbox.stages.count == 2)
        #expect(sandbox.stages.map(\.name) == ["world", "composite"])
        #expect(sandbox.stages[0].samples.isEmpty)
        #expect(sandbox.stages[1].samples == ["world"])
        #expect(sandbox.stages[0].writesToDrawable == false)
        #expect(sandbox.stages[1].writesToDrawable == true)
    }

    // MARK: - Render-through

    /// Walks the staged-sandbox stages headlessly: stage 0 renders into an
    /// offscreen `.rgba16Float` texture, stage 1 samples it (bound at
    /// `[[texture(13)]]`) and renders into an offscreen drawable-format
    /// texture. Asserts the WORLD-only output is bluish (sky) and the
    /// COMPOSITE output is bluish-with-bright-pixels (web overlay).
    @Test("Stage 1 samples stage 0's offscreen texture (pass-separated harness path)")
    func stagedSandboxRendersAndSamplesEarlierStage() throws {
        let ctx = try MetalContext()
        let loader = PresetLoader(device: ctx.device, pixelFormat: ctx.pixelFormat)
        guard let sandbox = loader.presets.first(where: {
            $0.descriptor.name == "Staged Sandbox"
        }) else {
            Issue.record("StagedSandbox preset not found in bundle")
            return
        }

        let width = 256
        let height = 144

        // Allocate a per-stage offscreen texture for stage 0 (.rgba16Float)
        // and a final-output texture matching the preset's drawable format.
        let worldTex = try makeRenderTexture(
            device: ctx.device,
            format: .rgba16Float,
            width: width, height: height,
            storage: .shared)
        let finalTex = try makeRenderTexture(
            device: ctx.device,
            format: ctx.pixelFormat,
            width: width, height: height,
            storage: .shared)

        // Allocate the audio-binding buffers the preamble requires.
        let floatStride = MemoryLayout<Float>.stride
        let fftBuf = try requireBuffer(ctx.makeSharedBuffer(length: 512 * floatStride))
        let waveBuf = try requireBuffer(ctx.makeSharedBuffer(length: 2048 * floatStride))
        let stemBuf = try requireBuffer(
            ctx.makeSharedBuffer(length: MemoryLayout<StemFeatures>.size))
        let histBuf = try requireBuffer(ctx.makeSharedBuffer(length: 4096 * floatStride))
        zero(stemBuf, MemoryLayout<StemFeatures>.size)
        zero(histBuf, 4096 * floatStride)

        var fv = FeatureVector(time: 1.0, deltaTime: 1.0 / 60.0)

        guard let cmd = ctx.commandQueue.makeCommandBuffer() else {
            Issue.record("Could not make command buffer")
            return
        }

        // Stage 0: WORLD → worldTex.
        let stage0 = sandbox.stages[0]
        try encodeStage(
            stage: stage0,
            target: worldTex,
            commandBuffer: cmd,
            features: &fv,
            fft: fftBuf, wave: waveBuf, stems: stemBuf, hist: histBuf,
            sampledTextures: [:]
        )

        // Stage 1: COMPOSITE samples world at [[texture(13)]] → finalTex.
        let stage1 = sandbox.stages[1]
        try encodeStage(
            stage: stage1,
            target: finalTex,
            commandBuffer: cmd,
            features: &fv,
            fft: fftBuf, wave: waveBuf, stems: stemBuf, hist: histBuf,
            sampledTextures: ["world": worldTex]
        )

        cmd.commit()
        cmd.waitUntilCompleted()
        #expect(cmd.status == .completed)

        // WORLD: read row near the top — should be cool/bluish (B > R).
        let topRow = readRow(worldTex, y: height / 8, width: width, format: .rgba16Float)
        let topAvgR = topRow.reduce(0) { $0 + $1.r } / Float(topRow.count)
        let topAvgB = topRow.reduce(0) { $0 + $1.b } / Float(topRow.count)
        let topMsg = "WORLD-only top row should be bluish (B=\(topAvgB) > R=\(topAvgR))"
        #expect(topAvgB > topAvgR + 0.05, Comment(rawValue: topMsg))

        // COMPOSITE: read a horizontal row across the hub band. Should contain
        // brighter pixels than WORLD because of the web overlay strokes.
        let hubRow = readRow(finalTex, y: Int(Float(height) * 0.42),
                             width: width, format: ctx.pixelFormat)
        let maxComposite = hubRow.reduce(0.0) { max($0, $1.luma) }
        let maxWorld = readRow(worldTex, y: Int(Float(height) * 0.42),
                                width: width, format: .rgba16Float)
            .reduce(0.0) { max($0, $1.luma) }
        let message = "COMPOSITE row should have brighter pixels than WORLD row " +
            "(composite=\(maxComposite), world=\(maxWorld))"
        #expect(maxComposite > maxWorld + 0.05, Comment(rawValue: message))
    }

    // MARK: - Helpers

    private func encodeStage(
        stage: PresetLoader.LoadedStage,
        target: MTLTexture,
        commandBuffer: MTLCommandBuffer,
        features: inout FeatureVector,
        fft: MTLBuffer, wave: MTLBuffer, stems: MTLBuffer, hist: MTLBuffer,
        sampledTextures: [String: MTLTexture]
    ) throws {
        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = target
        rpd.colorAttachments[0].loadAction = .clear
        rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        rpd.colorAttachments[0].storeAction = .store
        guard let enc = commandBuffer.makeRenderCommandEncoder(descriptor: rpd) else {
            throw StagedTestError.encoderCreationFailed
        }
        enc.setRenderPipelineState(stage.pipelineState)
        enc.setFragmentBytes(&features, length: MemoryLayout<FeatureVector>.size, index: 0)
        enc.setFragmentBuffer(fft, offset: 0, index: 1)
        enc.setFragmentBuffer(wave, offset: 0, index: 2)
        enc.setFragmentBuffer(stems, offset: 0, index: 3)
        enc.setFragmentBuffer(hist, offset: 0, index: 5)

        for (offset, name) in stage.samples.enumerated() {
            guard let tex = sampledTextures[name] else { continue }
            enc.setFragmentTexture(tex, index: kStagedSampledTextureFirstSlot + offset)
        }
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
    }

    private func makeRenderTexture(
        device: MTLDevice,
        format: MTLPixelFormat,
        width: Int, height: Int,
        storage: MTLStorageMode
    ) throws -> MTLTexture {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: format, width: width, height: height, mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = storage
        guard let tex = device.makeTexture(descriptor: desc) else {
            throw StagedTestError.textureAllocationFailed
        }
        return tex
    }

    private func requireBuffer(_ buffer: MTLBuffer?) throws -> MTLBuffer {
        guard let buffer else { throw StagedTestError.bufferAllocationFailed }
        return buffer
    }

    private func zero(_ buffer: MTLBuffer, _ length: Int) {
        _ = buffer.contents().initializeMemory(as: UInt8.self, repeating: 0, count: length)
    }

    private struct PixelSample {
        let r: Float
        let g: Float
        let b: Float
        var luma: Float { 0.299 * r + 0.587 * g + 0.114 * b }
    }

    private func readRow(
        _ texture: MTLTexture,
        y: Int,
        width: Int,
        format: MTLPixelFormat
    ) -> [PixelSample] {
        let region = MTLRegionMake2D(0, y, width, 1)
        switch format {
        case .rgba16Float:
            // 4 × Float16 per pixel = 8 bytes.
            var bytes = [UInt16](repeating: 0, count: width * 4)
            bytes.withUnsafeMutableBytes { ptr in
                texture.getBytes(ptr.baseAddress!,
                                 bytesPerRow: width * 8,
                                 from: region, mipmapLevel: 0)
            }
            return (0..<width).map { x in
                let base = x * 4
                return PixelSample(
                    r: float16ToFloat32(bytes[base + 0]),
                    g: float16ToFloat32(bytes[base + 1]),
                    b: float16ToFloat32(bytes[base + 2]))
            }
        default:
            // BGRA8 (sRGB or linear) — 4 × UInt8 per pixel = 4 bytes.
            var bytes = [UInt8](repeating: 0, count: width * 4)
            texture.getBytes(&bytes,
                             bytesPerRow: width * 4,
                             from: region, mipmapLevel: 0)
            return (0..<width).map { x in
                let base = x * 4
                let b = Float(bytes[base + 0]) / 255.0
                let g = Float(bytes[base + 1]) / 255.0
                let r = Float(bytes[base + 2]) / 255.0
                return PixelSample(r: r, g: g, b: b)
            }
        }
    }

    /// Convert IEEE-754 binary16 to binary32. Sufficient for test inspection.
    private func float16ToFloat32(_ value: UInt16) -> Float {
        let sign = UInt32(value & 0x8000) << 16
        let exp = UInt32((value >> 10) & 0x1F)
        let mant = UInt32(value & 0x3FF)
        if exp == 0 {
            if mant == 0 { return Float(bitPattern: sign) }
            // Subnormal — denormalize.
            var e: UInt32 = 0
            var m = mant
            while (m & 0x400) == 0 { m <<= 1; e += 1 }
            m &= 0x3FF
            let bits = sign | ((127 - 15 - e + 1) << 23) | (m << 13)
            return Float(bitPattern: bits)
        }
        if exp == 0x1F {
            return Float(bitPattern: sign | 0x7F800000 | (mant << 13))
        }
        let bits = sign | ((exp + (127 - 15)) << 23) | (mant << 13)
        return Float(bitPattern: bits)
    }
}

private enum StagedTestError: Error {
    case textureAllocationFailed
    case bufferAllocationFailed
    case encoderCreationFailed
}
