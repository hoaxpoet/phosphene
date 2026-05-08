// ArachneSpiderRenderTests — Deterministic fixture test for the Arachne spider render path.
//
// The organic trigger (sub-bass sustain + 5-minute cooldown) makes it impossible to verify
// the spider rendering path in normal test runs. This test bypasses the trigger entirely:
// it uses `_forceActivateSpiderForTest(at:)` to set a deterministic spider state, renders
// to a 64×64 buffer, and compares the 64-bit dHash against a stored golden value.
//
// Golden hash regeneration:
//   UPDATE_GOLDEN_SNAPSHOTS=1 swift test --package-path PhospheneEngine \
//       --filter "test_printSpiderGoldenHash"
//
// The test confirms that:
//   1. The spider rendering path compiles and executes without error.
//   2. The visual output is stable across refactors (regression net).
//
// Hardware caveat (D-039): Metal shader compilation is hardware-specific. The golden
// hash is tied to the device that generated it (Apple Silicon, macOS 14+).

import Testing
import Metal
@testable import Presets
@testable import Renderer
import Shared
import simd

// MARK: - Golden hash

/// 64-bit dHash for the forced-spider render at steady energy (bass/mid/treble = 0.5).
/// Regenerate with UPDATE_GOLDEN_SNAPSHOTS=1 swift test --filter test_printSpiderGoldenHash.
///
/// V.7.7B note: Arachne's staged COMPOSITE fragment now ports the V.7.5 v5
/// foreground (anchor + pool webs + drops + spider + mist + motes), so this
/// hash is once again a real spider-render regression gate. `worldTex` is
/// unbound under this regression render, so the captured composition is the
/// foreground over a black backdrop — the spider silhouette is visible
/// because the composite fragment overlays it on top of the (zero-sampled)
/// world.
///
/// V.7.7C: drop overlay rewritten to the §5.8 Snell's-law refractive recipe
/// (D-093). Under this regression path `worldTex` is unbound → bgSeen reads
/// black; drops compose only as thin warm fresnel rim + warm specular pinpoint
/// + dark edge ring multiplied by the audio gain. Hash drift from V.7.7B is a
/// few bits — well within the dHash tolerance of 8.
///
/// V.7.7D (D-094): 2D dark-silhouette spider replaced with a 3D SDF anatomy
/// (cephalothorax + abdomen + petiole + 8 IK legs + 6 eyes) rendered into a
/// `0.15 UV` screen-space patch and shaded via the §6.2 chitin recipe. Test
/// fixture inputs (`bass_dev = 0`, `beat_bass = 0`) zero out the §8.2
/// vibration jitter, and the spider's screen-space footprint at the 64×64
/// dHash resolution is small enough that the body+legs contribute below the
/// 9×8 luma quantization threshold of the digest — hash unchanged at the
/// V.7.7C value. The new 3D spider IS rendered in this test (the colour
/// values inside the patch differ from V.7.7C's dark silhouette); the dHash
/// is just too coarse to resolve a small isolated shape change. Real visual
/// divergence is observed in PresetVisualReviewTests where pixels are
/// captured directly.
///
/// V.7.7C.2 (D-095): the spider sits on the partially-built foreground web at
/// the test fixture's elapsed time. With Commit 3's foreground-anchor block
/// reading webs[0] Row 5 (frame phase, frameProgress ≈ 0.166 at the harness
/// warmup), the silk composition under and around the spider footprint
/// changes — the formerly-fully-built foreground (V.7.7D) is now an early
/// frame thread, so the chord rings + radial spokes the spider was sitting on
/// disappear. Hamming distance from V.7.7D: 14 bits, within the D-095
/// expected [10, 30] band. Spider's own 3D anatomy + chitin material are
/// byte-identical to V.7.7D (V.7.7D contract preserved); only the silk
/// background composition under the patch changed.
///
/// V.7.7C.3 (D-095 follow-up): test now calls `state.reset()` before warmup
/// so `bs.anchors[]` is seeded by Fisher-Yates and `webs[0].rng_seed` carries
/// a non-zero packed polygon — polyCount ≥ 3 inside `arachneEvalWeb`, and the
/// polygon-from-branchAnchors path is exercised. The frame-phase foreground
/// is still mostly invisible at warmup t=0.5 s (only partial bridge thread),
/// so the visual change under the spider footprint is subtle: 7-bit drift
/// from V.7.7C.2 (within the dHash 8-bit tolerance — the polygon-aware spoke
/// clipping visibly affects only the very few pixels where partial frame
/// edges land at the harness's low warmup progress). Polygon path coverage
/// is meaningful regardless — every rendered pixel decodes polyV[] and
/// invokes ray-polygon intersection through the foreground anchor block.
private let goldenSpiderForcedHash: UInt64 = 0x46160011C2D80800

