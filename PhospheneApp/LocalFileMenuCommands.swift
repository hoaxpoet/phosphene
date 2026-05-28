// LocalFileMenuCommands — LF.4 / D-131 + LF.5 / D-132 menu + drop glue.
//
// Bridges the `File → Open Local File…` (LF.4) + `File → Open Local Folder…`
// (LF.5) menu items, the `File → Open Recent ▸` submenu (LF.5), and the
// window-level drag-and-drop handler to the LF preparation pipeline driven
// by `SessionManager.startLocalFiles(at:origin:)`.
//
// Six entry-point shapes flow through here at LF.5 scope:
//
//   1. `openLocalFilePanel(engine:recentsStore:)` — `File → Open Local File…`
//      single-file picker via `NSOpenPanel`. Same shape as LF.4.
//   2. `openLocalFolderPanel(engine:recentsStore:)` — `File → Open Local Folder…`
//      LF.5 folder picker via `NSOpenPanel(canChooseDirectories: true)`.
//   3. `handleDrop(providers:engine:recentsStore:)` — drag-and-drop. Accepts
//      single audio files, multiple audio files, a folder, a `.m3u` file, or
//      any mixed combination. Folders expand recursively (depth-first
//      alphabetical), M3U files expand via `M3UParser`, audio files are
//      validated by extension. Mixed drops are flattened in drop order.
//   4. `openLocalFile(at:engine:recentsStore:)` — programmatic entry used by
//      the file-association handler (Task 7) and by the Recents submenu when
//      the user clicks a remembered file.
//   5. `openLocalFolder(at:engine:recentsStore:)` — programmatic entry for
//      the Recents submenu folder click + file-association folder open.
//   6. `openLocalM3U(at:engine:recentsStore:)` — programmatic entry for the
//      Recents submenu M3U click + file-association M3U open.
//
// Per Matt's audit sign-off (2026-05-27): folder ingest is capped at
// `maxQueueSize` (200 URLs); larger folders surface a localized NSAlert
// + queue the first 200 audio files (alphabetical).

import AppKit
import Foundation
import Renderer
import Session
import SwiftUI
import UniformTypeIdentifiers
import os.log

private let menuLogger = Logger(subsystem: "com.phosphene.app", category: "LocalFileMenuCommands")

// MARK: - LocalFileMenuCommands

enum LocalFileMenuCommands {

    /// File extensions Phosphene accepts for local-file playback. Matches the
    /// three formats covered by `LocalFilePlaybackFormatCoverageTests`.
    static let allowedExtensions: Set<String> = ["m4a", "mp3", "flac"]

    /// File extensions recognised as M3U / M3U8 playlists.
    static let playlistExtensions: Set<String> = ["m3u", "m3u8"]

    /// Per Matt's audit sign-off (2026-05-27), folder / multi-drop queues are
    /// truncated to 200 URLs to avoid cache-eviction churn under the
    /// `PersistentStemCache` 500 MB cap (~70 cached tracks). Larger queues
    /// surface a localized alert + queue the first 200 audio files.
    static let maxQueueSize: Int = 200

    // MARK: - Single-file picker (LF.4)

    /// Show `NSOpenPanel` to pick a single local audio file. On confirmation
    /// promotes the entry into Recents + dispatches to
    /// `SessionManager.startLocalFile(at:)`.
    @MainActor
    static func openLocalFilePanel(engine: VisualizerEngine, recentsStore: LocalFileRecentsStore) {
        let panel = NSOpenPanel()
        panel.title = String(localized: "lf.open.panel.title")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = supportedAudioContentTypes()
        panel.allowsOtherFileTypes = false

        guard panel.runModal() == .OK, let url = panel.url else {
            return                                          // user cancelled
        }
        Task { @MainActor in
            await openLocalFile(at: url, engine: engine, recentsStore: recentsStore)
        }
    }

    // MARK: - Folder picker (LF.5)

    /// Show `NSOpenPanel` to pick a local folder. On confirmation expands
    /// recursively, queues every readable audio file, promotes the entry
    /// into Recents, and dispatches.
    @MainActor
    static func openLocalFolderPanel(engine: VisualizerEngine, recentsStore: LocalFileRecentsStore) {
        let panel = NSOpenPanel()
        panel.title = String(localized: "lf.open.folder.panel.title")
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else {
            return                                          // user cancelled
        }
        Task { @MainActor in
            await openLocalFolder(at: url, engine: engine, recentsStore: recentsStore)
        }
    }

    // MARK: - Recents-driven re-entry (LF.5)

