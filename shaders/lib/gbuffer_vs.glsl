// Shared G-buffer vertex stage. Define PASS_TERRAIN for block data (emissive flag).
#include "/lib/settings.glsl"
#include "/lib/common.glsl"

#ifdef PASS_TERRAIN
in vec4 at_midBlock;
#endif

uniform mat4 gbufferModelViewInverse;

out vec2 texcoord;
out vec2 lmcoord;
out vec4 glcolor;
out vec3 normalWS;
out vec3 normalVS;
out vec3 playerPos;
flat out float emissive;
flat out float isGui;

void main() {
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    lmcoord = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
    glcolor = gl_Color;
    normalVS = gl_NormalMatrix * gl_Normal;
    normalWS = mat3(gbufferModelViewInverse) * normalVS;

    vec4 viewPos = gl_ModelViewMatrix * gl_Vertex;
    playerPos = (gbufferModelViewInverse * viewPos).xyz;

    // The inventory / GUI is drawn with an orthographic projection: never treat it as world geometry.
    isGui = abs(gl_ProjectionMatrix[3][3] - 1.0) < 0.01 ? 1.0 : 0.0;

#ifdef PASS_TERRAIN
    emissive = at_midBlock.w > 0.5 ? 1.0 : 0.0;
#else
    emissive = 0.0;
#endif

    gl_Position = gl_ProjectionMatrix * viewPos;
}
