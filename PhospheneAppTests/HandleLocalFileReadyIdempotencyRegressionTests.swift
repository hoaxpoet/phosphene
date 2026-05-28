// HandleLocalFileReadyIdempotencyRegressionTests — LF.5.fix.3-C gate.
//
// Bug C from the 2026-05-28T20-57-46Z LF.5.fix.2 manual smoke: a second
// `_completeLocalFilesReady` fired for the SAME folder while SZ2 was
// already playing → `handleLocalFileReady` ran provider.teardown + restart,
// tearing playback down with no user input (session.log lines 78-94).
//
// Bug A's gen-counter gate upstream should prevent the duplicate
// `_completeLocalFilesReady`, but Matt requested defense-in-depth at the
// .ready consumer side (URL match only — kickoff decision 2026-05-28).
// This test fails if any of the three load-bearing pieces of the C-side
// guard go missing:
//
//   1. `VisualizerEngine.swift` declares the `lastStartedLocalFilePlaybackURL`
//      field (the marker).
//   2. `VisualizerEngine+LocalFilePlayback.swift`'s `handleLocalFileReady`
//      reads the marker to skip a duplicate, AND writes the marker on
//      successful audio-router start (so the next duplicate sees the match).
//   3. `VisualizerEngine.swift`'s state-machine observer clears the marker
//      on .preparing (new session) AND .ended (teardown) — without those
//      clears the marker would persist across a re-open of the same file
//      and silently no-op a legitimate restart.
//
// Same pattern as `SettingsStoreEnvironmentRegressionTests` (QR.4 / D-091)
// and `OrchestratorWiringRegressionTests` (BUG-015): when the bug shape
// is "an App-layer wire was never added" or "a guard the design requires
// is missing", a source-presence assertion against the file where the
// wire lives is the regression discriminator. Behavioural tests of
// `VisualizerEngine` itself require a Metal device + an audio router +
// the full stem pipeline — out of scope for a unit-test suite.

import Foundation
import Testing

@Suite("HandleLocalFileReadyIdempotencyRegression")
struct HandleLocalFileReadyIdempotencyRegressionTests {

    // MARK: - Helpers

    private func repoRoot() -> URL {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while !FileManager.default.fileExists(
            atPath: dir.appendingPathComponent("PhospheneApp").path
        ) {
            let parent = dir.deletingLastPathComponent()
            if parent == dir {
                Issue.record("Could not locate repo root from \(#filePath)")
                return dir
            }
            dir = parent
        }
        return dir
    }

    /// Strip `//` line comments and `/* … */` block comments so the
    /// source-presence assertions don't get satisfied by doc-comment
    /// references to the symbol.
    private func stripComments(_ src: String) -> String {
        var out = ""
        out.reserveCapacity(src.count)
        var idx = src.startIndex
        var inBlock = false
        while idx < src.endIndex {
            let ch = src[idx]
            let next = src.index(after: idx)
            if inBlock {
                if ch == "*", next < src.endIndex, src[next] == "/" {
                    inBlock = false
                    idx = src.index(after: next)
                    continue
                }
                idx = next
                continue
            }
            if ch == "/", next < src.endIndex {
                let nextCh = src[next]
                if nextCh == "/" {
                    while idx < src.endIndex, src[idx] != "\n" { idx = src.index(after: idx) }
                    continue
                }
                if nextCh == "*" {
                    inBlock = true
                    idx = src.index(after: next)
                    continue
                }
            }
            out.append(ch)
            idx = next
        }
        return out
    }

    // MARK: - Tests

    @Test("VisualizerEngine declares lastStartedLocalFilePlaybackURL")
    func test_visualizerEngine_declaresMarkerField() throws {
        let url = repoRoot().appendingPathComponent("PhospheneApp/VisualizerEngine.swift")
        let raw = try String(contentsOf: url, encoding: .utf8)
        let src = stripComments(raw)

        #expect(src.contains("lastStartedLocalFilePlaybackURL"), """
        LF.5.fix.3-C regression: VisualizerEngine.swift no longer declares \
        `lastStartedLocalFilePlaybackURL`. Without this field the \
        handleLocalFileReady duplicate-emission guard cannot persist its \
        "we already started this URL" marker, and Bug C re-opens (see \
        session 2026-05-28T20-57-46Z lines 78-94: SZ2 playback torn down \
        + restarted by a redundant .ready transition).
        """)
    }

    @Test("handleLocalFileReady reads + writes the URL marker")
    func test_handleLocalFileReady_readsAndWritesMarker() throws {
        let url = repoRoot().appendingPathComponent(
            "PhospheneApp/VisualizerEngine+LocalFilePlayback.swift"
        )
        let raw = try String(contentsOf: url, encoding: .utf8)
        let src = stripComments(raw)

        // The guard must reference the marker at LEAST twice: once to read
        // (skip-on-match) and once to write (commit-on-success). The two
        // occurrences are not in the same statement so a single reference
        // is evidence one half went missing.
        let occurrences = src.components(separatedBy: "lastStartedLocalFilePlaybackURL").count - 1
        #expect(occurrences >= 2, """
        LF.5.fix.3-C regression: VisualizerEngine+LocalFilePlayback.swift \
        references `lastStartedLocalFilePlaybackURL` only \(occurrences) \
        time(s). The duplicate-emission guard requires both a read (skip \
        when the new URL matches) and a write (commit on successful \
        audio-router start). If either is missing, a redundant .ready \
        emission tears down active playback (Bug C reopens).
        """)
    }

    @Test("State observer clears the marker on .preparing and .ended")
    func test_stateObserver_clearsMarker() throws {
        let url = repoRoot().appendingPathComponent("PhospheneApp/VisualizerEngine.swift")
        let raw = try String(contentsOf: url, encoding: .utf8)
        let src = stripComments(raw)

        // The .preparing and .ended branches must each assign nil to the marker
        // so a new session (or a re-open of the same file) starts cleanly. A
        // single source-presence assertion isn't enough — we need both clears.
        let preparingClear = src.contains(".preparing")
            && src.contains("lastStartedLocalFilePlaybackURL = nil")
        #expect(preparingClear, """
        LF.5.fix.3-C regression: VisualizerEngine.swift's state observer no \
        longer clears `lastStartedLocalFilePlaybackURL = nil` on .preparing. \
        Without that clear, a re-open of the same file after a session ends \
        would silently no-op the duplicate-emission guard and never start \
        playback (the marker would still match the new URL).
        """)

        let endedClear = src.contains(".ended")
            && src.contains("lastStartedLocalFilePlaybackURL = nil")
        #expect(endedClear, """
        LF.5.fix.3-C regression: VisualizerEngine.swift's state observer no \
        longer clears `lastStartedLocalFilePlaybackURL = nil` on .ended. \
        The marker must release on session teardown so it doesn't survive \
        across `endSession()`.
        """)
    }
}
