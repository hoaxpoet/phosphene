// StemModel+Graph — MPSGraph construction for Open-Unmix HQ inference.
//
// Builds a single MPSGraph containing all 4 stems. Each stem is an
// independent subgraph sharing the same input placeholder. The graph is
// compiled once at init and reused for every predict() call.
//
// Architecture per stem (corrected per 3.7b weight extraction):
//   Input [431, 2, 1487] → InputNorm → Reshape [431, 2974]
//   → FC1(2974→512) + BN1 + Tanh
//   → LSTM(3 layers, bidirectional, hidden=256, output=512)
//   → concat(fc1_out, lstm_out) → [431, 1024]
//   → FC2(1024→512) + BN2 + ReLU
//   → FC3(512→4098) + BN3 + OutputDenorm
//   → Reshape [431, 2, 2049] → ReLU(mask) × input → Output [431, 2, 2049]

import Foundation
import Metal
import MetalPerformanceShadersGraph

// MARK: - Graph Bundle

/// The compiled MPSGraph and its I/O tensor handles.
struct StemModelGraphBundle {
    let graph: MPSGraph
    let inputTensor: MPSGraphTensor
    let stemOutputTensors: [MPSGraphTensor]
}

// MARK: - Linear Layer Config

/// Parameters for a bias-free linear layer in the graph.
struct LinearConfig {
    let weight: [Float]
    let outFeatures: Int
    let inFeatures: Int
}

// MARK: - Graph Construction

extension StemModelEngine {

    /// Build the complete Open-Unmix HQ graph for all 4 stems.
    static func buildGraph(allWeights: [StemWeights]) -> StemModelGraphBundle {
        let graph = MPSGraph()

        let shape: [NSNumber] = [
            NSNumber(value: modelFrameCount),
            2,
            NSNumber(value: nBins)
        ]
        let input = graph.placeholder(
            shape: shape,
            dataType: .float32,
            name: "spectrogram"
        )

        var outputs = [MPSGraphTensor]()
        let stemNames = ["vocals", "drums", "bass", "other"]

        for (idx, weights) in allWeights.enumerated() {
            let output = buildStemSubgraph(
                graph: graph,
                input: input,
                weights: weights,
                name: stemNames[idx]
            )
            outputs.append(output)
        }

        return StemModelGraphBundle(
            graph: graph,
            inputTensor: input,
            stemOutputTensors: outputs
        )
    }

    // MARK: - Per-Stem Subgraph

    /// Build the subgraph for a single stem.
    private static func buildStemSubgraph(
        graph: MPSGraph,
        input: MPSGraphTensor,
        weights: StemWeights,
        name: String
    ) -> MPSGraphTensor {
        // Steps 1-5: Input norm → FC1 → BN1 → Tanh
        let tanh1 = buildEncoderHead(
            graph: graph,
            input: input,
            weights: weights,
            name: name
        )

        // Step 6: LSTM stack (3 layers, bidirectional)
        let lstmOut = buildLSTMStack(
            graph: graph,
            input: tanh1,
            layers: weights.lstmLayers,
            name: "\(name)/lstm"
        )

        // Step 7: Skip connection → FC2 → BN2 → ReLU → FC3 → BN3
        let bn3Out = buildDecoderTail(
            graph: graph,
            fc1Out: tanh1,
            lstmOut: lstmOut,
            weights: weights,
            name: name
        )

        // Steps 12-13: Reshape → Denorm → ReLU → Mask
        return buildOutputMask(
            graph: graph,
            bn3Out: bn3Out,
            input: input,
            weights: weights,
            name: name
        )
    }

