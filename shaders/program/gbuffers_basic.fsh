/*
    Hearthlight - untextured geometry.

    The sky plane is drawn with its final colour in the vertex colour, so this
    simply passes it through.
*/

#include "/include/global.glsl"

in vec4 tint;

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 frag_color;

void main() {
    frag_color = tint;
}
