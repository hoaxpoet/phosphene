// VisualizerEngine+Stems — Background stem separation pipeline.
// Runs StemSeparator on a utility-QoS queue at 5-second cadence,
// feeds per-stem analysis to the render pipeline via buffer(3).

import DSP
import Foundation
import Metal
import ML
import os.log
import Shared

private let logger = Logger(subsystem: "com.phosphene.app", category: "VisualizerEngine")

// MARK: - Stem Pipeline

extension VisualizerEngine {

    /// Load the optional stem separator; return nil and log on failure.
    static func loadStemSeparator(device: MTLDevice) -> StemSeparator? {
        do {
            let separator = try StemSeparator(device: device)
            logger.info("StemSeparator loaded")
            return separator
        } catch {
            logger.error("StemSeparator failed to load: \(error)")
            return nil
        }
    }

    /// Start the background stem separation timer (5-second cadence).
    func startStemPipeline() {
        guard stemSeparator != nil else {
            logger.info("Stem pipeline skipped — separator not available")
            return
        }

        let timer = DispatchSource.makeTimerSource(queue: stemQueue)
        timer.schedule(deadline: .now() + 10, repeating: 5.0)
        timer.setEventHandler { [weak self] in
            self?.runStemSeparation()
        }
        timer.resume()
        stemTimer = timer
        logger.info("Stem pipeline started (5s cadence, 10s warmup)")
    }

    /// Stop the background stem separation timer.
    func stopStemPipeline() {
        stemTimer?.cancel()
        stemTimer = nil
    }

    /// Run a single stem separation + analysis cycle on the stem queue.
    func runStemSeparation() {
        guard let separator = stemSeparator else { return }

        // Snapshot ~10s of interleaved stereo audio.
        let samples = stemSampleBuffer.snapshotLatest(seconds: 10)
        let requiredStereo = StemSeparator.requiredMonoSamples * 2
        guard samples.count >= requiredStereo else {
            logger.debug("Stem pipeline: warmup (\(samples.count)/\(requiredStereo) samples)")
            return
        }

        do {
            let result = try separator.separate(
                audio: samples, channelCount: 2, sampleRate: 44100
            )

            // Extract mono waveforms from each stem buffer.
            let sampleCount = result.sampleCount
            var stemWaveforms: [[Float]] = []
            for buffer in separator.stemBuffers {
                let count = min(sampleCount, buffer.capacity)
                let waveform = Array(buffer.pointer.prefix(count))
                stemWaveforms.append(waveform)
            }

            // Analyze per-stem energy and beats.
            let features = stemAnalyzer.analyze(
                stemWaveforms: stemWaveforms, fps: 60
            )
            pipeline.setStemFeatures(features)
            let voc = features.vocalsEnergy
            let drm = features.drumsEnergy
            let bas = features.bassEnergy
            let oth = features.otherEnergy
            logger.debug("Stem update: v=\(voc) d=\(drm) b=\(bas) o=\(oth)")
        } catch {
            logger.error("Stem separation failed: \(error)")
        }
    }

    /// Reset the stem pipeline on track change.
    func resetStemPipeline() {
        stemSampleBuffer.reset()
        stemAnalyzer.reset()
        pipeline.setStemFeatures(.zero)
        logger.info("Stem pipeline reset (track change)")
    }
}
