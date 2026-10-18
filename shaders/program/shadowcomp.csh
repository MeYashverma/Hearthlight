/*
    Hearthlight - coloured light propagation

    One Jacobi iteration per shadow update. Every air cell takes the average of
    its six neighbours from the previous frame, decayed by LIGHT_DECAY; emitter
    cells are pinned to their own colour. Light therefore spreads one block per
    frame and fades out after roughly ten blocks, which is the range where a
    colour cast is visible at all.

    The volume moves with the player. Sampling the previous buffer at
    `pos + (floor(cameraPosition) - floor(previousCameraPosition))` cancels that
    motion so the light field stays put in the world instead of sliding along.

    The two colour images are ping-ponged by frame parity. The write target and
    the read sampler are swapped together, so a dispatch never reads the image
    it writes.
*/

#include "/include/global.glsl"
#include "/include/light_colors.glsl"

layout(local_size_x = 32, local_size_y = 1, local_size_z = 1) in;
const ivec3 workGroups = ivec3(2, 64, 64);

writeonly uniform image3D light_img_a;
writeonly uniform image3D light_img_b;

uniform sampler3D light_sampler_a;
uniform sampler3D light_sampler_b;

uniform usampler3D voxel_sampler;

const ivec3 FACE_OFFSETS[6] = ivec3[6](
    ivec3(1, 0, 0),
    ivec3(-1, 0, 0),
    ivec3(0, 1, 0),
    ivec3(0, -1, 0),
    ivec3(0, 0, 1),
    ivec3(0, 0, -1)
);

bool inside(ivec3 p) {
    return all(greaterThanEqual(p, ivec3(0)))
        && all(lessThan(p, ivec3(VOXEL_SIZE)));
}

vec3 gather_light(sampler3D light_sampler, ivec3 pos) {
    ivec3 centre = clamp(pos, ivec3(0), ivec3(VOXEL_SIZE - 1));
    vec3 sum = texelFetch(light_sampler, centre, 0).rgb;

    for (int i = 0; i < 6; ++i) {
        ivec3 neighbour = pos + FACE_OFFSETS[i];
        if (inside(neighbour)) {
            sum += texelFetch(light_sampler, neighbour, 0).rgb;
        }
    }

    return sum * (1.0 / 7.0);
}

void update_light(
    writeonly image3D light_img,
    sampler3D light_sampler,
    ivec3 pos,
    uint block_id,
    bool first_frames
) {
    bool emitter = block_id >= 32u && block_id < 80u;
    bool opaque = (block_id >= 1u && block_id < 32u) || emitter;

    vec3 light = emitter ? emitter_color(int(block_id)) : vec3(0.0);

    if (!opaque && !first_frames) {
        ivec3 shift = ivec3(
            floor(cameraPosition) - floor(previousCameraPosition)
        );
        vec3 spread = gather_light(light_sampler, pos + shift) * LIGHT_DECAY;
        light += min(spread, vec3(1.0));
    }

    imageStore(light_img, pos, vec4(clamp(light, 0.0, 1.0), 1.0));
}

void main() {
    ivec3 pos = ivec3(gl_GlobalInvocationID);
    if (!inside(pos)) {
        return;
    }

    // Images are not cleared every frame (the light field has to survive
    // between frames), so ignore whatever is in them right after the pack is
    // loaded instead of letting uninitialised memory seed the field.
    bool first_frames = frameCounter < 2;

    uint block_id = texelFetch(voxel_sampler, pos, 0).x;

    if ((frameCounter & 1) == 0) {
        update_light(light_img_a, light_sampler_b, pos, block_id, first_frames);
    } else {
        update_light(light_img_b, light_sampler_a, pos, block_id, first_frames);
    }
}
