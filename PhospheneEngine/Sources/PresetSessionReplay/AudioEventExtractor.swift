// AudioEventExtractor.swift — Find the strongest audio events per route.
//
// For each route, walk the session and identify the N timestamps where the
// route's input was strongest (subject to a refractory window so a single
// event isn't double-counted). These timestamps drive the video-frame
// extraction step — the visual response at each of these moments is what
// answers "does the route actually produce a visible effect."
//
// Event-extraction strategy: local maxima above the route's gate threshold,
// with a per-route refractory window (default 500 ms) to suppress
// nearby duplicates. Within the refractory window, only the strongest
// sample survives.

import Foundation

/// One audio event — the moment a route's input was locally maximal.
public struct AudioEvent: Sendable {
    public let routeName: String
    public let frameIndex: Int
    public let wallclockSeconds: Double
    public let inputValue: Float
}

public enum AudioEventExtractor {

    /// Extract up to `maxEvents` strongest events for `route` in `session`.
    /// Refractory window in seconds — events within the window of an already-
    /// selected event are suppressed unless they exceed it.
    public static func extract(
        route: RouteSpec,
        from session: SessionData,
        maxEvents: Int = 8,
        refractorySeconds: Double = 0.5
    ) -> [AudioEvent] {
        guard !session.frames.isEmpty else { return [] }

        // Pull (frame index, time, value) triples above the gate threshold.
        struct Candidate {
            let idx: Int
            let time: Double
            let value: Float
        }
        var candidates: [Candidate] = []
        for (idx, frame) in session.frames.enumerated() {
            let value = route.inputValue(frame)
            guard value >= route.gateThreshold else { continue }
            candidates.append(Candidate(
                idx: idx,
                time: frame.wallclockSeconds,
                value: value))
        }
        // Sort by value descending, then sweep with refractory.
        candidates.sort { $0.value > $1.value }

        var chosen: [Candidate] = []
        for cand in candidates where chosen.allSatisfy({ abs($0.time - cand.time) > refractorySeconds }) {
            chosen.append(cand)
            if chosen.count >= maxEvents { break }
        }
        // Sort selected by time for chronological reporting.
        chosen.sort { $0.time < $1.time }

        return chosen.map { cand in
            AudioEvent(
                routeName: route.name,
                frameIndex: session.frames[cand.idx].frame,
                wallclockSeconds: cand.time,
                inputValue: cand.value
            )
        }
    }
}
