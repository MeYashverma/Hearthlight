// Shared constants and helpers. Requires settings.glsl to be included first.
#ifndef HL_COMMON_GLSL
#define HL_COMMON_GLSL

#define saturate(x) clamp(x, 0.0, 1.0)

// Voxel volume: 128^3 blocks centred on the camera, 16^3 light cells of 8^3 blocks.
// Occupancy is stored per block as an 8-bit octant mask (2x2x2 half-blocks): slabs and stairs are exact.
const int VOXEL_RES = 128;
const int VOXEL_HALF = 64;
const int CELL_SIZE = 8;
const int CELLS_AXIS = 16;
const int CELLS_TOTAL = 4096;
const int MAX_LIGHTS = 2048;
const int CELL_CAP = 32;

// Light model tuning
const float LIGHT_I0 = 6.0;
const vec3 WARM_BASE = vec3(1.00, 0.72, 0.42);

float lightRange(float level) { return min(level * LIGHT_RANGE, 24.0); }
int cellIndex(ivec3 c) { return c.x + CELLS_AXIS * (c.y + CELLS_AXIS * c.z); }

// ---- shadow map distortion (more resolution near the player) ----
const float SHADOW_DISTORT = 0.85;
float distortFactor(vec2 xy) { return (1.0 - SHADOW_DISTORT) + length(xy) * SHADOW_DISTORT; }
vec2 distortShadow(vec2 xy) { return xy / distortFactor(xy); }

// ---- block id classes (block.properties / item.properties) ----
vec3 lightColorFromId(int id) {
    if (id == 10100) return vec3(1.00, 0.62, 0.28); // torch / lantern / campfire / fire
    if (id == 10101) return vec3(0.30, 0.72, 1.00); // soul fire
    if (id == 10102) return vec3(1.00, 0.42, 0.12); // magma
    if (id == 10114) return vec3(1.00, 0.42, 0.12); // lava (fluid)
    if (id == 10103) return vec3(1.00, 0.80, 0.50); // glowstone / lamps
    if (id == 10104) return vec3(0.65, 0.92, 1.00); // sea lantern / beacon
    if (id == 10105) return vec3(0.92, 0.90, 1.00); // end rod
    if (id == 10106) return vec3(1.00, 0.16, 0.08); // redstone
    if (id == 10107) return vec3(1.00, 0.82, 0.40); // ochre froglight
    if (id == 10108) return vec3(0.50, 1.00, 0.55); // verdant froglight
    if (id == 10109) return vec3(0.95, 0.60, 1.00); // pearlescent froglight
    if (id == 10110) return vec3(1.00, 0.62, 0.30); // shroomlight
    if (id == 10111) return vec3(0.62, 0.22, 1.00); // crying obsidian etc.
    if (id == 10115) return vec3(0.62, 0.22, 1.00); // nether portal / end gateway
    if (id == 10112) return vec3(0.35, 0.85, 0.80); // sculk / glow lichen
    if (id == 10113) return vec3(0.75, 0.50, 1.00); // amethyst / enchanting table
    if (id == 10116) return vec3(0.53, 0.79, 0.35); // copper torch (green flame)
    if (id == 10117) return vec3(0.60, 0.84, 0.42); // copper lantern (green)
    return vec3(0.0);
}
// Flame height above the block centre (blocks); a standing torch's flame is ~0.2 above centre.
float lightHeightOffset(int id) {
    if (id == 10100 || id == 10101 || id == 10106) return 0.2;
    return 0.0;
}
// Blocks that never occlude (glass, water, lava, portals).
bool isTransparentId(int id) { return id == 10002 || id == 10003 || id == 10114 || id == 10115; }
float packLightAlpha(float level, float yoff) {
    return (floor(level + 0.5) * 16.0 + floor(clamp(yoff, 0.0, 0.47) * 32.0 + 0.5)) / 255.0;
}

// ---- fog: render-distance fade (matches the sky horizon) + environmental fog ----
float hlFogFactor(vec3 playerPos, float farDist, float fStart, float fEnd) {
    farDist = farDist > 16.0 ? farDist : 512.0;   // guard: never fog the whole world if 'far' is unavailable
    float dist = length(playerPos);
    float rd = smoothstep(farDist * 0.35, farDist * 0.995, dist);
    float env = 0.0;
    if (fEnd > 0.0 && fEnd < farDist && fEnd > fStart) env = clamp((dist - fStart) / (fEnd - fStart), 0.0, 1.0);
    return max(rd, env);
}

#endif
