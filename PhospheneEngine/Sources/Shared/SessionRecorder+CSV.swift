import Foundation

extension SessionRecorder {

    // MARK: - CSV row formatting

    // swiftlint:disable multiline_arguments
    static func csvRow(features fv: FeatureVector, frame: Int, wallclock: CFAbsoluteTime) -> String {
        csvRow(features: fv, beatSync: .zero, frame: frame, wallclock: wallclock,
               frameCPUms: nil, frameGPUms: nil)
    }

    static func csvRow(
        features fv: FeatureVector,
        beatSync bs: BeatSyncSnapshot,
        frame: Int,
        wallclock: CFAbsoluteTime,
        frameCPUms: Float? = nil,
        frameGPUms: Float? = nil
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
        let timing = ",\(cpu),\(gpu)\n"
        return base + sync + timing
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
        let pitch = String(format: ",%.3f,%.4f\n",
                           stems.vocalsPitchHz, stems.vocalsPitchConfidence)
        return base + dev + rich + pitch
    }
    // swiftlint:enable multiline_arguments
}
