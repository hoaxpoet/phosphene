// BeatThisModel+Graph — MPSGraph construction for Beat This! small0 encoder.
//
// S4: real weights loaded from checkpoint.
//
// Three macOS-14 workarounds:
//   RMSNorm  — manual: reductionSum(x²)/D + ε → √ → x/rms × γ  (see BeatThisModel+Ops)
//   SDPA     — manual: Q@K.T/√D → softmax → @V  (scaledDotProductAttention is macOS 15+)
//   RoPE     — precomputed (tMax, headDim/2) cos/sin constant tables

// swiftlint:disable file_length

import Foundation
import MetalPerformanceShadersGraph

extension BeatThisModel {

    // MARK: - Build

    // swiftlint:disable:next function_body_length
    static func buildGraph(weights: BeatThisWeights) throws -> BeatThisGraphBundle {
        let graph = MPSGraph()

        let inputShape: [NSNumber] = [NSNumber(value: tMax), NSNumber(value: inputMels)]
        let input = graph.placeholder(
            shape: inputShape,
            dataType: .float32,
            name: "spectrogram"
        )

        let (cosTable, sinTable) = buildRoPETables(graph: graph)

        var intermediates: [String: MPSGraphTensor] = [:]

        var x = buildFrontend(
            graph: graph,
            input: input,
            weights: weights,
            cosTable: cosTable,
            sinTable: sinTable,
            name: "fe",
            intermediates: &intermediates
        )
        intermediates["frontend.linear"] = x

        for idx in 0..<numBlocks {
            x = buildTransformerBlock(
                graph: graph,
                input: x,
                cosTable: cosTable,
                sinTable: sinTable,
                blkWeights: weights.transformerBlocks[idx],
                name: "blk\(idx)"
            )
            intermediates["transformer.\(idx)"] = x
        }

        let postGamma = makeConst(
            graph,
            weights.postNormGamma,
            shape: [1, NSNumber(value: embedDim)],
            name: "pn_g"
        )
        x = buildRMSNorm(
            graph: graph,
            input: x,
            gamma: postGamma,
            dim: embedDim,
            name: "pn"
        )
        intermediates["transformer.norm"] = x

        let headSpec = BeatLinearSpec(
            weight: makeConst(
                graph,
                weights.headWeight,
                shape: [NSNumber(value: outputClasses), NSNumber(value: embedDim)],
                name: "head_w"
            ),
            bias: makeConst(
                graph,
                weights.headBias,
                shape: [NSNumber(value: outputClasses)],
                name: "head_b"
            ),
            outDim: outputClasses
        )
        let headOut = buildLinear(graph: graph, input: x, spec: headSpec, name: "head")
        intermediates["head.linear"] = headOut

        let col0 = graph.sliceTensor(headOut, dimension: 1, start: 0, length: 1, name: "col0")
        let col1 = graph.sliceTensor(headOut, dimension: 1, start: 1, length: 1, name: "col1")
        let beatLogits = graph.squeeze(
            graph.addition(col0, col1, name: "beat_sum"),
            axis: 1,
            name: "beat_sq"
        )
        intermediates["output.beat_logits"] = beatLogits
        let beatSig = graph.sigmoid(with: beatLogits, name: "beat_sig")
        intermediates["output.beat_sigmoid"] = beatSig
        return BeatThisGraphBundle(
            graph: graph,
            inputTensor: input,
            beatOutputTensor: beatSig,
            downbeatOutputTensor: graph.sigmoid(
                with: graph.squeeze(col1, axis: 1, name: "db_sq"),
                name: "db_sig"
            ),
            intermediates: intermediates
        )
    }

    // MARK: - RoPE Tables

    private static func buildRoPETables(
        graph: MPSGraph
    ) -> (cos: MPSGraphTensor, sin: MPSGraphTensor) {
        let half = headDim / 2
        var cosVals = [Float](repeating: 0, count: tMax * half)
        var sinVals = [Float](repeating: 0, count: tMax * half)

        for pos in 0..<tMax {
            for idx in 0..<half {
                let freq = 1.0 / pow(10000.0, Double(2 * idx) / Double(headDim))
                let angle = Float(Double(pos) * freq)
                cosVals[pos * half + idx] = Foundation.cos(angle)
                sinVals[pos * half + idx] = Foundation.sin(angle)
            }
        }

        let shape: [NSNumber] = [1, NSNumber(value: tMax), NSNumber(value: half)]
        let cosT = graph.constant(
            Data(bytes: cosVals, count: cosVals.count * MemoryLayout<Float>.size),
            shape: shape,
            dataType: .float32
        )
        let sinT = graph.constant(
            Data(bytes: sinVals, count: sinVals.count * MemoryLayout<Float>.size),
            shape: shape,
            dataType: .float32
        )
        return (cosT, sinT)
    }

    // MARK: - Transformer Block

