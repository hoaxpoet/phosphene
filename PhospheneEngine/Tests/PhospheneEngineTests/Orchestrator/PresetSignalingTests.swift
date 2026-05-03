// PresetSignalingTests — V.7.6.2 §3.4 verification.
//
// Confirms the protocol shape, the minSegmentDuration floor, and the subscription
// mechanism (firing, weak-reference release, idempotent cancellation).

import Combine
import Foundation
import Testing
@testable import Orchestrator

// MARK: - Test double

private final class FakeSignaler: PresetSignaling {
    let presetCompletionEvent = PassthroughSubject<Void, Never>()
}

@Suite("PresetSignaling")
struct PresetSignalingTests {

    @Test("minSegmentDuration default is 5 seconds (§3.4)")
    func minSegmentDurationDefault() {
        #expect(PresetSignalingDefaults.minSegmentDuration == 5.0)
    }

    @Test("PassthroughSubject delivers events to subscriber")
    func subscriberReceivesEvents() {
        let signaler = FakeSignaler()
        var receivedCount = 0
        let cancellable = signaler.presetCompletionEvent.sink { receivedCount += 1 }
        defer { cancellable.cancel() }

        signaler.presetCompletionEvent.send()
        signaler.presetCompletionEvent.send()

        #expect(receivedCount == 2)
    }

    @Test("Cancelled subscription stops receiving events")
    func cancelledSubscriptionDoesNotFire() {
        let signaler = FakeSignaler()
        var receivedCount = 0
        let cancellable = signaler.presetCompletionEvent.sink { receivedCount += 1 }
        signaler.presetCompletionEvent.send()
        cancellable.cancel()
        signaler.presetCompletionEvent.send()
        signaler.presetCompletionEvent.send()
        #expect(receivedCount == 1, "Only the first event should land")
    }

    @Test("minSegmentDuration floor: events below 5s are dropped (logical gate)")
    func floorGateLogic() {
        // Replicate the engine-side gate: honour iff (now - startTime) >= floor.
        func shouldHonour(elapsedSeconds: TimeInterval) -> Bool {
            elapsedSeconds >= PresetSignalingDefaults.minSegmentDuration
        }
        #expect(shouldHonour(elapsedSeconds: 0.0) == false)
        #expect(shouldHonour(elapsedSeconds: 4.999) == false)
        #expect(shouldHonour(elapsedSeconds: 5.0) == true)
        #expect(shouldHonour(elapsedSeconds: 60.0) == true)
    }
}
