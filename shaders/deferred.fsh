#version 430 compatibility
/* RENDERTARGETS: 0,4 */
// Hearthlight deferred lighting: picks the strongest nearby lights for each pixel,
// ray-traces them through the voxel volume, accumulates over time, and adds the
// result on top of the vanilla-lit colour.

#include "/lib/settings.glsl"
#include "/lib/common.glsl"
#include "/lib/lightbuf.glsl"
#include "/lib/sun.glsl"
#include "/lib/ssshadow.glsl"

/*
const int colortex0Format = RGBA16F;
const int colortex4Format = RGBA16F;
const bool colortex4Clear = false;
const vec4 colortex2ClearColor = vec4(0.0, 0.0, 0.0, 0.0);
*/

uniform sampler2D colortex0;
uniform sampler2D colortex1;
uniform sampler2D colortex2;
uniform sampler2D colortex3;
uniform sampler2D colortex4;
uniform sampler2D depthtex0;

uniform mat4 gbufferPreviousModelView;
uniform mat4 gbufferPreviousProjection;
uniform vec3 cameraPosition;
uniform vec3 previousCameraPosition;
uniform vec3 cameraPositionFract;
uniform float viewWidth;
uniform float viewHeight;
uniform int frameCounter;
uniform int heldItemId;
uniform int heldItemId2;
uniform int heldBlockLightValue;
uniform int heldBlockLightValue2;

in vec2 texcoord;
layout(location = 0) out vec4 outColor;
layout(location = 1) out vec4 outHist;

const int K = MAX_LIGHTS_PER_PIXEL;
float gScore[K];
int gIdx[K];

float ign(vec2 p) { return fract(52.9829189 * fract(dot(p, vec2(0.06711056, 0.00583715)))); }
float luma(vec3 c) { return dot(c, vec3(0.2126, 0.7152, 0.0722)); }

// Amanatides-Woo voxel walk from o to t. Returns remaining transmittance (0 = fully shadowed).
// The start cell and the emitter's own cell never occlude.
float traceVis(vec3 o, vec3 t, ivec3 lightCell) {
    vec3 d = t - o;
    float len = length(d);
    if (len < 1e-3) return 1.0;
    d /= len;

    ivec3 cell = ivec3(floor(o));
    ivec3 stp = ivec3(sign(d));
    vec3 inv = 1.0 / (abs(d) + 1e-6);
    vec3 frac = mix(o - vec3(cell), vec3(cell) + 1.0 - o, vec3(greaterThan(stp, ivec3(0))));
    vec3 tMax = frac * inv;
    vec3 tDelta = inv;

    float trans = 1.0;
    for (int i = 0; i < SHADOW_RAY_STEPS; i++) {
        float tn = min(tMax.x, min(tMax.y, tMax.z));
        if (tn >= len) break;
        if (tMax.x <= tMax.y && tMax.x <= tMax.z) { cell.x += stp.x; tMax.x += tDelta.x; }
        else if (tMax.y <= tMax.z)                { cell.y += stp.y; tMax.y += tDelta.y; }
        else                                      { cell.z += stp.z; tMax.z += tDelta.z; }

        if (any(lessThan(cell, ivec3(0))) || any(greaterThanEqual(cell, ivec3(VOXEL_RES)))) break;
        if (cell == lightCell) continue;

        trans *= 1.0 - imageLoad(voxelOcc, cell).r;
        if (trans < 0.03) return 0.0;
    }
    return trans;
}

float lightAtt(float d2, float R) {
    float x = d2 / (R * R);
    float w = saturate(1.0 - x * x);
    return w * w / (1.0 + ATT_K * d2);
}

// Unshadowed estimate used to rank candidates cheaply.
float estimate(vec3 lightPos, float level, vec3 O, vec3 N) {
    vec3 toL = lightPos - O;
    float d2 = dot(toL, toL);
    float R = lightRange(level);
    if (d2 >= R * R) return 0.0;
    float ndl = saturate(dot(N, toL * inversesqrt(d2 + 1e-6)) * 0.85 + 0.15);
    return (level / 15.0) * lightAtt(d2, R) * ndl;
}

