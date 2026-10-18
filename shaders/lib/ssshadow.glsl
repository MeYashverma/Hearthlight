// Screen-space sun shadow.
//
// The voxel volume is a 1-block grid: a door, a fence rail, a trapdoor, a
// player or a dropped item can only ever be a whole cube in it. Those are
// exactly the shapes people notice, so the sun gets a second, precise shadow:
// one ray per pixel marched through depthtex1, which holds the real geometry
// Iris just drew (depthtex1 rather than depthtex0 so glass, water and portals
// do not block sunlight).
//
// The two results are combined by confidence: once the ray has walked far
// enough that any occluder of a visible surface would have been on screen, the
// depth buffer is the better answer and the blocky voxel square is dropped.
// For the first block or two (and whenever the sun is behind the camera) the
// voxel result is kept, because the ray simply has no data there.
#ifndef HL_SSSHADOW_GLSL
#define HL_SSSHADOW_GLSL

uniform sampler2D depthtex1;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;   // used after this include in deferred.fsh

// How far behind a depth sample the ray must be before that sample counts as an
// occluder. Larger = fatter, safer shadows; smaller = nails thin geometry but
// risks self-shadowing stripes.
const float SS_START = 0.12;
const float SS_THICKNESS = 0.28;
const float SS_MAX_DIST = 32.0;

// Returns vec2(visibility, confidence).
//   visibility: 0 = an occluder was found, 1 = the ray was clear.
//   confidence: how much the clear result should override the voxel shadow.
//               0 = the ray left the screen immediately, 1 = full distance.
vec2 hl_ssSunShadow(vec3 viewPos, vec3 dirView) {
    vec3 p = viewPos + dirView * SS_START;
    float stepLen = 0.18;
    float travelled = 0.0;

    for (int i = 0; i < SS_SHADOW_STEPS; i++) {
        float dt = min(stepLen, SS_MAX_DIST - travelled);
        if (dt <= 1e-4) break;
        p += dirView * dt;
        travelled += dt;
        stepLen *= 1.25;

        float rayZ = -p.z;
        if (rayZ <= 0.05) break;                              // ray went behind the camera

        vec4 clip = gbufferProjection * vec4(p, 1.0);
        if (clip.w <= 1e-3) break;
        vec2 uv = clip.xy / clip.w * 0.5 + 0.5;
        if (any(lessThan(uv, vec2(0.0))) || any(greaterThan(uv, vec2(1.0)))) break;

        float d = texture(depthtex1, uv).r;
        if (d >= 1.0) continue;                                // nothing drawn there

        vec4 s = gbufferProjectionInverse * vec4(vec3(uv, d) * 2.0 - 1.0, 1.0);
        float sceneZ = -s.z / s.w;
        if (rayZ - sceneZ > SS_THICKNESS + 0.012 * travelled) return vec2(0.0, 1.0);
    }

    // Any occluder that matters for a surface you can see is within a few
    // blocks of it; after ~6 blocks of clear ray the voxel shadow is trusted
    // less than the depth buffer.
    return vec2(1.0, smoothstep(1.5, 6.0, travelled));
}

#endif
