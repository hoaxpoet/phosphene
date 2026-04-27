// MaterialRenderHarness.swift — Compute-pipeline harness for material cookbook tests.
//
// Design choice: Route (b) — lightweight compute fake.
// A pure compute kernel simulates a sphere SDF and evaluates the material function at
// each sample point, returning MaterialResult fields (albedo, roughness, metallic,
// emission) for assertion in MaterialCookbookTests.
//
// Route (a) (reusing the full engine ray-march pipeline) was evaluated during
// pre-flight and rejected: RayMarchPipeline requires MainActor-bound MTLDevice
// setup, IBL texture loading, and a configured VisualizerEngine — too much
// scaffolding for isolated unit testing. Route (b) exercises exactly the
// cookbook code under standardised lighting parameters via the same preamble
// path the renderer uses.
//
// Golden hashes use the same 9×8 luma dHash as PresetRegressionTests.

import Foundation
import Metal
@testable import Presets

// MARK: - MaterialResult Swift mirror

/// Swift mirror of the Metal MaterialResult struct for harness output deserialization.
struct MaterialResultSwift {
    var albedo:    SIMD3<Float>
    var roughness: Float
    var metallic:  Float
    var normal:    SIMD3<Float>
    var emission:  SIMD3<Float>
}

// MARK: - Sample struct (must match the Metal kernel layout)

// Output layout per sample:
// [0] albedo.x  [1] albedo.y  [2] albedo.z
// [3] roughness [4] metallic
// [5] normal.x  [6] normal.y  [7] normal.z
// [8] emission.x [9] emission.y [10] emission.z
let kMaterialOutputStride = 11

// MARK: - Harness entry point

/// Evaluate a material cookbook function at a grid of world-space sample points.
///
/// `materialID` selects which material the kernel dispatches to (see kernel switch below).
/// Returns an array of `MaterialResultSwift` for each sample position.
///
/// `extraSource` allows tests to inject auxiliary kernel code (e.g. helper constants).
func runMaterialKernel(
    materialID: Int,
    samplePositions: [SIMD3<Float>],
    extraParams: [Float] = []
) throws -> [MaterialResultSwift] {
    guard let device = MTLCreateSystemDefaultDevice() else {
        throw NoiseHarnessError.noDevice
    }

    let count    = samplePositions.count
    let outCount = count * kMaterialOutputStride

    // Sphere surface normals: for each position on unit sphere, normal = normalize(pos).
    let kernel = makeMaterialDispatchKernel()
    let fullSource = PresetLoader.shaderPreamble + "\n\n" + kernel

    let options = MTLCompileOptions()
    options.fastMathEnabled  = true
    options.languageVersion  = .version3_1

    let library: MTLLibrary
    do {
        library = try device.makeLibrary(source: fullSource, options: options)
    } catch {
        throw NoiseHarnessError.libraryCompilationFailed("\(error)")
    }

    guard let fn = library.makeFunction(name: "material_test_kernel") else {
        throw NoiseHarnessError.kernelNotFound("material_test_kernel")
    }

    let pipeline: MTLComputePipelineState
    do {
        pipeline = try device.makeComputePipelineState(function: fn)
    } catch {
        throw NoiseHarnessError.pipelineFailed
    }

    // Input: positions (float3 each, padded to 4 floats for alignment).
    let posStride = MemoryLayout<SIMD4<Float>>.stride
    let posData   = samplePositions.map { SIMD4<Float>($0.x, $0.y, $0.z, 0) }
    guard let positionBuf = device.makeBuffer(
        bytes: posData, length: count * posStride, options: .storageModeShared
    ) else { throw NoiseHarnessError.bufferAllocationFailed }

    // MaterialID as a single uint.
    var mid = UInt32(materialID)
    guard let idBuf = device.makeBuffer(
        bytes: &mid, length: MemoryLayout<UInt32>.size, options: .storageModeShared
    ) else { throw NoiseHarnessError.bufferAllocationFailed }

    // Extra float params (e.g. wetness, VdotH, etc.) up to 8 values.
    var padded = extraParams + [Float](repeating: 0, count: max(0, 8 - extraParams.count))
    guard let paramBuf = device.makeBuffer(
        bytes: &padded, length: 8 * MemoryLayout<Float>.size, options: .storageModeShared
    ) else { throw NoiseHarnessError.bufferAllocationFailed }

    // Output buffer: count * kMaterialOutputStride floats.
    guard let outputBuf = device.makeBuffer(
        length: outCount * MemoryLayout<Float>.size, options: .storageModeShared
    ) else { throw NoiseHarnessError.bufferAllocationFailed }

    guard let queue = device.makeCommandQueue(),
          let cmd   = queue.makeCommandBuffer(),
          let enc   = cmd.makeComputeCommandEncoder()
    else { throw NoiseHarnessError.commandBufferFailed }

    enc.setComputePipelineState(pipeline)
    enc.setBuffer(positionBuf, offset: 0, index: 10)
    enc.setBuffer(idBuf,       offset: 0, index: 11)
    enc.setBuffer(paramBuf,    offset: 0, index: 12)
    enc.setBuffer(outputBuf,   offset: 0, index: 13)

    let gridSize = MTLSize(width: count, height: 1, depth: 1)
    let tgSize   = MTLSize(width: min(pipeline.maxTotalThreadsPerThreadgroup, count), height: 1, depth: 1)
    enc.dispatchThreads(gridSize, threadsPerThreadgroup: tgSize)
    enc.endEncoding()

    cmd.commit()
    cmd.waitUntilCompleted()
    guard cmd.status == .completed else { throw NoiseHarnessError.renderFailed }

    let ptr = outputBuf.contents().bindMemory(to: Float.self, capacity: outCount)
    let raw = Array(UnsafeBufferPointer(start: ptr, count: outCount))

    return (0..<count).map { i in
        let b = i * kMaterialOutputStride
        return MaterialResultSwift(
            albedo:    SIMD3<Float>(raw[b],   raw[b+1], raw[b+2]),
            roughness:  raw[b+3],
            metallic:   raw[b+4],
            normal:    SIMD3<Float>(raw[b+5], raw[b+6], raw[b+7]),
            emission:  SIMD3<Float>(raw[b+8], raw[b+9], raw[b+10])
        )
    }
}

