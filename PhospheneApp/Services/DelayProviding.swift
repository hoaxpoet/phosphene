// DelayProviding — Protocol for injectable sleep, making retry logic unit-testable.

import Foundation

// MARK: - DelayProviding

/// Abstracts `Task.sleep` so retry loops can be tested without real wall-clock delays.
protocol DelayProviding: Sendable {
    func sleep(seconds: Double) async throws
}

// MARK: - RealDelay

/// Production delay: delegates to `Task.sleep(for:)`.
struct RealDelay: DelayProviding {
    func sleep(seconds: Double) async throws {
        try await Task.sleep(for: .seconds(seconds))
    }
}

// MARK: - InstantDelay

/// Test double: 1 ms sleep — a true suspension point that lets scheduled tasks run.
/// `Task.yield()` is unreliable as a sleep substitute on serial executors (@MainActor).
struct InstantDelay: DelayProviding {
    func sleep(seconds: Double) async throws {
        try await Task.sleep(for: .milliseconds(1))
    }
}
