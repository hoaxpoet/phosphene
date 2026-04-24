// PresetPreviewController — Stub for the 10-second row-tap preview loop (U.5 Part C).
//
// DEFERRED to Increment U.5b.
//
// Decision (D-048, 2026-04-23): Part C requires injecting a synthetic FeatureVector
// into the active RenderPipeline, a second render surface (or background-preset
// surface hijack), and a way to loop a preset without live audio callbacks. All three
// require engine-layer changes disjoint from the UX work in U.5. The preview loop is
// a delightful but non-blocking feature — ReadyView ships correctly without it, and
// the stub keeps the call site stable so U.5b can swap in a real implementation
// without touching PlanPreviewViewModel.
//
// Row-tap in PlanPreviewRowView is wired to PlanPreviewViewModel.previewRow(_:),
// which calls this controller's startPreview(). The stub logs and no-ops.
// The context-menu "Swap preset" action is disabled (TODO(U.5.C)).

import Foundation
import Orchestrator
import Presets
import Shared
import os.log

private let logger = Logger(subsystem: "com.phosphene.app", category: "PresetPreview")

// MARK: - PresetPreviewController

/// Orchestrates 10-second preset preview loops driven by cached stems.
///
/// **Current status:** stub — all methods log and return immediately.
/// Replace this class body with a real implementation in Increment U.5b.
@MainActor
final class PresetPreviewController {

    // MARK: - Init

    init() {}

    // MARK: - Public API

    /// Start a looping 10-second preview for the given preset + stems.
    ///
    /// TODO(U.5b): Switch the background render surface to `preset`, push
    /// `stems` to GPU buffer(3), loop until `stopPreview()` or session advances.
    func startPreview(preset: PresetDescriptor, stems: StemFeatures, duration: TimeInterval = 10) {
        logger.info("PresetPreviewController: preview not yet implemented (U.5b) for '\(preset.name)'")
    }

    /// Stop any active preview and revert to the session's default background.
    func stopPreview() {
        logger.info("PresetPreviewController: stopPreview (no-op stub)")
    }
}
