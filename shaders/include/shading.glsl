#ifndef HEARTHLIGHT_SHADING
#define HEARTHLIGHT_SHADING

#include "/include/fog.glsl"
#include "/include/light_colors.glsl"
#include "/include/voxel.glsl"

uniform sampler2D lightmap;
uniform sampler2D shadowtex1;

uniform sampler3D light_sampler_a;
uniform sampler3D light_sampler_b;

uniform int heldItemId;
uniform int heldItemId2;
uniform int heldBlockLightValue;
uniform int heldBlockLightValue2;
uniform vec3 heldBlockLightColor;
uniform vec3 heldBlockLightColor2;

// -----------------------------------------------------------------------------
// Sun and moon. Directions are scene space (see global.glsl).
// -----------------------------------------------------------------------------

vec3 get_sun_color() {
    float height = saturate(get_sun_dir().y);
    vec3 warm = vec3(1.00, 0.44, 0.18);
    vec3 noon = vec3(1.00, 0.94, 0.84);
    return mix(warm, noon, smoothstep(0.0, 0.40, height));
}

vec3 get_moon_color() { return vec3(0.52, 0.64, 1.00); }

// How much of the vanilla lightmap survives in the shade. Vanilla has no
// shadows at all, so its lightmap is already "full" brightness; darkening it a
// little is what makes the added sunlight read as sunlight.
const float AMBIENT_STRENGTH = 0.70;

const float SUN_INTENSITY = 0.65;
const float MOON_INTENSITY = 0.14;

vec3 get_direct_light_color() {
    if (!has_directional_light()) {
        return vec3(0.0);
    }
    return is_day() ? get_sun_color() * SUN_INTENSITY
                    : get_moon_color() * MOON_INTENSITY;
}

// -----------------------------------------------------------------------------
// Shadow map
// -----------------------------------------------------------------------------

float get_shadow(vec3 scene_pos, vec3 normal, float NoL) {
    if (!has_directional_light()) {
        return 1.0;
    }

    // Normal bias plus a small distance dependent term. Slope scaling keeps
    // grazing surfaces (grass, carpets, snow layers) from shadowing
    // themselves without pushing shadows away from their caster.
    vec3 bias = normal
        * (0.05 + 0.010 * min(length(scene_pos), 64.0))
        * (1.5 - 0.5 * clamp(NoL, 0.0, 1.0));

    vec3 shadow_view = (shadowModelView * vec4(scene_pos + bias, 1.0)).xyz;
    vec3 clip = project_ortho(shadowProjection, shadow_view);

    // Matches the distortion the shadow vertex shader rasterised with: a fourth
    // root radial warp in xy and a 0.2 scale on z.
    float distortion = quartic_length(clip.xy) * SHADOW_DISTORTION
        + (1.0 - SHADOW_DISTORTION);

    vec2 uv = (clip.xy / distortion) * 0.5 + 0.5;
    float reference = clip.z * SHADOW_DEPTH_SCALE * 0.5 + 0.5;

    // Outside the map in depth, or past its border: treat as lit.
    if (reference < 0.0 || reference > 1.0) {
        return 1.0;
    }

    float edge = smoothstep(0.90, 1.0, max(abs(clip.x), abs(clip.y)));

    // Filter width grows towards the edge of the map, where the distortion has
    // stretched the texels.
    float radius = SHADOW_SOFTNESS / float(shadowMapResolution) * distortion;

    float rotation = interleaved_gradient_noise(
                         gl_FragCoord.xy + float(frameCounter & 31)
                     )
        * TAU;

    int resolution = shadowMapResolution;
    float lit = 0.0;
    for (int i = 0; i < SHADOW_PCF_TAPS; ++i) {
        vec2 offset = vogel_disk(i, SHADOW_PCF_TAPS, rotation) * radius;
        vec2 coord = clamp(uv + offset, vec2(0.0), vec2(1.0));
        // texelFetch ignores the texture's compare mode, so the stored depth
        // comes back raw whether or not hardware shadow filtering is enabled.
        float stored = texelFetch(shadowtex1, ivec2(coord * resolution), 0).r;
        lit += step(reference - 6.0e-5, stored);
    }
    lit /= float(SHADOW_PCF_TAPS);

    return mix(lit, 1.0, edge);
}

