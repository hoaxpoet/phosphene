// StageRigState — Shared Swift mirror of the MSL `StageRigState` struct.
//
// Byte-identical to the matching MSL struct declared in:
//   - `PhospheneEngine/Sources/Renderer/Shaders/Common.metal` (Renderer library)
//   - `PhospheneEngine/Sources/Presets/PresetLoader+Preamble.swift`
//     (`rayMarchGBufferPreamble`)
//
// Bound at fragment slot 9 of BOTH the ray-march G-buffer pass and the
// ray-march lighting pass for every ray-march preset. Presets that adopt
// `SHADER_CRAFT.md §5.8` (currently Ferrofluid Ocean — V.9 Session 3)
// instantiate a per-preset Swift state class (`FerrofluidStageRig`) that
// owns a 208-byte UMA `MTLBuffer` storing this struct. All other ray-march
// presets receive `RayMarchPipeline.stageRigPlaceholderBuffer` (zero-filled
// 208-byte buffer) so the preamble's `[[buffer(9)]] constant StageRigState&`
// declaration is always satisfied — same pattern as
// `RayMarchPipeline.lumenPlaceholderBuffer` (slot 8, D-LM-buffer-slot-8).
//
// Layout (208 bytes, 16-byte aligned per D-125(c)):
//   16 B   header — activeLightCount (uint) + 12 B padding
//   192 B  lights[6] — each `StageRigLight` is 32 B (float4 + float4)
//
// Layout regression-locked by:
//   - `StageRigStateLayoutTests.test_stageRigState_strideIs208`
//   - `StageRigStateLayoutTests.test_stageRigLight_strideIs32`
//
// Same pattern as `LumenPatternState` (Lumen Mosaic Phase LM.2): keep the
// Swift size assertion colocated with the MSL declaration so they cannot
// drift silently.

import Foundation

// MARK: - StageRigLight (32 bytes)

/// One animated colored light in the §5.8 stage-rig.
///
/// Layout: 2 × float4 = 32 bytes. Individual fields are SIMD-typed so Metal's
/// 16-byte alignment for `float4` matches naturally — no explicit padding.
///
/// `positionAndIntensity.xyz` is the world-space light position. `.w` is the
/// linear-space intensity scalar — `0` means "inactive" (the matID == 2
/// branch in `raymarch_lighting_fragment` short-circuits and skips
/// per-light evaluation when `i >= activeLightCount`, but the convention is
/// also enforced inline so deactivated lights inside the active count still
/// produce zero contribution).
///
/// `color.xyz` is the linear-RGB light colour. `.w` is currently reserved
/// (zero) — future Sessions may use it for per-light angular falloff or
/// per-light beam-width parameters.
@frozen
public struct StageRigLight: Sendable, Equatable {
    /// xyz = world-space position, w = intensity scalar.
    public var positionAndIntensity: SIMD4<Float>
    /// xyz = linear RGB, w = 0 (reserved).
    public var color: SIMD4<Float>

    public init(
        positionAndIntensity: SIMD4<Float> = .zero,
        color: SIMD4<Float> = .zero
    ) {
        self.positionAndIntensity = positionAndIntensity
        self.color = color
    }

    public static let zero = StageRigLight()
}

// MARK: - StageRigState (208 bytes)

/// Per-frame snapshot of the §5.8 stage-rig.
///
/// Bound at fragment slot 9 of the ray-march pipeline. Read by the
/// `matID == 2` branch in `raymarch_lighting_fragment` (RayMarch.metal):
///
/// ```metal
/// for (uint i = 0; i < stageRig.activeLightCount; i++) {
///     // accumulate Cook-Torrance contribution per light
/// }
/// ```
///
/// `activeLightCount` is clamped to `[0, 6]` at construction. JSON-side
/// validation in `PresetDescriptor.StageRig` clamps `light_count` to
/// `[3, 6]`; the Swift mirror permits `0` so the zero-filled placeholder
/// buffer renders as "no direct light contribution" (matID == 2 still
/// dispatches but the per-light loop body never executes).
///
/// Layout matches the MSL struct in `Common.metal` (Renderer library) and
/// `rayMarchGBufferPreamble` (preset shader compilation):
///
/// ```msl
/// struct StageRigLight {
///     float4 positionAndIntensity;
///     float4 color;
/// };
///
/// struct StageRigState {
///     uint   activeLightCount;
///     uint   _pad0;
///     float2 _pad1;
///     StageRigLight lights[6];
/// };
/// ```
@frozen
public struct StageRigState: Sendable {
    /// Number of active lights in `lights`. Clamped `[0, 6]`.
    public var activeLightCount: UInt32
    /// Padding to satisfy 16-byte alignment before `lights[0]`.
    public var _pad0: UInt32
    /// Padding to satisfy 16-byte alignment before `lights[0]`.
    public var _pad1: SIMD2<Float>
    /// Up to 6 animated stage-rig lights. Entries past `activeLightCount`
    /// must be ignored by the shader. Stored as a fixed-size tuple rather
    /// than a Swift array so the layout is inline (no heap indirection),
    /// matching the MSL `lights[6]` declaration byte-for-byte.
    public var lights: (
        StageRigLight, StageRigLight, StageRigLight,
        StageRigLight, StageRigLight, StageRigLight
    )

    public init(
        activeLightCount: UInt32 = 0,
        lights: (
            StageRigLight, StageRigLight, StageRigLight,
            StageRigLight, StageRigLight, StageRigLight
        ) = (.zero, .zero, .zero, .zero, .zero, .zero)
    ) {
        self.activeLightCount = min(activeLightCount, 6)
        self._pad0 = 0
        self._pad1 = .zero
        self.lights = lights
    }

    /// Indexed read access. Returns `.zero` for out-of-range indices so
    /// callers don't have to bounds-check.
    public func light(at index: Int) -> StageRigLight {
        switch index {
        case 0: return lights.0
        case 1: return lights.1
        case 2: return lights.2
        case 3: return lights.3
        case 4: return lights.4
        case 5: return lights.5
        default: return .zero
        }
    }

    /// Indexed write access. Out-of-range indices are silently ignored
    /// (mirrors the read accessor's clamp).
    public mutating func setLight(at index: Int, _ light: StageRigLight) {
        switch index {
        case 0: lights.0 = light
        case 1: lights.1 = light
        case 2: lights.2 = light
        case 3: lights.3 = light
        case 4: lights.4 = light
        case 5: lights.5 = light
        default: break
        }
    }

    public static let zero = StageRigState()

    /// Public read-only view of the underlying tuple as an array. Useful for
    /// test fixtures and diagnostic dumps that prefer array iteration.
    public var lightArray: [StageRigLight] {
        [lights.0, lights.1, lights.2, lights.3, lights.4, lights.5]
    }
}