// MARK: - Standard sample positions

/// 32 uniformly-distributed points on a unit sphere for material tests.
/// Generated via Fibonacci lattice for even coverage.
let materialTestPositions: [SIMD3<Float>] = {
    let n = 32
    let phi = Float.pi * (3.0 - sqrt(5.0))
    return (0..<n).map { i in
        let y     = 1.0 - (Float(i) / Float(n - 1)) * 2.0
        let r     = sqrt(max(0, 1.0 - y * y))
        let theta = phi * Float(i)
        return SIMD3<Float>(r * cos(theta), y, r * sin(theta))
    }
}()

// MARK: - Kernel source

// Material IDs used by the dispatch kernel.
enum MaterialID: Int {
    case polishedChrome   = 0
    case brushedAluminum  = 1
    case gold             = 2
    case copper           = 3
    case ferrofluid       = 4
    case ceramic          = 5
    case frostedGlass     = 6
    case wetStone         = 7
    case bark             = 8
    case leaf             = 9
    case silkThread       = 10
    case chitin           = 11
    case ocean            = 12
    case ink              = 13
    case marble           = 14
    case granite          = 15
    // V.4 additions
    case velvet           = 16
    case sandGlints       = 17
    case concrete         = 18
}

private func makeMaterialDispatchKernel() -> String {
    // This kernel dispatches to the cookbook material under test via a switch.
    // MaterialResult is written to a flat float array (kMaterialOutputStride floats/sample).
    // Standard lighting: key light from (1,1,1) normalized, view from (0,0,-1).
    return """

    kernel void material_test_kernel(
        constant float4*  positions [[buffer(10)]],
        constant uint*    materialID [[buffer(11)]],
        constant float*   params    [[buffer(12)]],
        device   float*   outputs   [[buffer(13)]],
        uint tid [[thread_position_in_grid]])
    {
        float3 wp = positions[tid].xyz;
        float3 n  = normalize(wp);   // sphere: normal = position

        // Standard lighting parameters for all materials.
        float3 L   = normalize(float3(1.0, 1.0, 1.0));   // key light direction
        float3 V   = float3(0.0, 0.0, -1.0);             // view direction
        float3 H   = normalize(L + V);
        float  NdotV  = max(0.0, dot(n, V));
        float  VdotH  = max(0.0, dot(V, H));

        // Extra params: params[0]=wetness, params[1]=depth, params[2]=thickness_nm, params[3]=ao
        float wetness      = params[0];
        float depth        = max(0.001, params[1]);
        float thickness_nm = max(150.0, params[2]);
        float ao           = params[3];

        MaterialResult m = material_default(n);

        uint mid = *materialID;
        if (mid == 0) { m = mat_polished_chrome(wp, n); }
        else if (mid == 1) {
            m = mat_brushed_aluminum(wp, n, float3(1, 0, 0));
        }
        else if (mid == 2) { m = mat_gold(wp, n); }
        else if (mid == 3) { m = mat_copper(wp, n, ao); }
        else if (mid == 4) { m = mat_ferrofluid(wp, n); }
        else if (mid == 5) { m = mat_ceramic(wp, n, float3(0.8, 0.2, 0.1)); }
        else if (mid == 6) { m = mat_frosted_glass(wp, n); }
        else if (mid == 7) { m = mat_wet_stone(wp, n, wetness); }
        else if (mid == 8) { m = mat_bark(wp, n, float3(0, 1, 0)); }
        else if (mid == 9) { m = mat_leaf(wp, n, V, L); }
        else if (mid == 10) {
            FiberParams fp;
            fp.fiber_tangent  = float3(1, 0, 0);
            fp.fiber_normal   = n;
            fp.azimuthal_r    = 0.15;
            fp.azimuthal_tt   = 0.5;
            fp.absorption     = 0.1;
            fp.tint           = float3(0.95, 0.95, 0.95);
            m = mat_silk_thread(wp, fp, L, V);
        }
        else if (mid == 11) { m = mat_chitin(wp, n, VdotH, NdotV, thickness_nm); }
        else if (mid == 12) { m = mat_ocean(wp, n, NdotV, depth); }
        else if (mid == 13) { m = mat_ink(wp, n, float3(0.1, 0.2, 0.8), wp.xy, 0.0); }
        else if (mid == 14) { m = mat_marble(wp, n); }
        else if (mid == 15) { m = mat_granite(wp, n); }
        else if (mid == 16) { m = mat_velvet(wp, n, float3(0.6, 0.1, 0.2), NdotV); }
        else if (mid == 17) { m = mat_sand_glints(wp, n); }
        else if (mid == 18) { m = mat_concrete(wp, n); }

        int b = tid * 11;
        outputs[b + 0] = m.albedo.x;
        outputs[b + 1] = m.albedo.y;
        outputs[b + 2] = m.albedo.z;
        outputs[b + 3] = m.roughness;
        outputs[b + 4] = m.metallic;
        outputs[b + 5] = m.normal.x;
        outputs[b + 6] = m.normal.y;
        outputs[b + 7] = m.normal.z;
        outputs[b + 8] = m.emission.x;
        outputs[b + 9] = m.emission.y;
        outputs[b + 10] = m.emission.z;
    }
    """
}

