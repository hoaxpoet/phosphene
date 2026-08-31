// BeatDetector+TempoDiagnostics — DSP.1 baseline-capture instrumentation.
//
// Gated behind `BEATDETECTOR_DUMP_HIST=1`. Silent in production; intended
// for capturing before/after evidence on the three reference tracks before
// the IOI half/double voting pass replaces `applyOctaveCorrection`.
//
// Set `BEATDETECTOR_DUMP_FILE=<path>` to also append every dump line to a
// plain-text file (truncated at process start). Use this when capturing
// baselines via the TempoDumpRunner harness — it avoids `log show --info`
// flag wrangling and gives you a clean per-track artifact.

import Foundation
import Shared

extension BeatDetector {
    /// Cached env-var lookup. Set `BEATDETECTOR_DUMP_HIST=1` to enable.
    static let dumpHistogramEnabled: Bool =
        ProcessInfo.processInfo.environment["BEATDETECTOR_DUMP_HIST"] == "1"

    /// Optional file destination. Caller (e.g. TempoDumpRunner) is
    /// responsible for truncation / header lines before BeatDetector runs.
    /// Lock serializes appends across concurrent BeatDetector instances.
    static let dumpFileURL: URL? = {
        let env = ProcessInfo.processInfo.environment
        guard let path = env["BEATDETECTOR_DUMP_FILE"], !path.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: path)
    }()

    static let dumpFileLock = NSLock()

    /// Emit the top-5 IOI histogram bins (period, count, implied BPM) plus
    /// the raw best and currently-selected BPM. No-op when env not set.
    func dumpHistogram(label: String, hist: [Int], raw: Float, sel: Float) {
        guard Self.dumpHistogramEnabled else { return }

        let summary = String(
            format: "[DSP.1 dump] %@ raw=%.2f sel=%.2f", label, raw, sel
        )
        emitDumpLine(summary)

        let ranked = hist.enumerated()
            .filter { $0.element > 0 }
            .sorted { $0.element > $1.element }
            .prefix(5)
        for (idx, count) in ranked {
            let bpm = Float(idx + 60)
            let period = 60.0 / bpm
            let fmt = "[DSP.1 dump]   bin bpm=%.0f period=%.4f count=%d"
            let line = String(format: fmt, bpm, period, count)
            emitDumpLine(line)
        }
    }

    /// Emit a one-line "early-return" marker so a quiet capture is
    /// distinguishable from a dead capture (no audio, no onsets, no path).
    func dumpEarly(label: String, reason: String) {
        guard Self.dumpHistogramEnabled else { return }
        emitDumpLine("[DSP.1 dump] \(label) early reason=\(reason)")
    }

    /// Emit one line per timestamp recorded into the IOI histogram source.
    /// This is the EXACT event stream feeding `computeStableTempo` —
    /// `bandFlux[0]+bandFlux[1] > bassP75*2`, with 150ms minimum spacing.
    /// Compare per-band onset events (from runner) against this stream
    /// to localize tempo failures to the threshold/fusion logic.
    func dumpTempoTimestamp(time: Double, bassFlux: Float, threshold: Float) {
        guard Self.dumpHistogramEnabled else { return }
        let fmt = "[DSP.1 ts] t=%.4f flux=%.4f thr=%.4f"
        emitDumpLine(String(format: fmt, time, bassFlux, threshold))
    }

    /// Emit one line: unified-log notice + optional file append.
    /// `notice` (not `info`) so `log show` captures without extra flags.
    private func emitDumpLine(_ line: String) {
        Logging.dsp.notice("\(line, privacy: .public)")
        guard let url = Self.dumpFileURL else { return }
        Self.dumpFileLock.lock()
        defer { Self.dumpFileLock.unlock() }
        guard let data = (line + "\n").data(using: .utf8),
              let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        _ = try? handle.write(contentsOf: data)
    }
}