// -----------------------------------------------------------------------------
// Coloured block light
// -----------------------------------------------------------------------------

// Raw colour stored in the light volume at this point, or black outside it.
vec3 sample_light_volume(vec3 scene_pos, vec3 normal) {
    vec3 voxel_pos = scene_to_voxel(scene_pos);
    if (!inside_voxel_volume(voxel_pos)) {
        return vec3(0.0);
    }

    vec3 uvw = voxel_sample_uvw(scene_pos, normal);
    return ((frameCounter & 1) == 0)
        ? texture(light_sampler_a, uvw).rgb
        : texture(light_sampler_b, uvw).rgb;
}

vec3 get_blocklight_tint(vec3 scene_pos, vec3 normal) {
    vec3 colour = sample_light_volume(scene_pos, normal);

    float brightness = luma(colour);
    if (brightness < 0.02) {
        return vec3(1.0);
    }

    // Normalise to a pure hue. The lightmap already carries the intensity, this
    // volume only says what colour the light is.
    vec3 tint = clamp(colour / brightness, 0.0, 2.5);

    // Fade the tint in rather than switching it on at the edge of the volume.
    float strength = COLORED_LIGHT_STRENGTH
        * smoothstep(0.02, 0.10, brightness);

    return mix(vec3(1.0), tint, strength);
}

// Coloured light from a torch in the hand. `heldBlockLightColor` is white for
// vanilla items, so the item ID table fills in the colour instead.
vec3 get_held_light_color() {
    float main = float(heldBlockLightValue) / 15.0;
    float off = float(heldBlockLightValue2) / 15.0;

    vec3 main_color = heldBlockLightColor * held_item_color(heldItemId - 10000);
    vec3 off_color = heldBlockLightColor2
        * held_item_color(heldItemId2 - 10000);

    return main_color * main * main + off_color * off * off;
}

vec3 get_held_light(vec3 scene_pos) {
    if (heldBlockLightValue == 0 && heldBlockLightValue2 == 0) {
        return vec3(0.0);
    }

    float falloff = 1.0 - smoothstep(1.0, 16.0, length(scene_pos));
    return get_held_light_color() * falloff * HANDHELD_LIGHT_STRENGTH;
}

// -----------------------------------------------------------------------------
// Specular highlights
// -----------------------------------------------------------------------------

// Roughness and reflectance per material. The IDs come from block.properties
// (10001..10004) and are opaque to the light volume, so they sit in the plain
// 1..31 range of the material mask.
void get_material_specular(
    int material,
    out float roughness,
    out float reflectance,
    out float strength
) {
    // Defaults: matte, like dirt or planks, with just enough sheen that a
    // grazing sun angle still catches.
    roughness = 0.82;
    reflectance = 0.035;
    strength = 0.22;

    if (material == 1) { // metal blocks
        roughness = 0.22;
        reflectance = 0.85;
        strength = 1.00;
    } else if (material == 2) { // polished stone, quartz, amethyst, glazed
        roughness = 0.34;
        reflectance = 0.28;
        strength = 0.70;
    } else if (material == 3) { // ice, packed/blue ice, snow, frosted
        roughness = 0.18;
        reflectance = 0.16;
        strength = 0.85;
    } else if (material == 4) { // cut copper / oxidised copper, still metallic
        roughness = 0.40;
        reflectance = 0.55;
        strength = 0.75;
    } else if (material >= 32 && material < 80) { // emitters read as glossy
        roughness = 0.45;
        reflectance = 0.20;
        strength = 0.55;
    }
}

