// ConnectorTileView — Reusable tile for ConnectorPickerView.
// Presents an SF Symbol icon, title, and subtitle. Disabled tiles show an
// alternate caption and an optional secondary action button.

import SwiftUI

// MARK: - ConnectorTileView

struct ConnectorTileView: View {
    static let accessibilityIDPrefix = "phosphene.connector.tile"

    let type: ConnectorType
    let isEnabled: Bool
    /// Caption shown instead of subtitle when the tile is disabled.
    var disabledCaption: String?
    /// Label for an optional secondary button shown only in the disabled state.
    var secondaryActionLabel: String?
    var onSecondaryAction: (() -> Void)?

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: type.systemImage)
                .font(.title2)
                .frame(width: 32)
                .foregroundColor(isEnabled ? .white : .white.opacity(0.3))

            VStack(alignment: .leading, spacing: 4) {
                Text(type.title)
                    .font(.headline)
                    .foregroundColor(isEnabled ? .white : .white.opacity(0.4))

                if isEnabled {
                    Text(type.subtitle)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.5))
                } else if let caption = disabledCaption {
                    Text(caption)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.4))
                }
            }

            Spacer()

            if isEnabled {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.3))
            } else if let label = secondaryActionLabel, let action = onSecondaryAction {
                Button(label) { action() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isEnabled ? Color.white.opacity(0.07) : Color.white.opacity(0.03))
        )
        .accessibilityIdentifier("\(Self.accessibilityIDPrefix).\(type.rawValue)")
    }
}
