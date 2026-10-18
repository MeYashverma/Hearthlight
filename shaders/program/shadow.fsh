/*
    Hearthlight - shadow fragment shader

    Depth only. Iris copies the opaque depth buffer into shadowtex1, which is
    the map the lighting code reads, so this shader never needs to write a
    colour attachment: the cutout alpha test is all that is left to do.
*/

#include "/include/global.glsl"

uniform sampler2D gtexture;

/* RENDERTARGETS: 0 */

in vec2 uv;
flat in int material_mask;

void main() {
    if (texture(gtexture, uv).a < 0.1) {
        discard;
    }
}
