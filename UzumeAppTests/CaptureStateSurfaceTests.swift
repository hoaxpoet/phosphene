// CaptureStateSurfaceTests — R3.2 (PUB.10): the capture/signal-chain child's
// mutator contract (same recipe as NowPlayingSurfaceTests / R3.1).
//
// No grouped-transition test: unlike NowPlayingSurface's paired publishes,
// this surface has no invariant coupling two fields — the start path sets
// permission alone, and signal state / health arrive on independent
// callbacks (verified in the PUB.10 writer inventory).

import Foundation
import Audio
import Testing
@testable import PhospheneApp

@Suite("CaptureStateSurface")
@MainActor
struct CaptureStateSurfaceTests {

    @Test("defaults match the engine's historical initial values")
    func test_defaults() {
        let surface = CaptureStateSurface()
        #expect(surface.audioSignalState == .active)
        #expect(surface.signalHealth == SignalHealth())
        #expect(surface.hasScreenCapturePermission == false)
    }

    @Test("each mutator publishes its field")
    func test_mutators_publish() {
        let surface = CaptureStateSurface()

        surface.setSignalState(.silent)
        #expect(surface.audioSignalState == .silent)

        var health = SignalHealth()
        health.deadTap = true
        surface.setSignalHealth(health)
        #expect(surface.signalHealth.deadTap == true)

        surface.setScreenCapturePermission(true)
        #expect(surface.hasScreenCapturePermission == true)
    }

    @Test("mutations emit objectWillChange for the engine bridge")
    func test_objectWillChange_emits() {
        let surface = CaptureStateSurface()
        var changes = 0
        let cancellable = surface.objectWillChange.sink { _ in changes += 1 }

        surface.setSignalState(.silent)
        surface.setScreenCapturePermission(true)
        #expect(changes == 2)
        _ = cancellable
    }
}
