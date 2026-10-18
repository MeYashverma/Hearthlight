#version 430 compatibility
/* DRAWBUFFERS:0 */

#include "/lib/settings.glsl"
#include "/lib/common.glsl"
#include "/lib/voxelwrite.glsl"

const int shadowMapResolution = 128;
const float shadowDistance = 64.0;
const float shadowDistanceRenderMul = 1.0;

in vec2 texcoord;
flat in ivec3 vCell;
flat in int vId;
flat in float vLevel;
in float vCorner;

layout(location = 0) out vec4 outColor;

void main() {
    outColor = vec4(0.0, 0.0, 0.0, 1.0);   // alpha 1: never culled by Iris' injected alpha test
    hlWriteVoxel(vCell, vId, vLevel, vCorner, texcoord);
}
