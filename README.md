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

Download [`Hearthlight.zip`](Hearthlight.zip) (the green **Download** button on
that page, or `curl -L -O https://github.com/MeYashverma/Hearthlight/raw/main/Hearthlight.zip`
once this is merged), drop it into `.minecraft/shaderpacks/`, then select
**Hearthlight** in `Options → Video Settings → Shader Packs`.

The zip is rebuilt from the sources with `tools/package.sh`; it contains the
`shaders/` folder at its root, plus this readme and the licence.

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
| `LIGHT_FALLOFF` | 0.80 | per-block falloff; 0.8 reaches 17 blocks |
| `COLORED_LIGHT_STRENGTH` | 0.88 | how strongly block light tints a surface |
| `HANDHELD_LIGHT_STRENGTH` | 0.55 | brightness of the light in your hand |
| `DEBUG_VIEW` | 0 | 0 = normal, 1 = shadow, 2 = light volume, 3 = normals, 4 = sun, 5 = raw voxels |

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

```sh
python3 tools/validate.py --glslang /path/to/glslangValidator
python3 tools/iris_compat.py          # needs pcpp: pip install pcpp
python3 tools/simulate.py             # needs numpy
```

- **`validate.py`** expands the includes, injects the macros Iris injects,
  compiles every program with glslang and links each vertex/fragment pair the way
  Iris does at load time. 39 stages and 18 links pass.
- **`iris_compat.py`** runs the pack through a real C preprocessor (`pcpp`, the
  job JCPP does inside Iris) with Iris' standard defines applied, then compiles
  the result — plus a direct check for identifiers that collide with Iris' own
  `#define`s.
- **`simulate.py`** ports the pure maths (the flood fill, `shade_surface()`, the
  shadow bias and distortion) to Python and runs it on synthetic scenes.

### Reserved names

Iris `#define`s a set of names in *every* program, including
`MC_RENDER_STAGE_<PHASE>` (one per render phase, value = its ordinal), `IS_IRIS`,
`MC_VERSION`, `MC_GL_VERSION`, `DH_BLOCK_*`, `MC_<GLEXTENSION>` and others.

Declaring any of them in a pack is fatal in a non-obvious way: Hearthlight's
first upload declared `const int MC_RENDER_STAGE_NONE = 0;`, which Iris rewrote
to `const int 0 = 0;` and refused to load:

```
basic: ParseCancellationException: line 91:10 no viable alternative at input 'const int 0'
```

Use the names, never declare them. `tools/iris_defines.py` holds the list;
`validate.py` and `iris_compat.py` both fail if the pack declares one.

## Troubleshooting

Everything visual is controlled by one switch. Set `DEBUG_VIEW` at the bottom of
`shaders/include/settings.glsl`, reload shaders, and look at the ground:

| Value | Screen shows | What it tells you |
|---|---|---|
| `3` | rainbow that follows the block shapes | the pack *is* shading terrain |
| `1` | white = lit, black = shadowed | whether the shadow map is being sampled |
| `2` | coloured blobs around torches | whether the light volume is filling |
| `4` | a flat colour | the scene-space sun direction |
| `5` | red / green / blue blocks | what the shadow pass stored: red = solid, green = emitter, blue = transparent, black = air |

`5` is the important one for coloured light. If the ground is **black**
everywhere, the shadow pass is not writing the voxel volume at all (the fill has
nothing to work with). If it is red, the volume is fine and the problem is
downstream in the propagation.

If `3` shows vanilla-looking terrain, the pack's programs are not running at all
(check `latest.log` for `[Iris]` errors). If `1` is white everywhere, no shadow
map is being rendered. If `2` is black around a torch, the compute flood fill is
not running.

Note that **Voxy and Distant Horizons are not supported**: with either mod
enabled the LOD terrain is drawn by the mod, not by this pack. Test with them
disabled.

## Known limitations

- Coloured light spreads one block per shadow update, so a room fills with
  colour in well under a second, but the field is only refreshed when the
  shadow map updates (every other frame by default).
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
