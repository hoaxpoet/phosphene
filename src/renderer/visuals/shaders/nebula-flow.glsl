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
float fbm(vec2 p) {
    float v = 0.0; float a = 0.5;
    for (int i = 0; i < 5; i++) { v += a*noise(p); p *= 2.0; a *= 0.5; }
    return v;
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

    // === FEEDBACK — gradient displacement + per-preset zoom ===
    vec2 px = vec2(1.0) / u_resolution.xy;
    float lumL = dot(texture2D(u_prev_frame, uv - vec2(px.x*4.0, 0.0)).rgb, vec3(0.3,0.5,0.2));
    float lumR = dot(texture2D(u_prev_frame, uv + vec2(px.x*4.0, 0.0)).rgb, vec3(0.3,0.5,0.2));
    float lumU = dot(texture2D(u_prev_frame, uv + vec2(0.0, px.y*4.0)).rgb, vec3(0.3,0.5,0.2));
    float lumD = dot(texture2D(u_prev_frame, uv - vec2(0.0, px.y*4.0)).rgb, vec3(0.3,0.5,0.2));
    vec2 grad = vec2(lumR - lumL, lumU - lumD);

    float displaceStr = 10.0 + u_bass * 8.0 + u_beat * 12.0;
    vec2 feedUV = uv + grad * px * displaceStr;
    feedUV = 0.5 + (feedUV - 0.5) / (1.0 + u_base_zoom * u_bass + u_beat_zoom * u_beat);
    vec3 prev = texture2D(u_prev_frame, feedUV).rgb * u_decay;

    // === NEW: Nebula ===
    float t = u_time * 0.2;
    vec2 q = vec2(fbm(centered*2.5 + vec2(0.0,t)), fbm(centered*2.5 + vec2(5.2,t*1.3)));
    vec2 r = vec2(fbm(centered*2.5 + 4.0*q + t*0.3), fbm(centered*2.5 + 4.0*q + t*0.2));
    float warp = fbm(centered*2.5 + 4.0*r);

    float nebBright = 0.4 + 0.6 * u_beat;
    vec3 c1 = hsv2rgb(vec3(0.7 + u_bass*0.1, 0.9, warp * 0.4 * u_low_bass * nebBright));
    vec3 c2 = hsv2rgb(vec3(0.5, 0.9, q.x * 0.35 * u_mid_high * nebBright));
    vec3 c3 = hsv2rgb(vec3(0.0, 0.95, r.y * 0.2 * u_high_mid * nebBright));
    vec3 newColor = c1 + c2 + c3;

    float sparkle = pow(noise(uv*60.0 + u_time*2.5), 10.0);
    newColor += vec3(1.0,0.9,0.8) * sparkle * u_high * 0.6;

    float beatBloom = smoothstep(0.6, 0.0, dist) * u_beat;
    newColor += hsv2rgb(vec3(fract(u_time*0.08), 0.7, beatBloom * 0.5));

    vec3 color = prev + newColor;
    color *= 1.0 - smoothstep(0.4, 1.0, dist);
    color = min(color, vec3(1.0));

    gl_FragColor = vec4(color, 1.0);
}
