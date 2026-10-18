#version 430 compatibility
/* RENDERTARGETS: 0,4 */
/*
const int colortex0Format = RGBA16F;
const int colortex3Format = RGBA16F;
const int colortex4Format = RGBA16F;
const bool colortex4Clear = false;
const vec4 colortex2ClearColor = vec4(0.0, 0.0, 0.0, 0.0);
const vec4 colortex3ClearColor = vec4(0.0, 0.0, 0.0, 0.0);
*/
// Hearthlight deferred lighting.
//   ambient sky (vanilla light levels) + sun/moon (shadow map) + coloured vanilla-propagated fill
//   + ray-traced local lights (half-block voxel occlusion) , then fog / horizon haze.

#include "/lib/settings.glsl"
#include "/lib/common.glsl"
#include "/lib/lightbuf.glsl"
#include "/lib/ssshadow.glsl"

uniform sampler2D colortex0;
uniform sampler2D colortex1;
uniform sampler2D colortex2;
uniform sampler2D colortex3;
uniform sampler2D colortex4;
uniform sampler2D depthtex0;
uniform sampler2D shadowtex1;

uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferPreviousModelView;
uniform mat4 gbufferPreviousProjection;
uniform mat4 shadowModelView;
uniform mat4 shadowProjection;
uniform vec3 cameraPosition;
uniform vec3 previousCameraPosition;
uniform vec3 cameraPositionFract;
uniform vec3 sunPosition;
uniform vec3 shadowLightPosition;
uniform vec3 fogColor;
uniform float fogStart;
uniform float fogEnd;
uniform float far;
uniform float rainStrength;
uniform float viewWidth;
uniform float viewHeight;
uniform int moonPhase;
uniform int frameCounter;
uniform int heldItemId;
uniform int heldItemId2;
uniform int heldBlockLightValue;
uniform int heldBlockLightValue2;

layout(r32ui) readonly uniform uimage3D voxelMask;

in vec2 texcoord;
layout(location = 0) out vec4 outColor;
layout(location = 1) out vec4 outHist;

const int K = MAX_LIGHTS_PER_PIXEL;
float gScore[K];
int gIdx[K];

float ign(vec2 p) { return fract(52.9829189 * fract(dot(p, vec2(0.06711056, 0.00583715)))); }
float luma(vec3 c) { return dot(c, vec3(0.2126, 0.7152, 0.0722)); }
vec2 vogel(int i, int n, float rot) {
    float r = sqrt((float(i) + 0.5) / float(n));
    float a = float(i) * 2.39996323 + rot;
    return r * vec2(cos(a), sin(a));
}

// ---------------------------------------------------------------------------------------------
// Sun / moon shadow map lookup (PCF, normal-offset, distortion aware).
// ---------------------------------------------------------------------------------------------
float sunShadow(vec3 playerPos, vec3 N, float ndl, vec3 Lw, float noise) {
    float texelW = 2.0 * shadowDistance / float(shadowMapResolution);
    vec4 sp0 = shadowProjection * (shadowModelView * vec4(playerPos, 1.0));
    float localTexel = texelW * distortFactor(sp0.xy);
    vec3 pp = playerPos + N * (localTexel * (1.5 + 2.0 * (1.0 - ndl))) + Lw * (localTexel * 0.5);

    vec4 sp = shadowProjection * (shadowModelView * vec4(pp, 1.0));
    vec3 sc = vec3(distortShadow(sp.xy), sp.z) * 0.5 + 0.5;
    if (any(lessThan(sc.xy, vec2(0.0))) || any(greaterThan(sc.xy, vec2(1.0))) || sc.z > 1.0) return 1.0;

    float depthPerBlock = 0.5 * abs(shadowProjection[2][2]);
    float bias = localTexel * (1.0 + 2.0 * (1.0 - ndl)) * depthPerBlock;

#if SUN_SHADOW_QUALITY == 1
    const int taps = 4;
#elif SUN_SHADOW_QUALITY == 2
    const int taps = 8;
#else
    const int taps = 14;
#endif
    float rUV = 1.6 * SUN_SHADOW_SOFTNESS / float(shadowMapResolution);
    float rot = noise * 6.2831853;
    float vis = 0.0;
    for (int i = 0; i < taps; i++) {
        float d = texture(shadowtex1, sc.xy + vogel(i, taps, rot) * rUV).r;
        vis += (d >= sc.z - bias) ? 1.0 : 0.0;
    }
    vis /= float(taps);
    float edge = smoothstep(0.80, 0.98, max(abs(sc.x * 2.0 - 1.0), abs(sc.y * 2.0 - 1.0)));
    return mix(vis, 1.0, edge);
}

