#version 430 compatibility
// deferred B: scan the voxel volume and append every emitter to the light list.
layout(local_size_x = 8, local_size_y = 8, local_size_z = 8) in;
const ivec3 workGroups = ivec3(16, 16, 16);

#include "/lib/settings.glsl"
#include "/lib/common.glsl"
#include "/lib/lightbuf.glsl"

layout(rgba8) readonly uniform image3D voxelLight;

void main() {
    ivec3 v = ivec3(gl_GlobalInvocationID.xyz);
    vec4 d = imageLoad(voxelLight, v);
    float level = floor(d.a * 15.0 + 0.5);
    if (level < 1.5) return;

    uint idx = atomicAdd(LB.lightCount, 1u);
    if (idx >= uint(MAX_LIGHTS)) return;
    LB.lights[idx].posLevel = vec4(vec3(v) + 0.5, level);
    LB.lights[idx].color = vec4(d.rgb, 1.0);
}
