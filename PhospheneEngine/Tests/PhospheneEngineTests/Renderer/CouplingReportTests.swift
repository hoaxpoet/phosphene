// CouplingReportTests — QG.3 audio-visual coupling REPORT (report-first, no gate).
//
// The question this answers: does a preset's per-frame VISUAL change track the
// audio ENERGY envelope? A preset whose visual delta is uncorrelated with energy
// is dead-coupled — the motion is not driven by the music. This suite MEASURES
// that (cross-correlation of visual delta vs. energy) and PRINTS a table. It does
// NOT gate: verdicts on this uncalibrated proxy are forbidden until the baseline
// distribution across certified presets is known (QG.3.1). Low coupling here means
// "coupling not measured as present," never "preset is bad" — the M7 seat judges
// feel (manual-validation rule stands).
//
// Method (per certified, non-mesh preset × canonical fixture):
//   1. Reconstruct a per-frame FeatureVector + StemFeatures from the checked-in
//      route_coverage fixture (real preview clip through the production separation
//      + analysis chain — FA #27, nothing hand-authored).
//   2. Render each frame headlessly at 64×64 via the PresetRegressionTests harness
//      (same single-fragment path + zeroed aux state; see LIMITATIONS below).
//   3. visual_delta[i] = mean |luma(frame i) − luma(frame i−1)| over the 64×64
//      reduced-resolution frame (0..1). Write coupling/<preset>_<fixture>_visual_delta.csv.
//   4. Cross-correlate visual_delta vs. composite energy (mean of bass/mid/treble)
//      and each band, at lags 0–500 ms. Report peak Pearson r + lag, and a
//      stationarity note (r over sliding 10 s windows: min/median/max).
//   5. Negative control: fixture A's energy vs. fixture B's rendered frames — its
//      r bounds the noise floor (real audio mismatched to real frames — FA #27).
//
// LIMITATIONS (why this is REPORT-only): the offline harness renders ONE fragment
// with zeroed aux state (slot-6 CPU accumulators, feedback history texture, mv_warp
// marks buffer). Presets whose music response lives in that state (Nimbus, the
// mv_warp painters, the feedback/particle presets) render near-static offline and
// sit at the noise floor BY CONSTRUCTION — not because they are dead-coupled. The
// baseline doc (QG3_COUPLING_BASELINE) disambiguates by preset architecture before
// any KNOWN_ISSUES entry. Faithful measurement is limited to presets whose primary
// fragment reads FeatureVector/StemFeatures directly (ray-march presets).
//
// Gated behind PHOSPHENE_COUPLING=1 — the sweep renders ~50k frames. The normal
// battery skips fast (green); the baseline run sets the env. FidelityRubricReport-
// Tests is the diagnostic-report pattern this follows (no content assertions).

import Testing
import Foundation
import Metal
import Accelerate
@testable import Renderer
@testable import Presets
@testable import PresetSessionReplay
@testable import Shared

// swiftlint:disable identifier_name

@Suite("Coupling Report (QG.3)")
struct CouplingReportTests {

    static let fixtureTracks = ["love_rehab", "so_what", "there_there"]
    static let renderSize = 64
    static let maxLagMs: Double = 500
    static let windowSeconds: Double = 10
    // Negative control: this fixture's energy vs. the other's frames.
    static let controlEnergyFixture = "love_rehab"
    static let controlFrameFixture = "so_what"

