// CouplingReportTests — QG.3 audio-visual coupling REPORT (report-first, no gate).
//
// The question this answers: does a preset's per-frame VISUAL change track the
// audio ENERGY envelope? A preset whose visual delta is uncorrelated with energy
// is dead-coupled — the motion is not driven by the music. This suite MEASURES
// that (cross-correlation of visual delta vs. energy) and PRINTS a table. It does
// NOT gate: verdicts on this uncalibrated proxy are forbidden. Low coupling here means
// "coupling not measured as present," never "preset is bad" — the M7 seat judges
// feel (manual-validation rule stands). The gate flip (QG.3.2) is Matt's call, taken
// against the QG.3.1 distribution (docs/diagnostics/QG3_COUPLING_BASELINE.md).
//
// Method (per certified, non-mesh preset × canonical fixture):
//   1. Reconstruct a per-frame FeatureVector + StemFeatures from the checked-in
//      route_coverage fixture (real preview clip through the production separation
//      + analysis chain — FA #27, nothing hand-authored).
//   2. Render each frame headlessly through the preset's REAL path (QG.3.1): the 10
//      multi-pass / feedback / follower presets via the shared `MultiPassRenderHarness`
//      (feedback persistence — the same seam the flash-safety gate drives), the 3
//      single-pass presets (Ferrofluid Ocean, Murmuration, Nimbus) via one fragment
//      + the Nimbus CPU follower. This replaced the QG.3 single-fragment/zeroed-state
//      harness that rendered 11/13 presets static.
//   3. visual_delta[i] = mean |luma(frame i) − luma(frame i−1)| over a downsampled
//      luma field (0..1). Write coupling/<preset>_<fixture>_visual_delta.csv.
//   4. Cross-correlate visual_delta vs. composite energy (mean of bass/mid/treble)
//      and each band, at lags 0–500 ms. Report peak Pearson r + lag, and a
//      stationarity note (r over sliding 10 s windows: min/median/max).
//   5. Negative control: fixture A's energy vs. fixture B's rendered frames — its
//      r bounds the PER-PRESET noise floor (real audio mismatched to real frames —
//      FA #27). Feedback presets have higher floors (frame autocorrelation), so the
//      floor is per-preset, not global.
//
// PROXY-VALIDITY CAVEAT (why this stays a report): the metric correlates visual
// *delta* (motion magnitude) with energy *level*. A preset that couples via subtle
// camera motion (Nacre's downbeat push) or whose faithful render needs passes we
// approximate can legitimately read low. Low r ⇒ "not measured as present," never a
// defect. Disambiguation + calibration live in the baseline doc.
//
// Gated behind PHOSPHENE_COUPLING=1 — the sweep renders the full real multi-pass
// stack (~130 s). The normal battery skips fast (green); the baseline run sets the
// env. FidelityRubricReportTests is the diagnostic-report pattern this follows.

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
@MainActor
struct CouplingReportTests {

    static let fixtureTracks = ["love_rehab", "so_what", "there_there"]
    static let renderSize = 64
    static let maxLagMs: Double = 500
    static let windowSeconds: Double = 10
    // Negative control: this fixture's energy vs. the other's frames.
    static let controlEnergyFixture = "love_rehab"
    static let controlFrameFixture = "so_what"

    // QG.3.2 WARNING-tier thresholds (Matt's call — a review flag, never a cert gate,
    // D-186). A preset is flagged "review" when its best-fixture peak composite r fails
    // BOTH: (1) an absolute floor, and (2) clearing its own per-preset noise control by a
    // margin. Both must fail, so a preset that clears its (high) feedback control still
    // passes even below the absolute floor, and vice versa. Deliberately conservative:
    // low r is "coupling not measured as present," never "preset is bad" — the M7 seat
    // is the authority, and two certified presets (Nacre, Ferrofluid Ocean) read weak for
    // proxy/render-fidelity reasons. Do NOT convert this into a #expect assertion.
    static let warnFloor: Float = 0.15
    static let warnControlMargin: Float = 0.10

