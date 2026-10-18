#version 430 compatibility
// prepare B: count how many voxels the shadow pass wrote. If it is ~0 the terrain
// G-buffer pass switches on its fallback voxelizer for this frame.
layout(local_size_x = 8, local_size_y = 8, local_size_z = 8) in;
const ivec3 workGroups = ivec3(16, 16, 16);

#include "/lib/settings.glsl"
#include "/lib/common.glsl"
#include "/lib/lightbuf.glsl"

layout(r8) readonly uniform image3D voxelOcc;
shared uint groupCount;

void main() {
    if (gl_LocalInvocationIndex == 0u) groupCount = 0u;
    barrier();
    if (imageLoad(voxelOcc, ivec3(gl_GlobalInvocationID.xyz)).r > 0.0) atomicAdd(groupCount, 1u);
    barrier();
    if (gl_LocalInvocationIndex == 0u && groupCount > 0u) atomicAdd(LB.shadowOcc, groupCount);
}
