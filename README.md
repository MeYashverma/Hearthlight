# Hearthlight

Voxel ray-traced local lighting, sun/moon shadows and specular highlights for
**Minecraft Java 26.2 + Iris** (developed against Iris 1.11.4 / Sodium 0.9.2, OpenGL 4.3+,
Vulkan is not supported by Iris).

Torches, lanterns, lava, glowstone and every other emitter become real point lights:
they fall off with distance, respect surface orientation, are blocked by walls and ceilings,
can be coloured, and a torch in your hand lights and shadows the world as you walk.
On top of that the sun and moon cast real shadows, and polished materials catch a
specular highlight. Everything else (textures, sky, water, clouds, fog, UI) stays vanilla.

## Install
1. Install Iris for 26.2 (Fabric or NeoForge) with the Sodium version it requires (Iris 1.11.2 + Sodium 0.9.1 and Iris 1.11.4 + Sodium 0.9.2 are both valid 26.2 pairs).
2. Drop `Hearthlight.zip` into `.minecraft/shaderpacks/` (Options > Video Settings > Shader Packs > Open Folder).
3. Select it. Requires OpenGL 4.3 (compute, SSBO, image load/store). macOS is not supported.

## How it works
| Stage | What happens |
|---|---|
| `shadow.*` | The shadow pass is repurposed as a **voxelizer**. Each terrain quad is collapsed onto one pixel and its fragment writes the block into two 128^3 images: occupancy and light (colour + level). Iris culls this pass to a 128-block box around you. Those same images later feed the sun shadows, so no depth map is rendered. |
| `prepare_a/b.csh` | Count how many voxels the shadow pass wrote. If it wrote (almost) nothing, the next stage switches on its fallback automatically. |
| `gbuffers_*` | Write the vanilla-lit colour (vanilla lightmap, AO, face shading and fog intact) with the *block-light share reduced* near you, plus normals, albedo, a mask and the specular material class. **Fallback voxelizer:** `gbuffers_terrain` also writes visible emitters/occluders into the same volume when the shadow pass produced nothing. Water/glass/hand stay vanilla-lit. |
| `deferred_a/b/c.csh` | Clear counters, scan the volume for emitters into an SSBO light list (up to 2048), bin every light into the 8^3-block cells its range touches (32 per cell). |
| `deferred.fsh` | Per pixel: trace one ray toward the sun or moon through the voxel volume and take the missing direct light back out of the vanilla-lit colour; rank the local lights in its cell, ray-trace the strongest N (Amanatides-Woo DDA), add `albedo x light`, accumulate over time (reprojected) so soft shadows are smooth, then add the sun/moon specular lobe. Held torches are extra lights. |
| `final.fsh` | Hue-preserving highlight normalisation. Anything vanilla could show is untouched. |

Light level and emission come straight from Minecraft (`at_midBlock.w`), so modded emitters work;
known vanilla emitters get hand-picked colours, unknown ones take a hue hint from their texture.

Sun and moon shadows come from two sources that are blended per pixel:

* a ray through the same occupancy volume (one ray per pixel, no second shadow pass), which
  covers everything off screen and at long range;
* a second ray marched through `depthtex1`, i.e. the real geometry Iris just drew. This is
  what gives doors, fences, trapdoors, players and dropped items their actual silhouette
  instead of a 1-block square, and it takes over from the voxel ray once it has walked far
  enough to be trusted. `depthtex1` rather than `depthtex0` so glass, water and portals do
  not block sunlight.

Directions are rebuilt in player space from `gbufferModelViewInverse` — Iris' `sunPosition` is
in *view* space, and using it directly makes the light direction (and therefore every shadow)
rotate with the camera.

Light-emitting blocks are listed at the bottom of this section so they read as the right
colour, but the light level always comes from Minecraft, so a block this pack has never heard
of still lights up (it borrows a hue from its own texture). The list covers every vanilla
source from level 2 up, including the 1.21.9 copper torch and copper lanterns.

Specular is a GGX lobe with Smith geometry and Schlick Fresnel, tinted by the sun/moon colour
and masked by the shadow ray. Only full cubes in the specular classes take part, listed at the
bottom of `block.properties`: metals (10200), polished stone/quartz/amethyst (10201),
ice/snow (10202) and glazed terracotta (10203). Everything else keeps a faint default sheen.

