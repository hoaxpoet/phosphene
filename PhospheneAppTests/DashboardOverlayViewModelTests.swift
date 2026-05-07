// DashboardOverlayViewModelTests — Subscription, throttle, history-buffer
// behaviour for the SwiftUI dashboard view model (DASH.7).

import Combine
import Foundation
import Testing
@testable import PhospheneApp
@testable import Renderer
@testable import Shared

@MainActor
@Suite("DashboardOverlayViewModel")
struct DashboardOverlayViewModelTests {

    // MARK: - Helpers

    private static func snapshot(drums: Float = 0.3, bpm: Float = 125) -> DashboardSnapshot {
        var stems = StemFeatures.zero
        stems.drumsEnergyRel = drums
        stems.bassEnergyRel = 0.1
        stems.vocalsEnergyRel = -0.1
        stems.otherEnergyRel = 0.05
        let beat = BeatSyncSnapshot(
            barPhase01: 0.25,
            beatsPerBar: 4,
            beatInBar: 2,
            isDownbeat: false,
            sessionMode: 3,
            lockState: 2,
            gridBPM: bpm,
            playbackTimeS: 1.0,
            driftMs: 5.0
        )
        return DashboardSnapshot(beat: beat, stems: stems, perf: .zero)
    }

    private static func makeViewModel() -> DashboardOverlayViewModel {
        DashboardOverlayViewModel(snapshotPublisher: Just(nil).eraseToAnyPublisher())
    }

    // MARK: - Tests

    @Test("ingest updates layouts to three cards: BEAT / STEMS / PERF")
    func ingestProducesThreeLayouts() {
        let vm = Self.makeViewModel()
        vm.ingestForTest(Self.snapshot())
        #expect(vm.layouts.count == 3)
        #expect(vm.layouts[0].title == "BEAT")
        #expect(vm.layouts[1].title == "STEMS")
        #expect(vm.layouts[2].title == "PERF")
    }

    @Test("STEMS layout reflects the stem-energy history accumulated over multiple ingests")
    func stemHistoryAccumulates() throws {
        let vm = Self.makeViewModel()
        vm.ingestForTest(Self.snapshot(drums: 0.1))
        vm.ingestForTest(Self.snapshot(drums: 0.4))
        vm.ingestForTest(Self.snapshot(drums: 0.7))

        let stems = vm.layouts[1]
        guard case let .timeseries(_, samples, _, valueText, _) = stems.rows[0] else {
            Issue.record("Expected DRUMS .timeseries row")
            return
        }
        #expect(samples.count == 3)
        #expect(samples == [0.1, 0.4, 0.7])
        #expect(valueText == "+0.70")
    }

    @Test("history capacity caps stem sample arrays at StemEnergyHistory.capacity")
    func historyCapacityCap() throws {
        let vm = Self.makeViewModel()
        for i in 0..<(StemEnergyHistory.capacity + 5) {
            vm.ingestForTest(Self.snapshot(drums: Float(i)))
        }
        let stems = vm.layouts[1]
        guard case let .timeseries(_, samples, _, _, _) = stems.rows[0] else {
            Issue.record("Expected DRUMS .timeseries row")
            return
        }
        #expect(samples.count == StemEnergyHistory.capacity)
        // Oldest five samples were evicted; the most-recent sample is preserved.
        #expect(samples.last == Float(StemEnergyHistory.capacity + 4))
    }

    @Test("BEAT layout BPM reflects each ingested snapshot's gridBPM")
    func beatBPMReflectsSnapshot() throws {
        let vm = Self.makeViewModel()
        vm.ingestForTest(Self.snapshot(bpm: 125))
        // BPM row is index 1 (after MODE) and `.singleValue`.
        guard case let .singleValue(_, value, _) = vm.layouts[0].rows[1] else {
            Issue.record("Expected BPM .singleValue row")
            return
        }
        #expect(value == "125")
    }

    @Test("nil snapshots from publisher are filtered out — no crash, no layouts")
    func nilSnapshotIgnored() {
        let vm = Self.makeViewModel()  // publisher is Just(nil); compactMap drops nil.
        #expect(vm.layouts.isEmpty)
    }
}