    @Test("Audio-visual coupling report — certified presets × canonical fixtures (QG.3)")
    func couplingReport() throws {
        guard ProcessInfo.processInfo.environment["PHOSPHENE_COUPLING"] == "1" else {
            print("CouplingReportTests: gated — set PHOSPHENE_COUPLING=1 to run the render sweep "
                  + "(~50k headless frames). See docs/diagnostics/QG3_COUPLING_BASELINE.md for the baseline.")
            return
        }

        // Load every fixture once (per-frame FV + SF + energy/time series).
        var fixtures: [String: Fixture] = [:]
        for name in Self.fixtureTracks {
            fixtures[name] = try Self.loadFixture(name)
        }

        let outDir = Self.outputDirectory()
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        let ctx = try MetalContext()
        let certified = _acceptanceFixture.presets
            .filter { $0.descriptor.certified }
            .sorted { $0.descriptor.name < $1.descriptor.name }

        print("\n=== QG.3 COUPLING REPORT ===")
        print("lags 0–\(Int(Self.maxLagMs))ms · sliding \(Int(Self.windowSeconds))s windows · composite energy = mean(bass,mid,treble)")
        print("row: preset | fixture | comp_r@lag_ms | bass_r | mid_r | treb_r | win[min/med/max] | delta_mean")

        for preset in certified {
            if preset.descriptor.passes.contains(.meshShader) {
                print("SKIP | \(preset.descriptor.name) | meshShader — not renderable via drawPrimitives")
                continue
            }
            var perFixtureDelta: [String: [Float]] = [:]

            for name in Self.fixtureTracks {
                guard let fx = fixtures[name] else { continue }
                let delta = try Self.visualDeltas(preset: preset, fixture: fx, ctx: ctx)
                perFixtureDelta[name] = delta
                Self.writeDeltaCSV(preset: preset.descriptor.name, fixture: name,
                                   delta: delta, fixtureData: fx, dir: outDir)

                // Align energy to delta: delta[i] is the change INTO frame i+1, so
                // pair it with the audio at frame i+1.
                let comp = Array(fx.composite.dropFirst())
                let bass = Array(fx.bass.dropFirst())
                let mid = Array(fx.mid.dropFirst())
                let treb = Array(fx.treble.dropFirst())
                let maxLag = fx.frames(forMs: Self.maxLagMs)
                let win = fx.frames(forSeconds: Self.windowSeconds)

                let c = Self.crossCorr(delta: delta, energy: comp, maxLagFrames: maxLag)
                let b = Self.crossCorr(delta: delta, energy: bass, maxLagFrames: maxLag)
                let m = Self.crossCorr(delta: delta, energy: mid, maxLagFrames: maxLag)
                let t = Self.crossCorr(delta: delta, energy: treb, maxLagFrames: maxLag)
                let station = Self.stationarity(delta: delta, energy: comp,
                                                lag: c.lag, windowFrames: win)
                let dMean = delta.isEmpty ? 0 : delta.reduce(0, +) / Float(delta.count)

                print("ROW | \(preset.descriptor.name) | \(name) | "
                      + "\(f2(c.r))@\(Int(fx.msFor(frames: c.lag)))ms | "
                      + "\(f2(b.r)) | \(f2(m.r)) | \(f2(t.r)) | "
                      + "[\(f2(station.min))/\(f2(station.median))/\(f2(station.max))] | "
                      + "\(f4(dMean))")
            }

            // Negative control: mismatched audio × frames.
            if let df = perFixtureDelta[Self.controlFrameFixture],
               let ef = fixtures[Self.controlEnergyFixture] {
                let comp = Array(ef.composite.dropFirst())
                let maxLag = ef.frames(forMs: Self.maxLagMs)
                let c = Self.crossCorr(delta: df, energy: comp, maxLagFrames: maxLag)
                print("CONTROL | \(preset.descriptor.name) | "
                      + "\(Self.controlEnergyFixture)-audio×\(Self.controlFrameFixture)-frames | "
                      + "comp_r=\(f2(c.r)) (noise floor)")
            }
        }
        print("=== END COUPLING REPORT ===\n")
    }

    // MARK: - Fixture reconstruction

    struct Fixture {
        let name: String
        let features: [FeatureVector]
        let stems: [StemFeatures]
        let bass: [Float]
        let mid: [Float]
        let treble: [Float]
        let composite: [Float]
        let times: [Float]
        let medianDeltaTime: Float

        func frames(forMs ms: Double) -> Int {
            max(1, Int((ms / 1000.0 / Double(medianDeltaTime)).rounded()))
        }
        func frames(forSeconds s: Double) -> Int {
            max(2, Int((s / Double(medianDeltaTime)).rounded()))
        }
        func msFor(frames n: Int) -> Double { Double(n) * Double(medianDeltaTime) * 1000.0 }
    }

    static func loadFixture(_ name: String) throws -> Fixture {
        let base = try #require(
            Bundle.module.url(forResource: "route_coverage", withExtension: nil),
            "route_coverage fixtures not bundled")
        let dir = base.appendingPathComponent(name)
        let cols = try SessionColumnSeries.load(directory: dir)

        func series(_ col: String) -> [Float] {
            (cols.floatSeries(col) ?? []).map { $0 ?? 0 }
        }
        let n = cols.frameCount
        let bass = series("bass"), mid = series("mid"), treble = series("treble")
        let composite = (0..<n).map { i in (bass[i] + mid[i] + treble[i]) / 3 }
        let times = series("time")

