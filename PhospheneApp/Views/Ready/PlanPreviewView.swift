// PlanPreviewView — Sheet presenting the session plan before playback (U.5 Parts B & D).
//
// Part B: Display only — rows, transitions, empty-state message.
// Part D: "Regenerate Plan" button wired; "Modify" deferred to U.5c.
// TODO(U.5c): Add full Modify editor (drag-to-reorder, transition overrides, mood overrides).

import Combine
import Orchestrator
import Presets
import Session
import SwiftUI

// MARK: - PlanPreviewView

/// Sheet displaying the planned preset sequence for the current session.
///
/// Presented from `ReadyView` when the user taps "Preview the plan".
/// Creates and owns `PlanPreviewViewModel` via `@StateObject`.
@MainActor
struct PlanPreviewView: View {
    static let accessibilityID         = "phosphene.view.planPreview"
    static let regenerateButtonID      = "phosphene.planPreview.regenerate"

    @StateObject private var viewModel: PlanPreviewViewModel

    @Environment(\.dismiss) private var dismiss

    // MARK: - Init

    init(
        initialPlan: PlannedSession?,
        planPublisher: AnyPublisher<PlannedSession?, Never>,
        onRegenerate: @escaping @MainActor (Set<TrackIdentity>, [TrackIdentity: PresetDescriptor]) -> Void
    ) {
        _viewModel = StateObject(wrappedValue: PlanPreviewViewModel(
            initialPlan: initialPlan,
            planPublisher: planPublisher,
            onRegenerate: onRegenerate
        ))
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.rows.isEmpty {
                    emptyState
                } else {
                    planList
                }
            }
            .navigationTitle(navTitle)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "plan_preview.close_button")) { dismiss() }
                }
            }
        }
        .frame(minWidth: 500, minHeight: 400)
        .accessibilityIdentifier(Self.accessibilityID)
    }

    // MARK: - Subviews

    private var navTitle: String {
        if viewModel.rows.isEmpty {
            return String(localized: "plan_preview.title_empty")
        }
        return String(format: String(localized: "plan_preview.title_tracks"), viewModel.rows.count)
    }

    private var planList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.rows) { row in
                    if let transition = row.incomingTransition {
                        PlanPreviewTransitionView(summary: transition)
                    }
                    PlanPreviewRowView(
                        row: row,
                        catalog: [],
                        onSwap: { track, preset in viewModel.swapPreset(for: track, to: preset) },
                        onResetLock: { track in viewModel.resetLock(for: track) },
                        onPreview: { viewModel.previewRow($0) }
                    )
                    Divider()
                        .background(Color.white.opacity(0.06))
                }
            }
        }
        .background(Color(white: 0.07))
        .safeAreaInset(edge: .bottom) { footer }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform.path")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text("No plan available.")
                .font(.headline)
                .foregroundColor(.primary)
            Text("Running in reactive mode — presets adapt in real time.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button {
                viewModel.regeneratePlan()
            } label: {
                HStack(spacing: 6) {
                    if viewModel.isRegenerating {
                        ProgressView().controlSize(.small)
                    }
                    Text(viewModel.isRegenerating
                         ? "\(String(localized: "plan_preview.regenerate_button"))\u{2026}"
                         : String(localized: "plan_preview.regenerate_button"))
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isRegenerating || viewModel.rows.isEmpty)
            .accessibilityIdentifier(Self.regenerateButtonID)

            // QR.4 / D-091: hidden until V.5 plan-modification work lands.
            // Tooltip lies ("coming in a future update" on a disabled control)
            // are bugs per the post-QR.4 UX contract — hide instead.
            #if ENABLE_PLAN_MODIFICATION
            // TODO(V.5): Full Modify editor — drag-to-reorder, transition overrides.
            Button(String(localized: "plan_preview.modify_button")) {}
                .disabled(true)
                .foregroundColor(.secondary)
            #endif
        }
        .padding(16)
        .background(.ultraThinMaterial)
    }
}