    // swiftlint:disable:next function_parameter_count
    private static func buildTransformerBlock(
        graph: MPSGraph,
        input: MPSGraphTensor,
        cosTable: MPSGraphTensor,
        sinTable: MPSGraphTensor,
        blkWeights: BeatThisTransformerBlockWeights,
        name: String
    ) -> MPSGraphTensor {
        let attnOut = buildAttention(
            graph: graph,
            input: input,
            cosTable: cosTable,
            sinTable: sinTable,
            blkWeights: blkWeights.attn,
            name: "\(name)a"
        )
        let res1 = graph.addition(input, attnOut, name: "\(name)r1")
        return graph.addition(
            res1,
            buildFFN(
                graph: graph,
                input: res1,
                blkWeights: blkWeights.ffn,
                name: "\(name)f"
            ),
            name: "\(name)r2"
        )
    }

    // MARK: - Transformer Attention

    // swiftlint:disable:next function_body_length function_parameter_count
    private static func buildAttention(
        graph: MPSGraph,
        input: MPSGraphTensor,
        cosTable: MPSGraphTensor,
        sinTable: MPSGraphTensor,
        blkWeights: BeatThisAttnWeights,
        name: String
    ) -> MPSGraphTensor {
        let inner = numHeads * headDim
        let qkvDim = 3 * inner

        let gamma = makeConst(
            graph,
            blkWeights.normGamma,
            shape: [1, NSNumber(value: embedDim)],
            name: "\(name)ng"
        )
        let xNorm = buildRMSNorm(
            graph: graph,
            input: input,
            gamma: gamma,
            dim: embedDim,
            name: "\(name)n"
        )

        let qkvSpec = BeatLinearSpec(
            weight: makeConst(
                graph,
                blkWeights.qkvWeight,
                shape: [NSNumber(value: qkvDim), NSNumber(value: embedDim)],
                name: "\(name)qw"
            ),
            bias: nil,
            outDim: qkvDim
        )
        let qkvFlat = buildLinear(
            graph: graph,
            input: xNorm,
            spec: qkvSpec,
            name: "\(name)qkv"
        )

        let qkvShape: [NSNumber] = [
            NSNumber(value: tMax), NSNumber(value: 3),
            NSNumber(value: numHeads), NSNumber(value: headDim)
        ]
        let qkv4d = graph.reshape(qkvFlat, shape: qkvShape, name: "\(name)4d")
        let hdShape: [NSNumber] = [
            NSNumber(value: tMax), NSNumber(value: numHeads), NSNumber(value: headDim)
        ]
        let q3d = graph.reshape(
            graph.sliceTensor(qkv4d, dimension: 1, start: 0, length: 1, name: "\(name)qs"),
            shape: hdShape,
            name: "\(name)q3"
        )
        let k3d = graph.reshape(
            graph.sliceTensor(qkv4d, dimension: 1, start: 1, length: 1, name: "\(name)ks"),
            shape: hdShape,
            name: "\(name)k3"
        )
        let v3d = graph.reshape(
            graph.sliceTensor(qkv4d, dimension: 1, start: 2, length: 1, name: "\(name)vs"),
            shape: hdShape,
            name: "\(name)v3"
        )

        let qHT = graph.transposeTensor(q3d, dimension: 0, withDimension: 1, name: "\(name)qHT")
        let kHT = graph.transposeTensor(k3d, dimension: 0, withDimension: 1, name: "\(name)kHT")
        let vHT = graph.transposeTensor(v3d, dimension: 0, withDimension: 1, name: "\(name)vHT")

        let qRoPE = applyRoPE(
            graph: graph,
            x: qHT,
            cosTable: cosTable,
            sinTable: sinTable,
            name: "\(name)qr"
        )
        let kRoPE = applyRoPE(
            graph: graph,
            x: kHT,
            cosTable: cosTable,
            sinTable: sinTable,
            name: "\(name)kr"
        )

        let scaleConst = graph.constant(
            1.0 / sqrt(Double(headDim)),
            shape: [1],
            dataType: .float32
        )
        let kT = graph.transposeTensor(kRoPE, dimension: 1, withDimension: 2, name: "\(name)kT")
        let attn = graph.softMax(
            with: graph.multiplication(
                graph.matrixMultiplication(primary: qRoPE, secondary: kT, name: "\(name)sc"),
                scaleConst,
                name: "\(name)scl"
            ),
            axis: 2,
            name: "\(name)sfx"
        )
        let attnOut = graph.matrixMultiplication(primary: attn, secondary: vHT, name: "\(name)av")

        let gateSpec = BeatLinearSpec(
            weight: makeConst(
                graph,
                blkWeights.gateWeight,
                shape: [NSNumber(value: numHeads), NSNumber(value: embedDim)],
                name: "\(name)gw"
            ),
            bias: makeConst(
                graph,
                blkWeights.gateBias,
                shape: [NSNumber(value: numHeads)],
                name: "\(name)gb"
            ),
            outDim: numHeads
        )
        let gatesSig = graph.sigmoid(
            with: buildLinear(graph: graph, input: xNorm, spec: gateSpec, name: "\(name)g"),
            name: "\(name)gs"
        )
        let gatesExp = graph.expandDims(
            graph.transposeTensor(gatesSig, dimension: 0, withDimension: 1, name: "\(name)gHT"),
            axis: 2,
            name: "\(name)gEx"
        )
        let outFlat = graph.reshape(
            graph.transposeTensor(
                graph.multiplication(attnOut, gatesExp, name: "\(name)gated"),
                dimension: 0,
                withDimension: 1,
                name: "\(name)oT"
            ),
            shape: [NSNumber(value: tMax), NSNumber(value: inner)],
            name: "\(name)oF"
        )
        return buildLinear(
            graph: graph,
            input: outFlat,
            spec: BeatLinearSpec(
                weight: makeConst(
                    graph,
                    blkWeights.outWeight,
                    shape: [NSNumber(value: embedDim), NSNumber(value: inner)],
                    name: "\(name)tow"
                ),
                bias: nil,
                outDim: embedDim
            ),
            name: "\(name)to"
        )
    }

