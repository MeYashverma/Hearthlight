# Hearthlight

Dynamic sun and moon shadows plus voxel ray-traced local lights for **Minecraft Java 26.2 + Iris**
(Iris 1.11.2+ with its matching Sodium; OpenGL 4.3+, macOS is not supported).

## What you get
- **Directional sun and moon** from a real shadow map: the light direction follows the sky, shadows lengthen toward sunset, the moon is a real (phase-dependent) second light, and everything casts: the **player, mobs, fences, slabs, stairs, walls, trees/leaves, houses, terrain**.
- **Local lights that behave like lights**: torches, lanterns, lava, glowstone, sea lanterns, end rods, froglights, **Nether portals** and any modded emitter light the room with natural falloff, wall/floor/ceiling response and shadows. Held torches light and shadow the world too.
- **Colored light**: warm fire, blue soul fire, orange lava, purple portals, cool sea lanterns, golden glowstone. Fill light follows Minecraft's own light spreading around corners and tints with the nearest emitter.
- **Exact partial blocks for local-light shadows**: half-block resolution, so a light over a slab, stair, full block or open air behaves consistently.
- **Players, mobs, fences and items cast torch shadows too**: the strongest nearby lights are also traced through the depth buffer, so the shapes the half-block volume cannot hold still cast a real shadow (see Settings > Local Light Shadows).
- **Clean sky and horizon**: render-distance fog and a horizon haze that match, so no hard band. **Inventory/GUI icons are safe** (the old fog/lightmap logic no longer touches orthographic GUI rendering).
- Vanilla identity kept: no bloom, no color grading, no texture changes; anything vanilla could display is untouched.

## Install
Iris + its matching Sodium for 26.2, drop `Hearthlight.zip` into `.minecraft/shaderpacks/`, select it. Start with the **Medium** profile.

## How it works
| Stage | What happens |
|---|---|
| `shadow.vsh/gsh/fsh` | One shadow pass, two jobs. It renders a distorted sun/moon shadow map (terrain, translucents, entities, players, block entities, alpha-tested). Its geometry stage also **voxelizes terrain** into a 128^3 block volume: per block an 8-bit mask of occupied half-block octants (full cubes, slabs, stairs, doors; foliage counts as partial) and the emitter colour/level/flame height. |
| `prepare_a/b/c.csh` | Count voxelized blocks, scan the volume for emitters into an SSBO light list (2048), bin lights into 8^3-block cells. |
| `gbuffers_*` | Write albedo, normal, vanilla sky/block light and an emissive flag. Water/glass/hand stay vanilla-lit. GUI geometry (orthographic) is drawn plainly. |
| `deferred.fsh` | Ambient sky (vanilla light levels, dimmer in daylight so shadows read) + sun/moon with PCF shadow map + tinted vanilla-propagated fill + ray-traced local lights (strongest N per pixel, half-block DDA, plus a depth-buffer ray for the strongest few, temporal smoothing) + render-distance fog + horizon haze. |
| `final.fsh` | Hue-preserving highlight normalisation. |

## Settings
Profiles **Low / Medium / High / Ultra** set shadow resolution/distance/filtering and the local-light cost. Sun & Moon: strengths, daytime ambient, sun path tilt, shadow softness. Local lights: intensity, range, color strength, light spread, daylight suppression, shadow softness.

## Debug views (Settings > Debug View)
- **4 Status panel**: six squares top-left, all **green** while looking at terrain holding a torch: (1) shadow pass voxelized geometry, (2) emitters found, (3) lights near you, (4) G-buffer mask at screen centre, (5) held light reported, (6) ground under you voxelized.
- **5** G-buffer mask (green = lit by the pack). **6** sun/moon shadow only. **3** voxelisation check. **1** lights-per-cell heat map. **2** lighting only.

## Known limitations
- Entities cast sun/moon shadows and receive all lighting. For local lights they only cast a shadow through the depth-buffer ray (**Fine Light Shadows**, strongest 2 lights by default), so a mob that is off screen still does not block a torch.
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
- **A torch shadow is missing**: raise *Fine Shadow Lights* (or *Fine Light Shadows* if it is off) so that light gets the depth-buffer ray.
- **Hand or held item is invisible**: it must write the G-buffer; if you edit `gbuffers_hand.fsh`, keep `RENDERTARGETS: 0,1,2,3` and `PASS_HAND`, otherwise the deferred pass paints over it.
