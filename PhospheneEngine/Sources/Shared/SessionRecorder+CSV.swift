import Foundation

/// One analysis-frame's per-subsystem timing breakdown, captured by
/// VisualizerEngine and read by `SessionRecorder.recordFrame` when writing
/// the next features.csv row. (PERF.1 — BUG-019 instrumentation.)
///
/// All fields are optional so the CSV writer can emit empty cells before
/// the first analysis-frame has fired (cold-start frames before the
/// analysis queue produces its first row).
public struct SubsystemTimingSnapshot: Sendable {
    public let mirPipelineMs: Float?
    public let stemAnalyzerMs: Float?
    public let beatDetectorMs: Float?
    public let pitchTrackerMs: Float?
    public let moodClassifierMs: Float?

    public init(
        mirPipelineMs: Float?,
        stemAnalyzerMs: Float?,
        beatDetectorMs: Float?,
        pitchTrackerMs: Float?,
        moodClassifierMs: Float?
    ) {
        self.mirPipelineMs = mirPipelineMs
        self.stemAnalyzerMs = stemAnalyzerMs
        self.beatDetectorMs = beatDetectorMs
        self.pitchTrackerMs = pitchTrackerMs
        self.moodClassifierMs = moodClassifierMs
    }

    public static let empty = SubsystemTimingSnapshot(
        mirPipelineMs: nil,
        stemAnalyzerMs: nil,
        beatDetectorMs: nil,
        pitchTrackerMs: nil,
        moodClassifierMs: nil
    )
}

/// Render-loop CPU breakdown for the next features.csv row. (PERF.2-render —
/// BUG-019 instrumentation.) Captured by `RenderPipeline.draw` in the command-
/// buffer completion handler, plumbed through `onRenderTimingObserved`.
///
/// Both fields are optional so cold-start frames (before the first render-loop
/// completion fires) emit empty cells, distinguishing "no measurement yet"
/// from "measured 0."
public struct RenderTimingSnapshot: Sendable {
    public let encodeCpuMs: Float?
    public let renderFrameCpuMs: Float?

    public init(encodeCpuMs: Float?, renderFrameCpuMs: Float?) {
        self.encodeCpuMs = encodeCpuMs
        self.renderFrameCpuMs = renderFrameCpuMs
    }

    public static let empty = RenderTimingSnapshot(encodeCpuMs: nil, renderFrameCpuMs: nil)
}

/// Ray-march per-pass timing breakdown. (PERF.2-pass — BUG-019 instrumentation.)
/// Captured inside `RayMarchPipeline.render(...)` and plumbed via
/// `RenderPipeline.onRayMarchPassTimingObserved`. All fields optional so frames
/// where the active preset doesn't take the ray-march path emit empty cells
/// (mv_warp, feedback, ICB, post-process-only paths all produce nil values).
public struct RayMarchPassTimingSnapshot: Sendable {
    public let gbufferPassMs: Float?
    public let lightingPassMs: Float?
    public let ssgiPassMs: Float?
    public let postProcessPassMs: Float?

    public init(
        gbufferPassMs: Float?,
        lightingPassMs: Float?,
        ssgiPassMs: Float?,
        postProcessPassMs: Float?
    ) {
        self.gbufferPassMs = gbufferPassMs
        self.lightingPassMs = lightingPassMs
        self.ssgiPassMs = ssgiPassMs
        self.postProcessPassMs = postProcessPassMs
    }

    public static let empty = RayMarchPassTimingSnapshot(
        gbufferPassMs: nil,
        lightingPassMs: nil,
        ssgiPassMs: nil,
        postProcessPassMs: nil
    )
}

extension SessionRecorder {

    // MARK: - CSV row formatting

    // swiftlint:disable multiline_arguments
    static func csvRow(features fv: FeatureVector, frame: Int, wallclock: CFAbsoluteTime) -> String {
        csvRow(features: fv, stems: .zero, beatSync: .zero, frame: frame, wallclock: wallclock,
               frameCPUms: nil, frameGPUms: nil, subsystem: .empty, renderTiming: .empty,
               rayMarchPass: .empty)
    }

