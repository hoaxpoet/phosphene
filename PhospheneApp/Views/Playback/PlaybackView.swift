// PlaybackView — Shown when SessionManager.state == .playing (U.6 rewrite).
//
// Layer stack (bottom to top):
//   1. MetalView — full-bleed render surface
//   2. TrackChangeAnimationView — center-to-top-left boundary animation
//   3. PlaybackChromeView — auto-hiding overlay chrome (track card, progress, badge, toasts)
//   4. ShortcutHelpOverlayView — Shift+?
//   5. DebugOverlayView — D key (developer only)
//   6. End-session confirm dialog — Esc
//
// Publisher-injection pattern: ContentView passes engine.$xxx.eraseToAnyPublisher()
// at callsite, same as ReadyView. PlaybackView creates @StateObjects from the injected
// publishers at init time. PlaybackKeyMonitor replaces all .onKeyPress handlers.

import AppKit
import Audio
import Combine
import Orchestrator
import Renderer
import Session
import Shared
import SwiftUI

// MARK: - PlaybackView

/// Full-bleed Metal visualizer with auto-hiding chrome, keyboard shortcuts, and toasts.
@MainActor
struct PlaybackView: View {

    static let accessibilityID = "phosphene.view.playing"

    // MARK: - Injected

    @EnvironmentObject private var engine: VisualizerEngine
    private let onEndSession: () -> Void
    private let reduceMotion: Bool
    /// Session lifecycle, for the silent-tap detector's `.playing` gate.
    private let sessionStatePublisher: AnyPublisher<SessionState, Never>

    // MARK: - Owned (publisher-injected @StateObjects)

    @StateObject private var chromeVM: PlaybackChromeViewModel
    @StateObject private var toastManager = ToastManager()
    @StateObject private var endSessionVM: EndSessionConfirmViewModel
    @StateObject private var dashboardVM: DashboardOverlayViewModel

    // MARK: - View State

    @State private var showDebug: Bool = false
    @State private var showHelp: Bool = false
    @State private var showPlanPreview: Bool = false
    @State private var showSettings: Bool = false
    /// QR.4 / D-091: must be `@EnvironmentObject`, never `@StateObject`. A
    /// `@StateObject SettingsStore()` here creates a parallel state world —
    /// user toggles in Settings would never reach the playback-side reconciler.
    /// `SettingsStoreEnvironmentRegressionTests` enforces this invariant.
    @EnvironmentObject private var settingsStore: SettingsStore
    @State private var currentRegistry: PlaybackShortcutRegistry?
    @State private var keyMonitor = PlaybackKeyMonitor()
    @State private var fullscreenObserver = FullscreenObserver()
    @State private var actionRouter: DefaultPlaybackActionRouter?
    @State private var playbackErrorBridge: PlaybackErrorBridge?
    @State private var displayManager: DisplayManager?
    @State private var multiDisplayBridge: MultiDisplayToastBridge?
    @State private var displayChangeCoordinator: DisplayChangeCoordinator?
    /// Driven by `PlaybackErrorBridge`'s stall detector — shows the audio-stall card.
    @State private var audioStallActive: Bool = false
    /// DEBUG-only force-on for the audio-stall card (Cmd+Shift+Option+A), so the
    /// surface can be validated without a real tap stall. Always false in release.
    @State private var debugForceStallCard: Bool = false

    @Namespace private var trackAnimNamespace

    // MARK: - Init

