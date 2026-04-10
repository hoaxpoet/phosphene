// StemModel+Weights — Weight manifest parsing, .bin loading, and batch norm fusion.
//
// Loads the 172 Open-Unmix HQ weight tensors (43 per stem × 4 stems) from
// raw float32 .bin files bundled in Sources/ML/Weights/. Batch norm layers
// are fused at load time into a single scale+bias per layer.

import Accelerate
import Foundation
import Metal

// MARK: - Manifest Parsing

/// JSON structure of the weight manifest.
struct WeightManifest: Decodable {
    let formatVersion: Int
    let model: String
    let stems: [String]
    let dtype: String
    let tensors: [String: TensorEntry]

    struct TensorEntry: Decodable {
        let file: String
        let shape: [Int]
        let bytes: Int
    }

    enum CodingKeys: String, CodingKey {
        case formatVersion = "format_version"
        case model, stems, dtype, tensors
    }
}

// MARK: - Per-Stem Weight Bundles

/// Fused batch norm: y = x * scale + bias.
struct FusedBatchNorm {
    let scale: [Float]
    let bias: [Float]
}

/// Weights for a single LSTM layer (bidirectional).
/// Stored in the format MPSGraph expects:
/// - inputWeight: [8H, I] (forward [4H, I] + reverse [4H, I])
/// - recurrentWeight: [2, 4H, H] (forward + reverse as dim-0 slices)
/// - bias: [8H] (forward [4H] + reverse [4H])
struct LSTMLayerWeights {
    let inputWeight: [Float]      // [8*hidden, inputSize]
    let recurrentWeight: [Float]  // [2, 4*hidden, hidden] flattened
    let bias: [Float]             // [8*hidden]
    let inputSize: Int
}

/// All weights for one stem of the Open-Unmix HQ model.
struct StemWeights {
    let inputMean: [Float]       // [1487]
    let inputScale: [Float]      // [1487]
    let outputMean: [Float]      // [2049]
    let outputScale: [Float]     // [2049]

    let fc1Weight: [Float]       // [512, 2974]
    let bn1: FusedBatchNorm      // [512]

    let lstmLayers: [LSTMLayerWeights]  // 3 layers

    let fc2Weight: [Float]       // [512, 1024]
    let bn2: FusedBatchNorm      // [512]

    let fc3Weight: [Float]       // [4098, 512]
    let bn3: FusedBatchNorm      // [4098]
}

// MARK: - Weight Loading

enum StemModelWeightError: Error, Sendable {
    case manifestNotFound
    case manifestDecodeFailed(String)
    case tensorNotFound(String)
    case tensorFileMissing(String)
    case tensorSizeMismatch(String, expected: Int, got: Int)
}

/// Load all 4 stems' weights from the bundle.
func loadAllStemWeights() throws -> [StemWeights] {
    let manifest = try loadManifest()
    let stemNames = ["vocals", "drums", "bass", "other"]
    return try stemNames.map { try loadStemWeights(stem: $0, manifest: manifest) }
}

// MARK: - Manifest Loading

private func loadManifest() throws -> WeightManifest {
    guard let url = Bundle.module.url(
        forResource: "manifest",
        withExtension: "json",
        subdirectory: "Weights"
    ) else {
        throw StemModelWeightError.manifestNotFound
    }
    let data = try Data(contentsOf: url)
    do {
        return try JSONDecoder().decode(WeightManifest.self, from: data)
    } catch {
        throw StemModelWeightError.manifestDecodeFailed(error.localizedDescription)
    }
}

// MARK: - Per-Stem Loading

private func loadStemWeights(stem: String, manifest: WeightManifest) throws -> StemWeights {
    // Helper to load a single tensor.
    func tensor(_ name: String) throws -> [Float] {
        try loadTensor(key: "\(stem).\(name)", manifest: manifest)
    }

    let inputMean = try tensor("input_mean")
    let inputScale = try tensor("input_scale")
    let outputMean = try tensor("output_mean")
    let outputScale = try tensor("output_scale")

    let fc1Weight = try tensor("fc1.weight")
    let bn1 = try fuseBatchNorm(
        weight: tensor("bn1.weight"),
        bias: tensor("bn1.bias"),
        runningMean: tensor("bn1.running_mean"),
        runningVar: tensor("bn1.running_var")
    )

    let lstmLayers = try loadLSTMLayers(stem: stem, manifest: manifest)

    let fc2Weight = try tensor("fc2.weight")
    let bn2 = try fuseBatchNorm(
        weight: tensor("bn2.weight"),
        bias: tensor("bn2.bias"),
        runningMean: tensor("bn2.running_mean"),
        runningVar: tensor("bn2.running_var")
    )

    let fc3Weight = try tensor("fc3.weight")
    let bn3 = try fuseBatchNorm(
        weight: tensor("bn3.weight"),
        bias: tensor("bn3.bias"),
        runningMean: tensor("bn3.running_mean"),
        runningVar: tensor("bn3.running_var")
    )

    return StemWeights(
        inputMean: inputMean,
        inputScale: inputScale,
        outputMean: outputMean,
        outputScale: outputScale,
        fc1Weight: fc1Weight,
        bn1: bn1,
        lstmLayers: lstmLayers,
        fc2Weight: fc2Weight,
        bn2: bn2,
        fc3Weight: fc3Weight,
        bn3: bn3
    )
}

// MARK: - LSTM Weight Assembly

