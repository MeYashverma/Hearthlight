// Light list + per-cell light bins (SSBO 0). Layout MUST be identical in every shader that includes it.
// Size: 606224 bytes (allocated 1,000,000).
#ifndef HL_LIGHTBUF_GLSL
#define HL_LIGHTBUF_GLSL

struct HLight {
    vec4 posLevel; // xyz = voxel-space position, w = emission level (1..15)
    vec4 color;    // rgb = class colour
};

layout(std430, binding = 0) buffer LightData {
    uint lightCount;
    uint voxelCount;  // blocks with occupancy written by the shadow pass this frame (diagnostic)
    uint _pad1;
    uint _pad2;
    HLight lights[MAX_LIGHTS];
    uint cellCount[CELLS_TOTAL];
    uint cellLights[CELLS_TOTAL * CELL_CAP];
} LB;

#endif
