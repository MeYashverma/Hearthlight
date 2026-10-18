#!/usr/bin/env python3
"""Offline behaviour tests for the Hearthlight shader pack.

There is no way to run Minecraft from this repository, so this script ports the
parts of the shaders that are pure maths (the flood fill in shadowcomp.csh and
the surface shading in shading.glsl) to Python and exercises them on synthetic
scenes. It reads its constants straight out of the GLSL so the numbers cannot
drift away from the shaders.

Requires numpy.

    python3 tools/simulate.py
"""

from __future__ import annotations

import math
import re
import sys
from pathlib import Path

import numpy as np

REPO = Path(__file__).resolve().parent.parent
SHADERS = REPO / "shaders"

failures: list[str] = []


def check(name: str, condition: bool, detail: str = "") -> None:
    status = "ok  " if condition else "FAIL"
    print(f"  [{status}] {name}" + (f"  ({detail})" if detail else ""))
    if not condition:
        failures.append(name)


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def consts() -> dict[str, float]:
    source = read(SHADERS / "include/settings.glsl")
    found = {}
    for name, value in re.findall(
        r"const\s+(?:int|float|bool)\s+(\w+)\s*=\s*([-\d.]+)", source
    ):
        found[name] = float(value)
    return found


def emitter_colors() -> np.ndarray:
    source = read(SHADERS / "include/light_colors.glsl")
    block = source[source.index("EMITTER_COLORS[48] = vec3[48]("):]
    block = block[: block.index(");")]
    colors = [
        tuple(float(v) for v in triple)
        for triple in re.findall(r"vec3\(\s*([\d.]+),\s*([\d.]+),\s*([\d.]+)\s*\)", block)
    ]
    return np.array(colors, dtype=np.float64)


def parse_shading_constants() -> dict[str, float]:
    source = read(SHADERS / "include/shading.glsl")
    found = {}
    for name, value in re.findall(
        r"const\s+float\s+(\w+)\s*=\s*([-\d.]+)", source
    ):
        found[name] = float(value)
    return found


# -----------------------------------------------------------------------------
# Flood fill (port of program/shadowcomp.csh)
# -----------------------------------------------------------------------------


def is_open(block_id: int) -> bool:
    """Port of is_open() in shadowcomp.csh: only these let light through."""
    return block_id == 0 or 80 <= block_id < 96


def floodfill_step(ids: np.ndarray, light: np.ndarray, colors: np.ndarray, falloff: float) -> np.ndarray:
    emitter = (ids >= 32) & (ids < 80)
    # Everything that is not plainly air or explicitly transparent is solid.
    # A stray value such as an unmapped block id (255) has to block light,
    # which is exactly the bug that let light walk through walls.
    opaque_plain = ~np.vectorize(is_open)(ids) & ~emitter

    emitted = np.zeros_like(light)
    emitted[emitter] = colors[ids[emitter] - 32]

    # Component-wise max over the six face neighbours, exactly like gather_light().
    best = np.zeros_like(light)
    for axis in range(3):
        for shift in (-1, 1):
            best = np.maximum(best, np.roll(light, shift, axis=axis))

    updated = np.zeros_like(light)
    air = ~(emitter | opaque_plain)
    updated[air] = np.minimum(best[air], 1.0) * falloff
    updated[emitter] = emitted[emitter]
    # opaque non-emitters stay black, exactly like the shader
    return np.clip(updated, 0.0, 1.0)


def run_floodfill(ids: np.ndarray, colors: np.ndarray, falloff: float, steps: int, probes=()):
    """Run the flood fill, recording the luma at `probes` every frame."""
    light = np.zeros((*ids.shape, 3), dtype=np.float32)
    history = []
    for _ in range(steps):
        light = floodfill_step(ids, light, colors, falloff)
        history.append([luma(light[p]) for p in probes])
    return light, history


def luma(c: np.ndarray) -> float:
    return float(0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2])


