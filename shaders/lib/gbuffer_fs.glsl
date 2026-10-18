// Shared G-buffer fragment stage.
//  colortex0 = vanilla-lit colour (block light partly removed near the camera, fogged)
//  colortex1 = world normal (rgb) + sky light (a)            [deferred passes only]
//  colortex2 = albedo (rgb) + local-light mask (a)           [deferred passes only]
// Define PASS_ENTITY for entity tint, PASS_FORWARD for passes that skip deferred lighting.
#include "/lib/settings.glsl"
#include "/lib/common.glsl"
#ifdef PASS_VOXEL
#include "/lib/lightbuf.glsl"
#include "/lib/voxelwrite.glsl"
#elif defined(PASS_VOXEL_EMIT)
#include "/lib/voxelwrite.glsl"
#else
uniform sampler2D gtexture;
#endif
uniform sampler2D lightmap;
uniform float fogStart;
uniform float fogEnd;
uniform int fogMode;
uniform int fogShape;
uniform vec3 fogColor;
#ifdef PASS_ENTITY
uniform vec4 entityColor;
#endif

in vec2 texcoord;
in vec2 lmcoord;
in vec4 glcolor;
in vec3 normalWS;
in vec3 playerPos;
flat in float emissive;
#if defined(PASS_VOXEL) || defined(PASS_VOXEL_EMIT)
flat in ivec3 vCell;
flat in int vId;
flat in float vLevel;
in float vCorner;
#endif

layout(location = 0) out vec4 outColor;
#ifndef PASS_FORWARD
layout(location = 1) out vec4 outNormal;
layout(location = 2) out vec4 outAlbedo;
layout(location = 3) out vec4 outMaterial;   // r = specular class / 255
#endif

void main() {
    vec4 tex = texture(gtexture, texcoord);
    vec4 albedo = tex * glcolor;
#ifdef PASS_ENTITY
    albedo.rgb = mix(albedo.rgb, entityColor.rgb, entityColor.a);
#endif
    if (albedo.a < 0.1) discard;

#ifdef PASS_VOXEL
    // Fallback voxelizer: only active when the shadow-pass voxelizer wrote (almost) nothing this frame.
    if (LB.shadowOcc < 64u
        && all(greaterThanEqual(vCell, ivec3(0))) && all(lessThan(vCell, ivec3(VOXEL_RES)))) {
        hlWriteVoxel(vCell, vId, vLevel, vCorner, texcoord);
    }
#endif
#ifdef PASS_VOXEL_EMIT
    // Translucent pass: emitters only, never occupancy. Lava, nether portals and
    // other see-through light sources live here and the shadow pass skips them.
    hlWriteEmission(vCell, vId, vLevel, texcoord);
#endif

    // Vanilla lightmap, with the block-light part reduced where Hearthlight supplies its own.
    const float lmMin = 1.0 / 32.0;
    vec3 lm = texture(lightmap, lmcoord).rgb;
    vec3 blockOnly = max(texture(lightmap, vec2(lmcoord.x, lmMin)).rgb
                       - texture(lightmap, vec2(lmMin, lmMin)).rgb, vec3(0.0));

#if defined(PASS_FORWARD) || defined(PASS_HAND)
    float reduce = 0.0;   // forward-lit surfaces keep full vanilla light
#else
    float edge = 1.0 - smoothstep(float(VOXEL_HALF) * 0.70, float(VOXEL_HALF) * 0.94, length(playerPos));
    float reduce = (1.0 - VANILLA_FILL) * edge * (1.0 - emissive);
#endif
    vec3 light = max(lm - blockOnly * reduce, vec3(0.0));
    vec3 lit = albedo.rgb * light;

    // Vanilla-style linear fog (cylinder or sphere).
    float fogF = 0.0;
    if (fogMode != 0 && fogEnd > fogStart) {
        float dist = (fogShape == 1) ? max(length(playerPos.xz), abs(playerPos.y)) : length(playerPos);
        fogF = clamp((dist - fogStart) / (fogEnd - fogStart), 0.0, 1.0);
    }
    lit = mix(lit, fogColor, fogF);

    outColor = vec4(lit, albedo.a);

#ifndef PASS_FORWARD
    float skyL = clamp((lmcoord.y - lmMin) / (1.0 - 2.0 * lmMin), 0.0, 1.0);
    vec3 n = normalize(normalWS);
    float mask = 1.0;   // geometry present (fog is applied to colour only; the mask never depends on fog uniforms)
#ifdef PASS_HAND
    mask = 0.0;
#endif
    outNormal = vec4(n * 0.5 + 0.5, skyL);
    outAlbedo = vec4(albedo.rgb, mask);

    // Specular material class. Only the terrain pass knows block ids; entities
    // and block entities fall back to class 0 (a faint, uniform sheen).
    float cls = 0.0;
#ifdef PASS_VOXEL
    cls = blockMaterialClass(vId);
#endif
    outMaterial = vec4(cls / 255.0, 0.0, 0.0, 1.0);
#endif
}
