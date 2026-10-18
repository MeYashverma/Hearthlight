#version 430 compatibility
// prepare B: scan the volume. Count occupied blocks (diagnostic) and append every emitter to the light list.
layout(local_size_x = 8, local_size_y = 8, local_size_z = 8) in;
const ivec3 workGroups = ivec3(16, 16, 16);

#include "/lib/settings.glsl"
#include "/lib/common.glsl"
#include "/lib/lightbuf.glsl"

layout(rgba8) readonly uniform image3D voxelLight;
layout(r32ui) readonly uniform uimage3D voxelMask;
shared uint groupCount;

void main() {
    ivec3 v = ivec3(gl_GlobalInvocationID.xyz);
    if (gl_LocalInvocationIndex == 0u) groupCount = 0u;
    barrier();
    if (imageLoad(voxelMask, v).r != 0u) atomicAdd(groupCount, 1u);
    barrier();
    if (gl_LocalInvocationIndex == 0u && groupCount > 0u) atomicAdd(LB.voxelCount, groupCount);

    vec4 d = imageLoad(voxelLight, v);
    uint b = uint(d.a * 255.0 + 0.5);
    float level = float(b >> 4);
    if (level < 1.5) return;

    uint idx = atomicAdd(LB.lightCount, 1u);
    if (idx >= uint(MAX_LIGHTS)) return;
    float yoff = float(b & 15u) / 32.0;
    LB.lights[idx].posLevel = vec4(vec3(v) + vec3(0.5, 0.5 + yoff, 0.5), level);
    LB.lights[idx].color = vec4(d.rgb, 1.0);
}
