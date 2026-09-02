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

    /// What Uzume heard, per track, once that track is `.ready` (DS.4).
    ///
    /// A track appears here at the same moment its status becomes `.ready` — from fresh
    /// analysis, from a cache hit, or from the local-file path — and never before. Failed
    /// and partial tracks have no entry. Reset to empty at the start of every preparation
    /// pass, so a value never leaks across sessions.
    var trackProfiles: [TrackIdentity: TrackProfile] { get }

    /// Publisher that fires on every profile dictionary change. Emits on the main actor.
    var trackProfilesPublisher: AnyPublisher<[TrackIdentity: TrackProfile], Never> { get }

    /// Cancel the in-flight preparation pass.
    ///
    /// Cancels the underlying Task. Already-processed tracks retain their status; unprocessed
    /// tracks stay at `.queued`. The caller (SessionManager) is responsible for transitioning
    /// session state to `.idle` after calling this.
    func cancelPreparation()
}

// MARK: - Defaults

extension PreparationProgressPublishing {
    /// Publishers that carry only statuses (test doubles written before DS.4) expose no
    /// profiles: an empty dictionary and a publisher that never emits.
    public var trackProfiles: [TrackIdentity: TrackProfile] { [:] }
    public var trackProfilesPublisher: AnyPublisher<[TrackIdentity: TrackProfile], Never> {
        Empty(completeImmediately: false).eraseToAnyPublisher()
    }
}
