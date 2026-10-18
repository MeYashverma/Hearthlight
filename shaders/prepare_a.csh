#version 430 compatibility
// prepare A: reset counters and per-cell bin counts.
layout(local_size_x = 64) in;
const ivec3 workGroups = ivec3(64, 1, 1);

#include "/lib/settings.glsl"
#include "/lib/common.glsl"
#include "/lib/lightbuf.glsl"

void main() {
    uint i = gl_GlobalInvocationID.x;
    if (i < uint(CELLS_TOTAL)) LB.cellCount[i] = 0u;
    if (i == 0u) { LB.lightCount = 0u; LB.voxelCount = 0u; }
}
