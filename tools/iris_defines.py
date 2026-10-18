"""Macros Iris injects into every shader program.

Mirrors StandardMacros.createStandardEnvironmentDefines() from Iris
(common/src/main/java/net/irisshaders/iris/gl/shader/StandardMacros.java).

These are the names a pack must not redeclare. `MC_RENDER_STAGE_NONE = 0` in a
pack becomes `const int 0 = 0` once Iris' `#define` is applied, which is how
Hearthlight failed to load:

    ParseCancellationException: line 91:10 no viable alternative at input
    'const int 0'

Shared by tools/validate.py and tools/iris_compat.py so both see the same world.
"""

from __future__ import annotations

# Mirrors StandardMacros.createStandardEnvironmentDefines() in Iris
# (common/src/main/java/net/irisshaders/iris/gl/shader/StandardMacros.java).
# Values that vary at runtime are given plausible ones; the point is the *names*,
# because a name is what collides.
STANDARD_DEFINES: dict[str, str | None] = {
    "MC_VERSION": "12104",
    "MC_MIPMAP_LEVEL": "4",
    "IRIS_VERSION": "11102",
    "MC_GL_VERSION": "460",
    "MC_GLSL_VERSION": "460",
    "IS_IRIS": None,
    "IRIS_REQUIRES_SEPARATE_ENTITY_DRAWS": None,
    "MAX_COLOR_BUFFERS": "16",
    "IRIS_HAS_TRANSLUCENCY_SORTING": None,
    "IRIS_TAG_SUPPORT": "2",
    "IS_MONOCLE": None,
    "ALLOWS_UNKNOWN_SHADERS": None,
    "MC_NORMAL_MAP": None,
    "MC_SPECULAR_MAP": None,
    "MC_RENDER_QUALITY": "1.0",
    "MC_SHADOW_QUALITY": "1.0",
    "MC_HAND_DEPTH": "0.125",
    # DISTANT_HORIZONS / DISTANT_HORIZONS_TEXTURES are only defined when DH is
    # installed; a pack has to work with them defined, so define them here.
    "DISTANT_HORIZONS": None,
    "DISTANT_HORIZONS_TEXTURES": None,
}

# DH_BLOCK_* from StandardMacros.
for _index, _name in enumerate(
    [
        "UNKNOWN", "LEAVES", "STONE", "WOOD", "METAL", "DIRT", "LAVA", "DEEPSLATE",
        "SNOW", "SAND", "TERRACOTTA", "NETHER_STONE", "WATER", "GRASS", "AIR",
        "ILLUMINATED",
    ]
):
    STANDARD_DEFINES[f"DH_BLOCK_{_name}"] = str(_index)

# getRenderStages(): "MC_RENDER_STAGE_" + WorldRenderingPhase.name(), ordinal.
WORLD_RENDERING_PHASES = [
    "NONE", "SKY", "SUNSET", "CUSTOM_SKY", "SUN", "MOON", "STARS", "VOID",
    "TERRAIN_SOLID", "TERRAIN_CUTOUT_MIPPED", "TERRAIN_CUTOUT", "ENTITIES",
    "BLOCK_ENTITIES", "DESTROY", "OUTLINE", "DEBUG", "HAND_SOLID",
    "TERRAIN_TRANSLUCENT", "TRIPWIRE", "PARTICLES", "CLOUDS", "RAIN_SNOW",
    "WORLD_BORDER", "HAND_TRANSLUCENT",
]
for _ordinal, _phase in enumerate(WORLD_RENDERING_PHASES):
    STANDARD_DEFINES[f"MC_RENDER_STAGE_{_phase}"] = str(_ordinal)

# A representative slice of GL extensions, all of which Iris turns into
# `MC_<extension>` defines.
GL_EXTENSIONS = [
    "GL_ARB_shader_image_load_store",
    "GL_ARB_shader_storage_buffer_object",
    "GL_ARB_compute_shader",
    "GL_ARB_texture_gather",
    "GL_ARB_gpu_shader5",
    "GL_ARB_explicit_attrib_location",
    "GL_ARB_shading_language_420pack",
    "GL_ARB_shader_texture_lod",
    "GL_ARB_texture_query_levels",
    "GL_ARB_conservative_depth",
    "GL_ARB_derivative_control",
    "GL_ARB_separate_shader_objects",
    "GL_ARB_shader_atomic_counters",
    "GL_NV_fragment_shader_barycentric",
    "GL_KHR_blend_equation_advanced",
]

for _extension in GL_EXTENSIONS:
    STANDARD_DEFINES[f"MC_{_extension}"] = None

def as_prelude() -> str:
    """The defines as a GLSL prelude, for tools that do not run a preprocessor."""
    lines = []
    for name, value in STANDARD_DEFINES.items():
        lines.append(f"#define {name} {value}" if value is not None else f"#define {name}")
    return "\n".join(lines) + "\n"


RESERVED = frozenset(STANDARD_DEFINES)
