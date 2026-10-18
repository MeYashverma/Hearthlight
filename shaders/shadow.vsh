#version 430 compatibility
// Shadow pass vertex stage: ordinary distorted sun/moon shadow map transform.
// Per-vertex block data is forwarded to the geometry stage, which voxelizes terrain.

#include "/lib/settings.glsl"
#include "/lib/common.glsl"

in vec4 mc_Entity;
in vec4 at_midBlock;

uniform mat4 shadowModelViewInverse;

out vec2 texCoordV;
out vec4 colorV;
out vec3 posV;      // camera-relative position
out vec3 normalV;   // camera-relative face normal
out vec3 midV;      // vertex -> block centre (blocks); zero for entities
flat out int idV;
flat out float levelV;

void main() {
    texCoordV = gl_MultiTexCoord0.xy;
    colorV = gl_Color;

    vec4 viewPos = gl_ModelViewMatrix * gl_Vertex;
    posV = (shadowModelViewInverse * viewPos).xyz;
    normalV = mat3(shadowModelViewInverse) * (gl_NormalMatrix * gl_Normal);
    midV = at_midBlock.xyz / 64.0;
    levelV = at_midBlock.w;
    idV = int(mc_Entity.x + 0.5);

    vec4 clip = gl_ProjectionMatrix * viewPos;
    clip.xy = distortShadow(clip.xy);
    gl_Position = clip;
}
