/*
    Hearthlight - unlit textured geometry: sky, clouds, sun, moon, stars,
    enchantment glint and beacon beams.
*/

#include "/include/global.glsl"

out vec2 uv;
out vec3 scene_pos;
out vec4 tint;

void main() {
    uv = gl_MultiTexCoord0.xy;
    tint = gl_Color;

    vec3 view_pos = (gl_ModelViewMatrix * vec4(gl_Vertex.xyz, 1.0)).xyz;
    scene_pos = mat3(gbufferModelViewInverse) * view_pos;

    gl_Position = gl_ProjectionMatrix * vec4(view_pos, 1.0);
}
