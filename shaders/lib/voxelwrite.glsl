// Shared voxel write. Used by the shadow-pass voxelizer (primary) and by the
// terrain G-buffer pass (automatic fallback). Requires common.glsl.
#ifndef HL_VOXELWRITE_GLSL
#define HL_VOXELWRITE_GLSL

layout(r8) uniform image3D voxelOcc;
layout(rgba8) uniform image3D voxelLight;
uniform sampler2D gtexture;

// Emission only. Used by the translucent G-buffer pass so that lava and nether
// portals, which the shadow pass never draws, still light the scene.
void hlWriteEmission(ivec3 cell, int id, float level, vec2 uv) {
    if (level < 1.5) return;
    if (any(lessThan(cell, ivec3(0))) || any(greaterThanEqual(cell, ivec3(VOXEL_RES)))) return;

    vec3 col = lightColorFromId(id);
    if (dot(col, col) < 1e-4) {
        // Unknown emitter: take a hue hint from its own texture, but keep it
        // bright enough that a new block still reads as a light.
        vec3 t = texture(gtexture, uv).rgb;
        float m = max(max(t.r, max(t.g, t.b)), 1e-3);
        col = mix(vec3(1.0, 0.78, 0.52), t / m, 0.6);
        col = max(col, vec3(0.35, 0.30, 0.24));
    }
    imageStore(voxelLight, cell, vec4(col, level / 15.0));
}

void hlWriteVoxel(ivec3 cell, int id, float level, float corner, vec2 uv) {
    // Occupancy: only full-cube faces count (slabs/stairs read as full, plants/panes as empty).
    float opacity = blockOpacity(id);
    if (corner > 0.995 && opacity > 0.0) {
        imageStore(voxelOcc, cell, vec4(opacity));
    }
    hlWriteEmission(cell, id, level, uv);
}

#endif
