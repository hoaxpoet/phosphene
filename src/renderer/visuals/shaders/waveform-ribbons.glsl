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

vec3 hsv2rgb(vec3 c) {
    vec4 K = vec4(1.0,2.0/3.0,1.0/3.0,3.0);
    vec3 p = abs(fract(c.xxx+K.xyz)*6.0-K.www);
    return c.z*mix(K.xxx,clamp(p-K.xxx,0.0,1.0),c.y);
}

float ribbon(vec2 uv, float yCenter, float freq, float amp, float phase, float width) {
    float wave = sin(uv.x*freq + phase)*amp + sin(uv.x*freq*0.5 + phase*1.3)*amp*0.5;
    float d = abs(uv.y - yCenter - wave);
    return smoothstep(width, width*0.1, d);
}

void main() {
    vec2 uv = gl_FragCoord.xy / u_resolution.xy;
    vec2 centered = uv - 0.5;
    float aspect = u_resolution.x / u_resolution.y;
    centered.x *= aspect;
    float dist = length(centered);
    float t = u_time;

    // === FEEDBACK per-preset ===
    vec2 feedUV = uv;
    feedUV.y += 0.006 * u_mid;
    feedUV = 0.5 + (feedUV - 0.5) / (1.0 + u_base_zoom * u_bass + u_beat_zoom * u_beat);
    vec3 prev = texture2D(u_prev_frame, feedUV).rgb * u_decay;

    // === 6 RIBBONS — sustained instrument visibility ===
    // Each ribbon uses: instant value * 0.5 + attenuated * 0.5 + floor
    // This keeps ribbons visible for sustained instruments (horns, keys, bass)
    // while still pulsing brighter on transient attacks
    vec3 newColor = vec3(0.0);

    // Sub-bass (kick fundamental) — use bass_att for sustain
    float sb = u_sub_bass * 0.5 + u_bass_att * 0.4 + 0.05;
    newColor += hsv2rgb(vec3(0.0, 0.9, 0.9)) * ribbon(centered, -0.2, 3.0+u_sub_bass*3.0, 0.07+u_sub_bass*0.12, t*0.5, 0.022) * sb;

    // Low bass (bass guitar/synth) — use bass_att
    float lb = u_low_bass * 0.5 + u_bass_att * 0.4 + 0.05;
    newColor += hsv2rgb(vec3(0.07, 0.85, 0.9)) * ribbon(centered, -0.1, 4.0+u_low_bass*3.0, 0.06+u_low_bass*0.1, t*0.7, 0.018) * lb;

    // Low mid (guitar body, piano, warmth) — use mid_att
    float lm = u_low_mid * 0.5 + u_mid_att * 0.4 + 0.05;
    newColor += hsv2rgb(vec3(0.2+u_scene_progress*0.2, 0.8, 0.9)) * ribbon(centered, 0.0, 5.5+u_low_mid*4.0, 0.05+u_low_mid*0.08, t*1.0, 0.015) * lm;

    // Mid-high (vocals, horns, guitar leads) — use mid_att
    float mh = u_mid_high * 0.5 + u_mid_att * 0.4 + 0.05;
    newColor += hsv2rgb(vec3(0.45, 0.85, 0.95)) * ribbon(centered, 0.08, 7.0+u_mid_high*5.0, 0.04+u_mid_high*0.06, t*1.4, 0.012) * mh;

    // High-mid (presence, cymbals) — use treb_att
    float hm = u_high_mid * 0.5 + u_treb_att * 0.4 + 0.05;
    newColor += hsv2rgb(vec3(0.6, 0.8, 0.9)) * ribbon(centered, 0.16, 9.0+u_high_mid*6.0, 0.03+u_high_mid*0.04, t*1.8, 0.008) * hm;

    // High (air, hi-hats, sibilance) — use treb_att
    float hi = u_high * 0.5 + u_treb_att * 0.4 + 0.05;
    newColor += hsv2rgb(vec3(0.78, 0.75, 0.85)) * ribbon(centered, 0.24, 12.0+u_high*7.0, 0.02+u_high*0.03, t*2.2, 0.005) * hi;

    // Beat flash on bass ribbons
    newColor += hsv2rgb(vec3(0.05, 0.9, 1.0)) * ribbon(centered, -0.15, 3.5, 0.1, t*0.6, 0.03) * u_beat * 0.7;

    // Horizontal streak on beat
    float streak = smoothstep(0.03, 0.0, abs(centered.y)) * u_beat;
    newColor += vec3(0.8, 0.5, 0.9) * streak * 0.5;

    vec3 color = prev + newColor;
    color *= 1.0 - smoothstep(0.5, 1.1, dist);
    color = min(color, vec3(1.0));

    gl_FragColor = vec4(color, 1.0);
}
