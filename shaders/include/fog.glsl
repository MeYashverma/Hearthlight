#ifndef HEARTHLIGHT_FOG
#define HEARTHLIGHT_FOG

// Iris reports the vanilla fog state: which curve, and the colour that the sky
// uses at the horizon. Working in the same gamma space as the textures means
// this blends in without any conversion.

uniform vec3 fogColor;
uniform float fogStart;
uniform float fogEnd;
uniform float fogDensity;
uniform int fogMode;

const int GL_LINEAR_FOG = 0x2601;

float fog_factor(float dist) {
    if (fogMode == GL_LINEAR_FOG) {
        return saturate((dist - fogStart) / max(fogEnd - fogStart, 1.0e-3));
    }

    float d = fogDensity * dist;
    return saturate(1.0 - exp(-d * d));
}

vec3 apply_fog(vec3 color, float dist) {
    return mix(color, fogColor, fog_factor(dist));
}

#endif
