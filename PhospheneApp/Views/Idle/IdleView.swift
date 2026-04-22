// IdleView — Shown when SessionManager.state == .idle.
// U.1 stub: displays state name on black background.
// U.2 adds permission onboarding; U.3 adds connector picker + ad-hoc CTA.

import SwiftUI

// MARK: - IdleView

@MainActor
struct IdleView: View {
    static let accessibilityID = "phosphene.view.idle"

    var body: some View {
        VStack(spacing: 12) {
            Text("Phosphene")
                .font(.largeTitle)
                .foregroundColor(.white)
            Text("Connect a playlist to begin")
                .font(.body)
                .foregroundColor(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .accessibilityIdentifier(Self.accessibilityID)
    }
}
