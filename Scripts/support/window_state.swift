import CoreGraphics
import Foundation
// Window state WITHOUT assistive access: CGWindowList reports bounds, layer and on-screen
// membership for any app. This is what the BUG-085 occlusion hypothesis needs, and the
// AppleScript route (which the capture script used first) is blocked unless the user grants
// Accessibility — so it recorded a permission error instead of the answer.
let all = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
let onScreen = Set((CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? [])
    .compactMap { $0[kCGWindowNumber as String] as? Int })
let mine = all.filter { ($0[kCGWindowOwnerName as String] as? String) == "PhospheneApp" }
if mine.isEmpty { print("PhospheneApp: no windows found (not running?)") }
for win in mine {
    let num = win[kCGWindowNumber as String] as? Int ?? -1
    let rect = win[kCGWindowBounds as String] as? [String: Any] ?? [:]
    let alpha = win[kCGWindowAlpha as String] as? Double ?? -1
    let layer = win[kCGWindowLayer as String] as? Int ?? -999
    let on = onScreen.contains(num)
    print("window \(num) layer=\(layer) alpha=\(alpha) onScreen=\(on) "
          + "bounds=\(rect["X"] ?? "?"),\(rect["Y"] ?? "?") \(rect["Width"] ?? "?")x\(rect["Height"] ?? "?")")
    print("  -> \(on ? "COMPOSITED" : "NOT on screen — minimised or hidden; this is the BUG-085 occlusion condition")")
}
