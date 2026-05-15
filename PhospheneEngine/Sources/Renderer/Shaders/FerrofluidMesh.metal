// FerrofluidMesh.metal — Mesh + vertex-displacement G-buffer path for Ferrofluid Ocean.
//
// V.9 Session 4.5c Phase 1 round 12 (Step B): replaces the SDF ray-march
// path for Ferrofluid Ocean only. Tessellated quad mesh covers the world
// patch; the vertex stage samples the baked spike heightmap and displaces
// each vertex along +Y; the fragment stage outputs the G-buffer in the
// same format the existing `raymarch_lighting_fragment` reads — so the
// existing matID == 2 Leitl four-layer material path runs unchanged.
//
// Architectural parity with Leitl's `spikes.vert.glsl`:
//   - 256×256 tessellated plane covering the world patch
//   - Heightmap sample at vertex UV → vertex Y displacement
//   - Normal via cross product of finite-differenced neighbor positions
//     (matches Leitl's `cross(t-p, p-b)` recipe)
//
// Differences from SDF path:
//   - No ray march. Rasterization fills pixels from displaced triangles.
//   - No `sceneSDF`. Heightmap is the only geometry source.
//   - No central-differences normal in fragment. Normal comes from vertex
//     stage cross product, interpolated by rasterizer.
//   - No AO (set to 1.0). Could add later if visible occlusion needed.

#include <metal_stdlib>
using namespace metal;

// Common.metal is concatenated before this file by ShaderLibrary's
// alphabetical sort — FeatureVector / StemFeatures / SceneUniforms are
// in scope without an explicit `#include`.

// MARK: - Vertex IO

/// Mesh vertex input. Each vertex carries its local-XZ position (Y=0 before
/// displacement) and a UV that addresses the heightmap. `FerrofluidMesh.swift`
/// generates these in a regular grid covering the world patch.
struct FerrofluidMeshVertex {
    float3 position [[attribute(0)]];   // (x, 0, z) in world space pre-displacement
    float2 uv       [[attribute(1)]];   // [0, 1] addressing the heightmap
};

/// Interpolated outputs from vertex → fragment. Worldpos + normal are
/// needed by the fragment for G-buffer output; depth is computed from
/// the rasterizer's clip-space position.
struct FerrofluidMeshVaryings {
    float4 clipPosition [[position]];
    float3 worldPosition;
    float3 worldNormal;
};

// MARK: - Per-frame vertex uniforms (Phase 1 round 20)
//
// `FerrofluidMeshUniforms` carries the live BPM-derived tempo scale
// from CPU → vertex stage. `tempoScale = bpm / 60` (beats per second).
// Multiplied by `features.accumulated_audio_time` gives "beats since
// song start" — used by the Gerstner phase advance to tie wave motion
// to musical tempo rather than wall-clock seconds. At true silence or
// pre-grid-lock state `tempoScale = 0` so waves freeze (combined with
// the amplitude `presenceGate` which also zeroes at silence).

struct FerrofluidMeshUniforms {
    float tempoScale;       // bpm / 60  (beats per second)
    float _pad0;
    float _pad1;
    float _pad2;
};

// MARK: - Spike strength (Phase 1 round 20: audio coupling deprecated)
//
// `2026-05-15T16-02-12Z` review (Matt): "The movement of the spikes
// with the beat effectively obscures any perceptible wavelike movement
// of the surface ... I worry we already have too much going on between
// the undulation of the surface through waves and the spiking of
// spikes to the beat."
//
// Two motion systems were competing for visual attention; spikes-on-
// beat won because it's more dramatic per-frame. Round 20 deprecates
// spike audio coupling — the spike lattice's role is now "surface
// texture identifying the substrate as ferrofluid," not "music
// response per-beat." Music response moves to Gerstner amplitude +
// drum-pump amplitude swell + tempo-driven wave propagation.
//
// Constant 2.0 matches the round-16 modal spike strength (slight
// majority of frames at typical music). Height at the round-17
// configuration: 2.0 × `kFerrofluidMeshHeightFactor` (0.15) = 0.30 wu.
// Aspect at `spikeBaseRadius = 0.17`: 1.76 : 1. Same value applied at
// silence and music peak — no per-beat variation.
constant float kFerrofluidSpikeStrength = 2.0;

