// PreparationProgressView — Shown when SessionManager.state == .preparing.
// Per-track status list, aggregate progress bar, cancel affordance, and
// "Start now" CTA (active once SessionManager.progressiveReadinessLevel >= .readyForFirstTracks).
//
// U.7: Owns a PreparationErrorViewModel that watches network reachability and track
// statuses to decide whether to show a TopBannerView above the list (non-blocking
// warning) or replace the entire list with PreparationFailureView (catastrophic failure).

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
    static let accessibilityID  = "phosphene.view.preparing"
    static let cancelButtonID   = "phosphene.preparing.cancel"
    static let startNowButtonID = "phosphene.preparing.startNow"

    @StateObject private var viewModel: PreparationProgressViewModel
    @StateObject private var errorViewModel: PreparationErrorViewModel

    private let playlistName: String
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
    ///   - playlistName: Display name shown in the subtitle (may be empty).
    ///   - progressiveReadinessPublisher: Emits `ProgressiveReadinessLevel` from `SessionManager`;
    ///     drives the "Start now" CTA. Defaults to `.preparing` (CTA disabled) for previews.
    ///   - reachability: Injectable reachability monitor (defaults to `ReachabilityMonitor`).
    ///   - onCancel: Called when cancel is confirmed; caller transitions state.
    ///   - onStartNow: Called when "Start now" is tapped; typically forwards to `SessionManager.startNow()`.
    ///   - onPickAnotherPlaylist: Called from full-screen failure CTA (optional).
    ///   - onStartReactive: Called from "Start reactive mode" failure CTA (optional).
    init(
        publisher: any PreparationProgressPublishing,
        tracks: [TrackIdentity],
        playlistName: String = "",
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
        self.playlistName = playlistName
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
                PreparationFailureView(
                    error: error,
                    onPickAnotherPlaylist: onPickAnotherPlaylist ?? onCancel,
                    onStartReactive: onStartReactive
                )
            } else {
                normalBody
            }
        }
    }

    // MARK: - Normal Body

    private var normalBody: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                bannerSlot
                header
                progressBar
                trackList
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
            TopBannerView(error: error)
        }
    }

    private var header: some View {
        VStack(spacing: 4) {
            Text(String(localized: "preparation.header.title"))
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.white)

            let total   = viewModel.counts.total
            let suffix  = total == 1 ? "track" : "tracks"
            let subtitle = playlistName.isEmpty
                ? "\(total) \(suffix)"
                : "\(total) \(suffix) from \(playlistName)"

            Text(subtitle)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.5))
        }
        .padding(.top, 32)
        .padding(.bottom, 16)
        .padding(.horizontal, 24)
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.1))
                    .frame(height: 4)

                Capsule()
                    .fill(Color.white.opacity(0.7))
                    .frame(width: geo.size.width * viewModel.aggregateProgress, height: 4)
                    .animation(.easeInOut(duration: 0.3), value: viewModel.aggregateProgress)
            }
        }
        .frame(height: 4)
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
    }

    private var trackList: some View {
        Group {
            if viewModel.rows.isEmpty {
                VStack {
                    Spacer()
                    Text(String(localized: "preparation.empty_state"))
                        .foregroundColor(.white.opacity(0.4))
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(viewModel.rows) { row in
                            TrackPreparationRow(row: row)
                                .padding(.horizontal, 24)

                            if row.id != viewModel.rows.last?.id {
                                Divider()
                                    .background(Color.white.opacity(0.07))
                                    .padding(.horizontal, 24)
                            }
                        }
                    }
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
            .foregroundColor(.white.opacity(0.7))
            .accessibilityIdentifier(Self.cancelButtonID)

            if viewModel.canStartNow {
                Button(startNowLabel) {
                    viewModel.startNow()
                }
                .buttonStyle(.borderedProminent)
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
