// RendererPBRPortSyncTests — Drift detection for renderer-private PBR helpers.
//
// `RayMarch.metal` (engine renderer library) carries private ports of two
// preset-utility-tree functions:
//
//   `rm_fresnel_dielectric` ← `Utilities/PBR/Fresnel.metal :: fresnel_dielectric`
//   `rm_thinfilm_rgb`       ← `Utilities/PBR/Thin.metal :: thinfilm_rgb`
//
// The preset utility tree is concatenated only into per-preset preambles
// (see `PresetLoader+Utilities.swift`), so the renderer library cannot call
// the originals directly — it keeps its own copies. Both copies must produce
// bit-identical output on the same inputs; if a future session tunes the
// preset-side version without also updating the renderer-side copy (or vice
// versa), the matID == 3 thin-film branch in `raymarch_lighting_fragment`
// silently diverges from the matID == 0 reflectance any preset using the
// utility tree would compute.
//
// These tests extract the renderer-side `rm_*` function definitions textually
// from `RayMarch.metal`, paste them (renamed to `rmcopy_*` to avoid name
// collision) into a kernel alongside the preset preamble that exposes
// `fresnel_dielectric` / `thinfilm_rgb`, and assert numerical equality on a
// grid of inputs covering the parameter space the matID == 3 branch exercises.

import Foundation
import Metal
import Testing
@testable import Presets

// MARK: - Source-text extraction

/// Errors raised when extracting `rm_*` helper definitions from RayMarch.metal.
enum RendererPortExtractionError: Error {
    case rayMarchSourceNotFound
    case helperNotFound(String)
}

