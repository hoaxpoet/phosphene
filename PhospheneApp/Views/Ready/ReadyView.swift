// ReadyView — Shown when SessionManager.state == .ready (Increment U.5).
//
// Four surfaces per UX_SPEC §6.1–§6.4:
//  A. Layout: headline (source-aware), subtext, "Preview the plan" CTA, pulsing border.
//  B. Plan preview panel (sheet) — wired in Part B.
//  C. Background preset at 0.3× opacity — gradient placeholder until U.5b.
//  D. 90-second timeout overlay with Retry / End session.
//
// First-audio autodetect: ReadyViewModel owns FirstAudioDetector and emits
// shouldAdvanceToPlaying when signal is sustained ≥250 ms in .active.

import Audio
import Combine
import Orchestrator
import Presets
import Session
import SwiftUI

// MARK: - ReadyView

/// Top-level view for the `.ready` session state.
///
/// Creates and owns `ReadyViewModel` via `@StateObject`; all layout and
/// logic lives in the ViewModel. Auto-advances to `.playing` on first audio.
@MainActor
struct ReadyView: View {
    static let accessibilityID      = "phosphene.view.ready"
    static let headlineID           = "phosphene.ready.headline"
    static let previewPlanButtonID  = "phosphene.ready.previewPlan"
    static let endSessionButtonID   = "phosphene.ready.endSession"
    static let retryButtonID        = "phosphene.ready.retry"
    static let timeoutOverlayID     = "phosphene.ready.timeoutOverlay"

    @StateObject private var viewModel: ReadyViewModel

    /// Called by ContentView to advance .ready → .playing after audio confirmed.
    private let onBeginPlayback: () -> Void

    /// Plan publisher and regenerate closure forwarded to PlanPreviewView (Part B+D).
    private let planPublisher: AnyPublisher<PlannedSession?, Never>
    private let onRegenerate: @MainActor (Set<TrackIdentity>, [TrackIdentity: PresetDescriptor]) -> Void

    @State private var showingPlanPreview: Bool = false
    @State private var currentPlan: PlannedSession?

    // MARK: - Init

    init(
        sessionSource: PlaylistSource?,
        sessionManager: SessionManager,
        audioSignalStatePublisher: AnyPublisher<AudioSignalState, Never>,
        planPublisher: AnyPublisher<PlannedSession?, Never>,
        onBeginPlayback: @escaping () -> Void,
        onRegenerate: @escaping @MainActor (Set<TrackIdentity>, [TrackIdentity: PresetDescriptor]) -> Void,
        reduceMotion: Bool
    ) {
        _viewModel = StateObject(wrappedValue: ReadyViewModel(
            sessionSource: sessionSource,
            sessionManager: sessionManager,
            audioSignalStatePublisher: audioSignalStatePublisher,
            planPublisher: planPublisher,
            reduceMotion: reduceMotion
        ))
        self.planPublisher = planPublisher
        self.onBeginPlayback = onBeginPlayback
        self.onRegenerate = onRegenerate
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            ReadyBackgroundPresetView()

            VStack(spacing: 0) {
                Spacer()
                mainContent
                Spacer()
                endSessionLink
                    .padding(.bottom, 28)
            }

            ReadyPulsingBorder(reduceMotion: viewModel.reduceMotion)

            if viewModel.isTimedOut {
                timeoutOverlay
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier(Self.accessibilityID)
        .onReceive(viewModel.shouldAdvanceToPlaying) { _ in
            onBeginPlayback()
        }
        .onReceive(planPublisher.compactMap { $0 }) { plan in
            currentPlan = plan
        }
        .sheet(isPresented: $showingPlanPreview) {
            PlanPreviewView(
                initialPlan: currentPlan,
                planPublisher: planPublisher,
                onRegenerate: onRegenerate
            )
        }
    }

    // MARK: - Subviews

    private var planSummary: String {
        if viewModel.formattedDuration.isEmpty {
            return "\(viewModel.trackCount) tracks."
        }
        return String(
            format: String(localized: "ready.plan_summary"),
            viewModel.trackCount,
            viewModel.formattedDuration
        )
    }

    private var mainContent: some View {
        VStack(spacing: 20) {
            Text(String(localized: "ready.headline"))
                .font(.largeTitle.weight(.thin))
                .foregroundColor(.white)
                .accessibilityIdentifier(Self.headlineID)

            Text(String(format: String(localized: "ready.press_play"), viewModel.sourceName))
                .font(.title3)
                .foregroundColor(.white.opacity(0.85))
                .multilineTextAlignment(.center)

            if viewModel.trackCount > 0 {
                Text(planSummary)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.5))
            }

            Button(String(localized: "ready.preview_plan_button")) {
                showingPlanPreview = true
            }
            .buttonStyle(.bordered)
            .disabled(!viewModel.planPreviewEnabled)
            .opacity(viewModel.planPreviewEnabled ? 1 : 0.4)
            .padding(.top, 12)
            .accessibilityIdentifier(Self.previewPlanButtonID)
        }
        .padding(.horizontal, 40)
    }

    private var endSessionLink: some View {
        Button(String(localized: "ready.end_session_button")) {
            viewModel.endSession()
        }
        .foregroundColor(.white.opacity(0.35))
        .font(.caption)
        .accessibilityIdentifier(Self.endSessionButtonID)
    }

    private var timeoutOverlay: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Text(String(localized: "ready.timeout.headline"))
                    .font(.headline)
                    .foregroundColor(.white)
                Text(String(format: String(localized: "ready.timeout.subtext"), viewModel.sourceName))
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)

                HStack(spacing: 16) {
                    Button(String(localized: "ready.timeout.retry_button")) {
                        viewModel.retry()
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier(Self.retryButtonID)

                    Button(String(localized: "ready.end_session_button")) {
                        viewModel.endSession()
                    }
                    .foregroundColor(.white.opacity(0.6))
                }
            }
            .padding(32)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(40)
        }
        .accessibilityIdentifier(Self.timeoutOverlayID)
    }
}
