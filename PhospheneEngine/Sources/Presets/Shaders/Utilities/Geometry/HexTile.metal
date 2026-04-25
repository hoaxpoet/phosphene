// HexTile.metal — Mikkelsen practical hex-tiling for breaking texture repetition (V.2 Part A).
//
// Reference: "Practical Real-Time Hex-Tiling" — Mads Janus Mikkelsen (2022)
//   https://madsim.dk/journal/2022/hex-tiling-in-practice/
//
// Standard texture tiling shows obvious grid repetition in any direction.
// Hex-tiling samples the texture at three overlapping hexagonal grids, each
// rotated 120° apart, and blends them with smooth weights. The result has no
// visible seams and the only repeating unit is the hexagon itself (~2× larger
// than the original tile).
//
// Usage:
//   HexTileResult h = hex_tile_uv(uv, 3.0, 0.5);
//   float3 col = texture.sample(s, h.uvA) * h.weightA
//              + texture.sample(s, h.uvB) * h.weightB
//              + texture.sample(s, h.uvC) * h.weightC;
//
// Three texture samples per texel. On modern GPU hardware the cost is about
// 2× a single sample due to sampler-cache sharing within a hex cell.

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-function"

// ─── Result Type ─────────────────────────────────────────────────────────────

/// Output from hex_tile_uv. Sample your texture at uvA, uvB, uvC and
/// blend linearly with weightA, weightB, weightC (they sum to 1.0).
struct HexTileResult {
    float2 uvA;     // UV for hex sample A
    float2 uvB;     // UV for hex sample B
    float2 uvC;     // UV for hex sample C
    float  weightA; // blend weight A
    float  weightB; // blend weight B
    float  weightC; // blend weight C
};

// ─── Internal Hex Grid Helpers ───────────────────────────────────────────────

/// Hash a 2D integer cell to a scalar offset for per-cell UV rotation.
/// Returns a value in [0, 1).
static inline float hex_cell_hash(int2 cell) {
    int2 q = int2(cell.x * 1453 + cell.y * 2971, cell.x * 3539 + cell.y * 1117);
    q = (q ^ (q >> 9)) * 0x45d9f3b;
    return float(q.x ^ q.y) / float(0x7fffffff) * 0.5 + 0.5;
}

/// Rotate a UV by angle (radians) around (0.5, 0.5) centre.
static inline float2 hex_rotate_uv(float2 uv, float angle) {
    float c = cos(angle);
    float s = sin(angle);
    float2 centered = uv - 0.5;
    return float2(c * centered.x - s * centered.y,
                  s * centered.x + c * centered.y) + 0.5;
}

// ─── Hex-Tiling Main Function ─────────────────────────────────────────────────

/// Compute three overlapping hex-grid UV samples and their blend weights.
///
/// uv         = input UV (any range; wraps naturally via texture sampler).
/// tileScale  = scales the hex grid; larger values = smaller hex cells.
/// blendWidth = controls crossfade width at hex boundaries [0.01, 0.5].
///              Larger values = softer transitions but slightly more blurring.
///              Recommended: 0.3–0.5 for most textures.
///
/// Per-cell UV rotation is applied to break the remaining hex periodicity.
/// The rotation angle is derived from a hash of the integer cell index, so
/// each hex cell gets a unique rotation drawn from the full range [0, 2π].
static inline HexTileResult hex_tile_uv(float2 uv, float tileScale, float blendWidth) {
    // Scale UV into hex grid space.
    float2 scaledUV = uv * tileScale;

    // Hex grid basis vectors (equilateral triangle lattice).
    // Two axes at 0° and 60° produce the hex cell centres.
    const float2 e1 = float2(1.0, 0.0);
    const float2 e2 = float2(0.5, 0.866025);   // cos(60°), sin(60°)

    // Project UV into skewed coordinates.
    float s = scaledUV.x - scaledUV.y * 0.577350;  // tan(30°) = 1/√3
    float t = scaledUV.y * 1.154701;                // 2/√3

    // Integer and fractional parts in the skewed space.
    float2 si = floor(float2(s, t));
    float2 sf = fract(float2(s, t));

    // Identify which of the two triangles in the rhombus we're in.
    float2 tri = (sf.x + sf.y < 1.0)
        ? float2(0.0, 0.0)
        : float2(1.0, 1.0);

    // Three candidate hex centres (integer cell indices).
    int2 c0 = int2(si);
    int2 c1 = int2(si + float2(1.0, 0.0));
    int2 c2 = int2(si + float2(0.0, 1.0));
    if (tri.x > 0.5) {
        c1 = int2(si + float2(1.0, 1.0));
        c2 = int2(si + float2(1.0, 0.0));
    }

    // Hex centre UVs (convert back from skewed to UV space).
    float2 fc0 = float2(c0); float2 p0 = float2(fc0.x + fc0.y * 0.5, fc0.y * 0.866025) / tileScale;
    float2 fc1 = float2(c1); float2 p1 = float2(fc1.x + fc1.y * 0.5, fc1.y * 0.866025) / tileScale;
    float2 fc2 = float2(c2); float2 p2 = float2(fc2.x + fc2.y * 0.5, fc2.y * 0.866025) / tileScale;

    // Compute per-sample UVs: uv relative to each hex centre, then rotate.
    float angle0 = hex_cell_hash(c0) * 6.28318;
    float angle1 = hex_cell_hash(c1) * 6.28318;
    float angle2 = hex_cell_hash(c2) * 6.28318;

    float2 uvA = hex_rotate_uv(uv - p0 + 0.5, angle0);
    float2 uvB = hex_rotate_uv(uv - p1 + 0.5, angle1);
    float2 uvC = hex_rotate_uv(uv - p2 + 0.5, angle2);

    // Compute barycentric-style blend weights from distance to each centre.
    float dA = length(uv - p0);
    float dB = length(uv - p1);
    float dC = length(uv - p2);

    // Weights: inverse distance, normalised. Apply smoothstep to blend width.
    float wA = 1.0 / (dA + 1e-5);
    float wB = 1.0 / (dB + 1e-5);
    float wC = 1.0 / (dC + 1e-5);

    // Sharpen blend at cell boundaries using smoothstep on the normalised weight.
    float total = wA + wB + wC;
    wA /= total; wB /= total; wC /= total;

    // Soft-clamp: bring weights toward sharper boundaries.
    float sharpness = 1.0 / max(blendWidth, 0.01);
    float3 w3 = float3(wA, wB, wC);
    w3 = pow(w3, sharpness);
    float wSum = w3.x + w3.y + w3.z;
    w3 /= wSum;

    HexTileResult result;
    result.uvA     = uvA;
    result.uvB     = uvB;
    result.uvC     = uvC;
    result.weightA = w3.x;
    result.weightB = w3.y;
    result.weightC = w3.z;
    return result;
}

// ─── Weight-only variant (for debugging / cheap blending) ─────────────────────

/// Returns only the blend weights without per-cell UV rotation.
/// Cheaper than full hex_tile_uv when UV rotation isn't needed.
static inline float3 hex_tile_weights(float2 uv, float tileScale, float blendWidth) {
    HexTileResult h = hex_tile_uv(uv, tileScale, blendWidth);
    return float3(h.weightA, h.weightB, h.weightC);
}

#pragma clang diagnostic pop
