// Screen-space local-light shadows.
//
// The voxel volume is half-block: good for slabs, stairs and doors, but a
// player, a mob, a fence, a pane or a dropped item can never be in it, so those
// cast no shadow from a torch. The depth buffer has the real geometry, so for
// the strongest few local lights a second ray is marched through depthtex1 and
// blended with the voxel result.
//
// depthtex1 (not depthtex0) so glass, water and portals do not block torchlight.
#ifndef HL_SSSHADOW_GLSL
#define HL_SSSHADOW_GLSL

uniform sampler2D depthtex1;
uniform mat4 gbufferProjection;

// Distance behind a depth sample before the ray counts as blocked. Small keeps
// thin geometry sharp; too small and surfaces shadow themselves.
const float SS_LIGHT_THICKNESS = 0.22;

// Stop this far short of the light so the emitter's own block (a glowstone cube,
// a lantern) does not shadow the surface it is lighting.
const float SS_LIGHT_STOP = 0.80;

// Player space -> view space (mat3(gbufferModelViewInverse) is view -> world).
vec3 hl_worldToView(vec3 v, mat4 modelViewInverse) {
    return transpose(mat3(modelViewInverse)) * v;
}

// Returns vec2(visibility, confidence):
//   visibility 0 = blocked, 1 = clear.
//   confidence 0 = the ray left the screen at once (trust the voxel result),
//              1 = the ray reached the light's own block unblocked.
vec2 hl_ssLocalShadow(vec3 viewPos, vec3 lightView, mat4 projInverse) {
    vec3 d = lightView - viewPos;
    float len = length(d);
    if (len < 1e-3) return vec2(1.0, 1.0);
    d /= len;

    float stop = max(len - SS_LIGHT_STOP, 0.10);
    float t = 0.10;                 // skip the surface's own depth
    float stepLen = 0.20;
    float covered = 0.0;

    for (int i = 0; i < LIGHT_SS_STEPS; i++) {
        float dt = min(stepLen, stop - t);
        if (dt <= 1e-4) { covered = 1.0; break; }
        t += dt;
        stepLen *= 1.18;
        covered = t / stop;

        vec3 p = viewPos + d * t;
        float rayZ = -p.z;
        if (rayZ <= 0.05) break;

        vec4 clip = gbufferProjection * vec4(p, 1.0);
        if (clip.w <= 1e-3) break;
        vec2 uv = clip.xy / clip.w * 0.5 + 0.5;
        if (any(lessThan(uv, vec2(0.0))) || any(greaterThan(uv, vec2(1.0)))) break;

        float sd = texture(depthtex1, uv).r;
        if (sd >= 1.0) continue;                       // sky behind

        vec4 s = projInverse * vec4(vec3(uv, sd) * 2.0 - 1.0, 1.0);
        float sceneZ = -s.z / s.w;
        if (rayZ - sceneZ > SS_LIGHT_THICKNESS) return vec2(0.0, 1.0);
    }

    return vec2(1.0, smoothstep(0.45, 0.95, covered));
}

#endif
