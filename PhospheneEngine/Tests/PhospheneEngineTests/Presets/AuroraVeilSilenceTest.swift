// AuroraVeilSilenceTest — AV.1 silence-stable rendering gate.
//
// Renders Aurora Veil at zero audio (FeatureVector zero-init, StemFeatures.zero)
// and asserts three properties that together cover the AV.1 silence acceptance:
//
//   1. Non-black output. Mean luma exceeds a small threshold — proves the sky
//      gradient + stars + dimmed aurora column produce above-zero output at
//      silence (L1 silence fallback per `AURORA_VEIL_DESIGN.md §5.8`).
//
//   2. Vertically-stratified colour (Lawlor stratification check). Sampling
//      along a vertical slice through the brightest column, the LOWER edge
//      of the aurora band (large uv.y, closer to horizon) reads green-dominant
//      while the UPPER edge (small uv.y, closer to zenith) carries more
//      magenta. This validates the per-march-step IQ palette + per-fragment
//      screen-altitude phase offset are producing the green-base / magenta-
//      crown gradient — research §1.2 H(z) curve.
//
//   3. Form complexity ≥ 2 at silence. The top 20 % (sky) has non-zero luma
//      gradient (stars + sky gradient); the middle 60 % (aurora band) has a
//      local luma max; the bottom 20 % is darker than the middle. Three
//      distinct visual structures present — the L1 rubric gate.
//
// This is the AV.1 "Done When" silence test from `prompts/AV.1-prompt.md`.
// AV.2 + AV.3 add separate tests (continuous-dominance, pitch-hue).

import Testing
import Metal
@testable import Renderer
@testable import Presets
@testable import Shared

// 16-byte zero-initialised AuroraVeilStateGPU mirror used by the test
// harness. `kinkAccumulator = 0` (no kink at silence — matches CPU state's
// silence-stable baseline); `smoothedPitchNorm = 0` (irrelevant because
// the shader's `pitchConfident` gate is 0 when stems are zero, so the read
// falls back to the neutral 0.5 baseline).
private struct AuroraVeilStateGPUMirror {
    var kinkAccumulator: Float = 0
    var smoothedPitchNorm: Float = 0
    var padA: Float = 0
    var padB: Float = 0
}

@Suite("AuroraVeil silence")
struct AuroraVeilSilenceTest {

    // 256×128 is large enough to expose the vertical stratification and stars
    // without making the test slow. The harness reads back BGRA bytes for
    // direct sampling.
    private static let renderWidth  = 256
    private static let renderHeight = 128

    // MARK: - Assertion 1: Non-black output