// MARK: - Constants

/// World-space height factor — multiplies the [0, 1] heightmap sample
/// times spike_strength. Mirrors `fo_ferrofluid_field_sampled`'s
/// `* 0.15` constant so the mesh path produces the same spike heights
/// the prior SDF path produced at the same spike_strength.
constant float kFerrofluidMeshHeightFactor = 0.15;

/// Heightmap UV epsilon for neighbor sampling in the normal computation.
/// 1.0 / mesh-segments-per-side. Matches one mesh-segment world distance,
/// so the computed normal is consistent with the rasterized triangle's
/// orientation. (256 segments → 1/256 ≈ 0.0039)
constant float kFerrofluidMeshNormalEps = 0.00390625;

/// World span the heightmap covers, in X and Z. Must match
/// `FerrofluidParticles.worldSpan` (20.0) — used to convert UV-space
/// derivatives to world-space tangent lengths.
constant float kFerrofluidMeshWorldSpan = 20.0;

// MARK: - Gerstner ocean displacement (Phase 1 round 21, 2026-05-15)
//
// Bar-locked Gerstner waves. Round 20 tied wave phase to individual
// beats (per-wave beatsPerCycle 2/3/2/4) — Matt's `2026-05-15T16-35-17Z`
// review: "too active for Love Rehab and chaotic for the 7/4 rhythm
// of Money. ... The waves fire on the first beat of a new bar, so
// once per bar." Per-beat coupling produced restless motion that
// competed with the music's bar-level structure on calm tracks and
// clashed with odd time signatures.
//
// Round 21 locks all four waves to one cycle per bar. CPU passes
// `tempoScale = bpm / 60` via FerrofluidMeshUniforms; the vertex
// shader reads `features.beatsPerBar` directly (defaults to 4 in the
// MIRPipeline; updates to the track's time signature when a BeatGrid
// is installed — Money's 7/4 → beatsPerBar=7, bar duration
// 7×60/123 = 3.41 s; Love Rehab's 4/4 → beatsPerBar=4, bar duration
// 4×60/118 = 2.03 s).
//
// All four waves share the same bar-locked rate. Visual variation
// comes from spatial axes — different directions, wavelengths, and
// amplitudes — not from temporal rate offsets. At any given world
// position the four waves still interfere because they hit that
// position at different phases (depending on direction · position).
//
// Audio coupling (unchanged from round 20):
//   amplitudeMul = presenceGate × (0.7 + 0.3·arousal + 0.5·drums_dev)
//   tempoScale   = bpm / 60 (CPU-passed; 0 at silence / pre-lock)
//
// At silence: tempoScale = 0 → musicBars = 0 → wave phase frozen;
// presenceGate also = 0 → amplitudeMul = 0 → substrate flat.

constant int kGerstnerNumWaves = 4;

struct GerstnerWaveParams {
    float2 direction;       // unit vector in XZ
    float wavelength;       // world units
    float baseAmplitude;    // world units (before audio modulation)
};

constant GerstnerWaveParams kGerstnerWaves[kGerstnerNumWaves] = {
    // Primary: toward camera (+Z), longest wavelength, dominant amplitude.
    { float2(0.0, 1.0),        12.0, 0.20 },
    // Slight right-toward-camera offset (~17° from primary).
    { float2(0.2873, 0.9579),   8.0, 0.16 },
    // Slight left-toward-camera offset (~22° from primary).
    { float2(-0.3939, 0.9191), 10.0, 0.14 },
    // More perpendicular, shorter wavelength — surface chop.
    { float2(0.8321, 0.5547),   6.0, 0.10 }
};

/// Gerstner horizontal-sway factor (Q in Tessendorf's notation). 0 =
/// pure sinusoidal Y-displacement (no horizontal motion); 1 = maximum
/// circular orbit (risks wave-tip overlap for high amplitudes). 0.3 is
/// conservative — gives visible crest-rolling character without
/// fold-over even with all 4 waves at constructive peak.
constant float kGerstnerSteepness = 0.3;

