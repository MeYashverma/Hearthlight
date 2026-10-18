/*
    Hearthlight - textured and lit fragment shader
*/

#include "/include/global.glsl"
#include "/include/shading.glsl"

uniform sampler2D gtexture;

in vec2 uv;
in vec2 light_levels;
in vec3 scene_pos;
in vec3 scene_normal;
in vec4 tint;

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 frag_color;

// The hand is drawn right in front of the camera, where the shadow map has no
// useful information and where the held light should dominate.
vec3 shade_hand(vec3 albedo, vec2 light_levels) {
    vec2 lm = clamp(light_levels, vec2(0.5 / 16.0), vec2(15.5 / 16.0));
    vec3 lm_colour = texture(lightmap, lm).rgb;
    vec3 colour = albedo * lm_colour;
    colour += albedo * get_held_light(scene_pos) * 2.2;
    return colour;
}

void main() {
    vec4 albedo = texture(gtexture, uv) * tint;
    if (albedo.a < 0.1) {
        discard;
    }

    vec3 normal = safe_normalize(scene_normal, safe_normalize(scene_pos, vec3(0.0, 1.0, 0.0)));

    bool is_hand = renderStage == MC_RENDER_STAGE_HAND_SOLID
        || renderStage == MC_RENDER_STAGE_HAND_TRANSLUCENT;

    vec3 colour = is_hand ? shade_hand(albedo.rgb, light_levels)
                          : shade_surface(
                                albedo.rgb,
                                normal,
                                scene_pos,
                                light_levels,
                                0
                            );

    colour = apply_fog(colour, length(scene_pos));
    frag_color = vec4(colour, albedo.a);
}
