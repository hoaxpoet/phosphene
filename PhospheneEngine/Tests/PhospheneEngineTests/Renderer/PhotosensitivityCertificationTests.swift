// PhotosensitivityCertificationTests — enforced flash-safety gate (CLEAN.7.6, GAP-9).
//
// Every CERTIFIED preset is rendered over a synthetic worst-case beat train and
// its rendered full-frame luminance is measured against the Harding / WCAG 2.3.1
// general-flash limit (≤ 3 flashes/s). A preset that exceeds the limit FAILS the
// gate — it is a P1 safety finding to bring to Matt, not a number to tune away
// (CLEAN.7.6 rule; the certified beat-luminance motion was hand-tuned safe).
//
// WHY a synthetic drive (and not a recorded real session): the FBS forensics
// video that the kickoff named as the A/B reference was never committed, and the
// `Fixtures/fbs` CSVs are 3-band energy extracts that carry none of the beat /
// deviation / stem signals that actually cause flashing. The established cert
// gates (PresetContrastCertificationTests, PresetRegressionTests) all drive from
// synthetic FeatureVector fixtures rendered in-test; this gate follows that
// pattern. (Matt's pick, 2026-06-16: synthetic CI gate now; the blind spots
// below fold into the A-next runtime-clamp increment.)
//
// COVERAGE (CLEAN.7.6 finding, 2026-06-16; Matt's call: partial gate now, the
// rest folds into the A-next real-pipeline harness). This lightweight harness
// drives only the FeatureVector through a single fragment pass. It therefore
// VALIDLY measures only presets that read their music response directly from
// the FeatureVector in that pass — verified: Ferrofluid Ocean and Murmuration
// (both SAFE). The other certified presets render STATIC here because their
// music response arrives via paths this harness does not run:
//   - Lumen Mosaic, Nimbus: CPU follower-state buffer (slots 6/8) — zeroed here.
//   - Dragon Bloom, Fata Morgana: rayMarch — need the multi-pass G-buffer chain.
//   - Skein: painterly — needs feedback-texture history.
// A static render is NEVER asserted "safe" (that would be a vacuous pass — the
// cardinal sin for a safety gate). Such presets are tracked in
// `unmeasurableInHarness` and the gate FAILS LOUD on drift: if a known-static
// preset starts responding, or a known-responsive one (FFO/Murmuration) goes
// static, or a new certified preset renders static. Valid flash-safety for the
// static set requires the A-next headless real-RenderPipeline harness.
//
// FURTHER blind spots (all A-next): full-frame mean only (a sub-region flash <
// 10 % of the mean passes — regional/area-gating is the refinement); no
// saturated-red-flash channel; normal certified regime only (no edge states).

import Testing
import Metal
@testable import Renderer
@testable import Presets
@testable import Shared

// MARK: - PhotosensitivityCertificationTests

@Suite("Photosensitivity Certification (Harding / WCAG 2.3.1, CLEAN.7.6)")
struct PhotosensitivityCertificationTests {

    private let renderSize = 64
    private let fps = 60.0
    /// Worst-case accent rate: comfortably above the 3/s Harding limit (so a
    /// genuine full-frame strobe fails with margin) yet low enough that a
    /// preset's luminance smoothing cannot attenuate it away.
    private let accentHz = 4.5
    private let driveSeconds = 3.0
    /// Minimum full-frame luminance range for a render to count as "responded
    /// to the drive". Below this the single-pass harness produced a static frame
    /// (music response is follower-state / multi-pass / feedback-driven) and the
    /// measurement is not valid — observed responders sit at Δ ≥ 0.010, static
    /// presets at Δ = 0.000, so 0.003 cleanly separates them.
    private let responsiveLumaRange = 0.003

    /// Certified presets the single-pass FeatureVector harness cannot validly
    /// measure (they render static — see the file header). Tracked here so the
    /// gate FAILS LOUD on drift rather than silently passing them. Closing these
    /// out is the A-next runtime-clamp increment (real RenderPipeline, headless).
    static let unmeasurableInHarness: Set<String> = [
        "Lumen Mosaic", "Nimbus", "Dragon Bloom", "Fata Morgana", "Skein",
    ]

