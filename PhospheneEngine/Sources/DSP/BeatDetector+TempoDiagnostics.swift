// BeatDetector+TempoDiagnostics — DSP.1 baseline-capture instrumentation.
//
// Gated behind `BEATDETECTOR_DUMP_HIST=1`. Silent in production; intended
// for capturing before/after evidence on the three reference tracks before
// the IOI half/double voting pass replaces `applyOctaveCorrection`.

import Foundation
import Shared

extension BeatDetector {
    /// Cached env-var lookup. Set `BEATDETECTOR_DUMP_HIST=1` to enable.
    static let dumpHistogramEnabled: Bool =
        ProcessInfo.processInfo.environment["BEATDETECTOR_DUMP_HIST"] == "1"

    /// Emit the top-5 IOI histogram bins (period, count, implied BPM) plus
    /// the raw best and currently-selected BPM. One info line per bin plus
    /// one summary line. No-op when the env var is not set.
    func dumpHistogram(label: String, hist: [Int], raw: Float, sel: Float) {
        guard Self.dumpHistogramEnabled else { return }

        let summary = String(format: "[DSP.1 dump] %@ raw=%.2f sel=%.2f", label, raw, sel)
        Logging.dsp.info("\(summary, privacy: .public)")

        let ranked = hist.enumerated()
            .filter { $0.element > 0 }
            .sorted { $0.element > $1.element }
            .prefix(5)

        for (idx, count) in ranked {
            let bpm = Float(idx + 60)
            let period = 60.0 / bpm
            let line = String(format: "[DSP.1 dump]   bin bpm=%.0f period=%.4f count=%d", bpm, period, count)
            Logging.dsp.info("\(line, privacy: .public)")
        }
    }
}
