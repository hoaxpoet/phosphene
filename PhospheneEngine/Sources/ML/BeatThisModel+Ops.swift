// BeatThisModel+Ops — primitive MPSGraph ops for Beat This! encoder.
// RMSNorm, GELU, Linear, and constant helpers shared by BeatThisModel+Graph.

import Foundation
import MetalPerformanceShadersGraph

// MARK: - Linear Spec

/// Weight + optional bias for a single linear projection.
struct BeatLinearSpec {
    let weight: MPSGraphTensor  // [outDim, inDim]
    let bias: MPSGraphTensor?   // [outDim], or nil for bias-free
    let outDim: Int
}

// MARK: - Primitives

extension BeatThisModel {

    // MARK: - RMSNorm

    /// y = x / rms(x) × γ,  rms(x) = √(mean(x²) + ε).
    static func buildRMSNorm(
        graph: MPSGraph,
        input: MPSGraphTensor,
        gamma: MPSGraphTensor,
        dim: Int,
        normAxis: Int = 1,
        name: String
    ) -> MPSGraphTensor {
        let scalar: [NSNumber] = [1]
        let invDimC = graph.constant(1.0 / Double(dim), shape: scalar, dataType: .float32)
        let epsC = graph.constant(1e-6, shape: scalar, dataType: .float32)
        let xSq = graph.square(with: input, name: "\(name)sq")
        let sumSq = graph.reductionSum(with: xSq, axis: normAxis, name: "\(name)sum")
        let meanSq = graph.multiplication(sumSq, invDimC, name: "\(name)mean")
        let rms = graph.squareRoot(
            with: graph.addition(meanSq, epsC, name: "\(name)eps"),
            name: "\(name)rms"
        )
        return graph.multiplication(
            graph.division(input, rms, name: "\(name)div"),
            gamma,
            name: "\(name)scale"
        )
    }

    // MARK: - GELU

    /// GELU(x) = 0.5 × x × (1 + tanh(√(2/π) × (x + 0.044715 × x³)))
    static func buildGELU(
        graph: MPSGraph,
        input: MPSGraphTensor,
        name: String
    ) -> MPSGraphTensor {
        let scalar: [NSNumber] = [1]
        let c1 = graph.constant(sqrt(2.0 / Double.pi), shape: scalar, dataType: .float32)
        let c2 = graph.constant(0.044715, shape: scalar, dataType: .float32)
        let c3 = graph.constant(0.5, shape: scalar, dataType: .float32)
        let c4 = graph.constant(1.0, shape: scalar, dataType: .float32)
        let x3 = graph.multiplication(
            graph.multiplication(input, input, name: "\(name)x2"),
            input,
            name: "\(name)x3"
        )
        let inner = graph.multiplication(
            c1,
            graph.addition(input, graph.multiplication(c2, x3, name: "\(name)kx3"), name: "\(name)sum"),
            name: "\(name)inner"
        )
        let onePlusTanh = graph.addition(
            graph.tanh(with: inner, name: "\(name)tanh"),
            c4,
            name: "\(name)1t"
        )
        return graph.multiplication(
            c3,
            graph.multiplication(input, onePlusTanh, name: "\(name)xt"),
            name: "\(name)gelu"
        )
    }

    // MARK: - Linear

    static func buildLinear(
        graph: MPSGraph,
        input: MPSGraphTensor,
        spec: BeatLinearSpec,
        name: String
    ) -> MPSGraphTensor {
        let wT = graph.transposeTensor(spec.weight, dimension: 0, withDimension: 1, name: "\(name)wT")
        let mm = graph.matrixMultiplication(primary: input, secondary: wT, name: "\(name)mm")
        guard let bias = spec.bias else { return mm }
        let biasR = graph.reshape(bias, shape: [1, NSNumber(value: spec.outDim)], name: "\(name)bR")
        return graph.addition(mm, biasR, name: "\(name)ab")
    }

        // MARK: - Constant Helpers

    static func makeZerosConst(_ graph: MPSGraph, shape: [NSNumber], name: String) -> MPSGraphTensor {
        graph.constant(0.0, shape: shape, dataType: .float32)
    }

    /// All-ones tensor [1, dim] — used as RMSNorm γ (broadcasts over T).
    static func makeOnesConst(_ graph: MPSGraph, dim: Int, name: String) -> MPSGraphTensor {
        graph.constant(1.0, shape: [1, NSNumber(value: dim)], dataType: .float32)
    }

    /// Create a Float32 constant from a [Float] array with the given shape.
    static func makeConst(
        _ graph: MPSGraph, _ vals: [Float], shape: [NSNumber], name: String
    ) -> MPSGraphTensor {
        graph.constant(
            Data(bytes: vals, count: vals.count * MemoryLayout<Float>.size),
            shape: shape,
            dataType: .float32
        )
    }
}
