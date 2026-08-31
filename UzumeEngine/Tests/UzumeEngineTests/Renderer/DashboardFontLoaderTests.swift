// DashboardFontLoaderTests — 3 @Test functions verifying font resolution behaviour.

import Testing
@testable import Renderer

#if canImport(AppKit)
import AppKit
#endif

@Suite("DashboardFontLoader")
struct DashboardFontLoaderTests {

    // Reset the idempotency cache before each test so they run independently.
    init() {
        DashboardFontLoader.resetCacheForTesting()
    }

    @Test("resolveFonts returns non-empty postscript names")
    func resolveFonts_returnsNonEmptyNames() {
        // Use the test bundle — no Epilogue TTFs present → system fallback path.
        let resolution = DashboardFontLoader.resolveFonts(
            in: Bundle(for: DashboardFontLoaderAnchor.self) as Bundle?
        )
        #expect(!resolution.proseFontName.isEmpty)
        #expect(!resolution.proseMediumFontName.isEmpty)
    }

    @Test("resolveFonts is idempotent — second call returns equal resolution")
    func resolveFonts_isIdempotent() {
        let bundle = Bundle(for: DashboardFontLoaderAnchor.self)
        let first  = DashboardFontLoader.resolveFonts(in: bundle)
        let second = DashboardFontLoader.resolveFonts(in: bundle)
        // FontResolution is Equatable: names + flag must all match.
        #expect(first == second)
    }

    @Test("proseCustomLoaded is false when test bundle has no font files")
    func resolveFonts_proseCustomFlag_isFalseInTestBundle() {
        // The test bundle (PhospheneEngineTests) has no Epilogue TTFs; the
        // loader must fall back to system sans and report proseCustomLoaded = false.
        let resolution = DashboardFontLoader.resolveFonts(
            in: Bundle(for: DashboardFontLoaderAnchor.self) as Bundle?
        )
        #expect(resolution.proseCustomLoaded == false)
        // System fallback names vary by macOS version but are guaranteed non-empty.
        #expect(!resolution.proseFontName.isEmpty)
        #expect(!resolution.proseMediumFontName.isEmpty)
    }
}

// MARK: - Bundle anchor

/// Anchor class used to locate the test bundle.
private final class DashboardFontLoaderAnchor {}
