// MoodClassifierGoldenTests — Output-behaviour golden test for MoodClassifier.
//
// MoodClassifier carries 3,346 hardcoded Float32 weights extracted from a DEAM
// training run, plus 10-feature z-score normalization and a 4-layer MLP forward.
// There is no upstream test that anchors *what the classifier should output for
// a known input* — a future contributor could re-extract the weights from a
// different DEAM checkpoint or accidentally byte-order a buffer wrong, and the
// existing tests would all pass while production produced different mood values.
//
// This test fixes 10 deterministic 10-feature input vectors and the classifier's
// outputs for them, asserting the output behavior is byte-stable.
//
// Each entry uses its own MoodClassifier instance — the classifier carries an
// EMA smoother that depends on call order, so a fresh classifier per entry keeps
// the test hermetic.
//
// Regenerating: set `UPDATE_MOOD_GOLDEN=1` and re-run. The test prints the
// regenerated JSON to stdout; copy-paste it into `Fixtures/mood_classifier_golden.json`.
// Don't hand-type values — produce them by running the classifier.

import Testing
import Foundation
@testable import ML

@Suite("MoodClassifierGolden")
struct MoodClassifierGoldenTests {

    // MARK: - Inputs

    /// Ten varied 10-feature input vectors. Inputs are [subBass, lowBass, lowMid,
    /// midHigh, highMid, high, centroid, flux, majorKey, minorKey] — see
    /// MoodClassifier.swift class comment.
    /// Variants chosen to span: high-energy bright (entry 0), high-energy dark
    /// (1), low-energy bright (2), low-energy dark (3), mid-energy mid (4),
    /// vocal-band emphasis (5), bass-only (6), treble-only (7), majorKey edge
    /// (8), minorKey edge (9).
    static let goldenInputs: [[Float]] = [
        [0.50, 0.55, 0.30, 0.20, 0.18, 0.15, 0.65, 0.30, 0.85, 0.30],   // bright high
        [0.70, 0.65, 0.20, 0.10, 0.05, 0.04, 0.20, 0.40, 0.30, 0.85],   // dark high
        [0.10, 0.12, 0.10, 0.08, 0.05, 0.04, 0.55, 0.10, 0.80, 0.35],   // bright sparse
        [0.05, 0.08, 0.06, 0.04, 0.02, 0.01, 0.18, 0.05, 0.30, 0.80],   // dark sparse
        [0.30, 0.35, 0.30, 0.25, 0.20, 0.15, 0.45, 0.25, 0.55, 0.55],   // mid mid
        [0.10, 0.12, 0.45, 0.50, 0.20, 0.10, 0.55, 0.30, 0.55, 0.50],   // mid-band emph
        [0.65, 0.55, 0.10, 0.05, 0.02, 0.01, 0.10, 0.20, 0.40, 0.60],   // bass-only
        [0.05, 0.08, 0.10, 0.20, 0.45, 0.50, 0.85, 0.45, 0.55, 0.45],   // treble-only
        [0.25, 0.30, 0.25, 0.20, 0.15, 0.10, 0.50, 0.20, 0.95, 0.20],   // major edge
        [0.25, 0.30, 0.25, 0.20, 0.15, 0.10, 0.50, 0.20, 0.20, 0.95]    // minor edge
    ]

    // MARK: - Golden fixture

    struct GoldenEntry: Codable {
        let inputs: [Float]
        let valence: Float
        let arousal: Float
    }

    static let fixturePath: URL = {
        URL(fileURLWithPath: String(#filePath))
            .deletingLastPathComponent()  // ML/
            .deletingLastPathComponent()  // PhospheneEngineTests/
            .appendingPathComponent("Fixtures/mood_classifier_golden.json")
    }()

    // MARK: - Assertion test

    @Test("MoodClassifier output matches golden fixture within 1e-4 over 10 deterministic inputs")
    func test_moodClassifierGolden() throws {
        if ProcessInfo.processInfo.environment["UPDATE_MOOD_GOLDEN"] == "1" {
            // Regeneration mode: run the classifier and print the JSON to stdout.
            try regenerateAndPrintFixture()
            return
        }

        guard FileManager.default.fileExists(atPath: Self.fixturePath.path) else {
            Issue.record("""
                Golden fixture absent at \(Self.fixturePath.path) — run with \
                UPDATE_MOOD_GOLDEN=1 swift test --filter MoodClassifierGolden \
                and paste the printed JSON into the fixture file.
                """)
            return
        }
        let data = try Data(contentsOf: Self.fixturePath)
        let entries = try JSONDecoder().decode([GoldenEntry].self, from: data)
        #expect(entries.count == Self.goldenInputs.count,
                "Fixture has \(entries.count) entries; expected \(Self.goldenInputs.count). Inputs and fixture out of sync.")

        for (idx, entry) in entries.enumerated() {
            // Confirm fixture's stored inputs match the test's hardcoded ones —
            // catches drift between test inputs and fixture without the regeneration step.
            #expect(entry.inputs == Self.goldenInputs[idx],
                    "Entry \(idx): stored inputs disagree with goldenInputs — regenerate fixture.")

            let classifier = MoodClassifier()
            let result = try classifier.classify(features: entry.inputs)
            #expect(abs(result.valence - entry.valence) < 1e-4,
                    "Entry \(idx): valence \(result.valence) vs golden \(entry.valence)")
            #expect(abs(result.arousal - entry.arousal) < 1e-4,
                    "Entry \(idx): arousal \(result.arousal) vs golden \(entry.arousal)")
        }
    }

    // MARK: - Regeneration helper

    /// Runs the production MoodClassifier on `goldenInputs` and prints the
    /// resulting fixture JSON to stdout. Each input gets its own classifier
    /// instance so the EMA state is the same on regeneration as in `test_*`.
    private func regenerateAndPrintFixture() throws {
        var entries: [GoldenEntry] = []
        for input in Self.goldenInputs {
            let classifier = MoodClassifier()
            let result = try classifier.classify(features: input)
            entries.append(GoldenEntry(
                inputs: input,
                valence: result.valence,
                arousal: result.arousal
            ))
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(entries)
        guard let json = String(data: data, encoding: .utf8) else {
            Issue.record("Could not encode regenerated fixture as UTF-8")
            return
        }
        print("=== UPDATE_MOOD_GOLDEN=1 — paste below into mood_classifier_golden.json ===")
        print(json)
        print("=== END ===")
    }
}
