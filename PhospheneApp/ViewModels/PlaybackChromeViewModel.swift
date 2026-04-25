// PlaybackChromeViewModel — Drives the auto-hiding overlay chrome during playback.
//
// Pre-flight audit findings (U.6):
//
// 1. PlaybackView shape: ZStack with MetalView + preset name badge + NoAudioSignalBadge
//    (private inlined struct) + DebugOverlayView. No abstraction yet.
//
// 2. DebugOverlayView: separate file, gated by engine.showDebugOverlay (Bool). No
//    key binding — U.6 wires 'D' via PlaybackKeyMonitor.
//
// 3. NoAudioSignalBadge: triggers on audioSignalState == .silent, which by the
//    SilenceDetector state machine already implies ≥3 s of silence. U.6 renames
//    copy to "Listening…" and moves it to ListeningBadgeView.
//
// 4. currentPreset(at:) exists on VisualizerEngine for planned sessions.
//    livePlannedSession is @Published. No currentTrackIndex published — derived
//    here by matching currentTrack against plan.tracks by title.
//
// 5. OrchestratorDisplayState: no existing property. Derived from livePlan != nil.
//    .adapting requires U.6b wiring — omitted for now with TODO.
//
// 6. Keyboard handling: migrated from .onKeyPress to PlaybackKeyMonitor (NSEvent).
//
// 7-8. Fullscreen + multi-display handled in Part D.
//
// Threading: @MainActor. All Combine subscriptions arrive on the main run loop.

import AppKit
import Audio
import Combine
import Orchestrator
import Session
import Shared
import SwiftUI

// MARK: - Supporting types

/// Display-side projection of a live track.
struct TrackInfoDisplay: Equatable {
    let title: String
    let artist: String
    /// Art URL is nil in v1. TODO(U.future): populate from MetadataPreFetcher.
    let albumArtURL: URL?
}

/// Display-side projection of the active preset.
struct PresetDisplay: Equatable {
    let name: String
    let family: String
}

/// High-level orchestrator mode label shown in TrackInfoCardView.
enum OrchestratorDisplayState: String, Equatable {
    case planned  = "Planned"
    case reactive = "Reactive"
    // .adapting wired in U.6b when LiveAdapter emits events via PlaybackActionRouter.
}

/// Track-list progress summary for SessionProgressDotsView.
struct SessionProgressData: Equatable {
    let totalTracks: Int
    let currentIndex: Int       // 0-based; -1 when unknown
    let isReactiveMode: Bool    // true when no PlannedSession exists
}

// MARK: - PlaybackChromeViewModel

/// Observable source of truth for PlaybackChromeView.
///
/// Injected with Combine publishers so it can be unit-tested without Metal.
/// In production, PlaybackView passes `engine.$xxx.eraseToAnyPublisher()`.
@MainActor
final class PlaybackChromeViewModel: ObservableObject {

    // MARK: - Published

    @Published private(set) var currentTrack: TrackInfoDisplay?
    @Published private(set) var currentPreset: PresetDisplay?
    @Published private(set) var orchestratorState: OrchestratorDisplayState = .reactive
    @Published private(set) var sessionProgress: SessionProgressData = SessionProgressData(
        totalTracks: 0, currentIndex: -1, isReactiveMode: true
    )
    @Published var overlayVisible: Bool = true
    @Published private(set) var showListeningBadge: Bool = false
    @Published private(set) var reduceMotion: Bool
    /// True while background track preparation is still in flight (6.1).
    /// Drives the subtle "still preparing" teal dot in `PlaybackControlsCluster`.
    @Published private(set) var isBackgroundPreparationActive: Bool = false

    // MARK: - Private

    private var cancellables = Set<AnyCancellable>()
    private var hideTask: Task<Void, Never>?
    private let delay: any DelayProviding

    private var livePlan: PlannedSession?
    private var rawCurrentTrack: TrackMetadata?

    // MARK: - Init