    @Test("Audio-visual coupling report — certified presets × canonical fixtures (QG.3)")
    func couplingReport() throws {
        guard ProcessInfo.processInfo.environment["PHOSPHENE_COUPLING"] == "1" else {
            print("CouplingReportTests: gated — set PHOSPHENE_COUPLING=1 to run the real multi-pass "
                  + "render sweep (~130 s). See docs/diagnostics/QG3_COUPLING_BASELINE.md for the baseline.")
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

        var verdicts: [(name: String, bestR: Float, control: Float)] = []

        for preset in certified {
            if preset.descriptor.passes.contains(.meshShader) {
                print("SKIP | \(preset.descriptor.name) | meshShader — not renderable via drawPrimitives")
                continue
            }
            var perFixtureDelta: [String: [Float]] = [:]
            var bestR = -Float.greatestFiniteMagnitude

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
                bestR = max(bestR, c.r)

                print("ROW | \(preset.descriptor.name) | \(name) | "
                      + "\(f2(c.r))@\(Int(fx.msFor(frames: c.lag)))ms | "
                      + "\(f2(b.r)) | \(f2(m.r)) | \(f2(t.r)) | "
                      + "[\(f2(station.min))/\(f2(station.median))/\(f2(station.max))] | "
                      + "\(f4(dMean))")
            }

            // Negative control: mismatched audio × frames — the per-preset noise floor.
            var control: Float = 0
            if let df = perFixtureDelta[Self.controlFrameFixture],
               let ef = fixtures[Self.controlEnergyFixture] {
                let comp = Array(ef.composite.dropFirst())
                let maxLag = ef.frames(forMs: Self.maxLagMs)
                control = Self.crossCorr(delta: df, energy: comp, maxLagFrames: maxLag).r
                print("CONTROL | \(preset.descriptor.name) | "
                      + "\(Self.controlEnergyFixture)-audio×\(Self.controlFrameFixture)-frames | "
                      + "comp_r=\(f2(control)) (noise floor)")
            }
            verdicts.append((preset.descriptor.name, bestR == -Float.greatestFiniteMagnitude ? 0 : bestR, control))
        }
        print("=== END COUPLING REPORT ===\n")

        Self.printVerdicts(verdicts)
    }

    /// Standing coverage of the QG.3.2 warning-tier boundary (no GPU/env — runs in the
    /// normal battery). Locks the "both conditions must fail" rule so the flag can't
    /// silently become an absolute-floor-only gate that false-reds feedback presets.
    @Test("QG.3.2 warning-tier predicate boundaries")
    func reviewPredicateBoundaries() {
        // Below floor AND within margin of its own (low) control → REVIEW.
        #expect(Self.isReview(bestR: 0.05, control: -0.02))   // Nacre-like
        #expect(Self.isReview(bestR: 0.08, control: 0.08))    // Ferrofluid-like, at floor
        #expect(Self.isReview(bestR: 0.10, control: 0.05))
        // Clears the absolute floor → ok, even with a high feedback control.
        #expect(!Self.isReview(bestR: 0.20, control: 0.05))
        #expect(!Self.isReview(bestR: 0.47, control: 0.13))   // Dragon Bloom
        // Below the absolute floor BUT clears its own control by the margin → ok
        // (the feedback-preset escape hatch — high autocorrelation floor).
        #expect(!Self.isReview(bestR: 0.14, control: 0.02))
    }

    // MARK: - QG.3.2 warning-tier verdict (report-only, never a cert gate)

