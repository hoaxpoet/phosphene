import CoreGraphics
import Foundation
// Window state WITHOUT assistive access: CGWindowList reports bounds, layer and on-screen
// membership for any app. This is what the BUG-085 occlusion hypothesis needs, and the
// AppleScript route (which the capture script used first) is blocked unless the user grants
// Accessibility — so it recorded a permission error instead of the answer.
//
// EVERY off-screen window used to be labelled "this is the BUG-085 occlusion condition".
// On the 2026-08-05 freeze capture that printed the line EIGHT times — for the 1920x30 and
// 1080x30 MENU-BAR windows of secondary displays — while the actual render window was
// on-screen and composited. Read literally, the file confirmed a hypothesis that had already
// been experimentally refuted. A diagnostic that misleads is worse than one that stays quiet,
// so the verdict is now computed only for the RENDER window, and the rest are listed as
// context (menu bars, panels) without a verdict.

let all = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
let onScreen = Set((CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? [])
    .compactMap { $0[kCGWindowNumber as String] as? Int })
let mine = all.filter { ($0[kCGWindowOwnerName as String] as? String) == "PhospheneApp" }
if mine.isEmpty { print("PhospheneApp: no windows found (not running?)") }

/// A window is a plausible RENDER surface only at layer 0 and above menu-bar size. macOS
/// menu bars are ~30 pt tall and appear once per attached display, so they dominate the list
/// on a multi-display machine and are exactly what produced the false positive.
func isRenderCandidate(layer: Int, width: Double, height: Double) -> Bool {
    layer == 0 && height > 60 && width > 200
}

struct Row {
    let num: Int, layer: Int, alpha: Double, x: Double, y: Double, w: Double, h: Double, on: Bool
    var isRender: Bool { isRenderCandidate(layer: layer, width: w, height: h) }
}

let rows: [Row] = mine.map { win in
    let rect = win[kCGWindowBounds as String] as? [String: Any] ?? [:]
    func num(_ key: String) -> Double { (rect[key] as? NSNumber)?.doubleValue ?? 0 }
    let id = win[kCGWindowNumber as String] as? Int ?? -1
    return Row(num: id,
               layer: win[kCGWindowLayer as String] as? Int ?? -999,
               alpha: win[kCGWindowAlpha as String] as? Double ?? -1,
               x: num("X"), y: num("Y"), w: num("Width"), h: num("Height"),
               on: onScreen.contains(id))
}

for row in rows {
    let kind = row.isRender ? "RENDER" : "chrome"
    print("window \(row.num) [\(kind)] layer=\(row.layer) alpha=\(row.alpha) onScreen=\(row.on) "
          + "bounds=\(Int(row.x)),\(Int(row.y)) \(Int(row.w))x\(Int(row.h))")
}

// The verdict, computed ONLY over render-sized windows.
print("")
let render = rows.filter(\.isRender)
if render.isEmpty {
    print("VERDICT: no render-sized window found — cannot judge occlusion from this capture.")
} else if render.contains(where: { $0.on && $0.alpha > 0.01 }) {
    print("VERDICT: render window is ON SCREEN and composited — occlusion is NOT the condition here.")
} else {
    print("VERDICT: every render-sized window is off-screen or transparent — occlusion IS possible.")
    print("         Note the occlusion hypothesis was experimentally refuted at HANG.1;")
    print("         treat this as a NEW observation needing its own evidence, not a confirmation.")
}
let chrome = rows.count - render.count
if chrome > 0 {
    print("(\(chrome) chrome window(s) omitted from the verdict — menu bars/panels, one per display.)")
}
