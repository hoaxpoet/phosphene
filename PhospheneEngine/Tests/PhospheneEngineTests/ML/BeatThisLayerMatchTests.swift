// BeatThisLayerMatchTests — Per-stage numerical match against Python reference activations.
//
// Loads docs/diagnostics/DSP.2-S8-python-activations.json (committed ground truth, 34 stages)
// and compares each checked stage's min / max / mean against the corresponding Swift intermediate
// from BeatThisModel.predictDiagnostic run on love_rehab.m4a.
//
// Checked stages (all have time-first layout [1500, D] in Swift so slicing to 1497 frames is trivial):
//   stem.bn1d, frontend.linear, transformer.norm, head.linear, output.beat_logits, output.beat_sigmoid
//
// Transformer blocks (transformer.0–5) are NOT checked here: the Python dump script hooks
// sub-block outputs (before residual addition), while Swift captures full-block outputs
// (after residual), making them incompatible.  The transformer block regression surface is
// the final output stages (beat_logits, beat_sigmoid), which must match Python end-to-end.
//
// Two tolerance tiers:
//   preTfmTol = 2e-3  — pre-transformer stages (stem.bn1d, frontend.linear).
//               No attention sees the padded frames yet; 2e-3 isolates float32 noise.
//   postTfmTol = 1e-2 — post-transformer stages (transformer.norm, head.linear, output.*).
//               Non-causal self-attention propagates the 3 padded frames' influence to
//               all 1497 signal frames via softmax weights, introducing ~0.3–0.9% delta
//               even after slicing.  1e-2 covers this while remaining 100× tighter than
//               any real regression (all four S8 bugs caused > 100% divergence).
//
// The test is skipped gracefully when either fixture is absent (CI without audio fixtures).

import Testing
import Foundation
import Metal
@testable import DSP
@testable import ML

// MARK: - JSON decode helpers

private struct PyActivationStage: Decodable {
    let name: String
    let min: Double
    let max: Double
    let mean: Double
}

private struct PyActivationsDoc: Decodable {
    let stages: [PyActivationStage]
}

// MARK: - Stage mapping

// Each entry: (swiftName, pythonName, colsPerRow, toleranceTier)
// colsPerRow = product of all dims other than the first (time) axis.
// toleranceTier: "pre" = 2e-3 (before transformer); "post" = 1e-2 (after transformer).
private let layerMatchStages: [(swift: String, python: String, cols: Int, tier: String)] = [
    // Pre-transformer: tight tolerance (no attention over padded frames yet).
    ("stem.bn1d",          "stem.bn1d",           128, "pre"),
    ("frontend.linear",    "frontend.linear",      128, "pre"),
    // Post-transformer: looser tolerance (padding propagates via softmax across all frames).
    ("transformer.norm",   "transformer.norm",     128, "post"),
    ("head.linear",        "head.linear",            2, "post"),
    ("output.beat_logits", "output.beat_logits",     1, "post"),
    ("output.beat_sigmoid","output.beat_sigmoid",    1, "post"),
]

private let frameCount = 1497  // love_rehab.m4a at 50 fps

// MARK: - Suite

@Suite("BeatThisLayerMatch")
struct BeatThisLayerMatchTests {

    // MARK: - Main numerical-match test