    static func csvRow(
        features fv: FeatureVector,
        stems: StemFeatures,
        beatSync bs: BeatSyncSnapshot,
        frame: Int,
        wallclock: CFAbsoluteTime,
        frameCPUms: Float? = nil,
        frameGPUms: Float? = nil,
        subsystem: SubsystemTimingSnapshot = .empty,
        renderTiming: RenderTimingSnapshot = .empty,
        rayMarchPass: RayMarchPassTimingSnapshot = .empty,
        structure: StructuralPrediction = .none
    ) -> String {
        let base = String(format: "%d,%.4f,%.4f,%.4f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,"
                               + "%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,"
                               + "%.5f,%.5f,%.5f,%.5f",
                          frame, wallclock, fv.time, fv.deltaTime,
                          fv.bass, fv.mid, fv.treble,
                          fv.subBass, fv.lowBass, fv.lowMid, fv.midHigh, fv.highMid, fv.high,
                          fv.beatBass, fv.beatMid, fv.beatTreble, fv.beatComposite,
                          fv.spectralCentroid, fv.spectralFlux, fv.valence, fv.arousal,
                          fv.accumulatedAudioTime,
                          fv.beatPhase01, fv.bassRel, fv.bassDev, fv.bassAttRel)
        let sync = String(format: ",%d,%d,%d,%d,%d,%d,%.3f,%.4f,%.3f",
                          Int(bs.barPhase01 * 1000),  // barPhase01 as integer permille
                          bs.beatsPerBar,
                          bs.beatInBar,
                          bs.isDownbeat ? 1 : 0,
                          bs.sessionMode,
                          bs.lockState,
                          bs.gridBPM,
                          bs.playbackTimeS,
                          bs.driftMs)
        // DM.3a — frame_cpu_ms,frame_gpu_ms. Empty cells until the first
        // GPU completion handler fires (cold-start frames) or whenever
        // gpuMs is unavailable (cb.gpuEndTime <= cb.gpuStartTime).
        let cpu = frameCPUms.map { String(format: "%.4f", $0) } ?? ""
        let gpu = frameGPUms.map { String(format: "%.4f", $0) } ?? ""
        // CSP.3 — track_elapsed_s + cached_bass_proportion appended so the
        // FFO cold-start A/B is verifiable from artifacts. Both are 0 in
        // the default `csvRow(features:...)` overload (used in test harnesses
        // that don't have stems context).
        let elapsed = String(format: "%.4f", fv.trackElapsedS)
        let bassProp = String(format: "%.5f", stems.cachedBassProportion)
        let timing = ",\(cpu),\(gpu),\(elapsed),\(bassProp)"
        // PERF.1 — per-subsystem analysis-frame timing breakdown. Empty cells
        // until the first analysis-frame fires (cold-start frames before the
        // analysis queue produces its first row). Order matches the header in
        // `SessionRecorder.makeFileHandles`.
        let mirMs = subsystem.mirPipelineMs.map { String(format: "%.4f", $0) } ?? ""
        let stemMs = subsystem.stemAnalyzerMs.map { String(format: "%.4f", $0) } ?? ""
        let beatMs = subsystem.beatDetectorMs.map { String(format: "%.4f", $0) } ?? ""
        let pitchMs = subsystem.pitchTrackerMs.map { String(format: "%.4f", $0) } ?? ""
        let moodMs = subsystem.moodClassifierMs.map { String(format: "%.4f", $0) } ?? ""
        let subTiming = ",\(mirMs),\(stemMs),\(beatMs),\(pitchMs),\(moodMs)"
        // PERF.2-render — render-loop CPU breakdown. Empty cells until the
        // first render-loop completion handler fires.
        let encodeMs = renderTiming.encodeCpuMs.map { String(format: "%.4f", $0) } ?? ""
        let rfMs = renderTiming.renderFrameCpuMs.map { String(format: "%.4f", $0) } ?? ""
        let renderTimingCols = ",\(encodeMs),\(rfMs)"
        // PERF.2-pass — ray-march per-pass CPU breakdown. Empty cells on frames
        // where the active preset doesn't take the ray-march path.
        let gbufMs = rayMarchPass.gbufferPassMs.map { String(format: "%.4f", $0) } ?? ""
        let lightMs = rayMarchPass.lightingPassMs.map { String(format: "%.4f", $0) } ?? ""
        let ssgiMs = rayMarchPass.ssgiPassMs.map { String(format: "%.4f", $0) } ?? ""
        let postMs = rayMarchPass.postProcessPassMs.map { String(format: "%.4f", $0) } ?? ""
        let rayMarchPassCols = ",\(gbufMs),\(lightMs),\(ssgiMs),\(postMs)"
        // FBS Stage 1 (D-153) — the steady first-note-anchored beat pulse, so
        // anchor accuracy + steadiness are verifiable from session artifacts.
        let pulseCols = String(format: ",%.5f,%.3f", fv.pulsePhase01, fv.pulseAmp01)
        // Skein.5.2 — structural-section evidence (`section_index` / `section_start_s` /
        // `section_confidence`): the exact StructuralAnalyzer signal the Skein.5 structural
        // bias consumes (D-151), recorded so section firing — and BUG-035-class corruption
        // (sub-second "sections", inflated indices) — is verifiable from session artifacts.
        let structCols = String(format: ",%d,%.3f,%.4f",
                                structure.sectionIndex,
                                structure.sectionStartTime,
                                structure.confidence)
        // FBS.S5 (D-158) — trailing pulse columns (new columns go at the END;
        // positional parsers depend on the existing layout): the D-157 punch
        // mask seed and the D-158 global-bridge → regional blend, so the
        // flash-forensics replica can replay both exactly.
        let pulseCols2 = String(format: ",%.0f,%.4f\n",
                                fv.pulseBeatIndex, fv.pulseRegionalBlend01)
        return base + sync + timing + subTiming + renderTimingCols + rayMarchPassCols
            + pulseCols + structCols + pulseCols2
    }

