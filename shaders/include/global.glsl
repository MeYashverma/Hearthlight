#ifndef HEARTHLIGHT_GLOBAL
#define HEARTHLIGHT_GLOBAL

#include "/include/settings.glsl"

// -----------------------------------------------------------------------------
// Dimension. Iris picks the world folder, the wrapper files define WORLD_*.
// -----------------------------------------------------------------------------
#if defined WORLD_NETHER
const bool DIM_OVERWORLD = false;
const bool DIM_NETHER = true;
const bool DIM_END = false;
#elif defined WORLD_END
const bool DIM_OVERWORLD = false;
const bool DIM_NETHER = false;
const bool DIM_END = true;
#else
const bool DIM_OVERWORLD = true;
const bool DIM_NETHER = false;
const bool DIM_END = false;
#endif

// Render stage IDs come from Iris itself: it injects a `MC_RENDER_STAGE_<PHASE>`
// macro for every WorldRenderingPhase into every program, with the ordinal as
// the value. Do not declare them here - a `const int` with one of those names
// expands to `const int 0`, which Iris' parser rejects.
// (`renderStage` is the ordinal, see WorldRenderingPhase in Iris.)

// -----------------------------------------------------------------------------
// Uniforms supplied by Iris
// -----------------------------------------------------------------------------

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferPreviousModelView;

uniform mat4 shadowModelView;
uniform mat4 shadowModelViewInverse;
uniform mat4 shadowProjection;
uniform mat4 shadowProjectionInverse;

uniform vec3 cameraPosition;
uniform vec3 previousCameraPosition;

uniform vec3 sunPosition;
uniform vec3 moonPosition;
uniform vec3 shadowLightPosition;
uniform vec3 upPosition;

uniform float sunAngle;
uniform float frameTimeCounter;
uniform float rainStrength;
uniform float wetness;
uniform int frameCounter;
uniform int renderStage;

uniform bool hasSkylight;
uniform bool hasCeiling;

uniform int isEyeInWater;
uniform float near;
uniform float far;

// -----------------------------------------------------------------------------
// Constants and helpers
// -----------------------------------------------------------------------------

const float PI = 3.14159265358979323846;
const float TAU = 6.28318530717958647692;

float saturate(float x) { return clamp(x, 0.0, 1.0); }
vec2 saturate(vec2 x) { return clamp(x, 0.0, 1.0); }
vec3 saturate(vec3 x) { return clamp(x, 0.0, 1.0); }

float luma(vec3 c) { return dot(c, vec3(0.2126, 0.7152, 0.0722)); }

vec3 safe_normalize(vec3 v, vec3 fallback) {
    float l = length(v);
    return l > 1.0e-6 ? v / l : fallback;
}

float hash12(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// Value noise, used for cloud shapes and the animated water normal.
float value_noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash12(i);
    float b = hash12(i + vec2(1.0, 0.0));
    float c = hash12(i + vec2(0.0, 1.0));
    float d = hash12(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Cheap per-pixel rotation used for shadow PCF taps.
float interleaved_gradient_noise(vec2 p) {
    return fract(52.9829189 * fract(dot(p, vec2(0.06711056, 0.00583715))));
}

// Vogel disk sample, i / n in [0, 1).
vec2 vogel_disk(int i, int n, float rotation) {
    float r = sqrt((float(i) + 0.5) / float(n));
    float theta = float(i) * 2.399963229728653 + rotation;
    return vec2(cos(theta), sin(theta)) * r;
}

// Fourth root of x^4 + y^4. Iris uses the same curve for the shadow map, so
// sampling with it keeps texel density where the player looks.
float quartic_length(vec2 v) {
    float x2 = v.x * v.x;
    float y2 = v.y * v.y;
    return sqrt(sqrt(x2 * x2 + y2 * y2));
}

// Orthographic matrices have no perspective divide, so the diagonal and the
// translation are all that matter. Saves three dot products per call.
vec3 project_ortho(mat4 m, vec3 p) {
    return vec3(m[0][0], m[1][1], m[2][2]) * p + m[3].xyz;
}

vec3 scene_dir(vec3 view_dir) {
    return safe_normalize(
        mat3(gbufferModelViewInverse) * view_dir,
        vec3(0.0, 1.0, 0.0)
    );
}

// Iris builds sunPosition/moonPosition by pushing (0, 100, 0) through
// gbufferModelView (see CelestialUniforms.getCelestialPosition), so they are in
// **view space** and rotate with the camera. Comparing one of those directly
// against a scene-space normal gives a light direction that turns with the
// player, which is what makes sunlight and its shadows pop in and out as you
// look around. They have to go through gbufferModelViewInverse first.
vec3 get_sun_dir() { return scene_dir(sunPosition); }
vec3 get_moon_dir() { return scene_dir(moonPosition); }

// The overworld has a sun by day and a moon by night. The nether and the end
// have neither, they only get ambient light.
bool is_day() {
    return DIM_OVERWORLD && sunAngle < 0.5;
}

bool has_directional_light() { return DIM_OVERWORLD; }

vec3 get_light_dir() { return is_day() ? get_sun_dir() : get_moon_dir(); }

#endif
