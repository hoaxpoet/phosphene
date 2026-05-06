// VisualizerEngine+WiringLogs — BUG-006.1 instrumentation helpers.
// Source-tagged `WIRING:` log helpers for diagnosing the prepared-BeatGrid
// wiring path. Hypothesis disambiguation per docs/QUALITY/KNOWN_ISSUES.md:
// (1) _buildPlan not running on Spotify path; (2) engine.stemCache never
// assigned; (3) SessionPreparer storing empty grids; (4) cache key mismatch;
// (5) track-change/cache-attach race.
//
// Pure logging — no behaviour changes. Each helper writes once to
// sessionRecorder?.log (lands in session.log) and once via os.Logger.

import Audio
import Foundation
import os.log
import Session
import Shared

private let wiringLogger = Logger(subsystem: "com.phosphene.app", category: "VisualizerEngine.Wiring")

/// BUG-006.1 instrumentation: identifies which call site invoked
/// `resetStemPipeline(for:caller:)`. Used in `WIRING:` logs to disambiguate
/// the pre-fire (planner) path from the track-change path.
enum ResetStemPipelineCaller: String {
    case preFire        // _buildPlan() pre-fires for first planned track
    case trackChange    // streaming-metadata track-change observed
    case other          // any future call site
}

extension VisualizerEngine {

    @MainActor
    func logWiringBuildPlanEnter() {
        let trackCount = sessionManager.currentPlan?.tracks.count ?? 0
        let cacheState = stemCache.map { "present(\($0.count))" } ?? "nil"
        let mgrCacheCount = sessionManager.cache.count
        let msg = "WIRING: _buildPlan ENTER trackCount=\(trackCount) " +
            "engine.stemCache=\(cacheState) sessionManager.cache.count=\(mgrCacheCount)"
        sessionRecorder?.log(msg)
        wiringLogger.info("\(msg, privacy: .public)")
    }

    func logWiringBuildPlanEarlyReturn(reason: String) {
        let msg = "WIRING: _buildPlan EARLY-RETURN reason='\(reason)'"
        sessionRecorder?.log(msg)
        wiringLogger.info("\(msg, privacy: .public)")
    }

    func logWiringBuildPlanDone(firstTrackTitle: String, aboutToPreFire: Bool) {
        let msg = "WIRING: _buildPlan DONE livePlanSet=true firstTrack='\(firstTrackTitle)' " +
            "aboutToPreFire=\(aboutToPreFire)"
        sessionRecorder?.log(msg)
        wiringLogger.info("\(msg, privacy: .public)")
    }

    func logWiringBuildPlanFailed(_ error: Error) {
        let msg = "WIRING: _buildPlan FAILED reason='\(error)'"
        sessionRecorder?.log(msg)
        wiringLogger.info("\(msg, privacy: .public)")
    }

    func logWiringResetStemPipelineEnter(
        title: String,
        caller: ResetStemPipelineCaller
    ) {
        let engineCacheState = stemCache.map { "present(\($0.count))" } ?? "nil"
        let msg = "WIRING: resetStemPipeline ENTER track='\(title)' " +
            "caller=\(caller.rawValue) engine.stemCache=\(engineCacheState)"
        sessionRecorder?.log(msg)
        wiringLogger.info("\(msg, privacy: .public)")
    }

    func logTrackChangeObserved(event: TrackChangeEvent, identity: TrackIdentity) {
        let prevTitle = event.previous?.title ?? "<nil>"
        let newTitle = event.current.title ?? "<nil>"
        let durStr = identity.duration.map { String($0) } ?? "nil"
        let spotifyIDStr = identity.spotifyID ?? "nil"
        let resolved = (identity.duration != nil || identity.spotifyID != nil)
            ? "fromLivePlan" : "partialFallback"
        let msg = "WIRING: trackChange OBSERVED title='\(newTitle)' " +
            "previousTitle='\(prevTitle)' identity.duration=\(durStr) " +
            "identity.spotifyID=\(spotifyIDStr) resolution=\(resolved) aboutToReset=true"
        sessionRecorder?.log(msg)
    }

    func logWiringStemCacheLookup(identity: TrackIdentity) {
        let durStr = identity.duration.map { String(format: "%.2f", $0) } ?? "nil"
        let previewHost = identity.spotifyPreviewURL?.host ?? "nil"
        let engineHit = stemCache?.loadForPlayback(track: identity) != nil
        let msg = "WIRING: StemCache.loadForPlayback track='\(identity.title)' " +
            "artist='\(identity.artist)' duration=\(durStr) " +
            "spotifyPreviewURL=\(previewHost) engineCacheHit=\(engineHit)"
        sessionRecorder?.log(msg)
    }
}
