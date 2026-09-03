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
//    livePlannedSession is @Published. currentTrackIndex is @Published by
//    VisualizerEngine (QR.4 / D-091) — view models bind to it directly. The
//    pre-QR.4 lowercased-title+artist string match was Failed Approach
//    territory: covers, remasters, and encoding-different versions broke the
//    match silently.
//
// 5. OrchestratorDisplayState: removed at DS.6 (D-241) — the track card no longer says
//    whether the session is planned; the surprise model (D-238) keeps that from the
//    listener. `sessionProgress.isReactiveMode` still carries it to the dots.
//
// 6. Keyboard handling: migrated from .onKeyPress to PlaybackKeyMonitor (NSEvent).
//
// 7-8. Fullscreen + multi-display handled in Part D.
//
// Visibility (DS.6, D-241 — Matt's call): after 3 s of inactivity the chrome disappears
// completely so the listener can focus on the visuals. Mouse movement, a tap on the
// screen, any key, and a track change bring all of it back; Space toggles it. The
// first-show timer waits for the arrival (`PlaybackArrivalOverlay`) to fade before its
// 3 s start.
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
    /// Raw album-artwork bytes (PNG / JPEG, depending on container) for the
    /// live track, or nil when the source has no embedded artwork. Populated
    /// from `VisualizerEngine.currentTrackArtworkData` for LF sessions
    /// (LF.6). Streaming sessions stay nil until LF.6.streaming.
    let albumArtData: Data?
}

/// Display-side projection of the active preset.
struct PresetDisplay: Equatable {
    let name: String
    let family: String
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
    @Published private(set) var sessionProgress: SessionProgressData = SessionProgressData(
        totalTracks: 0, currentIndex: -1, isReactiveMode: true
    )
    /// The whole chrome, or nothing (D-241): false after 3 s of inactivity, true again on
    /// any input. Space toggles it.
    @Published private(set) var overlayVisible: Bool = true
    @Published private(set) var showListeningBadge: Bool = false
    @Published private(set) var reduceMotion: Bool
    /// True while background track preparation is still in flight (6.1).
    /// Drives the "still preparing" status beneath `PlaybackControlsCluster`.
    @Published private(set) var isBackgroundPreparationActive: Bool = false
    /// True when the active session is a local-file playback (LF.4 / LF.5).
    /// Drives whether `LocalFileTransportBar` renders in the chrome.
    /// LF.5.fix D-LF5-3.
    @Published private(set) var isLocalFileSession: Bool = false
    /// True when the LF audio router is currently paused.
    /// Drives the transport bar's Play/Pause glyph.
    @Published private(set) var isLocalFilePaused: Bool = false

    // MARK: - Private

    private var cancellables = Set<AnyCancellable>()
    private var hideTask: Task<Void, Never>?
    private var inputMonitor: Any?
    private let delay: any DelayProviding

    /// Seconds of inactivity before the chrome disappears (UX_SPEC §7.2).
    static let inactivityDelay: Double = 3
    /// When the arrival has faded. Activity before then — the pointer already resting over
    /// the window fires the hover the moment PlaybackView appears — must not shorten the
    /// first show: the listener has not seen the chrome yet.
    private let firstShowEnds: Date

    private var livePlan: PlannedSession?
    private var currentTrackIndex: Int?

    // MARK: - Init