// GGX / Smith / Schlick, evaluated in the same gamma space as the rest of the
// pack. Not energy conserving against the albedo, but a highlight that reads is
// the point and the cost is one pow() per light.
vec3 specular_highlight(
    vec3 normal,
    vec3 scene_pos,
    vec3 light_dir,
    vec3 light_colour,
    float shadow,
    float roughness,
    float reflectance,
    float strength
) {
    if (strength <= 0.0 || !has_directional_light()) {
        return vec3(0.0);
    }

    vec3 V = safe_normalize(-scene_pos, vec3(0.0, 0.0, 1.0));
    vec3 H = safe_normalize(light_dir + V, light_dir);

    float NoL = saturate(dot(normal, light_dir));
    float NoV = max(dot(normal, V), 1.0e-3);
    float NoH = saturate(dot(normal, H));
    float VoH = saturate(dot(V, H));

    if (NoL <= 0.0) {
        return vec3(0.0);
    }

    float a = roughness * roughness;
    float a2 = a * a;

    // GGX normal distribution.
    float d = NoH * NoH * (a2 - 1.0) + 1.0;
    float D = a2 / (PI * d * d);

    // Smith geometry term, Schlick approximation of the masking.
    float k = a * 0.5;
    float G = (NoL / (NoL * (1.0 - k) + k))
        * (NoV / (NoV * (1.0 - k) + k));

    // Schlick fresnel.
    float F = reflectance + (1.0 - reflectance) * pow(1.0 - VoH, 5.0);

    float spec = D * G * F / (4.0 * NoL * NoV + 1.0e-4);

    return light_colour * spec * NoL * shadow * strength;
}

// -----------------------------------------------------------------------------
// Surface shading
// -----------------------------------------------------------------------------

// `albedo` is in gamma space, exactly as it comes out of the block atlas, and
// so is the lightmap colour. Staying in that space keeps the pack looking like
// vanilla and avoids a tone mapping step that a small GPU cannot afford.
vec3 shade_surface(
    vec3 albedo,
    vec3 normal,
    vec3 scene_pos,
    vec2 light_levels,
    int material
) {
    vec2 lm = clamp(light_levels, 0.0, 1.0);
    // The vanilla lightmap is a 16x16 texture; sampling it at texel centres
    // reproduces the exact vanilla light curve, including weather, night and
    // night vision.
    vec2 lm_uv = clamp(lm, vec2(0.5 / 16.0), vec2(15.5 / 16.0));
    vec3 lm_colour = texture(lightmap, lm_uv).rgb;

    float block_weight = smoothstep(0.03, 0.45, lm.x);
    vec3 tint = get_blocklight_tint(scene_pos, normal);
    vec3 ambient_tint = mix(vec3(1.0), tint, block_weight);
    float ambient_strength = mix(AMBIENT_STRENGTH, 1.0, block_weight);

    vec3 ambient = albedo * lm_colour * ambient_tint * ambient_strength;

    vec3 L = get_light_dir();
    float NoL = saturate(dot(normal, L));
    // Sky light of zero means the point is under a solid ceiling; the shadow
    // map has nothing useful to say there.
    float sky_visibility = smoothstep(0.0, 0.28, lm.y);
    float shadow = get_shadow(scene_pos, normal, NoL);

    vec3 light_colour = get_direct_light_color();
    vec3 direct = albedo * light_colour * NoL * shadow * sky_visibility
        * (1.0 - 0.6 * rainStrength);

    float roughness;
    float reflectance;
    float strength;
    get_material_specular(material, roughness, reflectance, strength);

    vec3 specular = specular_highlight(
        normal,
        scene_pos,
        L,
        light_colour,
        shadow * sky_visibility * (1.0 - 0.5 * rainStrength),
        roughness,
        reflectance,
        strength
    );

    vec3 colour = ambient + direct + specular;
    colour += albedo * get_held_light(scene_pos);

    // Let the emitting block itself read as a light source in addition to the
    // light it puts into the colour volume.
    if (is_emitter_mask(material)) {
        colour += albedo * emitter_color(material) * 0.4;
    }

    // Soft shoulder instead of a hard clip, so sunlit snow and sand keep their
    // detail.
    colour = colour / (1.0 + 0.08 * colour);

    return max(colour, 0.0);
}

// Strong specular-only path for water. The surface is flat geometry, so the
// highlight is the only thing that sells it as a liquid.
vec3 water_specular(vec3 normal, vec3 scene_pos, vec2 light_levels, float shadow) {
    if (!has_directional_light()) {
        return vec3(0.0);
    }

    vec3 light_colour = is_day() ? get_sun_color() : get_moon_color();
    float sky_visibility = smoothstep(0.0, 0.28, light_levels.y);

    return specular_highlight(
        normal,
        scene_pos,
        get_light_dir(),
        light_colour,
        shadow * sky_visibility,
        0.08,
        0.02,
        1.6
    );
}

#endif
