#ifndef HEARTHLIGHT_SETTINGS
#define HEARTHLIGHT_SETTINGS

// Coloured block light is the whole point of the pack, so it is always on.
#define COLORED_LIGHTS

// The pack never reads the shadow colour buffers (shadows are depth only), so
// there is no reason to clear them every frame.
const bool shadowcolor0Clear = false;
const bool shadowcolor1Clear = false;

// -----------------------------------------------------------------------------
// Quality settings. Iris reads these const directives while loading the pack,
// so changing them here is the supported way to trade quality for performance.
// -----------------------------------------------------------------------------

// Shadow map resolution. 2048 is a good match for a 1080p screen; drop to 1536
// or 1024 on integrated GPUs when the frame time matters more than crisp edges.
const int shadowMapResolution = 2048; // [1024 1536 2048 3072 4096]

// Shadow distance in blocks. 112 is enough for a 12 render distance; the cost
// of a larger map is mostly in the terrain that has to be drawn twice.
const float shadowDistance = 112.0; // [64.0 80.0 96.0 112.0 128.0 160.0 192.0]

// 1.0 keeps the shadow map at the configured distance. Negative values would
// follow the vanilla shadow distance slider instead.
const float shadowDistanceRenderMul = 1.0;

// Tilts the shadow frustum so that vertical shadows are slightly longer than
// horizontal ones, like the sun being a bit lower in the sky.
const float sunPathRotation = -35.0; // [-40.0 -35.0 -30.0 -20.0 -10.0 0.0 10.0 20.0 30.0 35.0 40.0]

// Shadow filtering. A fixed Vogel disk of SHADOW_PCF_TAPS taps, rotated per
// pixel, gives clean penumbrae without the cost of ray marched PCSS.
const int SHADOW_PCF_TAPS = 12;
const float SHADOW_SOFTNESS = 1.15;
const float SHADOW_DISTORTION = 0.85;
const float SHADOW_DEPTH_SCALE = 0.2;

// Local coloured light volume, in blocks. 64 means a 64x64x64 grid centred on
// the player, so each voxel is exactly one block. Larger values spread light a
// little further but cost cubically more. If you change this, change the three
// image sizes in shaders/shaders.properties to match.
const int VOXEL_SIZE = 64;
const int VOXEL_HALF = 32;

// How much light survives one voxel of travel. The flood fill takes the
// brightest neighbour, so this is a plain per-block falloff: 0.8^n drops below
// the 0.02 tint threshold at 17 blocks, close to the 14 block radius of a
// torch in vanilla. Raise it towards 1.0 to make coloured light reach further.
const float LIGHT_FALLOFF = 0.80;

// Tint strength of coloured block light on top of the vanilla lightmap.
const float COLORED_LIGHT_STRENGTH = 0.88;

// Strength of the light colour cast by the held item.
const float HANDHELD_LIGHT_STRENGTH = 0.55;

// Diagnostic output for terrain. Change the number, reload shaders (F3+T or the
// shader screen) and look at the ground:
//
//   0  normal shading
//   1  shadow factor     white = lit, black = shadowed
//   2  coloured light    the raw light volume, boosted so it is visible
//   3  surface normal    should be a smooth rainbow that follows the shape
//   4  sun direction     colour = sun direction * 0.5 + 0.5
//
// 3 tells you whether this pack is drawing the terrain at all, 1 and 2 tell you
// which of the two features is missing.
#define DEBUG_VIEW 0

#endif
