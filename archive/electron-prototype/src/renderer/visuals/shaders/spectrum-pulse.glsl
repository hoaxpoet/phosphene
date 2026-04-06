#ifdef GL_ES
precision mediump float;
#endif

uniform float u_time;
uniform float u_bass;
uniform float u_mid;
uniform float u_treble;
uniform float u_volume;
uniform float u_bass_att;
uniform float u_mid_att;
uniform float u_treb_att;
uniform float u_beat;
uniform vec2 u_resolution;
uniform float u_scene_progress;
uniform sampler2D u_prev_frame;
uniform float u_sub_bass;
uniform float u_low_bass;
uniform float u_low_mid;
uniform float u_mid_high;
uniform float u_high_mid;
uniform float u_high;
// Per-preset params
uniform float u_beat_zoom;
uniform float u_beat_rot;
uniform float u_base_zoom;
uniform float u_base_rot;
uniform float u_decay;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
    vec2 i = floor(p); vec2 f = fract(p); f = f*f*(3.0-2.0*f);
    return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);
}
vec3 hsv2rgb(vec3 c) {
    vec4 K = vec4(1.0,2.0/3.0,1.0/3.0,3.0);
    vec3 p = abs(fract(c.xxx+K.xyz)*6.0-K.www);
    return c.z*mix(K.xxx,clamp(p-K.xxx,0.0,1.0),c.y);
}

void main() {
    vec2 uv = gl_FragCoord.xy / u_resolution.xy;
    vec2 centered = uv - 0.5;
    float aspect = u_resolution.x / u_resolution.y;
    centered.x *= aspect;
    float dist = length(centered);

    // === FEEDBACK with per-preset params ===
    float zoom = 1.0 + u_base_zoom * u_bass + u_beat_zoom * u_beat;
    float rot = u_base_rot * (u_treble - 0.3) + u_beat_rot * u_beat;
    vec2 feedUV = uv - 0.5;
    feedUV /= zoom;
    float ca = cos(rot); float sa = sin(rot);
    feedUV = vec2(feedUV.x*ca - feedUV.y*sa, feedUV.x*sa + feedUV.y*ca);
    feedUV += 0.5;
    vec3 prev = texture2D(u_prev_frame, feedUV).rgb * u_decay;

    // === NEW ELEMENTS — beat dominates size and brightness ===
    float orbRadius = 0.05 + 0.08 * u_bass + 0.25 * u_beat;
    float orbBright = 0.3 + 0.7 * u_beat;  // Dim when no beat, bright on beat
    float orbGlow = smoothstep(orbRadius + 0.05, orbRadius - 0.03, dist);
    float rings = sin(dist * (10.0 + 12.0 * u_mid) - u_time * 3.0) * 0.5 + 0.5;
    rings *= smoothstep(0.55, 0.1, dist) * (0.2 + 0.8 * u_treble);

    float hue = fract(u_time * 0.06 + dist * 0.4 + u_bass * 0.3);
    vec3 orbColor = hsv2rgb(vec3(hue, 0.9, 1.0));
    vec3 ringColor = hsv2rgb(vec3(fract(hue + 0.33), 0.85, 0.9));

    vec3 newColor = orbColor * orbGlow * orbBright * 1.5;
    newColor += ringColor * rings * 0.4;
    newColor += orbColor * smoothstep(orbRadius + 0.1, orbRadius - 0.05, dist) * u_beat * 0.8;

    float sparkle = pow(noise(uv * 40.0 + u_time * 3.0), 10.0);
    newColor += vec3(1.0, 0.9, 0.8) * sparkle * u_high * 0.5;

    vec3 color = prev + newColor;
    color *= 1.0 - smoothstep(0.35, 0.9, dist);
    color = min(color, vec3(1.0));

    gl_FragColor = vec4(color, 1.0);
}
