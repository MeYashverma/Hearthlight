// Shared constants and helpers. Requires settings.glsl to be included first.
#ifndef HL_COMMON_GLSL
#define HL_COMMON_GLSL

#define saturate(x) clamp(x, 0.0, 1.0)

// Voxel volume: 128^3 blocks centred on the camera, split into 16^3 cells of 8^3 blocks.
const int VOXEL_RES = 128;
const int VOXEL_HALF = 64;
const int CELL_SIZE = 8;
const int CELLS_AXIS = 16;
const int CELLS_TOTAL = 4096;
const int MAX_LIGHTS = 2048;     // emitters tracked per frame
const int CELL_CAP = 32;         // lights remembered per cell
const float SHADOW_RES = 128.0;  // must match shadowMapResolution

// Light model tuning
const float LIGHT_I0 = 4.0;      // irradiance of a level-15 light at point-blank
const float ATT_K = 0.45;        // inverse-square-ish falloff strength
const vec3 WARM_BASE = vec3(1.00, 0.72, 0.42);

float lightRange(float level) { return min(level * LIGHT_RANGE, 24.0); }
int cellIndex(ivec3 c) { return c.x + CELLS_AXIS * (c.y + CELLS_AXIS * c.z); }

// Block id classes come from block.properties / item.properties.
vec3 lightColorFromId(int id) {
    if (id == 10100) return vec3(1.00, 0.62, 0.28); // torch / lantern / campfire fire
    if (id == 10101) return vec3(0.30, 0.72, 1.00); // soul fire
    if (id == 10102) return vec3(1.00, 0.42, 0.12); // lava / magma
    if (id == 10103) return vec3(1.00, 0.80, 0.50); // glowstone / lamps (warm white)
    if (id == 10104) return vec3(0.65, 0.92, 1.00); // sea lantern / beacon
    if (id == 10105) return vec3(0.92, 0.90, 1.00); // end rod
    if (id == 10106) return vec3(1.00, 0.16, 0.08); // redstone
    if (id == 10107) return vec3(1.00, 0.82, 0.40); // ochre froglight
    if (id == 10108) return vec3(0.50, 1.00, 0.55); // verdant froglight
    if (id == 10109) return vec3(0.95, 0.60, 1.00); // pearlescent froglight
    if (id == 10110) return vec3(1.00, 0.62, 0.30); // shroomlight
    if (id == 10111) return vec3(0.62, 0.22, 1.00); // portal / crying obsidian
    if (id == 10112) return vec3(0.35, 0.85, 0.80); // sculk / glow lichen
    if (id == 10113) return vec3(0.75, 0.50, 1.00); // amethyst
    return vec3(0.0);
}

// Specular material class (assigned in block.properties, ids 10200..10203).
float blockMaterialClass(int id) {
    if (id == 10200) return 1.0;                     // metal
    if (id == 10201) return 2.0;                     // polished stone / quartz / amethyst
    if (id == 10202) return 3.0;                     // ice / snow
    if (id == 10203) return 4.0;                     // glazed terracotta
    if (id >= 10100 && id < 10200) return 5.0;       // emitters read as glossy
    return 0.0;
}

// How much a full-cube voxel of this block id blocks light (0 = none, 1 = all).
float blockOpacity(int id) {
    if (id == 10001) return 0.55; // leaves: partial
    if (id == 10002) return 0.0;  // glass: transparent
    return 1.0;
}

#endif
