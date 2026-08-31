// PANNsMobileNetV1+Graph — MPSGraph network build for the MobileNetV1 conv stack.
//
// Input: log-mel [1, frames, 64, 1] NHWC. The PANNs MobileNetV1 body downsamples
// via AvgPool2d (each conv is stride-1, pad-1); BatchNorm is fused to scale/shift
// at load. Head: mean over mel → (max + mean) over time → fc1+ReLU → fc+sigmoid.
//
// All ops are CNN-family already proven in the Beat This! / Open-Unmix ports;
// the only new primitive is grouped (depthwise) convolution via the descriptor's
// `groups` field. Diagnostic taps: bn0 (front-end → graph) and pre_fc (whole conv
// stack), the two layout-trivial anchors that localize any parity divergence.

import Foundation
import MetalPerformanceShadersGraph

extension PANNsMobileNetV1 {

    // MARK: - Build

    static func buildGraph(weights: PANNsWeights, frames: Int) throws -> PANNsGraphBundle {
        let graph = MPSGraph()
        let mel = melBins

        let input = graph.placeholder(
            shape: [1, NSNumber(value: frames), NSNumber(value: mel), 1],
            dataType: .float32,
            name: "logmel")

        // bn0 normalizes per mel-bin (the W=64 axis): broadcast [1,1,64,1].
        var x = applyBN(graph, input, weights.bn0, axisShape: [1, 1, NSNumber(value: mel), 1], name: "bn0")
        var intermediates: [String: MPSGraphTensor] = ["bn0": x]

        // features.0 — conv_bn(1 → 32, stride 2)
        x = convBN(graph, x, weights.stage0, name: "f0")

        // features.1 … features.13 — conv_dw
        for (i, st) in weights.dwStages.enumerated() {
            x = convDW(graph, x, st, name: "f\(i + 1)")
        }
        // x: [1, T'', 2, 1024]

        // Head: mean over mel (W, axis 2) → (max + mean) over time (axis 1).
        let meanW = graph.mean(of: x, axes: [2], name: "meanW")                     // [1,T'',1,1024]
        let bt = graph.reshape(meanW, shape: [1, NSNumber(value: -1), 1024], name: "bt")  // [1,T'',1024]
        let maxT = graph.reductionMaximum(with: bt, axis: 1, name: "maxT")          // [1,1,1024]
        let meanT = graph.mean(of: bt, axes: [1], name: "meanT")                    // [1,1,1024]
        let summed = graph.addition(maxT, meanT, name: "preFcSum")
        let preFc = graph.reshape(summed, shape: [1, 1024], name: "preFc")          // [1,1024]
        intermediates["pre_fc"] = graph.reshape(preFc, shape: [1024], name: "preFcFlat")

        // fc1 + ReLU
        let fc1Spec = LinearSpec(weight: weights.fc1Weight, bias: weights.fc1Bias, outDim: 1024)
        let fc1 = linear(graph, preFc, fc1Spec, name: "fc1")
        let fc1r = graph.reLU(with: fc1, name: "fc1relu")

        // fc_audioset → logits → sigmoid
        let fcSpec = LinearSpec(weight: weights.fcWeight, bias: weights.fcBias, outDim: classCount)
        let logits2 = linear(graph, fc1r, fcSpec, name: "fc")
        let logits = graph.reshape(logits2, shape: [NSNumber(value: classCount)], name: "logits")
        let probs = graph.sigmoid(with: logits, name: "probs")

        return PANNsGraphBundle(
            graph: graph,
            input: input,
            probs: probs,
            logits: logits,
            intermediates: intermediates)
    }

    // MARK: - Stages

    /// One stride-1 square conv, parameterized so the call sites stay one-line.
    private struct ConvSpec {
        let weightOIHW: [Float]
        let outC: Int
        let inC: Int
        let kernel: Int
        let groups: Int
    }

    /// conv_bn: Conv2d(3x3,pad1,s1) → AvgPool(stride) → BN → ReLU.
    private static func convBN(_ graph: MPSGraph, _ input: MPSGraphTensor,
                               _ cb: PANNsConvBN, name: String) -> MPSGraphTensor {
        let spec = ConvSpec(weightOIHW: cb.convWeight, outC: cb.outC, inC: cb.inC, kernel: 3, groups: 1)
        var x = conv(graph, input, spec, name: "\(name)c")
        x = avgPool(graph, x, k: cb.stride, name: "\(name)pool")
        x = applyBN(graph, x, cb.bn, axisShape: bnAxis(cb.outC), name: "\(name)bn")
        return graph.reLU(with: x, name: "\(name)relu")
    }

