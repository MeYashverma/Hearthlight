// ---------------------------------------------------------------------------
// Hearthlight - user options (Iris shader settings screen).
// Internal constants live in common.glsl and are NOT options.
// ---------------------------------------------------------------------------
#ifndef HL_SETTINGS_GLSL
#define HL_SETTINGS_GLSL

// ---- sun & moon (directional light with a real shadow map) ----
#define SUN_STRENGTH 1.00 // [0.50 0.75 1.00 1.25 1.50]
#define MOON_STRENGTH 1.00 // [0.50 1.00 1.50 2.00 3.00]
#define AMBIENT_DAY 0.55 // [0.35 0.45 0.55 0.65 0.75 0.85]
#define SUN_SHADOW_QUALITY 2 // [1 2 3]
#define SUN_SHADOW_SOFTNESS 1.00 // [0.50 1.00 1.50 2.00]

// ---- local lights (torches, lanterns, lava, portals ...) ----
#define LIGHT_INTENSITY 1.00 // [0.50 0.75 1.00 1.25 1.50 2.00 2.50]
#define LIGHT_RANGE 1.00 // [0.60 0.80 1.00 1.20 1.40]
#define COLOR_STRENGTH 0.80 // [0.00 0.25 0.50 0.80 1.00]
#define VANILLA_FILL 0.35 // [0.00 0.15 0.25 0.35 0.50 0.70 1.00]
#define DAY_SUPPRESS 0.50 // [0.00 0.35 0.50 0.65 0.85]
#define SHADOW_SOFTNESS 0.50 // [0.00 0.25 0.50 0.75 1.00]
#define SHADOW_RAY_STEPS 64 // [32 48 64 96]
#define MAX_LIGHTS_PER_PIXEL 4 // [2 4 6 8]

// ---- sky & atmosphere ----
#define AMBIENT_NIGHT 1.00 // [0.60 0.80 1.00 1.20 1.40]
#define DAWN_DUSK_TINT 1.00 // [0.00 0.50 1.00 1.50 2.00]
#define SUN_WARMTH 0.00 // [0.00 0.50 1.00 1.50 2.00]
#define RAIN_DARKENING 0.75 // [0.00 0.25 0.50 0.75 1.00]
#define HORIZON_HAZE 1.00 // [0.50 0.75 1.00 1.25 1.50 2.00]

// ---- view ----
#define HAND_BRIGHTNESS 1.00 // [0.75 1.00 1.25 1.50 2.00]
#define FOG_DISTANCE 1.00 // [0.75 1.00 1.25 1.50]
#define EXPOSURE 1.00 // [0.85 0.95 1.00 1.05 1.15 1.25]

#define DEBUG_VIEW 0 // [0 1 2 3 4 5 6 7]

// ---- shadow map (read by Iris) ----
const int shadowMapResolution = 2048; // [1024 2048 3072 4096]
const float shadowDistance = 96.0; // [64.0 96.0 128.0 160.0]
const float shadowDistanceRenderMul = 1.0;
const float sunPathRotation = -25.0; // [-40.0 -30.0 -25.0 -15.0 0.0 15.0 30.0]

#endif
