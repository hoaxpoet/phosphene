// ContentView — Pure switch on SessionManager.state.
// No layout, no logic beyond routing. Each state maps to one top-level view.

import SwiftUI

// MARK: - ContentView

/// Routes to the correct top-level view based on `SessionManager.state`.
///
/// All logic lives in the per-state views and their view models.
/// `SessionStateViewModel` bridges the engine's state machine into the view layer.
struct ContentView: View {
    @StateObject var viewModel: SessionStateViewModel

    init(viewModel: SessionStateViewModel) {
        self._viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        Group {
            switch viewModel.state {
            case .idle:       IdleView()
            case .connecting: ConnectingView()
            case .preparing:  PreparationProgressView()
            case .ready:      ReadyView()
            case .playing:    PlaybackView()
            case .ended:      EndedView()
            }
        }
    }
}
