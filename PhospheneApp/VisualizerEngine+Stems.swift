// VisualizerEngine+Stems — Background stem separation pipeline.
// Runs StemSeparator on a utility-QoS queue at 5-second cadence,
// feeds per-stem analysis to the render pipeline via buffer(3).

import DSP
import Foundation
import Metal
import ML
import os.log
import Session
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

    /// RMS threshold below which the stem pipeline skips CoreML inference.
    /// Interleaved stereo silence from Core Audio taps reads as true zero;
    /// 1e-6 catches near-zero noise floors without false-positive skips.
    private static let silenceRMSThreshold: Float = 1e-6

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

        // Idle suppression: skip CoreML inference when the buffer is silence.
        let rms = stemSampleBuffer.rms(seconds: 10)
        guard rms > Self.silenceRMSThreshold else {
            logger.debug("Stem pipeline: skipping — silence (RMS=\(rms))")
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

            // Multi-frame AGC warmup: iterate through the waveform in
            // 1024-sample windows at 60fps hop rate (~735 samples). This
            // feeds ~600 frames through BandEnergyProcessor's AGC, fully
            // warming it each cycle instead of producing attenuated output
            // from a single-frame analysis.
            let fps: Float = 60
            let hop = Int(44100.0 / fps)  // ~735 samples per frame
            let maxFrames = (sampleCount - 1024) / hop + 1
            var features = StemFeatures.zero

            for frame in 0..<maxFrames {
                let offset = frame * hop
                var frameWaveforms: [[Float]] = []
                for stem in stemWaveforms {
                    let end = min(offset + 1024, stem.count)
                    if offset < end {
                        frameWaveforms.append(Array(stem[offset..<end]))
                    } else {
                        frameWaveforms.append([Float](repeating: 0, count: 1024))
                    }
                }
                features = stemAnalyzer.analyze(stemWaveforms: frameWaveforms, fps: fps)
            }

            pipeline.setStemFeatures(features)
            let voc = features.vocalsEnergy
            let drm = features.drumsEnergy
            let bas = features.bassEnergy
            let oth = features.otherEnergy
            logger.debug("Stem update (\(maxFrames) frames): v=\(voc) d=\(drm) b=\(bas) o=\(oth)")

            // Diagnostic capture: dump the four separated stem waveforms as WAV
            // files so we can listen to separation quality against real audio.
            sessionRecorder?.recordStemSeparation(
                stemWaveforms: stemWaveforms,
                sampleRate: 44100,
                trackTitle: currentTrack?.title
            )
        } catch {
            logger.error("Stem separation failed: \(error)")
        }
    }

    /// Reset the stem pipeline on track change, loading pre-analyzed data from cache
    /// when available.
    ///
    /// Per the session preparation architecture:
    /// - `StemSampleBuffer` is NOT cleared — real-time audio keeps accumulating so
    ///   live separation can begin immediately.
    /// - If `stemCache` has data for the given identity, `StemFeatures` is seeded
    ///   from the pre-separated preview; otherwise it resets to `.zero`.
    ///
    /// - Parameter identity: The newly playing track. Pass nil when the identity is
    ///   unknown (falls back to `.zero` stems).
    func resetStemPipeline(for identity: TrackIdentity? = nil) {
        stemAnalyzer.reset()

        if let identity, let cached = stemCache?.loadForPlayback(track: identity) {
            pipeline.setStemFeatures(cached.stemFeatures)
            logger.info("Stem pipeline loaded from cache: \(identity.title) by \(identity.artist)")
        } else {
            pipeline.setStemFeatures(.zero)
            logger.info("Stem pipeline reset (track change, no cache entry)")
        }
        // StemSampleBuffer intentionally not reset — continues accumulating for live separation.
    }
}
