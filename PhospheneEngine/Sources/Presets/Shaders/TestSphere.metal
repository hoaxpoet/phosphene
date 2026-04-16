// TestSphere.metal — Minimal pipeline verification SDF.
// A sphere + floor plane. If this renders, the pipeline works.

float sceneSDF(float3 p,
               constant FeatureVector& f,
               constant SceneUniforms& s) {
    // Sphere at (0, 1.5, 5), radius 1.5
    float dSphere = length(p - float3(0.0, 1.5, 5.0)) - 1.5;
    // Floor at y = -1
    float dFloor = p.y + 1.0;
    return min(dSphere, dFloor);
}

void sceneMaterial(float3 p,
                   int matID,
                   constant FeatureVector& f,
                   constant SceneUniforms& s,
                   thread float3& albedo,
                   thread float& roughness,
                   thread float& metallic) {
    float dSphere = length(p - float3(0.0, 1.5, 5.0)) - 1.5;
    float dFloor = p.y + 1.0;
    if (dSphere < dFloor) {
        albedo    = float3(0.8, 0.2, 0.2);  // red sphere
        roughness = 0.3;
        metallic  = 0.0;
    } else {
        albedo    = float3(0.5, 0.5, 0.5);  // gray floor
        roughness = 0.8;
        metallic  = 0.0;
    }
}
