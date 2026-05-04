// BeatGridResolverTests — DSP.2 S5 unit + golden fixture tests for BeatGridResolver.
//
// Suite A (8 unit tests): synthetic probs → algorithm contracts.
// Suite B (24 golden tests): 6 Beat This! reference fixtures × 4 assertions each.
//   Assertions: ≥95% beats within ±20ms, ≥90% downbeats within ±40ms,
//   BPM within ±0.5 of reference, beatsPerBar matches reference.
//
// Fixtures in Fixtures/beat_this_reference/ — committed to repo, always present.
// Load from bundle via Bundle.module (see Package.swift resources).

import Testing
import Foundation
@testable import DSP

// MARK: - Fixture Type

private struct BeatThisFixture: Decodable {
    let beatLogitsFirst1500: [Double]
    let downbeatLogitsFirst1500: [Double]
    let beatsSeconds: [Double]
    let downbeatsSeconds: [Double]
    let bpmTrimmedMean: Double
    let beatsPerBarEstimate: Int
    let nFrames: Int

    enum CodingKeys: String, CodingKey {
        case beatLogitsFirst1500 = "beat_logits_first1500"
        case downbeatLogitsFirst1500 = "downbeat_logits_first1500"
        case beatsSeconds = "beats_seconds"
        case downbeatsSeconds = "downbeats_seconds"
        case bpmTrimmedMean = "bpm_trimmed_mean"
        case beatsPerBarEstimate = "beats_per_bar_estimate"
        case nFrames = "n_frames"
    }
}

// MARK: - Helpers

private func loadFixture(_ name: String) throws -> BeatThisFixture {
    let url = try #require(
        Bundle.module.url(
            forResource: "\(name)_reference",
            withExtension: "json",
            subdirectory: "beat_this_reference"
        ),
        "\(name)_reference.json not found in bundle"
    )
    let data = try Data(contentsOf: url)
    return try JSONDecoder().decode(BeatThisFixture.self, from: data)
}

private func sigmoid(_ x: Double) -> Float {
    Float(1.0 / (1.0 + Foundation.exp(-x)))
}

private func resolveGrid(from fixture: BeatThisFixture) -> BeatGrid {
    let beatProbs = fixture.beatLogitsFirst1500.map { sigmoid($0) }
    let dbProbs = fixture.downbeatLogitsFirst1500.map { sigmoid($0) }
    return BeatGridResolver.resolve(beatProbs: beatProbs, downbeatProbs: dbProbs, frameRate: 50.0)
}

/// Fraction of `reference` times that have a match in `resolved` within `tolerance` seconds.
private func matchFraction(resolved: [Double], reference: [Double], tolerance: Double) -> Double {
    guard !reference.isEmpty else { return 1.0 }
    let matched = reference.filter { refT in
        resolved.contains { abs($0 - refT) <= tolerance }
    }.count
    return Double(matched) / Double(reference.count)
}

/// Build a Float probability array of `length` with value 1.0 at each frame index in `peaks`.
private func makeProbs(length: Int, peaks: [Int]) -> [Float] {
    var arr = [Float](repeating: 0, count: length)
    for i in peaks where i < length { arr[i] = 1.0 }
    return arr
}

// MARK: - Suite A: Unit Tests

@Suite("BeatGridResolver — Unit")
struct BeatGridResolverUnitTests {

    // MARK: 1. Empty input

    @Test("emptyInput_returnsEmptyGrid")
    func test_emptyInput_returnsEmptyGrid() {
        let grid = BeatGridResolver.resolve(beatProbs: [], downbeatProbs: [], frameRate: 50.0)
        #expect(grid.beats.isEmpty)
        #expect(grid.downbeats.isEmpty)
        #expect(grid.bpm == 0.0)
        #expect(grid.beatsPerBar == 4)   // default when no data
        #expect(grid.frameCount == 0)
    }

    // MARK: 2. All below threshold → no beats

