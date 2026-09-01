// ConnectorTileView — Reusable tile for ConnectorPickerView.
// Presents an SF Symbol icon, title, and subtitle. Disabled tiles show an
// alternate caption and an optional secondary action button.

import SwiftUI

// MARK: - ConnectorTileView

struct ConnectorTileView: View {
    static let accessibilityIDPrefix = "uzume.connector.tile"

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
                .foregroundColor(isEnabled ? UzumeAppColor.textPrimary : UzumeAppColor.textDisabled)

            VStack(alignment: .leading, spacing: 4) {
                Text(type.title)
                    .font(.headline)
                    .foregroundColor(isEnabled ? UzumeAppColor.textPrimary : UzumeAppColor.textDisabled)

                if isEnabled {
                    Text(type.subtitle)
                        .font(.caption)
                        .foregroundColor(UzumeAppColor.textTertiary)
                } else if let caption = disabledCaption {
                    Text(caption)
                        .font(.caption)
                        .foregroundColor(UzumeAppColor.textDisabled)
                }
            }

            Spacer()

            if isEnabled {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(UzumeAppColor.textDisabled)
            } else if let label = secondaryActionLabel, let action = onSecondaryAction {
                Button(label) { action() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: UzumeAppRadius.md)
                .fill(isEnabled ? UzumeAppColor.surfaceRaised : UzumeAppColor.surface)
        )
        .accessibilityIdentifier("\(Self.accessibilityIDPrefix).\(type.rawValue)")
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            AccessibilityLabels.connectorTileLabel(
                type: type,
                isEnabled: isEnabled,
                disabledCaption: disabledCaption
            )
        )
        .accessibilityHint(AccessibilityLabels.connectorTileHint(isEnabled: isEnabled))
    }
}
