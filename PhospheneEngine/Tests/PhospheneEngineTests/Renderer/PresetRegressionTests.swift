// PresetRegressionTests — dHash visual regression gate for all production presets.
//
// Renders each preset at three FeatureVector fixtures (steady, beat-heavy, quiet),
// computes a 64-bit dHash of the 64×64 BGRA output, and compares against stored
// golden values with Hamming distance ≤ 8 (~87.5% match). Any intentional shader
// change that alters visual output must regenerate goldens; accidental changes fail.
//
// Skip rules (non-negotiable):
//   - meshShader presets: MTLMeshRenderPipeline cannot be invoked via drawPrimitives.
//   - Preset with no golden entry: skips silently (new preset or update in progress).
//
// To regenerate all goldens:
//   UPDATE_GOLDEN_SNAPSHOTS=1 swift test --package-path PhospheneEngine \
//     --filter "Print golden hashes"
// Paste the printed lines into goldenPresetHashes below.
//
// See D-039 in docs/DECISIONS.md.

import Testing
import Metal
@testable import Renderer
@testable import Presets
@testable import Shared

// MARK: - Golden Hash Table

private typealias PresetHashes = (steady: UInt64, beatHeavy: UInt64, quiet: UInt64)

/// Inline golden dHash values for each preset × 3 fixtures.
/// Update when a shader edit intentionally changes visual output — never silently.
private let goldenPresetHashes: [String: PresetHashes] = [
    "Ferrofluid Ocean": (steady: 0x56AB1C4A28B32727, beatHeavy: 0x5CB393AAAFA84840, quiet: 0xA64C51A62FD35356),
    "Glass Brutalist": (steady: 0x3369549494544D33, beatHeavy: 0x3369549494544D33, quiet: 0x3369549494544D33),
    "Gossamer": (steady: 0x14572B0F0F2A5714, beatHeavy: 0x14572B0F0F2A5714, quiet: 0x14572B0F0F2A5714),
    "Kinetic Sculpture": (steady: 0x592B6395585B1A4A, beatHeavy: 0x5B2B63B5505B124A, quiet: 0x5B2B6295585A1A4A),
    "Membrane": (steady: 0x33E3A919C9627939, beatHeavy: 0x12A3A998C9646139, quiet: 0x47E3C919CD627959),
    "Murmuration": (steady: 0x07449B6727773FF8, beatHeavy: 0x0B449A4727373FF8, quiet: 0x0744936727773FF8),
    "Nebula": (steady: 0x0000080C0C080000, beatHeavy: 0x0000080C0C080000, quiet: 0x0000080C0C080000),
    "Plasma": (steady: 0x030F170A072F1B0F, beatHeavy: 0x4193254F0E8E87C7, quiet: 0x0F1F0F0F0F07070F),
    "Spectral Cartograph": (steady: 0x0000000000000000, beatHeavy: 0x00000000000060E0, quiet: 0x0000000000000000),
    "Volumetric Lithograph": (steady: 0x8C63D435F2ADAB00, beatHeavy: 0x8C63D435F2ADAB00, quiet: 0x8C63D435F2ADAB00),
    "Waveform": (steady: 0x000F0F0000000000, beatHeavy: 0x000F0F0000000000, quiet: 0x000F0F0000000000),
]

private let hammingThreshold = 8  // ≤ 8 of 64 bits may differ

// MARK: - Suite

@Suite("Preset Regression Tests")
struct PresetRegressionTests {

