#version 430 compatibility
// Shadow pass geometry stage. Re-emits every triangle for the shadow map and, for terrain,
// records into the voxel volume:
//   voxelMask  (r32ui)  per block: bits 0-7 opaque half-block octants, bits 8-15 foliage octants
//   voxelLight (rgba8)  per block: emitter colour + (level<<4 | flame height)
// Only axis-aligned faces that fill >= 90% of an octant count as occluders, so slabs, stairs,
// doors and full blocks are exact while carpets, torches, plants and fences do not self-shadow.

#include "/lib/settings.glsl"
#include "/lib/common.glsl"

layout(triangles) in;
layout(triangle_strip, max_vertices = 3) out;

in vec2 texCoordV[3];
in vec4 colorV[3];
in vec3 posV[3];
in vec3 normalV[3];
in vec3 midV[3];
flat in int idV[3];
flat in float levelV[3];

out vec2 texCoord;
out vec4 color;

uniform vec3 cameraPositionFract;
uniform sampler2D gtexture;
layout(r32ui) uniform uimage3D voxelMask;
layout(rgba8) uniform image3D voxelLight;

void voxelize() {
    vec3 mid0 = midV[0];
    if (dot(mid0, mid0) < 1e-6) return;                       // entities / no block data

    ivec3 cell = ivec3(floor(posV[0] + mid0 + cameraPositionFract)) + VOXEL_HALF;
    if (any(lessThan(cell, ivec3(0))) || any(greaterThanEqual(cell, ivec3(VOXEL_RES)))) return;
    int id = idV[0];

    // ---- emission (level comes from Minecraft itself) ----
    float level = levelV[0];
    if (level > 1.5) {
        vec3 col = lightColorFromId(id);
        if (dot(col, col) < 1e-4) {
            vec2 uv = (texCoordV[0] + texCoordV[1] + texCoordV[2]) / 3.0;
            vec3 t = textureLod(gtexture, uv, 0.0).rgb;
            float m = max(max(t.r, t.g), max(t.b, 1e-3));
            col = mix(vec3(1.0, 0.78, 0.52), t / m, 0.6);
        }
        imageStore(voxelLight, cell, vec4(col, packLightAlpha(level, lightHeightOffset(id))));
    }

    // ---- occupancy ----
    if (isTransparentId(id)) return;
    vec3 n = normalV[0];
    vec3 an = abs(n);
    int a = an.x > an.y ? (an.x > an.z ? 0 : 2) : (an.y > an.z ? 1 : 2);
    if (an[a] < 0.97) return;                                   // plants, rotated models: not occluders

    vec3 l0 = vec3(0.5) - midV[0];                              // position inside the block, 0..1
    vec3 l1 = vec3(0.5) - midV[1];
    vec3 l2 = vec3(0.5) - midV[2];
    float p = (l0[a] + l1[a] + l2[a]) / 3.0;
    bool outward = n[a] > 0.0;                                  // solid lies behind the face
    int oa = int(clamp(floor((outward ? p - 0.001 : p + 0.001) * 2.0), 0.0, 1.0));
    float fill = outward ? (p - 0.5 * float(oa)) : (0.5 * float(oa + 1) - p);
    if (fill < 0.45) return;                                    // face is not (nearly) flush with the octant

    int b1 = (a + 1) % 3;
    int b2 = (a + 2) % 3;
    float u0 = min(l0[b1], min(l1[b1], l2[b1]));
    float u1 = max(l0[b1], max(l1[b1], l2[b1]));
    float v0 = min(l0[b2], min(l1[b2], l2[b2]));
    float v1 = max(l0[b2], max(l1[b2], l2[b2]));

    uint bits = 0u;
    for (int ou = 0; ou < 2; ou++) {
        if (min(u1, 0.5 * float(ou + 1)) - max(u0, 0.5 * float(ou)) < 0.45) continue;
        for (int ov = 0; ov < 2; ov++) {
            if (min(v1, 0.5 * float(ov + 1)) - max(v0, 0.5 * float(ov)) < 0.45) continue;
            ivec3 o = ivec3(0);
            o[a] = oa; o[b1] = ou; o[b2] = ov;
            bits |= 1u << uint(o.x + 2 * o.y + 4 * o.z);
        }
    }
    if (bits == 0u) return;
    if (id == 10001) bits <<= 8;                                // leaves: partial occluder
    imageAtomicOr(voxelMask, cell, bits);
}

void main() {
    voxelize();
    for (int i = 0; i < 3; i++) {
        gl_Position = gl_in[i].gl_Position;
        texCoord = texCoordV[i];
        color = colorV[i];
        EmitVertex();
    }
    EndPrimitive();
}
