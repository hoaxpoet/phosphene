// LocalFilesSettingsSection — GAP G (2026-05-28). Settings panel for local-
// file playback state: persistent stem-cache size + clear, Recents count +
// clear. Mirrors the structure of `AudioSettingsSection` etc.
//
// Reads engine + recentsStore via `@EnvironmentObject` — same wiring the
// LF chrome elsewhere uses. SwiftUI propagates environment into sheets so
// these resolve correctly when the Settings sheet is presented from
// PlaybackView.

import SwiftUI

// MARK: - LocalFilesSettingsSection

struct LocalFilesSettingsSection: View {

    @EnvironmentObject private var engine: VisualizerEngine
    @EnvironmentObject private var recentsStore: LocalFileRecentsStore

    /// Confirmation dialog state for the destructive "Clear cache" + "Clear
    /// recents" actions. Modal-allowed per design context — both are
    /// destructive (irreversible without re-preparing).
    @State private var showClearCacheConfirm = false
    @State private var showClearRecentsConfirm = false

    var body: some View {
        Form {
            Section(NSLocalizedString("settings.lf.cache.title", comment: "")) {
                HStack {
                    Text(NSLocalizedString("settings.lf.cache.size_label", comment: ""))
                    Spacer()
                    Text(verbatim: LocalFileMenuCommands.formatBytes(engine.localFileCacheBytes))
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }

                Text(NSLocalizedString("settings.lf.cache.body", comment: ""))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button(NSLocalizedString("settings.lf.cache.clear_button", comment: ""), role: .destructive) {
                    showClearCacheConfirm = true
                }
                .disabled(engine.localFileCacheBytes == 0)
            }

            Section(NSLocalizedString("settings.lf.recents.title", comment: "")) {
                HStack {
                    Text(NSLocalizedString("settings.lf.recents.count_label", comment: ""))
                    Spacer()
                    Text(verbatim: "\(recentsStore.recents.count)")
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }

                Text(NSLocalizedString("settings.lf.recents.body", comment: ""))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button(NSLocalizedString("settings.lf.recents.clear_button", comment: ""), role: .destructive) {
                    showClearRecentsConfirm = true
                }
                .disabled(recentsStore.recents.isEmpty)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(NSLocalizedString("settings.group.local_files", comment: ""))
        .confirmationDialog(
            NSLocalizedString("settings.lf.cache.confirm_title", comment: ""),
            isPresented: $showClearCacheConfirm,
            titleVisibility: .visible
        ) {
            Button(
                NSLocalizedString("settings.lf.cache.confirm_button", comment: ""),
                role: .destructive
            ) {
                LocalFileMenuCommands.clearLocalFileCache(engine: engine)
            }
            Button(NSLocalizedString("common.cancel", comment: ""), role: .cancel) {}
        } message: {
            Text(NSLocalizedString("settings.lf.cache.confirm_message", comment: ""))
        }
        .confirmationDialog(
            NSLocalizedString("settings.lf.recents.confirm_title", comment: ""),
            isPresented: $showClearRecentsConfirm,
            titleVisibility: .visible
        ) {
            Button(
                NSLocalizedString("settings.lf.recents.confirm_button", comment: ""),
                role: .destructive
            ) {
                recentsStore.clearAll()
            }
            Button(NSLocalizedString("common.cancel", comment: ""), role: .cancel) {}
        } message: {
            Text(NSLocalizedString("settings.lf.recents.confirm_message", comment: ""))
        }
    }
}