vec3 shadeLight(vec3 lightPos, float level, vec3 rawColor, vec3 O, vec3 N, vec3 rnd) {
    vec3 toL = lightPos - O;
    float d2 = dot(toL, toL);
    float R = lightRange(level);
    if (d2 >= R * R) return vec3(0.0);
    float d = sqrt(d2);
    float ndl = saturate(dot(N, toL / d) * 0.85 + 0.15);
    float e = LIGHT_I0 * (level / 15.0) * lightAtt(d2, R) * ndl;
    if (e < 0.004) return vec3(0.0);

    vec3 target = lightPos + (rnd * 2.0 - 1.0) * (SHADOW_SOFTNESS * 0.45);
    float vis = traceVis(O, target, ivec3(floor(lightPos)));
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
    // Status panel (top-left). Every tile should be GREEN while looking at terrain and holding a torch.
    //  1 shadow-pass voxelizer wrote geometry   2 emitters found      3 lights binned near you
    //  4 G-buffer mask present at screen centre 5 held light reported 6 ground under you is voxelized
    {
        vec2 fp = gl_FragCoord.xy - vec2(8.0, viewHeight - 34.0);
        if (fp.y > 0.0 && fp.y < 26.0 && fp.x > 0.0) {
            int t = int(floor(fp.x / 30.0));
            if (t < 6 && fp.x - float(t) * 30.0 < 26.0) {
                bool ok = false;
                if (t == 0) ok = LB.shadowOcc >= 64u;
                else if (t == 1) ok = LB.lightCount > 0u;
                else if (t == 2) ok = LB.cellCount[cellIndex(ivec3(CELLS_AXIS / 2))] > 0u;
                else if (t == 3) ok = texture(colortex2, vec2(0.5)).a > 0.003;
                else if (t == 4) ok = heldBlockLightValue >= 2;
                else { for (int y = 59; y < 64; y++) if (imageLoad(voxelOcc, ivec3(VOXEL_HALF, y, VOXEL_HALF)).r > 0.0) ok = true; }
                outColor = vec4(ok ? vec3(0.1, 0.85, 0.2) : vec3(0.9, 0.1, 0.1), 1.0);
                return;
            }
        }
    }
#endif
#if DEBUG_VIEW == 5
    // G-buffer check: green = terrain/entities wrote the lighting mask, magenta = not (fallback programs).
    if (depth < 1.0) {
        outColor = vec4(alb.a > 0.003 ? vec3(0.1, 0.8, 0.2) : vec3(0.85, 0.1, 0.85), 1.0);
        return;
    }
#endif

    if (depth >= 1.0 || alb.a <= 0.003) return;

    vec4 nrm = texture(colortex1, texcoord);
    vec3 N = normalize(nrm.rgb * 2.0 - 1.0);
    float skyL = nrm.a;

    vec4 ndc = vec4(texcoord * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
    vec4 vp = gbufferProjectionInverse * ndc;
    vec3 viewPos = vp.xyz / vp.w;
    vec3 playerPos = (gbufferModelViewInverse * vec4(viewPos, 1.0)).xyz;

    vec3 P = playerPos + cameraPositionFract + float(VOXEL_HALF);  // continuous voxel space
    vec3 O = P + N * 0.04;
    ivec3 vox = ivec3(floor(P));
    bool inVolume = all(greaterThanEqual(vox, ivec3(0))) && all(lessThan(vox, ivec3(VOXEL_RES)));

    // --- sun / moon --------------------------------------------------------
    // Direction and brightness come from hl_direct(), which rebuilds them in
    // player space; the shadow is a voxel walk toward the light.
    vec3 sunDir, sunCol;
    float sunUp, sunDay;
    hl_direct(sunDir, sunCol, sunUp, sunDay);
    float NoL = saturate(dot(N, sunDir));
    float vis = 1.0;
#if SUN_SHADOWS
    if (sunUp > 0.001 && NoL > 0.001) {
        if (inVolume) vis = hl_sunVis(P, N);
#if SS_SHADOWS
        // The depth buffer knows the real shape of doors, fences, players and
        // dropped items; where it can answer, it overrides the 1-block voxel.
        vec2 ss = hl_ssSunShadow(viewPos, hl_worldToView(sunDir));
        if (ss.x < 0.5) vis = 0.0;
        else vis = mix(vis, 1.0, ss.y);
#endif
    }
#endif
    // How much direct sunlight this pixel is missing. Gated by sky light so
    // caves and interiors (already dark in vanilla) are left alone.
    float shadowAmt = SUN_SHADOW_STRENGTH * sunUp * NoL * (1.0 - vis)
                    * smoothstep(0.02, 0.25, skyL);

    // --- gather candidates -------------------------------------------------
    for (int i = 0; i < K; i++) { gScore[i] = 0.0; gIdx[i] = -1; }
    if (inVolume) {
        int ci = cellIndex(vox / CELL_SIZE);
        int cnt = int(min(LB.cellCount[ci], uint(CELL_CAP)));
        for (int s = 0; s < cnt; s++) {
            int li = int(LB.cellLights[uint(ci) * uint(CELL_CAP) + uint(s)]);
            vec4 pl = LB.lights[li].posLevel;
            considerCandidate(estimate(pl.xyz, pl.w, O, N), li);
        }
    }

    // --- shade --------------------------------------------------------------
    float f = float(frameCounter & 63);
    vec2 fc = gl_FragCoord.xy;
    vec3 irr = vec3(0.0);
    for (int i = 0; i < K; i++) {
        if (gIdx[i] < 0) break;
        vec4 pl = LB.lights[gIdx[i]].posLevel;
        vec3 rnd = vec3(ign(fc + 5.588 * f + 11.0 * float(i)),
                        ign(fc.yx + 17.0 + 3.1 * f + 7.0 * float(i)),
                        ign(fc + 41.0 + 8.7 * f + 5.0 * float(i)));
        irr += shadeLight(pl.xyz, pl.w, LB.lights[gIdx[i]].color.rgb, O, N, rnd);
    }

    // Lights carried in the player's hands (voxel space = view offset rotated to player space).
    vec3 hp0 = (gbufferModelViewInverse * vec4(0.42, -0.34, -0.55, 1.0)).xyz + cameraPositionFract + float(VOXEL_HALF);
    vec3 hp1 = (gbufferModelViewInverse * vec4(-0.42, -0.34, -0.55, 1.0)).xyz + cameraPositionFract + float(VOXEL_HALF);
    vec3 rndH = vec3(ign(fc + 5.588 * f + 91.0), ign(fc.yx + 3.1 * f + 63.0), ign(fc + 8.7 * f + 29.0));
    if (heldBlockLightValue >= 2) {
        vec3 hc = lightColorFromId(heldItemId);
        if (dot(hc, hc) < 1e-4) hc = WARM_BASE;
        irr += shadeLight(hp0, float(heldBlockLightValue), hc, O, N, rndH);
    }
    if (heldBlockLightValue2 >= 2) {
        vec3 hc = lightColorFromId(heldItemId2);
        if (dot(hc, hc) < 1e-4) hc = WARM_BASE;
        irr += shadeLight(hp1, float(heldBlockLightValue2), hc, O, N, rndH.zxy);
    }

    // Daylight makes local lights less dominant; darkness does not.
    irr *= LIGHT_INTENSITY * (1.0 - DAY_SUPPRESS * skyL * sunDay);

    // --- temporal accumulation ---------------------------------------------
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

    vec3 shoulder = acc / (1.0 + acc * 0.55);

    // Direct sun is already baked into the vanilla lightmap, so a shadow has to
    // take it back out; then the specular lobe of the same light is added.
    float cls = floor(texture(colortex3, texcoord).r * 255.0 + 0.5);
    // What a shadow leaves behind is skylight, so it is a touch cooler than the
    // sunlit part; the removal itself stays neutral to keep the tint honest.
    vec3 lit = base.rgb * (1.0 - shadowAmt) * mix(vec3(1.0), vec3(0.94, 0.97, 1.04), shadowAmt)
             + alb.rgb * shoulder;
    lit += hl_specular(N, playerPos, vis, cls);

#if DEBUG_VIEW == 1
    // Heat map: number of lights binned to this pixel's cell.
    float heat = inVolume ? float(min(LB.cellCount[cellIndex(vox / CELL_SIZE)], uint(CELL_CAP))) / float(CELL_CAP) : 0.0;
    lit = mix(vec3(0.0, 0.0, 0.3), vec3(1.0, 0.9, 0.1), sqrt(heat));
#elif DEBUG_VIEW == 2
    lit = shoulder + 0.02;     // lighting only (no albedo)
#elif DEBUG_VIEW == 3
    // Voxelisation check: the voxel just *behind* each surface should be occupied (green).
    ivec3 behind = ivec3(floor(P - N * 0.1));
    bool ok = all(greaterThanEqual(behind, ivec3(0))) && all(lessThan(behind, ivec3(VOXEL_RES)));
    float occ = ok ? imageLoad(voxelOcc, behind).r : 0.0;
    lit = mix(vec3(0.8, 0.1, 0.1), vec3(0.1, 0.8, 0.2), step(0.5, occ)) * (0.35 + 0.65 * luma(base.rgb));
#endif

    outColor = vec4(lit, base.a);
}
