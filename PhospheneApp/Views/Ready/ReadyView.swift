// ReadyView — Shown when SessionManager.state == .ready.
// U.1 stub: displays state name on black background.
// U.5 adds "Press play in your music app" handoff message + plan preview.

import SwiftUI

// MARK: - ReadyView

@MainActor
struct ReadyView: View {
    static let accessibilityID = "phosphene.view.ready"

    var body: some View {
        VStack(spacing: 12) {
            Text("Ready")
                .font(.largeTitle)
                .foregroundColor(.white)
            Text("Press play in your music app")
                .font(.body)
                .foregroundColor(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .accessibilityIdentifier(Self.accessibilityID)
    }
}
