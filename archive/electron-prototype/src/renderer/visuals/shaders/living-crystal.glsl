#ifdef GL_ES
precision mediump float;
#endif

uniform float u_time;
uniform vec2 u_resolution;
uniform float u_scene_progress;
uniform float u_fps;
uniform float u_bass;
uniform float u_mid;
uniform float u_treble;
uniform float u_volume;
uniform float u_bass_att;
uniform float u_mid_att;
uniform float u_treb_att;
uniform float u_sub_bass;
uniform float u_low_bass;
uniform float u_low_mid;
uniform float u_mid_high;
uniform float u_high_mid;
uniform float u_high;
uniform sampler2D u_spectrum;
uniform sampler2D u_waveform;
uniform float u_centroid;
uniform float u_flux;
uniform float u_beat;
uniform float u_beat_bass;
uniform float u_beat_mid;
uniform float u_beat_treble;
uniform sampler2D u_prev_frame;
uniform float u_beat_zoom;
uniform float u_beat_rot;
uniform float u_base_zoom;
uniform float u_base_rot;
uniform float u_decay;

const float PI = 3.14159265;
const float TAU = 6.28318530;

vec3 hsv2rgb(vec3 c) {
    vec4 K = vec4(1.0, 2.0/3.0, 1.0/3.0, 3.0);
    vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

// Signed distance function: sphere deformed by spectrum and waveform
float sdf(vec3 p) {
    float r = length(p);
    // Calm, mostly smooth sphere. Bass makes it breathe gently.
    float baseRadius = 1.0 + u_bass_att * 0.15;

    // Spherical coordinates
    float theta = atan(p.z, p.x);
    float phi = acos(clamp(p.y / max(r, 0.001), -1.0, 1.0));

    // Spectrum creates gentle, broad deformation — NOT per-bin noise
    // Read only 4 broad frequency ranges for smooth, readable shape
    float specLow = texture2D(u_spectrum, vec2(0.05, 0.5)).r;   // bass region
    float specMid = texture2D(u_spectrum, vec2(0.25, 0.5)).r;   // mid region
    float specHigh = texture2D(u_spectrum, vec2(0.6, 0.5)).r;   // treble region

    // Each range deforms a different axis — creates an organic trilobate shape
    float deform = specLow * 0.12 * (0.5 + 0.5 * cos(theta * 2.0));
    deform += specMid * 0.08 * (0.5 + 0.5 * sin(phi * 2.0 + theta));
    deform += specHigh * 0.04 * (0.5 + 0.5 * cos(phi * 3.0 - theta * 2.0));

    // Waveform adds VERY subtle surface texture — like skin, not noise
    float waveU = texture2D(u_waveform, vec2(fract(theta / TAU + 0.5), 0.5)).r;
    float waveRipple = (waveU - 0.5) * 0.02 * u_volume;

    return r - baseRadius - deform - waveRipple;
}

// Compute surface normal via central differences
vec3 calcNormal(vec3 p) {
    float e = 0.005;
    return normalize(vec3(
        sdf(p + vec3(e, 0, 0)) - sdf(p - vec3(e, 0, 0)),
        sdf(p + vec3(0, e, 0)) - sdf(p - vec3(0, e, 0)),
        sdf(p + vec3(0, 0, e)) - sdf(p - vec3(0, 0, e))
    ));
}

void main() {
    vec2 uv = gl_FragCoord.xy / u_resolution.xy;
    vec2 centered = uv - 0.5;
    float aspect = u_resolution.x / u_resolution.y;
    centered.x *= aspect;

    // === FEEDBACK — simple zoom/rotate to keep 3D object sharp ===
    float zoom = 1.0 + u_base_zoom * u_bass + u_beat_zoom * u_beat;
    float rot = u_base_rot * (u_mid - 0.3) + u_beat_rot * u_beat;
    vec2 feedUV = uv - 0.5;
    feedUV /= zoom;
    float ca = cos(rot); float sa = sin(rot);
    feedUV = vec2(feedUV.x*ca - feedUV.y*sa, feedUV.x*sa + feedUV.y*ca);
    feedUV += 0.5;
    vec3 prev = texture2D(u_prev_frame, feedUV).rgb * u_decay;

    // === CAMERA ===
    // Orbit around the object, speed modulated by audio
    float camAngle = u_time * 0.3 + u_mid_att * 0.5;
    float camHeight = sin(u_time * 0.15) * 0.8 + u_bass_att * 0.3;
    float camDist = 3.5 - u_bass_att * 0.3;

    vec3 ro = vec3(cos(camAngle) * camDist, camHeight, sin(camAngle) * camDist);
    vec3 target = vec3(0.0);
    vec3 forward = normalize(target - ro);
    vec3 right = normalize(cross(forward, vec3(0, 1, 0)));
    vec3 up = cross(right, forward);

    vec3 rd = normalize(forward + centered.x * right + centered.y * up);

    // === RAYMARCHING ===
    float t = 0.0;
    float minDist = 1e10;
    bool hit = false;

    for (int i = 0; i < 64; i++) {
        vec3 p = ro + rd * t;
        float d = sdf(p);
        minDist = min(minDist, d);
        if (d < 0.002) {
            hit = true;
            break;
        }
        t += d * 0.8; // slight understepping for safety
        if (t > 12.0) break;
    }

    // === SHADING ===
    vec3 newColor = vec3(0.0);
    float bright = 0.3 + 0.7 * u_beat; // beat-gated brightness

    if (hit) {
        vec3 p = ro + rd * t;
        vec3 n = calcNormal(p);

        // Light orbits opposite to camera for dramatic effect
        vec3 lightDir = normalize(vec3(
            cos(camAngle + PI * 0.7) * 2.0,
            1.5,
            sin(camAngle + PI * 0.7) * 2.0
        ));

        // Diffuse
        float diff = max(dot(n, lightDir), 0.0);
        // Specular (Blinn-Phong)
        vec3 halfVec = normalize(lightDir - rd);
        float spec = pow(max(dot(n, halfVec), 0.0), 32.0);
        // Rim lighting (edge glow)
        float rim = pow(1.0 - max(dot(n, -rd), 0.0), 3.0);

        // Surface color: angle-dependent hue + centroid warmth
        float theta = atan(p.z, p.x);
        float surfHue = fract(
            (theta + PI) / TAU * 0.5 +
            mix(0.6, 0.0, u_centroid) +
            u_time * 0.02
        );

        // Spectrum-driven iridescence: brighter where frequencies are active
        float specAngle = (theta + PI) / TAU;
        float specVal = texture2D(u_spectrum, vec2(specAngle, 0.5)).r;
        float iridescence = 0.3 + specVal * 0.7;

        vec3 surfColor = hsv2rgb(vec3(surfHue, 0.85, 0.7 * iridescence));
        vec3 rimColor = hsv2rgb(vec3(fract(surfHue + 0.2), 0.6, 0.9));

        // Compose lighting
        newColor = surfColor * diff * 0.35 * bright;
        newColor += vec3(0.9, 0.85, 0.8) * spec * 0.2 * bright;
        newColor += rimColor * rim * 0.15 * bright;

        // Subsurface scattering approximation
        float sss = max(dot(n, -lightDir), 0.0) * 0.1;
        vec3 sssColor = hsv2rgb(vec3(fract(surfHue + 0.4), 0.9, 0.5));
        newColor += sssColor * sss * bright;

    } else {
        // Near-miss glow: creates an atmospheric halo around the object
        float glowDist = minDist;
        float glow = exp(-glowDist * 8.0) * 0.08 * bright;
        float glowHue = fract(mix(0.6, 0.0, u_centroid) + u_time * 0.03);
        newColor += hsv2rgb(vec3(glowHue, 0.7, 0.5)) * glow;
    }

    // === COMPOSITE ===
    vec3 color = prev + newColor;
    color = min(color, vec3(1.0));

    gl_FragColor = vec4(color, 1.0);
}
