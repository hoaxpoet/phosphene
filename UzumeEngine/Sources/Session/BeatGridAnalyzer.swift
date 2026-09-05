// BeatGridAnalyzer — Offline beat-grid analysis step in the session preparation pipeline.
//
// Wraps Beat This! preprocessing (audio → log-mel spectrogram), MPSGraph inference,
// and BeatGridResolver postprocessing into a single injectable step. The protocol
// matches the StemSeparating / MoodClassifying pattern so SessionPreparer accepts
// the dependency by interface and tests can stub it without Metal.

import DSP
import Foundation
import ML
import Metal
import os.log

private let logger = Logger(subsystem: "io.uzume", category: "BeatGridAnalyzer")

// MARK: - BeatGridAnalyzing

/// Contract for offline beat grid analysis during session preparation.
public protocol BeatGridAnalyzing: Sendable {
    /// Run Beat This! preprocessing + inference + resolver on mono PCM audio.
    ///
    /// - Parameters:
    ///   - samples: Mono Float32 PCM at `sampleRate`.
    ///   - sampleRate: The native sample rate of `samples` (e.g. 44100). The
    ///     preprocessor resamples internally to 22050 Hz.
    ///   - wholeTrack: `true` when `samples` is the ENTIRE track and the grid should
    ///     span it. The local-file path passes `true`; streaming passes `false` because
    ///     its input is a 30 s preview and there is nothing more to analyse.
    ///
    ///     This is the difference PR.12 measured. `BeatThisModel.tMax` clamps inference to
    ///     1500 frames (30 s at 50 fps), which costs a 30 s preview nothing and truncates a
    ///     local FLAC to **6.7–11.4 %** of its length. Past the end of `BeatGrid.beats`,
    ///     `localTiming` falls back to `60.0 / bpm` — a whole-track AVERAGE — so ~90 % of
    ///     every local track ran on one averaged tempo. A constant period against changing
    ///     music is a linear phase error, which is BUG-065's drift ramp.
    /// - Returns: Resolved `BeatGrid`; `.empty` on failure (graceful degradation).
    func analyzeBeatGrid(samples: [Float], sampleRate: Double, wholeTrack: Bool) -> BeatGrid
}

extension BeatGridAnalyzing {
    /// Streaming-shaped call: analyse whatever was passed under the 30 s clamp.
    /// Kept so the many existing call sites (tests, diagnostics, BeatBench) are unchanged.
    public func analyzeBeatGrid(samples: [Float], sampleRate: Double) -> BeatGrid {
        analyzeBeatGrid(samples: samples, sampleRate: sampleRate, wholeTrack: false)
    }
}

// MARK: - DefaultBeatGridAnalyzer

/// Production beat-grid analyzer composing `BeatThisPreprocessor` and `BeatThisModel`.
///
/// Both wrapped components are thread-safe (internal locks), so this analyzer is
/// safe to call from any thread. `analyzeBeatGrid` is synchronous and is intended
/// to be invoked from inside `Task.detached` in `SessionPreparer.prepareTrack`.
///
/// Frame rate is fixed at 50.0 fps — Beat This! always processes audio at
/// 22050 Hz with hop=441, giving 22050/441 = 50.0 fps.
public final class DefaultBeatGridAnalyzer: BeatGridAnalyzing, @unchecked Sendable {

    // MARK: - State

    private let preprocessor: BeatThisPreprocessor
    private let model: BeatThisModel
    private static let frameRate: Double = 50.0

    // MARK: - Init

    public init(device: MTLDevice) throws {
        self.preprocessor = BeatThisPreprocessor()
        self.model = try BeatThisModel(device: device)
    }

    // MARK: - BeatGridAnalyzing

