// ---------------------------------------------------------------------------
// Hearthlight - user options. Everything here is editable in the Iris shader
// settings screen. Internal constants live in common.glsl (NOT options).
// ---------------------------------------------------------------------------
#ifndef HL_SETTINGS_GLSL
#define HL_SETTINGS_GLSL

#define LIGHT_INTENSITY 1.00 // [0.50 0.75 1.00 1.25 1.50 2.00]
#define LIGHT_RANGE 1.00 // [0.60 0.80 1.00 1.20 1.40]
#define COLOR_STRENGTH 0.75 // [0.00 0.25 0.50 0.75 1.00]
#define VANILLA_FILL 0.35 // [0.00 0.15 0.25 0.35 0.50 0.75 1.00]
#define DAY_SUPPRESS 0.65 // [0.00 0.35 0.65 0.85]
#define SHADOW_SOFTNESS 0.50 // [0.00 0.25 0.50 0.75 1.00]
#define SHADOW_RAY_STEPS 36 // [24 36 48 64]
#define MAX_LIGHTS_PER_PIXEL 4 // [2 4 6 8]
#define SUN_SHADOWS 1 // [0 1]
#define SUN_SHADOW_STRENGTH 0.55 // [0.00 0.25 0.40 0.55 0.70 0.90]
#define SUN_SHADOW_STEPS 32 // [16 24 32 48 64]
#define SS_SHADOWS 1 // [0 1]
#define SS_SHADOW_STEPS 20 // [12 20 28 40]
#define SUN_SPECULAR 0.60 // [0.00 0.20 0.40 0.60 1.00 1.50]
#define DEBUG_VIEW 0 // [0 1 2 3 4 5]

#endif
