// BeatThisModel+Frontend — PartialFTTransformer frontend for Beat This! small0.
//
// Implements:
//   BN1d → Conv2d(4×3) stem
//   3× PartialFTTransformerBlock → BN2d → GELU → Conv2d(2×3) downsampling
//   rearrange + Linear projection → (tMax, 128)
//
// All tensors use MPSGraph NHWC layout: [batch, H_freq, W_time, C_channels].
// Conv weights rearranged OIHW→HWIO at graph build time (not a graph op).

// swiftlint:disable file_length

import Foundation
import MetalPerformanceShadersGraph

extension BeatThisModel {

    // MARK: - Frontend Entry Point

    // Build frontend: [tMax, 128] spectrogram → [tMax, 128] embeddings.
    // swiftlint:disable:next function_parameter_count
    static func buildFrontend(
        graph: MPSGraph,
        input: MPSGraphTensor,
        weights: BeatThisWeights,
        cosTable: MPSGraphTensor,
        sinTable: MPSGraphTensor,
        name: String,
        intermediates: inout [String: MPSGraphTensor]
    ) -> MPSGraphTensor {
        var x = buildStemConv(
            graph: graph,
            input: input,
            weights: weights,
            name: "\(name)s",
            intermediates: &intermediates
        )

        // (inDim, freqDim) after stem: (32, 32) → (64, 16) → (128, 8)
        let blockDims: [(Int, Int)] = [(32, 32), (64, 16), (128, 8)]
        for (idx, (inDim, freqDim)) in blockDims.enumerated() {
            x = buildPartialFTBlock(
                graph: graph,
                input: x,
                blkWeights: weights.frontendBlocks[idx],
                inDim: inDim,
                freqDim: freqDim,
                cosTable: cosTable,
                sinTable: sinTable,
                name: "\(name)b\(idx)",
                blockIdx: idx,
                intermediates: &intermediates
            )
        }

        // After 3 blocks: [1, 4_freq, tMax, 256_channels]
        // Rearrange "b c f t -> b t (c f)":
        //   Step 1: transpose H(freq)↔W(time): [1, tMax, 4, 256]
        //   Step 2: transpose dim2↔dim3: [1, tMax, 256, 4]
        //   Step 3: reshape → [1, tMax, 1024]  (c varies slow, f fast)
        let t1 = graph.transposeTensor(x, dimension: 1, withDimension: 2, name: "\(name)rT1")
        let t2 = graph.transposeTensor(t1, dimension: 2, withDimension: 3, name: "\(name)rT2")
        let flat = graph.reshape(
            t2,
            shape: [1, NSNumber(value: tMax), 1024],
            name: "\(name)rFl"
        )
        let squeezed = graph.squeeze(flat, axis: 0, name: "\(name)rSq")

        let projSpec = BeatLinearSpec(
            weight: makeConst(
                graph,
                weights.projWeight,
                shape: [NSNumber(value: embedDim), 1024],
                name: "\(name)pw"
            ),
            bias: makeConst(
                graph,
                weights.projBias,
                shape: [NSNumber(value: embedDim)],
                name: "\(name)pb"
            ),
            outDim: embedDim
        )
        return buildLinear(graph: graph, input: squeezed, spec: projSpec, name: "\(name)pr")
    }

    // MARK: - Stem Conv

