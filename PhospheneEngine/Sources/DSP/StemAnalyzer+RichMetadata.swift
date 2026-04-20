import Accelerate
import Shared

extension StemAnalyzer {

    // MARK: - MV-3a Rich Feature Result

    struct StemRichFeatures {
        var onsetRate: Float
        var centroid: Float
        var attackRatio: Float
        var energySlope: Float
    }

    // MARK: - MV-3a Rich Metadata

    /// Compute onset rate, spectral centroid, attack ratio, and energy slope for one stem.
    func computeRichFeatures(
        index: Int,
        waveform: [Float],
        magnitudes mags: [Float],
        attEnergy: Float,
        dt: Float
    ) -> StemRichFeatures {
        var centroid: Float = 0
        if !mags.isEmpty {
            let binResolution = sampleRate / Float(Self.fftSize)
            var weightedSum: Float = 0
            var totalMag: Float = 0
            for (idx, mag) in mags.enumerated() {
                let freq = Float(idx) * binResolution
                weightedSum += freq * mag
                totalMag += mag
            }
            centroid = totalMag > 1e-10 ? (weightedSum / totalMag) / nyquist : 0
        }

        var currentRMS: Float = 0
        if !waveform.isEmpty {
            var sumSq: Float = 0
            vDSP_svesq(waveform, 1, &sumSq, vDSP_Length(waveform.count))
            currentRMS = sqrt(sumSq / Float(waveform.count))
        }

        let fastDecay = exp(-dt / 0.050)
        let slowDecay = exp(-dt / 0.500)
        richStates[index].fastRMS = richStates[index].fastRMS * fastDecay
                                  + currentRMS * (1 - fastDecay)
        richStates[index].slowRMS = richStates[index].slowRMS * slowDecay
                                  + currentRMS * (1 - slowDecay)
        let attackRatio = min(3.0, richStates[index].fastRMS
                                  / max(richStates[index].slowRMS, 1e-8))

        let energySlope = dt > 0
            ? (attEnergy - richStates[index].prevAttEnergy) / dt
            : 0
        richStates[index].prevAttEnergy = attEnergy

        let flux = max(0, currentRMS - richStates[index].prevRMS)
        richStates[index].prevRMS = currentRMS
        richStates[index].fluxEMA = richStates[index].fluxEMA * 0.9 + flux * 0.1
        let fluxThreshold = richStates[index].fluxEMA * 1.5

        let refractoryFrames = max(1, Int((0.100 / max(dt, 1e-4)).rounded()))
        let nowAbove = flux > fluxThreshold && flux > 1e-6
        let risingEdge = nowAbove && !richStates[index].aboveThreshold
        let refractoryElapsed = richStates[index].framesSinceOnset >= refractoryFrames
        if risingEdge && refractoryElapsed {
            richStates[index].onsetAccum += 1.0
            richStates[index].framesSinceOnset = 0
        } else {
            richStates[index].framesSinceOnset &+= 1
        }
        richStates[index].aboveThreshold = nowAbove

        let windowDecay = exp(-dt / 0.5)
        richStates[index].onsetAccum *= windowDecay
        let onsetRate = richStates[index].onsetAccum * 2.0

        return StemRichFeatures(
            onsetRate: onsetRate,
            centroid: centroid,
            attackRatio: attackRatio,
            energySlope: energySlope
        )
    }

    // MARK: - Batch Rich Features

    /// Compute rich features for all 4 stems in a single call.
    func computeAllRichFeatures(
        stemWaveforms: [[Float]],
        results: [BandEnergyProcessor.Result],
        mags: [[Float]],
        dt: Float
    ) -> [StemRichFeatures] {
        return (0..<4).map { idx in
            let attE = (results[idx].bassAtt + results[idx].midAtt + results[idx].trebleAtt) / 3.0
            let wform = stemWaveforms[idx]
            return computeRichFeatures(index: idx, waveform: wform, magnitudes: mags[idx], attEnergy: attE, dt: dt)
        }
    }

    // MARK: - FFT Magnitudes

    /// Compute FFT magnitudes from a mono waveform.
    /// Uses the last `fftSize` samples. Returns 512 magnitude bins.
    func computeMagnitudes(from waveform: [Float]) -> [Float] {
        let sampleCount = waveform.count
        guard sampleCount > 0 else {
            magnitudes.withUnsafeMutableBufferPointer { buf in
                guard let base = buf.baseAddress else { return }
                base.initialize(repeating: 0, count: Self.binCount)
            }
            return magnitudes
        }

        let offset = max(0, sampleCount - Self.fftSize)
        let available = min(Self.fftSize, sampleCount)

        windowedSamples.withUnsafeMutableBufferPointer { buf in
            guard let base = buf.baseAddress else { return }
            base.initialize(repeating: 0, count: Self.fftSize)
        }
        waveform.withUnsafeBufferPointer { src in
            windowedSamples.withUnsafeMutableBufferPointer { dst in
                guard let dstBase = dst.baseAddress, let srcBase = src.baseAddress else { return }
                let copyStart = Self.fftSize - available
                dstBase.advanced(by: copyStart).update(
                    from: srcBase.advanced(by: offset),
                    count: available
                )
            }
        }

        vDSP_vmul(windowedSamples, 1, window, 1, &windowedSamples, 1, vDSP_Length(Self.fftSize))

        realPart.withUnsafeMutableBufferPointer { realBuf in
            imagPart.withUnsafeMutableBufferPointer { imagBuf in
                guard let realBase = realBuf.baseAddress, let imagBase = imagBuf.baseAddress else { return }
                var split = DSPSplitComplex(realp: realBase, imagp: imagBase)

                windowedSamples.withUnsafeBufferPointer { input in
                    guard let inputBase = input.baseAddress else { return }
                    inputBase.withMemoryRebound(
                        to: DSPComplex.self, capacity: Self.binCount
                    ) { complex in
                        vDSP_ctoz(complex, 2, &split, 1, vDSP_Length(Self.binCount))
                    }
                }

                vDSP_fft_zrip(fftSetup, &split, 1, Self.log2n, FFTDirection(kFFTDirection_Forward))

                magnitudes.withUnsafeMutableBufferPointer { magBuf in
                    guard let magBase = magBuf.baseAddress else { return }
                    vDSP_zvmags(&split, 1, magBase, 1, vDSP_Length(Self.binCount))
                }
            }
        }

        var scale = Float(Self.fftSize)
        vDSP_vsdiv(magnitudes, 1, &scale, &magnitudes, 1, vDSP_Length(Self.binCount))

        var count = Int32(Self.binCount)
        vvsqrtf(&magnitudes, magnitudes, &count)

        return magnitudes
    }
}
