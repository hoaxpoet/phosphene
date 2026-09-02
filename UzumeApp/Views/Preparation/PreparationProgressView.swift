// PreparationProgressView — Shown when SessionManager.state == .preparing.
//
// DS.4 (D-238): the wait is the overture. Two views behind a preference —
//   mysterious (default)  the cave (`PreparationAperture`), opening as Uzume hears the
//                         playlist; never names a track. Failures surface as a count
//                         line that opens the detailed view.
//   detailed              the track list (`PreparationTrackRow`), reporting what Uzume
//                         heard in each track once it is heard.
// The header and the progress bar are gone from both. `NoticeBanner` keeps its slot
// above; "Start now" and "Cancel" stay buttons below — the aperture may signal
// readiness, it never becomes the control.
//
// U.7: Owns a PreparationErrorViewModel that watches network reachability and track
// statuses to decide whether to show a NoticeBanner above (non-blocking warning) or
// replace the entire body with RecoveryScreen (catastrophic failure).

import Combine
import Session
import Shared
import SwiftUI

// MARK: - PreparationProgressView

/// Top-level view for the `.preparing` session state.
///
/// Creates and owns a `PreparationProgressViewModel` via `@StateObject` so the
/// ViewModel survives SwiftUI re-renders within the `.preparing` state. Cancel
/// teardown is forwarded to `SessionManager.cancel()` — state changes handled
/// reactively via `ContentView`'s switch on `SessionManager.state`.
@MainActor
struct PreparationProgressView: View {
    static let accessibilityID  = "uzume.view.preparing"
    static let cancelButtonID   = "uzume.preparing.cancel"
    static let startNowButtonID = "uzume.preparing.startNow"
    static let failedCountID    = "uzume.preparing.failedCount"

    @StateObject private var viewModel: PreparationProgressViewModel
    @StateObject private var errorViewModel: PreparationErrorViewModel

    /// The one app-wide store (D-091): the preparation-view preference is read live,
    /// so switching it mid-preparation swaps views without disturbing preparation.
    @EnvironmentObject private var settingsStore: SettingsStore
    /// Effective reduce-motion (system flag combined with the in-app preference).
    @EnvironmentObject private var accessibilityState: AccessibilityState

    private let onCancel: () -> Void
    private let onStartNow: () -> Void
    private let onPickAnotherPlaylist: (() -> Void)?
    private let onStartReactive: (() -> Void)?

    // 7.2: NetworkRecoveryCoordinator — resumes network-failed tracks on connectivity restore.
    @State private var networkRecoveryCoordinator: NetworkRecoveryCoordinator?
    private let sessionManager: SessionManager?
    private let reachabilityForRecovery: (any ReachabilityPublishing)?

    // MARK: - Init

    /// Create the view, instantiating its ViewModels from the given publisher and reachability.
    ///
    /// - Parameters:
    ///   - publisher: The `SessionPreparer`-backed publisher to observe.
    ///   - tracks: Ordered playlist — rows appear in this order.
    ///   - progressiveReadinessPublisher: Emits `ProgressiveReadinessLevel` from `SessionManager`;
    ///     drives the "Start now" CTA and the aperture. Defaults to `.preparing` for previews.
    ///   - reachability: Injectable reachability monitor (defaults to `ReachabilityMonitor`).
    ///   - onCancel: Called when cancel is confirmed; caller transitions state.
    ///   - onStartNow: Called when "Start now" is tapped; typically forwards to `SessionManager.startNow()`.
    ///   - onPickAnotherPlaylist: Called from full-screen failure CTA (optional).
    ///   - onStartReactive: Called from "Start reactive mode" failure CTA (optional).
    init(
        publisher: any PreparationProgressPublishing,
        tracks: [TrackIdentity],
        progressiveReadinessPublisher: AnyPublisher<ProgressiveReadinessLevel, Never> =
            Just(.preparing).eraseToAnyPublisher(),
        reachability: any ReachabilityPublishing = ReachabilityMonitor(),
        sessionManager: SessionManager? = nil,
        onCancel: @escaping () -> Void,
        onStartNow: @escaping () -> Void = {},
        onPickAnotherPlaylist: (() -> Void)? = nil,
        onStartReactive: (() -> Void)? = nil
    ) {
        _viewModel = StateObject(
            wrappedValue: PreparationProgressViewModel(
                publisher: publisher,
                trackList: tracks,
                progressiveReadinessPublisher: progressiveReadinessPublisher,
                onStartNow: onStartNow
            )
        )
        _errorViewModel = StateObject(
            wrappedValue: PreparationErrorViewModel(
                statusPublisher: publisher.trackStatusesPublisher,
                reachability: reachability,
                totalTrackCount: tracks.count
            )
        )
        self.onCancel = onCancel
        self.onStartNow = onStartNow
        self.onPickAnotherPlaylist = onPickAnotherPlaylist
        self.onStartReactive = onStartReactive
        self.sessionManager = sessionManager
        self.reachabilityForRecovery = reachability
    }

    // MARK: - Body

