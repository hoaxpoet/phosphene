extension PresetLoader {

    // MARK: - MV-Warp Preamble (MV-2, D-027)

    /// Additional Metal preamble injected when compiling a preset that declares `mv_warp`
    /// in its passes array.
    ///
    /// Contains:
    /// - `MVWarpPerFrame` struct — per-frame warp parameters returned by the preset function.
    /// - `WarpVertexOut` struct — vertex → fragment IO carrying warped UV and decay.
    /// - Forward declarations for preset-defined `mvWarpPerFrame()` and `mvWarpPerVertex()`.
    /// - `mvWarp_vertex` — the 32×24 vertex-grid shader that calls the preset functions.
    /// - `mvWarp_fragment` — samples the previous warp texture at the warped UV × decay.
    /// - `mvWarp_compose_fragment` — additively composites the current scene onto the warp.
    /// - `mvWarp_blit_fragment` — copies the composed warp texture to the drawable.
    ///
    /// Compiled per-preset alongside `sceneSDF`/`sceneMaterial` so that `mvWarp_vertex`
    /// can call the preset's `mvWarpPerFrame` and `mvWarpPerVertex` implementations.
    static let mvWarpPreamble: String = """

    // ── MVWarp preamble (MV-2, D-027) ────────────────────────────────────────
    // Injected only when "mv_warp" is in the preset's passes array.
    // The preset's .metal file must implement mvWarpPerFrame and mvWarpPerVertex.

    // SceneUniforms — defined here for direct (non-ray-march) mv_warp presets.
    // For ray-march mv_warp presets, rayMarchGBufferPreamble defines it first and
    // sets the guard, so this block is skipped to avoid redefinition errors.
    #ifndef SCENE_UNIFORMS_DEFINED
    #define SCENE_UNIFORMS_DEFINED
    struct SceneUniforms {
        float4 cameraOriginAndFov;        // xyz = camera pos, w = fov (radians)
        float4 cameraForward;             // xyz = forward dir, w = 0
        float4 cameraRight;               // xyz = right dir, w = 0
        float4 cameraUp;                  // xyz = up dir, w = 0
        float4 lightPositionAndIntensity; // xyz = light pos, w = intensity
        float4 lightColor;                // xyz = linear RGB, w = 0
        float4 sceneParamsA;              // x=audioTime, y=aspectRatio, z=near, w=far
        float4 sceneParamsB;              // x=fogNear, y=fogFar, zw=reserved
    };
    #endif

    // Per-frame warp parameters returned by the preset's mvWarpPerFrame().
    // All presets in the mv_warp family fill this struct; the vertex shader applies it.
    struct MVWarpPerFrame {
        float zoom;   // multiplicative zoom (1.0 = no change; >1 = zoom in)
        float rot;    // rotation in radians added to the warp grid this frame
        float decay;  // feedback blend weight [0,1] (0.96 = long trails, 0.85 = short)
        float warp;   // global warp-ripple amplitude
        float cx;     // warp centre X offset from screen centre (UV units, 0 = centre)
        float cy;     // warp centre Y offset from screen centre (UV units, 0 = centre)
        float dx;     // per-frame UV X translation
        float dy;     // per-frame UV Y translation
        float sx;     // per-axis scale correction X
        float sy;     // per-axis scale correction Y
        // Preset q-variables — pass per-frame audio data to mvWarpPerVertex.
        float q1; float q2; float q3; float q4;
        float q5; float q6; float q7; float q8;
    };

    // Vertex → fragment IO for the warp pass.
    struct WarpVertexOut {
        float4 position  [[position]]; // NDC screen position
        float2 uv;                     // direct screen UV [0,1]
        float2 warped_uv;              // displaced UV to sample prev frame at
        float  decay;                  // pf.decay, interpolated across the grid
    };

    // ── Sampler for warp texture reads (clamp-to-edge to avoid border wrap) ──
    constexpr sampler warpSampler(filter::linear, address::clamp_to_edge);

    // ── Per-preset forward declarations ──────────────────────────────────────
    // The preset .metal file MUST define both of these functions.

    /// Returns per-frame baseline warp parameters from live audio features.
    /// Called once per frame from `mvWarp_vertex` for every vertex in the grid.
    MVWarpPerFrame mvWarpPerFrame(constant FeatureVector& f,
                                  constant StemFeatures&  stems,
                                  constant SceneUniforms& s);

    /// Per-vertex UV displacement on top of the baseline rotation/zoom/translation.
    /// `uv`  — this vertex's screen UV [0,1].
    /// `rad` — radial distance from the warp centre (0 at centre, ~1 at corners).
    /// `ang` — polar angle from the warp centre (atan2).
    /// Returns the warped UV to sample the previous frame at.
    float2 mvWarpPerVertex(float2 uv, float rad, float ang,
                           thread const MVWarpPerFrame& pf,
                           constant FeatureVector& f,
                           constant StemFeatures& stems);

    // ── mvWarp_vertex ─────────────────────────────────────────────────────────
    // 32×24 vertex grid (31×23 quads = 1426 triangles = 4278 vertices, triangle list).
    // Each vertex computes a per-vertex warped UV by calling the preset functions.
    // Buffer layout (matches engine convention):
    //   buffer(0) = FeatureVector
    //   buffer(1) = StemFeatures
    //   buffer(2) = SceneUniforms (optional per-preset use in mvWarpPerFrame)
    vertex WarpVertexOut mvWarp_vertex(
        uint                    vid      [[vertex_id]],
        constant FeatureVector& features [[buffer(0)]],
        constant StemFeatures&  stems    [[buffer(1)]],
        constant SceneUniforms& scene    [[buffer(2)]]
    ) {
        // Reconstruct grid cell + corner from vertex id.
        // 6 vertices per quad (triangle list):
        //   0:(0,0) 1:(1,0) 2:(0,1)   3:(1,0) 4:(1,1) 5:(0,1)
        const uint2 qoffsets[6] = {
            {0,0},{1,0},{0,1}, {1,0},{1,1},{0,1}
        };
        uint quad_idx    = vid / 6;
        uint vert_in_quad = vid % 6;
        uint col = quad_idx % 31;  // 0..30 (31 quads wide)
        uint row = quad_idx / 31;  // 0..22 (23 quads tall)
        uint2 corner = uint2(col, row) + qoffsets[vert_in_quad];

        // UV: corner / (32 vertices - 1) gives exact 0..1 range.
        float2 uv = float2(float(corner.x) / 31.0,
                           float(corner.y) / 23.0);

        // Per-frame parameters from the preset (same for all vertices in this draw call).
        MVWarpPerFrame pf = mvWarpPerFrame(features, stems, scene);

        // Warp centre in UV space.
        float2 centre = float2(0.5 + pf.cx, 0.5 + pf.cy);
        float2 p      = uv - centre;
        float  rad    = length(p) * 2.0;
        float  ang    = atan2(p.y, p.x);

        // Per-vertex warped UV (preset defines the shape of the warp field).
        float2 warped_uv = mvWarpPerVertex(uv, rad, ang, pf, features, stems);

        // Screen position: UV → NDC (flip Y for Metal top-left origin).
        float4 ndcPos = float4(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0, 0.0, 1.0);

        WarpVertexOut out;
        out.position  = ndcPos;
        out.uv        = uv;
        out.warped_uv = warped_uv;
        out.decay     = pf.decay;
        return out;
    }

    // ── mvWarp_fragment ───────────────────────────────────────────────────────
    // Samples the previous warp texture at the per-vertex warped UV, scaled by decay.
    // Writes to the compose texture; the compose pass then adds the current scene.
    fragment float4 mvWarp_fragment(
        WarpVertexOut      in      [[stage_in]],
        texture2d<float>   prevTex [[texture(0)]]
    ) {
        float4 prev = prevTex.sample(warpSampler, in.warped_uv);
        return prev * in.decay;
    }

    // ── mvWarp_compose_fragment ───────────────────────────────────────────────
    // Composites the current scene onto the (already decay-warped) compose texture.
    // Uses alpha-blend blending: alpha = (1 - decay) so steady-state = scene × 1.0.
    // The compose render pass uses sourceAlpha × src + one × dst blend mode.
    fragment float4 mvWarp_compose_fragment(
        VertexOut          in       [[stage_in]],
        texture2d<float>   sceneTex [[texture(0)]],
        constant float&    decay    [[buffer(0)]]
    ) {
        float4 scene = sceneTex.sample(linearSampler, in.uv);
        return float4(scene.rgb, 1.0 - decay);  // alpha drives the blend equation
    }

    // ── mvWarp_blit_fragment ──────────────────────────────────────────────────
    // Copies the composed warp texture to the drawable. No tone-mapping here —
    // the scene was already ACES-composited before entering the warp pipeline.
    fragment float4 mvWarp_blit_fragment(
        VertexOut          in      [[stage_in]],
        texture2d<float>   warpTex [[texture(0)]]
    ) {
        return warpTex.sample(warpSampler, in.uv);
    }

    """
}
