// FakePreparationProgressPublisher — Test double for PreparationProgressPublishing.
// Allows tests to fire status transitions programmatically.

import Combine
import Foundation
@testable import Session

// MARK: - FakePreparationProgressPublisher

/// Conforms to `PreparationProgressPublishing` for use in ViewModel and integration tests.
///
/// Call `fire(_:for:)` to inject a status transition, then observe `trackStatuses`
/// or subscribe to `trackStatusesPublisher` to verify reactions.
@MainActor
final class FakePreparationProgressPublisher: PreparationProgressPublishing {

    // MARK: - State

    private(set) var trackStatuses: [TrackIdentity: TrackPreparationStatus] = [:]
    private var subject = CurrentValueSubject<[TrackIdentity: TrackPreparationStatus], Never>([:])

    // MARK: - Tracking

    private(set) var cancelCallCount = 0

    // MARK: - PreparationProgressPublishing

    var trackStatusesPublisher: AnyPublisher<[TrackIdentity: TrackPreparationStatus], Never> {
        subject.eraseToAnyPublisher()
    }

    func cancelPreparation() {
        cancelCallCount += 1
    }

    // MARK: - Test Control

    /// Push a status update for a single track, mirroring what SessionPreparer does.
    func fire(_ status: TrackPreparationStatus, for track: TrackIdentity) {
        trackStatuses[track] = status
        subject.send(trackStatuses)
    }

    /// Set the full status dictionary at once (e.g., to initialize all tracks to .queued).
    func setAll(_ statuses: [TrackIdentity: TrackPreparationStatus]) {
        trackStatuses = statuses
        subject.send(trackStatuses)
    }
}