    /// Print the per-preset warning-tier verdict. `REVIEW` = best-fixture peak composite r
    /// is below the absolute floor AND fails to clear its own noise control by the margin
    /// → "coupling not measured as present." This is a REVIEW FLAG surfaced for the reader,
    /// NOT a certification failure (D-186): the M7 seat judges felt coupling, and a low r
    /// can be a proxy artifact (subtle camera-motion coupling, approximated render).
    static func printVerdicts(_ verdicts: [(name: String, bestR: Float, control: Float)]) {
        let flagged = verdicts.filter { isReview(bestR: $0.bestR, control: $0.control) }
        print("=== QG.3.2 COUPLING VERDICT (warning tier — review flag, NOT a cert gate) ===")
        print("rule: REVIEW if best-fixture peak r < \(f2s(warnFloor)) AND < control + \(f2s(warnControlMargin))")
        for v in verdicts.sorted(by: { $0.bestR > $1.bestR }) {
            let review = isReview(bestR: v.bestR, control: v.control)
            print("VERDICT | \(review ? "REVIEW " : "ok     ") | \(v.name) | "
                  + "best_r=\(f2s(v.bestR)) control=\(f2s(v.control))"
                  + (review ? " → coupling not measured as present" : ""))
        }
        print("VERDICT SUMMARY | \(flagged.count) flagged for review / \(verdicts.count) measured "
              + "— review flags inform, they do NOT fail certification (M7 seat is the authority)")
        print("=== END VERDICT ===\n")
    }

    /// The warning-tier predicate. Both conditions must hold to flag (see `warnFloor`).
    static func isReview(bestR: Float, control: Float) -> Bool {
        bestR < warnFloor && bestR < control + warnControlMargin
    }

    private static func f2s(_ x: Float) -> String { String(format: "%+.2f", x) }

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

    /// Per-frame visual delta for a preset over a fixture. Dispatches to the FAITHFUL
    /// render path: the 10 multi-pass / feedback / follower presets go through the shared
    /// `MultiPassRenderHarness` (real feedback chain, QG.3.1); the 3 single-pass presets
    /// (Ferrofluid Ocean, Murmuration, Nimbus) read their response in one fragment (+ the
    /// Nimbus CPU follower) and go through `singleFragmentFields`. Both reduce each frame to
    /// a downsampled luma field; delta = mean |field(i) − field(i−1)| (0..1).
    static func visualDeltas(preset: PresetLoader.LoadedPreset,
                             fixture fx: Fixture, ctx: MetalContext) throws -> [Float] {
        let fields: [[Float]]
        if MultiPassRenderHarness.multiPassPresets.contains(preset.descriptor.name) {
            let harness = MultiPassRenderHarness()   // 320×180, the flash-gate render size
            fields = try harness.render(preset: preset.descriptor.name,
                                        features: fx.features, stems: fx.stems) {
                downsampledLuma($0, srcW: 320, srcH: 180, cols: 32)
            }
        } else {
            fields = try singleFragmentFields(preset: preset, fx: fx, ctx: ctx)
        }
        return deltas(fields)
    }

    /// Single-fragment render (Ferrofluid Ocean, Murmuration, Nimbus). Mirrors
    /// `PhotosensitivityCertificationTests.renderLuminanceSequence`: binds fft/wav/stem/hist
    /// (+ scene for rayMarch), and for Nimbus ticks the real `NimbusState` CPU follower into
    /// slot 6 so its response isn't zeroed. Returns one downsampled luma field per frame.
    static func singleFragmentFields(preset: PresetLoader.LoadedPreset,
                                     fx: Fixture, ctx: MetalContext) throws -> [[Float]] {
        let size = renderSize
        let texDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: ctx.pixelFormat, width: size, height: size, mipmapped: false)
        texDesc.usage = [.renderTarget, .shaderRead]
        texDesc.storageMode = .shared
        guard let texture = ctx.device.makeTexture(descriptor: texDesc) else {
            throw CouplingError.textureAllocationFailed
        }
        let floatStride = MemoryLayout<Float>.stride
        guard
            let fft = ctx.makeSharedBuffer(length: 512 * floatStride),
            let wav = ctx.makeSharedBuffer(length: 2048 * floatStride),
            let stemBuf = ctx.makeSharedBuffer(length: MemoryLayout<StemFeatures>.stride),
            let hist = ctx.makeSharedBuffer(length: 4096 * floatStride),
            let slot = ctx.makeSharedBuffer(length: 1024)
        else { throw CouplingError.bufferAllocationFailed }
        _ = fft.contents().initializeMemory(as: UInt8.self, repeating: 0, count: 512 * floatStride)
        _ = wav.contents().initializeMemory(as: UInt8.self, repeating: 0, count: 2048 * floatStride)
        _ = hist.contents().initializeMemory(as: UInt8.self, repeating: 0, count: 4096 * floatStride)
        _ = slot.contents().initializeMemory(as: UInt8.self, repeating: 0, count: 1024)