## Settings
Profiles **Low / Medium / High / Ultra** set the three performance knobs. Individual options:
- **Light Intensity / Light Range / Color Strength**: brightness, reach, and how far from vanilla-warm lights drift (default 0.75 keeps it tasteful).
- **Vanilla Fill Light**: share of vanilla's shadowless block light kept as ambient fill. Lower = darker, more contrasty corners.
- **Daylight Suppression**: tones local lights down under open sky by day. Never affects night or caves.
- **Shadow Softness**: 0 = hard and exact; higher = softer penumbra (temporal smoothing).
- **Lights Per Pixel** (main perf control), **Shadow Ray Steps**.
- **Sun Shadows** (on/off), **Sun Shadow Strength** (how much direct light a shadow removes),
  **Sun Shadow Steps** (how far the voxel ray reaches, see limitations).
- **Fine Shadows** (on/off) and **Fine Shadow Steps**: the depth-buffer ray that gives doors,
  fences, players and items their real shadow shape. Turn it off if you see shadow stripes.
- **Specular** (strength of the sun/moon highlight on the materials above).

## Debug views (Settings > Debug View)
- **4 Status panel** (start here): six squares in the top-left corner. All should be **green** while you look at terrain holding a torch.
  1. shadow-pass voxelizer wrote geometry (red = fallback voxelizer is carrying the load)
  2. emitters found in the volume
  3. lights binned near you
  4. G-buffer mask present at screen centre (red = look at terrain, not sky; if still red the pack's G-buffer programs are not running)
  5. a held light is reported by Iris (hold a torch)
  6. the ground under you is voxelized
- **5 G-buffer check**: green = lit by the pack, magenta = drawn by a fallback program (never lit).
- **3 Voxelisation check**: surfaces should look green. **1** lights-per-cell heat map. **2** lighting only.

## Known limitations
- Occluders are **full-cube faces only**: slabs/stairs count as full blocks; fences, panes, plants, torches do not block. Leaves block ~55%, glass 0%. Entities and block entities neither cast nor receive per-light shadows from voxels (they *are* lit).
- Diffuse only, no bounce light, no colored flood-fill: light does not wrap around corners except through the vanilla fill.
- Sun shadows are a hybrid. The fine (depth-buffer) ray only knows what is on screen: a shadow
  cast by something behind you falls back to the 1-block voxel shape, and at a very high sun
  the fine ray leaves the top of the screen after a few blocks, so the voxel square partly
  returns. Long-range shadows are always voxel-resolution.
- Local block light is still occluded by the 1-block voxel only. A closed door blocks it
  completely, but a fence, a pane or a trapdoor blocks or leaks in whole blocks rather than
  in the shape of its rails.
- Water and stained glass get vanilla light only (no local lights yet). Particles and clouds are vanilla.
- Volume is fixed at 128 blocks (+-64). Beyond ~45 blocks lighting blends back to vanilla.
- More than 32 lights overlapping one 8^3 cell, or 2048 lights in view, drops some lights.
- Voxelization runs a shadow-pass draw of nearby terrain every frame: expect a cost similar to a small shadow map.

## Mod compatibility notes
- **Dynamic-light mods (e.g. LambDynamicLights)**: they raise vanilla block light near held torches, which stacks with Hearthlight's own held-light. Disable them when judging the look.
- **LOD mods (e.g. Voxy)**: distant LOD terrain is not part of the voxel volume and may not be lit by this pack.
- **Chunk-culling mods** can remove geometry the voxelizer needs. If Debug View 3 shows red patches, test without them.

## Troubleshooting
- **Nothing lights up**: open Debug View 4 and note which squares are red (see above). Square 1 red alone is fine, the fallback covers it (shadows are then limited to what the camera can see). Check `latest.log` for Iris errors about `shadow`, images or SSBO; confirm OpenGL 4.3+.
- **Torch pools look too dim/bright**: Light Intensity, then Vanilla Fill.
- **Shimmering penumbrae**: lower Shadow Softness or raise Lights Per Pixel.
- Light leaks at long range: raise Shadow Ray Steps.
- **Shadow stripes / acne on the ground**: lower Fine Shadow Steps, or turn Fine Shadows off.
  The rest of the pack is unaffected.
- **Sun shadows look wrong or follow the camera**: they should not — the direction is camera
  independent. Check that `SUN_SHADOW_STEPS` is not 0 and that Debug View 3 shows green
  (red means nothing is voxelized, so there is nothing to shadow against).
- **No specular anywhere**: the material classes need `block.properties`; if you renamed or
  merged that file the highlight silently disappears. Metals are the obvious test.
