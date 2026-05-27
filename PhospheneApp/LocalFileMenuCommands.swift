// LocalFileMenuCommands — LF.4 / D-131.
//
// Glue between the `File → Open Local File…` menu command + drag-and-drop
// modifiers in `PhospheneApp.swift` / `ContentView.swift` and the LF
// preparation pipeline driven by `SessionManager.startLocalFile(at:)`.
//
// Handles two surfaces:
//   1. `openLocalFilePanel(engine:)` — invoked by the File menu and the
//      keyboard shortcut. Uses `NSOpenPanel` for the system-native file
//      picker; validates the chosen URL's extension; dispatches to the
//      preparer or surfaces a localized alert on mismatch.
//   2. `handleDrop(providers:engine:)` — invoked by ContentView's
//      `.onDrop(of:isTargeted:)`. Loads the first file URL from the
//      provided drag pasteboard, runs the same validation pass, then
//      dispatches.
//
// Validation rejects multi-file drops, non-existing paths, and files
// without one of the supported extensions (m4a, mp3, flac). Failures
// surface as a system alert with a localized message.

import AppKit
import Foundation
import Renderer
import SwiftUI
import UniformTypeIdentifiers
import os.log

private let menuLogger = Logger(subsystem: "com.phosphene.app", category: "LocalFileMenuCommands")

// MARK: - LocalFileMenuCommands

enum LocalFileMenuCommands {

    /// File extensions Phosphene accepts for local-file playback. Matches the
    /// three formats covered by `LocalFilePlaybackFormatCoverageTests`.
    static let allowedExtensions: Set<String> = ["m4a", "mp3", "flac"]

    /// Show `NSOpenPanel` to pick a single local audio file. On confirmation,
    /// validates the extension and dispatches to
    /// `engine.sessionManager.startLocalFile(at:)`. On rejection, shows a
    /// localized alert.
    @MainActor
    static func openLocalFilePanel(engine: VisualizerEngine) {
        let panel = NSOpenPanel()
        panel.title = String(localized: "lf.open.panel.title")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = supportedContentTypes()
        panel.allowsOtherFileTypes = false

        guard panel.runModal() == .OK, let url = panel.url else {
            return                                          // user cancelled
        }

        Task { @MainActor in
            await dispatchLocalFile(url: url, engine: engine)
        }
    }

    /// Drop handler for `ContentView`'s `.onDrop(of:isTargeted:)`. Accepts a
    /// single file URL; rejects multi-file drops with a localized alert.
    /// Returns `true` to acknowledge the drop (suppresses the system's bounce-
    /// back animation); `false` lets the system bounce the drop back to the
    /// user, signalling rejection.
    @MainActor
    static func handleDrop(
        providers: [NSItemProvider],
        engine: VisualizerEngine
    ) -> Bool {
        guard providers.count == 1, let provider = providers.first else {
            presentUnsupportedAlert(reason: .multipleFiles)
            return false
        }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
            // Resolve the URL on this completion queue first — `URL` is Sendable so
            // crossing the actor hop with just the resolved URL avoids the Swift 6
            // strict-concurrency "sending opaque `NSSecureCoding` risks races" diagnostic.
            let resolved: URL?
            if let data = item as? Data {
                resolved = URL(dataRepresentation: data, relativeTo: nil)
            } else if let directURL = item as? URL {
                resolved = directURL
            } else {
                resolved = nil
            }
            let errorMessage = error?.localizedDescription
            Task { @MainActor in
                if let errorMessage {
                    menuLogger.warning("[LF.4] drop loadItem failed: \(errorMessage, privacy: .public)")
                    return
                }
                guard let resolved else {
                    presentUnsupportedAlert(reason: .unreadable)
                    return
                }
                await dispatchLocalFile(url: resolved, engine: engine)
            }
        }
        return true
    }

    // MARK: - Validation + dispatch

    @MainActor
    private static func dispatchLocalFile(url: URL, engine: VisualizerEngine) async {
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            presentUnsupportedAlert(reason: .unreadable)
            return
        }
        let ext = url.pathExtension.lowercased()
        guard allowedExtensions.contains(ext) else {
            presentUnsupportedAlert(reason: .unsupportedFormat)
            return
        }
        menuLogger.info("[LF.4] dispatch local file: \(url.lastPathComponent, privacy: .public)")
        await engine.sessionManager.startLocalFile(at: url)
    }

    // MARK: - UTType list

    /// Content-type list used by `NSOpenPanel`. UTType doesn't ship a
    /// FLAC constant on macOS 14 so we look it up by filename-extension.
    private static func supportedContentTypes() -> [UTType] {
        var types: [UTType] = [.mpeg4Audio, .mp3]
        if let flac = UTType(filenameExtension: "flac") {
            types.append(flac)
        }
        return types
    }

    // MARK: - Clear cache

    /// Action target for `Phosphene → Clear Local-File Cache (…)`. Calls
    /// `PersistentStemCache.clearAll()` and surfaces a confirmation alert
    /// reporting the bytes freed. No-op when the persistent cache failed
    /// to initialise (LF.3 root-directory error path).
    @MainActor
    static func clearLocalFileCache(engine: VisualizerEngine) {
        guard let cache = engine.persistentStemCache else {
            menuLogger.warning("[LF.4] clearLocalFileCache no-op: persistentStemCache=nil")
            return
        }
        do {
            let freed = try cache.clearAll()
            engine.refreshLocalFileCacheBytes()
            menuLogger.info("[LF.4] Cleared local-file cache: freed \(freed) bytes")
            presentClearedAlert(freedBytes: freed)
        } catch {
            menuLogger.error("[LF.4] clearLocalFileCache failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    @MainActor
    private static func presentClearedAlert(freedBytes: Int64) {
        let alert = NSAlert()
        alert.messageText = String(localized: "lf.cache.cleared.title")
        alert.informativeText = String(
            format: String(localized: "lf.cache.cleared.body"),
            formatBytes(freedBytes)
        )
        alert.addButton(withTitle: String(localized: "cta.close"))
        alert.alertStyle = .informational
        alert.runModal()
    }

    /// Render a byte count as a short human-readable string (1 MB, 67.4 MB, 1.2 GB).
    /// Used by both the menu label and the post-clear confirmation copy.
    static func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB, .useKB]
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false
        return formatter.string(fromByteCount: bytes)
    }

    // MARK: - Error presentation

    enum UnsupportedReason {
        case multipleFiles
        case unsupportedFormat
        case unreadable
    }

    @MainActor
    private static func presentUnsupportedAlert(reason: UnsupportedReason) {
        let alert = NSAlert()
        alert.messageText = String(localized: "lf.open.error.unsupported.title")
        switch reason {
        case .multipleFiles:
            alert.informativeText = String(localized: "lf.open.error.multiple_files")
        case .unsupportedFormat:
            alert.informativeText = String(localized: "lf.open.error.unsupported_format")
        case .unreadable:
            alert.informativeText = String(localized: "lf.open.error.unreadable")
        }
        alert.addButton(withTitle: String(localized: "cta.close"))
        alert.alertStyle = .warning
        alert.runModal()
    }
}
