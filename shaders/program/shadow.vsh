/*
    Hearthlight - shadow vertex shader

    Terrain, cutout, water and (via the fallback chain) entities all end up
    here. While terrain is being drawn it also fills the coloured light volume:
    one voxel per block, storing 1 for opaque blocks, 32..79 for emitters and 0
    for anything light can pass through.

    The write is deliberately permissive. An earlier version only wrote when
    `renderStage` was one of the four terrain phases, and when that uniform was
    stale the whole volume stayed empty - which looks exactly like "coloured
    light does nothing", with no error anywhere. Now every phase writes except
    the ones that are definitely not world geometry (entities, the hand, the
    block outline). Writing a voxel twice is harmless: the last write wins and
    every write for a block lands in that block's own cell.

    The shadow map uses the same distortion as Iris and Photon: a fourth-root
    radial warp to spend more texels near the centre, and a z scale of 0.2 to
    keep more precision in a 32 bit depth buffer.
*/

#include "/include/global.glsl"
#include "/include/voxel.glsl"

out vec2 uv;
flat out int material_mask;

attribute vec3 at_midBlock;
attribute vec3 mc_Entity;

writeonly uniform uimage3D voxel_img;

// Phases that must not write to the light volume.
bool is_non_world_phase() {
    return renderStage == MC_RENDER_STAGE_ENTITIES
        || renderStage == MC_RENDER_STAGE_BLOCK_ENTITIES
        || renderStage == MC_RENDER_STAGE_HAND_SOLID
        || renderStage == MC_RENDER_STAGE_HAND_TRANSLUCENT
        || renderStage == MC_RENDER_STAGE_OUTLINE;
}

void main() {
    uv = gl_MultiTexCoord0.xy;
    material_mask = int(mc_Entity.x) - 10000;

    vec3 view_pos = (gl_ModelViewMatrix * vec4(gl_Vertex.xyz, 1.0)).xyz;

    if (!is_non_world_phase()) {
        // Land on the centre of the block this vertex belongs to. at_midBlock
        // holds (block centre - vertex) * 64 as a byte pair, so adding it puts
        // every vertex of a quad in the same voxel no matter which corner the
        // vertex is.
        vec3 mid_view
            = (gl_ModelViewMatrix
               * vec4(gl_Vertex.xyz + at_midBlock * (1.0 / 64.0), 1.0))
                  .xyz;
        vec3 mid_scene = (shadowModelViewInverse * vec4(mid_view, 1.0)).xyz;
        vec3 voxel_pos = scene_to_voxel(mid_scene);

        if (inside_voxel_volume(voxel_pos)) {
            uint stored;
            if (material_mask >= 32 && material_mask < 80) {
                stored = uint(material_mask); // emitter, carries its colour id
            } else if (material_mask >= 80 && material_mask < 96) {
                stored = 0u; // listed as light-transparent: leave the cell empty
            } else {
                stored = 1u; // everything else is solid
            }

            if (stored > 0u) {
                imageStore(
                    voxel_img,
                    ivec3(voxel_pos),
                    uvec4(stored, 0u, 0u, 0u)
                );
            }
        }
    }

#if !defined WORLD_OVERWORLD
    // Neither the nether nor the end has a directional light, so the shadow map
    // is never read there. The voxel writes above still matter (lava and fire
    // are the main light sources in the nether).
    gl_Position = vec4(-1.0);
    return;
#endif

    vec3 clip_pos = project_ortho(gl_ProjectionMatrix, view_pos);

    float distortion = quartic_length(clip_pos.xy) * SHADOW_DISTORTION
        + (1.0 - SHADOW_DISTORTION);

    clip_pos.xy /= distortion;
    clip_pos.z *= SHADOW_DEPTH_SCALE;

    gl_Position = vec4(clip_pos, 1.0);
}