        // Median deltaTime — robust to the occasional stall frame.
        let dts = series("deltaTime").filter { $0 > 0 }.sorted()
        let medDt = dts.isEmpty ? 0.0166 : dts[dts.count / 2]

        // Per-frame FeatureVector — every field the fragments read for reactivity.
        let subBass = series("subBass"), lowBass = series("lowBass"), lowMid = series("lowMid")
        let midHigh = series("midHigh"), highMid = series("highMid"), high = series("high")
        let beatBass = series("beatBass"), beatMid = series("beatMid")
        let beatTreble = series("beatTreble"), beatComposite = series("beatComposite")
        let centroid = series("spectralCentroid"), flux = series("spectralFlux")
        let valence = series("valence"), arousal = series("arousal")
        let accum = series("accumulatedAudioTime")
        let bassAtt = series("bass_att"), midAtt = series("mid_att"), trebAtt = series("treble_att")
        let bassRel = series("bassRel"), bassDev = series("bassDev"), bassAttRel = series("bassAttRel")
        let midRel = series("mid_rel"), midDev = series("mid_dev")
        let trebRel = series("treb_rel"), trebDev = series("treb_dev")
        let midAttRel = series("mid_att_rel"), trebAttRel = series("treb_att_rel")
        let beatPhase = series("beatPhase01"), beatsUntil = series("beats_until_next")
        let barPermille = series("barPhase01_permille"), beatsPerBar = series("beatsPerBar")
        let trackElapsed = series("track_elapsed_s")
        let pPhase = series("pulse_phase01"), pAmp = series("pulse_amp01")
        let pIdx = series("pulse_beat_index"), pBlend = series("pulse_regional_blend01")
        let tFifths = series("tonal_phase_fifths"), tThirds = series("tonal_phase_thirds")
        let tCons = series("tonal_consonance"), tTens = series("tonal_tension")
        let hFlux = series("harmonic_flux")

        var features: [FeatureVector] = []
        features.reserveCapacity(n)
        for i in 0..<n {
            var fv = FeatureVector(
                bass: bass[i], mid: mid[i], treble: treble[i],
                bassAtt: bassAtt[i], midAtt: midAtt[i], trebleAtt: trebAtt[i],
                subBass: subBass[i], lowBass: lowBass[i], lowMid: lowMid[i],
                midHigh: midHigh[i], highMid: highMid[i], high: high[i],
                beatBass: beatBass[i], beatMid: beatMid[i], beatTreble: beatTreble[i],
                beatComposite: beatComposite[i],
                spectralCentroid: centroid[i], spectralFlux: flux[i],
                valence: valence[i], arousal: arousal[i],
                time: times[i], deltaTime: medDt,
                accumulatedAudioTime: accum[i])
            fv.bassRel = bassRel[i]; fv.bassDev = bassDev[i]; fv.bassAttRel = bassAttRel[i]
            fv.midRel = midRel[i]; fv.midDev = midDev[i]
            fv.trebRel = trebRel[i]; fv.trebDev = trebDev[i]
            fv.midAttRel = midAttRel[i]; fv.trebAttRel = trebAttRel[i]
            fv.beatPhase01 = beatPhase[i]; fv.beatsUntilNext = beatsUntil[i]
            fv.barPhase01 = barPermille[i] / 1000; fv.beatsPerBar = max(1, beatsPerBar[i])
            fv.trackElapsedS = trackElapsed[i]
            fv.pulsePhase01 = pPhase[i]; fv.pulseAmp01 = pAmp[i]
            fv.pulseBeatIndex = pIdx[i]; fv.pulseRegionalBlend01 = pBlend[i]
            fv.tonalPhaseFifths = tFifths[i]; fv.tonalPhaseThirds = tThirds[i]
            fv.tonalConsonance = tCons[i]; fv.tonalTension = tTens[i]; fv.harmonicFlux = hFlux[i]
            features.append(fv)
        }

        // Per-frame StemFeatures — bound at slot 3 so stem-routed presets respond.
        func sfSeries(_ col: String) -> [Float] { series(col) }
        let stems = try Self.reconstructStems(count: n, series: sfSeries)

