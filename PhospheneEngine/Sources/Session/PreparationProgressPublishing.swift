// PreparationProgressPublishing — Protocol for per-track session preparation progress.
// Implemented by SessionPreparer. Consumed by PreparationProgressViewModel in the app layer.
// All members are @MainActor-isolated to match SessionPreparer's isolation domain.

import Combine
import Foundation

// MARK: - PreparationProgressPublishing

/// Exposes per-track preparation status to the UI without leaking SessionPreparer internals.
///
/// Conformers must be `AnyObject` (class) because the protocol uses `@Published` patterns
/// backed by Combine. `SessionPreparer` is the only production conformer; tests use
/// `MockPreparationProgressPublisher`.
@MainActor
public protocol PreparationProgressPublishing: AnyObject {

    /// Current preparation status keyed by track identity.
    ///
    /// All tracks in the session are present from the start of preparation (initially `.queued`).
    /// Never nil — empty dictionary before `prepare(tracks:)` is called.
    var trackStatuses: [TrackIdentity: TrackPreparationStatus] { get }

    /// Publisher that fires on every status dictionary change.
    ///
    /// Emits on the main actor. Values are the complete dictionary snapshot after each update.
    var trackStatusesPublisher: AnyPublisher<[TrackIdentity: TrackPreparationStatus], Never> { get }

    /// Cancel the in-flight preparation pass.
    ///
    /// Cancels the underlying Task. Already-processed tracks retain their status; unprocessed
    /// tracks stay at `.queued`. The caller (SessionManager) is responsible for transitioning
    /// session state to `.idle` after calling this.
    func cancelPreparation()
}
