import Foundation

extension SessionRecorder {

    // MARK: - CSV row formatting

    // swiftlint:disable multiline_arguments
    static func csvRow(features fv: FeatureVector, frame: Int, wallclock: CFAbsoluteTime) -> String {
        String(format: "%d,%.4f,%.4f,%.4f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,"
                     + "%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f,"
                     + "%.5f,%.5f,%.5f,%.5f\n",
               frame, wallclock, fv.time, fv.deltaTime,
               fv.bass, fv.mid, fv.treble,
               fv.subBass, fv.lowBass, fv.lowMid, fv.midHigh, fv.highMid, fv.high,
               fv.beatBass, fv.beatMid, fv.beatTreble, fv.beatComposite,
               fv.spectralCentroid, fv.spectralFlux, fv.valence, fv.arousal,
               fv.accumulatedAudioTime,
               fv.beatPhase01, fv.bassRel, fv.bassDev, fv.bassAttRel)
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
