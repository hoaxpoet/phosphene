// SessionPreparer+WiringLogs — Extracted to keep SessionPreparer.swift under
// the SwiftLint 400-line gate (BUG-008.2). Holds the per-track summary line
// emitted at the end of every prepare(), the BUG-006.1 WIRING: instrumentation
// (cleanup tracked under QR.5), and the BUG-008.2 BPM-mismatch warning.

import Foundation
import os.log

extension SessionPreparer {

    /// Emit per-track BeatGrid summaries plus the DONE line. Extracted from
    /// `_runPreparation` to keep that function within the 60-line SwiftLint gate.
    func logWiringDoneSummary(
        cachedTracks: [TrackIdentity],
        failedTracks: [TrackIdentity]
    ) {
        var withGrid = 0
        var emptyGrid = 0
        for track in cachedTracks {
            if let grid = cache.beatGrid(for: track), !grid.beats.isEmpty {
                withGrid += 1
                let bpmStr = String(format: "%.1f", grid.bpm)
                let beatCount = grid.beats.count
                sessionRecorder?.log(
                    "WIRING: SessionPreparer.beatGrid track='\(track.title)' " +
                    "bpm=\(bpmStr) beats=\(beatCount) isEmpty=false"
                )
                logBPMMismatchIfAny(track: track, gridBPM: grid.bpm)
            } else {
                emptyGrid += 1
                sessionRecorder?.log(
                    "WIRING: SessionPreparer.beatGrid track='\(track.title)' " +
                    "bpm=0 beats=0 isEmpty=true"
                )
            }
        }
        let doneMsg = "WIRING: SessionPreparer.prepare DONE prepared=\(cachedTracks.count) " +
            "withGrid=\(withGrid) empty=\(emptyGrid) failed=\(failedTracks.count)"
        sessionRecorder?.log(doneMsg)
        wiringLogsLogger.info("\(doneMsg, privacy: .public)")
    }

    /// Compare the offline BeatGrid BPM against the MIR-derived BPM for a
    /// prepared track and emit a `WARN: BPM mismatch` line when they
    /// disagree by more than 3 % (BUG-008.2). No runtime behaviour change —
    /// `LiveBeatDriftTracker` continues to consume the offline BeatGrid.
    fileprivate func logBPMMismatchIfAny(track: TrackIdentity, gridBPM: Double) {
        guard let mirFloat = cache.trackProfile(for: track)?.bpm else { return }
        guard let mismatch = detectBPMMismatch(
            mirBPM: Double(mirFloat),
            gridBPM: gridBPM
        ) else { return }

        let mirStr = String(format: "%.1f", mismatch.mirBPM)
        let gridStr = String(format: "%.1f", mismatch.gridBPM)
        let deltaStr = String(format: "%.1f", mismatch.deltaPct * 100.0)
        let line = "WARN: BPM mismatch track='\(track.title)' " +
            "mir_bpm=\(mirStr) grid_bpm=\(gridStr) delta_pct=\(deltaStr)% " +
            "(BUG-008: estimators disagree; prepared grid uses Beat This! value)"
        sessionRecorder?.log(line)
        wiringLogsLogger.warning("\(line, privacy: .public)")
    }
}

private let wiringLogsLogger = Logger(subsystem: "com.phosphene", category: "SessionPreparer.WiringLogs")