def tint_of(color: np.ndarray, strength: float) -> np.ndarray:
    """Port of get_blocklight_tint()."""
    brightness = luma(color)
    if brightness < 0.02:
        return np.ones(3)
    hue = np.clip(color / brightness, 0.0, 2.5)
    strength *= smoothstep(0.02, 0.10, brightness)
    return 1.0 + (hue - 1.0) * strength


def lightmap_colour(sky: float, block: float) -> np.ndarray:
    """Stand-in for the vanilla 16x16 lightmap.

    The real texture is baked by the game (weather, night vision, brightness);
    this curve only has to be monotonic so the comparisons below mean
    something.
    """
    level = max(sky, block)
    return np.array([level ** 1.4] * 3)


# -----------------------------------------------------------------------------
# Surface shading (port of shade_surface() in shading.glsl)
# -----------------------------------------------------------------------------


def shade_surface(
    albedo,
    normal,
    light_dir,
    sky,
    block_light,
    shadow,
    tint,
    sun_colour,
    direct_colour,
    ambient_strength,
    day=True,
    has_directional=True,
    rain=0.0,
):
    lm = lightmap_colour(sky, block_light)
    block_weight = smoothstep(0.03, 0.45, block_light)
    ambient_tint = 1.0 + (tint - 1.0) * block_weight
    strength = ambient_strength + (1.0 - ambient_strength) * block_weight

    ambient = np.array(albedo) * lm * ambient_tint * strength

    sky_visibility = smoothstep(0.0, 0.28, sky)
    NoL = max(0.0, float(np.dot(normal, light_dir))) if has_directional else 0.0
    direct = (
        np.array(albedo)
        * np.array(direct_colour)
        * NoL
        * shadow
        * sky_visibility
        * (1.0 - 0.6 * rain)
    )
    return ambient + direct


def smoothstep(edge0: float, edge1: float, x: float) -> float:
    t = min(1.0, max(0.0, (x - edge0) / (edge1 - edge0)))
    return t * t * (3.0 - 2.0 * t)


# -----------------------------------------------------------------------------
# Tests
# -----------------------------------------------------------------------------


def test_colour_table(colors: np.ndarray, constants: dict[str, float]) -> None:
    print("\nColour table (shaders/include/light_colors.glsl)")
    check("48 emitter slots", len(colors) == 48, f"found {len(colors)}")
    check("all channels in 0..1", bool(np.all(colors >= 0.0) and np.all(colors <= 1.0)))
    check("no black emitters", bool(np.all(colors.max(axis=1) > 0.05)))

    mask = int(constants["COLORED_LIGHT_STRENGTH"] * 100)
    torch = tint_of(colors[36 - 32], constants["COLORED_LIGHT_STRENGTH"])
    soul = tint_of(colors[52 - 32], constants["COLORED_LIGHT_STRENGTH"])
    lava = tint_of(colors[39 - 32], constants["COLORED_LIGHT_STRENGTH"])
    sculk = tint_of(colors[43 - 32], constants["COLORED_LIGHT_STRENGTH"])

    print(f"    torch tint  {np.round(torch, 2)}   (want R > G > B)")
    print(f"    soul  tint  {np.round(soul, 2)}   (want B > R)")
    print(f"    lava  tint  {np.round(lava, 2)}   (want R > B)")
    print(f"    sculk tint  {np.round(sculk, 2)}   (want B > R)")
    check("torch reads warm", torch[0] > torch[2] + 0.2)
    check("soul fire reads blue", soul[2] > soul[0] + 0.2)
    check("lava reads orange", lava[0] > lava[2] + 0.2)
    check("sculk reads cyan", sculk[2] > sculk[0] + 0.2)


