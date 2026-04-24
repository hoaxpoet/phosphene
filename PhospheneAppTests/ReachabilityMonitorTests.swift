// ReachabilityMonitorTests — Unit tests for StubReachabilityMonitor.
//
// Tests:
//   1. StubReachabilityMonitor starts with the given initial value.
//   2. Toggling isOnline emits the new value to subscribers.
//   3. isOnlinePublisher replays the current value to new subscribers.

import Combine
import Testing
@testable import PhospheneApp

// MARK: - Suite

@MainActor
@Suite("ReachabilityMonitor")
struct ReachabilityMonitorTests {

    @Test("StubReachabilityMonitor initialises with provided value")
    func test_stub_initialValue() {
        let stub = StubReachabilityMonitor(initialValue: false)
        #expect(stub.isOnline == false)
    }

    @Test("toggling isOnline emits new value to publisher")
    func test_stub_emitsOnChange() {
        let stub = StubReachabilityMonitor(initialValue: true)
        var received: [Bool] = []
        var cancellables = Set<AnyCancellable>()
        stub.isOnlinePublisher
            .dropFirst()  // skip initial
            .sink { received.append($0) }
            .store(in: &cancellables)

        stub.isOnline = false
        stub.isOnline = true

        #expect(received == [false, true])
    }

    @Test("isOnlinePublisher replays current value to new subscriber")
    func test_stub_replaysCurrent() {
        let stub = StubReachabilityMonitor(initialValue: false)
        var received: Bool?
        var cancellables = Set<AnyCancellable>()
        stub.isOnlinePublisher
            .first()
            .sink { received = $0 }
            .store(in: &cancellables)

        #expect(received == false)
    }
}
