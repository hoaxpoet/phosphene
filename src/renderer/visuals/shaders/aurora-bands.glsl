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
uniform float u_beat_bass;
uniform float u_beat_mid;
uniform float u_beat_treble;
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
float fbm(vec2 p) {
    float v = 0.0; float a = 0.5;
    for (int i = 0; i < 4; i++) { v += a*noise(p); p *= 2.0; a *= 0.5; }
    return v;
}
vec3 hsv2rgb(vec3 c) {
    vec4 K = vec4(1.0,2.0/3.0,1.0/3.0,3.0);
    vec3 p = abs(fract(c.xxx+K.xyz)*6.0-K.www);
    return c.z*mix(K.xxx,clamp(p-K.xxx,0.0,1.0),c.y);
}

// Each curtain receives its band energy AND its corresponding beat pulse.
// The beat pulse makes the curtain flash brighter on onset — kick drum curtain
// flashes on u_beat_bass, synth curtain flashes on u_beat_mid, etc.
vec3 curtain(vec2 uv, float yCenter, float speed, float freq, float energy, float energyAtt, float bandBeat, float hue) {
    float vis = energy * 0.7 + energyAtt * 0.2 + 0.05;
    // Beat pulse widens and brightens the curtain on onset
    vis += bandBeat * 0.4;
    float wave = fbm(vec2(uv.x * freq + u_time * speed, yCenter * 5.0));
    float y = yCenter + wave * 0.08 * (1.0 + vis);
    float d = abs(uv.y - y);
    float width = 0.01 + vis * 0.04 + bandBeat * 0.02;
    float intensity = smoothstep(width, width * 0.03, d) * vis;
    float glow = smoothstep(width * 3.0, 0.0, d) * 0.15 * vis;
    return hsv2rgb(vec3(hue, 0.85 - bandBeat * 0.15, intensity + glow));
}

void main() {
    vec2 uv = gl_FragCoord.xy / u_resolution.xy;

    // === FEEDBACK — gentle drift, no global beat zoom ===
    vec2 feedUV = uv;
    feedUV.y += 0.005 * u_bass;
    feedUV.x += 0.002 * sin(u_time * 0.3) * u_mid;
    feedUV = 0.5 + (feedUV - 0.5) / (1.0 + u_base_zoom * u_bass);
    vec3 prev = texture2D(u_prev_frame, feedUV).rgb * u_decay;

    // === Curtains — each with its OWN per-band beat ===
    vec3 newColor = vec3(0.0);
    // Sub-bass + bass curtains respond to bass beat (kick drum)
    newColor += curtain(uv, 0.10, 0.08, 1.5, u_sub_bass, u_bass_att, u_beat_bass, 0.95);
    newColor += curtain(uv, 0.22, 0.14, 2.0, u_low_bass, u_bass_att, u_beat_bass, 0.05);
    // Low-mid + mid-high curtains respond to mid beat (synth, vocals)
    newColor += curtain(uv, 0.38, 0.22, 2.5, u_low_mid,  u_mid_att,  u_beat_mid, 0.14);
    newColor += curtain(uv, 0.53, 0.32, 3.0, u_mid_high, u_mid_att,  u_beat_mid, 0.35);
    // High-mid + treble curtains respond to treble beat (hi-hats, cymbals)
    newColor += curtain(uv, 0.68, 0.48, 3.5, u_high_mid, u_treb_att, u_beat_treble, 0.58);
    newColor += curtain(uv, 0.84, 0.65, 4.5, u_high,     u_treb_att, u_beat_treble, 0.75);

    // Stars from treble
    float stars = pow(noise(uv * 80.0 + u_time * 0.5), 14.0);
    newColor += vec3(0.8, 0.9, 1.0) * stars * u_high * 0.5;

    // NO global beat multiplier — each curtain handles its own

    vec3 color = prev + newColor;
    color *= 0.35 + 0.65 * uv.y; // darker at bottom
    color *= 0.6 + 0.6 * u_volume;
    color = min(color, vec3(1.0));

    gl_FragColor = vec4(color, 1.0);
}
