/*
    Hearthlight - unlit textured geometry.

    Sky elements must stay exactly as vanilla draws them: they already carry the
    finished sky colour, and any lighting here would break the horizon.
*/

#include "/include/global.glsl"
#include "/include/fog.glsl"

uniform sampler2D gtexture;

in vec2 uv;
in vec3 scene_pos;
in vec4 tint;

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 frag_color;

void main() {
    vec4 colour = texture(gtexture, uv) * tint;
    if (colour.a < 0.004) {
        discard;
    }

    // Vanilla fades clouds into the horizon, nothing else.
    if (renderStage == MC_RENDER_STAGE_CLOUDS) {
        colour.rgb = apply_fog(colour.rgb, length(scene_pos));
    }

    frag_color = colour;
}
