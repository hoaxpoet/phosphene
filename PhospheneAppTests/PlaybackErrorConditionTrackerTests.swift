// PlaybackErrorConditionTrackerTests — Tests for PlaybackErrorConditionTracker (U.7 Part C).
//
// Tests:
//   1. isAsserted returns false initially.
//   2. assert(_:) marks condition as asserted.
//   3. clear(_:) removes the assertion.
//   4. reset() clears all conditions.

import Foundation
import Testing
@testable import PhospheneApp

@Suite("PlaybackErrorConditionTracker")
@MainActor
struct PlaybackErrorConditionTrackerTests {

    @Test("isAsserted returns false initially")
    func test_initiallyNotAsserted() {
        let tracker = PlaybackErrorConditionTracker()
        #expect(tracker.isAsserted("silence.extended") == false)
    }

    @Test("assert marks condition as asserted")
    func test_assert_marksAsserted() {
        let tracker = PlaybackErrorConditionTracker()
        tracker.assert("silence.extended")
        #expect(tracker.isAsserted("silence.extended") == true)
    }

    @Test("clear removes the assertion")
    func test_clear_removesAssertion() {
        let tracker = PlaybackErrorConditionTracker()
        tracker.assert("silence.extended")
        tracker.clear("silence.extended")
        #expect(tracker.isAsserted("silence.extended") == false)
    }

    @Test("reset clears all conditions")
    func test_reset_clearsAll() {
        let tracker = PlaybackErrorConditionTracker()
        tracker.assert("silence.extended")
        tracker.assert("audio.levels.low")
        tracker.reset()
        #expect(tracker.isAsserted("silence.extended") == false)
        #expect(tracker.isAsserted("audio.levels.low") == false)
    }
}
