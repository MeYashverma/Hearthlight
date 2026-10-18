// Sun and moon lighting: direction, direct-light colour, ray-traced shadows and
// material-aware specular highlights.
//
// The shadow pass in this pack is a voxelizer, not a depth-map renderer, so sun
// shadows are traced through the very same 128^3 occupancy volume that the local
// lights use. One ray per pixel from the surface toward the sun; the volume holds
// every full cube within 64 blocks of the camera, which is exactly the range that
// produces readable shadows.
//
// Iris builds sunPosition/moonPosition by pushing (0,100,0) through the G-buffer
// model-view matrix, so they are in *view* space and rotate with the camera.
// Comparing one directly against a world normal gives light directions that turn
// with the player, so everything below goes through gbufferModelViewInverse.
#ifndef HL_SUN_GLSL
#define HL_SUN_GLSL

#include "/lib/common.glsl"

uniform mat4 gbufferModelViewInverse;
uniform vec3 sunPosition;
uniform vec3 moonPosition;
uniform float sunAngle;

layout(r8) readonly uniform image3D voxelOcc;

vec3 hl_sunDir() { return normalize(mat3(gbufferModelViewInverse) * sunPosition); }
vec3 hl_moonDir() { return normalize(mat3(gbufferModelViewInverse) * moonPosition); }

// Player space -> view space (the 3x3 of gbufferModelViewInverse is view -> world).
vec3 hl_worldToView(vec3 v) { return transpose(mat3(gbufferModelViewInverse)) * v; }

// Sunlight reddens and dims toward the horizon; moonlight is a constant blue.
vec3 hl_sunColor(vec3 dir) {
    float h = clamp(dir.y, 0.0, 1.0);
    return mix(vec3(1.00, 0.45, 0.20), vec3(1.00, 0.95, 0.86), smoothstep(0.0, 0.35, h));
}
const vec3 HL_MOON_COLOR = vec3(0.50, 0.62, 1.00);

// Direct light: whichever body is above the horizon, blended across twilight.
//   up  = 0..1, how much direct light there is to shadow (moonlight is weaker).
//   day = 0..1, how much of that is the *sun*; drives daylight suppression so
//         local lights are never dimmed by moonlight.
void hl_direct(out vec3 dir, out vec3 color, out float up, out float day) {
    vec3 sd = hl_sunDir();
    vec3 md = hl_moonDir();
    float ws = smoothstep(-0.04, 0.06, sd.y);
    float wm = smoothstep(-0.04, 0.06, md.y);
    float sum = max(ws + wm, 1e-3);

    dir = normalize(sd * ws + md * wm);
    color = (hl_sunColor(sd) * ws + HL_MOON_COLOR * wm) / sum;
    day = (ws / sum) * smoothstep(-0.02, 0.22, sd.y);
    up = smoothstep(-0.02, 0.22, max(sd.y, md.y)) * mix(0.40, 1.0, ws / sum);
}

// Amanatides-Woo walk toward the sun until the ray leaves the volume.
// Returns transmittance: 0 = fully shadowed, 1 = fully lit.
float hl_sunVis(vec3 P, vec3 N) {
    vec3 dir, color;
    float up, day;
    hl_direct(dir, color, up, day);
    if (up <= 0.001) return 1.0;

    // Step off the surface so the owning cube cannot shadow itself.
    vec3 o = P + N * 0.06 + dir * 0.02;

    ivec3 cell = ivec3(floor(o));
    ivec3 stp = ivec3(sign(dir));
    vec3 inv = 1.0 / (abs(dir) + 1e-6);
    vec3 frac = mix(o - vec3(cell), vec3(cell) + 1.0 - o, vec3(greaterThan(stp, ivec3(0))));
    vec3 tMax = frac * inv;
    vec3 tDelta = inv;

    float trans = 1.0;
    for (int i = 0; i < SUN_SHADOW_STEPS; i++) {
        if (tMax.x <= tMax.y && tMax.x <= tMax.z) { cell.x += stp.x; tMax.x += tDelta.x; }
        else if (tMax.y <= tMax.z)                { cell.y += stp.y; tMax.y += tDelta.y; }
        else                                      { cell.z += stp.z; tMax.z += tDelta.z; }

        if (any(lessThan(cell, ivec3(0))) || any(greaterThanEqual(cell, ivec3(VOXEL_RES)))) break;

        trans *= 1.0 - imageLoad(voxelOcc, cell).r;
        if (trans < 0.02) return 0.0;
    }
    return trans;
}

// Roughness / reflectance for the material classes assigned in block.properties.
void hl_material(float cls, out float roughness, out float reflectance, out float strength) {
    roughness = 0.85;
    reflectance = 0.03;
    strength = 0.25;
    if (cls < 0.5) return;                // terrain without a class, entities
    if (cls < 1.5)      { roughness = 0.20; reflectance = 0.90; strength = 1.00; }  // 1 metal
    else if (cls < 2.5) { roughness = 0.33; reflectance = 0.35; strength = 0.75; }  // 2 polished stone / quartz / amethyst
    else if (cls < 3.5) { roughness = 0.16; reflectance = 0.18; strength = 0.85; }  // 3 ice / snow
    else if (cls < 4.5) { roughness = 0.28; reflectance = 0.45; strength = 0.70; }  // 4 glazed terracotta
    else                { roughness = 0.42; reflectance = 0.18; strength = 0.45; }  // 5 emitters
}

// GGX + Smith + Schlick against the sun or moon. `vis` is the shadow result.
vec3 hl_specular(vec3 N, vec3 playerPos, float vis, float cls) {
    float roughness, reflectance, strength;
    hl_material(cls, roughness, reflectance, strength);
    if (strength <= 0.0 || SUN_SPECULAR <= 0.0) return vec3(0.0);

    vec3 dir, color;
    float up, day;
    hl_direct(dir, color, up, day);
    if (up <= 0.001) return vec3(0.0);

    vec3 L = dir;
    vec3 V = normalize(-playerPos);
    vec3 H = normalize(L + V);

    float NoL = clamp(dot(N, L), 0.0, 1.0);
    float NoV = max(dot(N, V), 1e-3);
    float NoH = clamp(dot(N, H), 0.0, 1.0);
    float VoH = clamp(dot(V, H), 0.0, 1.0);
    if (NoL <= 0.0) return vec3(0.0);

    float a = roughness * roughness;
    float a2 = a * a;
    float d = NoH * NoH * (a2 - 1.0) + 1.0;
    float D = a2 / (3.14159265 * d * d);
    float k = a * 0.5;
    float G = (NoL / (NoL * (1.0 - k) + k)) * (NoV / (NoV * (1.0 - k) + k));
    float F = reflectance + (1.0 - reflectance) * pow(1.0 - VoH, 5.0);

    // Soft shoulder: the raw GGX peak of a polished metal is ~45, which would
    // clip to flat white. Reinhard on the scalar keeps the highlight's hue and
    // bounds it to ~3.3 instead of destroying the block's colour.
    float spec = D * G * F / (4.0 * NoL * NoV + 1e-4);
    spec = spec / (1.0 + spec * 0.30);
    return color * (spec * NoL * vis * strength * SUN_SPECULAR * up);
}

#endif