    /// Open a remembered file (Recents submenu click + file-association).
    /// Validates extension + readability before dispatching; failure shows a
    /// localized alert.
    @MainActor
    static func openLocalFile(
        at url: URL,
        engine: VisualizerEngine,
        recentsStore: LocalFileRecentsStore
    ) async {
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            presentUnsupportedAlert(reason: .unreadable)
            return
        }
        let ext = url.pathExtension.lowercased()
        guard allowedExtensions.contains(ext) else {
            presentUnsupportedAlert(reason: .unsupportedFormat)
            return
        }
        menuLogger.info("[LF.5] dispatch local file: \(url.lastPathComponent, privacy: .public)")
        recentsStore.addOrPromote(url: url, kind: .file)
        await engine.sessionManager.startLocalFile(at: url)
    }

    /// Open a remembered folder (Recents submenu click + file-association).
    @MainActor
    static func openLocalFolder(
        at url: URL,
        engine: VisualizerEngine,
        recentsStore: LocalFileRecentsStore
    ) async {
        guard FileManager.default.fileExists(atPath: url.path) else {
            presentUnsupportedAlert(reason: .unreadable)
            return
        }
        let expanded = expandFolder(at: url)
        guard !expanded.isEmpty else {
            presentUnsupportedAlert(reason: .emptyFolder)
            return
        }
        let queue = enforceQueueCap(expanded)
        menuLogger.info(
            "[LF.5] dispatch local folder: \(url.lastPathComponent, privacy: .public), \(queue.count) audio file(s)"
        )
        recentsStore.addOrPromote(url: url, kind: .folder)
        await engine.sessionManager.startLocalFiles(
            at: queue,
            origin: .localFolder(url, expanded: queue)
        )
    }

    /// Open a remembered M3U / M3U8 playlist (Recents submenu click +
    /// file-association).
    @MainActor
    static func openLocalM3U(
        at url: URL,
        engine: VisualizerEngine,
        recentsStore: LocalFileRecentsStore
    ) async {
        let parsed: M3UParser.ParseResult
        do {
            parsed = try M3UParser.parse(at: url)
        } catch {
            menuLogger.warning("[LF.5] M3U parse failed: \(error.localizedDescription, privacy: .public)")
            presentUnsupportedAlert(reason: .m3uParseFailed)
            return
        }
        let filtered = parsed.urls.filter { allowedExtensions.contains($0.pathExtension.lowercased()) }
        guard !filtered.isEmpty else {
            presentUnsupportedAlert(reason: .emptyFolder)            // re-use copy
            return
        }
        let queue = enforceQueueCap(filtered)
        menuLogger.info(
            "[LF.5] dispatch local M3U: \(url.lastPathComponent, privacy: .public), \(queue.count) audio file(s)"
        )
        recentsStore.addOrPromote(url: url, kind: .m3u)
        await engine.sessionManager.startLocalFiles(
            at: queue,
            origin: .localPlaylist(url, expanded: queue)
        )
    }

    // MARK: - Folder + M3U expansion

    /// Recursive depth-first alphabetical walk of `dir`. Filters to
    /// `allowedExtensions`. Returns the URLs sorted by full path so the
    /// queue is deterministic across runs.
    static func expandFolder(at dir: URL) -> [URL] {
        let fileManager = FileManager.default
        var collected: [URL] = []
        let keys: Set<URLResourceKey> = [.isDirectoryKey]
        guard let enumerator = fileManager.enumerator(
            at: dir,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: nil
        ) else {
            return []
        }
        for case let url as URL in enumerator {
            let resourceValues = try? url.resourceValues(forKeys: keys)
            let isDir = resourceValues?.isDirectory ?? false
            if isDir { continue }
            let ext = url.pathExtension.lowercased()
            guard allowedExtensions.contains(ext) else { continue }
            guard fileManager.isReadableFile(atPath: url.path) else { continue }
            collected.append(url)
        }
        collected.sort { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        return collected
    }

    /// Enforce the LF.5 `maxQueueSize` cap. If the input list exceeds the cap
    /// the user sees a localized NSAlert and the queue is truncated to the
    /// first N entries.
    @MainActor
    static func enforceQueueCap(_ urls: [URL]) -> [URL] {
        guard urls.count > maxQueueSize else { return urls }
        let dropped = urls.count - maxQueueSize
        presentTruncationAlert(total: urls.count, kept: maxQueueSize, dropped: dropped)
        return Array(urls.prefix(maxQueueSize))
    }

    // MARK: - Predicates

    static func isFolder(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    static func isM3U(_ url: URL) -> Bool {
        playlistExtensions.contains(url.pathExtension.lowercased())
    }

    // MARK: - UTType list

    /// Content-type list used by `NSOpenPanel`. UTType doesn't ship a
    /// FLAC constant on macOS 14 so we look it up by filename-extension.
    private static func supportedAudioContentTypes() -> [UTType] {
        var types: [UTType] = [.mpeg4Audio, .mp3]
        if let flac = UTType(filenameExtension: "flac") {
            types.append(flac)
        }
        return types
    }

    // MARK: - Clear cache (LF.4)

    /// Action target for `Phosphene → Clear Local-File Cache (…)`. Calls
    /// `PersistentStemCache.clearAll()` and surfaces a confirmation alert
    /// reporting the bytes freed.
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
    static func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB, .useKB]
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false
        return formatter.string(fromByteCount: bytes)
    }

    // MARK: - Error / truncation presentation

    enum UnsupportedReason {
        case multipleFiles
        case unsupportedFormat
        case unreadable
        case emptyFolder
        case m3uParseFailed
    }

    @MainActor
    static func presentUnsupportedAlert(reason: UnsupportedReason) {
        let alert = NSAlert()
        alert.messageText = String(localized: "lf.open.error.unsupported.title")
        switch reason {
        case .multipleFiles:
            alert.informativeText = String(localized: "lf.open.error.multiple_files")
        case .unsupportedFormat:
            alert.informativeText = String(localized: "lf.open.error.unsupported_format")
        case .unreadable:
            alert.informativeText = String(localized: "lf.open.error.unreadable")
        case .emptyFolder:
            alert.informativeText = String(localized: "lf.open.error.empty_folder")
        case .m3uParseFailed:
            alert.informativeText = String(localized: "lf.open.error.m3u_parse_failed")
        }
        alert.addButton(withTitle: String(localized: "cta.close"))
        alert.alertStyle = .warning
        alert.runModal()
    }

    @MainActor
    fileprivate static func presentTruncationAlert(total: Int, kept: Int, dropped: Int) {
        let alert = NSAlert()
        alert.messageText = String(localized: "lf.queue.truncation.title")
        alert.informativeText = String(
            format: String(localized: "lf.queue.truncation.body"),
            kept,
            total
        )
        alert.addButton(withTitle: String(localized: "cta.close"))
        alert.alertStyle = .informational
        alert.runModal()
    }
}