/// Compute Gerstner displacement at world-XZ position `p` at
/// `musicBars` of music time (= `accumulated_audio_time × tempoScale
/// / beatsPerBar`). Each wave advances one full cycle per bar.
/// Returns float3 (dx, dy, dz) to add to the un-displaced vertex
/// position. `amplitudeMul` scales all wave amplitudes uniformly.
static float3 gerstner_displacement(float2 p,
                                     float musicBars,
                                     float amplitudeMul) {
    float3 disp = float3(0.0);
    for (int i = 0; i < kGerstnerNumWaves; i++) {
        float2 D = kGerstnerWaves[i].direction;
        float k = 2.0 * M_PI_F / kGerstnerWaves[i].wavelength;
        float A = kGerstnerWaves[i].baseAmplitude * amplitudeMul;
        // Phase advance: 2π per bar (one wave cycle per bar).
        float phaseAdvance = 2.0 * M_PI_F * musicBars;
        float phase = k * dot(D, p) - phaseAdvance;
        float cosP = cos(phase);
        float sinP = sin(phase);
        disp.x += kGerstnerSteepness * A * D.x * cosP;
        disp.y += A * sinP;
        disp.z += kGerstnerSteepness * A * D.y * cosP;
    }
    return disp;
}

// MARK: - Vertex shader

/// Sample the heightmap at `uv`, return world-space Y displacement
/// scaled by `spike_strength`. Clamp-to-zero address mode (set on the
/// sampler in Swift) → vertices outside the heightmap patch get zero
/// displacement (flat substrate at the edges).
static inline float fmesh_sample_height(texture2d<float> heightTex,
                                         sampler heightSamp,
                                         float2 uv,
                                         float spikeStrength) {
    float h = heightTex.sample(heightSamp, uv).r;
    return h * spikeStrength * kFerrofluidMeshHeightFactor;
}

