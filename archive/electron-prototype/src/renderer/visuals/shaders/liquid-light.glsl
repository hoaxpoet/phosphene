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

vec3 hsv2rgb(vec3 c) {
    vec4 K = vec4(1.0, 2.0/3.0, 1.0/3.0, 3.0);
    vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

// Liquid surface height: calm broad swells with gentle waveform texture
float surfaceHeight(vec2 pos) {
    float h = 0.0;

    // Broad, slow swells from bass — the primary motion
    h += sin(pos.x * 0.4 + u_time * 0.5) * u_bass_att * 0.25;
    h += sin(pos.y * 0.35 - u_time * 0.4) * u_bass_att * 0.2;

    // Waveform adds gentle surface ripple — one read, not three
    float w1 = texture2D(u_waveform, vec2(fract(pos.x * 0.15 + u_time * 0.03), 0.5)).r;
    h += (w1 - 0.5) * 0.15 * u_volume;

    // Beat: single clean radial pulse, not frantic splash
    float distFromCenter = length(pos);
    float pulse = sin(distFromCenter * 2.0 - u_time * 3.0) * u_beat * 0.2;
    pulse *= exp(-distFromCenter * 0.4);
    h += pulse;

    return h;
}

void main() {
    vec2 uv = gl_FragCoord.xy / u_resolution.xy;
    vec2 centered = uv - 0.5;
    float aspect = u_resolution.x / u_resolution.y;
    centered.x *= aspect;

    // === FEEDBACK ===
    float zoom = 1.0 + u_base_zoom * u_bass + u_beat_zoom * u_beat;
    float rot = u_base_rot * (u_mid - 0.3) + u_beat_rot * u_beat;
    vec2 feedUV = uv - 0.5;
    feedUV /= zoom;
    float ca = cos(rot); float sa = sin(rot);
    feedUV = vec2(feedUV.x*ca - feedUV.y*sa, feedUV.x*sa + feedUV.y*ca);
    feedUV += 0.5;
    vec3 prev = texture2D(u_prev_frame, feedUV).rgb * u_decay;

    // === CAMERA — looking down at liquid surface from above and slightly tilted ===
    float camAngle = u_time * 0.15 + u_mid_att * 0.3;
    float tilt = 0.6 + u_bass_att * 0.1; // angle from vertical

    // Ray from camera into the liquid plane (y=0)
    vec3 ro = vec3(
        cos(camAngle) * 2.0,
        3.0 + u_bass_att * 0.5,
        sin(camAngle) * 2.0
    );

    vec3 target = vec3(0.0, 0.0, 0.0);
    vec3 forward = normalize(target - ro);
    vec3 right = normalize(cross(forward, vec3(0, 1, 0)));
    vec3 up = cross(right, forward);
    vec3 rd = normalize(forward + centered.x * right + centered.y * up);

    // === RAY-SURFACE INTERSECTION ===
    // March ray to find where it hits the wavy surface (y = surfaceHeight)
    vec3 newColor = vec3(0.0);
    float bright = 0.3 + 0.7 * u_beat;
    bool hitSurface = false;
    vec3 hitPos = vec3(0.0);

    float t = 0.0;
    for (int i = 0; i < 48; i++) {
        vec3 p = ro + rd * t;
        float h = surfaceHeight(p.xz);
        float surfDist = p.y - h;

        if (surfDist < 0.02) {
            hitSurface = true;
            hitPos = p;
            break;
        }
        // Step proportional to distance above surface, but not too far
        t += max(surfDist * 0.5, 0.05);
        if (t > 15.0) break;
    }

    if (hitSurface) {
        // === SURFACE NORMAL (finite differences on the height field) ===
        float eps = 0.05;
        float hL = surfaceHeight(hitPos.xz - vec2(eps, 0.0));
        float hR = surfaceHeight(hitPos.xz + vec2(eps, 0.0));
        float hD = surfaceHeight(hitPos.xz - vec2(0.0, eps));
        float hU = surfaceHeight(hitPos.xz + vec2(0.0, eps));
        vec3 normal = normalize(vec3(hL - hR, 2.0 * eps, hD - hU));

        // === LIGHTING ===
        vec3 lightDir = normalize(vec3(0.5, 1.0, 0.3));
        float diff = max(dot(normal, lightDir), 0.0);

        // Specular — creates sharp highlights on wave crests
        vec3 halfVec = normalize(lightDir - rd);
        float spec = pow(max(dot(normal, halfVec), 0.0), 64.0);

        // Fresnel — edges of waves glow more (like real water/glass)
        float fresnel = pow(1.0 - max(dot(normal, -rd), 0.0), 4.0);

        // === COLOR from spectrum ===
        // Different surface positions read different spectrum bins
        // Creates iridescent color that shifts with frequency content
        float specPos = fract(length(hitPos.xz) * 0.2 + atan(hitPos.z, hitPos.x) / (2.0 * PI));
        float specVal = texture2D(u_spectrum, vec2(specPos, 0.5)).r;

        // Centroid shifts the palette
        float hue = fract(
            mix(0.55, 0.0, u_centroid) +
            specPos * 0.4 +
            specVal * 0.15 +
            u_time * 0.02
        );

        vec3 surfColor = hsv2rgb(vec3(hue, 0.85, 0.6));
        vec3 specColor = hsv2rgb(vec3(fract(hue + 0.1), 0.4, 0.95)); // near-white specular
        vec3 fresnelColor = hsv2rgb(vec3(fract(hue + 0.3), 0.7, 0.7));

        // Compose — diffuse body + sharp specular + fresnel rim
        newColor += surfColor * diff * 0.2 * bright;
        newColor += surfColor * 0.05 * bright; // ambient fill
        newColor += specColor * spec * 0.35 * bright; // sharp white highlights
        newColor += fresnelColor * fresnel * 0.12 * bright;

        // Spectrum-driven glow: areas where frequencies are active glow brighter
        newColor += surfColor * specVal * 0.08 * bright;

        // Caustic-like patterns on the surface from refracted light
        float caustic = pow(max(dot(normal, vec3(0, 1, 0)), 0.0), 8.0);
        newColor += specColor * caustic * 0.06 * bright;

    } else {
        // Sky/background: faint ambient glow
        float skyGlow = smoothstep(0.5, -0.2, rd.y) * 0.02;
        float skyHue = mix(0.6, 0.0, u_centroid);
        newColor += hsv2rgb(vec3(skyHue, 0.5, 0.4)) * skyGlow * bright;
    }

    // === COMPOSITE ===
    vec3 color = prev + newColor;
    color = min(color, vec3(1.0));

    gl_FragColor = vec4(color, 1.0);
}
