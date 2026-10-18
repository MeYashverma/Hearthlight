/*
    Hearthlight - untextured geometry: the sky plane, the void plane and the
    block outline.
*/

#include "/include/global.glsl"

out vec4 tint;

void main() {
    tint = gl_Color;
    gl_Position = gl_ModelViewProjectionMatrix * gl_Vertex;
}