    /// Create a chrome view model wired to the given publishers.
    ///
    /// - Parameters:
    ///   - audioSignalStatePublisher: Emits `AudioSignalState` changes from the engine.
    ///   - currentTrackPublisher: Emits `TrackMetadata?` as Now Playing changes.
    ///   - currentTrackArtworkDataPublisher: Emits raw album-artwork bytes for the live track
    ///     (LF.6). Combined with `currentTrackPublisher` via `Publishers.CombineLatest` so
    ///     `TrackInfoDisplay` carries both fields atomically. Defaults to `Just(nil)` for
    ///     tests and pre-LF.6 callers.
    ///   - currentPresetNamePublisher: Emits the display preset name.
    ///   - livePlanPublisher: Emits `PlannedSession?` updates.
    ///   - reduceMotionPublisher: Emits effective reduce-motion state from `AccessibilityState`.
    ///     Defaults to a `Just(false)` publisher (normal motion) for backwards compatibility in
    ///     unit tests that don't need to exercise the reduce-motion path.
    ///   - progressiveReadinessPublisher: Emits `ProgressiveReadinessLevel` from `SessionManager`.
    ///     Drives the "still preparing" status. Defaults to `.fullyPrepared` so the
    ///     indicator is hidden in unit tests and in ad-hoc (no-playlist) sessions.
    ///   - firstShowDelay: Seconds the first inactivity timer waits before its own 3 s —
    ///     `PlaybackView` passes the arrival's duration so "visible for 3 s on session
    ///     start" begins when the arrival has faded (DS.6). Defaults to 0.
    ///   - delay: Injectable sleep; defaults to `RealDelay` (use `InstantDelay` in tests).
    init(
        audioSignalStatePublisher: AnyPublisher<AudioSignalState, Never>,
        currentTrackPublisher: AnyPublisher<TrackMetadata?, Never>,
        currentTrackArtworkDataPublisher: AnyPublisher<Data?, Never> =
            Just(nil).eraseToAnyPublisher(),
        currentTrackIndexPublisher: AnyPublisher<Int?, Never> = Just(nil).eraseToAnyPublisher(),
        currentPresetNamePublisher: AnyPublisher<String?, Never>,
        livePlanPublisher: AnyPublisher<PlannedSession?, Never>,
        reduceMotionPublisher: AnyPublisher<Bool, Never> = Just(false).eraseToAnyPublisher(),
        progressiveReadinessPublisher: AnyPublisher<ProgressiveReadinessLevel, Never> =
            Just(.fullyPrepared).eraseToAnyPublisher(),
        currentSourcePublisher: AnyPublisher<SessionOrigin?, Never> =
            Just(nil).eraseToAnyPublisher(),
        isLocalFilePausedPublisher: AnyPublisher<Bool, Never> =
            Just(false).eraseToAnyPublisher(),
        firstShowDelay: Double = 0,
        delay: any DelayProviding = RealDelay()
    ) {
        self.delay = delay
        self.reduceMotion = false   // overwritten immediately by the publisher below
        self.firstShowEnds = Date(timeIntervalSinceNow: firstShowDelay)

        // Start the initial hide timer, after the arrival has faded.
        scheduleHide(after: firstShowDelay + Self.inactivityDelay)

        // Reduce-motion: sourced from AccessibilityState via publisher injection.
        // Replaces the direct NSWorkspace observation from U.6 (U.9 migration).
        reduceMotionPublisher
            .receive(on: DispatchQueue.main)
            // CLEAN.1.4 (BUG-033): sink [weak self], not assign(to:on: self) —
            // Subscribers.Assign retains self, leaking this VM (deinit never ran).
            .sink { [weak self] reduce in self?.reduceMotion = reduce }
            .store(in: &cancellables)

        // Listening badge: show only on definite .silent (≥3 s per SilenceDetector SM).
        audioSignalStatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.showListeningBadge = (state == .silent)
            }
            .store(in: &cancellables)

        wireTrackPublishers(
            currentTrackPublisher: currentTrackPublisher,
            currentTrackArtworkDataPublisher: currentTrackArtworkDataPublisher
        )

