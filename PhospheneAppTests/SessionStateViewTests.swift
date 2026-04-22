// SessionStateViewTests — Verifies SessionStateViewModel observation and
// ContentView/view routing for all six session states.
//
// ViewModel tests (.idle, .playing, state propagation) exercise the Combine
// bridging layer directly — no rendering needed.
//
// ContentView routing tests verify (a) that the ViewModel reaches each
// synchronously-reachable state and (b) that each state's target view
// declares the expected accessibilityID constant. ContentView's routing is
// a plain switch statement whose exhaustiveness is enforced by the compiler;
// these tests guard against accidental identifier drift.
//
// View identifier tests verify the static accessibilityID constant on the
// three views whose states (.connecting, .preparing, .ready) are only reachable
// via the async startSession() path. Checking the constant is sufficient: each
// view applies .accessibilityIdentifier(Self.accessibilityID) in its body, so
// the constant and the modifier stay in sync by construction.
//
// No snapshot testing, no third-party dependencies.

import AppKit
import Audio
import Combine
import DSP
import Metal
import Session
import Shared
import SwiftUI
import Testing
@testable import PhospheneApp

// MARK: - ViewModel Tests

@Suite("SessionStateViewModel")
@MainActor
struct SessionStateViewModelTests {

    @Test("mirrors initial SessionManager state")
    func mirrorsInitialState() throws {
        let manager = SessionManager.testInstance()
        let vm = SessionStateViewModel(sessionManager: manager)
        #expect(vm.state == .idle)
    }

    @Test("reflects SessionManager state changes")
    func reflectsStateChanges() async throws {
        let manager = SessionManager.testInstance()
        let vm = SessionStateViewModel(sessionManager: manager)
        #expect(vm.state == .idle)

        manager.startAdHocSession()
        // Combine receive(on: DispatchQueue.main) needs a run-loop turn.
        try await Task.sleep(for: .milliseconds(50))
        #expect(vm.state == .playing)
    }

    @Test("reduceMotion matches NSWorkspace at init")
    func reduceMotionMatchesWorkspace() {
        let manager = SessionManager.testInstance()
        let vm = SessionStateViewModel(sessionManager: manager)
        #expect(vm.reduceMotion == NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }
}

// MARK: - ContentView Routing Tests (synchronously-reachable states)
//
// Tests (a) that the ViewModel reaches the expected state and (b) that
// the routed view carries the correct accessibilityID constant.

@Suite("ContentView routing")
@MainActor
struct ContentViewRoutingTests {

    @Test("idle state routes to IdleView")
    func idleState() {
        let vm = SessionStateViewModel(sessionManager: SessionManager.testInstance())
        #expect(vm.state == .idle)
        #expect(IdleView.accessibilityID == "phosphene.view.idle")
    }

    @Test("ended state routes to EndedView")
    func endedState() {
        let manager = SessionManager.testInstance()
        manager.endSession()
        let vm = SessionStateViewModel(sessionManager: manager)
        #expect(vm.state == .ended)
        #expect(EndedView.accessibilityID == "phosphene.view.ended")
    }

    @Test("playing state routes to PlaybackView")
    func playingState() async throws {
        let manager = SessionManager.testInstance()
        let vm = SessionStateViewModel(sessionManager: manager)
        manager.startAdHocSession()
        try await Task.sleep(for: .milliseconds(50))
        #expect(vm.state == .playing)
        #expect(PlaybackView.accessibilityID == "phosphene.view.playing")
    }
}

// MARK: - View Identifier Tests (async-only-reachable states)
//
// .connecting, .preparing, and .ready can only be reached by SessionManager
// via the async startSession(source:) path. These tests verify the views
// themselves declare the correct accessibilityID constants so ContentView
// routing would deliver the right identifier once those states are reachable.

@Suite("View identifiers")
@MainActor
struct ViewIdentifierTests {

    @Test("ConnectingView carries correct identifier")
    func connectingViewIdentifier() {
        #expect(ConnectingView.accessibilityID == "phosphene.view.connecting")
    }

    @Test("PreparationProgressView carries correct identifier")
    func preparingViewIdentifier() {
        #expect(PreparationProgressView.accessibilityID == "phosphene.view.preparing")
    }

    @Test("ReadyView carries correct identifier")
    func readyViewIdentifier() {
        #expect(ReadyView.accessibilityID == "phosphene.view.ready")
    }
}

// MARK: - SessionManager Test Factory

extension SessionManager {
    /// Create a minimal `SessionManager` for unit tests.
    /// Uses stubs — no network, no ML, no Metal setup.
    @MainActor
    static func testInstance() -> SessionManager {
        SessionManager(
            connector: StubPlaylistConnector(),
            preparer: SessionPreparer(
                resolver: StubPreviewResolver(),
                downloader: StubPreviewDownloader(),
                stemSeparator: StubStemSeparator(),
                stemAnalyzer: StubStemAnalyzer(),
                moodClassifier: StubMoodClassifier()
            )
        )
    }
}

// MARK: - Stub Dependencies

private final class StubPlaylistConnector: PlaylistConnecting, @unchecked Sendable {
    func connect(source: PlaylistSource) async throws -> [TrackIdentity] { [] }
}

private final class StubPreviewResolver: PreviewResolving, @unchecked Sendable {
    func resolvePreviewURL(for track: TrackIdentity) async throws -> URL? { nil }
}

private final class StubPreviewDownloader: PreviewDownloading, @unchecked Sendable {
    func download(track: TrackIdentity, from url: URL) async -> PreviewAudio? { nil }
    func batchDownload(tracks: [(TrackIdentity, URL)]) async -> [PreviewAudio] { [] }
}

private final class StubStemSeparator: StemSeparating, @unchecked Sendable {
    let stemLabels = ["vocals", "drums", "bass", "other"]
    var stemBuffers: [UMABuffer<Float>] { [] }
    func separate(audio: [Float], channelCount: Int, sampleRate: Float) throws -> StemSeparationResult {
        throw StemSeparationError.modelNotFound
    }
}

private final class StubStemAnalyzer: StemAnalyzing, @unchecked Sendable {
    func analyze(stemWaveforms: [[Float]], fps: Float) -> StemFeatures { StemFeatures() }
    func reset() {}
}

private final class StubMoodClassifier: MoodClassifying, @unchecked Sendable {
    var currentState: EmotionalState = .neutral
    func classify(features: [Float]) throws -> EmotionalState { .neutral }
}
