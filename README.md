# Hearthlight

Dynamic sun and moon shadows plus voxel ray-traced local lights for **Minecraft Java 26.2 + Iris**
(Iris 1.11.2+ with its matching Sodium; OpenGL 4.3+, macOS is not supported).

## What you get
- **Directional sun and moon** from a real shadow map: the light direction follows the sky, shadows lengthen toward sunset, the moon is a real (phase-dependent) second light, and everything casts: the **player, mobs, fences, slabs, stairs, walls, trees/leaves, houses, terrain**.
- **Local lights that behave like lights**: torches, lanterns, lava, glowstone, sea lanterns, end rods, froglights, **Nether portals** and any modded emitter light the room with natural falloff, wall/floor/ceiling response and shadows. Held torches light and shadow the world too.
- **Colored light**: warm fire, blue soul fire, orange lava, purple portals, cool sea lanterns, golden glowstone. Fill light follows Minecraft's own light spreading around corners and tints with the nearest emitter.
- **Exact partial blocks for local-light shadows**: half-block resolution, so a light over a slab, stair, full block or open air behaves consistently.
- **A hand that is always visible**, even in a pitch-dark room, and a *Hand Brightness* slider if you want it stronger.
- **Clean sky and horizon**: render-distance fog and a horizon haze that match, so no hard band. **Inventory/GUI icons are safe** (the old fog/lightmap logic no longer touches orthographic GUI rendering).
- Vanilla identity kept: no bloom, no color grading, no texture changes; anything vanilla could display is untouched.

## Install
Iris + its matching Sodium for 26.2, drop `Hearthlight.zip` into `.minecraft/shaderpacks/`, select it. Start with the **Medium** profile.

## How it works
| Stage | What happens |
|---|---|
| `shadow.vsh/gsh/fsh` | One shadow pass, two jobs. It renders a distorted sun/moon shadow map (terrain, translucents, entities, players, block entities, alpha-tested). Its geometry stage also **voxelizes terrain** into a 128^3 block volume: per block an 8-bit mask of occupied half-block octants (full cubes, slabs, stairs, doors; foliage counts as partial) and the emitter colour/level/flame height. |
| `prepare_a/b/c.csh` | Count voxelized blocks, scan the volume for emitters into an SSBO light list (2048), bin lights into 8^3-block cells. |
| `gbuffers_*` | Write albedo, normal, vanilla sky/block light and an emissive flag. Water/glass/hand stay vanilla-lit. GUI geometry (orthographic) is drawn plainly. The hand writes the G-buffer with a zero mask. |
| `deferred.fsh` | Ambient sky (vanilla light levels, dimmer in daylight so shadows read) + sun/moon with PCF shadow map + tinted vanilla-propagated fill + ray-traced local lights (strongest N per pixel, half-block DDA, temporal smoothing) + render-distance fog + horizon haze. The hand is detected through `depthtex2` and left untouched. |
| `final.fsh` | Hue-preserving highlight normalisation. |

## Settings
Profiles **Low / Medium / High / Ultra** set shadow resolution/distance/filtering and the local-light cost. The screens:

- **Sun & Moon**: sun and moon strength, sun warmth, sun path tilt, shadow quality and softness.
- **Sky & Atmosphere**: daytime and night ambient levels, sunrise/sunset tint strength, rain darkening, horizon haze.
- **Local Lights**: intensity, range, colour strength, vanilla fill, daylight suppression, shadow softness.
- **Performance**: shadow map resolution, shadow distance, lights per pixel, light ray steps.
- **View**: hand brightness, fog distance, exposure.

## Debug views (Settings > Debug View)
- **4 Status panel**: six squares top-left, all **green** while looking at terrain holding a torch: (1) shadow pass voxelized geometry, (2) emitters found, (3) lights near you, (4) G-buffer mask at screen centre, (5) held light reported, (6) ground under you voxelized.
- **5** G-buffer mask (green = lit by the pack). **6** sun/moon shadow only. **3** voxelisation check. **1** lights-per-cell heat map. **2** lighting only. **7** hand check: your hand and held item are painted red, everything else dark -- if nothing is red the hand is not being drawn at all.

## Known limitations
- Entities receive all lighting and cast sun/moon shadows, but they do not block *local* light unless you turn on the experimental **Fine Light Shadows**. That ray reads the depth buffer, which only stores the nearest surface, so anything standing between you and the lit ground (a fence, the lamp itself, your own hand) projects a phantom shadow over it. Measured on a randomised scene sweep: 16% of traceable pixels were wrongly shadowed. It is off by default for that reason.
- Local-light occlusion is half-block resolution: carpets, fences, panes, plants and torches do not block torch light unless the fine ray can see them.
- In first person your own body is not rendered, so it has no depth-buffer shadow; switch to third person to see it.
- The hand item is vanilla-lit: Hearthlight does not add local lights to it.
- Water, glass and the hand item are vanilla-lit (no sun shadows / local lights on them). Sky, stars, sun and moon sprites are vanilla.
- Volume is +-64 blocks; beyond that lighting blends back to vanilla fill. More than 32 lights per 8^3 cell or 2048 in view drops some.
- The shadow pass is heavier than before (real shadow map + voxelization). Use Low/Medium on weaker GPUs.

## Troubleshooting
- **Pack fails to load / shader error**: paste the `latest.log` lines mentioning `shadow.gsh` or the failing file.
- **No local light or no shadows**: Debug View 4; note which squares are red.
- Fences/walls look too dark/light in shadow: *Daytime Ambient*. Torches too weak/strong: *Light Intensity*, then *Light Spread*.
- **A mob or dropped item casts no torch shadow**: that needs *Fine Light Shadows*, which is off by default; see the limitation above before enabling it.
- **Hand or held item is invisible**: it must write the G-buffer; if you edit `gbuffers_hand.fsh`, keep `RENDERTARGETS: 0,1,2,3` and `PASS_HAND`, otherwise the deferred pass paints over it.