        // QR.4 / D-091: bind sessionProgress directly to the published
        // currentTrackIndex from the engine. No more lowercased title+artist
        // string matching (covers/remasters/encoding-different variants broke it).
        currentTrackIndexPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] idx in
                guard let self else { return }
                self.currentTrackIndex = idx
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

        // Live plan → sessionProgress.
        livePlanPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] plan in
                guard let self else { return }
                self.livePlan = plan
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

        wireLocalFilePublishers(
            currentSourcePublisher: currentSourcePublisher,
            isLocalFilePausedPublisher: isLocalFilePausedPublisher
        )
    }

    /// Current track + artwork → TrackInfoDisplay. Extracted from `init` at DS.6 to
    /// keep it under the SwiftLint function-body-length cap.
    private func wireTrackPublishers(
        currentTrackPublisher: AnyPublisher<TrackMetadata?, Never>,
        currentTrackArtworkDataPublisher: AnyPublisher<Data?, Never>
    ) {
        // Current track + artwork → TrackInfoDisplay. LF.6: bind both
        // publishers together via CombineLatest so the view sees title and
        // artwork as one projection. The engine writes both fields back-to-
        // back inside the same MainActor block (see
        // `VisualizerEngine.currentTrackArtworkData` invariant); CombineLatest
        // emits per-upstream change, so a track-advance briefly carries the
        // previous track's artwork into the next emission — acceptable per
        // the kickoff's "back-to-back" invariant since the second emission
        // lands within sub-frame time and the chrome's opacity-animate
        // covers it.
        Publishers.CombineLatest(currentTrackPublisher, currentTrackArtworkDataPublisher)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] meta, artworkData in
                guard let self else { return }
                let previousTitle = self.currentTrack?.title
                self.currentTrack = meta.map {
                    TrackInfoDisplay(
                        title: $0.title ?? "Unknown",
                        artist: $0.artist ?? "",
                        albumArtData: artworkData
                    )
                }
                self.refreshProgress()
                // A track change brings the chrome back for 3 s (UX_SPEC §7.2). Not on
                // the first track: that one arrives under the arrival's own timer.
                if let previousTitle, let title = self.currentTrack?.title, title != previousTitle {
                    self.onActivity()
                }
            }
            .store(in: &cancellables)
    }

    /// LF.5.fix D-LF5-3: local-file-session detection drives whether the
    /// transport bar renders; pause flag drives its Play/Pause glyph.
    /// Extracted to keep `init` under the SwiftLint function-body-length cap.
    private func wireLocalFilePublishers(
        currentSourcePublisher: AnyPublisher<SessionOrigin?, Never>,
        isLocalFilePausedPublisher: AnyPublisher<Bool, Never>
    ) {
        currentSourcePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] origin in
                self?.isLocalFileSession = origin?.isLocalFile ?? false
            }
            .store(in: &cancellables)
        isLocalFilePausedPublisher
            .receive(on: DispatchQueue.main)
            // CLEAN.1.4 (BUG-033): sink [weak self], not assign(to:on: self).
            .sink { [weak self] paused in self?.isLocalFilePaused = paused }
            .store(in: &cancellables)
    }

    deinit {
        hideTask?.cancel()
        // The input monitor is removed by `stopObservingInput()` from PlaybackView's
        // teardown — `NSEvent.removeMonitor` is not something a nonisolated deinit may call.
    }

    // MARK: - Activity

    /// Call on any user activity (mouse move, tap, key press, track change): the chrome
    /// comes back and the hide timer restarts — never to earlier than 3 s past the arrival.
    func onActivity() {
        overlayVisible = true
        let untilArrivalEnds = max(0, firstShowEnds.timeIntervalSinceNow)
        scheduleHide(after: untilArrivalEnds + Self.inactivityDelay)
    }

    /// The Space toggle: hides the chrome outright while it is up; brings it back — and
    /// restarts the hide timer — while it is not.
    func toggleOverlay() {
        if overlayVisible {
            hideTask?.cancel()
            overlayVisible = false
        } else {
            onActivity()
        }
    }

    /// A tap on the screen or any key press counts as activity (UX_SPEC §7.2; mouse
    /// movement is `PlaybackView`'s hover). Installed by `PlaybackView` alongside its
    /// shortcut monitor; every event passes through untouched. Space is skipped so
    /// `toggleOverlay` sees the state the listener pressed it in.
    func observeInput() {
        guard inputMonitor == nil else { return }
        inputMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            if !(event.type == .keyDown && event.keyCode == Self.spaceKeyCode) {
                Task { @MainActor [weak self] in self?.onActivity() }
            }
            return event
        }
    }

    func stopObservingInput() {
        if let inputMonitor { NSEvent.removeMonitor(inputMonitor) }
        inputMonitor = nil
    }

    private static let spaceKeyCode: UInt16 = 49

    // MARK: - Private

    private func scheduleHide(after seconds: Double = PlaybackChromeViewModel.inactivityDelay) {
        hideTask?.cancel()
        hideTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await self.delay.sleep(seconds: seconds)
            guard !Task.isCancelled else { return }
            self.overlayVisible = false
        }
    }

    /// QR.4 / D-091: recompute sessionProgress from the live plan + the
    /// currentTrackIndex published by VisualizerEngine. The pre-QR.4
    /// implementation matched lowercased title+artist against plan.tracks,
    /// which silently failed on covers, remasters, and encoding-different
    /// versions. The engine's plan walk knows the canonical index by
    /// construction; view models bind to it directly.
    private func refreshProgress() {
        guard let plan = livePlan, !plan.tracks.isEmpty else {
            sessionProgress = SessionProgressData(
                totalTracks: 0, currentIndex: -1, isReactiveMode: true
            )
            return
        }
        sessionProgress = SessionProgressData(
            totalTracks: plan.tracks.count,
            currentIndex: currentTrackIndex ?? -1,
            isReactiveMode: false
        )
    }
}
