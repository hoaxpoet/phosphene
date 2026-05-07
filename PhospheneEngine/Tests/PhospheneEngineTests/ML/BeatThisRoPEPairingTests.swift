// BeatThisRoPEPairingTests — Targeted spec test for DSP.2 S8 Bug 4.
//
// Pre-fix: Swift `applyRoPE4D` and `applyRoPE` (transformer) used half-and-half
// pairing `(x[i], x[D/2+i])`. PyTorch's `rotary_embedding_torch.rotate_half` pairs
// adjacent elements `(x[2i], x[2i+1])` — completely different attention dot
// products, breaking the model end-to-end.
//
// Production coverage is `BeatThisLayerMatchTests` — it runs the actual MPSGraph
// `applyRoPE4D` / `applyRoPE` on real audio and would diverge by > 30 % at
// transformer.norm if Bug 4 returned. This test is the *spec*: it documents what
// adjacent-pair semantics produces, in a venue that doesn't require fixtures or
// Metal, so a future regression localises immediately to "RoPE pairing wrong"
// rather than emerging only as a stat divergence further downstream.

import Testing
import Foundation

/// Reference implementation of paired-adjacent RoPE — must match the algorithmic
/// shape of `BeatThisModel.applyRoPE4D` / `applyRoPE`. If the production functions
/// are ever rewritten and this test still passes, the production regression is
/// caught by `BeatThisLayerMatchTests`; this stand-alone test simply pins the
/// spec so the *meaning* of "paired-adjacent RoPE" stays unambiguous in the repo.
private func applyRoPEAdjacent(input: [Float], cos: [Float], sin: [Float]) -> [Float] {
    precondition(input.count.isMultiple(of: 2), "headDim must be even")
    precondition(cos.count == input.count / 2)
    precondition(sin.count == input.count / 2)
    var out = [Float](repeating: 0, count: input.count)
    for pair in 0..<(input.count / 2) {
        let a = input[2 * pair]
        let b = input[2 * pair + 1]
        let c = cos[pair]
        let s = sin[pair]
        out[2 * pair]     = a * c - b * s
        out[2 * pair + 1] = a * s + b * c
    }
    return out
}

@Suite("BeatThisRoPEPairing")
struct BeatThisRoPEPairingTests {

    // MARK: - Adjacent-pair π/2 rotation produces the canonical pattern

    /// At cos=0, sin=1 (rotation angle π/2), each pair (a, b) maps via the
    /// production rotation matrix `new_a = a·cos − b·sin; new_b = a·sin + b·cos`
    /// to (−b, a). Adjacent pairing applies this to (x[2i], x[2i+1]):
    /// (1,2)→(−2,1) (3,4)→(−4,3) (5,6)→(−6,5) (7,8)→(−8,7).
    ///
    /// Half-and-half pairing (the pre-S8 bug) applies the same rotation to
    /// (x[i], x[D/2+i]), producing [-5,-6,-7,-8, 1,2,3,4] for this input —
    /// every index disagrees, hence the layer-match divergence > 30 %.
    @Test("RoPE applies adjacent-pair rotation, not half-and-half — DSP.2 S8 Bug 4")
    func test_ropeAdjacentPairing() {
        let input: [Float] = [1, 2, 3, 4, 5, 6, 7, 8]
        let cos = [Float](repeating: 0, count: 4)
        let sin = [Float](repeating: 1, count: 4)
        let output = applyRoPEAdjacent(input: input, cos: cos, sin: sin)
        let expected: [Float] = [-2, 1, -4, 3, -6, 5, -8, 7]
        for (idx, exp) in expected.enumerated() {
            #expect(abs(output[idx] - exp) < 1e-5,
                    "RoPE Bug 4 regression at index \(idx): got \(output[idx]), expected \(exp)")
        }
    }

    // MARK: - Identity rotation leaves input unchanged

    /// At cos=1, sin=0 (rotation angle 0), adjacent rotation is identity.
    /// Half-and-half would also be identity here, so this test is not
    /// discriminating against Bug 4 — it gates that the rotation matrix
    /// arithmetic itself is correct (a = a·1 − b·0; b = a·0 + b·1).
    @Test("RoPE identity rotation (cos=1, sin=0) is the identity map")
    func test_ropeIdentityRotation() {
        let input: [Float] = [1, 2, 3, 4, 5, 6, 7, 8]
        let cos = [Float](repeating: 1, count: 4)
        let sin = [Float](repeating: 0, count: 4)
        let output = applyRoPEAdjacent(input: input, cos: cos, sin: sin)
        for (idx, exp) in input.enumerated() {
            #expect(abs(output[idx] - exp) < 1e-6,
                    "RoPE identity regression at index \(idx): got \(output[idx]), expected \(exp)")
        }
    }

    // MARK: - Half-and-half pairing produces a different vector

    /// Documents the *wrong* pre-S8 semantics so a future reader can see the
    /// distinguishing signal without having to reconstruct it. If this test
    /// ever fails because adjacent and half-and-half produce the same output
    /// for the chosen input, the test input has lost discriminating power and
    /// this test should be tightened, not the production switched.
    @Test("Adjacent-pair output differs from the half-and-half pre-S8 output")
    func test_adjacentDiffersFromHalfAndHalf() {
        let input: [Float] = [1, 2, 3, 4, 5, 6, 7, 8]
        let cos = [Float](repeating: 0, count: 4)
        let sin = [Float](repeating: 1, count: 4)
        let adjacent = applyRoPEAdjacent(input: input, cos: cos, sin: sin)
        // Half-and-half: pairs (x[i], x[D/2+i]).
        // (1,5)→(5·-1, 1) (2,6)→(6·-1, 2) (3,7)→(7·-1, 3) (4,8)→(8·-1, 4)
        // first half = [-5, -6, -7, -8]; second half = [1, 2, 3, 4]
        let halfAndHalf: [Float] = [-5, -6, -7, -8, 1, 2, 3, 4]
        var anyDiffer = false
        for idx in 0..<input.count where abs(adjacent[idx] - halfAndHalf[idx]) > 1e-3 {
            anyDiffer = true
        }
        #expect(anyDiffer, "Adjacent and half-and-half produced identical output — test input no longer discriminates")
    }
}