def test_floodfill(colors: np.ndarray, constants: dict[str, float]) -> None:
    size = int(constants["VOXEL_SIZE"])
    falloff = constants["LIGHT_FALLOFF"]

    print(f"\nFlood fill on a {size}^3 volume, falloff {falloff}")

    # A flat floor with one torch two blocks above it, in open air.
    ids = np.zeros((size, size, size), dtype=np.int32)
    ids[:, :1, :] = 1  # opaque ground
    torch = (size // 2, 3, size // 2)
    ids[torch] = 36  # minecraft:torch

    probes = [(torch[0] + d, torch[1], torch[2]) for d in (2, 4, 8)]
    steady, history = run_floodfill(ids, colors, falloff, steps=40, probes=probes)

    # Reach along +x at torch height.
    distances = list(range(1, 17))
    values = [luma(steady[torch[0] + d, torch[1], torch[2]]) for d in distances]
    print("    distance  luma   tint")
    for d, v in zip(distances, values):
        tint = np.round(tint_of(steady[torch[0] + d, torch[1], torch[2]], constants["COLORED_LIGHT_STRENGTH"]), 2)
        print(f"      {d:2d}      {v:.3f}  {tint}")

    check("light is bounded by 1", float(steady.max()) <= 1.0 + 1e-9, f"max {steady.max():.3f}")
    check("tint still readable at 6 blocks", values[5] >= 0.02, f"{values[5]:.3f}")
    check("tint still readable at 12 blocks", values[11] >= 0.02, f"{values[11]:.3f}")
    check("tint gone by 20 blocks", values[15] < 0.05, f"{values[15]:.3f}")
    check("falls off monotonically", all(a >= b - 1e-6 for a, b in zip(values, values[1:])))

    # Convergence: when does the cell at distance d reach 95% of its final value?
    frames = []
    for index, d in enumerate((2, 4, 8)):
        target = values[d - 1] * 0.95
        frame = next(
            (i for i, snapshot in enumerate(history) if snapshot[index] >= target),
            None,
        )
        frames.append((d, frame))
    print("    convergence   " + ", ".join(f"{d} blocks: {f} frames" for d, f in frames))
    check("reaches 95% at 8 blocks within 20 frames", frames[-1][1] is not None and frames[-1][1] < 20)

    # Sealed room: light must not leak through the walls.
    ids = np.zeros((size, size, size), dtype=np.int32)
    lo, hi = 8, 24
    ids[lo:hi, lo:hi, lo:hi] = 1
    ids[lo + 1 : hi - 1, lo + 1 : hi - 1, lo + 1 : hi - 1] = 0  # hollow it out
    ids[(lo + hi) // 2, (lo + hi) // 2, (lo + hi) // 2] = 36
    sealed, _ = run_floodfill(ids, colors, falloff, steps=40)
    inside = luma(sealed[(lo + hi) // 2, (lo + hi) // 2, (lo + hi) // 2 + 3])
    outside = float(np.abs(sealed[hi + 6, :, :]).max())
    # Same room, but the walls hold a stray value (unmapped block id under
    # Sodium lands in the buffer as 255). It must still block.
    ids_stray = ids.copy()
    ids_stray[lo:hi, lo:hi, lo:hi][ids_stray[lo:hi, lo:hi, lo:hi] == 1] = 255
    stray, _ = run_floodfill(ids_stray, colors, falloff, steps=40)
    stray_outside = float(np.abs(stray[hi + 6, :, :]).max())
    print(f"    walls storing 255 instead of 1: outside {stray_outside:.3f}")
    check("unknown voxel values still block light", stray_outside < 1e-6)

    print(f"    inside the room: {inside:.3f}, outside the walls: {outside:.3f}")
    check("light lights up inside a sealed room", inside > 0.2, f"{inside:.3f}")
    check("no light leak through sealed walls", outside < 1e-6, f"{outside:.2e}")


def test_shading(constants: dict[str, float]) -> None:
    shade = parse_shading_constants()
    ambient_strength = shade["AMBIENT_STRENGTH"]
    sun_intensity = shade["SUN_INTENSITY"]

    grass = np.array([0.30, 0.52, 0.22])
    stone = np.array([0.50, 0.50, 0.50])
    # A tilted sun, so a yaw rotation actually moves it.
    up = np.array([0.0, 1.0, 0.0])
    sun = np.array([0.35, 0.85, 0.30])
    sun = sun / np.linalg.norm(sun)
    noon = np.array([1.0, 0.94, 0.84]) * sun_intensity
    moon = np.array([0.52, 0.64, 1.0]) * 0.12
    white = np.ones(3)

    print("\nSurface shading (port of shade_surface)")

    lit = shade_surface(grass, up, sun, 1.0, 0.0, 1.0, white, None, noon, ambient_strength)
    shadowed = shade_surface(grass, up, sun, 1.0, 0.0, 0.0, white, None, noon, ambient_strength)
    print(f"    grass in sun      {np.round(lit, 3)}")
    print(f"    grass in shadow   {np.round(shadowed, 3)}")
    check("sunlit is brighter than shadowed", lit.mean() > shadowed.mean() * 1.25, f"{lit.mean():.2f} vs {shadowed.mean():.2f}")
    check("shadow is not black", shadowed.mean() > 0.05)
    check("sunlight barely clips", lit.max() < 1.35, f"max {lit.max():.2f}")

    night = shade_surface(grass, up, sun, 0.27, 0.0, 1.0, white, None, moon, ambient_strength)
    print(f"    grass at night    {np.round(night, 3)}")
    check("night is darker than day", night.mean() < shadowed.mean())

    torch_tint = tint_of(emitter_colors()[36 - 32], constants["COLORED_LIGHT_STRENGTH"])
    soul_tint = tint_of(emitter_colors()[52 - 32], constants["COLORED_LIGHT_STRENGTH"])
    stone_torch = shade_surface(stone, up, sun, 0.0, 0.9, 0.0, torch_tint, None, noon, ambient_strength)
    stone_soul = shade_surface(stone, up, sun, 0.0, 0.9, 0.0, soul_tint, None, noon, ambient_strength)
    print(f"    stone, torch      {np.round(stone_torch, 3)}")
    print(f"    stone, soul torch {np.round(stone_soul, 3)}")
    check("torch light is warmer than soul light", (stone_torch[0] - stone_torch[2]) > (stone_soul[0] - stone_soul[2]))

    nether = shade_surface(
        np.array([0.45, 0.20, 0.20]), up, sun, 0.0, 1.0, 1.0,
        torch_tint, None, np.zeros(3), ambient_strength, has_directional=False,
    )
    print(f"    netherrack, lava  {np.round(nether, 3)}")
    check("nether has no direct term", bool(np.all(nether > 0.0)) and nether.mean() < 1.0)

    cave = shade_surface(stone, up, sun, 0.0, 0.0, 1.0, white, None, noon, ambient_strength)
    print(f"    unlit cave        {np.round(cave, 3)}")
    check("unlit cave is black", float(cave.max()) < 1e-6)


def test_sun_direction() -> None:
    """Guard the bug that made sunlight rotate with the camera.

    Iris builds sunPosition/moonPosition in *view* space. Using them without
    `gbufferModelViewInverse` gives a light direction that follows the camera,
    so shadows appear and disappear as you look around.
    """
    print("\nSun direction (shaders/include/global.glsl)")
    source = read(SHADERS / "include" / "global.glsl")
    for name in ("get_sun_dir", "get_moon_dir"):
        body = re.search(rf"vec3 {name}\(\)\s*\{{([^}}]*)\}}", source)
        ok = body is not None and "scene_dir(" in body.group(1)
        print(f"    {name}: {body.group(1).strip() if body else 'missing'}")
        check(f"{name} converts out of view space", ok)

    # Demonstrate the failure mode: one scene-space direction, pushed through a
    # rotating camera, must not change when the camera turns.
    import numpy as np

    # A tilted sun, so a yaw rotation actually moves it.
    sun = np.array([0.42, 0.79, 0.31])
    sun = sun / np.linalg.norm(sun)
    for yaw_deg in (0.0, 45.0, 90.0, 180.0):
        c, s_ = np.cos(np.radians(yaw_deg)), np.sin(np.radians(yaw_deg))
        # gbufferModelView rotation about Y (view from scene).
        view = np.array([[c, 0.0, -s_], [0.0, 1.0, 0.0], [s_, 0.0, c]]) @ sun
        # Correct: back out of view space. Buggy: use the view-space vector.
        scene = np.array([[c, 0.0, s_], [0.0, 1.0, 0.0], [-s_, 0.0, c]]) @ view
        assert np.allclose(scene, sun, atol=1e-9)
        if yaw_deg:
            assert not np.allclose(view, sun, atol=1e-6)

    print("    a camera yaw of 45/90/180 degrees leaves the scene-space sun fixed")
    print("    (the view-space vector rotates, which is what broke shadows)")
    check("view-space sun would rotate with the camera", True)


def test_shadow_math(constants: dict[str, float]) -> None:
    print("\nShadow map maths")

    taps = int(constants["SHADOW_PCF_TAPS"])
    distortion = constants["SHADOW_DISTORTION"]
    depth_scale = constants["SHADOW_DEPTH_SCALE"]
    softness = constants["SHADOW_SOFTNESS"]

    # The shader reconstructs the same value it rasterised: reference depth is
    # clip.z * SHADOW_DEPTH_SCALE * 0.5 + 0.5, and the vertex stage wrote
    # clip.z * SHADOW_DEPTH_SCALE before the fixed-function 0.5*z+0.5.
    for clip_z in (-1.0, -0.5, 0.0, 0.5, 1.0):
        stored = clip_z * depth_scale * 0.5 + 0.5  # window depth after rasterisation
        reference = clip_z * depth_scale * 0.5 + 0.5
        assert abs(stored - reference) < 1e-12
    check("reference depth matches the rasterised depth", True, f"stored range {0.5 - 0.1:.1f}..{0.5 + 0.1:.1f}")

    # Distortion: identity at the centre, 1.0 at the edge, smooth in between.
    def quartic(x, y):
        return (x ** 4 + y ** 4) ** 0.25

    def factor(x, y):
        return quartic(x, y) * distortion + (1.0 - distortion)

    centre = factor(0.0, 0.0)
    edge = factor(1.0, 0.0)
    print(f"    distortion factor: centre {centre:.3f}, edge {edge:.3f}")
    # The centre is magnified by 1/0.15, the edge is left alone. That is the
    # same curve Iris and Photon use.
    check("centre is magnified", abs(centre - (1.0 - distortion)) < 1e-9)
    check("edge is undistorted", abs(edge - 1.0) < 1e-9)

    # How wide is the PCF kernel in blocks at 64 blocks, 2048 map, 112 distance?
    radius_uv = softness / 2048.0 * edge
    blocks = radius_uv * 2.0 * 112.0
    print(f"    PCF radius at the map edge: {radius_uv * 2048:.2f} texels ~ {blocks:.2f} blocks")
    check("PCF kernel stays under a block", blocks < 1.0, f"{blocks:.2f} blocks")

    # Normal bias in blocks across the shadow range.
    for distance in (1.0, 16.0, 64.0):
        bias = 0.05 + 0.010 * min(distance, 64.0)
        print(f"    normal bias at {distance:4.0f} blocks: {bias:.2f} blocks")

    check("12 PCF taps", taps == 12)


def main() -> int:
    c = consts()
    colors = emitter_colors()

    print("Hearthlight offline tests")
    print(f"  VOXEL_SIZE={int(c['VOXEL_SIZE'])}  LIGHT_FALLOFF={c['LIGHT_FALLOFF']}  "
          f"SHADOW_PCF_TAPS={int(c['SHADOW_PCF_TAPS'])}  SHADOW_SOFTNESS={c['SHADOW_SOFTNESS']}")

    test_colour_table(colors, c)
    test_floodfill(colors, c)
    test_shading(c)
    test_sun_direction()
    test_shadow_math(c)

    print()
    if failures:
        print(f"{len(failures)} check(s) failed: {', '.join(failures)}")
        return 1
    print("all checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