    // MARK: - Fixtures (identical definitions to PresetAcceptanceTests)

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
        fv.midRel = -0.70
        fv.trebRel = -0.70
        return fv
    }

    // MARK: - Regression Tests

    @Test("Visual regression: steady energy", arguments: _acceptanceFixture.presets)
    func test_steadyHash(_ preset: PresetLoader.LoadedPreset) throws {
        guard !preset.descriptor.passes.contains(.meshShader) else { return }
        guard let golden = goldenPresetHashes[preset.descriptor.name] else { return }
        let ctx = try MetalContext()
        var fixture = steadyFixture
        let pixels = try renderFrame(preset: preset, features: &fixture, context: ctx)
        let hash = dHash(pixels)
        let distance = hammingDistance(hash, golden.steady)
        #expect(
            distance <= hammingThreshold,
            """
            Preset '\(preset.descriptor.name)' steady hash drifted: \
            distance=\(distance) threshold=\(hammingThreshold) \
            new=0x\(String(hash, radix: 16, uppercase: true)) \
            golden=0x\(String(golden.steady, radix: 16, uppercase: true))
            """
        )
    }

    @Test("Visual regression: beat-heavy energy", arguments: _acceptanceFixture.presets)
    func test_beatHeavyHash(_ preset: PresetLoader.LoadedPreset) throws {
        guard !preset.descriptor.passes.contains(.meshShader) else { return }
        guard let golden = goldenPresetHashes[preset.descriptor.name] else { return }
        let ctx = try MetalContext()
        var fixture = beatHeavyFixture
        let pixels = try renderFrame(preset: preset, features: &fixture, context: ctx)
        let hash = dHash(pixels)
        let distance = hammingDistance(hash, golden.beatHeavy)
        #expect(
            distance <= hammingThreshold,
            """
            Preset '\(preset.descriptor.name)' beat-heavy hash drifted: \
            distance=\(distance) threshold=\(hammingThreshold) \
            new=0x\(String(hash, radix: 16, uppercase: true)) \
            golden=0x\(String(golden.beatHeavy, radix: 16, uppercase: true))
            """
        )
    }

    @Test("Visual regression: quiet passage", arguments: _acceptanceFixture.presets)
    func test_quietHash(_ preset: PresetLoader.LoadedPreset) throws {
        guard !preset.descriptor.passes.contains(.meshShader) else { return }
        guard let golden = goldenPresetHashes[preset.descriptor.name] else { return }
        let ctx = try MetalContext()
        var fixture = quietFixture
        let pixels = try renderFrame(preset: preset, features: &fixture, context: ctx)
        let hash = dHash(pixels)
        let distance = hammingDistance(hash, golden.quiet)
        #expect(
            distance <= hammingThreshold,
            """
            Preset '\(preset.descriptor.name)' quiet hash drifted: \
            distance=\(distance) threshold=\(hammingThreshold) \
            new=0x\(String(hash, radix: 16, uppercase: true)) \
            golden=0x\(String(golden.quiet, radix: 16, uppercase: true))
            """
        )
    }

    @Test("Print golden hashes (UPDATE_GOLDEN_SNAPSHOTS only)")
    func test_printGoldenHashes() throws {
        guard ProcessInfo.processInfo.environment["UPDATE_GOLDEN_SNAPSHOTS"] != nil else { return }
        let ctx = try MetalContext()
        print("\n// Paste into goldenPresetHashes in PresetRegressionTests.swift:")
        for preset in _acceptanceFixture.presets {
            guard !preset.descriptor.passes.contains(.meshShader) else { continue }
            var steady = steadyFixture
            var beatHeavy = beatHeavyFixture
            var quiet = quietFixture
            let sp = try renderFrame(preset: preset, features: &steady, context: ctx)
            let bp = try renderFrame(preset: preset, features: &beatHeavy, context: ctx)
            let qp = try renderFrame(preset: preset, features: &quiet, context: ctx)
            let sh = dHash(sp)
            let bh = dHash(bp)
            let qh = dHash(qp)
            print("""
            "\(preset.descriptor.name)": \
            (steady: 0x\(hexString(sh)), beatHeavy: 0x\(hexString(bh)), quiet: 0x\(hexString(qh))),
            """)
        }
    }

    // MARK: - Rendering (duplicated from PresetAcceptanceTests — no shared helpers across @Suite structs)

    private let renderSize = 64

    private func renderFrame(
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
            throw RegressionTestError.textureAllocationFailed
        }
        let buffers = try makeRenderBuffers(context: context, preset: preset)
        guard let cmdBuf = context.commandQueue.makeCommandBuffer() else {
            throw RegressionTestError.commandBufferFailed
        }
        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = texture
        rpd.colorAttachments[0].loadAction = .clear
        rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        rpd.colorAttachments[0].storeAction = .store
        guard let encoder = cmdBuf.makeRenderCommandEncoder(descriptor: rpd) else {
            throw RegressionTestError.encoderCreationFailed
        }
        encoder.setRenderPipelineState(preset.pipelineState)
        encoder.setFragmentBytes(&features, length: MemoryLayout<FeatureVector>.size, index: 0)
        encoder.setFragmentBuffer(buffers.fft, offset: 0, index: 1)
        encoder.setFragmentBuffer(buffers.wav, offset: 0, index: 2)
        encoder.setFragmentBuffer(buffers.stem, offset: 0, index: 3)
        if let sceneBuf = buffers.scene { encoder.setFragmentBuffer(sceneBuf, offset: 0, index: 4) }
        encoder.setFragmentBuffer(buffers.hist, offset: 0, index: 5)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        cmdBuf.commit()
        cmdBuf.waitUntilCompleted()
        guard cmdBuf.status == .completed else { throw RegressionTestError.renderFailed }
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        texture.getBytes(&pixels, bytesPerRow: size * 4,
                         from: MTLRegionMake2D(0, 0, size, size), mipmapLevel: 0)
        return pixels
    }

    private struct RenderBuffers {
        let fft: MTLBuffer
        let wav: MTLBuffer
        let stem: MTLBuffer
        let hist: MTLBuffer
        let scene: MTLBuffer?
    }

    private func makeRenderBuffers(context: MetalContext, preset: PresetLoader.LoadedPreset) throws -> RenderBuffers {
        let floatStride = MemoryLayout<Float>.stride
        guard
            let fft = context.makeSharedBuffer(length: 512 * floatStride),
            let wav = context.makeSharedBuffer(length: 2048 * floatStride),
            let stem = context.makeSharedBuffer(length: MemoryLayout<StemFeatures>.size),
            let hist = context.makeSharedBuffer(length: 4096 * floatStride)
        else { throw RegressionTestError.bufferAllocationFailed }

        _ = fft.contents().initializeMemory(as: UInt8.self, repeating: 0, count: 512 * floatStride)
        _ = stem.contents().initializeMemory(as: UInt8.self, repeating: 0, count: MemoryLayout<StemFeatures>.size)
        _ = hist.contents().initializeMemory(as: UInt8.self, repeating: 0, count: 4096 * floatStride)

        var scene: MTLBuffer?
        if preset.descriptor.passes.contains(.rayMarch),
           let buf = context.makeSharedBuffer(length: MemoryLayout<SceneUniforms>.size) {
            var su = preset.descriptor.makeSceneUniforms()
            buf.contents().copyMemory(from: &su, byteCount: MemoryLayout<SceneUniforms>.size)
            scene = buf
        }
        return RenderBuffers(fft: fft, wav: wav, stem: stem, hist: hist, scene: scene)
    }

    // MARK: - dHash

    /// Computes a 64-bit dHash: downsample to a 9×8 luma grid, compare adjacent horizontal cells.
    private func dHash(_ pixels: [UInt8], width: Int = 64, height: Int = 64) -> UInt64 {
        let grid = computeLumaGrid(pixels: pixels, width: width, height: height, cols: 9, rows: 8)
        var hash: UInt64 = 0
        for row in 0..<8 {
            for col in 0..<8 {
                if grid[row * 9 + col + 1] > grid[row * 9 + col] {
                    hash |= UInt64(1) << UInt64(row * 8 + col)
                }
            }
        }
        return hash
    }

    /// Downsamples pixels to a cols×rows luma grid by averaging cells.
    /// BGRA byte order: luma = 0.114·B + 0.587·G + 0.299·R.
    private func computeLumaGrid(
        pixels: [UInt8], width: Int, height: Int, cols: Int, rows: Int
    ) -> [Float] {
        var grid = [Float](repeating: 0, count: cols * rows)
        for row in 0..<rows {
            let yStart = row * height / rows
            let yEnd = (row + 1) * height / rows
            for col in 0..<cols {
                let xStart = col * width / cols
                let xEnd = (col + 1) * width / cols
                var sum: Float = 0
                var count = 0
                for y in yStart..<yEnd {
                    for x in xStart..<xEnd {
                        let idx = (y * width + x) * 4
                        sum += 0.114 * Float(pixels[idx]) + 0.587 * Float(pixels[idx + 1]) + 0.299 * Float(pixels[idx + 2])
                        count += 1
                    }
                }
                grid[row * cols + col] = count > 0 ? sum / Float(count) : 0
            }
        }
        return grid
    }

    private func hammingDistance(_ a: UInt64, _ b: UInt64) -> Int {
        (a ^ b).nonzeroBitCount
    }

    private func hexString(_ value: UInt64) -> String {
        String(format: "%016llX", value)
    }
}

// MARK: - Error

private enum RegressionTestError: Error {
    case textureAllocationFailed
    case bufferAllocationFailed
    case commandBufferFailed
    case encoderCreationFailed
    case renderFailed
}