    // BN1d → reshape → Conv2d(4×3) → BN2d → GELU.
    // Input [tMax, 128] → Output [1, 32_freq, tMax, 32_channels].
    // swiftlint:disable:next function_body_length
    private static func buildStemConv(
        graph: MPSGraph,
        input: MPSGraphTensor,
        weights: BeatThisWeights,
        name: String,
        intermediates: inout [String: MPSGraphTensor]
    ) -> MPSGraphTensor {
        // BN1d: [tMax, 128] × scale[1,128] + shift[1,128]
        let bn1Scale = makeConst(
            graph,
            weights.stemBN1d.scale,
            shape: [1, NSNumber(value: inputMels)],
            name: "\(name)1sc"
        )
        let bn1Shift = makeConst(
            graph,
            weights.stemBN1d.shift,
            shape: [1, NSNumber(value: inputMels)],
            name: "\(name)1sh"
        )
        let normed = graph.addition(
            graph.multiplication(input, bn1Scale, name: "\(name)1mul"),
            bn1Shift,
            name: "\(name)1add"
        )
        intermediates["stem.bn1d"] = normed

        // `normed` shape is [T, F] (T outer / time-major). We need NHWC
        // [B=1, H=F, W=T, C=1] for the 2D conv. A direct reshape would
        // reinterpret the bytes wrong (giving the conv a scrambled mel
        // spectrogram and producing flat sub-threshold output downstream
        // — DSP.2 S8 root cause). Transpose T↔F first, THEN reshape.
        let normedFT = graph.transposeTensor(
            normed, dimension: 0, withDimension: 1, name: "\(name)tr"
        )
        // `normedFT` shape is now [F, T] in row-major. Reshape to NHWC
        // [B=1, H=F, W=T, C=1].
        let xNHWC = graph.reshape(
            normedFT,
            shape: [1, NSNumber(value: inputMels), NSNumber(value: tMax), 1],
            name: "\(name)rs"
        )

        // Conv2d: kernel(kH=4,kW=3), stride(sY=4,sX=1), pad(top=0,bot=0,left=1,right=1).
        let convW = rearrangeConvOIHW_to_HWIO(
            data: weights.stemConvWeight, outC: 32, inC: 1, kH: 4, kW: 3
        )
        let convConst = makeConst(graph, convW, shape: [4, 3, 1, 32], name: "\(name)cw")
        // swiftlint:disable force_unwrapping
        let convDesc = MPSGraphConvolution2DOpDescriptor(
            strideInX: 1,
            strideInY: 4,
            dilationRateInX: 1,
            dilationRateInY: 1,
            groups: 1,
            paddingLeft: 1,
            paddingRight: 1,
            paddingTop: 0,
            paddingBottom: 0,
            paddingStyle: .explicit,
            dataLayout: .NHWC,
            weightsLayout: .HWIO
        )!
        // swiftlint:enable force_unwrapping
        let convOut = graph.convolution2D(
            xNHWC,
            weights: convConst,
            descriptor: convDesc,
            name: "\(name)cv"
        )
        intermediates["stem.conv2d"] = convOut

        // BN2d: [1, 1, 1, 32] broadcast
        let bn2Scale = makeConst(
            graph,
            weights.stemBN2d.scale,
            shape: [1, 1, 1, 32],
            name: "\(name)2sc"
        )
        let bn2Shift = makeConst(
            graph,
            weights.stemBN2d.shift,
            shape: [1, 1, 1, 32],
            name: "\(name)2sh"
        )
        let bn2Out = graph.addition(
            graph.multiplication(convOut, bn2Scale, name: "\(name)2mul"),
            bn2Shift,
            name: "\(name)2add"
        )
        intermediates["stem.bn2d"] = bn2Out
        let stemOut = buildGELU(graph: graph, input: bn2Out, name: "\(name)ge")
        intermediates["stem.activation"] = stemOut
        return stemOut
    }

    // MARK: - PartialFT Block

