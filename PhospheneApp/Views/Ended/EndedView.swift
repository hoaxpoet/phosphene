// EndedView — Shown when SessionManager.state == .ended.
// U.1 stub: displays state name on black background.
// U.10 adds session summary + new-session affordance.

import SwiftUI

// MARK: - EndedView

@MainActor
struct EndedView: View {
    static let accessibilityID = "phosphene.view.ended"

    var body: some View {
        VStack(spacing: 12) {
            Text(String(localized: "ended.headline"))
                .font(.largeTitle)
                .foregroundColor(.white)
            Text(String(localized: "ended.subtext"))
                .font(.body)
                .foregroundColor(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .accessibilityIdentifier(Self.accessibilityID)
    }
}
