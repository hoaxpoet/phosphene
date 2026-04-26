// CaptureModeSwitchCoordinator — Session-state preservation contract for capture-mode
// switches mid-session (Increment 7.2, D-061).
//
// CaptureModeReconciler (D-052) already calls AudioInputRouter.switchMode(_:) when
// Settings change. During the switch, SilenceDetector briefly enters .suspect and then
// .silent as the tap restarts. Without a grace window:
//
//   1. LiveAdapter may see a large mood Δ from silence-derived features and trigger
//      a spurious preset override (yanking the user to a different preset right when
//      they're confirming the new audio source works).
//   2. PlaybackErrorBridge fires the silence-extended toast at 15s even though the
//      silence is expected and transient.
//
// The coordinator opens a 5-second grace window on every non-.localFile mode switch.
// During the window:
//   · VisualizerEngine.captureModeSwitchGraceWindowEndsAt is set so applyLiveUpdate
//     filters out presetOverride events.
//   · PlaybackErrorBridge.effectiveThresholdSeconds is raised to 20s.
//
// After the window both are restored to defaults. D-061(b,c).

import Combine
import Foundation
import os.log

private let logger = Logger(subsystem: "com.phosphene.app", category: "CaptureModeSwitchCoordinator")

// MARK: - CaptureModeSwitchEngineInterface

/// Minimal engine surface required by `CaptureModeSwitchCoordinator`.
/// Extracted for testability — tests use `MockCaptureModeSwitchEngine`. D-061(b).
@MainActor
protocol CaptureModeSwitchEngineInterface: AnyObject {
    var captureModeSwitchGraceWindowEndsAt: Date? { get set }
}

// MARK: - CaptureModeSwitchCoordinator

/// Enforces the session-state preservation contract around live capture-mode switches.
///
/// Owned by `PlaybackView` as `@State`, wired in `setup()` after the `PlaybackErrorBridge`
/// is created. Subscribes to `SettingsStore.captureModeChanged`. D-061(b,c).
@MainActor
final class CaptureModeSwitchCoordinator {

    // MARK: - Constants

    /// Duration of the grace window in seconds. Chosen to cover SilenceDetector's
    /// typical .suspect → .active recovery time (~2–3s) with margin for Bluetooth
    /// output devices (~2s wake latency). D-061(b).
    static let graceWindowSeconds: TimeInterval = 5

    // MARK: - State

    /// Whether a grace window is currently active. Read by tests.
    private(set) var isGraceWindowActive: Bool = false

    // MARK: - Dependencies

    private weak var engine: (any CaptureModeSwitchEngineInterface)?
    private weak var playbackErrorBridge: PlaybackErrorBridge?
    private let settingsStore: SettingsStore

    private var cancellables = Set<AnyCancellable>()
    private var graceWindowTask: Task<Void, Never>?

    // MARK: - Init

    init(
        engine: any CaptureModeSwitchEngineInterface,
        playbackErrorBridge: PlaybackErrorBridge,
        settingsStore: SettingsStore
    ) {
        self.engine = engine
        self.playbackErrorBridge = playbackErrorBridge
        self.settingsStore = settingsStore

        settingsStore.captureModeChanged
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.handleModeChange() }
            .store(in: &cancellables)
    }

    // MARK: - Private

    private func handleModeChange() {
        // .localFile shows a "coming later" toast and doesn't touch the router (D-052).
        // No audio disruption → no grace window needed.
        if settingsStore.captureMode == .localFile { return }

        openGraceWindow()
    }

    func openGraceWindow() {
        let endTime = Date().addingTimeInterval(Self.graceWindowSeconds)
        engine?.captureModeSwitchGraceWindowEndsAt = endTime
        playbackErrorBridge?.effectiveThresholdSeconds =
            PlaybackErrorBridge.silenceToastGraceWindowThresholdSeconds
        isGraceWindowActive = true

        let old = settingsStore.captureMode
        let threshold = PlaybackErrorBridge.silenceToastGraceWindowThresholdSeconds
        logger.info("""
            CaptureModeSwitchCoordinator: grace window opened (\(old.rawValue, privacy: .public) → …); \
            silence threshold \(threshold, format: .fixed(precision: 0), privacy: .public)s
            """)

        // Cancel any in-flight grace window task before starting a fresh one.
        graceWindowTask?.cancel()
        graceWindowTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.graceWindowSeconds))
            guard !Task.isCancelled, let self else { return }
            self.closeGraceWindow()
        }
    }

    func closeGraceWindow() {
        engine?.captureModeSwitchGraceWindowEndsAt = nil
        playbackErrorBridge?.effectiveThresholdSeconds =
            PlaybackErrorBridge.silenceToastThresholdSeconds
        isGraceWindowActive = false
        graceWindowTask = nil
        logger.info("CaptureModeSwitchCoordinator: grace window closed — thresholds restored")
    }
}
