// IdleView — Shown when SessionManager.state == .idle.
// U.1 stub: displays state name on black background.
// U.2: photosensitivity sheet on first appearance (persisted via UserDefaults).
// U.3 will add connector picker + ad-hoc CTA.

import SwiftUI

// MARK: - IdleView

@MainActor
struct IdleView: View {
    static let accessibilityID = "phosphene.view.idle"

    @State private var showPhotosensitivityNotice = false
    private let acknowledgementStore = PhotosensitivityAcknowledgementStore()

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
        .onAppear {
            if !acknowledgementStore.isAcknowledged {
                showPhotosensitivityNotice = true
            }
        }
        .sheet(isPresented: $showPhotosensitivityNotice) {
            PhotosensitivityNoticeView {
                acknowledgementStore.markAcknowledged()
                showPhotosensitivityNotice = false
            }
        }
    }
}
