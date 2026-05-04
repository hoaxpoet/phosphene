// BeatThisModel+Weights — Manifest parsing, .bin loading, BN fusion for Beat This! small0.
//
// Weight files live at Sources/ML/Weights/beat_this/<name>.bin and are indexed by
// manifest.json in the same directory.  161 float32 tensors, 8.4 MB.

import Accelerate
import Foundation

// MARK: - Manifest

/// JSON index for the Beat This! weight bundle.
struct BeatThisManifest: Decodable {
    let formatVersion: Int
    let dtype: String
    let tensors: [String: TensorEntry]

    struct TensorEntry: Decodable {
        let file: String
        let shape: [Int]
        let bytes: Int
    }

    enum CodingKeys: String, CodingKey {
        case formatVersion = "format_version"
        case dtype, tensors
    }
}

// MARK: - Weight Structs

/// Fused BN: y = x * scale + shift.
struct BeatThisFusedBN {
    let scale: [Float]
    let shift: [Float]
}

/// Weights for one attention sub-block (attnF / attnT in frontend; transformer attention).
struct BeatThisAttnWeights {
    let normGamma: [Float]   // RMSNorm γ
    let qkvWeight: [Float]   // [3·H·D, dim]
    let gateWeight: [Float]  // [H, dim]
    let gateBias: [Float]    // [H]
    let outWeight: [Float]   // [dim, H·D]  (to_out.0.weight)
}

/// Weights for one FFN sub-block (ffF / ffT in frontend; transformer FFN).
struct BeatThisFFNWeights {
    let normGamma: [Float]   // RMSNorm γ  (net.0.gamma)
    let upWeight: [Float]    // [ff_dim, dim]
    let upBias: [Float]      // [ff_dim]
    let downWeight: [Float]  // [dim, ff_dim]
    let downBias: [Float]    // [dim]
}

/// Weights for one PartialFTTransformer block + downsampling conv + norm.
struct BeatThisFrontendBlockWeights {
    let attnF: BeatThisAttnWeights
    let ffF: BeatThisFFNWeights
    let attnT: BeatThisAttnWeights
    let ffT: BeatThisFFNWeights
    let convWeight: [Float]      // [outC, inC, kH, kW] OIHW — rearranged to HWIO at graph build
    let norm: BeatThisFusedBN    // BN2d applied before downsampling conv
}

/// Weights for one transformer block (attention + FFN).
struct BeatThisTransformerBlockWeights {
    let attn: BeatThisAttnWeights
    let ffn: BeatThisFFNWeights
}

/// All weights for the Beat This! small0 model.
struct BeatThisWeights {
    let stemBN1d: BeatThisFusedBN     // applied to [T, 128] input
    let stemConvWeight: [Float]        // [32, 1, 4, 3] OIHW → rearranged at graph build
    let stemBN2d: BeatThisFusedBN     // applied to conv output [1, H, T, 32] NHWC
    let frontendBlocks: [BeatThisFrontendBlockWeights]  // 3 blocks
    let projWeight: [Float]            // [128, 1024]
    let projBias: [Float]              // [128]
    let transformerBlocks: [BeatThisTransformerBlockWeights]  // 6 blocks
    let postNormGamma: [Float]         // [128]
    let headWeight: [Float]            // [2, 128]
    let headBias: [Float]              // [2]
}

// MARK: - Errors

enum BeatThisWeightError: Error, Sendable {
    case manifestNotFound
    case manifestDecodeFailed(String)
    case tensorNotFound(String)
    case tensorFileMissing(String)
    case tensorSizeMismatch(String, expected: Int, got: Int)
}

// MARK: - Loading

extension BeatThisModel {

    // Load all Beat This! small0 weights from the bundle.
    // swiftlint:disable:next function_body_length
    static func loadWeights() throws -> BeatThisWeights {
        let manifest = try loadBeatThisManifest()
        func ten(_ key: String) throws -> [Float] {
            try loadBeatThisTensor(key: key, manifest: manifest)
        }
        func fuseBN(_ pfx: String) throws -> BeatThisFusedBN {
            try fuseBeatThisBN(
                weight: ten("\(pfx).weight"),
                bias: ten("\(pfx).bias"),
                runningMean: ten("\(pfx).running_mean"),
                runningVar: ten("\(pfx).running_var")
            )
        }
        func attn(_ pfx: String) throws -> BeatThisAttnWeights {
            try BeatThisAttnWeights(
                normGamma: ten("\(pfx).norm.gamma"),
                qkvWeight: ten("\(pfx).to_qkv.weight"),
                gateWeight: ten("\(pfx).to_gates.weight"),
                gateBias: ten("\(pfx).to_gates.bias"),
                outWeight: ten("\(pfx).to_out.0.weight")
            )
        }
        func ffn(_ pfx: String) throws -> BeatThisFFNWeights {
            try BeatThisFFNWeights(
                normGamma: ten("\(pfx).net.0.gamma"),
                upWeight: ten("\(pfx).net.1.weight"),
                upBias: ten("\(pfx).net.1.bias"),
                downWeight: ten("\(pfx).net.4.weight"),
                downBias: ten("\(pfx).net.4.bias")
            )
        }

        var feBlocks = [BeatThisFrontendBlockWeights]()
        for idx in 0..<3 {
            let blk = "frontend.blocks.\(idx)"
            feBlocks.append(BeatThisFrontendBlockWeights(
                attnF: try attn("\(blk).partial.attnF"),
                ffF: try ffn("\(blk).partial.ffF"),
                attnT: try attn("\(blk).partial.attnT"),
                ffT: try ffn("\(blk).partial.ffT"),
                convWeight: try ten("\(blk).conv2d.weight"),
                norm: try fuseBN("\(blk).norm")
            ))
        }

        var txBlocks = [BeatThisTransformerBlockWeights]()
        for idx in 0..<numBlocks {
            let blk = "transformer_blocks.layers.\(idx)"
            txBlocks.append(BeatThisTransformerBlockWeights(
                attn: try attn("\(blk).0"),
                ffn: try ffn("\(blk).1")
            ))
        }

        return BeatThisWeights(
            stemBN1d: try fuseBN("frontend.stem.bn1d"),
            stemConvWeight: try ten("frontend.stem.conv2d.weight"),
            stemBN2d: try fuseBN("frontend.stem.bn2d"),
            frontendBlocks: feBlocks,
            projWeight: try ten("frontend.linear.weight"),
            projBias: try ten("frontend.linear.bias"),
            transformerBlocks: txBlocks,
            postNormGamma: try ten("transformer_blocks.norm.gamma"),
            headWeight: try ten("task_heads.beat_downbeat_lin.weight"),
            headBias: try ten("task_heads.beat_downbeat_lin.bias")
        )
    }
}

