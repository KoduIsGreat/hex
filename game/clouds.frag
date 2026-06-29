#version 330
precision highp float;

in vec2 frag_texcoord;
in vec4 frag_color;
out vec4 final_color;

uniform vec2  u_resolution; // screen size in pixels
uniform vec2  u_center;     // globe center, top-left pixel coords
uniform float u_radius;     // globe pixel radius
uniform float u_time;       // seconds
uniform float u_blend;      // 0..1 globe-mode strength
uniform float u_seed;       // varies the cloud pattern per world
uniform float u_mode;       // 0 = globe clouds, 1 = flat ground shadows
uniform float u_zoom;       // camera zoom (flat mode)
uniform vec2  u_cam_target; // camera target in world coords (flat mode)
uniform float u_day;        // 0 = night .. 1 = day
uniform vec3  u_sun;        // globe sun direction

const float PI = 3.14159265;

float hash(vec2 p) {
    p = fract(p * vec2(123.34, 345.45));
    p += dot(p, p + 34.345);
    return fract(p.x * p.y);
}

float value_noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    float a = hash(i + vec2(0.0, 0.0));
    float b = hash(i + vec2(1.0, 0.0));
    float c = hash(i + vec2(0.0, 1.0));
    float d = hash(i + vec2(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
    float v = 0.0;
    float a = 0.5;
    for (int i = 0; i < 5; i++) {
        v += a * value_noise(p);
        p *= 2.0;
        a *= 0.5;
    }
    return v;
}

// Top-left pixel coords (u_center is also top-left).
vec2 frag_px() {
    return vec2(gl_FragCoord.x, u_resolution.y - gl_FragCoord.y);
}

void main() {
    if (u_mode < 0.5) {
        // ---- Globe clouds -------------------------------------------------
        vec2 p = (frag_px() - u_center) / u_radius; // [-1,1] across disc
        float r2 = dot(p, p);
        if (r2 > 1.0) {
            discard;
        }
        float z = sqrt(1.0 - r2);
        vec3 n = vec3(p.x, p.y, z);

        // Lat/long; longitude drifts so the planet appears to spin.
        float lon = atan(n.x, n.z) + u_time * 0.05;
        float lat = asin(clamp(n.y, -1.0, 1.0));
        vec2 uv = vec2(lon / PI, lat / (0.5 * PI));

        // Offset by the camera target so clouds pan with the terrain, not the screen.
        vec2 pan = u_cam_target * 0.003;
        vec2 q = uv * 3.0 + vec2(u_seed * 13.0, u_seed * 7.0) + pan;
        float clouds = fbm(q + vec2(u_time * 0.02, 0.0));
        clouds += 0.5 * fbm(q * 2.3 - vec2(u_time * 0.015, 0.0));
        clouds /= 1.5;

        clouds = smoothstep(0.38, 0.72, clouds); // wider band = more coverage

        float limb = smoothstep(1.0, 0.5, r2);

        // Day/night: light the cloud tops by the sun; dim the night side.
        float ndl = max(0.0, dot(n, u_sun));
        float light = 0.15 + 0.85 * ndl;
        float shade = (0.8 + 0.2 * z) * light;

        float alpha = clouds * limb * u_blend * mix(0.25, 1.0, ndl);
        final_color = vec4(vec3(shade), alpha);
    } else {
        // ---- Flat ground shadows -----------------------------------------
        // Sample noise in WORLD space so shadows stay glued to the terrain
        // while panning/zooming, plus a slow drift of their own.
        vec2 world = (frag_px() - u_center) / u_zoom + u_cam_target;
        vec2 q = world * 0.004 + vec2(u_seed * 13.0, u_seed * 7.0);
        vec2 drift = vec2(u_time * 0.05, u_time * 0.02);

        float clouds = fbm(q + drift);
        clouds += 0.5 * fbm(q * 2.3 - drift);
        clouds /= 1.5;

        float shadow = smoothstep(0.45, 0.72, clouds);
        float alpha = shadow * 0.35 * u_day; // no shadows without sun
        final_color = vec4(0.0, 0.0, 0.0, alpha);
    }
}
