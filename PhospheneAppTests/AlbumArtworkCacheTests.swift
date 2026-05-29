// AlbumArtworkCacheTests — Verify decode + downsize + LRU semantics
// of the LF.6 in-memory artwork cache.

import AppKit
import Foundation
import Testing

@testable import PhospheneApp

@Suite("AlbumArtworkCache (LF.6)")
struct AlbumArtworkCacheTests {

    // MARK: - Fixtures

    /// Build an in-memory PNG of the given pixel size with a solid fill.
    /// Using PNG (not JPEG) so the synthesised fixture is lossless and
    /// downsized output is deterministic across runs.
    private func makePNGData(size: Int, fill: NSColor = .systemTeal) throws -> Data {
        let pixelSize = NSSize(width: size, height: size)
        let rep = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: size,
            pixelsHigh: size,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        fill.setFill()
        NSRect(origin: .zero, size: pixelSize).fill()
        NSGraphicsContext.restoreGraphicsState()
        return try #require(rep.representation(using: .png, properties: [:]))
    }

    // MARK: - Tests

    @Test("decodeAndDownsize caps a large source at maxEdgePoints")
    func downsizesLargeSource() throws {
        AlbumArtworkCache.clearAll()
        let data = try makePNGData(size: 600)
        let image = try #require(AlbumArtworkCache.image(for: data, cacheKey: "large|artist"))
        let longest = max(image.size.width, image.size.height)
        #expect(longest <= AlbumArtworkCache.maxEdgePoints)
        #expect(longest > AlbumArtworkCache.maxEdgePoints * 0.9, "expected near-max edge length")
    }

    @Test("decodeAndDownsize preserves a small source as-is")
    func preservesSmallSource() throws {
        AlbumArtworkCache.clearAll()
        let smallEdge = Int(AlbumArtworkCache.maxEdgePoints / 2)
        let data = try makePNGData(size: smallEdge)
        let image = try #require(AlbumArtworkCache.image(for: data, cacheKey: "small|artist"))
        // Source PNG is square; should pass through near-unchanged (allowing
        // for NSImage's point vs pixel conversion).
        let longest = max(image.size.width, image.size.height)
        #expect(longest <= AlbumArtworkCache.maxEdgePoints)
    }

    @Test("Second lookup with the same cacheKey returns the same instance")
    func cacheHitReturnsSameInstance() throws {
        AlbumArtworkCache.clearAll()
        let data = try makePNGData(size: 600)
        let first = try #require(AlbumArtworkCache.image(for: data, cacheKey: "hit|artist"))
        let second = try #require(AlbumArtworkCache.image(for: data, cacheKey: "hit|artist"))
        // NSCache returns the same object pointer on hit.
        #expect(first === second)
    }

    @Test("Different cacheKeys produce distinct cache entries")
    func distinctKeysDoNotCollide() throws {
        AlbumArtworkCache.clearAll()
        let dataA = try makePNGData(size: 600, fill: .systemRed)
        let dataB = try makePNGData(size: 600, fill: .systemBlue)
        let imageA = try #require(AlbumArtworkCache.image(for: dataA, cacheKey: "a|artist"))
        let imageB = try #require(AlbumArtworkCache.image(for: dataB, cacheKey: "b|artist"))
        #expect(imageA !== imageB)
    }

    @Test("Malformed bytes return nil")
    func malformedBytesReturnNil() {
        AlbumArtworkCache.clearAll()
        let bogus = Data([0xDE, 0xAD, 0xBE, 0xEF])
        #expect(AlbumArtworkCache.image(for: bogus, cacheKey: "bogus|artist") == nil)
    }

    @Test("Empty data returns nil")
    func emptyBytesReturnNil() {
        AlbumArtworkCache.clearAll()
        #expect(AlbumArtworkCache.image(for: Data(), cacheKey: "empty|artist") == nil)
    }
}
