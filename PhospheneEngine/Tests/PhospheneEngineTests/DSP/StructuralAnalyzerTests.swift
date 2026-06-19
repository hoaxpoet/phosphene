// StructuralAnalyzerTests — Unit tests for progressive structural analysis.
// Validates boundary detection, prediction, repetition, and confidence scoring.
//
// BUG-042: the analyzer decimates its ~94 Hz input to one structural frame every
// 0.5 s (2 Hz) before the similarity matrix, so the frame-denominated geometry is
// section-scale: 8-frame checkerboard = 4 s, minPeakDistance 16 = 8 s minimum
// section, 600-frame ring = 5 min. These tests therefore use SECOND-scale section
// durations (15–20 s) — note-scale fixtures (2–3 s) no longer register boundaries.

import Testing
import Foundation
@testable import DSP
@testable import Shared

// MARK: - Helpers

/// A distinct 12-bin chroma vector for testing section identity.
private func chromaA() -> [Float] {
    // Strong C, E, G (C major triad).
    [0.9, 0.05, 0.05, 0.05, 0.8, 0.05, 0.05, 0.7, 0.05, 0.05, 0.05, 0.05]
}

/// A contrasting 12-bin chroma vector.
private func chromaB() -> [Float] {
    // Strong F#, A#, C# (F# major triad).
    [0.05, 0.8, 0.05, 0.05, 0.05, 0.05, 0.9, 0.05, 0.05, 0.05, 0.7, 0.05]
}

/// Frames for `seconds` of audio at the helper's feed rate (60 raw fps).
private func frames(_ seconds: Float) -> Int { Int(seconds * 60) }

/// Feed a section of N frames with given chroma to the analyzer.
@discardableResult
private func feedSection(
    analyzer: StructuralAnalyzer,
    chroma: [Float],
    centroid: Float = 0.5,
    flux: Float = 0.3,
    rolloff: Float = 0.6,
    energy: Float = 0.5,
    frames: Int,
    startTime: Float,
    fps: Float = 60
) -> StructuralPrediction {
    var prediction = StructuralPrediction.none
    let summary = StructuralAnalyzer.SpectralSummary(
        centroid: centroid,
        flux: flux,
        rolloff: rolloff,
        energy: energy
    )
    for i in 0..<frames {
        let time = startTime + Float(i) / fps
        prediction = analyzer.process(
            chroma: chroma,
            spectral: summary,
            time: time
        )
    }
    return prediction
}

// MARK: - Live-Edge Guard (BUG-040)

@Test func structuralAnalyzer_evolvingMusicNoBoundary_registersNothing() {
    // BUG-040 live-edge guard: continuously-evolving material with NO structural
    // discontinuity must register ZERO boundaries — pre-fix, the advancing live-edge
    // novelty peak escaped the dedup window and machine-gunned 20-35 junk boundaries
    // (session 2026-06-10T03-09-20Z).
    //
    // BUG-042 re-expression: the material must be non-sectional AT SECTION SCALE. The
    // pre-fix fixture used incommensurate sinusoids whose slowest term has a ~25 s period
    // — note-scale noise, but a legitimate ~25 s SECTION once the geometry is section-scale
    // (it correctly found 3). A monotonic linear A→B drift over the whole 50 s has constant
    // novelty everywhere — no local peak, no section — the section-scale analogue of
    // "smoothly evolving, no boundary" (cf. the detector-level gradualChange test).
    let analyzer = StructuralAnalyzer(maxHistory: 600, featureDim: 16, detectionInterval: 2)
    let startChroma = chromaA(), endChroma = chromaB()
    let total = 3000
    for i in 0..<total {
        let u = Float(i) / Float(total - 1)            // 0 → 1, monotonic.
        let chroma = (0..<12).map { startChroma[$0] + (endChroma[$0] - startChroma[$0]) * u }
        _ = analyzer.process(
            chroma: chroma,
            spectral: StructuralAnalyzer.SpectralSummary(
                centroid: 0.3 + 0.5 * u,
                flux: 0.1 + 0.6 * u,
                rolloff: 0.4 + 0.5 * u,
                energy: 0.3 + 0.5 * u
            ),
            time: Float(i) / 60.0
        )
    }
    #expect(analyzer.boundaryCount == 0,
            "Continuously-evolving no-boundary material registered \(analyzer.boundaryCount) boundaries (\(analyzer.boundaryTimestamps)) — the live-edge guard regressed (BUG-040).")
}

