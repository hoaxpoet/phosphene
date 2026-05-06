// SessionPreparer+WiringLogs — Extracted to keep SessionPreparer.swift under
// the SwiftLint 400-line gate (BUG-008.2). Holds the per-track summary line
// emitted at the end of every prepare(), the BUG-006.1 WIRING: instrumentation
// (cleanup tracked under QR.5), and the BPM-mismatch warnings (2-way BUG-008.2
// and 3-way DSP.4).

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
            } else {
                emptyGrid += 1
                sessionRecorder?.log(
                    "WIRING: SessionPreparer.beatGrid track='\(track.title)' " +
                    "bpm=0 beats=0 isEmpty=true"
                )
            }
            logDrumsBeatGridLine(track: track)
            logBPMMismatchIfAny(track: track)
        }
        let doneMsg = "WIRING: SessionPreparer.prepare DONE prepared=\(cachedTracks.count) " +
            "withGrid=\(withGrid) empty=\(emptyGrid) failed=\(failedTracks.count)"
        sessionRecorder?.log(doneMsg)
        wiringLogsLogger.info("\(doneMsg, privacy: .public)")
    }

    // MARK: - DSP.4 Drums BeatGrid

    /// Emit a `WIRING: SessionPreparer.drumsBeatGrid` line for every prepared track.
    /// Diagnostic-only — the live drift tracker does not consume this grid.
    fileprivate func logDrumsBeatGridLine(track: TrackIdentity) {
        if let grid = cache.drumsBeatGrid(for: track), !grid.beats.isEmpty {
            let bpmStr = String(format: "%.1f", grid.bpm)
            let beatCount = grid.beats.count
            sessionRecorder?.log(
                "WIRING: SessionPreparer.drumsBeatGrid track='\(track.title)' " +
                "bpm=\(bpmStr) beats=\(beatCount) isEmpty=false"
            )
        } else {
            sessionRecorder?.log(
                "WIRING: SessionPreparer.drumsBeatGrid track='\(track.title)' " +
                "bpm=0 beats=0 isEmpty=true"
            )
        }
    }

    // MARK: - BPM Mismatch

    /// Emit a BPM-mismatch warning for a prepared track.
    ///
    /// **Precedence (DSP.4):** when all three estimators (MIR, full-mix grid,
    /// drums-stem grid) are non-zero and at least one pair disagrees by > 3 %,
    /// emits `WARN: BPM 3-way` and suppresses the 2-way line. When drumsBPM is
    /// zero or missing, falls through to the existing `WARN: BPM mismatch`
    /// (2-way, BUG-008.2) for backward grep-ability.
    fileprivate func logBPMMismatchIfAny(track: TrackIdentity) {
        guard let mirFloat = cache.trackProfile(for: track)?.bpm else { return }
        let mirBPM = Double(mirFloat)
        let gridBPM = cache.beatGrid(for: track)?.bpm ?? 0
        let drumsBPM = cache.drumsBeatGrid(for: track)?.bpm ?? 0

        // 3-way preferred: all three estimators present and at least one pair disagrees.
        if let three = detectThreeWayBPMDisagreement(
            mirBPM: mirBPM,
            gridBPM: gridBPM,
            drumsBPM: drumsBPM
        ) {
            let mirStr = String(format: "%.1f", three.mirBPM)
            let gridStr = String(format: "%.1f", three.gridBPM)
            let drumsStr = String(format: "%.1f", three.drumsBPM)
            let mgStr = String(format: "%.1f", three.mirGridDeltaPct * 100.0)
            let mdStr = String(format: "%.1f", three.mirDrumsDeltaPct * 100.0)
            let gdStr = String(format: "%.1f", three.gridDrumsDeltaPct * 100.0)
            let line = "WARN: BPM 3-way track='\(track.title)' " +
                "mir_bpm=\(mirStr) grid_bpm=\(gridStr) drums_bpm=\(drumsStr) " +
                "mir-grid=\(mgStr)% mir-drums=\(mdStr)% grid-drums=\(gdStr)% " +
                "(DSP.4: estimators on full-mix vs drums-stem vs kick-rate IOI)"
            sessionRecorder?.log(line)
            wiringLogsLogger.warning("\(line, privacy: .public)")
            return
        }

        // 2-way fallback: drumsBPM zero/missing, or all three agree (3-way returned nil).
        // Preserved verbatim for BUG-008.2 backward grep-ability.
        guard gridBPM > 0,
              let mismatch = detectBPMMismatch(mirBPM: mirBPM, gridBPM: gridBPM)
        else { return }

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