/// Read RayMarch.metal from the repo and return the source text of the two
/// renderer-private PBR helpers, with names + inner calls renamed to `rmcopy_*`
/// so they can coexist with the preset-tree originals in a single compilation
/// unit. Returns concatenated `rmcopy_fresnel_dielectric` + `rmcopy_thinfilm_rgb`
/// source ready to splice into a test kernel.
@MainActor
private func extractRendererPBRPorts() throws -> String {
    // Resolve RayMarch.metal relative to this test file's location at build time.
    // PhospheneEngine/Tests/PhospheneEngineTests/Renderer/RendererPBRPortSyncTests.swift
    // → PhospheneEngine/Sources/Renderer/Shaders/RayMarch.metal
    let here = URL(fileURLWithPath: #filePath)
    let rayMarchURL = here
        .deletingLastPathComponent()             // Renderer/
        .deletingLastPathComponent()             // PhospheneEngineTests/
        .deletingLastPathComponent()             // Tests/
        .deletingLastPathComponent()             // PhospheneEngine/
        .appendingPathComponent("Sources/Renderer/Shaders/RayMarch.metal")

    guard FileManager.default.fileExists(atPath: rayMarchURL.path) else {
        throw RendererPortExtractionError.rayMarchSourceNotFound
    }
    let src = try String(contentsOf: rayMarchURL, encoding: .utf8)

    // Extract `static <type> rm_<name>(...) { ... }` blocks via brace matching.
    let fresnelBody = try extractStaticFunction(named: "rm_fresnel_dielectric", from: src)
    let thinBody    = try extractStaticFunction(named: "rm_thinfilm_rgb",       from: src)

    // Rename to avoid collision with anything else in the test kernel + with
    // any future engine-library function that happens to share a prefix.
    let renamed = (fresnelBody + "\n\n" + thinBody)
        .replacingOccurrences(of: "rm_fresnel_dielectric", with: "rmcopy_fresnel_dielectric")
        .replacingOccurrences(of: "rm_thinfilm_rgb",       with: "rmcopy_thinfilm_rgb")
    return renamed
}

/// Find `static <return-type> <name>(...) { ... }` in `src` and return the
/// full definition including the opening `static` keyword and the closing `}`.
/// Uses simple brace-counting from the function's first `{` — sufficient
/// because neither helper contains string/char literals or preprocessor
/// directives with braces.
private func extractStaticFunction(named name: String, from src: String) throws -> String {
    // Locate the function signature start: a `static` keyword on a line that
    // also references `<name>(`. We don't try to parse arbitrary C++; we just
    // search for the function name preceded by `static` on the same line or
    // a preceding line within a small window.
    guard let nameRange = src.range(of: "\(name)(") else {
        throw RendererPortExtractionError.helperNotFound(name)
    }
    // Walk backwards to the nearest `static` keyword (start of definition).
    var defStart = nameRange.lowerBound
    let searchTail = src[..<defStart]
    guard let staticRange = searchTail.range(of: "static ", options: .backwards) else {
        throw RendererPortExtractionError.helperNotFound(name)
    }
    defStart = staticRange.lowerBound

    // Walk forward to the first `{`, then brace-match.
    guard let firstBrace = src[defStart...].firstIndex(of: "{") else {
        throw RendererPortExtractionError.helperNotFound(name)
    }
    var depth = 0
    var cursor = firstBrace
    while cursor < src.endIndex {
        let ch = src[cursor]
        if ch == "{" { depth += 1 }
        else if ch == "}" {
            depth -= 1
            if depth == 0 {
                let defEnd = src.index(after: cursor)
                return String(src[defStart..<defEnd])
            }
        }
        cursor = src.index(after: cursor)
    }
    throw RendererPortExtractionError.helperNotFound(name)
}

// MARK: - Drift-detection tests

@Suite("Renderer PBR port sync — rm_* helpers stay byte-equivalent to preset-tree originals")
@MainActor
struct RendererPBRPortSyncTests {

    /// `rm_fresnel_dielectric` ≡ `fresnel_dielectric` on a grid of (VdotH, ior).
    /// Coverage spans normal-incidence (VdotH≈1), grazing (VdotH≈0), and the
    /// total-internal-reflection branch (ior=1 → never; covered by ior=1.0 case).
    @Test func rm_fresnel_dielectric_matchesPresetUtility() throws {
        let rendererPorts = try extractRendererPBRPorts()

        let kernel = """
        \(rendererPorts)

        kernel void test_kernel(
            constant float3* inputs  [[buffer(10)]],
            device   float*  outputs [[buffer(11)]],
            uint tid [[thread_position_in_grid]]
        ) {
            float VdotH = inputs[tid].x;
            float ior   = inputs[tid].y;
            // Pair output: even = preset original, odd = renderer port.
            outputs[2 * tid + 0] = fresnel_dielectric(VdotH, ior);
            outputs[2 * tid + 1] = rmcopy_fresnel_dielectric(VdotH, ior);
        }
        """

        var inputs: [SIMD3<Float>] = []
        // VdotH × ior grid spanning the Ferrofluid Ocean parameter space
        // (matID == 3 calls with VdotH ∈ [0, 1], ior_thin = 1.45, ior_base = 1.0).
        // Extra IORs exercise the more general branch in case a future caller
        // uses different substrates (1.33 = water; 1.52 = glass; 2.0 = diamond).
        let vdhValues: [Float] = [0.0, 0.05, 0.2, 0.4, 0.6, 0.8, 0.95, 1.0]
        let iorValues: [Float] = [1.0, 1.33, 1.45, 1.52, 2.0]
        for vdh in vdhValues {
            for ior in iorValues {
                inputs.append(SIMD3<Float>(vdh, ior, 0))
            }
        }
        let results = try runNoiseKernel(
            kernelSource: kernel, inputs: inputs, outputCount: inputs.count * 2
        )

        for i in 0 ..< inputs.count {
            let preset   = results[2 * i + 0]
            let renderer = results[2 * i + 1]
            #expect(
                abs(preset - renderer) < 1e-6,
                """
                rm_fresnel_dielectric drift at VdotH=\(inputs[i].x), ior=\(inputs[i].y):
                  preset original  = \(preset)
                  renderer port    = \(renderer)
                If you intentionally tuned one copy, update the other to match
                — RayMarch.metal cannot include the preset utility tree.
                """
            )
        }
    }

    /// `rm_thinfilm_rgb` ≡ `thinfilm_rgb` on a grid of (VdotH, thicknessNm, iorThin).
    /// iorBase swept across two values (1.0 = Ferrofluid Ocean production; 1.52 =
    /// glass substrate, sanity-check second branch in case a future preset uses it).
    /// thicknessNm = 0 exercises the early-return path; 80–400 nm exercises the
    /// visible-light interference band.
    @Test func rm_thinfilm_rgb_matchesPresetUtility() throws {
        let rendererPorts = try extractRendererPBRPorts()

        for iorBase in [Float(1.0), Float(1.52)] {
            let kernel = """
            \(rendererPorts)

            kernel void test_kernel(
                constant float3* inputs  [[buffer(10)]],
                device   float*  outputs [[buffer(11)]],
                uint tid [[thread_position_in_grid]]
            ) {
                float VdotH       = inputs[tid].x;
                float thicknessNm = inputs[tid].y;
                float iorThin     = inputs[tid].z;
                float iorBase     = \(iorBase);
                float3 preset   = thinfilm_rgb(VdotH, thicknessNm, iorThin, iorBase);
                float3 renderer = rmcopy_thinfilm_rgb(VdotH, thicknessNm, iorThin, iorBase);
                // 6 outputs per input: preset.rgb followed by renderer.rgb.
                outputs[6 * tid + 0] = preset.x;
                outputs[6 * tid + 1] = preset.y;
                outputs[6 * tid + 2] = preset.z;
                outputs[6 * tid + 3] = renderer.x;
                outputs[6 * tid + 4] = renderer.y;
                outputs[6 * tid + 5] = renderer.z;
            }
            """

            var inputs: [SIMD3<Float>] = []
            // VdotH × thickness × ior_thin grid. thickness=0 hits the
            // early-return branch; the rest cover the visible interference band.
            let vdhValues: [Float] = [0.05, 0.3, 0.6, 0.9, 1.0]
            let thicknesses: [Float] = [0.0, 80.0, 150.0, 220.0, 320.0, 500.0]
            let iorThinValues: [Float] = [1.33, 1.45]
            for vdh in vdhValues {
                for thick in thicknesses {
                    for thin in iorThinValues {
                        inputs.append(SIMD3<Float>(vdh, thick, thin))
                    }
                }
            }
            let results = try runNoiseKernel(
                kernelSource: kernel, inputs: inputs, outputCount: inputs.count * 6
            )

            for i in 0 ..< inputs.count {
                let p = SIMD3<Float>(results[6 * i + 0], results[6 * i + 1], results[6 * i + 2])
                let r = SIMD3<Float>(results[6 * i + 3], results[6 * i + 4], results[6 * i + 5])
                let diff = max(abs(p.x - r.x), max(abs(p.y - r.y), abs(p.z - r.z)))
                #expect(
                    diff < 1e-6,
                    """
                    rm_thinfilm_rgb drift at VdotH=\(inputs[i].x), thickness=\(inputs[i].y) nm, \
                    iorThin=\(inputs[i].z), iorBase=\(iorBase):
                      preset original  = \(p)
                      renderer port    = \(r)
                      max channel diff = \(diff)
                    If you intentionally tuned one copy, update the other to match
                    — RayMarch.metal cannot include the preset utility tree.
                    """
                )
            }
        }
    }
}
