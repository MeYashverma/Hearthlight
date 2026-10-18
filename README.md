# Hearthlight

A small, hand written Iris shader pack for Minecraft Java **1.21.x / 26.2**.
It keeps the vanilla look and spends its budget on the two things that change
how the world reads: real sun and moon shadows, and coloured light from torches,
lanterns, lava, portals and everything else that glows.

Designed to run on modest hardware (target: Radeon 760M class integrated
graphics at 1080p) rather than to win a screenshot contest.

## Features

- **Directional shadows** from a 2048² shadow map with a Vogel disk PCF kernel,
  the same radial distortion Iris and Photon use, and a slope scaled normal
  bias. The shadow frustum follows the player and snaps to the block grid, so
  shadows do not swim while you walk.
- **Coloured block light** from a 64×64×64 voxel volume centred on the player.
  Emitters seed their colour, a Jacobi flood fill in a compute shader spreads it
  around corners, and the result tints the vanilla lightmap. Walls, ceilings and
  foliage cast the light properly; glass and leaves let it through.
- **Coloured held light**: a torch in the hand lights the ground warm, a soul
  torch blue, a copper lantern green-ish.
- **Vanilla faithful**: no tone mapping, no bloom, no TAA, no "cinematic" fog.
  Textures, the lightmap and the sun colour all stay in the gamma space vanilla
  uses, so the pack looks like the game with better light, not like a different
  game. The sky, sun, moon, stars and clouds are passed through untouched.
- **Every dimension is handled.** The overworld gets sun/moon shadows, the
  nether gets coloured light from lava and fire with no shadow pass at all, and
  the end is ambient only.
- **Cheap by construction**: no deferred pass, no composite pass, no full screen
  post processing, and no final pass. Terrain is shaded once, in the gbuffer
  pass, and Iris copies the result to the screen.

## Requirements

| | |
|---|---|
| Minecraft | 1.21.x, tested against Iris for 26.2 |
| Loader | Fabric or NeoForge with **Iris** |
| Sodium | **Strongly recommended** (all development targets Sodium's terrain path) |
| GPU | Anything with image load/store and compute shaders (GL 4.3+) |

Distant Horizons and Voxy are **not** supported yet: neither `dh_terrain` nor
`voxy.json` ships with the pack, so LOD terrain will be missing or unshaded when
those mods are enabled. Turn them off, or wait for a later version.

## Installation

1. Copy the `shaders/` folder (or the built `Hearthlight.zip`) into
   `.minecraft/shaderpacks/`.
2. Select **Hearthlight** in `Options → Video Settings → Shader Packs`.

## Settings

Quality knobs are `const`s at the top of `shaders/include/settings.glsl`:

| Setting | Default | Notes |
|---|---|---|
| `shadowMapResolution` | 2048 | 1024 / 1536 for integrated GPUs |
| `shadowDistance` | 112 | blocks; 64–80 is plenty at render distance 8 |
| `sunPathRotation` | −35° | tilts the shadow frustum |
| `SHADOW_PCF_TAPS` | 12 | 4 is a hard shadow, 24 is soft |
| `SHADOW_SOFTNESS` | 1.15 | filter radius in shadow texels |
| `VOXEL_SIZE` | 64 | coloured light volume, 1 block per voxel |
| `LIGHT_DECAY` | 0.99 | lower = shorter reach for coloured light |
| `COLORED_LIGHT_STRENGTH` | 0.88 | how strongly block light tints a surface |
| `HANDHELD_LIGHT_STRENGTH` | 0.55 | brightness of the light in your hand |

Colours live in `shaders/include/light_colors.glsl`, indexed by the block IDs
assigned in `shaders/block.properties`. Adding a light emitting block means
adding it to both files (or reusing an existing slot).

## How it works

```
shadow.vsh/.fsh        depth only, plus voxelization of the terrain into voxel_img
shadowcomp.csh         one flood fill iteration, writes light_img_a/b (ping-pong)
gbuffers_terrain       albedo * lightmap + sun/moon * shadow, tinted by the light volume
gbuffers_water         the same, plus specular and an animated normal
gbuffers_textured_lit  entities, items, particles, weather and the hand
gbuffers_textured      sky, clouds, sun, moon, stars (passthrough)
gbuffers_basic         sky plane, void plane, block outline (passthrough)
```

The shadow vertex shader is the only place that sees every terrain vertex, so it
is also what fills the voxel volume: `1` for an opaque block, `32..79` for an
emitter, nothing for anything light can pass through. The compute shader then
averages six neighbours per cell, pins emitters, and samples the previous frame
at a camera-shifted position so the light field stays anchored in the world.

The lighting code samples the *vanilla lightmap* for intensity and only takes
the hue from the voxel volume, which keeps the pack cheap: a wrong or stale
colour can never make a cave brighter than vanilla says it should be.

## Validating

`tools/validate.py` expands the pack's `#include`s and runs `glslangValidator`
over every program wrapper in `shaders/world*`:

```sh
python3 tools/validate.py --glslang /path/to/glslangValidator
```

This checks that the shaders compile, which is not the same as checking that
they look right: there is no way to render Minecraft from this repository.

## Known limitations

- Coloured light spreads one block per shadow update, so a room takes a second
  or two to fill with colour after a torch is placed. This is the same trade
  off Photon makes.
- The coloured light volume is 64 blocks wide and centred on the player; light
  sources further away contribute nothing.
- Only block light is coloured. Sunlight, ambient sky light, entities and the
  hand are tinted by the vanilla lightmap.
- `shadowcolor0` is not used, so stained glass and portals do not colour the
  shadows themselves.
- Distant Horizons and Voxy LOD terrain are not shaded by the pack.

## License

MIT, see `LICENSE`. The pack is written from scratch; it was developed with
Photon and Complementary Reimagined as references for Iris behaviour, but no
shader code is copied from them.
