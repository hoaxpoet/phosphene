// SessionRecorder+Timing.swift — per-analysis-frame subsystem timing API.
//
// Companion to `SessionRecorder.recordFrameTiming(cpuMs:gpuMs:)` (DM.3a).
// The setter here is called from VisualizerEngine's analysis queue inside
// `processAnalysisFrame` once per analysis frame (~94 Hz). It updates the
// recorder's queue-protected `latestMIRPipelineMs` / `latestStemAnalyzerMs`
// / `latestBeatDetectorMs` / `latestPitchTrackerMs` / `latestMoodClassifierMs`
// fields; the next features.csv row to be written reads those and emits the
// per-subsystem columns.
//
// PERF.1 — BUG-019 instrumentation. See `docs/QUALITY/KNOWN_ISSUES.md`
// BUG-019 and `docs/ENGINEERING_PLAN.md` Phase PERF for context.

import Foundation

extension SessionRecorder {

    /// Record one frame's CPU + GPU timing as observed by `RenderPipeline`.
    /// Wires `RenderPipeline.onFrameTimingObserved` to the next features.csv
    /// row's `frame_cpu_ms` / `frame_gpu_ms` columns. Safe to call from any
    /// thread — the update hops onto the recorder's serial queue. (DM.3a)
    public func recordFrameTiming(cpuMs: Float, gpuMs: Float?) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.latestFrameCPUms = cpuMs
            self.latestFrameGPUms = gpuMs
        }
    }

    /// Record one analysis-frame's per-subsystem timing breakdown for the
    /// next features.csv row's `mir_pipeline_ms` / `stem_analyzer_ms` /
    /// `beat_detector_ms` / `pitch_tracker_ms` / `mood_classifier_ms`
    /// columns. Safe to call from any thread — the update hops onto the
    /// recorder's serial queue.
    ///
    /// Pass `0` (not `nil`) for subsystems that did not run this frame
    /// (e.g. mood classifier on a non-firing frame) so the CSV column
    /// distinguishes "ran-but-zero-cost" from "didn't write a value yet."
    public func recordSubsystemTimings(
        mirPipelineMs: Float,
        stemAnalyzerMs: Float,
        beatDetectorMs: Float,
        pitchTrackerMs: Float,
        moodClassifierMs: Float
    ) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.latestMIRPipelineMs = mirPipelineMs
            self.latestStemAnalyzerMs = stemAnalyzerMs
            self.latestBeatDetectorMs = beatDetectorMs
            self.latestPitchTrackerMs = pitchTrackerMs
            self.latestMoodClassifierMs = moodClassifierMs
        }
    }
}