    @Test("singleBeat_belowThreshold_noBeat")
    func test_singleBeat_belowThreshold() {
        let probs = [Float](repeating: 0.4, count: 200)
        let grid = BeatGridResolver.resolve(beatProbs: probs, downbeatProbs: probs, frameRate: 50.0)
        #expect(grid.beats.isEmpty)
    }

    // MARK: 3. Single peak above threshold → 1 beat at correct time

    @Test("singleBeat_aboveThreshold_correctTime")
    func test_singleBeat_aboveThreshold() {
        // Frame 100 at 50fps → 2.0 s
        let probs = makeProbs(length: 200, peaks: [100])
        let grid = BeatGridResolver.resolve(beatProbs: probs, downbeatProbs: [], frameRate: 50.0)
        #expect(grid.beats.count == 1)
        let expected = 100.0 / 50.0   // 2.0 s
        #expect(abs(grid.beats[0] - expected) < 1e-9)
    }

    // MARK: 4. Adjacent frames: lower neighbour suppressed by max-pool

    @Test("maxPool_suppressesNeighbour_onePeakSurvives")
    func test_maxPool_suppressesNeighbour() {
        // Frame 50 = 0.9, frame 51 = 0.7.
        // Frame 51's 7-frame window [48..54] includes frame 50 (0.9) → max=0.9 ≠ 0.7 → suppressed.
        var probs = [Float](repeating: 0, count: 200)
        probs[50] = 0.9
        probs[51] = 0.7
        let grid = BeatGridResolver.resolve(beatProbs: probs, downbeatProbs: [], frameRate: 50.0)
        #expect(grid.beats.count == 1)
        #expect(abs(grid.beats[0] - 50.0 / 50.0) < 1e-9)
    }

    // MARK: 5. Uniform beat spacing → BPM ≈ 120.0

    @Test("bpmCalculation_uniform120bpm")
    func test_bpmCalculation_uniform120bpm() {
        // 21 beats at 25-frame spacing (0.5 s at 50 fps) → BPM = 120.
        // Window length 550 ensures no boundary effects on first/last beats.
        let beatFrames = stride(from: 25, through: 525, by: 25).map { Int($0) }
        let probs = makeProbs(length: 550, peaks: beatFrames)
        let grid = BeatGridResolver.resolve(beatProbs: probs, downbeatProbs: [], frameRate: 50.0)
        #expect(grid.beats.count == beatFrames.count)
        #expect(abs(grid.bpm - 120.0) < 0.01, "BPM was \(grid.bpm)")
    }

    // MARK: 6. beatsPerBar 4/4

    @Test("beatsPerBar_4_4_confidence1")
    func test_beatsPerBar_4_4() {
        // Beats at 25-frame spacing (BPM=120), downbeats at 100-frame spacing (4 beats/bar).
        let beatFrames = stride(from: 25, through: 525, by: 25).map { Int($0) }
        let dbFrames   = stride(from: 25, through: 425, by: 100).map { Int($0) } // 5 downbeats
        let beatProbs = makeProbs(length: 550, peaks: beatFrames)
        let dbProbs   = makeProbs(length: 550, peaks: dbFrames)
        let grid = BeatGridResolver.resolve(beatProbs: beatProbs, downbeatProbs: dbProbs, frameRate: 50.0)
        #expect(grid.beatsPerBar == 4, "Expected 4, got \(grid.beatsPerBar)")
        #expect(abs(Double(grid.barConfidence) - 1.0) < 0.01, "Expected confidence≈1.0, got \(grid.barConfidence)")
    }

    // MARK: 7. beatsPerBar 3/4

