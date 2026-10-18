#version 430 compatibility
// Final: hue-preserving highlight handling. Anything vanilla could show (all channels <= 1)
// is untouched; over-bright light is normalised so a coloured torch cannot clip into a yellow-white blob.

#include "/lib/settings.glsl"

/*
const int colortex0Format = RGBA16F;
const int colortex3Format = RGBA16F;
const int colortex4Format = RGBA16F;
const bool colortex4Clear = false;
const vec4 colortex2ClearColor = vec4(0.0, 0.0, 0.0, 0.0);
const vec4 colortex3ClearColor = vec4(0.0, 0.0, 0.0, 0.0);
*/

uniform sampler2D colortex0;
in vec2 texcoord;
layout(location = 0) out vec4 outColor;

void main() {
    vec3 c = texture(colortex0, texcoord).rgb * EXPOSURE;
    // Hue-preserving clamp: only geometry that is genuinely over-bright is
    // touched, so vanilla colours are byte-identical at EXPOSURE = 1.
    float m = max(max(c.r, c.g), c.b);
    c /= max(1.0, m);
    outColor = vec4(c, 1.0);
}