        return Fixture(name: name, features: features, stems: stems,
                       bass: bass, mid: mid, treble: treble, composite: composite,
                       times: times, medianDeltaTime: medDt)
    }

    static func reconstructStems(count n: Int, series: (String) -> [Float]) throws -> [StemFeatures] {
        let cols: [(String, WritableKeyPath<StemFeatures, Float>)] = [
            ("vocalsEnergy", \.vocalsEnergy), ("vocalsBand0", \.vocalsBand0),
            ("vocalsBand1", \.vocalsBand1), ("vocalsBeat", \.vocalsBeat),
            ("drumsEnergy", \.drumsEnergy), ("drumsBand0", \.drumsBand0),
            ("drumsBand1", \.drumsBand1), ("drumsBeat", \.drumsBeat),
            ("bassEnergy", \.bassEnergy), ("bassBand0", \.bassBand0),
            ("bassBand1", \.bassBand1), ("bassBeat", \.bassBeat),
            ("otherEnergy", \.otherEnergy), ("otherBand0", \.otherBand0),
            ("otherBand1", \.otherBand1), ("otherBeat", \.otherBeat),
            ("vocalsEnergyRel", \.vocalsEnergyRel), ("vocalsEnergyDev", \.vocalsEnergyDev),
            ("drumsEnergyRel", \.drumsEnergyRel), ("drumsEnergyDev", \.drumsEnergyDev),
            ("bassEnergyRel", \.bassEnergyRel), ("bassEnergyDev", \.bassEnergyDev),
            ("otherEnergyRel", \.otherEnergyRel), ("otherEnergyDev", \.otherEnergyDev),
            ("vocalsOnsetRate", \.vocalsOnsetRate), ("vocalsCentroid", \.vocalsCentroid),
            ("vocalsAttackRatio", \.vocalsAttackRatio), ("vocalsEnergySlope", \.vocalsEnergySlope),
            ("drumsOnsetRate", \.drumsOnsetRate), ("drumsCentroid", \.drumsCentroid),
            ("drumsAttackRatio", \.drumsAttackRatio), ("drumsEnergySlope", \.drumsEnergySlope),
            ("bassOnsetRate", \.bassOnsetRate), ("bassCentroid", \.bassCentroid),
            ("bassAttackRatio", \.bassAttackRatio), ("bassEnergySlope", \.bassEnergySlope),
            ("otherOnsetRate", \.otherOnsetRate), ("otherCentroid", \.otherCentroid),
            ("otherAttackRatio", \.otherAttackRatio), ("otherEnergySlope", \.otherEnergySlope),
            ("vocalsPitchHz", \.vocalsPitchHz), ("vocalsPitchConfidence", \.vocalsPitchConfidence),
            ("stringsActivity", \.stringsActivity), ("stringsActivityDev", \.stringsActivityDev),
            ("brassActivity", \.brassActivity), ("brassActivityDev", \.brassActivityDev),
            ("woodwindsActivity", \.woodwindsActivity), ("woodwindsActivityDev", \.woodwindsActivityDev),
            ("percussionActivity", \.percussionActivity), ("percussionActivityDev", \.percussionActivityDev)
        ]
        let loaded = cols.map { ($0.1, series($0.0)) }
        var out: [StemFeatures] = []
        out.reserveCapacity(n)
        for i in 0..<n {
            var sf = StemFeatures()
            for (kp, s) in loaded where i < s.count { sf[keyPath: kp] = s[i] }
            out.append(sf)
        }
        return out
    }

    // MARK: - Rendering + visual delta

    static func visualDeltas(preset: PresetLoader.LoadedPreset,
                             fixture fx: Fixture, ctx: MetalContext) throws -> [Float] {
        let size = renderSize
        let texDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: ctx.pixelFormat, width: size, height: size, mipmapped: false)
        texDesc.usage = [.renderTarget, .shaderRead]
        texDesc.storageMode = .shared
        guard let texture = ctx.device.makeTexture(descriptor: texDesc) else {
            throw CouplingError.textureAllocationFailed
        }

        // Aux buffers allocated once, reused across frames.
        let floatStride = MemoryLayout<Float>.stride
        guard
            let fft = ctx.makeSharedBuffer(length: 512 * floatStride),
            let wav = ctx.makeSharedBuffer(length: 2048 * floatStride),
            let stemBuf = ctx.makeSharedBuffer(length: MemoryLayout<StemFeatures>.stride),
            let hist = ctx.makeSharedBuffer(length: 4096 * floatStride)
        else { throw CouplingError.bufferAllocationFailed }
        _ = fft.contents().initializeMemory(as: UInt8.self, repeating: 0, count: 512 * floatStride)
        _ = wav.contents().initializeMemory(as: UInt8.self, repeating: 0, count: 2048 * floatStride)
        _ = hist.contents().initializeMemory(as: UInt8.self, repeating: 0, count: 4096 * floatStride)

        var scene: MTLBuffer?
        if preset.descriptor.passes.contains(.rayMarch),
           let buf = ctx.makeSharedBuffer(length: MemoryLayout<SceneUniforms>.stride) {
            var su = preset.descriptor.makeSceneUniforms()
            buf.contents().copyMemory(from: &su, byteCount: MemoryLayout<SceneUniforms>.stride)
            scene = buf
        }
        // Slot-6 / slot-8 state buffers: bind zeroed so the pipeline never reads
        // undefined (matches PresetRegressionTests). Real state can't be reconstructed
        // offline — the documented LIMITATION.
        var aux6: MTLBuffer?
        if preset.descriptor.name == "Nimbus" {
            aux6 = ctx.makeSharedBuffer(length: MemoryLayout<NimbusStateGPU>.stride)
            _ = aux6?.contents().initializeMemory(as: UInt8.self, repeating: 0,
                                                  count: MemoryLayout<NimbusStateGPU>.stride)
        }
        var aux8: MTLBuffer?
        if preset.descriptor.name == "Lumen Mosaic" {
            aux8 = ctx.makeSharedBuffer(length: MemoryLayout<LumenPatternState>.stride)
            _ = aux8?.contents().initializeMemory(as: UInt8.self, repeating: 0,
                                                  count: MemoryLayout<LumenPatternState>.stride)
        }

        var deltas: [Float] = []
        deltas.reserveCapacity(fx.features.count)
        var prevLuma: [Float]?
        let stemStride = MemoryLayout<StemFeatures>.stride

        for i in 0..<fx.features.count {
            var fv = fx.features[i]
            var sf = fx.stems[i]
            withUnsafeBytes(of: &sf) { stemBuf.contents().copyMemory(from: $0.baseAddress!, byteCount: stemStride) }

            guard let cmd = ctx.commandQueue.makeCommandBuffer() else { throw CouplingError.commandBufferFailed }
            let rpd = MTLRenderPassDescriptor()
            rpd.colorAttachments[0].texture = texture
            rpd.colorAttachments[0].loadAction = .clear
            rpd.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
            rpd.colorAttachments[0].storeAction = .store
            guard let enc = cmd.makeRenderCommandEncoder(descriptor: rpd) else {
                throw CouplingError.encoderCreationFailed
            }
            enc.setRenderPipelineState(preset.pipelineState)
            enc.setFragmentBytes(&fv, length: MemoryLayout<FeatureVector>.stride, index: 0)
            enc.setFragmentBuffer(fft, offset: 0, index: 1)
            enc.setFragmentBuffer(wav, offset: 0, index: 2)
            enc.setFragmentBuffer(stemBuf, offset: 0, index: 3)
            if let scene { enc.setFragmentBuffer(scene, offset: 0, index: 4) }
            enc.setFragmentBuffer(hist, offset: 0, index: 5)
            if let aux6 { enc.setFragmentBuffer(aux6, offset: 0, index: 6) }
            if let aux8 { enc.setFragmentBuffer(aux8, offset: 0, index: 8) }
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            enc.endEncoding()
            cmd.commit()
            cmd.waitUntilCompleted()
            guard cmd.status == .completed else { throw CouplingError.renderFailed }

            var pixels = [UInt8](repeating: 0, count: size * size * 4)
            texture.getBytes(&pixels, bytesPerRow: size * 4,
                             from: MTLRegionMake2D(0, 0, size, size), mipmapLevel: 0)
            let luma = lumaField(pixels)
            if let prev = prevLuma {
                var acc: Float = 0
                for p in 0..<luma.count { acc += abs(luma[p] - prev[p]) }
                deltas.append(acc / Float(luma.count) / 255)   // normalize to 0..1
            }
            prevLuma = luma
        }
        return deltas
    }

    /// Per-pixel luma (BGRA: 0.114·B + 0.587·G + 0.299·R), 0..255.
    static func lumaField(_ pixels: [UInt8]) -> [Float] {
        var out = [Float](repeating: 0, count: pixels.count / 4)
        for p in 0..<out.count {
            let idx = p * 4
            out[p] = 0.114 * Float(pixels[idx]) + 0.587 * Float(pixels[idx + 1]) + 0.299 * Float(pixels[idx + 2])
        }
        return out
    }

    // MARK: - Correlation (Accelerate)

    /// Pearson r; 0 when either input has ~zero variance (correct edge case).
    static func pearson(_ a: [Float], _ b: [Float]) -> Float {
        let n = min(a.count, b.count)
        guard n > 1 else { return 0 }
        let x = Array(a[0..<n]), y = Array(b[0..<n])
        var mx: Float = 0, my: Float = 0
        vDSP_meanv(x, 1, &mx, vDSP_Length(n))
        vDSP_meanv(y, 1, &my, vDSP_Length(n))
        let xc = x.map { $0 - mx }, yc = y.map { $0 - my }
        var sxy: Float = 0, sxx: Float = 0, syy: Float = 0
        vDSP_dotpr(xc, 1, yc, 1, &sxy, vDSP_Length(n))
        vDSP_dotpr(xc, 1, xc, 1, &sxx, vDSP_Length(n))
        vDSP_dotpr(yc, 1, yc, 1, &syy, vDSP_Length(n))
        let denom = (sxx * syy).squareRoot()
        return denom > 1e-9 ? sxy / denom : 0
    }

    /// Peak Pearson r over energy-leads-visual lags 0…maxLagFrames (signed peak).
    static func crossCorr(delta: [Float], energy: [Float], maxLagFrames: Int) -> (r: Float, lag: Int) {
        let m = min(delta.count, energy.count)
        guard m > 2 else { return (0, 0) }
        var bestR = -Float.greatestFiniteMagnitude
        var bestLag = 0
        for lag in 0...min(maxLagFrames, m - 2) {
            let d = Array(delta[lag..<m])
            let e = Array(energy[0..<(m - lag)])
            let r = pearson(d, e)
            if r > bestR { bestR = r; bestLag = lag }
        }
        return (bestR == -Float.greatestFiniteMagnitude ? 0 : bestR, bestLag)
    }

    /// r within each non-overlapping window (at the peak lag) → min/median/max.
    static func stationarity(delta: [Float], energy: [Float], lag: Int, windowFrames: Int)
        -> (min: Float, median: Float, max: Float) {
        let m = min(delta.count, energy.count) - lag
        guard m > windowFrames, windowFrames > 1 else { return (0, 0, 0) }
        let d = Array(delta[lag..<(lag + m)])
        let e = Array(energy[0..<m])
        var rs: [Float] = []
        var start = 0
        while start + windowFrames <= m {
            rs.append(pearson(Array(d[start..<start + windowFrames]),
                              Array(e[start..<start + windowFrames])))
            start += windowFrames
        }
        guard !rs.isEmpty else { return (0, 0, 0) }
        let sorted = rs.sorted()
        return (sorted.first!, sorted[sorted.count / 2], sorted.last!)
    }

    // MARK: - CSV output

    static func outputDirectory() -> URL {
        if let override = ProcessInfo.processInfo.environment["PHOSPHENE_COUPLING_DIR"] {
            return URL(fileURLWithPath: override)
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("coupling")
    }

    static func writeDeltaCSV(preset: String, fixture: String, delta: [Float],
                              fixtureData fx: Fixture, dir: URL) {
        let slug = preset.lowercased().replacingOccurrences(of: " ", with: "_")
        var text = "frame,time,visual_delta\n"
        for (i, d) in delta.enumerated() {
            // delta[i] is the change into frame i+1.
            let f = i + 1
            let t = f < fx.times.count ? fx.times[f] : 0
            text += "\(f),\(t),\(d)\n"
        }
        let url = dir.appendingPathComponent("\(slug)_\(fixture)_visual_delta.csv")
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - Formatting

    private func f2(_ x: Float) -> String { String(format: "%+.2f", x) }
    private func f4(_ x: Float) -> String { String(format: "%.5f", x) }
}

private enum CouplingError: Error {
    case textureAllocationFailed
    case bufferAllocationFailed
    case commandBufferFailed
    case encoderCreationFailed
    case renderFailed
}

// swiftlint:enable identifier_name
