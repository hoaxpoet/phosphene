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

vec3 ring(float dist, float angle, float center, float energy, float energyAtt, float hue) {
    // Sustained visibility: blend instant + attenuated + floor
    float vis = energy * 0.5 + energyAtt * 0.4 + 0.05;
    float width = 0.012 + vis * 0.025;
    float wobble = noise(vec2(angle*3.0 + u_time*0.5, hue*10.0)) * 0.015 * (1.0+vis);
    float d = abs(dist - center - vis*0.02 + wobble);
    float core = smoothstep(width, width*0.08, d);
    float glow = smoothstep(width*5.0, 0.0, d) * 0.3;
    vec3 col = hsv2rgb(vec3(hue + u_time*0.02, 0.9, 1.0));
    return col * (core + glow) * vis;
}

void main() {
    vec2 uv = gl_FragCoord.xy / u_resolution.xy;
    vec2 centered = uv - 0.5;
    centered.x *= u_resolution.x / u_resolution.y;
    float dist = length(centered);
    float angle = atan(centered.y, centered.x);

    // === FEEDBACK per-preset ===
    float zoom = 1.0 + u_base_zoom * u_bass + u_beat_zoom * u_beat;
    float rot = u_base_rot * u_treble + u_beat_rot * u_beat;
    vec2 feedUV = uv - 0.5;
    feedUV /= zoom;
    float ca = cos(rot); float sa = sin(rot);
    feedUV = vec2(feedUV.x*ca - feedUV.y*sa, feedUV.x*sa + feedUV.y*ca);
    feedUV += 0.5;
    vec3 prev = texture2D(u_prev_frame, feedUV).rgb * u_decay;

    // === 6 rings with sustained instrument visibility ===
    vec3 newColor = vec3(0.0);
    newColor += ring(dist, angle, 0.05, u_sub_bass, u_bass_att, 0.0);
    newColor += ring(dist, angle, 0.12, u_low_bass, u_bass_att, 0.07);
    newColor += ring(dist, angle, 0.19, u_low_mid,  u_mid_att,  0.18);
    newColor += ring(dist, angle, 0.26, u_mid_high, u_mid_att,  0.45);
    newColor += ring(dist, angle, 0.33, u_high_mid, u_treb_att, 0.6);
    newColor += ring(dist, angle, 0.40, u_high,     u_treb_att, 0.78);

    newColor += hsv2rgb(vec3(0.0, 0.9, 0.8)) * smoothstep(0.06, 0.0, dist) * (u_sub_bass * 0.5 + u_bass_att * 0.5);
    newColor += vec3(0.8, 0.5, 1.0) * smoothstep(0.2, 0.0, dist) * u_beat * 0.5;

    vec3 color = prev + newColor;
    color *= 1.0 - smoothstep(0.35, 0.85, dist);
    color = min(color, vec3(1.0));

    gl_FragColor = vec4(color, 1.0);
}