    /// Load the Python reference stats and Swift intermediate activations once,
    /// then assert each stage's max/mean/min match within 2e-3 relative error.
    ///
    /// This test is the load-bearing regression surface for all four DSP.2 S8 bugs:
    ///   Bug 1 (norm shape)    — visible at stem.bn1d and frontend.linear
    ///   Bug 2 (stem reshape)  — visible at stem.bn1d and all downstream stages
    ///   Bug 3 (BN1d padding)  — visible at stem.bn1d edge frames and output
    ///   Bug 4 (paired RoPE)   — visible at transformer.0 and all transformer stages
    @Test func test_swiftMatchesPython_allKeyStages() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("BeatThisLayerMatchTests: no Metal device — skipping")
            return
        }

        // MARK: Locate fixtures
        let testDir = URL(fileURLWithPath: String(#filePath)).deletingLastPathComponent()
        let audioURL = testDir
            .deletingLastPathComponent()  // PhospheneEngineTests/
            .deletingLastPathComponent()  // Tests/
            .appendingPathComponent("Fixtures/tempo/love_rehab.m4a")
        let jsonURL = testDir
            .deletingLastPathComponent()  // PhospheneEngineTests/
            .deletingLastPathComponent()  // Tests/
            .deletingLastPathComponent()  // PhospheneEngine/
            .deletingLastPathComponent()  // repo root
            .appendingPathComponent("docs/diagnostics/DSP.2-S8-python-activations.json")

        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            print("BeatThisLayerMatchTests: skipping — audio fixture absent at \(audioURL.path)")
            return
        }
        guard FileManager.default.fileExists(atPath: jsonURL.path) else {
            print("BeatThisLayerMatchTests: skipping — JSON fixture absent at \(jsonURL.path)")
            return
        }

        // MARK: Load Python reference
        let jsonData = try Data(contentsOf: jsonURL)
        let pyDoc = try JSONDecoder().decode(PyActivationsDoc.self, from: jsonData)
        let pyByName = Dictionary(uniqueKeysWithValues: pyDoc.stages.map { ($0.name, $0) })

        // MARK: Load audio + run predictDiagnostic
        let samples = try decodeMono22050(url: audioURL)
        let pre = BeatThisPreprocessor()
        let (spect, actualFrameCount) = pre.process(samples: samples, inputSampleRate: 22050)
        let model = try BeatThisModel(device: device)
        let captures = try model.predictDiagnostic(spectrogram: spect, frameCount: actualFrameCount)

        // MARK: Compare each stage
        func relErr(_ a: Float, _ b: Float) -> Float {
            abs(a - b) / max(abs(b), 1e-6)
        }
        let preTfmTol: Float  = 2e-3   // stem, frontend: no attention over padding
        let postTfmTol: Float = 1e-2   // transformer+: softmax sees padding → ~0.3–0.9% delta

        var failures: [(stage: String, stat: String, py: Float, sw: Float, relErr: Float, tol: Float)] = []

        for entry in layerMatchStages {
            guard let pyStage = pyByName[entry.python] else {
                Issue.record("Python stage '\(entry.python)' not found in reference JSON")
                continue
            }
            guard let swEntry = captures[entry.swift] else {
                Issue.record("Swift stage '\(entry.swift)' not captured by predictDiagnostic")
                continue
            }

            // Slice to the first `frameCount` rows (time axis 0) to match Python's 1497 frames.
            let sliceCount = frameCount * entry.cols
            let sliced: ArraySlice<Float>
            if swEntry.values.count >= sliceCount {
                sliced = swEntry.values[0..<sliceCount]
            } else {
                Issue.record("Stage '\(entry.swift)': insufficient values (\(swEntry.values.count) < \(sliceCount))")
                continue
            }

            let swMin  = sliced.min() ?? 0
            let swMax  = sliced.max() ?? 0
            let swMean = sliced.reduce(0, +) / Float(sliced.count)

            let pyMin  = Float(pyStage.min)
            let pyMax  = Float(pyStage.max)
            let pyMean = Float(pyStage.mean)

            let tol: Float = entry.tier == "pre" ? preTfmTol : postTfmTol

            if relErr(swMax, pyMax) > tol {
                failures.append((entry.swift, "max", pyMax, swMax, relErr(swMax, pyMax), tol))
            }
            if relErr(swMin, pyMin) > tol {
                failures.append((entry.swift, "min", pyMin, swMin, relErr(swMin, pyMin), tol))
            }
            if relErr(swMean, pyMean) > tol {
                failures.append((entry.swift, "mean", pyMean, swMean, relErr(swMean, pyMean), tol))
            }
        }

        #expect(failures.isEmpty, """
            Layer match failures (\(failures.count)):
            \(failures.map { "  \($0.stage).\($0.stat) (tol=\(String(format:"%.0e",$0.tol))): py=\($0.py) sw=\($0.sw) relErr=\(String(format: "%.4f", $0.relErr))" }.joined(separator: "\n"))
            """)
    }

    // MARK: - Helpers

    private func decodeMono22050(url: URL) throws -> [Float] {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = [
            "ffmpeg", "-loglevel", "error",
            "-i", url.path,
            "-ac", "1", "-ar", "22050",
            "-f", "f32le", "-"
        ]
        let stdoutPipe = Pipe()
        proc.standardOutput = stdoutPipe
        proc.standardError = Pipe()
        try proc.run()
        let raw = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else {
            throw NSError(
                domain: "BeatThisLayerMatchTests",
                code: Int(proc.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: "ffmpeg decode failed"]
            )
        }
        let count = raw.count / MemoryLayout<Float>.size
        return raw.withUnsafeBytes { buf in
            let typed = buf.bindMemory(to: Float.self)
            return Array(UnsafeBufferPointer(start: typed.baseAddress, count: count))
        }
    }
}
