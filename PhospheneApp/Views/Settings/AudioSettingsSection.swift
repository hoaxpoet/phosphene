// AudioSettingsSection — Audio capture settings (U.8 Part B).

import SwiftUI

// MARK: - AudioSettingsSection

struct AudioSettingsSection: View {

    var body: some View {
        Form {
            Section(NSLocalizedString("settings.audio.quality_hints.title", comment: "")) {
                Text(NSLocalizedString("settings.audio.quality_hints.body", comment: ""))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(NSLocalizedString("settings.group.audio", comment: ""))
    }
}
