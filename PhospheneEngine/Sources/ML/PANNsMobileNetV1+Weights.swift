// PANNsMobileNetV1+Weights — manifest parsing, .bin loading, BN fusion.
//
// Weights live at Sources/ML/Weights/panns_mobilenetv1/<name>.bin, indexed by
// manifest.json in the same directory (146 float32 tensors, ~23.6 MB). BN is
// fused into scale/shift at load (reusing fuseBeatThisBN); conv weights stay
// OIHW and are rearranged to HWIO at graph build. The torchlibrosa STFT basis
// (conv_real/conv_imag) and librosa mel filterbank (melW) ship as tensors so
// the front-end is exact matmuls (see +Frontend).

import Accelerate
import Foundation

// MARK: - Manifest

struct PANNsManifest: Decodable {
    let formatVersion: Int
    let dtype: String
    let tensors: [String: TensorEntry]

    struct TensorEntry: Decodable {
        let file: String
        let shape: [Int]
        let bytes: Int
        let sha256: String
    }

    enum CodingKeys: String, CodingKey {
        case formatVersion = "format_version"
        case dtype, tensors
    }
}

// MARK: - Weight Structs

/// Fused BN: y = x * scale + shift.
struct PANNsFusedBN {
    let scale: [Float]
    let shift: [Float]
}

/// Front-end matrices, exported from the checkpoint (exact parity, no librosa).
struct PANNsFrontendMatrices {
    let convReal: [Float]   // [nBins, nFFT] row-major (Hann-windowed DFT cos basis)
    let convImag: [Float]   // [nBins, nFFT] (sin basis)
    let melW: [Float]       // [nBins, 64] mel filterbank
    let nBins: Int          // 513 = nFFT/2 + 1
}

/// conv_bn stage: Conv2d(3x3,pad1) → AvgPool(stride) → BN → ReLU.
struct PANNsConvBN {
    let convWeight: [Float] // OIHW [outC, inC, 3, 3]
    let inC: Int
    let outC: Int
    let stride: Int
    let bn: PANNsFusedBN
}

/// conv_dw stage: dwConv(3x3,pad1,groups=inC) → AvgPool(stride) → BN → ReLU →
/// pwConv(1x1) → BN → ReLU.
struct PANNsConvDW {
    let dwWeight: [Float]   // OIHW [inC, 1, 3, 3]
    let bn1: PANNsFusedBN   // dim inC
    let pwWeight: [Float]   // OIHW [outC, inC, 1, 1]
    let bn2: PANNsFusedBN   // dim outC
    let inC: Int
    let outC: Int
    let stride: Int
}

struct PANNsWeights {
    let frontend: PANNsFrontendMatrices
    let bn0: PANNsFusedBN
    let stage0: PANNsConvBN
    let dwStages: [PANNsConvDW]   // features.1 … features.13
    let fc1Weight: [Float]        // [1024, 1024]
    let fc1Bias: [Float]
    let fcWeight: [Float]         // [527, 1024]
    let fcBias: [Float]
}

// MARK: - Errors

enum PANNsWeightError: Error, Sendable {
    case manifestNotFound
    case manifestDecodeFailed(String)
    case tensorNotFound(String)
    case tensorFileMissing(String)
    case tensorSizeMismatch(String, expected: Int, got: Int)
    case checksumMismatch(key: String, expected: String, got: String)
}

// MARK: - Stage Spec for features.1 … features.13

private struct DWSpec {
    let inC: Int
    let outC: Int
    let stride: Int
    init(_ inC: Int, _ outC: Int, _ stride: Int) { self.inC = inC; self.outC = outC; self.stride = stride }
}

private let dwSpecs: [DWSpec] = [
    DWSpec(32, 64, 1), DWSpec(64, 128, 2), DWSpec(128, 128, 1), DWSpec(128, 256, 2), DWSpec(256, 256, 1),
    DWSpec(256, 512, 2), DWSpec(512, 512, 1), DWSpec(512, 512, 1), DWSpec(512, 512, 1), DWSpec(512, 512, 1),
    DWSpec(512, 512, 1), DWSpec(512, 1024, 2), DWSpec(1024, 1024, 1),
]