// ---------------------------------------------------------------------------------------------
// Local lights: ray walk through the half-block octant volume (Amanatides-Woo).
// Returns remaining transmittance. The start cell and the emitter's own block never occlude.
// ---------------------------------------------------------------------------------------------
float traceVis(vec3 o, vec3 t, ivec3 lightBlock) {
    vec3 o2 = o * 2.0;
    vec3 d = t * 2.0 - o2;
    float len = length(d);
    if (len < 1e-3) return 1.0;
    d /= len;

    ivec3 cell = ivec3(floor(o2));
    ivec3 stp = ivec3(sign(d));
    vec3 inv = 1.0 / (abs(d) + 1e-6);
    vec3 frac = mix(o2 - vec3(cell), vec3(cell) + 1.0 - o2, vec3(greaterThan(stp, ivec3(0))));
    vec3 tMax = frac * inv;
    vec3 tDelta = inv;

    ivec3 lastBlock = ivec3(-1000);
    uint mask = 0u;
    float trans = 1.0;
    for (int i = 0; i < SHADOW_RAY_STEPS; i++) {
        float tn = min(tMax.x, min(tMax.y, tMax.z));
        if (tn >= len) break;
        if (tMax.x <= tMax.y && tMax.x <= tMax.z) { cell.x += stp.x; tMax.x += tDelta.x; }
        else if (tMax.y <= tMax.z)                { cell.y += stp.y; tMax.y += tDelta.y; }
        else                                      { cell.z += stp.z; tMax.z += tDelta.z; }

        if (any(lessThan(cell, ivec3(0))) || any(greaterThanEqual(cell, ivec3(2 * VOXEL_RES)))) break;
        ivec3 blk = cell >> 1;
        if (blk == lightBlock) continue;
        if (blk != lastBlock) { mask = imageLoad(voxelMask, blk).r; lastBlock = blk; }
        if (mask == 0u) continue;
        uint bit = uint((cell.x & 1) | ((cell.y & 1) << 1) | ((cell.z & 1) << 2));
        if ((mask & (1u << bit)) != 0u) return 0.0;
        if ((mask & (256u << bit)) != 0u) { trans *= 0.5; if (trans < 0.1) return 0.0; }
    }
    return trans;
}

// Inverse-square-like pool with a smooth window to zero at the light's range.
float lightAtt(float d, float R) {
    float w = saturate(1.0 - d / R);
    return w * w / (1.0 + 0.25 * d * d);
}

float estimate(vec3 lp, float level, vec3 O, vec3 N) {
    vec3 toL = lp - O;
    float d = length(toL);
    float R = lightRange(level);
    if (d >= R) return 0.0;
    float ndl = saturate((dot(N, toL / max(d, 1e-3)) + 0.25) / 1.25);
    return (level / 15.0) * lightAtt(d, R) * ndl;
}

vec3 shadeLight(vec3 lp, float level, vec3 rawColor, vec3 O, vec3 N, vec3 rnd,
                vec3 viewPos, float useSS) {
    vec3 toL = lp - O;
    float d = length(toL);
    float R = lightRange(level);
    if (d >= R) return vec3(0.0);
    float ndl = saturate((dot(N, toL / max(d, 1e-3)) + 0.25) / 1.25);
    float e = LIGHT_I0 * (level / 15.0) * lightAtt(d, R) * ndl;
    if (e < 0.004) return vec3(0.0);

    ivec3 lb = ivec3(floor(lp));
    vec3 target = lp + (rnd * 2.0 - 1.0) * (SHADOW_SOFTNESS * 0.35);
    target = clamp(target, vec3(lb) + 0.05, vec3(lb) + 0.95);
    float vis = traceVis(O, target, lb);

#if LIGHT_SS_SHADOWS
    // The half-block volume cannot hold a player, a mob, a fence or a pane, so
    // the strongest lights also trace the depth buffer; where that ray has
    // enough of the view to answer, it replaces the voxel result.
    if (useSS > 0.5) {
        vec3 lightView = hl_worldToView(lp - cameraPositionFract - float(VOXEL_HALF), gbufferModelViewInverse);
        vec2 ss = hl_ssLocalShadow(viewPos, lightView, gbufferProjectionInverse);
        vis = (ss.x < 0.5) ? 0.0 : mix(vis, 1.0, ss.y);
    }
#endif

    vec3 col = mix(WARM_BASE, rawColor, COLOR_STRENGTH);
    return col * (e * vis);
}