    /// conv_dw: dwConv(3x3,pad1,groups=inC) → AvgPool → BN → ReLU → pwConv(1x1) → BN → ReLU.
    private static func convDW(_ graph: MPSGraph, _ input: MPSGraphTensor,
                               _ cd: PANNsConvDW, name: String) -> MPSGraphTensor {
        // Depthwise: PyTorch weight [inC,1,3,3] → HWIO [3,3,1,inC], groups=inC.
        let dw = ConvSpec(weightOIHW: cd.dwWeight, outC: cd.inC, inC: 1, kernel: 3, groups: cd.inC)
        var x = conv(graph, input, dw, name: "\(name)dw")
        x = avgPool(graph, x, k: cd.stride, name: "\(name)pool")
        x = applyBN(graph, x, cd.bn1, axisShape: bnAxis(cd.inC), name: "\(name)bn1")
        x = graph.reLU(with: x, name: "\(name)relu1")
        // Pointwise 1x1.
        let pw = ConvSpec(weightOIHW: cd.pwWeight, outC: cd.outC, inC: cd.inC, kernel: 1, groups: 1)
        x = conv(graph, x, pw, name: "\(name)pw")
        x = applyBN(graph, x, cd.bn2, axisShape: bnAxis(cd.outC), name: "\(name)bn2")
        return graph.reLU(with: x, name: "\(name)relu2")
    }

    /// BN broadcast shape over the channel (last) axis: [1,1,1,C].
    private static func bnAxis(_ channels: Int) -> [NSNumber] { [1, 1, 1, NSNumber(value: channels)] }

    // MARK: - Primitives

    /// Conv2d, stride-1, square kernel (pad = kernel/2 → 3×3 pad 1, 1×1 pad 0).
    private static func conv(_ graph: MPSGraph, _ input: MPSGraphTensor,
                             _ spec: ConvSpec, name: String) -> MPSGraphTensor {
        let pad = spec.kernel / 2
        let hwio = rearrangeConvOIHW_to_HWIO(
            data: spec.weightOIHW, outC: spec.outC, inC: spec.inC, kH: spec.kernel, kW: spec.kernel)
        let shape = [NSNumber(value: spec.kernel), NSNumber(value: spec.kernel),
                     NSNumber(value: spec.inC), NSNumber(value: spec.outC)]
        let wConst = makeConst(graph, hwio, shape: shape, name: "\(name)w")
        // swiftlint:disable force_unwrapping
        let desc = MPSGraphConvolution2DOpDescriptor(
            strideInX: 1,
            strideInY: 1,
            dilationRateInX: 1,
            dilationRateInY: 1,
            groups: spec.groups,
            paddingLeft: pad,
            paddingRight: pad,
            paddingTop: pad,
            paddingBottom: pad,
            paddingStyle: .explicit,
            dataLayout: .NHWC,
            weightsLayout: .HWIO)!
        // swiftlint:enable force_unwrapping
        return graph.convolution2D(input, weights: wConst, descriptor: desc, name: name)
    }

    private static func avgPool(_ graph: MPSGraph, _ input: MPSGraphTensor,
                                k: Int, name: String) -> MPSGraphTensor {
        guard k > 1 else { return input }   // AvgPool2d(1) is identity
        // swiftlint:disable force_unwrapping
        let desc = MPSGraphPooling2DOpDescriptor(
            kernelWidth: k,
            kernelHeight: k,
            strideInX: k,
            strideInY: k,
            dilationRateInX: 1,
            dilationRateInY: 1,
            paddingLeft: 0,
            paddingRight: 0,
            paddingTop: 0,
            paddingBottom: 0,
            paddingStyle: .explicit,
            dataLayout: .NHWC)!
        // swiftlint:enable force_unwrapping
        return graph.avgPooling2D(withSourceTensor: input, descriptor: desc, name: name)
    }

    /// Fused BN as elementwise scale/shift, broadcast over `axisShape`.
    private static func applyBN(_ graph: MPSGraph, _ input: MPSGraphTensor,
                                _ bn: PANNsFusedBN, axisShape: [NSNumber], name: String) -> MPSGraphTensor {
        let scale = makeConst(graph, bn.scale, shape: axisShape, name: "\(name)sc")
        let shift = makeConst(graph, bn.shift, shape: axisShape, name: "\(name)sh")
        return graph.addition(graph.multiplication(input, scale, name: "\(name)mul"), shift, name: "\(name)add")
    }

    private struct LinearSpec {
        let weight: [Float]   // [outDim, inDim] row-major
        let bias: [Float]
        let outDim: Int
    }

    /// y = x · Wᵀ + b. `input` [1, inDim]; inDim derived from weight.count / outDim.
    private static func linear(_ graph: MPSGraph, _ input: MPSGraphTensor,
                               _ spec: LinearSpec, name: String) -> MPSGraphTensor {
        let wShape = [NSNumber(value: spec.outDim), NSNumber(value: spec.weight.count / spec.outDim)]
        let wConst = makeConst(graph, spec.weight, shape: wShape, name: "\(name)w")
        let wT = graph.transposeTensor(wConst, dimension: 0, withDimension: 1, name: "\(name)wT")
        let mm = graph.matrixMultiplication(primary: input, secondary: wT, name: "\(name)mm")
        let bConst = makeConst(graph, spec.bias, shape: [1, NSNumber(value: spec.outDim)], name: "\(name)b")
        return graph.addition(mm, bConst, name: "\(name)bias")
    }

    // MARK: - Const helper

    static func makeConst(_ graph: MPSGraph, _ vals: [Float], shape: [NSNumber], name: String) -> MPSGraphTensor {
        graph.constant(
            Data(bytes: vals, count: vals.count * MemoryLayout<Float>.size),
            shape: shape,
            dataType: .float32)
    }
}
