// CaptureStateSurface — the capture/signal-chain state, extracted from
// VisualizerEngine (R3.2 / PUB.10, CLEAN Phase 8 / ultra-review R3).
//
// The three signal-chain surfaces the playback views and error bridge bind to
// (tap signal state, ASH.1 health classification, Screen Recording grant) get
// ONE owner with `private(set)` publication and semantic mutators — the same
// recipe as NowPlayingSurface (R3.1): a path can no longer write one of these
// from an arbitrary thread or leave a sibling stale by convention.
//
// Membership (Task-1 decision, PUB.10): `isCapturing` stays engine-side. Its
// writers are the CSV feature-capture start/stop ('C'-key diagnostics), not
// the tap chain — no view, publisher, or bridge consumes it. A later
// diagnostics slice can take it; this surface holds exactly the trio every
// signal-chain consumer (PlaybackErrorBridge, ReadyViewModel,
// PlaybackChromeViewModel, FirstAudioDetector, DebugOverlayView) reads.
//
// Threading: main-thread only (SwiftUI @Published writes), enforced by
// dispatchPrecondition. Both live writers arrive off-main (the real-time tap
// callback and SignalHealthMonitor.onHealthChanged) and hop via
// `Task { @MainActor }` at the call site — the hop stays at the writer, the
// precondition stays here. VisualizerEngine bridges this object's
// objectWillChange into its own so existing `@EnvironmentObject var engine`
// observers keep re-rendering.

import Audio
import Combine
import Foundation

// MARK: - CaptureStateSurface

/// Single owner of the capture/signal-chain surface. See file header.
final class CaptureStateSurface: ObservableObject {

    // MARK: - Published surface (read-only outside; mutate via the methods below)

    /// Current audio signal state — `.silent` indicates DRM-triggered tap silencing.
    @Published private(set) var audioSignalState: AudioSignalState = .active

    /// Latest classified signal health, surfaced in the debug overlay (ASH.1)
    /// and the band=low low-level nudge (ASH.2 / D-184).
    @Published private(set) var signalHealth = SignalHealth()

    /// Whether screen capture permission has been granted.
    @Published private(set) var hasScreenCapturePermission = false

    // MARK: - Mutators (main-thread only)

    /// Publish a tap signal-state transition (from the real-time tap callback,
    /// after its `Task { @MainActor }` hop).
    func setSignalState(_ state: AudioSignalState) {
        dispatchPrecondition(condition: .onQueue(.main))
        audioSignalState = state
    }

    /// Publish a health classification change (SignalHealthMonitor publishes
    /// on state CHANGE only, not per-window — ASH.1).
    func setSignalHealth(_ health: SignalHealth) {
        dispatchPrecondition(condition: .onQueue(.main))
        signalHealth = health
    }

    /// Record the Screen Recording grant (startAudio preflight/request, and
    /// the denied-path poll loop).
    func setScreenCapturePermission(_ granted: Bool) {
        dispatchPrecondition(condition: .onQueue(.main))
        hasScreenCapturePermission = granted
    }
}
