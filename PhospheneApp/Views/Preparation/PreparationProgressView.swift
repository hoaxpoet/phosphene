// PreparationProgressView — Shown when SessionManager.state == .preparing.
// U.1 stub: displays state name on black background.
// U.4 adds per-track status list + progressive "Start now" CTA.

import SwiftUI

// MARK: - PreparationProgressView

@MainActor
struct PreparationProgressView: View {
    static let accessibilityID = "phosphene.view.preparing"

    var body: some View {
        VStack(spacing: 12) {
            Text("Preparing")
                .font(.largeTitle)
                .foregroundColor(.white)
            Text("Analyzing tracks…")
                .font(.body)
                .foregroundColor(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .accessibilityIdentifier(Self.accessibilityID)
    }
}
