// BeatThisModel+Graph — MPSGraph construction for Beat This! small0 encoder.
//
// S3: zero-weight initialisation. S4 replaces with checkpoint weights.
//
// Three macOS-14 workarounds:
//   RMSNorm  — manual: reductionSum(x²)/D + ε → √ → x/rms × γ  (see BeatThisModel+Ops)
//   SDPA     — manual: Q@K.T/√D → softmax → @V  (scaledDotProductAttention is macOS 15+)
//   RoPE     — precomputed (tMax, headDim/2) cos/sin constant tables

import Foundation
import MetalPerformanceShadersGraph

extension BeatThisModel {

    // MARK: - Build

    static func buildGraph() throws -> BeatThisGraphBundle {
        let graph = MPSGraph()

        let inputShape: [NSNumber] = [NSNumber(value: tMax), NSNumber(value: inputMels)]
        let input = graph.placeholder(shape: inputShape, dataType: .float32, name: "spectrogram")

        let (cosTable, sinTable) = buildRoPETables(graph: graph)
        var x = buildFrontendLinear(graph: graph, input: input)

        for idx in 0..<numBlocks {
            x = buildTransformerBlock(
                graph: graph,
                input: x,
                cosTable: cosTable,
                sinTable: sinTable,
                name: "blk\(idx)"
            )
        }

        let postGamma = makeOnesConst(graph, dim: embedDim, name: "pn_g")
        x = buildRMSNorm(graph: graph, input: x, gamma: postGamma, dim: embedDim, name: "pn")

        let headSpec = BeatLinearSpec(
            weight: makeZerosConst(
                graph,
                shape: [NSNumber(value: outputClasses), NSNumber(value: embedDim)],
                name: "head_w"
            ),
            bias: makeZerosConst(graph, shape: [NSNumber(value: outputClasses)], name: "head_b"),
            outDim: outputClasses
        )
        let headOut = buildLinear(graph: graph, input: x, spec: headSpec, name: "head")

        // beats = col0 + col1 (downbeats ⊂ beats), downbeats = col1
        let col0 = graph.sliceTensor(headOut, dimension: 1, start: 0, length: 1, name: "col0")
        let col1 = graph.sliceTensor(headOut, dimension: 1, start: 1, length: 1, name: "col1")
        let beatLogits = graph.squeeze(
            graph.addition(col0, col1, name: "beat_sum"),
            axis: 1,
            name: "beat_sq"
        )
        return BeatThisGraphBundle(
            graph: graph,
            inputTensor: input,
            beatOutputTensor: graph.sigmoid(with: beatLogits, name: "beat_sig"),
            downbeatOutputTensor: graph.sigmoid(
                with: graph.squeeze(col1, axis: 1, name: "db_sq"),
                name: "db_sig"
            )
        )
    }

    // MARK: - Frontend Placeholder

    private static func buildFrontendLinear(
        graph: MPSGraph,
        input: MPSGraphTensor
    ) -> MPSGraphTensor {
        let spec = BeatLinearSpec(
            weight: makeZerosConst(
                graph,
                shape: [NSNumber(value: embedDim), NSNumber(value: inputMels)],
                name: "fe_w"
            ),
            bias: makeZerosConst(graph, shape: [NSNumber(value: embedDim)], name: "fe_b"),
            outDim: embedDim
        )
        return buildLinear(graph: graph, input: input, spec: spec, name: "fe")
    }

    // MARK: - RoPE Tables