    public func analyzeBeatGrid(
        samples: [Float], sampleRate: Double, wholeTrack: Bool
    ) -> BeatGrid {
        let (spec, frameCount) = preprocessor.process(
            samples: samples,
            inputSampleRate: sampleRate
        )
        guard frameCount > 0 else {
            logger.info("BeatGrid: preprocessor returned empty spectrogram")
            return .empty
        }
        do {
            // FT.4 (Matt, 2026-08-27), env-flagged A/B per the program house rule (plan §4).
            // OFF: one `predict` over a fixed 1500-frame (~30 s) window, and bar position from
            // the model's downbeat head. ON: FT.1's tiler decodes the WHOLE track, and bar
            // position comes from FT.3's `BarLineEstimator`, which scores beat-synchronous
            // accent features at already-known beat times instead of reading that head.
            //
            // The head is why this exists: it over-fires. On money it emits a downbeat on 78 %
            // of beats, so `computeMeter`'s round(median_IOI / beat_period) returns 1 and the
            // 7 collapses (docs/diagnostics/DOWNBEAT_SURVEY_2026-08-27.md). Four levers have
            // already failed to fix it in place (TRK.2, DBN.2, MDL.1, FT.1); this bypasses it.
            //
            // The estimator DECLINES rather than guessing — at its calibrated threshold it
            // answers ~2 of 9 ground-truthed tracks. That is the point, not a shortfall: the
            // program's suite-5 principle is that a confident-but-wrong beat is worse than
            // declining, and D-205 makes meter/downbeat a hard gate because Nacre's and
            // Glaze's downbeat pushes are their connection layer.
            // Split into two switches at FT.4.1 (Matt, 2026-08-27). FT.4 bundled them and the
            // A/B could not tell take_five's bar win apart from bleed's beat loss; they are
            // independent — `BarLineEstimator` takes any `beats` array. `UZUME_FULLTRACK_BARS`
            // still turns both on so the FT.4 arm stays reproducible.
            let env = ProcessInfo.processInfo.environment
            let both = env["UZUME_FULLTRACK_BARS"] == "1"
            // PR.12 (Matt, 2026-09-04: "fix the local path to analyze the whole track").
            // `wholeTrack` is the local-file path saying it holds the entire file. The env
            // flags remain for A/B and for forcing the behaviour on the streaming path.
            //
            // FT.4.1 disqualified full-track decode on bleed 115.00 -> 123.62. That was a
            // SCORING artifact: BeatBench trims the reference to each grid's own span, so
            // the 30 s grid was graded on 30 s and the full-track grid on six minutes.
            // Scored over an identical span, beat F is equal or better on 8 of 9 fixtures
            // and bleed itself goes 0.99 -> 1.00 (PR12_BEAT_ANALYZER_RETHINK_2026-09-04.md).
            let fullTrack = both || wholeTrack || env["UZUME_FULLTRACK_DECODE"] == "1"
            // NOT adopted. Default-on was tried at PR.3d and REVERTED the same day
            // (Matt: "the failure rate here is too high"). It was recommended off nine
            // benchmark fixtures without measuring the album Matt actually reviewed; on
            // Bowie's Low it takes bar coverage 11/11 -> 5/11, fixes What In The World
            // (2 -> 4) and SILENCES Be My Wife and A New Career, which both had the
            // correct 4/4 AND the tightest phase on the record. One track fixed, two
            // working tracks broken. See PR3D_BARLINE_ADOPTION_2026-09-04.md §6.
            let barLine = both || env["UZUME_BARLINE"] == "1"
            // PR.17 (Matt, 2026-09-05: "sparse and correct"). The windowed arm — the same
            // estimator asked once per ~80 beats instead of once per track, emitting bars
            // ONLY where a window answers. PR.15 measured why: scored globally, one number
            // has to describe an intro, a chorus and an outro at once, and it is worse than
            // either the windows or the old 30 s clip. Per window, money answers 7 and
            // take_five answers 5 on 11 of 11 windows.
            //
            // Gated on `fullTrack`, because the estimator's scope is the whole file: a
            // 30 s streaming grid is one short window and would just decline. The name
            // says local because that is the only path it can serve.
            //
            // DEFAULT ON since 2026-09-05 (Matt: "Flip it"), measured on Bowie's Low and
            // on every truthed fixture first (PR17_LOCAL_BARS_2026-09-05.md, [D-243]).
            // What it buys: take_five decodes 5/4 and money 7/4 for the first time, and
            // every wrong bar on Low disappears. What it costs: bar-driven motion goes
            // quiet on ~half of Low, including Be My Wife, which had a correct bar — and
            // 0.89 s/track of preparation against D-242's 7.5 s/track budget.
            // `UZUME_BARLINE_LOCAL=0` restores the model's downbeat head.
            let barLineLocal = Self.usesWindowedBarLine(environment: env)
            let activations: (beats: [Float], downbeats: [Float])
            if fullTrack {
                activations = try BeatThisTiledInference.predictFullTrack(
                    model: model,
                    spectrogram: spec,
                    frameCount: frameCount
                )
            } else {
                activations = try model.predict(spectrogram: spec, frameCount: frameCount)
            }

            let grid = BeatGridResolver.resolve(
                beatProbs: activations.beats,
                downbeatProbs: activations.downbeats,
                frameRate: Self.frameRate
            )
            if barLineLocal, fullTrack {
                return Self.applyWindowedBarLine(
                    to: grid,
                    samples: samples,
                    sampleRate: sampleRate
                )
            }
            guard barLine else { return grid }
            return Self.applyBarLineEstimate(
                to: grid,
                samples: samples,
                sampleRate: sampleRate
            )
        } catch {
            logger.error("BeatGrid: model.predict failed: \(error.localizedDescription)")
            return .empty
        }
    }

    // MARK: - FT.4 bar-line override

