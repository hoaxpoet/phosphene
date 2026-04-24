// TrackPreparationStatusTests — Unit tests for TrackPreparationStatus Equatable conformance,
// associated value comparison, and derived property correctness.

import Testing
@testable import Session

// MARK: - Suite

@Suite("TrackPreparationStatus")
struct TrackPreparationStatusTests {

    // MARK: - Equatable

    @Test func equatable_sameCases_areEqual() {
        #expect(TrackPreparationStatus.queued == .queued)
        #expect(TrackPreparationStatus.resolving == .resolving)
        #expect(TrackPreparationStatus.ready == .ready)
    }

    @Test func equatable_differentDownloadProgress_areNotEqual() {
        let a = TrackPreparationStatus.downloading(progress: 0.3)
        let b = TrackPreparationStatus.downloading(progress: 0.7)
        #expect(a != b)
    }

    @Test func equatable_sameDownloadProgress_areEqual() {
        let a = TrackPreparationStatus.downloading(progress: 0.5)
        let b = TrackPreparationStatus.downloading(progress: 0.5)
        #expect(a == b)
    }

    @Test func equatable_partialReason_preservedAcrossEquality() {
        let a = TrackPreparationStatus.partial(reason: "Stems unavailable")
        let b = TrackPreparationStatus.partial(reason: "Stems unavailable")
        let c = TrackPreparationStatus.partial(reason: "Other reason")
        #expect(a == b)
        #expect(a != c)
    }

    @Test func equatable_differentAnalysisStages_areNotEqual() {
        let stemSep = TrackPreparationStatus.analyzing(stage: .stemSeparation)
        let mir = TrackPreparationStatus.analyzing(stage: .mir)
        let caching = TrackPreparationStatus.analyzing(stage: .caching)
        #expect(stemSep != mir)
        #expect(mir != caching)
        #expect(stemSep != caching)
        #expect(stemSep == .analyzing(stage: .stemSeparation))
    }

    @Test func equatable_failedReason_preservedAcrossEquality() {
        let a = TrackPreparationStatus.failed(reason: "Preview not available")
        let b = TrackPreparationStatus.failed(reason: "Preview not available")
        let c = TrackPreparationStatus.failed(reason: "Download failed")
        #expect(a == b)
        #expect(a != c)
    }

    // MARK: - isTerminal

    @Test func isTerminal_readyPartialFailed_areTerminal() {
        #expect(TrackPreparationStatus.ready.isTerminal)
        #expect(TrackPreparationStatus.partial(reason: "x").isTerminal)
        #expect(TrackPreparationStatus.failed(reason: "x").isTerminal)
    }

    @Test func isTerminal_inFlightStatuses_areNotTerminal() {
        #expect(!TrackPreparationStatus.queued.isTerminal)
        #expect(!TrackPreparationStatus.resolving.isTerminal)
        #expect(!TrackPreparationStatus.downloading(progress: -1).isTerminal)
        #expect(!TrackPreparationStatus.analyzing(stage: .stemSeparation).isTerminal)
    }

    // MARK: - isInFlight

    @Test func isInFlight_resolvingDownloadingAnalyzing_areInFlight() {
        #expect(TrackPreparationStatus.resolving.isInFlight)
        #expect(TrackPreparationStatus.downloading(progress: 0.5).isInFlight)
        #expect(TrackPreparationStatus.analyzing(stage: .mir).isInFlight)
    }

    @Test func isInFlight_queuedAndTerminal_areNotInFlight() {
        #expect(!TrackPreparationStatus.queued.isInFlight)
        #expect(!TrackPreparationStatus.ready.isInFlight)
        #expect(!TrackPreparationStatus.partial(reason: "x").isInFlight)
        #expect(!TrackPreparationStatus.failed(reason: "x").isInFlight)
    }
}
