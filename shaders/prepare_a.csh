#version 430 compatibility
// prepare A: reset the shadow-pass voxel counter (diagnostic + fallback switch).
layout(local_size_x = 1) in;
const ivec3 workGroups = ivec3(1, 1, 1);

#include "/lib/settings.glsl"
#include "/lib/common.glsl"
#include "/lib/lightbuf.glsl"

void main() { LB.shadowOcc = 0u; }
