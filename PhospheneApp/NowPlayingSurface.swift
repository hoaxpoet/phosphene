// NowPlayingSurface — the now-playing chrome state, extracted from
// VisualizerEngine (R3.1 / PUB.9, CLEAN Phase 8 / ultra-review R3).
//
// The four SwiftUI surfaces every playback view binds to (track metadata,
// artwork bytes, plan index, pre-fetched profile) get ONE owner with
// `private(set)` publication and semantic mutators. This structurally closes
// the BUG-024 write-without-clear class for these fields: a path can no
// longer scribble one field and forget its siblings — publishes are paired
// (`publishTrack` sets title + index together per the currentTrackArtworkData
// invariant), and the session-boundary clear is a single method instead of a
// convention.
//
// Threading: main-thread only (SwiftUI @Published writes), enforced by
// dispatchPrecondition — the same contract style as applyPreset (PUB.5).
// VisualizerEngine bridges this object's objectWillChange into its own so
// existing `@EnvironmentObject var engine` observers keep re-rendering.

import Combine
import Foundation
import Session
import Shared

// MARK: - NowPlayingSurface

/// Single owner of the now-playing chrome surface. See file header.
final class NowPlayingSurface: ObservableObject {

    // MARK: - Published surface (read-only outside; mutate via the methods below)

    /// Current track metadata from Now Playing.
    @Published private(set) var currentTrack: TrackMetadata?

    /// Raw album-artwork bytes for the live track (PNG / JPEG). LF sessions
    /// populate it from the LF.5 persistent cache's `artwork.bin` sibling;
    /// streaming via the LF.6.streaming `StreamingArtworkPublisher` chain.
    ///
    /// **Invariant (BUG-024):** written in the same MainActor tick as
    /// `currentTrack` where possible — title-first, artwork-second — so chrome
    /// consumers binding to both never render the previous track's artwork
    /// against the new track's title.
    @Published private(set) var currentTrackArtworkData: Data?

    /// 0-based index of the live track within the planned session, or nil
    /// when the track is not in the plan (covers/remasters) or no plan exists
    /// (QR.4 / D-091).
    @Published private(set) var currentTrackIndex: Int?

    /// Pre-fetched profile from external APIs (BPM/key/genre hints).
    @Published private(set) var preFetchedProfile: PreFetchedTrackProfile?

    // MARK: - Mutators (main-thread only)

    /// Publish a new track's chrome in one tick: metadata + plan index
    /// together (the paired-publish half of the BUG-024 rule). Pass
    /// `clearArtwork: true` on per-track boundaries where the new artwork
    /// arrives asynchronously, so the old track's art never dresses the new
    /// title; pass `artwork:` directly when the bytes are already in hand
    /// (the LF cache path).
    func publishTrack(
        _ track: TrackMetadata?,
        index: Int?,
        artwork: Data?? = nil
    ) {
        dispatchPrecondition(condition: .onQueue(.main))
        currentTrack = track
        currentTrackIndex = index
        if let artwork { currentTrackArtworkData = artwork }
    }

    /// Update only the plan index (the orchestrator's plan walk resolves it
    /// after the metadata publish on the streaming path).
    func setTrackIndex(_ index: Int?) {
        dispatchPrecondition(condition: .onQueue(.main))
        currentTrackIndex = index
    }

    /// Artwork bytes arriving asynchronously (streaming fetch completion).
    func setArtwork(_ data: Data?) {
        dispatchPrecondition(condition: .onQueue(.main))
        currentTrackArtworkData = data
    }

    /// Pre-fetched external profile for the live track (or nil to drop a
    /// stale one — required on LF track publishes so a streaming profile
    /// can't suppress live key/BPM, PUB.2).
    func setProfile(_ profile: PreFetchedTrackProfile?) {
        dispatchPrecondition(condition: .onQueue(.main))
        preFetchedProfile = profile
    }

    /// THE session-boundary clear (PUB.2's clearSessionScopedSurfaces, now a
    /// single owner-side method): every surface drops in one tick so no
    /// consumer observes a half-cleared surface.
    func clear() {
        dispatchPrecondition(condition: .onQueue(.main))
        currentTrack = nil
        currentTrackArtworkData = nil
        currentTrackIndex = nil
        preFetchedProfile = nil
    }
}