// MARK: - Validation helpers

/// Check that all MaterialResult fields are finite (no NaN / Inf).
func assertMaterialFinite(_ results: [MaterialResultSwift]) throws {
    for m in results {
        let vals: [Float] = [
            m.albedo.x, m.albedo.y, m.albedo.z,
            m.roughness, m.metallic,
            m.normal.x, m.normal.y, m.normal.z,
            m.emission.x, m.emission.y, m.emission.z
        ]
        for v in vals {
            if !v.isFinite {
                throw NoiseHarnessError.renderFailed
            }
        }
    }
}

/// Compute average of albedo.x across all samples.
func avgAlbedoR(_ results: [MaterialResultSwift]) -> Float {
    results.reduce(0.0) { $0 + $1.albedo.x } / Float(results.count)
}
func avgAlbedoG(_ results: [MaterialResultSwift]) -> Float {
    results.reduce(0.0) { $0 + $1.albedo.y } / Float(results.count)
}
func avgAlbedoB(_ results: [MaterialResultSwift]) -> Float {
    results.reduce(0.0) { $0 + $1.albedo.z } / Float(results.count)
}
func avgEmissionR(_ results: [MaterialResultSwift]) -> Float {
    results.reduce(0.0) { $0 + $1.emission.x } / Float(results.count)
}
func avgMetallic(_ results: [MaterialResultSwift]) -> Float {
    results.reduce(0.0) { $0 + $1.metallic } / Float(results.count)
}
func avgRoughness(_ results: [MaterialResultSwift]) -> Float {
    results.reduce(0.0) { $0 + $1.roughness } / Float(results.count)
}
