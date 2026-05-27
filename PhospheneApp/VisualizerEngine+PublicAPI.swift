// VisualizerEngine+PublicAPI — startAudio, toggles, and display helpers.

import Audio
import CoreGraphics
import Foundation
import ML
import Session
import SwiftUI
import os.log

private let apiLogger = Logger(subsystem: "com.phosphene.app", category: "VisualizerEngine")

extension VisualizerEngine {

    // MARK: - Public API

    /// Start audio capture and metadata observation.
    func startAudio() {
        // LF.1: when the local-file playback path is already active, do
        // NOT start the process-tap capture. Otherwise `audioRouter.start(.systemAudio)`
        // below would call `stopInternal()` first, tearing down the
        // LocalFilePlaybackProvider that the LF.1 launch hook just stood up.
        // PlaybackView.setup() runs `startAudio()` unconditionally when the
        // playback view appears; the LF.1 hook transitions to .playing
        // before the view renders, so without this guard the LF playback
        // would be silently clobbered. Stem pipeline + preset apply are
        // already taken care of in `startLocalFilePlayback(url:)`.
        if localFilePlaybackActive {
            apiLogger.info("[LF.1] startAudio skipped — LF playback already active")
            return
        }
        if #available(macOS 14.2, *), let audioRouter = router as? AudioInputRouter {
            audioRouter.startMetadataOnly()
        }
        var permitted = CGPreflightScreenCaptureAccess()
        if !permitted { permitted = CGRequestScreenCaptureAccess() }
        hasScreenCapturePermission = permitted
        if permitted {
            startAudioCapture()
            startStemPipeline()
        } else {
            apiLogger.info("Screen capture denied — grant in System Settings for audio capture")
            pollForScreenCapturePermission()
        }
        if let current = presetLoader.currentPreset {
            applyPreset(current)
            showPresetName(current.descriptor.name)
        }
    }

    /// Poll until screen capture permission is granted, then start audio capture.
    private func pollForScreenCapturePermission() {
        Task { @MainActor in
            while !hasScreenCapturePermission {
                try? await Task.sleep(for: .seconds(2))
                if CGPreflightScreenCaptureAccess() {
                    hasScreenCapturePermission = true
                    apiLogger.info("Screen capture permission granted")
                    startAudioCapture()
                    startStemPipeline()
                    break
                }
            }
        }
    }

    /// Start Core Audio tap capture (requires screen capture permission).
    private func startAudioCapture() {
        if #available(macOS 14.2, *), let audioRouter = router as? AudioInputRouter {
            do {
                try audioRouter.start(mode: .systemAudio)
                apiLogger.info("Audio capture started")
            } catch {
                apiLogger.error("Audio capture failed: \(error)")
            }
        }
    }

    // MARK: - LF.1 — Local File Playback

    /// Start playback of a local audio file via `AVAudioEngine`. Bypasses
    /// the Core Audio process-tap path entirely — no screen-capture
    /// permission required. Transitions the session to ad-hoc / `.playing`
    /// so `ContentView` renders the visualizer surface, and starts the
    /// background stem pipeline so live stem analysis kicks in after the
    /// usual ~10 s warmup.
    ///
    /// Invoked once at app launch from the `PHOSPHENE_LOCAL_FILE_PLAYBACK`
    /// env-var hook in `PhospheneApp.swift`. Safe to call when audio is
    /// not yet started (router is nil-tolerant); no-op if LF playback is
    /// already active.
    @MainActor
    func startLocalFilePlayback(url: URL) {
        guard !localFilePlaybackActive else {
            apiLogger.info("[LF.1] startLocalFilePlayback ignored — already active")
            return
        }
        // Flip the flag first so the SwiftUI body re-render that follows
        // sees LF playback as active and bypasses the permission gate
        // (see ContentView.swift). The router start is synchronous so the
        // tap is already delivering samples by the time SwiftUI repaints.
        localFilePlaybackActive = true
        _completeLocalFilePlaybackStart(url: url, tag: "LF.1")
    }

    /// Shared start sequence used by both `startLocalFilePlayback(url:)`
    /// (LF.1, no pre-analysis) and `prepareAndStartLocalFilePlayback(url:)`
    /// (LF.2, pre-analysis first). Caller is responsible for flipping
    /// `localFilePlaybackActive = true` BEFORE invoking — this helper
    /// only handles the audio-router start, stem-pipeline start, ad-hoc
    /// session transition, and initial preset apply.
    ///
    /// `tag` distinguishes log lines so post-mortem traces can tell which
    /// entry point fired.
    @MainActor
    private func _completeLocalFilePlaybackStart(url: URL, tag: String) {
        if #available(macOS 14.2, *), let audioRouter = router as? AudioInputRouter {
            do {
                try audioRouter.start(mode: .localFilePlayback(url))
                apiLogger.info("[\(tag, privacy: .public)] LF playback router started: \(url.lastPathComponent, privacy: .public)")
            } catch {
                let msg = error.localizedDescription
                apiLogger.error("[\(tag, privacy: .public)] LF playback router start failed: \(msg, privacy: .public)")
                localFilePlaybackActive = false
                return
            }
        }

        startStemPipeline()
        sessionManager.startAdHocSession()

        if let current = presetLoader.currentPreset {
            applyPreset(current)
            showPresetName(current.descriptor.name)
        }
    }

    // MARK: - LF.2 — Pre-analyzed Local File Playback

    /// Run the offline pre-analysis pipeline on the local file, install
    /// the cached `BeatGrid` and stem-feature snapshot into the live
    /// pipeline, then start playback via the LF.1 audio path. The win
    /// over `startLocalFilePlayback(url:)` is that `BeatGrid` is installed
    /// at session start (not ~10 s in, after live Beat This! converges),
    /// and `stems.csv` shows non-zero stem features from frame 0.
    ///
    /// Pre-analysis uses the same `SessionPreparer.analyzePreview(...)`
    /// pipeline as the streaming path. The underlying analyzers have
    /// fixed window limits (StemSeparator ~10 s; Beat This! ~30 s); inputs
    /// longer than those limits are silently truncated by the analyzers.
    /// The LF.2 win is structural — same PCM bytes are pre-analyzed AND
    /// played, so the BeatGrid's phase is correct on the live audio by
    /// construction (vs streaming, where the preview clip is a different
    /// recording per BSAudit.2 cross-capture instability).
    ///
    /// Dispatch model: blocking. The audio router is started only after
    /// pre-analysis returns. UI latency ~2–4 s on M2 Pro for typical-length
    /// files. If any pre-analysis step throws (missing weights, etc.),
    /// falls through silently to the LF.1 behaviour (no cached install;
    /// live pipeline catches up after ~10 s).
    ///
    /// Invoked from the `PHOSPHENE_LOCAL_FILE_PLAYBACK` env-var hook in
    /// `PhospheneApp.swift`. No-op if LF playback is already active.
    @MainActor
    func prepareAndStartLocalFilePlayback(url: URL) async {
        guard !localFilePlaybackActive else {
            apiLogger.info("[LF.2] prepareAndStartLocalFilePlayback ignored — already active")
            return
        }
        // Flip the flag synchronously so ContentView's permission gate
        // bypasses immediately and the user doesn't see a flash of
        // permission-onboarding UI during the ~2–4 s pre-analysis window.
        localFilePlaybackActive = true

        let startTime = Date()
        let sep = stemSeparator
        let analyzer = stemAnalyzer
        let classifier: any MoodClassifying = moodClassifier ?? MoodClassifier()
        // The live Beat This! analyzer is lazy-initialised at first
        // live-inference call. For LF.2 we need it ready BEFORE audio
        // starts, so force eager init here. The same instance is then
        // reused by `performLiveBeatInference` once audio is flowing —
        // Beat This! state is per-call, no contention.
        if liveBeatGridAnalyzer == nil {
            do {
                liveBeatGridAnalyzer = try DefaultBeatGridAnalyzer(device: context.device)
            } catch {
                let msg = error.localizedDescription
                apiLogger.warning(
                    "[LF.2] DefaultBeatGridAnalyzer init failed: \(msg, privacy: .public) — cached grid empty"
                )
            }
        }
        let gridAnalyzer = liveBeatGridAnalyzer

        let analysisResult: (identity: TrackIdentity, cached: CachedTrackData)?
        if let sep {
            do {
                analysisResult = try await Task.detached(priority: .userInitiated) {
                    let preview = try PreviewAudio.fromLocalFile(at: url)
                    let cached = try SessionPreparer.analyzePreview(
                        preview,
                        separator: sep,
                        analyzer: analyzer,
                        classifier: classifier,
                        beatGridAnalyzer: gridAnalyzer,
                        prefetchedProfile: nil
                    )
                    return (preview.trackIdentity, cached)
                }.value
            } catch {
                let msg = error.localizedDescription
                apiLogger.error(
                    "[LF.2] pre-analysis failed: \(msg, privacy: .public) — continuing uncached"
                )
                analysisResult = nil
            }
        } else {
            apiLogger.warning("[LF.2] no stem separator — continuing without cached install")
            analysisResult = nil
        }

        if let analysisResult {
            let cached = analysisResult.cached
            let identity = analysisResult.identity
            stemCache?.store(cached, for: identity)
            let bpmStr = String(format: "%.1f", cached.beatGrid.bpm)
            let elapsedMs = Int(Date().timeIntervalSince(startTime) * 1000)
            let beatCount = cached.beatGrid.beats.count
            apiLogger.info("[LF.2] pre-analysis done: bpm=\(bpmStr) beats=\(beatCount) elapsed=\(elapsedMs)ms")
            // resetStemPipeline reads stemCache and installs the BeatGrid
            // + cached StemFeatures + cached bass proportion. This is the
            // load-bearing call — the BEAT_GRID_INSTALL log line fires here.
            resetStemPipeline(for: identity, caller: .other)
        }

        _completeLocalFilePlaybackStart(url: url, tag: "LF.2")
    }

    // MARK: - Accessibility (U.9, D-054)

    /// Apply reduced-motion and beat-amplitude flags to the render pipeline.
    ///
    /// Called from `PhospheneApp` whenever `AccessibilityState` publishes a change.
    /// Both `pipeline.frameReduceMotion` and `pipeline.beatAmplitudeScale` are
    /// read on the main actor in `draw(in:)`, so no lock is needed here.
    @MainActor
    func applyAccessibility(reduceMotion: Bool, beatAmplitudeScale: Float) {
        pipeline.frameReduceMotion = reduceMotion
        pipeline.beatAmplitudeScale = beatAmplitudeScale
        // Propagate to any active RayMarchPipeline so SSGI is suppressed immediately.
        // Uses the a11y-specific setter — the OR-gate ensures the governor flag is unaffected.
        currentRayMarchPipeline?.setA11yReducedMotion(reduceMotion)
    }

    // MARK: - Preset Settings

    /// Forward the "show uncertified presets" user preference into the engine.
    ///
    /// Called from `PhospheneApp` whenever `SettingsStore.showUncertifiedPresets` changes.
    /// Stored so `applyReactiveUpdate` can pass it through to `PresetScoringContext`,
    /// which otherwise defaults to `includeUncertifiedPresets: false`.
    @MainActor
    func applyShowUncertifiedPresets(_ show: Bool) {
        showUncertifiedPresets = show
    }

    // MARK: - Toggles

    /// Toggle the debug metadata overlay.
    func toggleDebugOverlay() {
        showDebugOverlay.toggle()
    }

    #if DEBUG
    /// Toggle forced-spider mode for visual verification. DEBUG builds only.
    ///
    /// - Returns: The new `forceSpiderActive` state (`true` = forced on).
    @discardableResult
    func toggleForceSpider() -> Bool {
        guard let state = arachneState else { return false }
        state.forceSpiderActive.toggle()
        return state.forceSpiderActive
    }
    #endif

    // MARK: - Display Helpers

    /// Briefly display the preset name, then fade it out after 2 seconds.
    func showPresetName(_ name: String) {
        hideNameTask?.cancel()
        currentPresetName = name
        sessionRecorder?.log("preset → \(name)")
        hideNameTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.5)) {
                currentPresetName = nil
            }
        }
    }
}