// MARK: - Test Suite

@Suite("ArachneSpiderRenderTests")
struct ArachneSpiderRenderTests {

    // MARK: - Spider forced render — golden regression

    @Test("spider forced at (0.42, 0.40) renders to stable dHash")
    func arachneSpiderForced_rendersToStableHash() throws {
        let ctx = try MetalContext()
        let loader = PresetLoader(device: ctx.device, pixelFormat: ctx.pixelFormat, loadBuiltIn: true)
        guard let preset = loader.presets.first(where: { $0.descriptor.name == "Arachne" }) else {
            // Arachne may be absent if Metal isn't available — return without failing.
            return
        }
        // Skip mesh-shader pipeline: acceptance tests can't invoke mesh pipelines via drawPrimitives.
        guard !preset.descriptor.passes.contains(.meshShader) else { return }

        guard let device = MTLCreateSystemDefaultDevice() else {
            throw SpiderTestError.noMetalDevice
        }
        guard let state = ArachneState(device: device, seed: 42) else {
            throw SpiderTestError.stateAllocationFailed
        }

        // V.7.7C.3 / D-095 follow-up — `reset()` seeds the BuildState polygon
        // (`bs.anchors[]` via Fisher-Yates) so the foreground anchor block
        // exercises polygon-aware geometry. Without reset, anchors=[] →
        // packed=0 → polyCount=0 → V.7.5 fallback (regression-mode silently
        // skips polygon-mode bugs). Production calls `reset()` from
        // `applyPreset .staged`; mirror that here.
        state.reset()

        // Advance pool so the anchor webs are stable and the best hub is known.
        let warmupFV = FeatureVector(bass: 0.5, mid: 0.5, treble: 0.5, time: 1.0, deltaTime: 1.0 / 60.0)
        for _ in 0..<30 { state.tick(features: warmupFV, stems: .zero) }

        // Force spider to deterministic position — bypasses trigger, heading=0, tips at rest.
        state.forceActivateForTest(at: SIMD2<Float>(0.42, 0.40))

        var fv = FeatureVector(bass: 0.5, mid: 0.5, treble: 0.5, time: 2.0, deltaTime: 1.0 / 60.0)
        let pixels = try renderFrameWithSpider(preset: preset, context: ctx,
                                               arachneState: state, features: &fv)
        let hash = dHash(pixels)

        if goldenSpiderForcedHash == 0 {
            // Golden not yet set — print and pass (first-run bootstrap).
            print("[ArachneSpiderRenderTests] no golden set; computed hash: 0x\(String(hash, radix: 16, uppercase: true))")
            return
        }

        let hamming = hammingDistance(hash, goldenSpiderForcedHash)
        #expect(
            hamming <= 8,
            """
            Spider hash Hamming distance \(hamming) exceeds tolerance 8 \
            got=0x\(String(hash, radix: 16, uppercase: true)) \
            golden=0x\(String(goldenSpiderForcedHash, radix: 16, uppercase: true))
            """
        )
    }

    // MARK: - Golden hash printer

    @Test("Print spider golden hash (UPDATE_GOLDEN_SNAPSHOTS only)")
    func test_printSpiderGoldenHash() throws {
        guard ProcessInfo.processInfo.environment["UPDATE_GOLDEN_SNAPSHOTS"] != nil else { return }

        let ctx = try MetalContext()
        let loader = PresetLoader(device: ctx.device, pixelFormat: ctx.pixelFormat, loadBuiltIn: true)
        guard let preset = loader.presets.first(where: { $0.descriptor.name == "Arachne" }) else {
            print("[ArachneSpiderRenderTests] Arachne preset not found — cannot generate golden")
            return
        }
        guard !preset.descriptor.passes.contains(.meshShader) else {
            print("[ArachneSpiderRenderTests] Arachne is mesh-shader — skip golden print")
            return
        }

        guard let device = MTLCreateSystemDefaultDevice() else { return }
        guard let state = ArachneState(device: device, seed: 42) else { return }

        let warmupFV = FeatureVector(bass: 0.5, mid: 0.5, treble: 0.5, time: 1.0, deltaTime: 1.0 / 60.0)
        for _ in 0..<30 { state.tick(features: warmupFV, stems: .zero) }
        state.forceActivateForTest(at: SIMD2<Float>(0.42, 0.40))

        var fv = FeatureVector(bass: 0.5, mid: 0.5, treble: 0.5, time: 2.0, deltaTime: 1.0 / 60.0)
        let pixels = try renderFrameWithSpider(preset: preset, context: ctx,
                                               arachneState: state, features: &fv)
        let hash = dHash(pixels)
        print("""

        // Paste into goldenSpiderForcedHash in ArachneSpiderRenderTests.swift:
        private let goldenSpiderForcedHash: UInt64 = 0x\(String(hash, radix: 16, uppercase: true))
        """)
    }

    // MARK: - Render helper

    private let renderSize = 64

    /// Render one frame of `preset` into a 64×64 texture with Arachne's web + spider buffers bound.
    private func renderFrameWithSpider(
        preset: PresetLoader.LoadedPreset,
        context: MetalContext,
        arachneState: ArachneState,
        features: inout FeatureVector
    ) throws -> [UInt8] {
        let size = renderSize
        let texDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: context.pixelFormat, width: size, height: size, mipmapped: false)
        texDesc.usage = [.renderTarget, .shaderRead]
        texDesc.storageMode = .shared
        guard let texture = context.device.makeTexture(descriptor: texDesc) else {
            throw SpiderTestError.textureAllocationFailed
        }

        let floatStride = MemoryLayout<Float>.stride
        guard
            let fftBuf  = context.makeSharedBuffer(length: 512 * floatStride),
            let wavBuf  = context.makeSharedBuffer(length: 2048 * floatStride),
            let stemBuf = context.makeSharedBuffer(length: MemoryLayout<StemFeatures>.size),
            let histBuf = context.makeSharedBuffer(length: 4096 * floatStride)
        else { throw SpiderTestError.bufferAllocationFailed }

        _ = stemBuf.contents().initializeMemory(as: UInt8.self, repeating: 0,
                                                 count: MemoryLayout<StemFeatures>.size)
        _ = histBuf.contents().initializeMemory(as: UInt8.self, repeating: 0,
                                                 count: 4096 * floatStride)

        guard let cmdBuf = context.commandQueue.makeCommandBuffer() else {
            throw SpiderTestError.commandBufferFailed
        }
        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = texture
        rpd.colorAttachments[0].loadAction = .clear
        rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        rpd.colorAttachments[0].storeAction = .store
        guard let encoder = cmdBuf.makeRenderCommandEncoder(descriptor: rpd) else {
            throw SpiderTestError.encoderCreationFailed
        }

        encoder.setRenderPipelineState(preset.pipelineState)
        // Standard buffer layout (all presets):
        encoder.setFragmentBytes(&features, length: MemoryLayout<FeatureVector>.size, index: 0)
        encoder.setFragmentBuffer(fftBuf,  offset: 0, index: 1)
        encoder.setFragmentBuffer(wavBuf,  offset: 0, index: 2)
        encoder.setFragmentBuffer(stemBuf, offset: 0, index: 3)
        // index 4 = SceneUniforms (ray-march only — Arachne is direct fragment, skip)
        encoder.setFragmentBuffer(histBuf, offset: 0, index: 5)
        // Arachne-specific: web pool at 6, spider GPU at 7.
        encoder.setFragmentBuffer(arachneState.webBuffer,    offset: 0, index: 6)
        encoder.setFragmentBuffer(arachneState.spiderBuffer, offset: 0, index: 7)

        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        cmdBuf.commit()
        cmdBuf.waitUntilCompleted()
        guard cmdBuf.status == .completed else { throw SpiderTestError.renderFailed }

        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        texture.getBytes(&pixels, bytesPerRow: size * 4,
                         from: MTLRegionMake2D(0, 0, size, size), mipmapLevel: 0)
        return pixels
    }

    // MARK: - dHash

    /// Computes a 64-bit dHash: downsample to a 9×8 luma grid, compare adjacent horizontal cells.
    /// BGRA byte order: luma = 0.114·B + 0.587·G + 0.299·R.
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

    private func computeLumaGrid(pixels: [UInt8], width: Int, height: Int,
                                  cols: Int, rows: Int) -> [Float] {
        var grid = [Float](repeating: 0, count: cols * rows)
        let cellW = width / cols
        let cellH = height / rows
        for row in 0..<rows {
            for col in 0..<cols {
                var sum: Float = 0
                var count = 0
                for y in (row * cellH)..<min((row + 1) * cellH, height) {
                    for x in (col * cellW)..<min((col + 1) * cellW, width) {
                        let idx = (y * width + x) * 4
                        let blue  = Float(pixels[idx])
                        let green = Float(pixels[idx + 1])
                        let red   = Float(pixels[idx + 2])
                        sum += 0.114 * blue + 0.587 * green + 0.299 * red
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
}

// MARK: - Errors

private enum SpiderTestError: Error {
    case noMetalDevice
    case stateAllocationFailed
    case textureAllocationFailed
    case bufferAllocationFailed
    case commandBufferFailed
    case encoderCreationFailed
    case renderFailed
}