    /// Steps 1-5: Slice → Normalize → Reshape → FC1 → BN1 → Tanh.
    private static func buildEncoderHead(
        graph: MPSGraph,
        input: MPSGraphTensor,
        weights: StemWeights,
        name: String
    ) -> MPSGraphTensor {
        // 1. Slice [431, 2, 2049] → [431, 2, 1487]
        let sliced = graph.sliceTensor(
            input,
            dimension: 2,
            start: 0,
            length: bandwidthBins,
            name: "\(name)/slice"
        )

        // 2. Normalize: (x - mean) / scale
        let mean = makeConstant(graph, weights.inputMean, shape: [1, 1, NSNumber(value: bandwidthBins)])
        let scale = makeConstant(graph, weights.inputScale, shape: [1, 1, NSNumber(value: bandwidthBins)])
        let sub = graph.subtraction(sliced, mean, name: "\(name)/sub_mean")
        let normalized = graph.division(sub, scale, name: "\(name)/div_scale")

        // 3. Reshape [431, 2, 1487] → [431, 2974]
        let flatShape: [NSNumber] = [NSNumber(value: modelFrameCount), NSNumber(value: 2 * bandwidthBins)]
        let reshaped = graph.reshape(normalized, shape: flatShape, name: "\(name)/reshape_in")

        // 4-5. FC1 → BN1 → Tanh
        let fc1Config = LinearConfig(weight: weights.fc1Weight, outFeatures: 512, inFeatures: 2 * bandwidthBins)
        let fc1Out = buildLinear(graph: graph, input: reshaped, config: fc1Config, name: "\(name)/fc1")
        let bn1Out = buildFusedBN(graph: graph, input: fc1Out, bn: weights.bn1, name: "\(name)/bn1")
        return graph.tanh(with: bn1Out, name: "\(name)/tanh1")
    }

    /// Steps 7-11: Skip → FC2 → BN2 → ReLU → FC3 → BN3.
    private static func buildDecoderTail(
        graph: MPSGraph,
        fc1Out: MPSGraphTensor,
        lstmOut: MPSGraphTensor,
        weights: StemWeights,
        name: String
    ) -> MPSGraphTensor {
        // 7. Skip connection: concat → [431, 1024]
        let concat = graph.concatTensors([fc1Out, lstmOut], dimension: 1, name: "\(name)/skip")

        // 8-9. FC2 → BN2 → ReLU
        let fc2Config = LinearConfig(weight: weights.fc2Weight, outFeatures: 512, inFeatures: 1024)
        let fc2Out = buildLinear(graph: graph, input: concat, config: fc2Config, name: "\(name)/fc2")
        let bn2Out = buildFusedBN(graph: graph, input: fc2Out, bn: weights.bn2, name: "\(name)/bn2")
        let relu2 = graph.reLU(with: bn2Out, name: "\(name)/relu2")

        // 10-11. FC3 → BN3
        let fc3Config = LinearConfig(weight: weights.fc3Weight, outFeatures: 4098, inFeatures: 512)
        let fc3Out = buildLinear(graph: graph, input: relu2, config: fc3Config, name: "\(name)/fc3")
        return buildFusedBN(graph: graph, input: fc3Out, bn: weights.bn3, name: "\(name)/bn3")
    }

    /// Steps 12-13: Reshape → Denormalize → ReLU → Apply mask.
    private static func buildOutputMask(
        graph: MPSGraph,
        bn3Out: MPSGraphTensor,
        input: MPSGraphTensor,
        weights: StemWeights,
        name: String
    ) -> MPSGraphTensor {
        let outShape: [NSNumber] = [NSNumber(value: modelFrameCount), 2, NSNumber(value: nBins)]
        let maskReshaped = graph.reshape(bn3Out, shape: outShape, name: "\(name)/reshape_out")

        let outScale = makeConstant(graph, weights.outputScale, shape: [1, 1, NSNumber(value: nBins)])
        let outMean = makeConstant(graph, weights.outputMean, shape: [1, 1, NSNumber(value: nBins)])

        let scaled = graph.multiplication(maskReshaped, outScale, name: "\(name)/out_scale")
        let denormed = graph.addition(scaled, outMean, name: "\(name)/out_denorm")
        let reluMask = graph.reLU(with: denormed, name: "\(name)/relu_mask")

        return graph.multiplication(reluMask, input, name: "\(name)/apply_mask")
    }

