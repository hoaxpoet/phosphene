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

    /// Record one render frame's CPU breakdown for the next features.csv
    /// row's `encode_cpu_ms` / `renderframe_cpu_ms` columns. Wires
    /// `RenderPipeline.onRenderTimingObserved` to the recorder.
    /// (PERF.2-render — BUG-019 instrumentation.)
    ///
    ///   - `encodeCpuMs`: wall-clock from `draw()` entry through
    ///     `commandBuffer.commit()` (CPU encode side only).
    ///   - `renderFrameCpuMs`: time inside `renderFrame(...)` — the per-pass
    ///     dispatch. Tells you whether the CPU work is in the pass or in the
    ///     pre/post setup around it.
    public func recordRenderTimings(encodeCpuMs: Float, renderFrameCpuMs: Float) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.latestEncodeCPUms = encodeCpuMs
            self.latestRenderFrameCPUms = renderFrameCpuMs
        }
    }

    /// Record one ray-march frame's per-sub-pass timing breakdown for the
    /// next features.csv row's `gbuffer_pass_ms` / `lighting_pass_ms` /
    /// `ssgi_pass_ms` / `post_process_pass_ms` columns. Wires
    /// `RenderPipeline.onRayMarchPassTimingObserved` to the recorder.
    /// (PERF.2-pass — BUG-019 instrumentation.)
    ///
    /// Only fires on frames where the active preset takes the ray-march path.
    /// Frames running mv_warp / feedback / ICB / post-process-only paths leave
    /// these CSV cells empty (the recorder's latest* fields stay at their last
    /// observed value, which is fine — diagnostic scans should filter by the
    /// known-active preset).
    /// Record the latest structural-section prediction for the next features.csv
    /// row's `section_index` / `section_start_s` / `section_confidence` columns.
    /// Called from the per-frame MIR publish (the same site that feeds
    /// `RenderPipeline.setStructuralPrediction` — Skein.ENGINE.3 / D-151), so the
    /// artifact records exactly the signal the Skein.5 structural bias consumes.
    /// Safe to call from any thread — hops onto the recorder's serial queue. (Skein.5.2)
    public func recordStructuralPrediction(_ prediction: StructuralPrediction) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.latestStructuralPrediction = prediction
        }
    }

    public func recordRayMarchPassTimings(
        gbufferMs: Float,
        lightingMs: Float,
        ssgiMs: Float,
        postProcessMs: Float
    ) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.latestGBufferPassMs = gbufferMs
            self.latestLightingPassMs = lightingMs
            self.latestSSGIPassMs = ssgiMs
            self.latestPostProcessPassMs = postProcessMs
        }
    }
}
