/*
    Hearthlight - textured and lit geometry: entities, items, particles,
    weather, the hand and block entities.
*/

#include "/include/global.glsl"

out vec2 uv;
out vec2 light_levels;
out vec3 scene_pos;
out vec3 scene_normal;
out vec4 tint;

void main() {
    uv = gl_MultiTexCoord0.xy;
    light_levels = saturate(gl_MultiTexCoord1.xy * (1.0 / 240.0));
    tint = gl_Color;

    vec3 view_pos = (gl_ModelViewMatrix * vec4(gl_Vertex.xyz, 1.0)).xyz;
    scene_pos = mat3(gbufferModelViewInverse) * view_pos;
    scene_normal = mat3(gbufferModelViewInverse) * (gl_NormalMatrix * gl_Normal);

    gl_Position = gl_ProjectionMatrix * vec4(view_pos, 1.0);
}
