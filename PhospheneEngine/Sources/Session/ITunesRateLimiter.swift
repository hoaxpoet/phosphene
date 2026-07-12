// ITunesRateLimiter — one shared sliding-window rate limit for ALL
// itunes.apple.com traffic (PUB.6, ultra-review).
//
// Previously PreviewResolver ran its own 20/min window while the app's
// ITunesSearchFetcher (metadata pre-fetch) had NO throttle at all — combined
// traffic could exceed the API's 20 req/min and trip 429s mid-preparation.
// Both clients now acquire from one process-wide window (`.shared`); tests
// inject private instances for isolation.

import Foundation
import Shared

// MARK: - ITunesRateLimiter

/// Sliding-window request limiter. `acquire()` suspends the caller until a
/// slot is free, then records the request timestamp.
public final class ITunesRateLimiter: @unchecked Sendable {

    /// The process-wide window every production itunes.apple.com caller shares.
    public static let shared = ITunesRateLimiter()

    private let lock = NSLock()
    private var requestTimestamps: [Date] = []
    private var _maxRequestsPerWindow: Int
    private var _window: TimeInterval

    /// Maximum requests allowed within `window`. Defaults to 20 (iTunes limit).
    public var maxRequestsPerWindow: Int {
        get { lock.withLock { _maxRequestsPerWindow } }
        set { lock.withLock { _maxRequestsPerWindow = newValue } }
    }

    /// Sliding-window length in seconds. Defaults to 60.
    public var window: TimeInterval {
        get { lock.withLock { _window } }
        set { lock.withLock { _window = newValue } }
    }

    public init(maxRequestsPerWindow: Int = 20, window: TimeInterval = 60.0) {
        self._maxRequestsPerWindow = maxRequestsPerWindow
        self._window = window
    }

    /// Suspends the caller if the window is full, then records the timestamp.
    /// (Verbatim algorithm from PreviewResolver.throttle(), extracted at PUB.6.)
    public func acquire() async {
        while true {
            let waitTime: TimeInterval = lock.withLock {
                let now = Date()
                let windowStart = now.addingTimeInterval(-_window)
                requestTimestamps.removeAll { $0 <= windowStart }

                if requestTimestamps.count >= _maxRequestsPerWindow,
                   let oldest = requestTimestamps.first {
                    let waitUntil = oldest.addingTimeInterval(_window)
                    return max(0.001, waitUntil.timeIntervalSince(now))
                }
                requestTimestamps.append(now)
                return 0
            }

            guard waitTime > 0 else { return }
            try? await Task.sleep(nanoseconds: UInt64(waitTime * 1_000_000_000))
        }
    }
}
