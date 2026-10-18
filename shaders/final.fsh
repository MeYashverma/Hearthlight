#version 430 compatibility
// Final: hue-preserving highlight handling. Anything that vanilla could display
// (all channels <= 1) is left untouched; over-bright light is normalised so a
// coloured torch does not clip into a yellow-white blob.

/*
const int colortex0Format = RGBA16F;
const int colortex4Format = RGBA16F;
const bool colortex4Clear = false;
const vec4 colortex2ClearColor = vec4(0.0, 0.0, 0.0, 0.0);
const int shadowMapResolution = 128;
const float shadowDistance = 64.0;
const float shadowDistanceRenderMul = 1.0;
*/

uniform sampler2D colortex0;
in vec2 texcoord;
layout(location = 0) out vec4 outColor;

void main() {
    vec3 c = texture(colortex0, texcoord).rgb;
    float m = max(max(c.r, c.g), c.b);
    c /= max(1.0, m);
    outColor = vec4(c, 1.0);
}