vertex FerrofluidMeshVaryings ferrofluid_mesh_vertex(
    FerrofluidMeshVertex in        [[stage_in]],
    constant FeatureVector& features [[buffer(0)]],
    constant StemFeatures&  stems    [[buffer(3)]],
    constant SceneUniforms& scene    [[buffer(4)]],
    constant FerrofluidMeshUniforms& meshUniforms [[buffer(5)]],
    texture2d<float>        heightTex [[texture(10)]]
) {
    constexpr sampler heightSamp(coord::normalized,
                                  filter::linear,
                                  address::clamp_to_zero);

    // Round 20: spike audio coupling deprecated. Spike strength is now
    // a constant (`kFerrofluidSpikeStrength`); music response lives
    // entirely in the Gerstner wave amplitude + tempo-driven motion.
    float spikeStr = kFerrofluidSpikeStrength;

    // ── Gerstner audio modulation (Phase 1 round 20) ───────────────
    float arousalClamped = clamp(features.arousal, 0.0, 1.0);
    float drumsClamped   = max(0.0, stems.drums_energy_dev);
    float totalStemEnergy = stems.vocals_energy + stems.drums_energy
                          + stems.bass_energy + stems.other_energy;
    float presenceGate = smoothstep(0.02, 0.10, totalStemEnergy);
    float amplitudeMul = presenceGate
                       * (0.7 + 0.3 * arousalClamped + 0.5 * drumsClamped);

    // Music time in bars: 0 when paused or pre-grid-lock (tempoScale=0
    // or accumulated_audio_time=0). When music plays, this increments
    // at one unit per bar — `(tempoScale / beatsPerBar)` bars per
    // second. Each wave advances one full cycle per bar.
    //
    // `features.beats_per_bar` defaults to 4 (MIRPipeline) and updates
    // to the track's time signature when a BeatGrid is installed
    // (Money's 7/4 → 7; Love Rehab's 4/4 → 4). Clamped with
    // `max(1, …)` defensively in case a malformed value reaches the
    // shader.
    float musicBeats = features.accumulated_audio_time * meshUniforms.tempoScale;
    float beatsPerBar = max(1.0, features.beats_per_bar);
    float musicBars = musicBeats / beatsPerBar;

    // World-space epsilon for neighbour sampling (single mesh segment).
    float worldEps = kFerrofluidMeshNormalEps * kFerrofluidMeshWorldSpan;

    // ── Spike heightmap samples (one centre + 4 neighbours) ────────
    // Centre drives the vertex's own Y; neighbours feed the normal.
    float yCenter_spike = fmesh_sample_height(heightTex, heightSamp,
                                               in.uv, spikeStr);
    float yRight_spike  = fmesh_sample_height(heightTex, heightSamp,
                                               in.uv + float2(kFerrofluidMeshNormalEps, 0.0),
                                               spikeStr);
    float yLeft_spike   = fmesh_sample_height(heightTex, heightSamp,
                                               in.uv - float2(kFerrofluidMeshNormalEps, 0.0),
                                               spikeStr);
    float yFwd_spike    = fmesh_sample_height(heightTex, heightSamp,
                                               in.uv + float2(0.0, kFerrofluidMeshNormalEps),
                                               spikeStr);
    float yBack_spike   = fmesh_sample_height(heightTex, heightSamp,
                                               in.uv - float2(0.0, kFerrofluidMeshNormalEps),
                                               spikeStr);

    // ── Gerstner samples at matching world-XZ positions ────────────
    // For the CENTRE we use the full 3D displacement (x, y, z) — the
    // vertex shifts horizontally to ride the wave. For neighbours we
    // only need Y for the normal calc (height-field approximation;
    // horizontal Gerstner displacement of neighbours is small relative
    // to wavelength so the slope contribution is negligible).
    float3 gerstnerCentre = gerstner_displacement(in.position.xz,
                                                   musicBars,
                                                   amplitudeMul);
    float yRight_g = gerstner_displacement(in.position.xz + float2(worldEps, 0.0),
                                            musicBars, amplitudeMul).y;
    float yLeft_g  = gerstner_displacement(in.position.xz + float2(-worldEps, 0.0),
                                            musicBars, amplitudeMul).y;
    float yFwd_g   = gerstner_displacement(in.position.xz + float2(0.0, worldEps),
                                            musicBars, amplitudeMul).y;
    float yBack_g  = gerstner_displacement(in.position.xz + float2(0.0, -worldEps),
                                            musicBars, amplitudeMul).y;

    // Combined Y at each sample point — spike lattice rides on top of the
    // Gerstner swell, both contributing to the surface height.
    float yCenter = yCenter_spike + gerstnerCentre.y;
    float yRight  = yRight_spike  + yRight_g;
    float yLeft   = yLeft_spike   + yLeft_g;
    float yFwd    = yFwd_spike    + yFwd_g;
    float yBack   = yBack_spike   + yBack_g;

    // World displacement vector — centre gets the full Gerstner XZ sway
    // in addition to the combined Y.
    float3 displaced = float3(in.position.x + gerstnerCentre.x,
                              in.position.y + yCenter,
                              in.position.z + gerstnerCentre.z);

    // Tangent vectors in world space. UV-space epsilon maps to world-space
    // distance via worldSpan: dWorld = (eps × 2) × worldSpan in the X / Z
    // directions. Heights at ±eps neighbours yield the Y component.
    float3 tangentX = float3(2.0 * worldEps, yRight - yLeft, 0.0);
    float3 tangentZ = float3(0.0, yFwd - yBack, 2.0 * worldEps);

    // Surface normal — cross product, oriented so +Y is "up" for a flat
    // surface. tangentX × tangentZ gives a vector pointing in +Y for the
    // expected winding (right-hand rule with X to the right, Z forward).
    float3 normalWS = normalize(cross(tangentZ, tangentX));

    // Build view-projection from scene uniforms. Phosphene doesn't ship a
    // pre-multiplied view-projection matrix in SceneUniforms; reconstruct
    // from camera basis vectors + FOV. Same math the SDF G-buffer fragment
    // uses to build ray directions, run in reverse to project a world
    // point to clip space.
    float3 camPos = scene.cameraOriginAndFov.xyz;
    float3 camFwd = scene.cameraForward.xyz;
    float3 camRt  = scene.cameraRight.xyz;
    float3 camUp  = scene.cameraUp.xyz;
    float  yFov   = scene.cameraOriginAndFov.w;
    float  nearP  = scene.sceneParamsA.z;
    float  farP   = scene.sceneParamsA.w;
    float  aspect = scene.sceneParamsA.y;

    // Camera-relative vector.
    float3 toPoint = displaced - camPos;

    // Project onto camera basis to get view-space coordinates.
    float viewX = dot(toPoint, camRt);
    float viewY = dot(toPoint, camUp);
    float viewZ = dot(toPoint, camFwd);

    // Standard Metal/D3D perspective projection. Clip-space depth in
    // [0, far] (post-divide [0, 1]). clip.w = viewZ so rasterizer's
    // perspective divide produces correct NDC.
    float tanHalfFov = tan(yFov * 0.5);
    float clipX = viewX / (tanHalfFov * aspect);
    float clipY = viewY / tanHalfFov;
    float clipZ = viewZ * farP / (farP - nearP)
                - farP * nearP / (farP - nearP);
    float clipW = viewZ;

    FerrofluidMeshVaryings out;
    out.clipPosition  = float4(clipX, clipY, clipZ, clipW);
    out.worldPosition = displaced;
    out.worldNormal   = normalWS;
    return out;
}