    // MARK: - Linear Layer (bias=False)

    /// Matrix multiplication: input [T, I] × weight^T → [T, O].
    private static func buildLinear(
        graph: MPSGraph,
        input: MPSGraphTensor,
        config: LinearConfig,
        name: String
    ) -> MPSGraphTensor {
        let shape: [NSNumber] = [NSNumber(value: config.outFeatures), NSNumber(value: config.inFeatures)]
        let weightConst = graph.constant(
            Data(bytes: config.weight, count: config.weight.count * 4),
            shape: shape,
            dataType: .float32
        )
        let weightT = graph.transposeTensor(
            weightConst,
            dimension: 0,
            withDimension: 1,
            name: "\(name)/wT"
        )
        return graph.matrixMultiplication(
            primary: input,
            secondary: weightT,
            name: "\(name)/mm"
        )
    }

    // MARK: - Fused Batch Norm

    /// Apply pre-fused batch norm: y = x * scale + bias.
    private static func buildFusedBN(
        graph: MPSGraph,
        input: MPSGraphTensor,
        bn: FusedBatchNorm,
        name: String
    ) -> MPSGraphTensor {
        let scaleConst = makeConstant(graph, bn.scale, shape: [1, NSNumber(value: bn.scale.count)])
        let biasConst = makeConstant(graph, bn.bias, shape: [1, NSNumber(value: bn.bias.count)])
        let scaled = graph.multiplication(input, scaleConst, name: "\(name)/scale")
        return graph.addition(scaled, biasConst, name: "\(name)/bias")
    }

    // MARK: - Bidirectional LSTM Stack

    /// Build a 3-layer bidirectional LSTM stack.
    private static func buildLSTMStack(
        graph: MPSGraph,
        input: MPSGraphTensor,
        layers: [LSTMLayerWeights],
        name: String
    ) -> MPSGraphTensor {
        var current = graph.expandDims(input, axis: 1, name: "\(name)/expand_batch")

        for (idx, layer) in layers.enumerated() {
            current = buildBidirectionalLSTMLayer(
                graph: graph,
                input: current,
                weights: layer,
                name: "\(name)/l\(idx)"
            )
        }

        return graph.squeeze(current, axis: 1, name: "\(name)/squeeze_batch")
    }

    /// Build a single bidirectional LSTM layer using MPSGraph's LSTM op.
    private static func buildBidirectionalLSTMLayer(
        graph: MPSGraph,
        input: MPSGraphTensor,
        weights: LSTMLayerWeights,
        name: String
    ) -> MPSGraphTensor {
        let hiddenSize = 256
        let gateSize = 4 * hiddenSize

        let inputW = makeConstant(
            graph,
            weights.inputWeight,
            shape: [NSNumber(value: 2 * gateSize), NSNumber(value: weights.inputSize)]
        )
        let recurrentW = makeConstant(
            graph,
            weights.recurrentWeight,
            shape: [2, NSNumber(value: gateSize), NSNumber(value: hiddenSize)]
        )
        let biasT = makeConstant(graph, weights.bias, shape: [NSNumber(value: 2 * gateSize)])

        let desc = MPSGraphLSTMDescriptor()
        desc.bidirectional = true

        let results = graph.LSTM(
            input,
            recurrentWeight: recurrentW,
            inputWeight: inputW,
            bias: biasT,
            initState: nil,
            initCell: nil,
            descriptor: desc,
            name: name
        )

        return results[0]
    }

    // MARK: - Constant Helper

    /// Create an MPSGraph constant from a float array with the given shape.
    private static func makeConstant(
        _ graph: MPSGraph,
        _ values: [Float],
        shape: [NSNumber]
    ) -> MPSGraphTensor {
        graph.constant(
            Data(bytes: values, count: values.count * MemoryLayout<Float>.size),
            shape: shape,
            dataType: .float32
        )
    }
}