// MARK: - Loading

extension PANNsMobileNetV1 {

    static func loadWeights() throws -> PANNsWeights {
        let manifest = try loadPANNsManifest()
        func ten(_ key: String) throws -> [Float] {
            try loadPANNsTensor(key: key, manifest: manifest)
        }
        func fuseBN(_ pfx: String) throws -> PANNsFusedBN {
            let fused = fuseBeatThisBN(
                weight: try ten("\(pfx).weight"),
                bias: try ten("\(pfx).bias"),
                runningMean: try ten("\(pfx).running_mean"),
                runningVar: try ten("\(pfx).running_var"))
            return PANNsFusedBN(scale: fused.scale, shift: fused.shift)
        }

        let frontend = PANNsFrontendMatrices(
            convReal: try ten("spectrogram_extractor.stft.conv_real.weight"),
            convImag: try ten("spectrogram_extractor.stft.conv_imag.weight"),
            melW: try ten("logmel_extractor.melW"),
            nBins: Self.nFFT / 2 + 1)

        let stage0 = PANNsConvBN(
            convWeight: try ten("features.0.0.weight"),
            inC: 1,
            outC: 32,
            stride: 2,
            bn: try fuseBN("features.0.2"))

        var dwStages = [PANNsConvDW]()
        for (idx, spec) in dwSpecs.enumerated() {
            let i = idx + 1   // features.1 … features.13
            dwStages.append(PANNsConvDW(
                dwWeight: try ten("features.\(i).0.weight"),
                bn1: try fuseBN("features.\(i).2"),
                pwWeight: try ten("features.\(i).4.weight"),
                bn2: try fuseBN("features.\(i).5"),
                inC: spec.inC,
                outC: spec.outC,
                stride: spec.stride))
        }

        return PANNsWeights(
            frontend: frontend,
            bn0: try fuseBN("bn0"),
            stage0: stage0,
            dwStages: dwStages,
            fc1Weight: try ten("fc1.weight"),
            fc1Bias: try ten("fc1.bias"),
            fcWeight: try ten("fc_audioset.weight"),
            fcBias: try ten("fc_audioset.bias"))
    }
}

// MARK: - Bundle I/O

private func loadPANNsManifest() throws -> PANNsManifest {
    guard let url = Bundle.module.url(
        forResource: "manifest",
        withExtension: "json",
        subdirectory: "Weights/panns_mobilenetv1"
    ) else {
        throw PANNsWeightError.manifestNotFound
    }
    let data = try Data(contentsOf: url)
    do {
        return try JSONDecoder().decode(PANNsManifest.self, from: data)
    } catch {
        throw PANNsWeightError.manifestDecodeFailed(error.localizedDescription)
    }
}

private func loadPANNsTensor(key: String, manifest: PANNsManifest) throws -> [Float] {
    guard let entry = manifest.tensors[key] else {
        throw PANNsWeightError.tensorNotFound(key)
    }
    guard let url = Bundle.module.url(
        forResource: entry.file,
        withExtension: nil,
        subdirectory: "Weights/panns_mobilenetv1"
    ) else {
        throw PANNsWeightError.tensorFileMissing(entry.file)
    }
    let raw = try Data(contentsOf: url)
    guard raw.count == entry.bytes else {
        throw PANNsWeightError.tensorSizeMismatch(key, expected: entry.bytes, got: raw.count)
    }
    try WeightChecksum.verify(raw, expected: entry.sha256, key: key) {
        PANNsWeightError.checksumMismatch(key: $0, expected: $1, got: $2)
    }
    let count = raw.count / MemoryLayout<Float>.size
    return raw.withUnsafeBytes { buf in
        Array(buf.bindMemory(to: Float.self).prefix(count))
    }
}
