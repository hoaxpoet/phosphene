// ConnectingView — Shown when SessionManager.state == .connecting.
// U.1 stub: displays state name on black background.
// U.3 adds per-connector spinner + cancel affordance.

import SwiftUI

// MARK: - ConnectingView

@MainActor
struct ConnectingView: View {
    static let accessibilityID = "phosphene.view.connecting"

    var body: some View {
        VStack(spacing: 12) {
            Text("Connecting…")
                .font(.largeTitle)
                .foregroundColor(.white)
            Text("Reading your playlist")
                .font(.body)
                .foregroundColor(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .accessibilityIdentifier(Self.accessibilityID)
    }
}
