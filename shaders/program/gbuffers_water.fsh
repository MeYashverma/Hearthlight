/*
    Hearthlight - translucent terrain (water, stained glass, ice, ...)

    The water surface gets a small animated normal perturbation so that the
    sun glint moves, everything else is shaded like opaque terrain and blended
    by the vanilla blend state.
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

// Two octaves of scrolling value noise, used only to break up the specular
// highlight. No geometry displacement, so the surface stays cheap.
vec3 water_normal(vec3 base_normal, vec3 scene_pos) {
    vec2 p = scene_pos.xz * 0.8 + scene_pos.y * 0.35;
    float t = frameTimeCounter * 0.55;

    vec2 gradient;
    gradient.x = value_noise(p + vec2(t, 0.0))
        - value_noise(p + vec2(t, 0.0) + vec2(0.08, 0.0));
    gradient.y = value_noise(p + vec2(0.0, t * 1.3))
        - value_noise(p + vec2(0.0, t * 1.3) + vec2(0.0, 0.08));

    vec3 perturbed = base_normal + vec3(gradient.x, 0.0, gradient.y) * 3.0;
    return safe_normalize(perturbed, base_normal);
}

void main() {
    vec4 albedo = texture(gtexture, uv) * tint;
    if (albedo.a < 0.02) {
        discard;
    }

    vec3 normal = safe_normalize(scene_normal, vec3(0.0, 1.0, 0.0));

    // Only upward facing surfaces get the animated glint; sides of glass panes
    // should stay flat.
    if (normal.y > 0.9) {
        normal = water_normal(normal, scene_pos);
    }

    vec3 colour
        = shade_surface(albedo.rgb, normal, scene_pos, light_levels, material_mask);

    // Water: a sharp sun/moon highlight plus a little fresnel so the surface
    // reads as a liquid even when the sky is overcast.
    if (material_mask == 80 || material_mask == 0) {
        colour += water_specular(normal, scene_pos, light_levels, 220.0);

        vec3 V = safe_normalize(-scene_pos, vec3(0.0, 0.0, 1.0));
        float fresnel = pow(1.0 - saturate(dot(normal, V)), 4.0);
        colour += fresnel * 0.08 * texture(lightmap, clamp(light_levels, vec2(0.04), vec2(0.96))).rgb;
    }

    colour = apply_fog(colour, length(scene_pos));
    frag_color = vec4(colour, albedo.a);
}
