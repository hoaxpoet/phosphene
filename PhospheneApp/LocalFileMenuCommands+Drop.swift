// LocalFileMenuCommands+Drop — LF.5 / D-132 drag-and-drop handler.
//
// Split from `LocalFileMenuCommands.swift` to keep that file under SwiftLint's
// 400-line file_length + 300-line type_body_length caps after the LF.5 menu
// expansion. Houses the multi-provider drop entry point + the
// `@MainActor`-isolated `DropCollector` that batches asynchronous
// `NSItemProvider.loadItem` callbacks before dispatching.
//
// Swift 6 strict-concurrency note: `NSItemProvider` is non-Sendable, so the
// provider array never crosses an actor boundary. Each provider's
// `loadItem` callback runs on a non-isolated queue, resolves the URL
// synchronously (URL IS Sendable), then crosses to `@MainActor` via a
// per-callback `Task` that calls into `DropCollector.add(_:)`. When every
// provider has reported the collector forwards the batched URLs to
// `LocalFileMenuCommands.dispatchDrop`.

import AppKit
import Foundation
import Renderer
import Session
import SwiftUI
import UniformTypeIdentifiers
import os.log

private let dropLogger = Logger(subsystem: "com.phosphene.app", category: "LocalFileMenuCommands+Drop")

// MARK: - Drop entry point

extension LocalFileMenuCommands {

    /// Drag-and-drop handler. Accepts single audio files (LF.4), multiple
    /// audio files (LF.5), folders (LF.5), M3U files (LF.5), or any
    /// combination thereof (LF.5). Always returns `true` to acknowledge the
    /// drop so SwiftUI doesn't bounce the user's input.
    @MainActor
    static func handleDrop(
        providers: [NSItemProvider],
        engine: VisualizerEngine,
        recentsStore: LocalFileRecentsStore
    ) -> Bool {
        guard !providers.isEmpty else { return false }
        let collector = DropCollector(
            total: providers.count,
            engine: engine,
            recentsStore: recentsStore
        )
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                if let error {
                    dropLogger.warning(
                        "[LF.5] drop loadItem failed: \(error.localizedDescription, privacy: .public)"
                    )
                }
                let url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else if let value = item as? URL {
                    url = value
                } else {
                    url = nil
                }
                Task { @MainActor in
                    collector.add(url)
                }
            }
        }
        return true
    }

    /// Inner dispatch after every provider's URL has been resolved.
    /// Single-URL drops route to the targeted dispatch path (`.localFile` /
    /// `.localFolder` / `.localPlaylist`); multi-URL drops flatten folders
    /// + M3Us into a single `.localFiles` queue in drop order.
    @MainActor
    fileprivate static func dispatchDrop(
        urls: [URL],
        engine: VisualizerEngine,
        recentsStore: LocalFileRecentsStore
    ) async {
        if urls.count == 1, let url = urls.first {
            if isFolder(url) {
                await openLocalFolder(at: url, engine: engine, recentsStore: recentsStore)
                return
            }
            if isM3U(url) {
                await openLocalM3U(at: url, engine: engine, recentsStore: recentsStore)
                return
            }
            await openLocalFile(at: url, engine: engine, recentsStore: recentsStore)
            return
        }

        var queue: [URL] = []
        for url in urls {
            if isFolder(url) {
                queue.append(contentsOf: expandFolder(at: url))
            } else if isM3U(url) {
                if let parsed = try? M3UParser.parse(at: url) {
                    queue.append(contentsOf: parsed.urls.filter {
                        allowedExtensions.contains($0.pathExtension.lowercased())
                    })
                }
            } else if allowedExtensions.contains(url.pathExtension.lowercased()),
                      FileManager.default.isReadableFile(atPath: url.path) {
                queue.append(url)
            }
        }
        guard !queue.isEmpty else {
            presentUnsupportedAlert(reason: .unsupportedFormat)
            return
        }
        let capped = enforceQueueCap(queue)
        dropLogger.info("[LF.5] dispatch multi-file drop: \(capped.count) audio file(s)")
        await engine.sessionManager.startLocalFiles(at: capped, origin: .localFiles(capped))
    }
}

// MARK: - DropCollector

/// MainActor-isolated batch collector for the drag-and-drop path. Each
/// `NSItemProvider`'s non-isolated `loadItem` callback resolves its URL,
/// then crosses to `@MainActor` and calls `add(_:)`. When every provider has
/// reported, the collector dispatches the batched URLs through
/// `LocalFileMenuCommands.dispatchDrop`. Lives only for the duration of one
/// drop; deallocated once the dispatch task is enqueued.
@MainActor
final class DropCollector {
    private var collected: [URL] = []
    private var remaining: Int
    private let engine: VisualizerEngine
    private let recentsStore: LocalFileRecentsStore

    init(total: Int, engine: VisualizerEngine, recentsStore: LocalFileRecentsStore) {
        self.remaining = total
        self.engine = engine
        self.recentsStore = recentsStore
    }

    func add(_ url: URL?) {
        if let url { collected.append(url) }
        remaining -= 1
        guard remaining == 0 else { return }
        let batch = collected
        let engineRef = engine
        let recentsRef = recentsStore
        Task { @MainActor in
            guard !batch.isEmpty else {
                LocalFileMenuCommands.presentUnsupportedAlert(reason: .unreadable)
                return
            }
            await LocalFileMenuCommands.dispatchDrop(
                urls: batch,
                engine: engineRef,
                recentsStore: recentsRef
            )
        }
    }
}
