#version 430 compatibility
// prepare C: bin each light into every 8^3-block cell its range touches.
layout(local_size_x = 64) in;
const ivec3 workGroups = ivec3(32, 1, 1);

#include "/lib/settings.glsl"
#include "/lib/common.glsl"
#include "/lib/lightbuf.glsl"

void main() {
    uint i = gl_GlobalInvocationID.x;
    uint n = min(LB.lightCount, uint(MAX_LIGHTS));
    if (i >= n) return;

    vec4 pl = LB.lights[i].posLevel;
    float R = lightRange(pl.w);
    ivec3 c0 = clamp(ivec3(floor((pl.xyz - R) / float(CELL_SIZE))), ivec3(0), ivec3(CELLS_AXIS - 1));
    ivec3 c1 = clamp(ivec3(floor((pl.xyz + R) / float(CELL_SIZE))), ivec3(0), ivec3(CELLS_AXIS - 1));

    for (int z = c0.z; z <= c1.z; z++)
    for (int y = c0.y; y <= c1.y; y++)
    for (int x = c0.x; x <= c1.x; x++) {
        ivec3 c = ivec3(x, y, z);
        vec3 lo = vec3(c * CELL_SIZE);
        vec3 q = clamp(pl.xyz, lo, lo + float(CELL_SIZE));
        vec3 dd = pl.xyz - q;
        if (dot(dd, dd) > R * R) continue;
        int ci = cellIndex(c);
        uint slot = atomicAdd(LB.cellCount[ci], 1u);
        if (slot < uint(CELL_CAP)) LB.cellLights[uint(ci) * uint(CELL_CAP) + slot] = i;
    }
}
