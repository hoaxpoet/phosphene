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
    float angle = atan(centered.y, centered.x);

    // === FEEDBACK — aggressive spiral per-preset ===
    float zoom = 1.0 + u_base_zoom * u_bass + u_beat_zoom * u_beat;
    float rot = u_base_rot * u_mid + u_beat_rot * u_beat;
    vec2 feedUV = uv - 0.5;
    feedUV /= zoom;
    float ca = cos(rot); float sa = sin(rot);
    feedUV = vec2(feedUV.x*ca - feedUV.y*sa, feedUV.x*sa + feedUV.y*ca);
    feedUV += 0.5;
    vec3 prev = texture2D(u_prev_frame, feedUV).rgb * u_decay;

    // === NEW: Kaleidoscope ===
    float segments = 6.0;
    float segAngle = 3.14159 * 2.0 / segments;
    float a = mod(angle + u_time * 0.3, segAngle);
    if (a > segAngle * 0.5) a = segAngle - a;
    vec2 kp = vec2(cos(a), sin(a)) * dist;

    float flower = 0.0;
    for (int i = 0; i < 6; i++) {
        float fa = float(i) * 3.14159 * 2.0 / 6.0;
        vec2 c = vec2(cos(fa), sin(fa)) * (0.12 + 0.04 * u_beat);
        flower += smoothstep(0.09, 0.06, length(kp - c));
    }
    flower = min(flower, 1.0);

    float rings = sin(dist * (18.0 + u_treble * 15.0) - u_time * 2.5) * 0.5 + 0.5;
    rings *= smoothstep(0.5, 0.08, dist);

    float hue = fract(u_time * 0.04 + u_scene_progress * 0.3);
    float kalBright = 0.3 + 0.7 * u_beat;
    vec3 newColor = vec3(0.0);
    newColor += hsv2rgb(vec3(hue, 0.95, flower * kalBright)) * (0.3 + u_low_mid * 0.7);
    newColor += hsv2rgb(vec3(hue + 0.4, 0.85, rings * 0.5 * kalBright)) * u_high_mid;
    newColor += hsv2rgb(vec3(hue + 0.1, 0.6, smoothstep(0.3, 0.0, dist) * u_beat));

    vec3 color = prev + newColor;
    color *= 1.0 - smoothstep(0.3, 0.85, dist);
    color = min(color, vec3(1.0));

    gl_FragColor = vec4(color, 1.0);
}