    init(
        sessionManager: SessionManager,
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
        dashboardSnapshotPublisher: AnyPublisher<DashboardSnapshot?, Never> =
            Just(nil).eraseToAnyPublisher(),
        currentSourcePublisher: AnyPublisher<SessionOrigin?, Never> =
            Just(nil).eraseToAnyPublisher(),
        isLocalFilePausedPublisher: AnyPublisher<Bool, Never> =
            Just(false).eraseToAnyPublisher(),
        onEndSession: @escaping () -> Void,
        reduceMotion: Bool
    ) {
        self.onEndSession = onEndSession
        self.reduceMotion = reduceMotion
        self.sessionStatePublisher = sessionManager.$state.eraseToAnyPublisher()
        _chromeVM = StateObject(wrappedValue: PlaybackChromeViewModel(
            audioSignalStatePublisher: audioSignalStatePublisher,
            currentTrackPublisher: currentTrackPublisher,
            currentTrackArtworkDataPublisher: currentTrackArtworkDataPublisher,
            currentTrackIndexPublisher: currentTrackIndexPublisher,
            currentPresetNamePublisher: currentPresetNamePublisher,
            livePlanPublisher: livePlanPublisher,
            reduceMotionPublisher: reduceMotionPublisher,
            progressiveReadinessPublisher: progressiveReadinessPublisher,
            currentSourcePublisher: currentSourcePublisher,
            isLocalFilePausedPublisher: isLocalFilePausedPublisher
        ))
        _endSessionVM = StateObject(wrappedValue: EndSessionConfirmViewModel(
            sessionManager: sessionManager
        ))
        _dashboardVM = StateObject(wrappedValue: DashboardOverlayViewModel(
            snapshotPublisher: dashboardSnapshotPublisher
        ))
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            // Layer 1: Metal render
            MetalView(context: engine.context, pipeline: engine.pipeline)

            // Layer 2: Track-change center animation
            TrackChangeAnimationView(
                trackInfo: chromeVM.currentTrack,
                reduceMotion: reduceMotion,
                namespace: trackAnimNamespace
            )

            // Layer 3: Chrome overlay
            PlaybackChromeView(
                viewModel: chromeVM,
                toastManager: toastManager,
                onSettings: { showSettings = true },
                onEndSession: { endSessionVM.requestEnd() },
                onLocalFileStop: { engine.stopLocalFilePlayback() },
                onLocalFilePrev: { engine.skipToPreviousLocalFileTrack() },
                onLocalFilePlayPause: { engine.togglePauseLocalFile() },
                onLocalFileNext: { engine.skipToNextLocalFileTrack() }
            )

            // Layer 3.5: Audio-stall overlay card (silent-tap family,
            // BUG-057/055/058). Non-blocking, center; auto-clears on fresh audio.
            AudioStallOverlayView(
                isVisible: audioStallActive || debugForceStallCard,
                reduceMotion: reduceMotion
            )

            // Layer 4: Shortcut help overlay
            if showHelp, let registry = currentRegistry {
                ShortcutHelpOverlayView(
                    shortcuts: registry.shortcuts,
                    onDismiss: { showHelp = false }
                )
            }

            // Layer 5: Debug overlay (bottom-leading SwiftUI — raw diagnostics).
            if showDebug {
                DebugOverlayView(engine: engine)
                    .transition(.opacity)
            }

            // Layer 6: Dashboard overlay (top-trailing SwiftUI — instruments).
            // DASH.7 SwiftUI port (D-087); DASH.7.1 brand-aligned (D-088).
            // The transition is asymmetric — descend gently in, fade quietly
            // out — per the .impeccable.md "appears when needed, disappears
            // when not" principle.
            if showDebug {
                DashboardOverlayView(viewModel: dashboardVM)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .offset(y: -8)),
                        removal: .opacity
                    ))
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        .accessibilityIdentifier(Self.accessibilityID)
        .confirmationDialog(
            String(localized: "playback.endSession.title"),
            isPresented: $endSessionVM.isPresented,
            titleVisibility: .visible
        ) {
            Button(String(localized: "playback.endSession.confirm"), role: .destructive) {
                endSessionVM.confirm()
            }
            Button(String(localized: "common.cancel"), role: .cancel) {
                endSessionVM.cancel()
            }
        } message: {
            Text(String(localized: "playback.endSession.message"))
        }
        .onContinuousHover { phase in
            if case .active = phase { chromeVM.onActivity() }
        }
        .onAppear { setup() }
        // CLEAN.1.4 (BUG-033): tell the engine whether the dashboard overlay is
        // shown, so its per-frame snapshot pump can skip all work when hidden
        // (the default). `showDebug` is this view's local state.
        .onChange(of: showDebug) { _, visible in engine.dashboardOverlayVisible = visible }
        .onDisappear {
            teardown()
            engine.dashboardOverlayVisible = false
        }
        .sheet(isPresented: $showPlanPreview) {
            PlanPreviewView(
                initialPlan: engine.livePlannedSession,
                planPublisher: engine.$livePlannedSession.eraseToAnyPublisher(),
                onRegenerate: { @MainActor lockedTracks, lockedPresets in
                    engine.regeneratePlan(lockedTracks: lockedTracks, lockedPresets: lockedPresets)
                }
            )
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(store: settingsStore)
        }
    }

    // MARK: - Setup / Teardown

    private func setup() {
        engine.startAudio()

        // Build live-adaptation toast bridge (default on per U.6b).
        let toastBridge = LiveAdaptationToastBridge(toastManager: toastManager)

        // Build action router — U.6b: uses live factory wired to the engine.
        let router = DefaultPlaybackActionRouter.live(
            engine: engine,
            toastBridge: toastBridge,
            onShowPlanPreview: { showPlanPreview = true }
        )
        actionRouter = router

        // Fullscreen + display management
        if let window = NSApp.keyWindow {
            fullscreenObserver.attach(to: window)
            let dm = DisplayManager(fullscreenObserver: fullscreenObserver)
            dm.attach(to: window)
            displayManager = dm
            multiDisplayBridge = MultiDisplayToastBridge(toastManager: toastManager, displayManager: dm)
            // 7.2: resilience coordinator — resets FrameBudgetManager rolling buffer on hot-plug.
            displayChangeCoordinator = DisplayChangeCoordinator(
                displayManager: dm,
                frameBudgetManager: engine.pipeline.frameBudgetManager
            )
        }

        // §9.4 playback errors — silence at 15s, condition-ID auto-dismiss.
        // Silent-tap detector (BUG-057/055/058): raise the audio-stall card when
        // no fresh audio reaches the visualizer while playing. Mode A keys on
        // `.silent`; Mode B on the tap frame count (InputLevelMonitor) ceasing to
        // advance. Gated on `.playing` && not paused so it never false-fires
        // pre-play, in `.ready`, or on a deliberate local-file pause.
        let stallBinding = $audioStallActive
        let errorBridge = PlaybackErrorBridge(
            audioSignalStatePublisher: engine.$audioSignalState.eraseToAnyPublisher(),
            toastManager: toastManager,
            sessionStatePublisher: sessionStatePublisher,
            isPausedPublisher: engine.$isLocalFilePaused.eraseToAnyPublisher(),
            frameCountProvider: { [weak engine = self.engine] in
                engine?.inputLevelMonitor.currentSnapshot().frameCount ?? 0
            },
            hasEverDetectedSignalProvider: { [weak engine = self.engine] in engine?.hasEverDetectedAudio ?? false },
            onStallChanged: { active in stallBinding.wrappedValue = active }
        )
        playbackErrorBridge = errorBridge

        // Build registry — closures capture weak refs to avoid retain cycles
        let registry = buildRegistry(router: router)
        currentRegistry = registry
        keyMonitor.install(registry: registry)
    }

    private func teardown() {
        keyMonitor.uninstall()
        fullscreenObserver.detach()
    }

    // MARK: - Registry factory

    // Wiring-only function: each new shortcut adds a few lines of closure.
    // Splitting would obscure the shortcut → action mapping.
    // swiftlint:disable:next function_body_length
    private func buildRegistry(router: DefaultPlaybackActionRouter) -> PlaybackShortcutRegistry {
        #if DEBUG
        let forceSpiderAction: (@MainActor () -> Void)? = { [weak engine = self.engine, weak tm = self.toastManager] in
            guard let engine, let tm else { return }
            let isOn = engine.toggleForceSpider()
            tm.enqueue(PhospheneToast(
                severity: .info,
                copy: isOn ? "Spider forced: ON" : "Spider forced: OFF",
                duration: 3,
                conditionID: "debug.spider.forced"
            ))
        }
        // Cmd+] / Cmd+[ — direct preset cycle that bypasses the orchestrator.
        // Pure debug navigation for preset development (V.7.5 / V.7.6 etc.).
        // Toast announces the new preset name so Matt knows where he landed.
        let debugNext: (@MainActor () -> Void)? = { [weak engine = self.engine, weak tm = self.toastManager] in
            guard let engine else { return }
            engine.nextPreset()
            if let name = engine.presetLoader.currentPreset?.descriptor.name {
                tm?.enqueue(PhospheneToast(
                    severity: .info,
                    copy: "Preset → \(name)",
                    duration: 2,
                    conditionID: "debug.preset.cycle"
                ))
            }
        }
        let debugPrev: (@MainActor () -> Void)? = { [weak engine = self.engine, weak tm = self.toastManager] in
            guard let engine else { return }
            engine.previousPreset()
            if let name = engine.presetLoader.currentPreset?.descriptor.name {
                tm?.enqueue(PhospheneToast(
                    severity: .info,
                    copy: "Preset → \(name)",
                    duration: 2,
                    conditionID: "debug.preset.cycle"
                ))
            }
        }
        let audioStallCardAction: (@MainActor () -> Void)? = { [stall = $debugForceStallCard] in
            stall.wrappedValue.toggle()
        }
        #else
        let forceSpiderAction: (@MainActor () -> Void)? = nil
        let debugNext: (@MainActor () -> Void)? = nil
        let debugPrev: (@MainActor () -> Void)? = nil
        let audioStallCardAction: (@MainActor () -> Void)? = nil
        #endif
        let diagHoldAction: (@MainActor () -> Void)? = { [weak engine = self.engine, weak tm = self.toastManager] in
            guard let engine, let tm else { return }
            engine.diagnosticPresetLocked.toggle()
            let isOn = engine.diagnosticPresetLocked
            tm.enqueue(PhospheneToast(
                severity: .info,
                copy: isOn ? "Diagnostic hold ON" : "Diagnostic hold OFF",
                duration: 3,
                conditionID: "debug.diagnostic.hold"
            ))
        }
        return PlaybackShortcutRegistry(
            actionRouter: router,
            onToggleFullscreen: { [weak fo = self.fullscreenObserver] in
                fo?.toggleFullscreen()
            },
            onMoveToSecondaryDisplay: { [weak dm = self.displayManager] in
                if let dm {
                    dm.moveToSecondaryDisplay()
                }
            },
            onToggleOverlay: { [weak chromeVM] in
                chromeVM?.toggleOverlay()
            },
            onToggleDebug: { [weak engine = self.engine] in
                engine?.toggleDebugOverlay()
                // DASH.7.1: spring-choreographed toggle (D-088). Both surfaces
                // animate in/out via `withAnimation` — `showDebug` drives both
                // DebugOverlayView (Layer 5) and DashboardOverlayView (Layer 6).
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                    showDebug.toggle()
                }
            },
            onHandleEsc: { [weak fo = self.fullscreenObserver] in
                if fo?.isFullscreen == true {
                    fo?.toggleFullscreen()
                } else {
                    endSessionVM.requestEnd()
                }
            },
            onShowHelp: { showHelp = true },
            onShowPlanPreview: { showPlanPreview = true },
            onToggleDiagnosticHold: diagHoldAction,
            onToggleForceSpider: forceSpiderAction,
            onToggleAudioStallCard: audioStallCardAction,
            onDebugNextPreset: debugNext,
            onDebugPreviousPreset: debugPrev,
            onDecreaseBeatPhaseOffset: { [weak engine] in
                engine?.adjustBeatPhaseOffset(ms: -10)
            },
            onIncreaseBeatPhaseOffset: { [weak engine] in
                engine?.adjustBeatPhaseOffset(ms: +10)
            },
            onCycleBarPhaseOffset: { [weak engine] in
                engine?.cycleBarPhaseOffset()
            },
            onDecreaseAudioOutputLatency: { [weak engine] in
                engine?.adjustAudioOutputLatency(ms: -5)
            },
            onIncreaseAudioOutputLatency: { [weak engine] in
                engine?.adjustAudioOutputLatency(ms: +5)
            }
        )
    }
}
