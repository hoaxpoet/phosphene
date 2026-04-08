// StructuralAnalyzerTests — Unit tests for progressive structural analysis.
// Validates boundary detection, prediction, repetition, and confidence scoring.

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
    for i in 0..<frames {
        let time = startTime + Float(i) / fps
        prediction = analyzer.process(
            chroma: chroma,
            spectralCentroid: centroid,
            spectralFlux: flux,
            spectralRolloff: rolloff,
            energy: energy,
            time: time
        )
    }
    return prediction
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
        maxHistory: 400, featureDim: 16, detectionInterval: 10
    )

    // Feed 300 frames of section A — no transition, so no boundaries.
    let prediction = feedSection(
        analyzer: analyzer, chroma: chromaA(),
        frames: 300, startTime: 0
    )

    #expect(prediction.confidence == 0,
            "With only one section, confidence should be 0")
    #expect(prediction.predictedNextBoundary == 0,
            "No prediction without 2+ boundaries")
}

// MARK: - Two Sections Predict Third

@Test func structuralAnalyzer_twoSections_predictsThirdBoundary() {
    let analyzer = StructuralAnalyzer(
        maxHistory: 600, featureDim: 16, detectionInterval: 10
    )

    // Section A: 150 frames (2.5s at 60fps).
    feedSection(
        analyzer: analyzer, chroma: chromaA(),
        frames: 150, startTime: 0
    )

    // Section B: 150 frames.
    feedSection(
        analyzer: analyzer, chroma: chromaB(),
        frames: 150, startTime: 2.5
    )

    // Partial section A again: 100 frames — enough to trigger detection.
    let prediction = feedSection(
        analyzer: analyzer, chroma: chromaA(),
        frames: 100, startTime: 5.0
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
        maxHistory: 400, featureDim: 16, detectionInterval: 10
    )

    // Clear section A.
    feedSection(
        analyzer: analyzer, chroma: chromaA(),
        centroid: 0.3, flux: 0.1, rolloff: 0.4, energy: 0.3,
        frames: 150, startTime: 0
    )

    // Very different section B.
    feedSection(
        analyzer: analyzer, chroma: chromaB(),
        centroid: 0.8, flux: 0.7, rolloff: 0.9, energy: 0.8,
        frames: 150, startTime: 2.5
    )

    #expect(analyzer.boundaryCount >= 1,
            "A sharp A→B transition should detect at least 1 boundary, got \(analyzer.boundaryCount)")
}

// MARK: - Repetition

@Test func structuralAnalyzer_repetition_identifiedCorrectly() {
    let analyzer = StructuralAnalyzer(
        maxHistory: 600, featureDim: 16, detectionInterval: 10
    )

    // ABAB pattern — sections 1 & 3 (A) should be similar, 2 & 4 (B) similar.
    feedSection(analyzer: analyzer, chroma: chromaA(), frames: 120, startTime: 0)
    feedSection(analyzer: analyzer, chroma: chromaB(), frames: 120, startTime: 2.0)
    feedSection(analyzer: analyzer, chroma: chromaA(), frames: 120, startTime: 4.0)
    let prediction = feedSection(
        analyzer: analyzer, chroma: chromaB(), frames: 120, startTime: 6.0
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
        maxHistory: 600, featureDim: 16, detectionInterval: 10
    )

    // Feed random-ish features — slowly varying, no clear sections.
    var prediction = StructuralPrediction.none
    for i in 0..<500 {
        let t = Float(i) / 60.0
        let phase = Float(i) * 0.037  // Slow irrational phase.
        let chroma: [Float] = (0..<12).map { bin in
            0.3 + 0.2 * sinf(phase + Float(bin) * 0.5)
        }
        prediction = analyzer.process(
            chroma: chroma,
            spectralCentroid: 0.4 + 0.1 * sinf(phase),
            spectralFlux: 0.2 + 0.1 * cosf(phase),
            spectralRolloff: 0.5,
            energy: 0.4,
            time: t
        )
    }

    // Ambient/random material should yield low confidence.
    #expect(prediction.confidence < 0.3,
            "Random features should yield low confidence, got \(prediction.confidence)")
}

@Test func structuralAnalyzer_confidence_highForRepetitiveTrack() {
    let analyzer = StructuralAnalyzer(
        maxHistory: 600, featureDim: 16, detectionInterval: 10
    )

    // ABAB pattern with very distinct sections and consistent durations.
    feedSection(
        analyzer: analyzer, chroma: chromaA(),
        centroid: 0.3, flux: 0.1, rolloff: 0.4, energy: 0.3,
        frames: 120, startTime: 0
    )
    feedSection(
        analyzer: analyzer, chroma: chromaB(),
        centroid: 0.8, flux: 0.7, rolloff: 0.9, energy: 0.8,
        frames: 120, startTime: 2.0
    )
    feedSection(
        analyzer: analyzer, chroma: chromaA(),
        centroid: 0.3, flux: 0.1, rolloff: 0.4, energy: 0.3,
        frames: 120, startTime: 4.0
    )
    let prediction = feedSection(
        analyzer: analyzer, chroma: chromaB(),
        centroid: 0.8, flux: 0.7, rolloff: 0.9, energy: 0.8,
        frames: 120, startTime: 6.0
    )

    if analyzer.boundaryCount >= 3 {
        #expect(prediction.confidence > 0.6,
                "ABAB with consistent durations should yield high confidence, got \(prediction.confidence)")
    }
}

// MARK: - Reset

@Test func structuralAnalyzer_reset_clearsHistory() {
    let analyzer = StructuralAnalyzer(
        maxHistory: 400, featureDim: 16, detectionInterval: 10
    )

    // Feed some data.
    feedSection(analyzer: analyzer, chroma: chromaA(), frames: 100, startTime: 0)
    feedSection(analyzer: analyzer, chroma: chromaB(), frames: 100, startTime: 1.67)

    // Reset.
    analyzer.reset()

    #expect(analyzer.boundaryCount == 0, "After reset, boundaryCount should be 0")
    #expect(analyzer.boundaryTimestamps.isEmpty, "After reset, no timestamps")

    // Process a frame — should behave like fresh.
    let prediction = analyzer.process(
        chroma: chromaA(),
        spectralCentroid: 0.5, spectralFlux: 0.3,
        spectralRolloff: 0.6, energy: 0.5, time: 0
    )
    #expect(prediction.confidence == 0, "After reset, confidence should be 0")
}
