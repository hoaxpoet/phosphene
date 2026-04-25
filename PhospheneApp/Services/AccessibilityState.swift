// AccessibilityState — Single source of truth for runtime accessibility state.
//
// Pre-flight audit findings (U.9, 2026-04-24):
//   1. reduceMotion existed as three independent stubs (SessionStateViewModel,
//      PlaybackChromeViewModel, ReadyViewModel), all reading NSWorkspace directly
//      and ignoring SettingsStore.reducedMotion (which was display-only).
//   2. SSGI exists (RayMarchPipeline.ssgiEnabled) — single-frame, not temporal.
//      Gated on reducedMotion in RayMarchPipeline.reducedMotion setter.
//   3. Beat-pulse amplitude clamped in RenderPipeline.draw(in:) before renderFrame,
//      applied to all four beat fields (beatBass/Mid/Treble/Composite) of the local
//      FeatureVector copy. Affects all presets, all draw paths, uniformly.
//   4. SettingsStore.reducedMotion preference is now wired: PhospheneApp.body uses
//      .task to subscribe settings.$reducedMotion → AccessibilityState.applyPreference.
//   5. PlaybackChromeViewModel migrated from direct NSWorkspace observation to a
//      reduceMotionPublisher injected at init (publisher-injection pattern, D-049).
//
// Key decision: single observable + per-frame engine flags (not in-shader gating).
// See docs/DECISIONS.md D-054.

import AppKit
import Combine
import Foundation

// MARK: - AccessibilityState

/// Single source of truth for runtime accessibility state.
///
/// Combines the system `NSWorkspace.accessibilityDisplayShouldReduceMotion` flag
/// with the user's in-app `ReducedMotionPreference` (from `SettingsStore`) into a
/// single `reduceMotion: Bool` that the app and engine consume.
///
/// Owned by `PhospheneApp` as a `@StateObject`. Distributed via `.environmentObject`.
/// Engine flags (`beatAmplitudeScale`, `frameReduceMotion`) are propagated via
/// `VisualizerEngine.applyAccessibility(_:)` on each state change.
@MainActor
final class AccessibilityState: ObservableObject {

    // MARK: - Published

    /// Raw system reduce-motion flag from NSWorkspace. Updated on
    /// `accessibilityDisplayOptionsDidChangeNotification`.
    @Published private(set) var systemReduceMotion: Bool

    /// Effective reduce-motion state: combination of system flag + user preference.
    @Published private(set) var reduceMotion: Bool

    /// Beat-pulse amplitude scale to apply at the audio→shader boundary.
    /// `1.0` in normal mode; `0.5` in reduced-motion mode.
    @Published private(set) var beatAmplitudeScale: Float

    // MARK: - Private

    private var reducedMotionPreference: ReducedMotionPreference = .matchSystem
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    /// Create the accessibility state, seeding from the current system flag.
    ///
    /// - Parameter workspace: NSWorkspace to read the system flag from. Overrideable for testing.
    init(workspace: NSWorkspace = .shared) {
        let system = workspace.accessibilityDisplayShouldReduceMotion
        self.systemReduceMotion = system
        self.reduceMotion = system          // matchSystem default
        self.beatAmplitudeScale = system ? 0.5 : 1.0

        NotificationCenter.default
            .publisher(for: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.systemReduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                self.recompute()
            }
            .store(in: &cancellables)
    }

    // MARK: - Preference Update

    /// Apply an updated `ReducedMotionPreference` (called by PhospheneApp when
    /// `SettingsStore.reducedMotion` changes).
    func applyPreference(_ pref: ReducedMotionPreference) {
        guard pref != reducedMotionPreference else { return }
        reducedMotionPreference = pref
        recompute()
    }

    // MARK: - Queries

    /// Whether the mv_warp pass should execute for a given preset.
    ///
    /// Returns `false` — skipping the pass — when `reduceMotion` is true,
    /// regardless of the preset's declared passes. The preset's direct-render
    /// pass continues to execute; only the warp/feedback layer is suppressed.
    func shouldExecuteMVWarp(presetEnabled: Bool) -> Bool {
        presetEnabled && !reduceMotion
    }

    /// Whether SSGI should execute this frame.
    ///
    /// SSGI in the current implementation is single-frame (no temporal accumulation),
    /// but it does contribute visual complexity that may cause discomfort for users
    /// with motion sensitivity.
    /// TODO(post-SSGI-temporal-landing): revisit when temporal SSGI is added.
    var shouldExecuteSSGI: Bool { !reduceMotion }

    // MARK: - Private

    private func recompute() {
        let effective: Bool
        switch reducedMotionPreference {
        case .matchSystem: effective = systemReduceMotion
        case .alwaysOn:    effective = true
        case .alwaysOff:   effective = false
        }
        reduceMotion = effective
        beatAmplitudeScale = effective ? 0.5 : 1.0
    }
}
