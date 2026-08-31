// VisualizerEngine+TrackIdentityResolution — BUG-006.2 fix (cause 2).
//
// Streaming metadata (Apple Music / Spotify Now Playing AppleScript) only
// carries `title` + `artist`. The `PlannedSession` was constructed by
// `SessionPreparer` from full Spotify-API identities (which include
// `duration`, `spotifyID`, and the `spotifyPreviewURL` hint). A partial
// identity hashes differently, so the cache lookup misses even when
// preparation succeeded — and the prepared `BeatGrid` never installs.
//
// `canonicalTrackIdentity(matching:)` resolves a partial title+artist pair
// against the live plan when one is present, returning the planned identity
// (which is the cache key `SessionPreparer.store(_:for:)` used). Falls back
// to `nil` for ad-hoc / reactive sessions and for ambiguous matches so we
// never pin the wrong cache entry.

import Foundation
import Orchestrator
import Session
import Shared

extension VisualizerEngine {

    /// Resolve the canonical `TrackIdentity` from the live plan when one is
    /// present and the title+artist pair matches uniquely.
    ///
    /// Returns `nil` when:
    /// - `livePlan` is nil (ad-hoc / reactive session — preserves existing
    ///   reactive behaviour),
    /// - no planned track matches the partial identity, or
    /// - more than one planned track matches (ambiguity — caller falls back
    ///   to the partial identity, deferring to the live Beat This! path
    ///   rather than risking the wrong cached grid).
    ///
    /// Thread-safe: acquires `orchestratorLock`. Delegates the search to
    /// `PlannedSession.canonicalIdentity(matchingTitle:artist:)` so the
    /// matching algorithm itself is testable from `PhospheneEngineTests`.
    func canonicalTrackIdentity(matching partial: TrackIdentity) -> TrackIdentity? {
        let plan = orchestratorLock.withLock { livePlan }
        return plan?.canonicalIdentity(matchingTitle: partial.title, artist: partial.artist)
    }
}