    var body: some View {
        Group {
            if case .fullScreen(let error) = errorViewModel.presentationState {
                RecoveryScreen(
                    error: error,
                    primaryLabel: String(localized: "preparation.failure.pick_playlist_button"),
                    primaryAction: onPickAnotherPlaylist ?? onCancel,
                    secondaryLabel: String(localized: "preparation.failure.start_reactive_button"),
                    secondaryAction: onStartReactive
                )
            } else {
                normalBody
            }
        }
    }

    // MARK: - Normal Body

    private var normalBody: some View {
        ZStack {
            UzumeAppColor.canvas.ignoresSafeArea()

            VStack(spacing: 0) {
                bannerSlot
                switch settingsStore.preparationView {
                case .mysterious: mysteriousBody
                case .detailed:   trackList
                }
                bottomBar
            }
        }
        .accessibilityIdentifier(Self.accessibilityID)
        .onAppear {
            // 7.2: wire NetworkRecoveryCoordinator when a real session manager is present.
            if let sm = sessionManager, let reach = reachabilityForRecovery {
                let coordinator = NetworkRecoveryCoordinator(
                    sessionManager: sm,
                    reachability: reach,
                    sessionStatePublisher: sm.$state.eraseToAnyPublisher()
                )
                coordinator.resetForNewSession()
                networkRecoveryCoordinator = coordinator
            }
        }
        .onDisappear {
            networkRecoveryCoordinator = nil
        }
        .confirmationDialog(
            String(localized: "preparation.cancel.confirm_title"),
            isPresented: $viewModel.showCancelConfirmation,
            titleVisibility: .visible
        ) {
            Button(String(localized: "preparation.cancel.confirm_button"), role: .destructive) {
                viewModel.cancel()
                onCancel()
            }
            Button(String(localized: "preparation.cancel.keep_button"), role: .cancel) {
                viewModel.showCancelConfirmation = false
            }
        } message: {
            Text(String(localized: "preparation.cancel.confirm_message"))
        }
    }

    // MARK: - Sub-Views

    @ViewBuilder
    private var bannerSlot: some View {
        if case .banner(let error) = errorViewModel.presentationState {
            NoticeBanner(error: error)
        }
    }

    /// The cave, and beneath it the two facts the light conveys, as text: how many
    /// heard, and — when tracks fail — how many, with the detailed view one tap away.
    private var mysteriousBody: some View {
        VStack(spacing: 0) {
            PreparationAperture(
                openness: ApertureStop.openness(
                    level: viewModel.readinessLevel,
                    heard: viewModel.counts.ready,
                    total: viewModel.counts.total
                ),
                character: PreparationCharacter(profiles: viewModel.heardProfiles),
                heard: viewModel.counts.ready,
                total: viewModel.counts.total,
                canStart: viewModel.canStartNow,
                reduceMotion: accessibilityState.reduceMotion
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack {
                Text(verbatim: heardLine)
                    .font(.caption)
                    .foregroundColor(UzumeAppColor.textTertiary)
                Spacer()
                if viewModel.counts.failed > 0 {
                    Button(failedLine) {
                        settingsStore.preparationView = .detailed
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundColor(UzumeAppColor.textTertiary)
                    .accessibilityHint(String(localized: "a11y.preparing.failed_count.hint"))
                    .accessibilityIdentifier(Self.failedCountID)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
        }
    }

    private var heardLine: String {
        let total = viewModel.counts.total
        let key = total == 1 ? "preparation.heard_count_one" : "preparation.heard_count_other"
        return String(format: String(localized: String.LocalizationValue(key)), viewModel.counts.ready, total)
    }

    private var failedLine: String {
        let failed = viewModel.counts.failed
        return failed == 1
            ? String(localized: "preparation.failed_count_one")
            : String(format: String(localized: "preparation.failed_count_other"), failed)
    }

    private var trackList: some View {
        Group {
            if viewModel.rows.isEmpty {
                VStack {
                    Spacer()
                    Text(String(localized: "preparation.empty_state"))
                        .foregroundColor(UzumeAppColor.textDisabled)
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(viewModel.rows) { row in
                            PreparationTrackRow(row: row, profile: viewModel.profiles[row.id])
                                .padding(.horizontal, 24)

                            if row.id != viewModel.rows.last?.id {
                                Divider()
                                    .background(UzumeAppColor.lineSubtle)
                                    .padding(.horizontal, 24)
                            }
                        }
                    }
                    .padding(.top, 16)
                    .padding(.bottom, 16)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var bottomBar: some View {
        HStack(spacing: 16) {
            Button(String(localized: "preparation.cancel_button")) {
                viewModel.requestCancel()
                if !viewModel.showCancelConfirmation { onCancel() }
            }
            .buttonStyle(.bordered)
            .foregroundColor(UzumeAppColor.textSecondary)
            .accessibilityIdentifier(Self.cancelButtonID)

            if viewModel.canStartNow {
                Button(startNowLabel) {
                    viewModel.startNow()
                }
                .buttonStyle(.borderedProminent)
                .uzumeTint()
                .accessibilityIdentifier(Self.startNowButtonID)
            }
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 24)
    }

    private var startNowLabel: String {
        let count = viewModel.readyTrackCount
        return String(format: String(localized: "preparation.start_now_button_with_count"), count)
    }
}
