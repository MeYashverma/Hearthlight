/*
    Hearthlight - terrain vertex shader
    Shared by gbuffers_terrain (solid and cutout) and gbuffers_water.
*/

#include "/include/global.glsl"

out vec2 uv;
out vec2 light_levels;
out vec3 scene_pos;
out vec3 scene_normal;
out vec4 tint;
flat out int material_mask;

attribute vec3 at_midBlock;
attribute vec3 mc_Entity;

void main() {
    uv = gl_MultiTexCoord0.xy;
    // Vanilla packs light and sky light as two 4 bit values in 0..240.
    light_levels = saturate(gl_MultiTexCoord1.xy * (1.0 / 240.0));
    tint = gl_Color;

    // mc_Entity.x is the ID from block.properties (10000 + N), or -1 for blocks
    // that the pack does not mention. Iris rewrites this attribute to an
    // integer on Sodium; the arithmetic below works either way.
    material_mask = int(mc_Entity.x) - 10000;

    vec3 view_pos = (gl_ModelViewMatrix * vec4(gl_Vertex.xyz, 1.0)).xyz;
    scene_pos = mat3(gbufferModelViewInverse) * view_pos;
    scene_normal = mat3(gbufferModelViewInverse) * (gl_NormalMatrix * gl_Normal);

    gl_Position = gl_ProjectionMatrix * vec4(view_pos, 1.0);
}
