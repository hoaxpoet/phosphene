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

    // MARK: - Owned (publisher-injected @StateObjects)

    @StateObject private var chromeVM: PlaybackChromeViewModel
    @StateObject private var toastManager = ToastManager()
    @StateObject private var endSessionVM: EndSessionConfirmViewModel

    // MARK: - View State

    @State private var showDebug: Bool = false
    @State private var showHelp: Bool = false
    @State private var showPlanPreview: Bool = false
    @State private var showSettings: Bool = false
    @StateObject private var settingsStore = SettingsStore()
    @State private var currentRegistry: PlaybackShortcutRegistry?
    @State private var keyMonitor = PlaybackKeyMonitor()
    @State private var fullscreenObserver = FullscreenObserver()
    @State private var actionRouter: DefaultPlaybackActionRouter?
    @State private var playbackErrorBridge: PlaybackErrorBridge?
    @State private var displayManager: DisplayManager?
    @State private var multiDisplayBridge: MultiDisplayToastBridge?
    @State private var displayChangeCoordinator: DisplayChangeCoordinator?
    @State private var captureModeSwitchCoordinator: CaptureModeSwitchCoordinator?

    @Namespace private var trackAnimNamespace

    // MARK: - Init

    init(
        sessionManager: SessionManager,
        audioSignalStatePublisher: AnyPublisher<AudioSignalState, Never>,
        currentTrackPublisher: AnyPublisher<TrackMetadata?, Never>,
        currentPresetNamePublisher: AnyPublisher<String?, Never>,
        livePlanPublisher: AnyPublisher<PlannedSession?, Never>,
        reduceMotionPublisher: AnyPublisher<Bool, Never> = Just(false).eraseToAnyPublisher(),
        progressiveReadinessPublisher: AnyPublisher<ProgressiveReadinessLevel, Never> =
            Just(.fullyPrepared).eraseToAnyPublisher(),
        onEndSession: @escaping () -> Void,
        reduceMotion: Bool
    ) {
        self.onEndSession = onEndSession
        self.reduceMotion = reduceMotion
        _chromeVM = StateObject(wrappedValue: PlaybackChromeViewModel(
            audioSignalStatePublisher: audioSignalStatePublisher,
            currentTrackPublisher: currentTrackPublisher,
            currentPresetNamePublisher: currentPresetNamePublisher,
            livePlanPublisher: livePlanPublisher,
            reduceMotionPublisher: reduceMotionPublisher,
            progressiveReadinessPublisher: progressiveReadinessPublisher
        ))
        _endSessionVM = StateObject(wrappedValue: EndSessionConfirmViewModel(
            sessionManager: sessionManager
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
                onEndSession: { endSessionVM.requestEnd() }
            )

            // Layer 4: Shortcut help overlay
            if showHelp, let registry = currentRegistry {
                ShortcutHelpOverlayView(
                    shortcuts: registry.shortcuts,
                    onDismiss: { showHelp = false }
                )
            }

            // Layer 5: Debug overlay
            if showDebug {
                DebugOverlayView(engine: engine)
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        .accessibilityIdentifier(Self.accessibilityID)
        .confirmationDialog(
            "End this session?",
            isPresented: $endSessionVM.isPresented,
            titleVisibility: .visible
        ) {
            Button("End session", role: .destructive) { endSessionVM.confirm() }
            Button("Cancel", role: .cancel) { endSessionVM.cancel() }
        } message: {
            Text("The visualizer session will stop.")
        }
        .onContinuousHover { phase in
            if case .active = phase { chromeVM.onActivity() }
        }
        .onAppear { setup() }
        .onDisappear { teardown() }
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

        // §9.4 playback errors — silence at 15s, condition-ID auto-dismiss
        let errorBridge = PlaybackErrorBridge(
            audioSignalStatePublisher: engine.$audioSignalState.eraseToAnyPublisher(),
            toastManager: toastManager
        )
        playbackErrorBridge = errorBridge

        // 7.2: capture-mode switch coordinator — 5s grace window on mode changes.
        captureModeSwitchCoordinator = CaptureModeSwitchCoordinator(
            engine: engine,
            playbackErrorBridge: errorBridge,
            settingsStore: settingsStore
        )

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
        #else
        let forceSpiderAction: (@MainActor () -> Void)? = nil
        let debugNext: (@MainActor () -> Void)? = nil
        let debugPrev: (@MainActor () -> Void)? = nil
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
                showDebug.toggle()
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
            onDebugNextPreset: debugNext,
            onDebugPreviousPreset: debugPrev,
            onDecreaseBeatPhaseOffset: { [weak engine] in
                engine?.adjustBeatPhaseOffset(ms: -10)
            },
            onIncreaseBeatPhaseOffset: { [weak engine] in
                engine?.adjustBeatPhaseOffset(ms: +10)
            }
        )
    }
}