    @Test("beatsPerBar_3_4")
    func test_beatsPerBar_3_4() {
        // Beats at 25-frame spacing (BPM=120), downbeats at 75-frame spacing (3 beats/bar).
        let beatFrames = stride(from: 25, through: 525, by: 25).map { Int($0) }
        let dbFrames   = stride(from: 25, through: 375, by: 75).map { Int($0) } // 5 downbeats
        let beatProbs = makeProbs(length: 550, peaks: beatFrames)
        let dbProbs   = makeProbs(length: 550, peaks: dbFrames)
        let grid = BeatGridResolver.resolve(beatProbs: beatProbs, downbeatProbs: dbProbs, frameRate: 50.0)
        #expect(grid.beatsPerBar == 3, "Expected 3, got \(grid.beatsPerBar)")
    }

    // MARK: 8. Downbeat snap: candidate farther than 2 frames (40 ms) is discarded

    @Test("downbeatSnap_discards_farCandidate")
    func test_downbeatSnap_discards_farCandidate() {
        // Beat at frame 50 (1.0 s), downbeat candidate at frame 53 (1.06 s).
        // Distance = 3 frames = 60 ms > 40 ms snap tolerance → candidate discarded.
        let beatProbs = makeProbs(length: 200, peaks: [50])
        let dbProbs   = makeProbs(length: 200, peaks: [53])
        let grid = BeatGridResolver.resolve(beatProbs: beatProbs, downbeatProbs: dbProbs, frameRate: 50.0)
        #expect(grid.beats.count == 1)
        #expect(grid.downbeats.isEmpty, "Expected 0 downbeats (candidate too far), got \(grid.downbeats.count)")
    }
}

// MARK: - Suite B: Golden Fixture Tests

@Suite("BeatGridResolver — Golden")
struct BeatGridResolverGoldenTests {

    static let fixtures = [
        "love_rehab",
        "so_what",
        "there_there",
        "pyramid_song",
        "money",
        "if_i_were_with_her_now",
    ]

    // MARK: Beats within ±20 ms

    @Test("beats_withinTolerance", arguments: fixtures)
    func test_beats_withinTolerance(fixtureName: String) throws {
        let fixture = try loadFixture(fixtureName)
        let grid = resolveGrid(from: fixture)
        let frac = matchFraction(resolved: grid.beats, reference: fixture.beatsSeconds, tolerance: 0.02)
        #expect(frac >= 0.95,
                "\(fixtureName): expected ≥95% beats within ±20ms, got \(String(format: "%.1f", frac * 100))%")
    }

    // MARK: Downbeats within ±40 ms

    @Test("downbeats_withinTolerance", arguments: fixtures)
    func test_downbeats_withinTolerance(fixtureName: String) throws {
        let fixture = try loadFixture(fixtureName)
        let grid = resolveGrid(from: fixture)
        let frac = matchFraction(resolved: grid.downbeats, reference: fixture.downbeatsSeconds, tolerance: 0.04)
        #expect(frac >= 0.90,
                "\(fixtureName): expected ≥90% downbeats within ±40ms, got \(String(format: "%.1f", frac * 100))%")
    }

    // MARK: BPM within ±0.5 of reference

    @Test("bpm_withinTolerance", arguments: fixtures)
    func test_bpm_withinTolerance(fixtureName: String) throws {
        let fixture = try loadFixture(fixtureName)
        let grid = resolveGrid(from: fixture)
        #expect(abs(grid.bpm - fixture.bpmTrimmedMean) < 0.5,
                "\(fixtureName): bpm=\(String(format: "%.2f", grid.bpm)) expected≈\(fixture.bpmTrimmedMean)")
    }

    // MARK: Meter correct (pyramid_song = 3 is the load-bearing gate)

    @Test("meter_correct", arguments: fixtures)
    func test_meter_correct(fixtureName: String) throws {
        let fixture = try loadFixture(fixtureName)
        let grid = resolveGrid(from: fixture)
        #expect(grid.beatsPerBar == fixture.beatsPerBarEstimate,
                "\(fixtureName): beatsPerBar=\(grid.beatsPerBar) expected=\(fixture.beatsPerBarEstimate)")
    }
}