// MARK: - BN Fusion

/// Fuse BatchNorm into scale + shift constants.
///
/// Inference: y = (x − mean) / sqrt(var + ε) × γ + β
/// Fused:     y = x × fusedScale + fusedShift
func fuseBeatThisBN(
    weight: [Float],
    bias: [Float],
    runningMean: [Float],
    runningVar: [Float],
    eps: Float = 1e-5
) -> BeatThisFusedBN {
    let cnt = weight.count
    var scale = [Float](repeating: 0, count: cnt)
    var shift = [Float](repeating: 0, count: cnt)

    var epsVec = [Float](repeating: eps, count: cnt)
    var varPlusEps = [Float](repeating: 0, count: cnt)
    vDSP_vadd(runningVar, 1, &epsVec, 1, &varPlusEps, 1, vDSP_Length(cnt))

    var sqrtV = [Float](repeating: 0, count: cnt)
    var cntI32 = Int32(cnt)
    vvsqrtf(&sqrtV, varPlusEps, &cntI32)

    var one: Float = 1.0
    var invStd = [Float](repeating: 0, count: cnt)
    vDSP_svdiv(&one, sqrtV, 1, &invStd, 1, vDSP_Length(cnt))

    vDSP_vmul(weight, 1, invStd, 1, &scale, 1, vDSP_Length(cnt))

    var negMeanScale = [Float](repeating: 0, count: cnt)
    vDSP_vmul(runningMean, 1, scale, 1, &negMeanScale, 1, vDSP_Length(cnt))
    // shift = bias - mean * scale  →  vDSP_vsub(a, b) = b - a
    vDSP_vsub(negMeanScale, 1, bias, 1, &shift, 1, vDSP_Length(cnt))

    return BeatThisFusedBN(scale: scale, shift: shift)
}

// MARK: - Conv Weight Rearrangement

/// Rearrange conv weight from PyTorch OIHW to MPSGraph HWIO.
///
/// PyTorch stores [outC, inC, kH, kW]; MPSGraph NHWC conv expects [kH, kW, inC, outC].
func rearrangeConvOIHW_to_HWIO(
    data: [Float],
    outC: Int, inC: Int, kH: Int, kW: Int
) -> [Float] {
    var out = [Float](repeating: 0, count: data.count)
    for outIdx in 0..<outC {
        for inIdx in 0..<inC {
            for kHIdx in 0..<kH {
                for kWIdx in 0..<kW {
                    let src = outIdx * (inC * kH * kW)
                        + inIdx * (kH * kW)
                        + kHIdx * kW
                        + kWIdx
                    let dst = kHIdx * (kW * inC * outC)
                        + kWIdx * (inC * outC)
                        + inIdx * outC
                        + outIdx
                    out[dst] = data[src]
                }
            }
        }
    }
    return out
}

// MARK: - I/O

private func loadBeatThisManifest() throws -> BeatThisManifest {
    guard let url = Bundle.module.url(
        forResource: "manifest",
        withExtension: "json",
        subdirectory: "Weights/beat_this"
    ) else {
        throw BeatThisWeightError.manifestNotFound
    }
    let data = try Data(contentsOf: url)
    do {
        return try JSONDecoder().decode(BeatThisManifest.self, from: data)
    } catch {
        throw BeatThisWeightError.manifestDecodeFailed(error.localizedDescription)
    }
}

private func loadBeatThisTensor(key: String, manifest: BeatThisManifest) throws -> [Float] {
    guard let entry = manifest.tensors[key] else {
        throw BeatThisWeightError.tensorNotFound(key)
    }
    guard let url = Bundle.module.url(
        forResource: entry.file,
        withExtension: nil,
        subdirectory: "Weights/beat_this"
    ) else {
        throw BeatThisWeightError.tensorFileMissing(entry.file)
    }
    let raw = try Data(contentsOf: url)
    guard raw.count == entry.bytes else {
        throw BeatThisWeightError.tensorSizeMismatch(
            key,
            expected: entry.bytes,
            got: raw.count
        )
    }
    let count = raw.count / MemoryLayout<Float>.size
    return raw.withUnsafeBytes { buf in
        Array(buf.bindMemory(to: Float.self).prefix(count))
    }
}