    static func csvRow(stems: StemFeatures, frame: Int, wallclock: CFAbsoluteTime) -> String {
        let base = String(format: "%d,%.4f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,"
                                + "%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f",
                          frame, wallclock,
                          stems.drumsEnergy, stems.drumsBeat, stems.drumsBand0, stems.drumsBand1,
                          stems.bassEnergy, stems.bassBeat, stems.bassBand0, stems.bassBand1,
                          stems.vocalsEnergy, stems.vocalsBeat, stems.vocalsBand0, stems.vocalsBand1,
                          stems.otherEnergy, stems.otherBeat, stems.otherBand0, stems.otherBand1)
        let dev = String(format: ",%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f",
                         stems.drumsEnergyRel, stems.drumsEnergyDev,
                         stems.bassEnergyRel, stems.bassEnergyDev,
                         stems.vocalsEnergyRel, stems.vocalsEnergyDev,
                         stems.otherEnergyRel, stems.otherEnergyDev)
        let rich = String(format: ",%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,"
                                + "%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f",
                          stems.drumsOnsetRate, stems.drumsCentroid,
                          stems.drumsAttackRatio, stems.drumsEnergySlope,
                          stems.bassOnsetRate, stems.bassCentroid,
                          stems.bassAttackRatio, stems.bassEnergySlope,
                          stems.vocalsOnsetRate, stems.vocalsCentroid,
                          stems.vocalsAttackRatio, stems.vocalsEnergySlope,
                          stems.otherOnsetRate, stems.otherCentroid,
                          stems.otherAttackRatio, stems.otherEnergySlope)
        let pitch = String(format: ",%.3f,%.4f",
                           stems.vocalsPitchHz, stems.vocalsPitchConfidence)
        // IFC.4 (D-177) — per-family instrument activity (smoothed + D-026 dev).
        // The diagnostic artifact for the family-capture pipeline. New columns
        // at the END (positional parsers depend on the existing layout).
        let family = String(format: ",%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f\n",
                            stems.stringsActivity, stems.stringsActivityDev,
                            stems.brassActivity, stems.brassActivityDev,
                            stems.woodwindsActivity, stems.woodwindsActivityDev,
                            stems.percussionActivity, stems.percussionActivityDev)
        return base + dev + rich + pitch + family
    }
    // swiftlint:enable multiline_arguments
}
