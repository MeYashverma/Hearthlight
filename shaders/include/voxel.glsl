#ifndef HEARTHLIGHT_VOXEL
#define HEARTHLIGHT_VOXEL

// -----------------------------------------------------------------------------
// The coloured light volume stores one voxel per block, 64 blocks on a side,
// centred on the player. It is written from the shadow vertex shader (which sees
// every terrain vertex) and read from the gbuffer fragment shaders.
//
// `scene_pos` is camera relative. Adding fract(cameraPosition) makes the grid
// line up with world block coordinates even when the camera sits at a
// fractional position, and adding VOXEL_HALF shifts the origin to the corner of
// the volume, so the whole thing becomes integer cell indices.
// -----------------------------------------------------------------------------

vec3 scene_to_voxel(vec3 scene_pos) {
    return scene_pos + fract(cameraPosition) + vec3(float(VOXEL_HALF));
}

vec3 voxel_to_scene(vec3 voxel_pos) {
    return voxel_pos - vec3(float(VOXEL_HALF)) - fract(cameraPosition);
}

bool inside_voxel_volume(vec3 voxel_pos) {
    return all(greaterThanEqual(voxel_pos, vec3(0.0)))
        && all(lessThan(voxel_pos, vec3(float(VOXEL_SIZE))));
}

// Where to sample the volume for a shaded point. Moving half a voxel along the
// normal keeps surface samples out of the solid block they belong to.
vec3 voxel_sample_uvw(vec3 scene_pos, vec3 normal) {
    vec3 p = scene_to_voxel(scene_pos) + normal * 0.5;
    return clamp(p / float(VOXEL_SIZE), 0.0, 1.0);
}

#endif