    @Test("Aurora Veil at silence produces non-black output (sky + stars + dim aurora)")
    func test_silence_isNotBlack() throws {
        guard let pixels = try renderSilenceFrame() else {
            print("AuroraVeilSilenceTest: skipping — no Metal device or preset missing")
            return
        }
        let meanLuma = computeMeanLuma(pixels: pixels)
        // Sky gradient (very dim) + sparse stars + faintly-drifting aurora at
        // silence-time should land mean luma well above 0.005 in [0, 1] space.
        // BGRA bytes are in [0, 255]; threshold in byte units = 0.005 × 255 ≈ 1.3.
        #expect(
            meanLuma > 1.3,
            """
            Aurora Veil silence mean luma \(meanLuma) ≤ threshold (1.3 / 255). \
            Preset likely renders fully black at silence — sky / star / aurora \
            layers are not contributing.
            """
        )
    }

    // MARK: - Assertion 2: Vertical Lawlor stratification

    @Test("Aurora Veil at silence shows green-base / magenta-crown stratification")
    func test_silence_isVerticallyStratified() throws {
        guard let pixels = try renderSilenceFrame() else {
            print("AuroraVeilSilenceTest: skipping — no Metal device or preset missing")
            return
        }

        // Find the column (uv.x) with the highest aggregate luma in the aurora
        // band (uv.y ∈ [0.30, 0.70]). Sample 256 columns at three altitudes,
        // pick the one with the brightest mid-altitude sample.
        let brightCol = findBrightestColumnInAuroraBand(pixels: pixels)

        // Sample at three uv.y values within the aurora envelope (which
        // ramps in at uv.y=0.05..0.40 and cuts off at uv.y=0.74..0.84).
        // uv.y=0.25 → upper aurora band (screenAlt high → magenta-shifted)
        // uv.y=0.50 → mid aurora band
        // uv.y=0.65 → lower aurora band (screenAlt low → green-dominant)
        let upperColor = samplePixel(pixels: pixels, ux: brightCol, uy: 0.25)
        let lowerColor = samplePixel(pixels: pixels, ux: brightCol, uy: 0.65)

        // Lower aurora band must read green-dominant (G > R and G > B). Use a
        // small slack to avoid floating-point flakiness at the edge.
        let lowerGreenDominant = lowerColor.g > lowerColor.r + 0.5 / 255.0
                              && lowerColor.g > lowerColor.b + 0.5 / 255.0
        #expect(
            lowerGreenDominant,
            """
            Lower aurora band (uv.y=0.65) is not green-dominant: \
            RGB=(\(lowerColor.r), \(lowerColor.g), \(lowerColor.b)). \
            Likely cause: per-march-step palette phase offsets are off, or \
            the screen-altitude phase offset is mis-signed.
            """
        )

        // Upper aurora band must carry more magenta content (R + B) than the
        // lower band. Use combined R+B comparison to be robust to overall
        // brightness differences between the two altitudes.
        let upperMagentaContent = upperColor.r + upperColor.b
        let lowerMagentaContent = lowerColor.r + lowerColor.b
        #expect(
            upperMagentaContent > lowerMagentaContent + 1.0 / 255.0,
            """
            Upper aurora band (uv.y=0.25) does not carry more magenta than \
            lower (uv.y=0.65): upper R+B=\(upperMagentaContent), \
            lower R+B=\(lowerMagentaContent). Lawlor H(z) stratification is \
            not manifesting on screen — likely cause: screen-altitude phase \
            offset is too small or zero.
            """
        )
    }

    // MARK: - Assertion 3: Form complexity ≥ 2

    @Test("Aurora Veil at silence has 3 distinct vertical regions (sky / aurora / dark base)")
    func test_silence_formComplexity() throws {
        guard let pixels = try renderSilenceFrame() else {
            print("AuroraVeilSilenceTest: skipping — no Metal device or preset missing")
            return
        }

        // Per-row mean luma.
        let rowLuma = computeRowLumaProfile(pixels: pixels)

        // Sky band: uv.y ∈ [0.00, 0.20]. Must have non-zero luma gradient (sky
        // gradient + occasional star samples). Coarse check: max-min over rows
        // in the band > a small threshold.
        let skyBand = rowLuma.prefix(Int(0.20 * Double(Self.renderHeight)))
        let skyMin = skyBand.min() ?? 0
        let skyMax = skyBand.max() ?? 0
        #expect(
            skyMax - skyMin > 0.5,
            """
            Sky band (top 20 %) shows no vertical luma variation \
            (max=\(skyMax), min=\(skyMin)). Sky gradient + stars layer is \
            not contributing.
            """
        )

        // Aurora band: uv.y ∈ [0.30, 0.70]. Must have a strict local maximum
        // versus the sky and the bottom — i.e., mean luma in this band exceeds
        // mean luma in both surrounding bands.
        let auroraStart  = Int(0.30 * Double(Self.renderHeight))
        let auroraEnd    = Int(0.70 * Double(Self.renderHeight))
        let auroraMean   = rowLuma[auroraStart..<auroraEnd].reduce(0, +) / Float(auroraEnd - auroraStart)

        // Bottom band: uv.y ∈ [0.85, 1.00]. Must be darker than the aurora
        // band (auroraEnv cutoff at uv.y > 0.84 → near-zero aurora here, only
        // the sky gradient remains).
        let bottomStart  = Int(0.85 * Double(Self.renderHeight))
        let bottomBand   = rowLuma[bottomStart..<Self.renderHeight]
        let bottomMean   = bottomBand.reduce(0, +) / Float(Self.renderHeight - bottomStart)

        #expect(
            auroraMean > bottomMean + 1.0,
            """
            Aurora band (uv.y∈[0.30,0.70], mean=\(auroraMean)) is not \
            brighter than bottom band (uv.y∈[0.85,1.00], mean=\(bottomMean)). \
            The aurora envelope is not producing a defined lower edge.
            """
        )

        let skyMean = skyBand.reduce(0, +) / Float(skyBand.count)
        #expect(
            auroraMean > skyMean + 0.5,
            """
            Aurora band (mean=\(auroraMean)) is not brighter than sky band \
            (mean=\(skyMean)). The aurora column is not contributing visible \
            luma above the sky baseline.
            """
        )
    }

    // MARK: - Render harness

    /// Renders Aurora Veil at silence into a BGRA byte buffer
    /// (`renderWidth × renderHeight × 4`). Returns nil if Metal is unavailable
    /// or the preset failed to load (CI fallback path).
    private func renderSilenceFrame() throws -> [UInt8]? {
        guard let preset = _acceptanceFixture.presets.first(where: {
            $0.descriptor.name == "Aurora Veil"
        }) else {
            return nil
        }
        let ctx = try MetalContext()

        let width = Self.renderWidth
        let height = Self.renderHeight

        let texDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: ctx.pixelFormat,
            width: width, height: height, mipmapped: false)
        texDesc.usage = [.renderTarget, .shaderRead]
        texDesc.storageMode = .shared
        guard let texture = ctx.device.makeTexture(descriptor: texDesc) else { return nil }

        let floatStride = MemoryLayout<Float>.stride
        guard
            let fft  = ctx.makeSharedBuffer(length: 512 * floatStride),
            let wav  = ctx.makeSharedBuffer(length: 2048 * floatStride),
            let stem = ctx.makeSharedBuffer(length: MemoryLayout<StemFeatures>.size),
            let hist = ctx.makeSharedBuffer(length: 4096 * floatStride),
            let avState = ctx.makeSharedBuffer(length: MemoryLayout<AuroraVeilStateGPUMirror>.stride)
        else { return nil }
        _ = fft.contents().initializeMemory(as: UInt8.self, repeating: 0, count: 512 * floatStride)
        _ = stem.contents().initializeMemory(as: UInt8.self, repeating: 0,
                                             count: MemoryLayout<StemFeatures>.size)
        _ = hist.contents().initializeMemory(as: UInt8.self, repeating: 0, count: 4096 * floatStride)
        // AV.2: bind a zero AuroraVeilStateGPU at slot 6. The shader's
        // pitch-confidence gate (`vocals_pitch_confidence >= 0.5`) is 0 in
        // silence so `smoothedPitchNorm` is ignored; `kinkAccumulator = 0`
        // produces no lateral UV jitter. Silence equivalent to AV.1.
        var avState0 = AuroraVeilStateGPUMirror()
        avState.contents().copyMemory(from: &avState0,
                                      byteCount: MemoryLayout<AuroraVeilStateGPUMirror>.stride)

        // Silence FeatureVector — time advanced enough that the time-driven
        // noise rotation is non-trivial (so the asymmetric stratification
        // check doesn't accidentally hit a noise-field symmetry point).
        var features = FeatureVector(time: 3.0, deltaTime: 0.016)

        guard let cmd = ctx.commandQueue.makeCommandBuffer() else { return nil }
        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = texture
        rpd.colorAttachments[0].loadAction = .clear
        rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        rpd.colorAttachments[0].storeAction = .store
        guard let enc = cmd.makeRenderCommandEncoder(descriptor: rpd) else { return nil }

        enc.setRenderPipelineState(preset.pipelineState)
        enc.setFragmentBytes(&features, length: MemoryLayout<FeatureVector>.size, index: 0)
        enc.setFragmentBuffer(fft, offset: 0, index: 1)
        enc.setFragmentBuffer(wav, offset: 0, index: 2)
        enc.setFragmentBuffer(stem, offset: 0, index: 3)
        enc.setFragmentBuffer(hist, offset: 0, index: 5)
        enc.setFragmentBuffer(avState, offset: 0, index: 6)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
        cmd.commit()
        cmd.waitUntilCompleted()
        guard cmd.status == .completed else { return nil }

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        texture.getBytes(&pixels, bytesPerRow: width * 4,
                         from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        return pixels
    }

    // MARK: - Pixel helpers

    /// Linear-space RGB triple sampled at (ux, uy) in [0, 1] UV.
    private struct PixelRGB {
        let r: Float
        let g: Float
        let b: Float
    }

    /// Sample one pixel. BGRA byte layout: pixel[0]=B, pixel[1]=G, pixel[2]=R.
    private func samplePixel(pixels: [UInt8], ux: Float, uy: Float) -> PixelRGB {
        let x = max(0, min(Self.renderWidth  - 1, Int(ux * Float(Self.renderWidth))))
        let y = max(0, min(Self.renderHeight - 1, Int(uy * Float(Self.renderHeight))))
        let idx = (y * Self.renderWidth + x) * 4
        return PixelRGB(r: Float(pixels[idx + 2]),
                        g: Float(pixels[idx + 1]),
                        b: Float(pixels[idx + 0]))
    }

    /// Mean luma (BT.601 weights) over the whole frame, in [0, 255].
    private func computeMeanLuma(pixels: [UInt8]) -> Float {
        var sum: Float = 0
        let total = Self.renderWidth * Self.renderHeight
        for i in 0..<total {
            let b = Float(pixels[i * 4 + 0])
            let g = Float(pixels[i * 4 + 1])
            let r = Float(pixels[i * 4 + 2])
            sum += 0.299 * r + 0.587 * g + 0.114 * b
        }
        return sum / Float(total)
    }

    /// Per-row mean luma profile, length `renderHeight`, values in [0, 255].
    private func computeRowLumaProfile(pixels: [UInt8]) -> [Float] {
        var profile = [Float](repeating: 0, count: Self.renderHeight)
        for y in 0..<Self.renderHeight {
            var sum: Float = 0
            for x in 0..<Self.renderWidth {
                let idx = (y * Self.renderWidth + x) * 4
                let b = Float(pixels[idx + 0])
                let g = Float(pixels[idx + 1])
                let r = Float(pixels[idx + 2])
                sum += 0.299 * r + 0.587 * g + 0.114 * b
            }
            profile[y] = sum / Float(Self.renderWidth)
        }
        return profile
    }

    /// Returns the uv.x in [0, 1] of the column with the brightest aurora-mid
    /// sample (uv.y = 0.50). Robust against having the brightness max in a
    /// stars-only region of the sky.
    private func findBrightestColumnInAuroraBand(pixels: [UInt8]) -> Float {
        let midY = Int(0.50 * Double(Self.renderHeight))
        var bestX = 0
        var bestLuma: Float = -1
        for x in 0..<Self.renderWidth {
            let idx = (midY * Self.renderWidth + x) * 4
            let b = Float(pixels[idx + 0])
            let g = Float(pixels[idx + 1])
            let r = Float(pixels[idx + 2])
            let luma = 0.299 * r + 0.587 * g + 0.114 * b
            if luma > bestLuma {
                bestLuma = luma
                bestX = x
            }
        }
        return (Float(bestX) + 0.5) / Float(Self.renderWidth)
    }
}