    // PartialFTTransformer + BN2d + GELU + Conv2d(2×3) downsampling.
    // Input [1, freqDim, tMax, inDim] → Output [1, freqDim/2, tMax, inDim*2].
    // swiftlint:disable:next function_parameter_count function_body_length
    private static func buildPartialFTBlock(
        graph: MPSGraph,
        input: MPSGraphTensor,
        blkWeights: BeatThisFrontendBlockWeights,
        inDim: Int,
        freqDim: Int,
        cosTable: MPSGraphTensor,
        sinTable: MPSGraphTensor,
        name: String,
        blockIdx: Int,
        intermediates: inout [String: MPSGraphTensor]
    ) -> MPSGraphTensor {
        let heads = inDim / headDim

        // F-direction: batch over T, sequence over F
        // [1, freqDim, tMax, inDim] → transpose H↔W → [1, tMax, freqDim, inDim]
        //                           → reshape → [tMax, freqDim, inDim]
        let xFT = graph.transposeTensor(input, dimension: 1, withDimension: 2, name: "\(name)aFT")
        let xF = graph.reshape(
            xFT,
            shape: [NSNumber(value: tMax), NSNumber(value: freqDim), NSNumber(value: inDim)],
            name: "\(name)aFrs"
        )
        let cosFSlice = graph.sliceTensor(cosTable, dimension: 1, start: 0, length: freqDim, name: "\(name)aFcos")
        let sinFSlice = graph.sliceTensor(sinTable, dimension: 1, start: 0, length: freqDim, name: "\(name)aFsin")
        let attnFOut = buildBatchedAttn(
            graph: graph,
            input: xF,
            weights: blkWeights.attnF,
            heads: heads,
            seqLen: freqDim,
            dim: inDim,
            cosTable: cosFSlice,
            sinTable: sinFSlice,
            name: "\(name)aF"
        )
        let xFAttn = graph.addition(xF, attnFOut, name: "\(name)aFr")
        let ffFOut = buildBatchedFFN(
            graph: graph,
            input: xFAttn,
            weights: blkWeights.ffF,
            dim: inDim,
            name: "\(name)fF"
        )
        let xFFF = graph.addition(xFAttn, ffFOut, name: "\(name)fFr")
        // Restore [tMax, freqDim, inDim] → transpose → [freqDim, tMax, inDim]
        //       → [1, freqDim, tMax, inDim]
        let xFrT = graph.transposeTensor(xFFF, dimension: 0, withDimension: 1, name: "\(name)aFrT")
        var x = graph.reshape(
            xFrT,
            shape: [1, NSNumber(value: freqDim), NSNumber(value: tMax), NSNumber(value: inDim)],
            name: "\(name)aFrrs"
        )

        // T-direction: batch over F, sequence over T
        // [1, freqDim, tMax, inDim] → reshape → [freqDim, tMax, inDim]
        let xT = graph.reshape(
            x,
            shape: [NSNumber(value: freqDim), NSNumber(value: tMax), NSNumber(value: inDim)],
            name: "\(name)aTrs"
        )
        let attnTOut = buildBatchedAttn(
            graph: graph,
            input: xT,
            weights: blkWeights.attnT,
            heads: heads,
            seqLen: tMax,
            dim: inDim,
            cosTable: cosTable,
            sinTable: sinTable,
            name: "\(name)aT"
        )
        let xTAttn = graph.addition(xT, attnTOut, name: "\(name)aTr")
        let ffTOut = buildBatchedFFN(
            graph: graph,
            input: xTAttn,
            weights: blkWeights.ffT,
            dim: inDim,
            name: "\(name)fT"
        )
        let xTFF = graph.addition(xTAttn, ffTOut, name: "\(name)fTr")
        x = graph.reshape(
            xTFF,
            shape: [1, NSNumber(value: freqDim), NSNumber(value: tMax), NSNumber(value: inDim)],
            name: "\(name)aTrrs"
        )
        intermediates["frontend.blocks.\(blockIdx).partial"] = x

        // PyTorch frontend block ordering: partial → conv2d(in→out) → norm(out_dim) → GELU.
        // Earlier Swift port had the norm BEFORE the conv with the wrong shape
        // ([1,1,1,inDim] truncating the loaded out_dim weights), which produced a
        // structurally degraded forward pass — max sigmoid 0.29 vs Python 1.0
        // on love_rehab. The fix is purely the order + the shape.

        let outDim = inDim * 2

        // Downsampling Conv2d: kernel(kH=2,kW=3), stride(sY=2,sX=1), pad(top=0,bot=0,L=1,R=1).
        let dcW = rearrangeConvOIHW_to_HWIO(data: blkWeights.convWeight, outC: outDim, inC: inDim, kH: 2, kW: 3)
        let dcConst = makeConst(
            graph,
            dcW,
            shape: [2, 3, NSNumber(value: inDim), NSNumber(value: outDim)],
            name: "\(name)dw"
        )
        // swiftlint:disable force_unwrapping
        let dcDesc = MPSGraphConvolution2DOpDescriptor(
            strideInX: 1,
            strideInY: 2,
            dilationRateInX: 1,
            dilationRateInY: 1,
            groups: 1,
            paddingLeft: 1,
            paddingRight: 1,
            paddingTop: 0,
            paddingBottom: 0,
            paddingStyle: .explicit,
            dataLayout: .NHWC,
            weightsLayout: .HWIO
        )!
        // swiftlint:enable force_unwrapping
        let dcOut = graph.convolution2D(
            x,
            weights: dcConst,
            descriptor: dcDesc,
            name: "\(name)dc"
        )
        intermediates["frontend.blocks.\(blockIdx).conv2d"] = dcOut

        // BN2d norm (blocks.N.norm, fused) on the conv OUTPUT (outDim channels).
        let normS = makeConst(
            graph,
            blkWeights.norm.scale,
            shape: [1, 1, 1, NSNumber(value: outDim)],
            name: "\(name)ns"
        )
        let normSh = makeConst(
            graph,
            blkWeights.norm.shift,
            shape: [1, 1, 1, NSNumber(value: outDim)],
            name: "\(name)nsh"
        )
        let normed = graph.addition(
            graph.multiplication(dcOut, normS, name: "\(name)nmul"),
            normSh,
            name: "\(name)nadd"
        )
        intermediates["frontend.blocks.\(blockIdx).norm"] = normed
        let blockOut = buildGELU(graph: graph, input: normed, name: "\(name)dge")
        intermediates["frontend.blocks.\(blockIdx).activation"] = blockOut
        return blockOut
    }

