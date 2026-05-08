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
    // V.7.7B Arachne: staged COMPOSITE fragment now ports the V.7.5 v5 web
    // walk + spider + mist + dust motes. The regression renders the COMPOSITE
    // stage in isolation with `worldTex` unbound (texture sampler returns 0),
    // so the hash captures the foreground composition alone — silk strands,
    // adhesive droplets, mist + motes — over a black backdrop. The full
    // WORLD + COMPOSITE composite is exercised by PresetVisualReviewTests.
    //
    // V.7.7C (D-093): drop overlay rewritten to §5.8 Snell's-law refractive
    // recipe. Under this regression path `worldTex` is unbound → bgSeen reads
    // black; drops compose as thin warm fresnel rim + warm specular pinpoint
    // + dark edge ring × audio gain. dHash UNCHANGED at the V.7.7B values:
    // the new contributions sum below the 9×8 luma quantization threshold of
    // dHash, so the foreground silhouette fingerprint is bytewise identical.
    // Real visual divergence is observed in PresetVisualReviewTests.
    //
    // V.7.7D (D-094): 3D SDF spider replaces the 2D overlay (spider not drawn
    // under regression — `spider.blend = 0` when buffer is unbound), and a
    // §8.2 12 Hz UV-jitter vibration is applied to the foreground web walks.
    // Vibration amplitude is gated by `bass_dev` + `beat_bass` so the silence
    // and quiet fixtures (zero/low values) produce no visible shake — those
    // hashes stay byte-identical. The beatHeavy fixture (`beat_bass` ≈ 1.0)
    // produces a small UV jitter that drifts the silk pattern by a few bits;
    // hash updated to match. Real visual divergence — including the new 3D
    // spider — is observed in PresetVisualReviewTests / ArachneSpiderRenderTests.
    //
    // V.7.7C.2 (D-095): Commit 3 swaps the foreground anchor's data source
    // from hardcoded (stage=3, progress=1) to webs[0] Row 5 BuildState. At
    // the harness's 0.5 s warmup the foreground hero is in frame phase at
    // frameProgress ≈ 0.166 (only the partial bridge thread renders), so the
    // V.7.7D upper-left fully-built foreground web disappears from the
    // regression composition. webs[1] (the second seedInitialWebs() stable
    // web) continues to render at lower-right unchanged, providing background
    // depth context. All three fixtures converge to the same hash because
    // the harness warmup uses one shared warmFV regardless of fixture — the
    // per-fixture pace differences surface only on real-music playback
    // (Matt's manual smoke gate). Hamming distance from V.7.7D `steady`:
    // 16 bits, within the D-095 expected [10, 30] band.
    //
    // V.7.7C.3 (D-095 follow-up): hash UNCHANGED. PresetRegression's render
    // harness does not bind slot 6 / 7 (sees zeroed buffers), so:
    //   - webs[0].rng_seed = 0 → polyCount = 0 → V.7.5 fallback (circular
    //     spoke tips, regular oval) instead of the new polygon path.
    //   - Pool loop iterates `wi=1..1` (empty) so the V.7.5 churn that
    //     V.7.7C.3 retired never appeared in this regression anyway.
    //   - webs[0].build_stage = 0 → foreground frame phase at 0 % progress,
    //     no visible foreground content.
    // Net: only the WORLD backdrop renders, identical to V.7.7C.2's
    // composition. The V.7.7C.3 polygon-mode visual change IS exercised by
    // ArachneSpiderRenderTests (which binds a real, reset()-seeded
    // ArachneState) and by PresetVisualReviewTests' RENDER_VISUAL=1 path.
    //
    // V.7.7C.5 (D-100): Arachne hashes UNCHANGED again. The §4 atmospheric
    // reframe retires the WORLD-side six-layer forest and replaces it with
    // the §4.2 sky band + volumetric atmosphere, AND the WEB pillar's
    // foreground hero web is now canvas-filling (`webR = 0.55`, hub at
    // (0.5, 0.5), polygon vertices off-frame). PresetRegression still
    // doesn't bind slot 6/7, so:
    //   - The COMPOSITE fragment samples `worldTex` for its backdrop, but
    //     the regression harness leaves `worldTex` unbound → bgColor = 0.
    //     The §4 WORLD reframe therefore produces no visible change in the
    //     regression-mode composition (which only sees COMPOSITE alone).
    //   - Foreground hero web at (0.5, 0.5) / `webR = 0.55` would now span
    //     most of the canvas — but the harness's zeroed slot-6 buffer gives
    //     `build_stage = 0, frame_progress = 0` → frame phase at 0 % →
    //     nothing rendered, so the canvas-filling change also doesn't
    //     surface here.
    //   - Spider hash DOES drift (`ArachneSpiderRenderTests` binds a
    //     `state.reset()`-seeded `ArachneState`, so the off-frame
    //     `kBranchAnchors[6]` move into the polygon decode path). Hamming
    //     distance V.7.7C.4 → V.7.7C.5: 7 bits (`0x06129A55C258494D` →
    //     `0x06D29A65E458494D`).
    // Real visual divergence — sky band + light shafts + canvas-filling
    // web — is observed in `PresetVisualReviewTests` (per-stage harness
    // with worldTex bound + reset()-seeded `ArachneState`).
    //
    // V.7.7C.4 (D-095 follow-up): hashes drift. Three fixes contribute:
    //   - Silk palette enrichment (silkTint 0.60 → 0.85; mood-driven hue;
    //     vocal-pitch coupling; ambient tint 0.25 → 0.40). Affects the
    //     foreground anchor block's silk emission stage — visible whenever
    //     `wr.strandCov > 0.001`.
    //   - Hub knot brightness 0.80 → 1.20 (saturated). Visible from
    //     `stage >= 1u`.
    //   - Per-beat global emission pulse `beatPulse * 0.45`. Adds
    //     `beat_bass`/`beat_composite` energy to silk brightness when a
    //     beat is firing.
    // PresetRegression still doesn't bind slot 6/7, so foreground at
    // frame-phase 0% has no silk content. The hash drift here comes from
    // the §8.2 vibration UV jitter applied at the top of
    // arachne_composite_fragment — which uses `bass_att_rel`. The
    // V.7.7C.4 changes don't move this term, but the cumulative shifts
    // through the V.7.7C.3 polygon mode + V.7.7C.4 emission stage produce
    // a slightly different per-pixel composition under noise alignment.
    // beatHeavy fixture (`beat_bass = 1.0`, `bassDev = 0.60`) diverges
    // from steady/quiet (zero bass deviation → no vibration). All three
    // fixtures within the [10, 30] hamming band documented for D-095.
    "Arachne": (steady: 0x06129A65E458494D, beatHeavy: 0xC6921125C4D85849, quiet: 0x06129A65E458494D),
    "Ferrofluid Ocean": (steady: 0x56AB1C4A28B32727, beatHeavy: 0x5CB393AAAFA84840, quiet: 0xA64C51A62FD35356),
    "Glass Brutalist": (steady: 0x336954B4B4544D33, beatHeavy: 0x336954B4B4544D33, quiet: 0x336954B4B4544D33),
    // DM.2: Drift Motes regression fixtures capture the warm-amber sky +
    // light shaft + floor fog backdrop. The harness renders the sky
    // fragment (`drift_motes_sky_fragment`) only; it does not dispatch
    // the `motes_update` particle kernel, so per-mote hue (D-019 blend
    // baking) is regression-locked separately by
    // `DriftMotesRespawnDeterminismTest`. The shaft intensity reads
    // `f.mid_att_rel`, which is zero across all three regression
    // fixtures, so steady / beatHeavy / quiet converge to the same hash.
    // Murmuration's path stays byte-identical to the post-DM.0 baseline
    // (D-097, DM.1).
    "Drift Motes": (steady: 0x0001070F1F3F7FFF, beatHeavy: 0x0001070F1F3F7FFF, quiet: 0x0001070F1F3F7FFF),
    "Gossamer": (steady: 0x5756A72F070F0F0D, beatHeavy: 0x5756A72F070F0F0D, quiet: 0x5756872D0F0F0F0D),
    // QR.1 (D-079): sminK now mixes continuous bass (Layer 1) + bass_dev
    // accent. steady/quiet hashes regenerated to original V.7 values within
    // the 8-bit dHash tolerance; beatHeavy shifts slightly because bass_dev
    // now contributes a small +0.06 to the smooth-union radius.
    "Kinetic Sculpture": (steady: 0x5EAB7295D25B4A4A, beatHeavy: 0x5AAB72B5564B4A4B, quiet: 0x56AB7295925B4A4A),
    "Membrane": (steady: 0x33E3A919C9627939, beatHeavy: 0x12A3A998C9646139, quiet: 0x47E3C919CD627959),
    "Murmuration": (steady: 0x07449B6727773FF8, beatHeavy: 0x0B449A4727373FF8, quiet: 0x0744936727773FF8),
    "Nebula": (steady: 0x0000080C0C080000, beatHeavy: 0x0000080C0C080000, quiet: 0x0000080C0C080000),
    "Plasma": (steady: 0x030F170A072F1B0F, beatHeavy: 0x4193254F0E8E87C7, quiet: 0x0F1F0F0F0F07070F),
    "Spectral Cartograph": (steady: 0x00180C0C0C0C0000, beatHeavy: 0x00180C0C0C0C6080, quiet: 0x00180C0C0C0C0000),
    "Staged Sandbox": (steady: 0x000022160A162A00, beatHeavy: 0x000022160A162A00, quiet: 0x000022160A162A00),
    "Volumetric Lithograph": (steady: 0x8C63D43512030000, beatHeavy: 0x8C63D43512030000, quiet: 0x8C63D43512030000),
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