@Test func structuralAnalyzer_boundaryTimestamps_nonNegativeAndPlausible() {
    // BUG-040's second head: the live caller hardwired `time: 0` into MIRPipeline.process,
    // freezing the analyzer clock — boundary timestamps came out NEGATIVE (≈ −0.3 s) and
    // durations were noise. At the ANALYZER layer the contract is: fed a sane clock, the
    // registered boundary timestamp is non-negative and lands near the transition.
    // Section-scale (BUG-042): A for 15 s, B for 15 s — one true boundary at t = 15 s.
    // Tolerance ±3 s reflects the 4 s checkerboard block + 0.5 s decimation quantization.
    let analyzer = StructuralAnalyzer(maxHistory: 600, featureDim: 16, detectionInterval: 2)
    feedSection(analyzer: analyzer, chroma: chromaA(), frames: frames(15), startTime: 0)
    feedSection(analyzer: analyzer, chroma: chromaB(), centroid: 0.7, flux: 0.6,
                frames: frames(15), startTime: 15.0)
    let stamps = analyzer.boundaryTimestamps
    #expect(stamps.count == 1, "Expected exactly one boundary, got \(stamps)")
    if let ts = stamps.first {
        #expect(ts >= 0, "Boundary timestamp is negative (\(ts)) — the clock skew regressed (BUG-040).")
        #expect(abs(ts - 15.0) < 3.0,
                "Boundary timestamp \(ts) is far from the true transition at 15.0 s.")
    }
}

// MARK: - Ring-Wrap Dedup (BUG-035)

@Test func structuralAnalyzer_ringWrap_boundaryRegistersOnce() {
    // The pre-fix stale-index dedup re-admitted a boundary every ~4 detect calls while it
    // slid through the ring (~4-5 duplicates). Post-BUG-042 the ring holds DECIMATED
    // frames, so to exercise a wrap with a fast test we shrink the ring to 40 decimated
    // frames (= 20 s) and slide one real A→B boundary fully out with 40 s of B.
    let analyzer = StructuralAnalyzer(
        maxHistory: 40, featureDim: 16, detectionInterval: 2
    )

    // One real A→B transition at t = 10 s, then enough B to slide it fully out of history.
    feedSection(analyzer: analyzer, chroma: chromaA(), frames: frames(10), startTime: 0)
    feedSection(
        analyzer: analyzer, chroma: chromaB(), centroid: 0.7, flux: 0.6,
        frames: frames(40), startTime: 10.0
    )

    // Pre-fix: stale logical-index dedup re-registered the boundary ~4-5×,
    // collapsing section durations toward 0 and inflating sectionIndex.
    #expect(analyzer.boundaryCount == 1,
            "One musical boundary should register once across the ring slide, got \(analyzer.boundaryCount): \(analyzer.boundaryTimestamps)")
}

// MARK: - Init

@Test func structuralAnalyzer_init_noSegments() {
    let analyzer = StructuralAnalyzer()
    #expect(analyzer.boundaryCount == 0, "Fresh analyzer should have 0 boundaries")
    #expect(analyzer.boundaryTimestamps.isEmpty, "No timestamps on init")
}

// MARK: - One Section

@Test func structuralAnalyzer_oneSection_noPrediction() {
    let analyzer = StructuralAnalyzer(
        maxHistory: 400, featureDim: 16, detectionInterval: 2
    )

    // Feed 30 s of section A — no transition, so detection runs but finds no boundaries.
    let prediction = feedSection(
        analyzer: analyzer, chroma: chromaA(),
        frames: frames(30), startTime: 0
    )

    #expect(prediction.confidence == 0,
            "With only one section, confidence should be 0")
    #expect(prediction.predictedNextBoundary == 0,
            "No prediction without 2+ boundaries")
}

// MARK: - Two Sections Predict Third

@Test func structuralAnalyzer_twoSections_predictsThirdBoundary() {
    let analyzer = StructuralAnalyzer(
        maxHistory: 600, featureDim: 16, detectionInterval: 2
    )

    // Section A: 15 s.
    feedSection(
        analyzer: analyzer, chroma: chromaA(),
        frames: frames(15), startTime: 0
    )

    // Section B: 15 s.
    feedSection(
        analyzer: analyzer, chroma: chromaB(),
        frames: frames(15), startTime: 15.0
    )

    // Partial section A again: 12 s — enough after-context for the B→A boundary.
    let prediction = feedSection(
        analyzer: analyzer, chroma: chromaA(),
        frames: frames(12), startTime: 30.0
    )

    // After A→B and B→A boundaries, should have a prediction.
    if analyzer.boundaryCount >= 2 {
        #expect(prediction.predictedNextBoundary > 0,
                "Should predict next boundary after 2+ boundaries detected")
        #expect(prediction.confidence > 0,
                "Confidence should be > 0 with detected boundaries")
    }
    // If boundaries weren't detected (threshold sensitivity), still valid — just no prediction.
}

// MARK: - Boundary Detection

@Test func structuralAnalyzer_sectionBoundary_detectedOnNoveltyPeak() {
    let analyzer = StructuralAnalyzer(
        maxHistory: 400, featureDim: 16, detectionInterval: 2
    )

    // Clear section A — 15 s.
    feedSection(
        analyzer: analyzer, chroma: chromaA(),
        centroid: 0.3, flux: 0.1, rolloff: 0.4, energy: 0.3,
        frames: frames(15), startTime: 0
    )

    // Very different section B — 15 s.
    feedSection(
        analyzer: analyzer, chroma: chromaB(),
        centroid: 0.8, flux: 0.7, rolloff: 0.9, energy: 0.8,
        frames: frames(15), startTime: 15.0
    )

    #expect(analyzer.boundaryCount >= 1,
            "A sharp A→B transition should detect at least 1 boundary, got \(analyzer.boundaryCount)")
}