/// Load and assemble weights for all 3 LSTM layers of one stem.
///
/// PyTorch stores forward/reverse weights separately. MPSGraph bidirectional
/// LSTM expects them stacked:
/// - inputWeight: [8H, I] (forward [4H, I] concatenated with reverse [4H, I])
/// - recurrentWeight: [2, 4H, H] (forward slice then reverse slice)
/// - bias: [8H] (forward [4H] then reverse [4H])
///
/// PyTorch bias = bias_ih + bias_hh (summed per direction before stacking).
private func loadLSTMLayers(
    stem: String, manifest: WeightManifest
) throws -> [LSTMLayerWeights] {
    func tensor(_ name: String) throws -> [Float] {
        try loadTensor(key: "\(stem).\(name)", manifest: manifest)
    }

    var layers = [LSTMLayerWeights]()
    for layerIdx in 0..<3 {
        // Input sizes: layer 0 = 512 (FC1 output), layers 1-2 = 512 (bidirectional output)
        let inputSize = 512

        // Forward direction
        let fwdWIH = try tensor("lstm.weight_ih_l\(layerIdx)")
        let fwdWHH = try tensor("lstm.weight_hh_l\(layerIdx)")
        let fwdBIH = try tensor("lstm.bias_ih_l\(layerIdx)")
        let fwdBHH = try tensor("lstm.bias_hh_l\(layerIdx)")

        // Reverse direction
        let revWIH = try tensor("lstm.weight_ih_l\(layerIdx)_reverse")
        let revWHH = try tensor("lstm.weight_hh_l\(layerIdx)_reverse")
        let revBIH = try tensor("lstm.bias_ih_l\(layerIdx)_reverse")
        let revBHH = try tensor("lstm.bias_hh_l\(layerIdx)_reverse")

        // Combine biases: bias = bias_ih + bias_hh per direction
        let fwdBias = addVectors(fwdBIH, fwdBHH)
        let revBias = addVectors(revBIH, revBHH)

        // Stack inputWeight: [8H, I] = concat([4H, I], [4H, I])
        let inputWeight = fwdWIH + revWIH

        // Stack recurrentWeight: [2, 4H, H] flattened = concat([4H, H], [4H, H])
        let recurrentWeight = fwdWHH + revWHH

        // Stack bias: [8H] = concat([4H], [4H])
        let bias = fwdBias + revBias

        layers.append(LSTMLayerWeights(
            inputWeight: inputWeight,
            recurrentWeight: recurrentWeight,
            bias: bias,
            inputSize: inputSize
        ))
    }
    return layers
}

// MARK: - Tensor File I/O

private func loadTensor(key: String, manifest: WeightManifest) throws -> [Float] {
    guard let entry = manifest.tensors[key] else {
        throw StemModelWeightError.tensorNotFound(key)
    }
    guard let url = Bundle.module.url(
        forResource: entry.file,
        withExtension: nil,
        subdirectory: "Weights"
    ) else {
        throw StemModelWeightError.tensorFileMissing(entry.file)
    }
    let data = try Data(contentsOf: url)
    let expectedBytes = entry.bytes
    guard data.count == expectedBytes else {
        throw StemModelWeightError.tensorSizeMismatch(
            key, expected: expectedBytes, got: data.count
        )
    }
    let count = data.count / MemoryLayout<Float>.size
    return data.withUnsafeBytes { raw in
        Array(raw.bindMemory(to: Float.self).prefix(count))
    }
}

// MARK: - Batch Norm Fusion

/// Fuse batch norm into a single scale + bias operation.
///
/// In inference mode: `y = (x - mean) / sqrt(var + eps) * gamma + beta`
/// Fused: `y = x * fusedScale + fusedBias`
/// where `fusedScale = gamma / sqrt(var + eps)`
///   and `fusedBias = beta - mean * fusedScale`
private func fuseBatchNorm(
    weight: [Float],
    bias: [Float],
    runningMean: [Float],
    runningVar: [Float],
    eps: Float = 1e-5
) -> FusedBatchNorm {
    let count = weight.count
    var fusedScale = [Float](repeating: 0, count: count)
    var fusedBias = [Float](repeating: 0, count: count)

    // Vectorize: invStd = 1 / sqrt(var + eps)
    var epsVec = [Float](repeating: eps, count: count)
    var varPlusEps = [Float](repeating: 0, count: count)
    vDSP_vadd(runningVar, 1, &epsVec, 1, &varPlusEps, 1, vDSP_Length(count))

    var invStd = [Float](repeating: 0, count: count)
    var sqrtResult = [Float](repeating: 0, count: count)
    var countInt32 = Int32(count)
    vvsqrtf(&sqrtResult, varPlusEps, &countInt32)

    // invStd = 1.0 / sqrt(var + eps)
    var one: Float = 1.0
    vDSP_svdiv(&one, sqrtResult, 1, &invStd, 1, vDSP_Length(count))

    // fusedScale = weight * invStd
    vDSP_vmul(weight, 1, invStd, 1, &fusedScale, 1, vDSP_Length(count))

    // fusedBias = bias - runningMean * fusedScale
    var meanTimesScale = [Float](repeating: 0, count: count)
    vDSP_vmul(runningMean, 1, fusedScale, 1, &meanTimesScale, 1, vDSP_Length(count))
    vDSP_vsub(meanTimesScale, 1, bias, 1, &fusedBias, 1, vDSP_Length(count))

    return FusedBatchNorm(scale: fusedScale, bias: fusedBias)
}

// MARK: - Vector Utilities

/// Element-wise addition of two float vectors.
private func addVectors(_ lhs: [Float], _ rhs: [Float]) -> [Float] {
    var result = [Float](repeating: 0, count: lhs.count)
    vDSP_vadd(lhs, 1, rhs, 1, &result, 1, vDSP_Length(lhs.count))
    return result
}