    // MARK: - Batched Attention (frontend PartialFT)

    // Multi-head gated RoPE attention over [batchSz, seqLen, dim] → [batchSz, seqLen, dim].
    // swiftlint:disable:next function_parameter_count function_body_length
    private static func buildBatchedAttn(
        graph: MPSGraph,
        input: MPSGraphTensor,
        weights: BeatThisAttnWeights,
        heads: Int,
        seqLen: Int,
        dim: Int,
        cosTable: MPSGraphTensor,
        sinTable: MPSGraphTensor,
        name: String
    ) -> MPSGraphTensor {
        let inner = heads * headDim

        let gamma = makeConst(
            graph,
            weights.normGamma,
            shape: [1, 1, NSNumber(value: dim)],
            name: "\(name)ng"
        )
        let xNorm = buildRMSNorm(
            graph: graph,
            input: input,
            gamma: gamma,
            dim: dim,
            normAxis: 2,
            name: "\(name)n"
        )

        // QKV projection [B, S, dim] → [B, S, 3·inner]
        let qkvSpec = BeatLinearSpec(
            weight: makeConst(
                graph,
                weights.qkvWeight,
                shape: [NSNumber(value: 3 * inner), NSNumber(value: dim)],
                name: "\(name)qw"
            ),
            bias: nil,
            outDim: 3 * inner
        )
        let qkvFlat = buildLinear(
            graph: graph,
            input: xNorm,
            spec: qkvSpec,
            name: "\(name)qkv"
        )

        // Capture dynamic batch dimension (varies: tMax in T-attn, freqDim in F-attn)
        // swiftlint:disable:next force_unwrapping
        let batchDim = input.shape![0]
        let qkvShape: [NSNumber] = [
            batchDim,
            NSNumber(value: seqLen), 3,
            NSNumber(value: heads), NSNumber(value: headDim)
        ]
        let qkv5 = graph.reshape(qkvFlat, shape: qkvShape, name: "\(name)5d")
        let hdShape: [NSNumber] = [
            batchDim,
            NSNumber(value: seqLen),
            NSNumber(value: heads),
            NSNumber(value: headDim)
        ]
        let q4 = graph.reshape(
            graph.sliceTensor(qkv5, dimension: 2, start: 0, length: 1, name: "\(name)qs"),
            shape: hdShape,
            name: "\(name)q4"
        )
        let k4 = graph.reshape(
            graph.sliceTensor(qkv5, dimension: 2, start: 1, length: 1, name: "\(name)ks"),
            shape: hdShape,
            name: "\(name)k4"
        )
        let v4 = graph.reshape(
            graph.sliceTensor(qkv5, dimension: 2, start: 2, length: 1, name: "\(name)vs"),
            shape: hdShape,
            name: "\(name)v4"
        )

        // Transpose to [B, H, S, D]
        let qHT = graph.transposeTensor(q4, dimension: 1, withDimension: 2, name: "\(name)qT")
        let kHT = graph.transposeTensor(k4, dimension: 1, withDimension: 2, name: "\(name)kT")
        let vHT = graph.transposeTensor(v4, dimension: 1, withDimension: 2, name: "\(name)vT")

        // RoPE: expand cosTable [1, S, Hd/2] → [1, 1, S, Hd/2]
        let cosE = graph.expandDims(cosTable, axis: 0, name: "\(name)cosEx")
        let sinE = graph.expandDims(sinTable, axis: 0, name: "\(name)sinEx")
        let qRoPE = applyRoPE4D(
            graph: graph,
            x: qHT,
            cosTable: cosE,
            sinTable: sinE,
            name: "\(name)qrp"
        )
        let kRoPE = applyRoPE4D(
            graph: graph,
            x: kHT,
            cosTable: cosE,
            sinTable: sinE,
            name: "\(name)krp"
        )

        // Scaled dot-product: Q@K.T / sqrt(D) → softmax → @V
        let scaleConst = graph.constant(
            1.0 / sqrt(Double(headDim)),
            shape: [1],
            dataType: .float32
        )
        let kTransp = graph.transposeTensor(kRoPE, dimension: 2, withDimension: 3, name: "\(name)kTr")
        let attnW = graph.softMax(
            with: graph.multiplication(
                graph.matrixMultiplication(primary: qRoPE, secondary: kTransp, name: "\(name)sc"),
                scaleConst,
                name: "\(name)scl"
            ),
            axis: 3,
            name: "\(name)sfx"
        )
        let attnOut = graph.matrixMultiplication(primary: attnW, secondary: vHT, name: "\(name)av")

        // Gating: Linear(dim → H) → sigmoid → expand → scale
        let gateSpec = BeatLinearSpec(
            weight: makeConst(
                graph,
                weights.gateWeight,
                shape: [NSNumber(value: heads), NSNumber(value: dim)],
                name: "\(name)gw"
            ),
            bias: makeConst(
                graph,
                weights.gateBias,
                shape: [NSNumber(value: heads)],
                name: "\(name)gb"
            ),
            outDim: heads
        )
        let gateSig = graph.sigmoid(
            with: buildLinear(graph: graph, input: xNorm, spec: gateSpec, name: "\(name)g"),
            name: "\(name)gs"
        )
        // [B, S, H] → transpose → [B, H, S] → expand → [B, H, S, 1]
        let gateT = graph.transposeTensor(gateSig, dimension: 1, withDimension: 2, name: "\(name)gHT")
        let gateEx = graph.expandDims(gateT, axis: 3, name: "\(name)gEx")
        let gated = graph.multiplication(attnOut, gateEx, name: "\(name)gated")

        // Merge heads: [B, H, S, D] → [B, S, H, D] → [B, S, H*D]
        let gatedT = graph.transposeTensor(gated, dimension: 1, withDimension: 2, name: "\(name)oT")
        let outFlat = graph.reshape(
            gatedT,
            shape: [batchDim, NSNumber(value: seqLen), NSNumber(value: inner)],
            name: "\(name)oF"
        )

        // Output projection
        let outSpec = BeatLinearSpec(
            weight: makeConst(
                graph,
                weights.outWeight,
                shape: [NSNumber(value: dim), NSNumber(value: inner)],
                name: "\(name)ow"
            ),
            bias: nil,
            outDim: dim
        )
        return buildLinear(graph: graph, input: outFlat, spec: outSpec, name: "\(name)to")
    }