// MARK: - Fragment shader

/// G-buffer output (same layout as `GBufferOutput` in
/// PresetLoader+Preamble.swift — must stay byte-identical so the
/// existing `raymarch_lighting_fragment` reads correctly).
struct FerrofluidMeshGBufferOutput {
    float4 gbuf0 [[color(0)]];   // (depth, matID, 0, 0) — rg16Float
    float4 gbuf1 [[color(1)]];   // (normal.xyz, AO)     — rgba8Snorm
    float4 gbuf2 [[color(2)]];   // (albedo, packedRM)   — rgba8Unorm
};

fragment FerrofluidMeshGBufferOutput ferrofluid_mesh_gbuffer_fragment(
    FerrofluidMeshVaryings  in    [[stage_in]],
    constant SceneUniforms& scene [[buffer(4)]]
) {
    FerrofluidMeshGBufferOutput out;

    // Depth: normalize view-space Z by far plane to match SDF path's
    // `depthNorm = t / farPlane`. View-Z for this point:
    float3 camPos = scene.cameraOriginAndFov.xyz;
    float3 camFwd = scene.cameraForward.xyz;
    float  farP   = scene.sceneParamsA.w;
    float  viewZ  = dot(in.worldPosition - camPos, camFwd);
    float  depthNorm = clamp(viewZ / farP, 0.0, 0.9999);

    // matID == 2 → routes to Leitl four-layer material in lighting pass.
    out.gbuf0 = float4(depthNorm, 2.0, 0.0, 0.0);

    // Normal (already normalized in vertex stage; rasterizer interpolation
    // can denormalize so renormalize). AO = 1.0 (no occlusion data).
    float3 normal = normalize(in.worldNormal);
    out.gbuf1 = float4(normal, 1.0);

    // Albedo: pitch-black per §4.6 `mat_ferrofluid` recipe — substrate is
    // pure metal, all visible color comes from the env reflection in the
    // matID == 2 lighting branch. Roughness 0.08 + metallic 1.0 packed
    // into the alpha byte per the SDF path's convention.
    constexpr float kFerrofluidAlbedoR = 0.02;
    constexpr float kFerrofluidAlbedoG = 0.03;
    constexpr float kFerrofluidAlbedoB = 0.05;
    constexpr float kFerrofluidRoughness = 0.08;
    constexpr float kFerrofluidMetallic  = 1.0;
    int rByte = int(clamp(kFerrofluidRoughness, 0.0, 1.0) * 15.0 + 0.5);
    int mByte = int(clamp(kFerrofluidMetallic,  0.0, 1.0) * 15.0 + 0.5);
    float packed = float((rByte << 4) | mByte) / 255.0;

    out.gbuf2 = float4(kFerrofluidAlbedoR,
                       kFerrofluidAlbedoG,
                       kFerrofluidAlbedoB,
                       packed);
    return out;
}