    // MARK: - Gate

    @Test("Certified preset is flash-safe under a worst-case beat train (or tracked as unmeasurable)",
          arguments: _acceptanceFixture.presets)
    func certifiedPresetIsFlashSafe(_ preset: PresetLoader.LoadedPreset) throws {
        // Gate covers the certified, shipping set. Mesh-shader presets cannot
        // drawPrimitives in this harness and are skipped (same as the other gates).
        guard preset.descriptor.certified else { return }
        guard !preset.descriptor.passes.contains(.meshShader) else { return }
        let name = preset.descriptor.name

        let ctx = try MetalContext()
        let drive = worstCaseBeatTrain(accentHz: accentHz, seconds: driveSeconds, fps: fps)
        let luma = try renderLuminanceSequence(preset: preset, features: drive, context: ctx)
        let report = FlashAnalyzer.analyze(relativeLuminance: luma, fps: fps)

        // Did the preset actually respond to the drive? A static render means the
        // harness cannot reach this preset's music response (see file header).
        let lo = luma.min() ?? 0, hi = luma.max() ?? 0
        let range = hi - lo
        let responded = range >= responsiveLumaRange
        let mean = luma.reduce(0, +) / Double(max(luma.count, 1))

        // Evidence line (closeout per-preset table). This gate's measured output
        // is its visual evidence; printed for every certified preset.
        print(String(
            format: "[flash-safety] %@: %@ | peak %.2f flashes/s (%d transitions) — %@ | luma %.3f…%.3f (Δ%.3f, mean %.3f) [limit 3.0]",
            name, responded ? "MEASURED" : "UNMEASURED(static)",
            report.peakFlashesPerSecond, report.transitionCount,
            report.isSafe ? "SAFE" : "UNSAFE", lo, hi, range, mean))

        if responded {
            // Validly measured → real Harding/WCAG safety assertion.
            #expect(
                report.isSafe,
                """
                '\(name)' peaks at \(String(format: "%.2f", report.peakFlashesPerSecond)) \
                flashes/s (limit 3) under a \(String(format: "%.1f", accentHz)) Hz worst-case beat train \
                — exceeds Harding/WCAG 2.3.1. P1 safety finding: bring to Matt, do not tune away.
                """
            )
            // A preset we thought was unmeasurable now responds — good news, but
            // the tracking set is stale and it should be promoted to a real gate.
            #expect(
                !Self.unmeasurableInHarness.contains(name),
                "'\(name)' now responds to the flash drive — remove it from `unmeasurableInHarness`; it is now genuinely gated."
            )
        } else {
            // Static render → measurement is NOT valid; never assert "safe".
            // Fail only if this static render is unexpected (a regression in a
            // responsive preset, or a new certified preset needing the A-next harness).
            #expect(
                Self.unmeasurableInHarness.contains(name),
                """
                '\(name)' rendered static (Δ\(String(format: "%.3f", range))) under the flash drive but is NOT in \
                `unmeasurableInHarness` — it cannot be validly flash-gated by this single-pass harness. \
                Either a responsive preset regressed, or a new certified preset needs the A-next \
                real-pipeline harness; add it to the set and track it.
                """
            )
        }
    }

    /// Guards against a vacuous pass: if the Shaders bundle fails to load, the
    /// parameterized gate above would run zero certified cases and silently pass.
    @Test("Certified preset set is non-empty (gate is not vacuous)")
    func certifiedSetIsPresent() {
        let certified = _acceptanceFixture.presets.filter { $0.descriptor.certified }
        #expect(!certified.isEmpty, "No certified presets loaded — Shaders bundle missing? The flash gate would pass vacuously.")
    }

    // MARK: - Worst-case beat train

    /// A synthetic drive that maximally exercises the beat-accent / deviation
    /// pathway (the FBS "beat-punch" flash class) at `accentHz`: sharp,
    /// full-amplitude, impulse-decayed accents over energetic-but-smoothed
    /// continuous bands, in the normal certified regime.
    private func worstCaseBeatTrain(accentHz: Double, seconds: Double, fps: Double) -> [FeatureVector] {
        let count = Int(seconds * fps)
        let period = fps / accentHz          // frames per accent
        let barLen = period * 4
        var out: [FeatureVector] = []
        out.reserveCapacity(count)
        for i in 0..<count {
            let t = Float(Double(i) / fps)
            let phase = Double(i).truncatingRemainder(dividingBy: period) / period   // 0…1 within a beat
            let env = Float(exp(-phase * 6.0))    // 1.0 at onset → impulse decay before next beat

            // Continuous bands: energetic, only mildly beat-coupled — real AGC'd
            // bands are smoothed and do not strobe. The sharp signal lives in the
            // accents and deviation spikes below.
            let cont = 0.55 + 0.15 * env
            var fv = FeatureVector(
                bass: cont, mid: cont * 0.95, treble: cont * 0.9,
                bassAtt: 0.55 + 0.08 * env, midAtt: 0.52 + 0.08 * env, trebleAtt: 0.5 + 0.08 * env,
                subBass: cont, lowBass: cont, lowMid: cont * 0.95,
                midHigh: cont * 0.9, highMid: cont * 0.9, high: cont * 0.85,
                beatBass: env, beatMid: env, beatTreble: env, beatComposite: env,
                spectralCentroid: 0.5 + 0.3 * env, spectralFlux: env,
                valence: 0.2, arousal: 0.85,
                time: t, deltaTime: Float(1.0 / fps),
                accumulatedAudioTime: t * 0.6)

            // Deviation primitives: mild continuous Rel + sharp positive Dev
            // spikes to the real p99 (~0.85) — the accent/threshold flash pathway.
            let contRel = (cont - 0.5) * 2.0
            fv.bassRel = contRel; fv.midRel = contRel; fv.trebRel = contRel
            fv.bassDev = env * 0.85; fv.midDev = env * 0.85; fv.trebDev = env * 0.85
            fv.bassAttRel = contRel * 0.7; fv.midAttRel = contRel * 0.7; fv.trebAttRel = contRel * 0.7

            // Phase signals: normal progression through beats / bars / pulses.
            fv.beatPhase01 = Float(phase); fv.beatsUntilNext = Float(1.0 - phase)
            fv.barPhase01 = Float(Double(i).truncatingRemainder(dividingBy: barLen) / barLen)
            fv.beatsPerBar = 4
            fv.pulsePhase01 = Float(phase); fv.pulseAmp01 = 1.0
            fv.pulseBeatIndex = Float(Int(Double(i) / period))
            fv.pulseRegionalBlend01 = 1.0    // certified regional regime (FBS fix engaged)
            fv.trackElapsedS = t             // warm — past any cold-start crossfade
            out.append(fv)
        }
        return out
    }

    // MARK: - Rendering

    /// Render `features` frame-by-frame (feedback-less, cleared each frame) and
    /// return the per-frame WCAG relative luminance (linear-light, Rec. 709).
    private func renderLuminanceSequence(
        preset: PresetLoader.LoadedPreset,
        features: [FeatureVector],
        context ctx: MetalContext
    ) throws -> [Double] {
        let size = renderSize
        let texDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: ctx.pixelFormat, width: size, height: size, mipmapped: false)
        texDesc.usage = [.renderTarget, .shaderRead]
        texDesc.storageMode = .shared
        guard let texture = ctx.device.makeTexture(descriptor: texDesc) else {
            throw FlashGateError.textureAllocationFailed
        }
        let floatStride = MemoryLayout<Float>.stride
        guard
            let fft  = ctx.makeSharedBuffer(length: 512 * floatStride),
            let wav  = ctx.makeSharedBuffer(length: 2048 * floatStride),
            let stem = ctx.makeSharedBuffer(length: MemoryLayout<StemFeatures>.size),
            let hist = ctx.makeSharedBuffer(length: 4096 * floatStride),
            let slot = ctx.makeSharedBuffer(length: 1024)
        else { throw FlashGateError.bufferAllocationFailed }
        _ = stem.contents().initializeMemory(as: UInt8.self, repeating: 0, count: MemoryLayout<StemFeatures>.size)
        _ = hist.contents().initializeMemory(as: UInt8.self, repeating: 0, count: 4096 * floatStride)
        _ = slot.contents().initializeMemory(as: UInt8.self, repeating: 0, count: 1024)

        var scene: MTLBuffer?
        if preset.descriptor.passes.contains(.rayMarch),
           let buf = ctx.makeSharedBuffer(length: MemoryLayout<SceneUniforms>.size) {
            var su = preset.descriptor.makeSceneUniforms()
            buf.contents().copyMemory(from: &su, byteCount: MemoryLayout<SceneUniforms>.size)
            scene = buf
        }

        var luma: [Double] = []
        luma.reserveCapacity(features.count)
        var pixels = [UInt8](repeating: 0, count: size * size * 4)

        for frameIndex in features.indices {
            var fv = features[frameIndex]
            guard let cmdBuf = ctx.commandQueue.makeCommandBuffer() else {
                throw FlashGateError.commandBufferFailed
            }
            let rpd = MTLRenderPassDescriptor()
            rpd.colorAttachments[0].texture     = texture
            rpd.colorAttachments[0].loadAction  = .clear   // feedback-less (documented limit)
            rpd.colorAttachments[0].clearColor  = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
            rpd.colorAttachments[0].storeAction = .store
            guard let enc = cmdBuf.makeRenderCommandEncoder(descriptor: rpd) else {
                throw FlashGateError.encoderCreationFailed
            }
            enc.setRenderPipelineState(preset.pipelineState)
            enc.setFragmentBytes(&fv, length: MemoryLayout<FeatureVector>.size, index: 0)
            enc.setFragmentBuffer(fft,  offset: 0, index: 1)
            enc.setFragmentBuffer(wav,  offset: 0, index: 2)
            enc.setFragmentBuffer(stem, offset: 0, index: 3)
            if let sceneBuf = scene { enc.setFragmentBuffer(sceneBuf, offset: 0, index: 4) }
            enc.setFragmentBuffer(hist, offset: 0, index: 5)
            enc.setFragmentBuffer(slot, offset: 0, index: 6)
            enc.setFragmentBuffer(slot, offset: 0, index: 7)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            enc.endEncoding()
            cmdBuf.commit()
            cmdBuf.waitUntilCompleted()
            guard cmdBuf.status == .completed else { throw FlashGateError.renderFailed }
            texture.getBytes(&pixels, bytesPerRow: size * 4,
                             from: MTLRegionMake2D(0, 0, size, size), mipmapLevel: 0)
            luma.append(meanRelativeLuminance(pixels))
        }
        return luma
    }

    /// Mean WCAG relative luminance (linear-light, Rec. 709) of a BGRA buffer.
    /// Per-pixel sRGB → linear via a 256-entry LUT (linearise then average — the
    /// correct order for luminance, unlike a gamma-encoded mean).
    private func meanRelativeLuminance(_ bgra: [UInt8]) -> Double {
        let pixelCount = bgra.count / 4
        guard pixelCount > 0 else { return 0 }
        var sum = 0.0
        var i = 0
        while i < bgra.count {
            let bLin = Self.srgbToLinear[Int(bgra[i])]
            let gLin = Self.srgbToLinear[Int(bgra[i + 1])]
            let rLin = Self.srgbToLinear[Int(bgra[i + 2])]
            sum += 0.2126 * rLin + 0.7152 * gLin + 0.0722 * bLin
            i += 4
        }
        return sum / Double(pixelCount)
    }

    /// sRGB byte (0…255) → linear relative-luminance component (0…1).
    private static let srgbToLinear: [Double] = (0..<256).map { byte in
        let c = Double(byte) / 255.0
        return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    private enum FlashGateError: Error {
        case textureAllocationFailed
        case bufferAllocationFailed
        case commandBufferFailed
        case encoderCreationFailed
        case renderFailed
    }
}