    // MARK: - Batched FFN (frontend PartialFT)

    // RMSNorm + up-proj + GELU + down-proj over [B, S, dim] → [B, S, dim].
    private static func buildBatchedFFN(
        graph: MPSGraph,
        input: MPSGraphTensor,
        weights: BeatThisFFNWeights,
        dim: Int,
        name: String
    ) -> MPSGraphTensor {
        let ffDim = weights.upBias.count
        let gamma = makeConst(
            graph,
            weights.normGamma,
            shape: [1, 1, NSNumber(value: dim)],
            name: "\(name)ng"
        )
        let xNorm = buildRMSNorm(
            graph: graph,
            input: input,
            gamma: gamma,
            dim: dim,
            normAxis: 2,
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
                        weights.upWeight,
                        shape: [NSNumber(value: ffDim), NSNumber(value: dim)],
                        name: "\(name)uw"
                    ),
                    bias: makeConst(
                        graph,
                        weights.upBias,
                        shape: [NSNumber(value: ffDim)],
                        name: "\(name)ub"
                    ),
                    outDim: ffDim
                ),
                name: "\(name)up"
            ),
            name: "\(name)ge"
        )
        return buildLinear(
            graph: graph,
            input: activated,
            spec: BeatLinearSpec(
                weight: makeConst(
                    graph,
                    weights.downWeight,
                    shape: [NSNumber(value: dim), NSNumber(value: ffDim)],
                    name: "\(name)dw"
                ),
                bias: makeConst(
                    graph,
                    weights.downBias,
                    shape: [NSNumber(value: dim)],
                    name: "\(name)db"
                ),
                outDim: dim
            ),
            name: "\(name)dn"
        )
    }

    // MARK: - 4D RoPE (frontend batched attention)

    // Apply RoPE to [B, H, S, Hd] using cos/sin [1, 1, S, Hd/2].
    private static func applyRoPE4D(
        graph: MPSGraph,
        x: MPSGraphTensor,
        cosTable: MPSGraphTensor,
        sinTable: MPSGraphTensor,
        name: String
    ) -> MPSGraphTensor {
        let halfD = headDim / 2
        let x1 = graph.sliceTensor(x, dimension: 3, start: 0, length: halfD, name: "\(name)x1")
        let x2 = graph.sliceTensor(x, dimension: 3, start: halfD, length: halfD, name: "\(name)x2")
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
        return graph.concatTensors([r1, r2], dimension: 3, name: "\(name)cat")
    }
}