    // MARK: - RoPE Application (transformer blocks)

    // Apply RoPE to [B, S, headDim] using cos/sin [1, S, headDim/2].
    // Matches `rotary_embedding_torch.rotate_half` paired-adjacent semantics
    // — same bug as the 4D version in BeatThisModel+Frontend.swift.
    private static func applyRoPE(
        graph: MPSGraph,
        x: MPSGraphTensor,
        cosTable: MPSGraphTensor,
        sinTable: MPSGraphTensor,
        name: String
    ) -> MPSGraphTensor {
        // swiftlint:disable force_unwrapping
        let xShape = x.shape!
        // swiftlint:enable force_unwrapping
        let halfD = headDim / 2
        // Reshape [B, S, D] → [B, S, D/2, 2]
        let pairedShape: [NSNumber] = [
            xShape[0], xShape[1],
            NSNumber(value: halfD), 2
        ]
        let xPaired = graph.reshape(x, shape: pairedShape, name: "\(name)pair")
        let evenSlice = graph.sliceTensor(
            xPaired, dimension: 3, start: 0, length: 1, name: "\(name)ev"
        )
        let xEven = graph.squeeze(evenSlice, axis: 3, name: "\(name)evSq")
        let oddSlice = graph.sliceTensor(
            xPaired, dimension: 3, start: 1, length: 1, name: "\(name)od"
        )
        let xOdd = graph.squeeze(oddSlice, axis: 3, name: "\(name)odSq")
        let rEven = graph.subtraction(
            graph.multiplication(xEven, cosTable, name: "\(name)evC"),
            graph.multiplication(xOdd, sinTable, name: "\(name)odS"),
            name: "\(name)rEv"
        )
        let rOdd = graph.addition(
            graph.multiplication(xEven, sinTable, name: "\(name)evS"),
            graph.multiplication(xOdd, cosTable, name: "\(name)odC"),
            name: "\(name)rOd"
        )
        let rEvenE = graph.expandDims(rEven, axis: 3, name: "\(name)rEvEx")
        let rOddE = graph.expandDims(rOdd, axis: 3, name: "\(name)rOdEx")
        let rPaired = graph.concatTensors([rEvenE, rOddE], dimension: 3, name: "\(name)pCat")
        return graph.reshape(rPaired, shape: xShape, name: "\(name)merge")
    }

    // MARK: - Transformer FFN

    private static func buildFFN(
        graph: MPSGraph,
        input: MPSGraphTensor,
        blkWeights: BeatThisFFNWeights,
        name: String
    ) -> MPSGraphTensor {
        let gamma = makeConst(
            graph,
            blkWeights.normGamma,
            shape: [1, NSNumber(value: embedDim)],
            name: "\(name)ng"
        )
        let xNorm = buildRMSNorm(
            graph: graph,
            input: input,
            gamma: gamma,
            dim: embedDim,
            name: "\(name)n"
        )
        let activated = buildGELU(
            graph: graph,
            input: buildLinear(
                graph: graph,
                input: xNorm,
                spec: BeatLinearSpec(
                    weight: makeConst(
                        graph,
                        blkWeights.upWeight,
                        shape: [NSNumber(value: ffnDim), NSNumber(value: embedDim)],
                        name: "\(name)uw"
                    ),
                    bias: makeConst(
                        graph,
                        blkWeights.upBias,
                        shape: [NSNumber(value: ffnDim)],
                        name: "\(name)ub"
                    ),
                    outDim: ffnDim
                ),
                name: "\(name)up"
            ),
            name: "\(name)gelu"
        )
        return buildLinear(
            graph: graph,
            input: activated,
            spec: BeatLinearSpec(
                weight: makeConst(
                    graph,
                    blkWeights.downWeight,
                    shape: [NSNumber(value: embedDim), NSNumber(value: ffnDim)],
                    name: "\(name)dw"
                ),
                bias: makeConst(
                    graph,
                    blkWeights.downBias,
                    shape: [NSNumber(value: embedDim)],
                    name: "\(name)db"
                ),
                outDim: embedDim
            ),
            name: "\(name)dn"
        )
    }
}
