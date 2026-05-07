// DashboardFontLoader — Resolves fonts needed by DashboardTextLayer.
//
// Font strategy (D-080):
//   • SF Mono  — system monospaced font (`NSFont.monospacedSystemFont`). No registration
//                needed; available on every supported macOS. Callers query it directly via
//                NSFont — nothing to store in FontResolution.
//   • Epilogue — bundled OTF/TTF (SIL OFL). Loaded from Resources/Fonts/ if present;
//                falls back to the system sans postscript name when absent.
//
// DashboardFontLoader.resolveFonts() is idempotent: the first call registers fonts and
// caches the result; subsequent calls return the cached value immediately.

import CoreText
import Foundation
import Metal        // Module-level import needed in Renderer targets
import os.log

#if canImport(AppKit)
import AppKit
#endif

// MARK: - DashboardFontLoader

/// Resolves fonts for the Telemetry dashboard.
public enum DashboardFontLoader {

    // MARK: - FontResolution

    /// Result of a single font resolution pass.
    public struct FontResolution: Sendable, Equatable {
        /// PostScript name for the regular prose font.
        /// Either "Epilogue-Regular" (when the TTF is registered) or the system sans fallback.
        public let proseFontName: String

        /// PostScript name for the medium-weight prose font.
        /// Either "Epilogue-Medium" (when the TTF is registered) or the system medium sans fallback.
        public let proseMediumFontName: String

        /// `true` iff both Epilogue font files were found in the bundle and successfully registered.
        public let proseCustomLoaded: Bool

        /// PostScript name for the display font used on card titles + state headlines.
        /// Either "ClashDisplay-Medium" (when the OTF is registered) or the system semibold fallback.
        public let displayFontName: String

        /// `true` iff the Clash Display font file was found in the bundle and successfully registered.
        public let displayCustomLoaded: Bool
    }

    // MARK: - State

    // OSAllocatedUnfairLock wraps an optional FontResolution so resolveFonts() short-circuits
    // on subsequent calls without repeating bundle lookups or registration.
    private static let _lock = OSAllocatedUnfairLock<FontResolution?>(initialState: nil)

    private static let log = Logger(subsystem: "com.phosphene", category: "DashboardFontLoader")

    // MARK: - Public API

    /// Resolve dashboard fonts, registering Epilogue from the bundle if available.
    ///
    /// - Parameter bundle: The bundle to search for `Epilogue-Regular.ttf` /
    ///   `Epilogue-Medium.ttf`. Pass `nil` to use the Renderer module bundle.
    ///   Tests pass `Bundle(for: ...)` to exercise the fallback path.
    /// - Returns: A `FontResolution` describing the resolved postscript names.
    public static func resolveFonts(in bundle: Bundle? = nil) -> FontResolution {
        // Bundle.module is internal and cannot be used as a default argument value
        // in Swift 6; resolve the effective bundle at the call site instead.
        let effectiveBundle = bundle ?? .module
        return _lock.withLock { cached -> FontResolution in
            if let existing = cached { return existing }
            let resolution = performResolution(bundle: effectiveBundle)
            cached = resolution
            return resolution
        }
    }

    // MARK: - Private

    /// Resets the cached resolution — for testing only.
    static func resetCacheForTesting() {
        _lock.withLock { $0 = nil }
    }

    private static func performResolution(bundle: Bundle) -> FontResolution {
        // Epilogue (prose / labels / body)
        let regularURL = bundle.url(forResource: "Epilogue-Regular",
                                    withExtension: "ttf",
                                    subdirectory: "Fonts")
        let mediumURL = bundle.url(forResource: "Epilogue-Medium",
                                   withExtension: "ttf",
                                   subdirectory: "Fonts")
        let regularRegistered = registerFont(at: regularURL, name: "Epilogue-Regular")
        let mediumRegistered = registerFont(at: mediumURL, name: "Epilogue-Medium")
        let proseCustomLoaded = regularRegistered && mediumRegistered

        let proseRegular: String
        let proseMedium: String
        if proseCustomLoaded {
            proseRegular = "Epilogue-Regular"
            proseMedium = "Epilogue-Medium"
            log.info("DashboardFontLoader: Epilogue registered from bundle")
        } else {
            // Fall back to system sans — postscript names vary by macOS version.
            proseRegular = NSFont.systemFont(ofSize: 12, weight: .regular).fontName
            proseMedium = NSFont.systemFont(ofSize: 12, weight: .medium).fontName
            log.info("DashboardFontLoader: Epilogue not found, falling back to \(proseRegular)")
        }

        // Clash Display (card titles, state headlines)
        let displayURL = bundle.url(forResource: "ClashDisplay-Medium",
                                    withExtension: "otf",
                                    subdirectory: "Fonts")
            ?? bundle.url(forResource: "ClashDisplay-Medium",
                          withExtension: "ttf",
                          subdirectory: "Fonts")
        let displayCustomLoaded = registerFont(at: displayURL, name: "ClashDisplay-Medium")
        let displayName: String
        if displayCustomLoaded {
            displayName = "ClashDisplay-Medium"
            log.info("DashboardFontLoader: ClashDisplay registered from bundle")
        } else {
            displayName = NSFont.systemFont(ofSize: 18, weight: .semibold).fontName
            log.info("DashboardFontLoader: ClashDisplay not found, falling back to \(displayName)")
        }

        return FontResolution(
            proseFontName: proseRegular,
            proseMediumFontName: proseMedium,
            proseCustomLoaded: proseCustomLoaded,
            displayFontName: displayName,
            displayCustomLoaded: displayCustomLoaded
        )
    }

    /// Attempts to register the font at `url` via CoreText.
    /// Returns `true` on success; logs and returns `false` on any failure.
    private static func registerFont(at url: URL?, name: String) -> Bool {
        guard let url else {
            log.debug("DashboardFontLoader: \(name) not found in bundle — using system fallback")
            return false
        }
        var error: Unmanaged<CFError>?
        let ok = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
        if !ok {
            let desc = error?.takeRetainedValue().localizedDescription ?? "unknown"
            log.warning("DashboardFontLoader: failed to register \(name): \(desc)")
        }
        return ok
    }
}
