// OrchestratorWiringRegressionTests — BUG-015 load-bearing gate.
//
// Catches the "DefaultLiveAdapter + DefaultReactiveOrchestrator are fully
// implemented and unit-tested but never invoked at runtime" bug surfaced by
// the CA.4 Orchestrator audit (2026-05-20). Pre-fix: a grep for
// `applyLiveUpdate` in PhospheneApp + PhospheneEngine returned the declaration
// site, four doc-comment references, two test references, and ZERO actual
// invocations. The entire Phase 4.5 / 4.6 runtime adaptation pipeline was
// dead in production while the Orchestrator-module unit tests passed green.
//
// Same pattern as `SettingsStoreEnvironmentRegressionTests` (QR.4 / D-091):
// when the bug shape is "an App-layer wire was never added," a source-presence
// assertion against the file where the wire belongs is the test that fails on
// the buggy state and passes after the fix. The Orchestrator-side unit tests
// (LiveAdapterTests, ReactiveOrchestratorTests, DiagnosticHoldTests, …) all
// passed against pre-fix `main`; they invoke the adapter / orchestrator
// directly and bypass the App-layer entry point. They cannot catch BUG-015.
// This test does.
//
// The accepted call-site spellings are either `applyLiveUpdate(` (direct
// invocation of the engine method on `VisualizerEngine+Orchestrator.swift`)
// or `runOrchestratorLiveUpdate(` (the cadence-gated wrapper added by
// BUG-015's fix). Either is sufficient evidence that the analysis path
// reaches the live-adaptation pipeline. If both names disappear, the wire
// is dead again and the test fails.

import Foundation
import Testing

@Suite("OrchestratorWiringRegression")
struct OrchestratorWiringRegressionTests {

    // MARK: - Helpers

    /// Walk up from this test file until we find the repo root (the directory
    /// containing `PhospheneApp/`).
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

    /// Strip `//` line comments and `/* … */` block comments so source-presence
    /// assertions are not satisfied by doc-comment mentions of the symbol.
    /// (CA.4 audit's grep found four doc-comment references in unrelated
    /// files; this test must not be fooled by the same.)
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
                    // Line comment — skip to newline.
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

    /// **The load-bearing assertion.** `VisualizerEngine+Audio.swift` must
    /// contain a non-comment call to `applyLiveUpdate(` or
    /// `runOrchestratorLiveUpdate(`. If both disappear, the live-adaptation
    /// pipeline is dead in production (BUG-015 has regressed).
    @Test("VisualizerEngine+Audio.swift wires the Orchestrator live-adaptation pipeline")
    func test_visualizerEngineAudio_wiresOrchestratorLiveUpdate() throws {
        let url = repoRoot().appendingPathComponent(
            "PhospheneApp/VisualizerEngine+Audio.swift"
        )
        let raw = try String(contentsOf: url, encoding: .utf8)
        let src = stripComments(raw)

        let directCall = src.contains("applyLiveUpdate(")
        let wrappedCall = src.contains("runOrchestratorLiveUpdate(")

        #expect(directCall || wrappedCall, """
        BUG-015 regression: VisualizerEngine+Audio.swift has no call to \
        `applyLiveUpdate(` or `runOrchestratorLiveUpdate(`. The Orchestrator \
        live-adaptation pipeline (DefaultLiveAdapter + DefaultReactiveOrchestrator) \
        is dead in production. The Orchestrator-module unit tests will still \
        pass — they bypass the App-layer entry point — but no live MIR data \
        reaches the adapter or orchestrator at runtime. See \
        docs/QUALITY/KNOWN_ISSUES.md §BUG-015 and \
        docs/CAPABILITY_REGISTRY/ORCHESTRATOR.md §broken-but-claimed.
        """)
    }

    /// Companion assertion: the wrapper method (or the direct call) must reach
    /// `applyLiveUpdate(...)` somewhere. The grep is over the App layer.
    /// We accept the wrapper in `VisualizerEngine+Orchestrator.swift` if it's
    /// the only direct caller — that's the BUG-015 fix shape.
    @Test("App layer contains a production call site for applyLiveUpdate(")
    func test_appLayer_hasProductionCallSiteForApplyLiveUpdate() throws {
        let appDir = repoRoot().appendingPathComponent("PhospheneApp")
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: appDir,
            includingPropertiesForKeys: nil
        ) else {
            Issue.record("Could not enumerate \(appDir.path)")
            return
        }

        // Files where the declaration lives — must be excluded from the
        // "call site" count. Doc-comments-only references are stripped by
        // `stripComments`.
        let declarationFile = "VisualizerEngine+Orchestrator.swift"
        let declarationSignature = "func applyLiveUpdate(\n"
            + "        trackIndex: Int,"

        var callSiteFiles: [String] = []
        for case let url as URL in enumerator {
            guard url.pathExtension == "swift" else { continue }
            guard let raw = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let src = stripComments(raw)
            guard src.contains("applyLiveUpdate(") else { continue }
            // The declaration site itself doesn't count as a call site.
            if url.lastPathComponent == declarationFile,
               raw.contains(declarationSignature) {
                // Subtract the declaration. Any remaining `applyLiveUpdate(`
                // tokens in this file ARE call sites (e.g. the wrapper).
                let totalOccurrences = src.components(separatedBy: "applyLiveUpdate(").count - 1
                if totalOccurrences > 1 {
                    callSiteFiles.append(url.lastPathComponent)
                }
                continue
            }
            callSiteFiles.append(url.lastPathComponent)
        }

        #expect(!callSiteFiles.isEmpty, """
        BUG-015 regression: zero production call sites for `applyLiveUpdate(` \
        exist anywhere in PhospheneApp/ (outside the declaration in \
        VisualizerEngine+Orchestrator.swift). The live-adaptation pipeline is \
        dead in production. See docs/QUALITY/KNOWN_ISSUES.md §BUG-015.
        """)
    }
}
