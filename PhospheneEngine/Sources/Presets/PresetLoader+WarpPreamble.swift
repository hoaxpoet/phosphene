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
        float4 sceneParamsB;              // x=fogNear, y=fogFar, z=D-057 step mult, w=SSGI radius
        float4 light1PositionAndIntensity; // RMENV.1 additional lights (appended)
        float4 light1Color;
        float4 light2PositionAndIntensity;
        float4 light2Color;
        float4 light3PositionAndIntensity;
        float4 light3Color;
        float4 lightingParams;            // x = lightCount (1..4); yzw reserved
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
        WarpVertexOut      in           [[stage_in]],
        texture2d<float>   prevTex      [[texture(0)]],
        constant float&    chromaticMix [[buffer(0)]]
    ) {
        // ── L4 (D-137): full source.milk warp shader (warp_3..15) ──────────────
        // This is the FILL/SATURATION mechanism. L3 ported only the R->G->B
        // transfer (warp_11..15). The source warp shader ALSO does, before the
        // transfer:
        //   warp_3  ret  = sample(prev, warped_uv)            // base feedback colour
        //   warp_4  ret /= (ret.r+ret.g+ret.b)                // NORMALISE -> hue
        //   warp_5  zoom = dot(hue, (1, 0.975, 0.95))         // R-weighted, ∈[0.95,1]
        //   warp_7  ret  = sample(prev, (warped_uv-0.5)*zoom + 0.5)  // RESAMPLE at hue-zoom
        // The hue-dependent inward resample makes saturated content flow OUTWARD
        // at a colour-dependent rate — over the decay window this fills the frame
        // with saturated colour (verified against the faithful butterchurn oracle:
        // full-warp = saturated frame-filling fill, vs L3-transfer-only = a dim
        // dull thread). The fill is COOL on its own; the blit-stage invert
        // (mvWarp_blit_fragment, bInvert=1) flips it warm — see the plan §0 L4.
        //
        // Per-preset gated by chromaticMix: at 0 the resample collapses to
        // warped_uv and the transfer mix collapses to identity, so every other
        // mv_warp preset is byte-for-byte unchanged (PresetRegression confirms).
        // Base sample at the per-vertex warped UV. The per_pixel warp (5-lobe petal
        // zoom + concentric rotation + inward baseline + the bass BREATHING) is
        // computed on the 32×24 vertex mesh in the preset's mvWarpPerVertex — exactly
        // Milkdrop/butterchurn's warp-mesh approach (and cheaper than a per-fragment
        // recompute). The chromatic transfer below still gates on chromaticMix so
        // every other mv_warp preset is byte-for-byte unchanged.
        float2 baseUV = in.warped_uv;
        float3 c0  = prevTex.sample(warpSampler, baseUV).rgb;
        float  a0  = prevTex.sample(warpSampler, baseUV).a;
        float  sum = max(c0.r + c0.g + c0.b, 1e-4);
        float3 hue = c0 / sum;
        float  hzoom    = dot(hue, float3(1.0, 0.975, 0.95));      // ∈ [0.95, 1.0]
        float2 zoomedUV = (baseUV - 0.5) * hzoom + 0.5;
        float2 sUV      = mix(baseUV, zoomedUV, chromaticMix);     // identity at 0 (baseUV==warped_uv)
        float3 cr       = prevTex.sample(warpSampler, sUV).rgb;

        // R->G->B transfer (warp_11..15) on the resampled colour — VERBATIM source
        // (r=0.02; the three pushes are r·0.7, r·4, r·1 = 0.014, 0.080, 0.020).
        // Where R is present it bleeds R->G; where G is present (and R/G low) G->B;
        // B fades. Iterated through the feedback this cycles the field through the
        // hue wheel — the source's full colour cycling, not a tuned approximation.
        float3 xfer = saturate((cr - 0.05) * 99.0);
        xfer.yz    *= saturate((0.1 - cr.xy) * 99.0);
        float3 warm = cr;
        warm += xfer.xxx * float3(-1.0, 1.0, 0.0) * 0.014;
        warm += xfer.yyy * float3(0.0, -1.0, 1.0) * 0.080;
        warm += xfer.zzz * float3(0.0, 0.0, -1.0) * 0.020;
        // (warp_18..19 error-diffusion dither deferred — needs a noise texture
        // bound to the warp pass; it is anti-banding polish, not the fill.)
        //
        // DECAY: butterchurn applies decay ONLY in the DEFAULT warp
        // (`ret = sample(prev)·decay`). When a CUSTOM warp shader is present (DB),
        // it sets warpColor = (1,1,1,1) and does `fragColor = ret · vColor` — i.e.
        // NO decay multiply; the custom shader self-regulates the feedback via its
        // normalise + R→G→B transfer (the B-fade) instead. So for the custom-warp
        // path (chromaticMix>0) we must NOT apply decay — applying it was an extra
        // ~5%/frame loss that starved the edges (pale background) and dimmed the
        // field vs the oracle. Other presets use the default-warp decay unchanged.
        float decayMul = (chromaticMix > 0.0) ? 1.0 : in.decay;
        return float4(mix(cr, warm, chromaticMix), a0) * decayMul;
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
    // Copies the composed warp texture to the drawable, applying the optional
    // DISPLAY-stage post params (Dragon Bloom L4, D-137). The blit output is
    // presented and NEVER swapped back into the feedback loop, so this is the
    // faithful home for source.milk's comp-shader effects (bInvert / bBrighten) —
    // the cool full-warp fill accumulates undisturbed in the feedback texture and
    // only the presented frame is warmed (Milkdrop comp-shader semantics).
    //
    // FAITHFUL fixed-function comp of source.milk (PSVERSION_COMP=0), transcribed
    // VERBATIM from butterchurn's built-in comp shader. Display-stage only (applied
    // to the float feedback on the way to the drawable, NOT fed back — Milkdrop
    // comp semantics, so the feedback field accumulates undisturbed):
    //
    //   uv_echo = (uv-0.5)*(1/echoZoom)*vec2(orientX,orientY)+0.5   // orient 1 = flip x
    //   ret = mix(main(uv), main(uv_echo), echoAlpha)               // fVideoEchoAlpha=0.5
    //   ret *= gammaAdj                                             // fGammaAdj=1.07 (MULTIPLY)
    //   if(brighten) ret = sqrt(ret)   ┐ bBrighten=1 AND bDarken=1
    //   if(darken)   ret = ret*ret     ┘ → sqrt then square = IDENTITY (cancel)
    //   if(invert)   ret = 1 - ret                                  // bInvert=1
    //
    // The video echo (orientation 1, horizontal flip) also fills asymmetric gaps
    // (an empty corner takes the mirror of the filled side) and cleans the
    // bilateral symmetry. brighten+darken cancel for THIS preset → no net contrast
    // op (so there is intentionally no brighten term here).
    //
    // post.x = invert (bInvert), post.y = echoAlpha (fVideoEchoAlpha),
    // post.z = gamma (fGammaAdj), post.w = BEAT PULSE (D-137 music response).
    // (0, 0, 1, 0) ⇒ identity blit — every other mv_warp preset byte-for-byte
    // unchanged (echoAlpha 0 → mix=base; gamma 1; invert 0; beat 0).
    //
    // post.w (beat pulse, 0..1, per-frame): a DISPLAY-stage pump + brighten on the
    // beat. The no-decay feedback smears per-beat changes into the slow field, so
    // beat sync read subtle when driven inside the loop; applying it at the comp
    // (NOT fed back) makes a crisp per-beat pump that punches through. The whole
    // bloom zooms out slightly + brightens on the beat, then settles — "dancing
    // with the beat" without strobing or disturbing the feedback equilibrium.
    fragment float4 mvWarp_blit_fragment(
        VertexOut          in      [[stage_in]],
        texture2d<float>   warpTex [[texture(0)]],
        constant float4&   post    [[buffer(0)]]
    ) {
        float  bp  = post.w;   // smoothed beat envelope (CPU-side attack/decay)
        // Beat pump: zoom the sampled image OUT slightly on the beat so the bloom
        // gently swells, then settles. Applied to the sample UV (display only).
        // Kept subtle (4% pump / 12% brighten) — the earlier 7%/28% read as flicker.
        float2 puv = (in.uv - 0.5) * (1.0 - 0.04 * bp) + 0.5;
        float3 base = warpTex.sample(warpSampler, puv).rgb;
        float3 echo = warpTex.sample(warpSampler, float2(1.0 - puv.x, puv.y)).rgb;  // orient 1, zoom 1
        float3 ret  = mix(base, echo, post.y);   // video echo
        ret *= post.z;                            // gamma multiply (1.07)
        // brighten(sqrt)+darken(square) cancel → omitted.
        ret  = mix(ret, 1.0 - ret, post.x);       // invert
        ret *= (1.0 + 0.12 * bp);                 // beat brighten (accent on the pump)
        return float4(saturate(ret), 1.0);
    }

    """
}
