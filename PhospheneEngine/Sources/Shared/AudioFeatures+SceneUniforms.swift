// AudioFeatures+SceneUniforms — Camera, lighting, and scene parameters for ray march presets.
//
// Uploaded to the GPU as buffer(4) in the G-buffer and lighting passes.
// Layout must match the `SceneUniforms` MSL struct in Common.metal and in the
// preset shader preamble — identical float4 field ordering, 128 bytes total.
//
// All fields use SIMD4<Float> to guarantee unambiguous 16-byte alignment in both
// Swift and Metal, avoiding the packed_float3 vs SIMD3<Float> size mismatch
// documented in RayIntersector+Internal.swift.

import simd

// MARK: - SceneUniforms

/// Camera, lighting, and scene parameters for deferred ray march shader passes.
///
/// Uploaded to the GPU at `buffer(4)` in the G-buffer pass and lighting pass.
/// The MSL `SceneUniforms` struct in `Common.metal` and the preset preamble must
/// have the identical layout.  All fields are `SIMD4<Float>` (16 bytes each) to
/// avoid `float3` vs `SIMD3<Float>` size ambiguity.
///
/// Layout (128 bytes = 8 × float4):
/// ```
/// [0]  cameraOriginAndFov     xyz = world-space camera position, w = vertical fov (radians)
/// [1]  cameraForward          xyz = normalized forward direction, w = 0
/// [2]  cameraRight            xyz = normalized right direction, w = 0
/// [3]  cameraUp               xyz = normalized up direction, w = 0
/// [4]  lightPositionAndIntensity  xyz = world-space light position, w = intensity
/// [5]  lightColor             xyz = linear RGB light colour, w = 0
/// [6]  sceneParamsA           x = audioTime, y = aspectRatio, z = nearPlane, w = farPlane
/// [7]  sceneParamsB           x = fogNear, y = fogFar, zw = reserved (0)
/// ```
@frozen
public struct SceneUniforms: Sendable {

    // MARK: Camera (64 bytes)

    /// xyz = world-space camera position; w = vertical field of view in radians.
    public var cameraOriginAndFov: SIMD4<Float>

    /// xyz = normalized camera forward direction; w = 0.
    public var cameraForward: SIMD4<Float>

    /// xyz = normalized camera right direction; w = 0.
    public var cameraRight: SIMD4<Float>

    /// xyz = normalized camera up direction; w = 0.
    public var cameraUp: SIMD4<Float>

    // MARK: Lighting (32 bytes)

    /// xyz = world-space position of the primary point light; w = intensity multiplier.
    public var lightPositionAndIntensity: SIMD4<Float>

    /// xyz = linear-RGB colour of the primary light; w = 0.
    public var lightColor: SIMD4<Float>

    // MARK: Scene Parameters (32 bytes)

    /// x = accumulated audio time; y = framebuffer aspect ratio (width/height);
    /// z = ray march near-plane distance; w = ray march far-plane / max distance.
    public var sceneParamsA: SIMD4<Float>

    /// x = fog start distance; y = fog end distance (fully opaque beyond this); zw = 0.
    public var sceneParamsB: SIMD4<Float>

    // MARK: Convenience Accessors

    /// World-space camera position.
    public var cameraPos: SIMD3<Float> {
        get { SIMD3(cameraOriginAndFov.x, cameraOriginAndFov.y, cameraOriginAndFov.z) }
        set { cameraOriginAndFov = SIMD4(newValue.x, newValue.y, newValue.z, cameraOriginAndFov.w) }
    }

    /// Vertical field of view in radians.
    public var cameraFov: Float {
        get { cameraOriginAndFov.w }
        set { cameraOriginAndFov.w = newValue }
    }

    /// World-space position of the primary point light.
    public var lightPos: SIMD3<Float> {
        get { SIMD3(lightPositionAndIntensity.x, lightPositionAndIntensity.y, lightPositionAndIntensity.z) }
        set { lightPositionAndIntensity = SIMD4(newValue.x, newValue.y, newValue.z, lightPositionAndIntensity.w) }
    }

    /// Primary light intensity multiplier.
    public var lightIntensity: Float {
        get { lightPositionAndIntensity.w }
        set { lightPositionAndIntensity.w = newValue }
    }

    /// Accumulated audio time (energy-weighted, reset on track change).
    public var audioTime: Float {
        get { sceneParamsA.x }
        set { sceneParamsA.x = newValue }
    }

    /// Framebuffer aspect ratio (width / height).
    public var aspectRatio: Float {
        get { sceneParamsA.y }
        set { sceneParamsA.y = newValue }
    }

    /// Ray march near-plane distance.
    public var nearPlane: Float {
        get { sceneParamsA.z }
        set { sceneParamsA.z = newValue }
    }

    /// Ray march far-plane / maximum march distance.
    public var farPlane: Float {
        get { sceneParamsA.w }
        set { sceneParamsA.w = newValue }
    }

    // MARK: Init

    /// Create `SceneUniforms` with a default orbit camera and a single overhead-side light.
    ///
    /// Defaults: camera at (0, 0, -5) looking along +Z, light at (3, 8, -3) with white colour.
    /// `audioTime` and `aspectRatio` are set to 0 and 16/9 respectively; update them each
    /// frame from the render loop before uploading.
    public init(
        cameraPos: SIMD3<Float> = SIMD3(0, 0, -5),
        cameraFov: Float = .pi / 4.0,
        cameraForward: SIMD3<Float> = SIMD3(0, 0, 1),
        cameraRight: SIMD3<Float> = SIMD3(1, 0, 0),
        cameraUp: SIMD3<Float> = SIMD3(0, 1, 0),
        lightPos: SIMD3<Float> = SIMD3(3, 8, -3),
        lightIntensity: Float = 5.0,
        lightColor: SIMD3<Float> = SIMD3(1, 1, 1),
        audioTime: Float = 0,
        aspectRatio: Float = 16.0 / 9.0,
        nearPlane: Float = 0.1,
        farPlane: Float = 30.0,
        fogNear: Float = 20.0,
        fogFar: Float = 30.0
    ) {
        self.cameraOriginAndFov = SIMD4(cameraPos.x, cameraPos.y, cameraPos.z, cameraFov)
        self.cameraForward = SIMD4(cameraForward.x, cameraForward.y, cameraForward.z, 0)
        self.cameraRight = SIMD4(cameraRight.x, cameraRight.y, cameraRight.z, 0)
        self.cameraUp = SIMD4(cameraUp.x, cameraUp.y, cameraUp.z, 0)
        self.lightPositionAndIntensity = SIMD4(lightPos.x, lightPos.y, lightPos.z, lightIntensity)
        self.lightColor = SIMD4(lightColor.x, lightColor.y, lightColor.z, 0)
        self.sceneParamsA = SIMD4(audioTime, aspectRatio, nearPlane, farPlane)
        self.sceneParamsB = SIMD4(fogNear, fogFar, 0, 0)
    }
}
