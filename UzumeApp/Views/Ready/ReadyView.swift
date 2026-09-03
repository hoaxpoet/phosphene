// ReadyView — the streaming handoff: Uzume is ready, the listener presses play.
// (DS.5 / D-240)
//
// The cave the listener watched widen through preparation is fully open behind the
// copy — Ready is the arrival, not a waiting room. Uzume still genuinely does not
// control a streaming source, so this screen keeps asking for the one thing only the
// listener can do (press play in Spotify / Apple Music), listens for real audio
// (FirstAudioDetector, ≥250 ms sustained, UX_SPEC §6.3), and keeps the 90 s timeout
// card (§6.4). "Begin now" — a bordered button, the same weight as End session — starts
// the show without waiting for audio. Either path lands in `.playing`, where
// PlaybackArrivalOverlay runs the camera push through this same aperture.
//
// Local-file sessions never see this view: ContentView routes them to
// LocalFileCountdownView, because there is no external app to press play in.

import Audio
import Combine
import Orchestrator
import Session
import SwiftUI

// MARK: - ReadyView

/// Top-level view for the `.ready` session state of a streaming session.
///
/// Creates and owns `ReadyViewModel` via `@StateObject`; the detector, timeout and
/// copy live there. Advances to `.playing` on first audio or on "Begin now".
@MainActor
struct ReadyView: View {
    static let accessibilityID      = "uzume.view.ready"
    static let headlineID           = "uzume.ready.headline"
    static let beginNowButtonID     = "uzume.ready.beginNow"
    static let endSessionButtonID   = "uzume.ready.endSession"
    static let retryButtonID        = "uzume.ready.retry"
    static let timeoutOverlayID     = "uzume.ready.timeoutOverlay"

    @StateObject private var viewModel: ReadyViewModel

    /// What Uzume heard — the same character the preparation aperture was drawn with.
    private let character: PreparationCharacter

    /// Called to advance .ready → .playing, on first audio or on "Begin now".
    private let onBeginPlayback: () -> Void

    // MARK: - Init

    init(
        origin: SessionOrigin?,
        character: PreparationCharacter,
        sessionManager: SessionManager,
        audioSignalStatePublisher: AnyPublisher<AudioSignalState, Never>,
        planPublisher: AnyPublisher<PlannedSession?, Never>,
        onBeginPlayback: @escaping () -> Void,
        reduceMotion: Bool
    ) {
        _viewModel = StateObject(wrappedValue: ReadyViewModel(
            origin: origin,
            sessionManager: sessionManager,
            audioSignalStatePublisher: audioSignalStatePublisher,
            planPublisher: planPublisher,
            reduceMotion: reduceMotion
        ))
        self.character = character
        self.onBeginPlayback = onBeginPlayback
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            UzumeAppColor.canvas.ignoresSafeArea()
            OpenAperture(character: character, reduceMotion: viewModel.reduceMotion)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()
                mainContent
                    .padding(.bottom, 40)
            }

            if viewModel.isTimedOut {
                timeoutOverlay
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier(Self.accessibilityID)
        .onReceive(viewModel.shouldAdvanceToPlaying) { _ in
            onBeginPlayback()
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

    /// Copy sits low, under the mouth of the cave, so it reads against rock and spill
    /// rather than against the light itself.
    private var mainContent: some View {
        VStack(spacing: 20) {
            Text(String(localized: "ready.headline"))
                .font(.largeTitle.weight(.thin))
                .foregroundColor(UzumeAppColor.textPrimary)
                .legibleOverLight()
                .accessibilityIdentifier(Self.headlineID)

            Text(String(format: String(localized: "ready.press_play"), viewModel.sourceName))
                .font(.title3)
                .foregroundColor(UzumeAppColor.textSecondary)
                .multilineTextAlignment(.center)
                .legibleOverLight()

            if viewModel.trackCount > 0 {
                Text(planSummary)
                    .font(.subheadline)
                    .foregroundColor(UzumeAppColor.textTertiary)
                    .legibleOverLight()
            }

            HStack(spacing: 16) {
                Button(String(localized: "ready.end_session_button")) {
                    viewModel.endSession()
                }
                .buttonStyle(.bordered)
                .foregroundColor(UzumeAppColor.textSecondary)
                .accessibilityIdentifier(Self.endSessionButtonID)

                Button(String(localized: "ready.begin_now_button")) {
                    viewModel.beginNow()
                }
                .buttonStyle(.bordered)
                .foregroundColor(UzumeAppColor.textSecondary)
                .accessibilityHint(String(localized: "a11y.ready.begin_now.hint"))
                .accessibilityIdentifier(Self.beginNowButtonID)
            }
            .padding(.top, 12)
        }
        .padding(.horizontal, 40)
    }

    private var timeoutOverlay: some View {
        ZStack {
            UzumeAppColor.Performance.sheetScrim
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Text(String(localized: "ready.timeout.headline"))
                    .font(.headline)
                    .foregroundColor(UzumeAppColor.textPrimary)
                Text(String(format: String(localized: "ready.timeout.subtext"), viewModel.sourceName))
                    .font(.subheadline)
                    .foregroundColor(UzumeAppColor.textSecondary)
                    .multilineTextAlignment(.center)

                HStack(spacing: 16) {
                    Button(String(localized: "ready.timeout.retry_button")) {
                        viewModel.retry()
                    }
                    .buttonStyle(.borderedProminent)
                    .uzumeTint()
                    .accessibilityIdentifier(Self.retryButtonID)

                    Button(String(localized: "ready.end_session_button")) {
                        viewModel.endSession()
                    }
                    .foregroundColor(UzumeAppColor.textTertiary)
                }
            }
            .padding(32)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: UzumeAppRadius.lg))
            .padding(40)
        }
        .accessibilityIdentifier(Self.timeoutOverlayID)
    }
}

// MARK: - Legibility over the aperture

private extension View {
    /// A tight dark halo so text holds up wherever the spill happens to be bright.
    func legibleOverLight() -> some View {
        shadow(color: UzumeAppColor.canvas.opacity(0.9), radius: 3)
            .shadow(color: UzumeAppColor.canvas.opacity(0.7), radius: 18)
    }
}