void considerCandidate(float s, int idx) {
    if (s <= gScore[K - 1]) return;
    int j = K - 1;
    for (; j > 0; j--) {
        if (gScore[j - 1] >= s) break;
        gScore[j] = gScore[j - 1];
        gIdx[j] = gIdx[j - 1];
    }
    gScore[j] = s;
    gIdx[j] = idx;
}

void main() {
    vec4 base = texture(colortex0, texcoord);
    vec4 alb = texture(colortex2, texcoord);
    float depth = texture(depthtex0, texcoord).r;

    outColor = base;
    outHist = vec4(0.0, 0.0, 0.0, -1.0);

#if DEBUG_VIEW == 4
    // Status panel (top-left): all six squares should be GREEN while looking at terrain holding a torch.
    //  1 shadow pass wrote geometry  2 emitters found  3 lights near you
    //  4 G-buffer mask at screen centre  5 held light reported  6 ground under you voxelized
    {
        vec2 fp = gl_FragCoord.xy - vec2(8.0, viewHeight - 34.0);
        if (fp.y > 0.0 && fp.y < 26.0 && fp.x > 0.0) {
            int t = int(floor(fp.x / 30.0));
            if (t < 6 && fp.x - float(t) * 30.0 < 26.0) {
                bool ok = false;
                if (t == 0) ok = LB.voxelCount >= 64u;
                else if (t == 1) ok = LB.lightCount > 0u;
                else if (t == 2) ok = LB.cellCount[cellIndex(ivec3(CELLS_AXIS / 2))] > 0u;
                else if (t == 3) ok = texture(colortex2, vec2(0.5)).a > 0.003;
                else if (t == 4) ok = heldBlockLightValue >= 2;
                else { for (int y = 59; y < 64; y++) if (imageLoad(voxelMask, ivec3(VOXEL_HALF, y, VOXEL_HALF)).r != 0u) ok = true; }
                outColor = vec4(ok ? vec3(0.1, 0.85, 0.2) : vec3(0.9, 0.1, 0.1), 1.0);
                return;
            }
        }
    }
#endif

    vec4 ndc = vec4(texcoord * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
    vec4 vp = gbufferProjectionInverse * ndc;
    vec3 viewPos = vp.xyz / vp.w;
    vec3 playerPos = (gbufferModelViewInverse * vec4(viewPos, 1.0)).xyz;

    // ---- sky: blend the horizon into the same fog colour the terrain fades to (no hard band) ----
    if (depth >= 1.0) {
        // Something drew here without leaving depth (the hand can): keep it.
        if (alb.a > 0.003) return;
        float h = normalize(playerPos).y;
        float haze = exp(-max(h, 0.0) * 6.5);
        outColor = vec4(mix(base.rgb, fogColor, haze), base.a);
        return;
    }

#if DEBUG_VIEW == 5
    outColor = vec4(alb.a > 0.003 ? vec3(0.1, 0.8, 0.2) : vec3(0.85, 0.1, 0.85), 1.0);
    return;
#endif

    if (alb.a <= 0.003) return;

    vec4 nrm = texture(colortex1, texcoord);
    vec3 N = normalize(nrm.rgb * 2.0 - 1.0);
    float skyL = nrm.a;
    vec4 lgt = texture(colortex3, texcoord);
    vec3 skyAmb = lgt.rgb;
    float blockLum = lgt.a;
    vec3 albedo = alb.rgb;
    float fogF = hlFogFactor(playerPos, far, fogStart, fogEnd);

    // ---- emissive surfaces (torches, lava, glowstone ...) keep their bright, self-lit look ----
    if (alb.a < 0.75) {
        vec3 em = albedo * 1.15;
        outColor = vec4(mix(em, fogColor, fogF), base.a);
        return;
    }

    float noise = ign(gl_FragCoord.xy + 5.588 * float(frameCounter & 63));

    // ---- sun / moon ----------------------------------------------------------------------
    vec3 sunDirW = normalize(mat3(gbufferModelViewInverse) * sunPosition);
    float sunH = sunDirW.y;
    // shadowLightPosition is the sun (day) or moon (night) in *gbuffer* view space:
    // Iris' CelestialUniforms builds it with getGbufferModelView(), not the shadow
    // camera's matrix, so gbufferModelViewInverse is the matrix that undoes it.
    // (Using shadowModelViewInverse here rotates the light by the shadow camera and
    // paints large, wrongly-oriented shadows across the world.)
    bool haveShadowLight = dot(shadowLightPosition, shadowLightPosition) > 1e-4;
    vec3 Lw = normalize(mat3(gbufferModelViewInverse) * (haveShadowLight ? shadowLightPosition : sunPosition));
    float dayAmt = smoothstep(-0.10, 0.35, sunH);

    vec3 lightCol;
    float lightI;
    if (sunH > 0.0) {
        lightCol = mix(vec3(1.00, 0.50, 0.22), vec3(1.00, 0.96, 0.88), smoothstep(0.0, 0.70, sunH));
        lightI = 0.52 * SUN_STRENGTH * smoothstep(0.0, 0.22, sunH);
    } else {
        float fullness = 0.5 + 0.5 * cos(float(moonPhase) * 0.7853982);
        lightCol = vec3(0.50, 0.62, 1.00);
        lightI = 0.16 * MOON_STRENGTH * mix(0.45, 1.0, fullness) * smoothstep(0.0, 0.30, -sunH);
    }
    lightI *= 1.0 - 0.75 * rainStrength;

    float ndl = saturate((dot(N, Lw) + 0.12) / 1.12);   // slight wrap: low sun still grazes surfaces
    float skyGate = smoothstep(0.30, 0.85, skyL);
    float vis = 1.0;
    if (ndl > 0.0 && skyGate > 0.0 && lightI > 0.001) vis = sunShadow(playerPos, N, ndl, Lw, noise);
    vec3 direct = lightCol * (lightI * ndl * vis * skyGate);

    // Ambient sky light: cool at midday, warming toward dusk/dawn, vanilla night colour after dark.
    float dusk = (1.0 - smoothstep(0.02, 0.40, sunH)) * smoothstep(-0.12, 0.04, sunH);
    vec3 ambTint = mix(vec3(0.93, 0.98, 1.06), vec3(1.10, 0.82, 0.62), dusk);
    vec3 ambient = skyAmb * mix(1.0, AMBIENT_DAY, dayAmt) * mix(vec3(1.0), ambTint, dayAmt * 0.6 + dusk * 0.4)
                 * (1.0 - 0.12 * rainStrength);

    // ---- local lights -----------------------------------------------------------------------
    vec3 P = playerPos + cameraPositionFract + float(VOXEL_HALF);  // continuous voxel space
    vec3 O = P + N * 0.03;
    ivec3 vox = ivec3(floor(P));
    bool inVolume = all(greaterThanEqual(vox, ivec3(0))) && all(lessThan(vox, ivec3(VOXEL_RES)));

    for (int i = 0; i < K; i++) { gScore[i] = 0.0; gIdx[i] = -1; }
    vec3 tintAcc = vec3(0.0);
    float tintW = 0.0;
    if (inVolume) {
        int ci = cellIndex(vox / CELL_SIZE);
        int cnt = int(min(LB.cellCount[ci], uint(CELL_CAP)));
        for (int s = 0; s < cnt; s++) {
            int li = int(LB.cellLights[uint(ci) * uint(CELL_CAP) + uint(s)]);
            vec4 pl = LB.lights[li].posLevel;
            float e = estimate(pl.xyz, pl.w, O, N);
            tintAcc += LB.lights[li].color.rgb * e;
            tintW += e;
            considerCandidate(e, li);
        }
    }

    float f = float(frameCounter & 63);
    vec2 fc = gl_FragCoord.xy;
    vec3 irr = vec3(0.0);
    for (int i = 0; i < K; i++) {
        if (gIdx[i] < 0) break;
        vec4 pl = LB.lights[gIdx[i]].posLevel;
        vec3 rnd = vec3(ign(fc + 5.588 * f + 11.0 * float(i)),
                        ign(fc.yx + 17.0 + 3.1 * f + 7.0 * float(i)),
                        ign(fc + 41.0 + 8.7 * f + 5.0 * float(i)));
        irr += shadeLight(pl.xyz, pl.w, LB.lights[gIdx[i]].color.rgb, O, N, rnd,
                          viewPos, i < LIGHT_SS_COUNT ? 1.0 : 0.0);
    }

    // Lights carried in the hands.
    vec3 hp0 = (gbufferModelViewInverse * vec4(0.42, -0.34, -0.55, 1.0)).xyz + cameraPositionFract + float(VOXEL_HALF);
    vec3 hp1 = (gbufferModelViewInverse * vec4(-0.42, -0.34, -0.55, 1.0)).xyz + cameraPositionFract + float(VOXEL_HALF);
    vec3 rndH = vec3(ign(fc + 5.588 * f + 91.0), ign(fc.yx + 3.1 * f + 63.0), ign(fc + 8.7 * f + 29.0));
    if (heldBlockLightValue >= 2) {
        vec3 hc = lightColorFromId(heldItemId);
        if (dot(hc, hc) < 1e-4) hc = WARM_BASE;
        irr += shadeLight(hp0, float(heldBlockLightValue), hc, O, N, rndH, viewPos, 0.0);
        tintAcc += hc * 0.5; tintW += 0.5;
    }
    if (heldBlockLightValue2 >= 2) {
        vec3 hc = lightColorFromId(heldItemId2);
        if (dot(hc, hc) < 1e-4) hc = WARM_BASE;
        irr += shadeLight(hp1, float(heldBlockLightValue2), hc, O, N, rndH.zxy, viewPos, 0.0);
        tintAcc += hc * 0.5; tintW += 0.5;
    }

    // Local lights stay meaningful at night but yield to bright open-sky daylight.
    irr *= LIGHT_INTENSITY * (1.0 - DAY_SUPPRESS * skyL * dayAmt);

    // ---- temporal accumulation of the local-light term ---------------------------------------
    vec3 prevView = (gbufferPreviousModelView * vec4(playerPos + cameraPosition - previousCameraPosition, 1.0)).xyz;
    vec4 pc = gbufferPreviousProjection * vec4(prevView, 1.0);
    vec2 prevUV = pc.xy / pc.w * 0.5 + 0.5;
    float linDepth = -viewPos.z;
    vec3 acc = irr;
    if (SHADOW_SOFTNESS > 0.0 && pc.w > 0.0 && all(greaterThan(prevUV, vec2(0.0))) && all(lessThan(prevUV, vec2(1.0)))) {
        vec4 h = texelFetch(colortex4, ivec2(prevUV * vec2(viewWidth, viewHeight)), 0);
        float expected = -prevView.z;
        if (h.a > 0.0 && abs(h.a - expected) < 0.08 * expected + 0.1) {
            float blend = mix(0.40, 0.12, SHADOW_SOFTNESS);
            float lh = luma(h.rgb), lc = luma(irr);
            float ghost = saturate(abs(lh - lc) / (max(lh, lc) + 0.15) - 0.6);
            blend = max(blend, ghost * 0.6);
            acc = mix(h.rgb, irr, blend);
        }
    }
    outHist = vec4(acc, linDepth);
    vec3 localLight = acc / (1.0 + acc * 0.45);

    // ---- coloured fill: vanilla's own light propagation (around corners, through doors) tinted by nearby emitters ----
    vec3 tint = WARM_BASE;
    if (tintW > 1e-3) tint = mix(WARM_BASE, tintAcc / tintW, COLOR_STRENGTH * saturate(tintW * 6.0));
    vec3 fill = tint * (blockLum * VANILLA_FILL);

    vec3 lit = albedo * (ambient + direct + fill + localLight);

#if DEBUG_VIEW == 1
    float heat = inVolume ? float(min(LB.cellCount[cellIndex(vox / CELL_SIZE)], uint(CELL_CAP))) / float(CELL_CAP) : 0.0;
    lit = mix(vec3(0.0, 0.0, 0.3), vec3(1.0, 0.9, 0.1), sqrt(heat));
#elif DEBUG_VIEW == 2
    lit = ambient + direct + fill + localLight;
#elif DEBUG_VIEW == 3
    ivec3 behind = ivec3(floor(P - N * 0.1));
    bool ok = all(greaterThanEqual(behind, ivec3(0))) && all(lessThan(behind, ivec3(VOXEL_RES)));
    bool occ = ok && imageLoad(voxelMask, behind).r != 0u;
    lit = mix(vec3(0.8, 0.1, 0.1), vec3(0.1, 0.8, 0.2), occ ? 1.0 : 0.0) * (0.35 + 0.65 * luma(base.rgb));
#elif DEBUG_VIEW == 6
    lit = vec3(vis) * (0.15 + 0.85 * ndl);
#endif

    lit = mix(lit, fogColor, fogF);
    outColor = vec4(lit, base.a);
}
