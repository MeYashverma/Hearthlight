#version 430 compatibility
/* DRAWBUFFERS:0 */
// Shadow map fragment stage: alpha-tested so leaves, fences' transparent texels, etc. cast detailed shadows.

#include "/lib/settings.glsl"

uniform sampler2D gtexture;
in vec2 texCoord;
in vec4 color;
layout(location = 0) out vec4 outColor;

void main() {
    vec4 c = texture(gtexture, texCoord) * color;
    if (c.a < 0.1) discard;
    outColor = c;
}