    /// Create a chrome view model wired to the given publishers.
    ///
    /// - Parameters:
    ///   - audioSignalStatePublisher: Emits `AudioSignalState` changes from the engine.
    ///   - currentTrackPublisher: Emits `TrackMetadata?` as Now Playing changes.
    ///   - currentPresetNamePublisher: Emits the display preset name.
    ///   - livePlanPublisher: Emits `PlannedSession?` updates.
    ///   - reduceMotionPublisher: Emits effective reduce-motion state from `AccessibilityState`.
    ///     Defaults to a `Just(false)` publisher (normal motion) for backwards compatibility in
    ///     unit tests that don't need to exercise the reduce-motion path.
    ///   - progressiveReadinessPublisher: Emits `ProgressiveReadinessLevel` from `SessionManager`.
    ///     Drives the "still preparing" teal dot indicator. Defaults to `.fullyPrepared` so the
    ///     indicator is hidden in unit tests and in ad-hoc (no-playlist) sessions.
    ///   - delay: Injectable sleep; defaults to `RealDelay` (use `InstantDelay` in tests).
    init(
        audioSignalStatePublisher: AnyPublisher<AudioSignalState, Never>,
        currentTrackPublisher: AnyPublisher<TrackMetadata?, Never>,
        currentPresetNamePublisher: AnyPublisher<String?, Never>,
        livePlanPublisher: AnyPublisher<PlannedSession?, Never>,
        reduceMotionPublisher: AnyPublisher<Bool, Never> = Just(false).eraseToAnyPublisher(),
        progressiveReadinessPublisher: AnyPublisher<ProgressiveReadinessLevel, Never> =
            Just(.fullyPrepared).eraseToAnyPublisher(),
        delay: any DelayProviding = RealDelay()
    ) {
        self.delay = delay
        self.reduceMotion = false   // overwritten immediately by the publisher below

        // Start the initial auto-hide timer.
        scheduleHide()

        // Reduce-motion: sourced from AccessibilityState via publisher injection.
        // Replaces the direct NSWorkspace observation from U.6 (U.9 migration).
        reduceMotionPublisher
            .receive(on: DispatchQueue.main)
            .assign(to: \.reduceMotion, on: self)
            .store(in: &cancellables)

        // Listening badge: show only on definite .silent (≥3 s per SilenceDetector SM).
        audioSignalStatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.showListeningBadge = (state == .silent)
            }
            .store(in: &cancellables)

        // Current track → TrackInfoDisplay.
        currentTrackPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] meta in
                guard let self else { return }
                self.rawCurrentTrack = meta
                self.currentTrack = meta.map {
                    TrackInfoDisplay(
                        title: $0.title ?? "Unknown",
                        artist: $0.artist ?? "",
                        albumArtURL: nil
                    )
                }
                self.refreshProgress()
            }
            .store(in: &cancellables)

        // Preset name → PresetDisplay (family derived in U.future when engine exposes it).
        currentPresetNamePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] name in
                self?.currentPreset = name.map { PresetDisplay(name: $0, family: "") }
            }
            .store(in: &cancellables)

        // Live plan → orchestratorState + sessionProgress.
        livePlanPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] plan in
                guard let self else { return }
                self.livePlan = plan
                self.orchestratorState = plan != nil ? .planned : .reactive
                self.refreshProgress()
            }
            .store(in: &cancellables)

        // Background preparation indicator (6.1).
        progressiveReadinessPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] level in
                self?.isBackgroundPreparationActive = level < .fullyPrepared
            }
            .store(in: &cancellables)
    }

    deinit {
        hideTask?.cancel()
    }

    // MARK: - Activity

    /// Call on any user activity (mouse move, key press) to reset the auto-hide timer.
    func onActivity() {
        overlayVisible = true
        scheduleHide()
    }

    /// Toggle the overlay manually (Space key). Resets the timer if making visible.
    func toggleOverlay() {
        overlayVisible.toggle()
        if overlayVisible { scheduleHide() }
    }

    // MARK: - Private

    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            guard let self else { return }
            try? await self.delay.sleep(seconds: 3)
            guard !Task.isCancelled else { return }
            await MainActor.run { self.overlayVisible = false }
        }
    }

    /// Recompute sessionProgress from the current plan and raw track metadata.
    private func refreshProgress() {
        guard let plan = livePlan, !plan.tracks.isEmpty else {
            sessionProgress = SessionProgressData(
                totalTracks: 0, currentIndex: -1, isReactiveMode: true
            )
            return
        }
        let title = rawCurrentTrack?.title
        let artist = rawCurrentTrack?.artist
        let idx = plan.tracks.firstIndex {
            $0.track.title.lowercased() == (title ?? "").lowercased()
            && $0.track.artist.lowercased() == (artist ?? "").lowercased()
        } ?? -1
        sessionProgress = SessionProgressData(
            totalTracks: plan.tracks.count,
            currentIndex: idx,
            isReactiveMode: false
        )
    }
}
