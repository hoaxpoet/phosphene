// PresetCategoryBlocklistPicker — Multi-select preset category exclusion (U.8 Part B).

import Presets
import SwiftUI

// MARK: - PresetCategoryBlocklistPicker

/// Checklist of all preset categories. Checked = excluded from session planning.
struct PresetCategoryBlocklistPicker: View {

    @Binding var selection: Set<PresetCategory>

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(NSLocalizedString("settings.visuals.blocklist.caption", comment: ""))
                .font(.caption)
                .foregroundColor(.secondary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], spacing: 4) {
                ForEach(PresetCategory.allCases, id: \.self) { category in
                    Toggle(isOn: Binding(
                        get: { selection.contains(category) },
                        set: { included in
                            if included {
                                selection.insert(category)
                            } else {
                                selection.remove(category)
                            }
                        }
                    )) {
                        Text(category.rawValue.capitalized)
                            .font(.caption)
                    }
                    .toggleStyle(.checkbox)
                }
            }
        }
    }
}
