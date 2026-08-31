// ChainHealthAnalyzer — CLI wrapper around ChainAnalyzer (ASH.2).
//
// Grades a session directory out-of-process (retroactive grading of old dirs)
// using the same ChainAnalyzer the app runs in-process at session end. Writes
// chain_health.json + the CHAIN_HEALTH: line into the dir and prints the verdict.
//
//   swift run --package-path PhospheneEngine ChainHealthAnalyzer <session-dir>
//
// Wrapped by Scripts/analyze_session_chain.sh.

import Foundation
import Shared

let args = CommandLine.arguments
guard args.count == 2 else {
    FileHandle.standardError.write(Data("usage: ChainHealthAnalyzer <session-dir>\n".utf8))
    exit(2)
}

let dir = URL(fileURLWithPath: (args[1] as NSString).expandingTildeInPath)
var isDir: ObjCBool = false
guard FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else {
    FileHandle.standardError.write(Data("not a directory: \(dir.path)\n".utf8))
    exit(1)
}

let health = ChainAnalyzer.analyzeAndWrite(sessionDir: dir)
print(health.logLine)
if let peak = health.peakDBFS { print("  peak: \(String(format: "%.1f", peak)) dBFS") }
if let onsets = health.loveRehabMedianOnsetsPer5s { print("  love-rehab onsets/5s (median): \(onsets)") }
if !health.notes.isEmpty { print("  notes: \(health.notes.joined(separator: ", "))") }
// Exit code mirrors the verdict so CI / reel scripts can gate on it.
exit(health.verdict == .clean ? 0 : 1)
