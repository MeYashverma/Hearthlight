// Shared G-buffer vertex stage. Define PASS_TERRAIN / PASS_ENTITY / PASS_HAND before including.
#include "/lib/settings.glsl"
#include "/lib/common.glsl"

#ifdef PASS_TERRAIN
in vec4 at_midBlock;
#endif
#if defined(PASS_VOXEL) || defined(PASS_VOXEL_EMIT)
in vec4 mc_Entity;
uniform vec3 cameraPositionFract;
flat out ivec3 vCell;
flat out int vId;
flat out float vLevel;
out float vCorner;
#endif

uniform mat4 gbufferModelViewInverse;

out vec2 texcoord;
out vec2 lmcoord;
out vec4 glcolor;
out vec3 normalWS;
out vec3 playerPos;
flat out float emissive;

void main() {
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    lmcoord = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
    glcolor = gl_Color;
    normalWS = mat3(gbufferModelViewInverse) * (gl_NormalMatrix * gl_Normal);

    vec4 viewPos = gl_ModelViewMatrix * gl_Vertex;
    playerPos = (gbufferModelViewInverse * viewPos).xyz;

#ifdef PASS_TERRAIN
    emissive = at_midBlock.w > 0.5 ? 1.0 : 0.0;
#if defined(PASS_VOXEL) || defined(PASS_VOXEL_EMIT)
    {
        vec3 toCentre = at_midBlock.xyz / 64.0;
        vec3 centreRel = playerPos + toCentre + cameraPositionFract;
        vCell = ivec3(floor(centreRel)) + VOXEL_HALF;
        vec3 off = abs(toCentre);
        bool hasMid = dot(at_midBlock.xyz, at_midBlock.xyz) > 0.5;
        vCorner = (hasMid && off.x > 0.484 && off.y > 0.484 && off.z > 0.484) ? 1.0 : 0.0;
        vId = int(mc_Entity.x + 0.5);
        vLevel = hasMid ? at_midBlock.w : 0.0;
    }
#endif
#else
    emissive = 0.0;
#endif

    gl_Position = gl_ProjectionMatrix * viewPos;
}
