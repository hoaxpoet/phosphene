// PANNsMobileNetV1Tests — numerical parity vs the PyTorch reference (IFC.2).
//
// The reference fixtures are produced by tools/panns_reference.py on two
// public-domain orchestral clips (Beethoven Sym 5 i. — strings; Wind Octet
// Op.103 — brass↔woodwind trades). This suite proves the MPSGraph port matches
// the PyTorch MobileNetV1 to numerical parity along the whole chain:
//   front-end (waveform → log-mel) → network (log-mel → 527 sigmoids),
// and that the per-family activity discrimination (the IFC payload) is
// reproduced family-for-family on real orchestral windows.

import Foundation
import Metal
import Testing
@testable import ML

@Suite struct PANNsMobileNetV1Tests {

    // MARK: - Fixture models

    struct Tap: Decodable { let shape: [Int]; let data: [Float] }
    struct FixtureEntry: Decodable {
        let waveform: [Float]?
        let logmel: [Float]
        let logits: [Float]
        let probs: [Float]
        let taps: [String: Tap]?
    }
    struct Window: Decodable {
        let tag: String
        let t: Double
        let logmel: [Float]
        let probs: [Float]
        let family: [String: Float]
    }
    struct WindowsDoc: Decodable {
        let family_indices: [String: [Int]]   // swiftlint:disable:this identifier_name
        let windows: [Window]
    }

    static func loadJSON<T: Decodable>(_ name: String, _ type: T.Type) throws -> T {
        let url = try #require(Bundle.module.url(
            forResource: name, withExtension: "json", subdirectory: "panns_reference"))
        return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
    }

    static func maxAbsDiff(_ a: [Float], _ b: [Float]) -> Float {
        precondition(a.count == b.count, "len \(a.count) != \(b.count)")
        return zip(a, b).map { abs($0 - $1) }.max() ?? 0
    }

    // MARK: - Build / load

    @Test func test_weightsLoad_noThrow() throws {
        #expect(throws: Never.self) { _ = try PANNsMobileNetV1.loadWeights() }
    }

    @Test func test_graphBuilds() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        _ = try PANNsMobileNetV1(device: device)
    }

    // MARK: - Front-end parity (waveform → log-mel)

    @Test func test_frontendParity() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        let model = try PANNsMobileNetV1(device: device)
        let fixtures = try Self.loadJSON("fixtures", [String: FixtureEntry].self)
        for (name, entry) in fixtures {
            guard let waveform = entry.waveform else { continue }
            let lm = model.logMel(waveform: waveform)
            let diff = Self.maxAbsDiff(lm, entry.logmel)
            print("frontend \(name): logmel max abs diff = \(diff) dB")
            #expect(diff < 0.05, "front-end log-mel diverges (\(diff) dB) for \(name)")
        }
    }

    // MARK: - Network parity (reference log-mel → probs), isolates the conv stack

    @Test func test_networkParity_fromReferenceLogMel() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        let model = try PANNsMobileNetV1(device: device)
        let fixtures = try Self.loadJSON("fixtures", [String: FixtureEntry].self)
        for (name, entry) in fixtures {
            let diag = try model.predictFromLogMel(entry.logmel)
            let probDiff = Self.maxAbsDiff(diag.probs, entry.probs)
            let logitDiff = Self.maxAbsDiff(diag.logits, entry.logits)
            print("network \(name): prob diff = \(probDiff), logit diff = \(logitDiff)")
            #expect(diag.probs.count == PANNsMobileNetV1.classCount)
            #expect(probDiff < 5e-3, "probs diverge (\(probDiff)) for \(name)")
            #expect(logitDiff < 5e-2, "logits diverge (\(logitDiff)) for \(name)")
            if let bn0 = entry.taps?["bn0"] {
                let bnDiff = Self.maxAbsDiff(diag.taps["bn0"] ?? [], bn0.data)
                print("network \(name): bn0 tap diff = \(bnDiff)")
                #expect(bnDiff < 5e-2, "bn0 diverges (\(bnDiff)) for \(name)")
            }
            if let preFc = entry.taps?["pre_fc"] {
                let pfDiff = Self.maxAbsDiff(diag.taps["pre_fc"] ?? [], preFc.data)
                print("network \(name): pre_fc tap diff = \(pfDiff)")
                #expect(pfDiff < 5e-2, "pre_fc diverges (\(pfDiff)) for \(name)")
            }
        }
    }

    // MARK: - End-to-end parity (waveform → probs)

    @Test func test_endToEndParity() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        let model = try PANNsMobileNetV1(device: device)
        let fixtures = try Self.loadJSON("fixtures", [String: FixtureEntry].self)
        for (name, entry) in fixtures {
            guard let waveform = entry.waveform else { continue }
            let probs = try model.predict(waveform: waveform)
            let diff = Self.maxAbsDiff(probs, entry.probs)
            print("end-to-end \(name): prob diff = \(diff)  top=\(argmax(probs)) ref-top=\(argmax(entry.probs))")
            #expect(diff < 5e-3, "end-to-end probs diverge (\(diff)) for \(name)")
            #expect(argmax(probs) == argmax(entry.probs), "top class mismatch for \(name)")
        }
    }

    // MARK: - Per-family discrimination matches the reference

    @Test func test_perFamilyDiscriminationMatches() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        let model = try PANNsMobileNetV1(device: device)
        let doc = try Self.loadJSON("windows", WindowsDoc.self)
        let order = ["strings", "brass", "woodwinds", "timpani", "orchestra"]

        func pad(_ s: String, _ n: Int) -> String {
            s.count >= n ? s : s + String(repeating: " ", count: n - s.count)
        }
        func f3(_ v: Float) -> String { String(format: "%.3f", v) }

        print("per-family activity — Swift port vs PyTorch reference:")
        print("  " + pad("window", 12) + pad("family", 11) + pad("swift", 8) + "ref")
        var worst: Float = 0
        for w in doc.windows {
            let diag = try model.predictFromLogMel(w.logmel)
            let label = "\(w.tag)@\(Int(w.t))s"
            for fam in order {
                guard let idxs = doc.family_indices[fam] else { continue }
                let swiftVal = idxs.map { diag.probs[$0] }.max() ?? 0
                let refVal = w.family[fam] ?? 0
                let d = abs(swiftVal - refVal)
                worst = max(worst, d)
                if fam == "strings" || fam == "brass" || fam == "woodwinds" {
                    print("  " + pad(label, 12) + pad(fam, 11) + pad(f3(swiftVal), 8) + f3(refVal))
                }
                #expect(d < 5e-3, "family \(fam) diverges (\(d)) at \(label)")
            }
        }
        print("per-family worst abs diff = \(worst)")
    }

    private func argmax(_ a: [Float]) -> Int {
        var best = 0
        for i in 1..<a.count where a[i] > a[best] { best = i }
        return best
    }
}