    /// Replace the grid's meter/bar phase with `BarLineEstimator`'s, or leave the grid's
    /// beats alone and carry NO bars when the estimator declines.
    ///
    /// A decline is expressed as `beatsPerBar = 1` with empty `downbeats` and zero
    /// confidence — the same shape a track with no detected bars already produces, so
    /// consumers need no new case. Beats are never touched: they are the layer that
    /// works (F 0.97–0.99), and D-004 keeps them an accent layer regardless.
    private static func applyBarLineEstimate(
        to grid: BeatGrid,
        samples: [Float],
        sampleRate: Double
    ) -> BeatGrid {
        // PR.3 / BUG-114: run the estimator at the rate its `declineThreshold` was
        // calibrated on. `nFFT` is fixed in SAMPLES, so passing the file's native rate
        // straight through halves the per-beat analysis window (92.9 ms → 46.4 ms at
        // 44.1 kHz) and depresses every margin. The parity test decodes to 22050
        // explicitly, so it cannot see this. Measured: around_the_world 0.147 → 1.265,
        // crossing the 1.24 threshold from decline to answer.
        let estimate = BarLineEstimator.estimate(
            beats: grid.beats,
            audio: samples,
            sampleRate: sampleRate,
            options: .init(resampleToReferenceRate: true)
        )
        guard let beatsPerBar = estimate.beatsPerBar, let phase = estimate.barLinePhase else {
            let why = estimate.decline.rawValue
            logger.info("BeatGrid FT.4: bar line DECLINED (\(why), margin \(estimate.margin)) — no bars")
            return BeatGrid(
                beats: grid.beats,
                downbeats: [],
                bpm: grid.bpm,
                beatsPerBar: 1,
                barConfidence: 0,
                frameRate: grid.frameRate,
                frameCount: grid.frameCount
            )
        }
        // Lay downbeats on the estimated phase: every `beatsPerBar`-th beat from `phase`.
        let downbeats = grid.beats.enumerated()
            .filter { $0.offset % beatsPerBar == phase }
            .map(\.element)
        logger.info("BeatGrid FT.4: bar \(beatsPerBar) phase \(phase), \(downbeats.count) downbeats")
        return BeatGrid(
            beats: grid.beats,
            downbeats: downbeats,
            bpm: grid.bpm,
            beatsPerBar: beatsPerBar,
            barConfidence: Float(min(1.0, estimate.margin / 4.0)),
            frameRate: grid.frameRate,
            frameCount: grid.frameCount
        )
    }

    // MARK: - PR.17 windowed bar line

    /// Whether the windowed bar line is active. Default ON; `UZUME_BARLINE_LOCAL=0` opts
    /// out. Pure and testable because the DEFAULT is the load-bearing part — an inverted
    /// comparison here silently reverts every local track to the over-firing downbeat head
    /// with no test failing.
    static func usesWindowedBarLine(environment: [String: String]) -> Bool {
        environment["UZUME_BARLINE_LOCAL"] != "0"
    }

    /// Lay downbeats from the per-window estimator: bars where a window answers, and
    /// NOTHING where it declines.
    ///
    /// Matt's call (2026-09-05) between sparse-and-correct and dense-with-fallback was
    /// sparse. So a declined window is not backfilled from the model's downbeat head —
    /// a preset gets no bar-driven motion through that stretch rather than an accent on
    /// the wrong beat. `beatsPerBar` carries the modal answered meter as a summary for
    /// the consumers that read it when `downbeats` is empty; `downbeats` is the truth.
    ///
    /// `barConfidence` stays what D-154's irregularity gate expects — the strength of the
    /// bars that WERE found, not how much of the track they cover. A track where every
    /// window declines reports 0, exactly as the global decline path already does, so the
    /// beat-locked-preset exclusion behaves identically.
    static func applyWindowedBarLine(
        to grid: BeatGrid,
        samples: [Float],
        sampleRate: Double
    ) -> BeatGrid {
        let windowed = BarLineEstimator.estimateWindowed(
            beats: grid.beats,
            audio: samples,
            sampleRate: sampleRate,
            options: .init(resampleToReferenceRate: true)
        )
        let confident = windowed.estimates.filter(\.isConfident)
        let meanMargin = confident.isEmpty
            ? 0
            : confident.reduce(0) { $0 + $1.margin } / Double(confident.count)
        let answered = windowed.windowsAnswered
        let total = windowed.windowCount
        let cover = Int(windowed.coverage * 100)
        let meter = windowed.modalMeter ?? 0
        let bars = windowed.downbeats.count
        logger.info("BeatGrid PR.17: \(answered)/\(total) windows, \(cover) % of beats, meter \(meter), \(bars) bars")
        return BeatGrid(
            beats: grid.beats,
            downbeats: windowed.downbeats,
            bpm: grid.bpm,
            beatsPerBar: windowed.modalMeter ?? 1,
            barConfidence: Float(min(1.0, meanMargin / 4.0)),
            frameRate: grid.frameRate,
            frameCount: grid.frameCount
        )
    }
}
