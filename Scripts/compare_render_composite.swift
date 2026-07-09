#!/usr/bin/env swift
// compare_render_composite.swift — [QG.2]
//
// Compositor backend for Scripts/compare_render.sh. Given a set of reference
// images and a set of render frames, writes one composite sheet: a grid with
// one row per reference (reference panel on the left, every render frame to its
// right), each panel's filename burned in at the bottom.
//
// Invoked, not run directly:
//   swift compare_render_composite.swift OUT.png --refs a.jpg b.jpg --renders x.png y.png
//
// No ImageMagick on the dev box (audited QG.2); CoreImage/AppKit is the
// repo-native compositing path (mirrors PresetVisualReviewTests.buildContactSheet).

import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// MARK: - Arg parsing

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("compare_render_composite: \(message)\n".utf8))
    exit(1)
}

var outPath: String?
var refs: [String] = []
var renders: [String] = []
var bucket = 0  // 0 = expecting out path, 1 = refs, 2 = renders

for arg in CommandLine.arguments.dropFirst() {
    switch arg {
    case "--refs": bucket = 1
    case "--renders": bucket = 2
    default:
        switch bucket {
        case 1: refs.append(arg)
        case 2: renders.append(arg)
        default: outPath = arg
        }
    }
}

guard let outPath else { fail("missing output path") }
guard !refs.isEmpty else { fail("no reference images given") }
guard !renders.isEmpty else { fail("no render frames given") }

// MARK: - Layout constants

let cellW = 480
let cellH = 300          // 16:9 image area (270) + label strip (30)
let imageH = 270
let labelH = cellH - imageH
let cols = 1 + renders.count
let rows = refs.count
let sheetW = cols * cellW
let sheetH = rows * cellH

// MARK: - Drawing helpers

func loadCGImage(_ path: String) -> CGImage? {
    let url = URL(fileURLWithPath: path)
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(src, 0, nil)
}

/// Draw `image` letterboxed (aspect-preserving) into `rect`.
func drawLetterboxed(_ image: CGImage, in rect: CGRect, ctx: CGContext) {
    let srcW = CGFloat(image.width), srcH = CGFloat(image.height)
    let scale = min(rect.width / srcW, rect.height / srcH)
    let drawW = srcW * scale, drawH = srcH * scale
    let box = CGRect(x: rect.midX - drawW / 2, y: rect.midY - drawH / 2, width: drawW, height: drawH)
    ctx.draw(image, in: box)
}

guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { fail("no sRGB colorspace") }
let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
guard let ctx = CGContext(
    data: nil,
    width: sheetW,
    height: sheetH,
    bitsPerComponent: 8,
    bytesPerRow: sheetW * 4,
    space: colorSpace,
    bitmapInfo: bitmapInfo
) else {
    fail("CGContext allocation failed")
}

ctx.setFillColor(red: 0.07, green: 0.07, blue: 0.08, alpha: 1)
ctx.fill(CGRect(x: 0, y: 0, width: sheetW, height: sheetH))
ctx.interpolationQuality = .high

let labelAttrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.boldSystemFont(ofSize: 15),
    .foregroundColor: NSColor.white,
    .backgroundColor: NSColor(red: 0, green: 0, blue: 0, alpha: 0.75),
]

// CGContext origin is bottom-left; row 0 (first reference) goes at the top.
func cellRect(row: Int, col: Int) -> CGRect {
    let y = sheetH - (row + 1) * cellH
    return CGRect(x: col * cellW, y: y, width: cellW, height: cellH)
}

let nsContext = NSGraphicsContext(cgContext: ctx, flipped: false)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = nsContext

func drawPanel(path: String, row: Int, col: Int) {
    let cell = cellRect(row: row, col: col)
    let imageRect = CGRect(
        x: cell.minX,
        y: cell.minY + CGFloat(labelH),
        width: CGFloat(cellW),
        height: CGFloat(imageH)
    )
    if let img = loadCGImage(path) {
        drawLetterboxed(img, in: imageRect, ctx: ctx)
    } else {
        // Missing/undecodable image — mark the panel rather than silently blank it.
        NSAttributedString(string: " (unreadable) ", attributes: labelAttrs)
            .draw(at: NSPoint(x: imageRect.minX + 8, y: imageRect.midY))
    }
    NSAttributedString(string: " \(URL(fileURLWithPath: path).lastPathComponent) ", attributes: labelAttrs)
        .draw(at: NSPoint(x: cell.minX + 6, y: cell.minY + 7))
}

for (row, ref) in refs.enumerated() {
    drawPanel(path: ref, row: row, col: 0)
    for (i, render) in renders.enumerated() {
        drawPanel(path: render, row: row, col: 1 + i)
    }
}

NSGraphicsContext.restoreGraphicsState()

guard let cgImage = ctx.makeImage() else { fail("makeImage failed") }
let outURL = URL(fileURLWithPath: outPath)
guard let dest = CGImageDestinationCreateWithURL(outURL as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    fail("cannot create PNG at \(outPath)")
}
CGImageDestinationAddImage(dest, cgImage, nil)
guard CGImageDestinationFinalize(dest) else { fail("PNG write failed") }