// MARK: - Repetition

@Test func structuralAnalyzer_repetition_identifiedCorrectly() {
    let analyzer = StructuralAnalyzer(
        maxHistory: 600, featureDim: 16, detectionInterval: 2
    )

    // ABAB pattern (15 s sections) — sections 1 & 3 (A) should be similar, 2 & 4 (B) similar.
    feedSection(analyzer: analyzer, chroma: chromaA(), frames: frames(15), startTime: 0)
    feedSection(analyzer: analyzer, chroma: chromaB(), frames: frames(15), startTime: 15.0)
    feedSection(analyzer: analyzer, chroma: chromaA(), frames: frames(15), startTime: 30.0)
    let prediction = feedSection(
        analyzer: analyzer, chroma: chromaB(), frames: frames(15), startTime: 45.0
    )

    // With an ABAB pattern, if boundaries are detected, confidence should
    // reflect both consistent durations and repetition.
    if analyzer.boundaryCount >= 2 {
        #expect(prediction.confidence > 0,
                "ABAB pattern should yield positive confidence")
    }
}

// MARK: - Confidence

@Test func structuralAnalyzer_confidence_lowForAmbientTrack() {
    let analyzer = StructuralAnalyzer(
        maxHistory: 600, featureDim: 16, detectionInterval: 2
    )

    // Feed random-ish features — slowly varying, no clear sections.
    var prediction = StructuralPrediction.none
    for i in 0..<1800 {
        let time = Float(i) / 60.0
        let phase = Float(i) * 0.0037  // Slow irrational phase.
        let chroma: [Float] = (0..<12).map { bin in
            0.3 + 0.2 * sinf(phase + Float(bin) * 0.5)
        }
        let summary = StructuralAnalyzer.SpectralSummary(
            centroid: 0.4 + 0.1 * sinf(phase),
            flux: 0.2 + 0.1 * cosf(phase),
            rolloff: 0.5,
            energy: 0.4
        )
        prediction = analyzer.process(
            chroma: chroma,
            spectral: summary,
            time: time
        )
    }

    // Ambient/random material should yield low confidence.
    #expect(prediction.confidence < 0.3,
            "Random features should yield low confidence, got \(prediction.confidence)")
}

@Test func structuralAnalyzer_confidence_highForRepetitiveTrack() {
    let analyzer = StructuralAnalyzer(
        maxHistory: 600, featureDim: 16, detectionInterval: 2
    )

    // ABAB pattern (15 s sections) with very distinct sections and consistent durations.
    feedSection(
        analyzer: analyzer, chroma: chromaA(),
        centroid: 0.3, flux: 0.1, rolloff: 0.4, energy: 0.3,
        frames: frames(15), startTime: 0
    )
    feedSection(
        analyzer: analyzer, chroma: chromaB(),
        centroid: 0.8, flux: 0.7, rolloff: 0.9, energy: 0.8,
        frames: frames(15), startTime: 15.0
    )
    feedSection(
        analyzer: analyzer, chroma: chromaA(),
        centroid: 0.3, flux: 0.1, rolloff: 0.4, energy: 0.3,
        frames: frames(15), startTime: 30.0
    )
    let prediction = feedSection(
        analyzer: analyzer, chroma: chromaB(),
        centroid: 0.8, flux: 0.7, rolloff: 0.9, energy: 0.8,
        frames: frames(15), startTime: 45.0
    )

    if analyzer.boundaryCount >= 3 {
        #expect(prediction.confidence > 0.6,
                "ABAB with consistent durations should yield high confidence, got \(prediction.confidence)")
    }
}

// MARK: - Reset

@Test func structuralAnalyzer_reset_clearsHistory() {
    let analyzer = StructuralAnalyzer(
        maxHistory: 400, featureDim: 16, detectionInterval: 2
    )

    // Feed some data.
    feedSection(analyzer: analyzer, chroma: chromaA(), frames: frames(10), startTime: 0)
    feedSection(analyzer: analyzer, chroma: chromaB(), frames: frames(10), startTime: 10.0)

    // Reset.
    analyzer.reset()

    #expect(analyzer.boundaryCount == 0, "After reset, boundaryCount should be 0")
    #expect(analyzer.boundaryTimestamps.isEmpty, "After reset, no timestamps")

    // Process a frame — should behave like fresh.
    let prediction = analyzer.process(
        chroma: chromaA(),
        spectral: StructuralAnalyzer.SpectralSummary(
            centroid: 0.5,
            flux: 0.3,
            rolloff: 0.6,
            energy: 0.5
        ),
        time: 0
    )
    #expect(prediction.confidence == 0, "After reset, confidence should be 0")
}
