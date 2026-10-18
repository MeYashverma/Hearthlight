#version 430 compatibility
// Hearthlight voxelizer. The shadow pass is NOT used for sun shadows: every
// terrain quad is collapsed onto one shadow-map pixel and its fragment writes
// the quad's block into a 3D image (occupancy + light emission).

#include "/lib/settings.glsl"
#include "/lib/common.glsl"

in vec4 mc_Entity;
in vec2 mc_midTexCoord;
in vec4 at_midBlock;

uniform mat4 shadowModelViewInverse;
uniform vec3 cameraPositionFract;

out vec2 texcoord;
flat out ivec3 vCell;
flat out int vId;
flat out float vLevel;
out float vCorner;

void main() {
    texcoord = gl_MultiTexCoord0.xy;

    vec4 viewPos = gl_ModelViewMatrix * gl_Vertex;
    vec3 playerPos = (shadowModelViewInverse * viewPos).xyz;   // camera-relative

    vec3 toCentre = at_midBlock.xyz / 64.0;                    // vertex -> block centre
    vec3 centreRel = playerPos + toCentre + cameraPositionFract;
    ivec3 cell = ivec3(floor(centreRel)) + VOXEL_HALF;

    bool hasMid = dot(at_midBlock.xyz, at_midBlock.xyz) > 0.5;   // Iris can omit mid-block data for some blocks
    bool inside = hasMid && all(greaterThanEqual(cell, ivec3(0))) && all(lessThan(cell, ivec3(VOXEL_RES)));

    // A vertex of a full cube face sits on a block corner: |offset| == 0.5 on every axis.
    vec3 off = abs(toCentre);
    vCorner = (off.x > 0.484 && off.y > 0.484 && off.z > 0.484) ? 1.0 : 0.0;

    vCell = cell;
    vId = int(mc_Entity.x + 0.5);
    vLevel = at_midBlock.w;

    // Collapse the quad onto the centre pixel of the (tiny) shadow map.
    vec2 corner = sign(gl_MultiTexCoord0.xy - mc_midTexCoord.xy);
    vec2 c = vec2(1.0 / SHADOW_RES) + corner * (0.75 / SHADOW_RES);
    gl_Position = inside ? vec4(c, 0.0, 1.0) : vec4(2.0, 2.0, 2.0, 1.0);
}
