/*
    Hearthlight - opaque terrain

    Everything is shaded here, in the same gamma space that the textures and the
    vanilla lightmap live in. That keeps the look close to vanilla, and it means
    the pack needs no composite or deferred pass at all.
*/

#include "/include/global.glsl"
#include "/include/shading.glsl"

uniform sampler2D gtexture;

in vec2 uv;
in vec2 light_levels;
in vec3 scene_pos;
in vec3 scene_normal;
in vec4 tint;
flat in int material_mask;

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 frag_color;

void main() {
    vec4 albedo = texture(gtexture, uv) * tint;

    // Cutout foliage, panes and the like. Matches block.properties, which lists
    // the blocks that need an alpha test in its transparent ranges.
    if (albedo.a < 0.1) {
        discard;
    }

    vec3 normal = safe_normalize(scene_normal, vec3(0.0, 1.0, 0.0));

#if DEBUG_VIEW == 1
    float NoL = saturate(dot(normal, get_light_dir()));
    frag_color = vec4(vec3(get_shadow(scene_pos, normal, NoL)), 1.0);
    return;
#elif DEBUG_VIEW == 2
    frag_color = vec4(sample_light_volume(scene_pos, normal) * 4.0, 1.0);
    return;
#elif DEBUG_VIEW == 3
    frag_color = vec4(normal * 0.5 + 0.5, 1.0);
    return;
#elif DEBUG_VIEW == 4
    frag_color = vec4(get_light_dir() * 0.5 + 0.5, 1.0);
    return;
#endif

    vec3 colour
        = shade_surface(albedo.rgb, normal, scene_pos, light_levels, material_mask);
    colour = apply_fog(colour, length(scene_pos));

    frag_color = vec4(colour, 1.0);
}