        var scene: MTLBuffer?
        if preset.descriptor.passes.contains(.rayMarch),
           let buf = ctx.makeSharedBuffer(length: MemoryLayout<SceneUniforms>.stride) {
            var su = preset.descriptor.makeSceneUniforms()
            buf.contents().copyMemory(from: &su, byteCount: MemoryLayout<SceneUniforms>.stride)
            scene = buf
        }
        // Nimbus: tick the real CPU follower each frame and bind its live state at slot 6
        // (else the follower-driven body is static — the QG.3 zeroed-slot limitation).
        let nimbusState: NimbusState? =
            preset.descriptor.name == "Nimbus" ? NimbusState(device: ctx.device) : nil

        var fields: [[Float]] = []
        fields.reserveCapacity(fx.features.count)
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
            if let ns = nimbusState {
                ns.tick(deltaTime: fv.deltaTime, features: fv, stems: sf)
                enc.setFragmentBuffer(ns.stateBuffer, offset: 0, index: 6)
            } else {
                enc.setFragmentBuffer(slot, offset: 0, index: 6)
            }
            enc.setFragmentBuffer(slot, offset: 0, index: 7)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            enc.endEncoding()
            cmd.commit()
            cmd.waitUntilCompleted()
            guard cmd.status == .completed else { throw CouplingError.renderFailed }

            var pixels = [UInt8](repeating: 0, count: size * size * 4)
            texture.getBytes(&pixels, bytesPerRow: size * 4,
                             from: MTLRegionMake2D(0, 0, size, size), mipmapLevel: 0)
            fields.append(downsampledLuma(pixels, srcW: size, srcH: size, cols: 32))
        }
        return fields
    }

    /// Downsample a BGRA frame to a `cols × rows` luma grid (rows from aspect), 0..255.
    /// BGRA: luma = 0.114·B + 0.587·G + 0.299·R. Reduced resolution denoises the delta.
    static func downsampledLuma(_ bgra: [UInt8], srcW: Int, srcH: Int, cols: Int) -> [Float] {
        let rows = max(1, Int((Double(cols) * Double(srcH) / Double(srcW)).rounded()))
        var grid = [Float](repeating: 0, count: cols * rows)
        for row in 0..<rows {
            let y0 = row * srcH / rows, y1 = (row + 1) * srcH / rows
            for col in 0..<cols {
                let x0 = col * srcW / cols, x1 = (col + 1) * srcW / cols
                var sum: Float = 0, count = 0
                var y = y0
                while y < y1 {
                    var x = x0
                    while x < x1 {
                        let idx = (y * srcW + x) * 4
                        sum += 0.114 * Float(bgra[idx]) + 0.587 * Float(bgra[idx + 1]) + 0.299 * Float(bgra[idx + 2])
                        count += 1; x += 1
                    }
                    y += 1
                }
                grid[row * cols + col] = count > 0 ? sum / Float(count) : 0
            }
        }
        return grid
    }

    /// Per-frame visual delta series from consecutive luma fields: mean |Δ| / 255 (0..1).
    static func deltas(_ fields: [[Float]]) -> [Float] {
        guard fields.count > 1 else { return [] }
        var out: [Float] = []
        out.reserveCapacity(fields.count - 1)
        for i in 1..<fields.count {
            let a = fields[i], b = fields[i - 1]
            let n = min(a.count, b.count)
            guard n > 0 else { out.append(0); continue }
            var acc: Float = 0
            for p in 0..<n { acc += abs(a[p] - b[p]) }
            out.append(acc / Float(n) / 255)
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
