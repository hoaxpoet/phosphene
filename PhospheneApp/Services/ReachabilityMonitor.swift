// ReachabilityMonitor — Lightweight network reachability via NWPathMonitor.
//
// Debounces state transitions at 1 second to avoid flapping on brief loss events.
// Used by PreparationErrorViewModel to detect offline conditions during preparation.
//
// If NWPathMonitor is unavailable in tests, swap with the protocol-based stub below.

import Combine
import Foundation
import Network
import os.log

private let logger = Logger(subsystem: "com.phosphene.app", category: "ReachabilityMonitor")

// MARK: - ReachabilityPublishing

/// Protocol for injectable reachability in tests.
@MainActor
protocol ReachabilityPublishing: AnyObject {
    var isOnlinePublisher: AnyPublisher<Bool, Never> { get }
    var isOnline: Bool { get }
}

// MARK: - ReachabilityMonitor

/// Wraps `NWPathMonitor` and publishes `isOnline` with 1-second debounce.
@MainActor
final class ReachabilityMonitor: ObservableObject, ReachabilityPublishing {

    // MARK: - Published

    @Published private(set) var isOnline: Bool = true

    var isOnlinePublisher: AnyPublisher<Bool, Never> {
        $isOnline.eraseToAnyPublisher()
    }

    // MARK: - Private

    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.phosphene.reachability")
    private var debounceTask: Task<Void, Never>?

    // MARK: - Init / Deinit

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let satisfied = path.status == .satisfied
            Task { @MainActor [weak self] in
                self?.handlePathChange(isOnline: satisfied)
            }
        }
        monitor.start(queue: monitorQueue)
    }

    deinit {
        monitor.cancel()
    }

    // MARK: - Private

    private func handlePathChange(isOnline: Bool) {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, let self else { return }
            if self.isOnline != isOnline {
                self.isOnline = isOnline
                logger.info("ReachabilityMonitor: isOnline → \(isOnline)")
            }
        }
    }
}

// MARK: - StubReachabilityMonitor (for tests)

/// Stub that allows tests to control reachability without NWPathMonitor.
final class StubReachabilityMonitor: ReachabilityPublishing {
    private let subject: CurrentValueSubject<Bool, Never>

    var isOnline: Bool {
        get { subject.value }
        set { subject.send(newValue) }
    }

    var isOnlinePublisher: AnyPublisher<Bool, Never> {
        subject.eraseToAnyPublisher()
    }

    init(initialValue: Bool = true) {
        subject = CurrentValueSubject(initialValue)
    }
}
