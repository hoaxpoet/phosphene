// StemSeparationCadenceRegressionTests — BUG-086 regression gate.
//
// BUG-086: every per-stem feature reached presets ≈5.4 s behind the audio while
// the beat grid beside it was time-aligned to ≈0.3 s. Nothing was miscoded. The
// cause was three independent literals in two files — a 5 s separation period
// (`VisualizerEngine+Stems.swift`), a 10 s chunk (same file), and a read window
// starting 5 s into that chunk (`VisualizerEngine+Audio.swift`) — with no line
// anywhere naming the relationship between them.
//
// The relationship is:
//
//     latency = chunkSeconds − readStartSeconds
//     runway  = chunkSeconds − readStartSeconds     (the same span)
//     runway must be ≥ separationPeriod, or the per-frame read window clamps at
//     the chunk's end and stem features freeze between separations
//
// so latency ≥ separationPeriod, always. These tests assert that relationship
// rather than the constants' values, so retuning the cadence stays free while
// re-breaking the invariant does not.
//
// Why it matters beyond one preset: the stem features feed every stem-driven
// preset, including Aurora Veil, whose `other_energy_dev` route is its
// song-defining anchor.

import Foundation
import ML
import Testing
@testable import PhospheneApp

@Suite("Stem separation cadence invariants (BUG-086)")
struct StemSeparationCadenceRegressionTests {

    // MARK: - The invariant that BUG-086 violated

    @Test("Read window has at least one separation period of runway before it clamps")
    func runwayCoversOneSeparationPeriod() {
        let runway = VisualizerEngine.stemChunkSeconds
            - VisualizerEngine.stemReadStartSeconds

        #expect(
            runway >= VisualizerEngine.stemSeparationPeriodSeconds,
            """
            Read runway \(runway)s is shorter than the \
            \(VisualizerEngine.stemSeparationPeriodSeconds)s separation period. The \
            per-frame window advances in real time and will clamp at the chunk's end \
            before the next chunk lands, freezing stem features. Raise \
            stemReadMarginSeconds, or shorten stemSeparationPeriodSeconds.
            """
        )
    }

    @Test("Read start leaves margin beyond the bare period, so jitter cannot clamp it")
    func runwayCarriesMarginBeyondThePeriod() {
        let runway = VisualizerEngine.stemChunkSeconds
            - VisualizerEngine.stemReadStartSeconds
        let slack = runway - VisualizerEngine.stemSeparationPeriodSeconds

        // Inference time and MLDispatchScheduler deferral (D-059, 2 s ceiling)
        // both push the next chunk's arrival later than the nominal period.
        // Zero slack means routine clamping.
        #expect(
            slack > 0,
            "Runway exactly equals the period — any inference or deferral jitter clamps it."
        )
        #expect(slack == VisualizerEngine.stemReadMarginSeconds)
    }

    // MARK: - Latency, the user-facing quantity

    @Test("Nominal stem latency is the chunk span the read window sits behind")
    func nominalLatencyMatchesTheReadOffset() {
        #expect(
            VisualizerEngine.stemNominalLatencySeconds
                == VisualizerEngine.stemChunkSeconds - VisualizerEngine.stemReadStartSeconds
        )
    }

    @Test("Nominal stem latency stays well under the ≈5.4 s BUG-086 measured")
    func latencyIsBelowTheRegressionCeiling() {
        // 3.0 s is a ceiling, not a target. The measured pre-fix value was ≈5.4 s
        // (39 of 40 stem × track pairs, docs/diagnostics/
        // CHR1_STEM_DECORRELATION_2026-08-11.md §7b). Anything at or above the old
        // behaviour is the regression this gate exists to catch.
        #expect(VisualizerEngine.stemNominalLatencySeconds < 3.0)
    }

    // MARK: - The chunk length is not a tuning knob

    @Test("Chunk length matches what the exported model actually requires")
    func chunkLengthMatchesTheModelContract() {
        // StemSeparator.modelFrameCount is fixed by the exported Open-Unmix model;
        // requiredMonoSamples is derived from it. If someone shortens
        // stemChunkSeconds to cut latency, separation silently gets too little
        // audio — so pin the constant to the model's own requirement.
        let modelSeconds = Double(StemSeparator.requiredMonoSamples)
            / Double(StemSeparator.modelSampleRate)

        #expect(
            abs(VisualizerEngine.stemChunkSeconds - modelSeconds) < 0.5,
            """
            stemChunkSeconds (\(VisualizerEngine.stemChunkSeconds)s) no longer matches the \
            model's required input (\(modelSeconds)s). Chunk length is set by the exported \
            model, not chosen — cut latency via stemSeparationPeriodSeconds instead.
            """
        )
    }

    @Test("Read start is derived from the cadence, not an independent literal")
    func readStartIsDerived() {
        // The specific failure mode of BUG-086: read start and period drifting
        // apart because they were separate literals in separate files.
        #expect(
            VisualizerEngine.stemReadStartSeconds
                == max(
                    0,
                    VisualizerEngine.stemChunkSeconds
                        - VisualizerEngine.stemSeparationPeriodSeconds
                        - VisualizerEngine.stemReadMarginSeconds
                )
        )
    }

    @Test("Read start stays inside the chunk for any cadence the constants allow")
    func readStartIsWithinTheChunk() {
        #expect(VisualizerEngine.stemReadStartSeconds >= 0)
        #expect(VisualizerEngine.stemReadStartSeconds < VisualizerEngine.stemChunkSeconds)
    }
}