    private static func buildRoPETables(
        graph: MPSGraph
    ) -> (cos: MPSGraphTensor, sin: MPSGraphTensor) {
        let half = headDim / 2
        var cosVals = [Float](repeating: 0, count: tMax * half)
        var sinVals = [Float](repeating: 0, count: tMax * half)

        for pos in 0..<tMax {
            for i in 0..<half {
                let freq = 1.0 / pow(10000.0, Double(2 * i) / Double(headDim))
                let angle = Float(Double(pos) * freq)
                cosVals[pos * half + i] = Foundation.cos(angle)
                sinVals[pos * half + i] = Foundation.sin(angle)
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

    private static func buildTransformerBlock(
        graph: MPSGraph,
        input: MPSGraphTensor,
        cosTable: MPSGraphTensor,
        sinTable: MPSGraphTensor,
        name: String
    ) -> MPSGraphTensor {
        let attnOut = buildAttention(
            graph: graph,
            input: input,
            cosTable: cosTable,
            sinTable: sinTable,
            name: "\(name)a"
        )
        let res1 = graph.addition(input, attnOut, name: "\(name)r1")
        return graph.addition(
            res1,
            buildFFN(graph: graph, input: res1, name: "\(name)f"),
            name: "\(name)r2"
        )
    }

    // MARK: - Attention

    // swiftlint:disable:next function_body_length
    private static func buildAttention(
        graph: MPSGraph,
        input: MPSGraphTensor,
        cosTable: MPSGraphTensor,
        sinTable: MPSGraphTensor,
        name: String
    ) -> MPSGraphTensor {
        let inner = numHeads * headDim  // 128
        let qkvDim = 3 * inner          // 384

        let xNorm = buildRMSNorm(
            graph: graph,
            input: input,
            gamma: makeOnesConst(graph, dim: embedDim, name: "\(name)ng"),
            dim: embedDim,
            name: "\(name)n"
        )
        let qkvFlat = buildLinear(
            graph: graph,
            input: xNorm,
            spec: BeatLinearSpec(
                weight: makeZerosConst(
                    graph,
                    shape: [NSNumber(value: qkvDim), NSNumber(value: embedDim)],
                    name: "\(name)qw"
                ),
                bias: nil,
                outDim: qkvDim
            ),
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
            graph: graph, x: qHT, cosTable: cosTable, sinTable: sinTable, name: "\(name)qr"
        )
        let kRoPE = applyRoPE(
            graph: graph, x: kHT, cosTable: cosTable, sinTable: sinTable, name: "\(name)kr"
        )

        let scaleShape: [NSNumber] = [1]
        let kT = graph.transposeTensor(kRoPE, dimension: 1, withDimension: 2, name: "\(name)kT")
        let attn = graph.softMax(
            with: graph.multiplication(
                graph.matrixMultiplication(primary: qRoPE, secondary: kT, name: "\(name)sc"),
                graph.constant(1.0 / sqrt(Double(headDim)), shape: scaleShape, dataType: .float32),
                name: "\(name)scl"
            ),
            axis: 2,
            name: "\(name)sfx"
        )
        let attnOut = graph.matrixMultiplication(primary: attn, secondary: vHT, name: "\(name)av")

        let gatesSig = graph.sigmoid(
            with: buildLinear(
                graph: graph,
                input: xNorm,
                spec: BeatLinearSpec(
                    weight: makeZerosConst(
                        graph,
                        shape: [NSNumber(value: numHeads), NSNumber(value: embedDim)],
                        name: "\(name)gw"
                    ),
                    bias: makeZerosConst(graph, shape: [NSNumber(value: numHeads)], name: "\(name)gb"),
                    outDim: numHeads
                ),
                name: "\(name)g"
            ),
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
                weight: makeZerosConst(
                    graph,
                    shape: [NSNumber(value: embedDim), NSNumber(value: inner)],
                    name: "\(name)tow"
                ),
                bias: nil,
                outDim: embedDim
            ),
            name: "\(name)to"
        )
    }

    // MARK: - RoPE Application

    private static func applyRoPE(
        graph: MPSGraph,
        x: MPSGraphTensor,
        cosTable: MPSGraphTensor,
        sinTable: MPSGraphTensor,
        name: String
    ) -> MPSGraphTensor {
        let half = headDim / 2
        let x1 = graph.sliceTensor(x, dimension: 2, start: 0, length: half, name: "\(name)x1")
        let x2 = graph.sliceTensor(x, dimension: 2, start: half, length: half, name: "\(name)x2")
        let r1 = graph.subtraction(
            graph.multiplication(x1, cosTable, name: "\(name)x1c"),
            graph.multiplication(x2, sinTable, name: "\(name)x2s"),
            name: "\(name)r1"
        )
        let r2 = graph.addition(
            graph.multiplication(x1, sinTable, name: "\(name)x1s"),
            graph.multiplication(x2, cosTable, name: "\(name)x2c"),
            name: "\(name)r2"
        )
        return graph.concatTensors([r1, r2], dimension: 2, name: "\(name)cat")
    }

    // MARK: - FFN

    private static func buildFFN(
        graph: MPSGraph,
        input: MPSGraphTensor,
        name: String
    ) -> MPSGraphTensor {
        let xNorm = buildRMSNorm(
            graph: graph,
            input: input,
            gamma: makeOnesConst(graph, dim: embedDim, name: "\(name)ng"),
            dim: embedDim,
            name: "\(name)n"
        )
        let activated = buildGELU(
            graph: graph,
            input: buildLinear(
                graph: graph,
                input: xNorm,
                spec: BeatLinearSpec(
                    weight: makeZerosConst(
                        graph,
                        shape: [NSNumber(value: ffnDim), NSNumber(value: embedDim)],
                        name: "\(name)uw"
                    ),
                    bias: makeZerosConst(graph, shape: [NSNumber(value: ffnDim)], name: "\(name)ub"),
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
                weight: makeZerosConst(
                    graph,
                    shape: [NSNumber(value: embedDim), NSNumber(value: ffnDim)],
                    name: "\(name)dw"
                ),
                bias: makeZerosConst(graph, shape: [NSNumber(value: embedDim)], name: "\(name)db"),
                outDim: embedDim
            ),
            name: "\(name)dn"
        )
    }
}
