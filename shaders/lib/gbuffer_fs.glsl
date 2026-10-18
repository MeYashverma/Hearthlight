// Shared G-buffer fragment stage.
//  colortex0 = vanilla-lit colour (fallback; the deferred pass recomputes lighting for masked surfaces)
//  colortex1 = world normal (rgb) + sky light (a)
//  colortex2 = albedo (rgb) + mask (a): 1 = lit surface, 0.5 = emissive surface, 0 = not handled
//  colortex3 = vanilla sky/ambient light colour (rgb) + vanilla block light brightness (a)
// PASS_FORWARD programs (water, glass, hand) only write colortex0 and stay vanilla-lit.
#include "/lib/settings.glsl"
#include "/lib/common.glsl"

uniform sampler2D gtexture;
uniform sampler2D lightmap;
uniform float far;
uniform float fogStart;
uniform float fogEnd;
uniform vec3 fogColor;
#ifdef PASS_ENTITY
uniform vec4 entityColor;
#endif

in vec2 texcoord;
in vec2 lmcoord;
in vec4 glcolor;
in vec3 normalWS;
in vec3 normalVS;
in vec3 playerPos;
flat in float emissive;
flat in float isGui;

layout(location = 0) out vec4 outColor;
// The hand writes the G-buffer too: it is drawn *before* the deferred pass, so
// leaving these untouched let the deferred pass re-light the terrain behind the
// hand and paint over it. A zero mask tells deferred to keep colortex0 as-is.
#if !defined(PASS_FORWARD) || defined(PASS_HAND)
layout(location = 1) out vec4 outNormal;
layout(location = 2) out vec4 outAlbedo;
layout(location = 3) out vec4 outLight;
#define HL_GBUFFER_OUT
#endif

void main() {
    vec4 albedo = texture(gtexture, texcoord) * glcolor;
#ifdef PASS_ENTITY
    albedo.rgb = mix(albedo.rgb, entityColor.rgb, entityColor.a);
#endif
#ifdef PASS_FORWARD
    if (albedo.a < 0.004) discard;
#else
    if (albedo.a < 0.1) discard;
#endif

#ifdef HL_GBUFFER_OUT
    outNormal = vec4(0.0);
    outAlbedo = vec4(0.0);
    outLight = vec4(0.0);
#endif

    // ---- GUI / inventory: simple vanilla-style item lighting, no world lighting or fog ----
    if (isGui > 0.5) {
        vec3 nv = normalize(normalVS);
        float s = max(dot(nv, normalize(vec3(0.2, 1.0, -0.7))), 0.0) + max(dot(nv, normalize(vec3(-0.2, 1.0, 0.7))), 0.0);
        outColor = vec4(albedo.rgb * (0.58 + 0.42 * min(s, 1.0)), albedo.a);
        return;
    }

    const float lmMin = 1.0 / 32.0;
    vec3 lm = texture(lightmap, lmcoord).rgb;
    vec3 lit = albedo.rgb * lm;
    float fogF = hlFogFactor(playerPos, far, fogStart, fogEnd);
    outColor = vec4(mix(lit, fogColor, fogF), albedo.a);

#ifdef PASS_HAND
    // Mask stays 0 (written above): deferred returns colortex0 unchanged.
    return;
#endif

#ifdef HL_GBUFFER_OUT
    vec3 skyAmb = texture(lightmap, vec2(lmMin, lmcoord.y)).rgb;
    vec3 blk = max(texture(lightmap, vec2(lmcoord.x, lmMin)).rgb - texture(lightmap, vec2(lmMin, lmMin)).rgb, vec3(0.0));
    float skyL = clamp((lmcoord.y - lmMin) / (1.0 - 2.0 * lmMin), 0.0, 1.0);
    outNormal = vec4(normalize(normalWS) * 0.5 + 0.5, skyL);
    outAlbedo = vec4(albedo.rgb, emissive > 0.5 ? 0.5 : 1.0);
    outLight = vec4(skyAmb, dot(blk, vec3(0.3333)));
#endif
}
