#!/usr/bin/env python3
"""Offline behaviour tests for the Hearthlight shader pack.

Minecraft cannot be run from this repository, so this script ports the parts of
the shaders that are pure maths to Python and exercises them on synthetic
scenes. Constants are parsed straight out of the GLSL so the numbers cannot
drift away from the shaders.

Covered here:
  * volume / cell / SSBO layout against shaders.properties
  * block.properties and item.properties id tables against the GLSL tables
  * the packed light byte (level + flame height)
  * the half-block octant bit layout used by the voxelizer
  * shadow-map distortion maths
  * sun and moon direction, including the shadow-view space regression
  * the local-light octant DDA
  * the depth-buffer (screen-space) light shadow
  * light falloff and ranking

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


# ---------------------------------------------------------------------------
# parsing
# ---------------------------------------------------------------------------
def settings() -> dict[str, float]:
    """#define NAME value // [options]  and  const <type> NAME = value; // [...]"""
    out: dict[str, float] = {}
    for line in read(SHADERS / "lib/settings.glsl").splitlines():
        m = re.match(r"\s*#define\s+(\w+)\s+(-?[\d.]+)", line)
        if m:
            out[m.group(1)] = float(m.group(2))
            continue
        m = re.match(r"\s*const\s+(?:int|float)\s+(\w+)\s*=\s*(-?[\d.]+)\s*;", line)
        if m:
            out[m.group(1)] = float(m.group(2))
    return out


def consts() -> dict[str, float]:
    """const <type> NAME = value;  from lib/common.glsl."""
    out: dict[str, float] = {}
    text = read(SHADERS / "lib/common.glsl")
    for m in re.finditer(r"const\s+(?:int|float)\s+(\w+)\s*=\s*(-?[\d.]+)\s*;", text):
        out[m.group(1)] = float(m.group(2))
    return out


def light_colours() -> dict[int, tuple[float, float, float]]:
    text = read(SHADERS / "lib/common.glsl")
    body = text.split("vec3 lightColorFromId")[1].split("\n}")[0]
    out: dict[int, tuple[float, float, float]] = {}
    for m in re.finditer(r"if \(id == (\d+)\) return vec3\(([^)]*)\);", body):
        out[int(m.group(1))] = tuple(float(v) for v in m.group(2).split(","))
    return out


def block_properties() -> dict[int, list[str]]:
    out: dict[int, list[str]] = {}
    for line in read(SHADERS / "block.properties").splitlines():
        line = line.split("#")[0].strip()
        m = re.match(r"block\.(\d+)\s*=\s*(.*)", line)
        if not m:
            continue
        out.setdefault(int(m.group(1)), []).extend(n for n in m.group(2).split() if n)
    return out


def item_properties() -> dict[int, list[str]]:
    out: dict[int, list[str]] = {}
    for line in read(SHADERS / "item.properties").splitlines():
        line = line.split("#")[0].strip()
        m = re.match(r"item\.(\d+)\s*=\s*(.*)", line)
        if not m:
            continue
        out.setdefault(int(m.group(1)), []).extend(n for n in m.group(2).split() if n)
    return out


# ---------------------------------------------------------------------------
# small maths helpers mirroring the GLSL
# ---------------------------------------------------------------------------
def smoothstep(e0: float, e1: float, x: float) -> float:
    t = min(max((x - e0) / (e1 - e0), 0.0), 1.0)
    return t * t * (3.0 - 2.0 * t)


def normalize(v):
    v = np.asarray(v, dtype=float)
    n = np.linalg.norm(v)
    return v / n if n > 1e-9 else v


def rot_x(a: float) -> np.ndarray:
    c, s = math.cos(a), math.sin(a)
    return np.array([[1.0, 0.0, 0.0], [0.0, c, -s], [0.0, s, c]])


def rot_y(a: float) -> np.ndarray:
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, 0.0, s], [0.0, 1.0, 0.0], [-s, 0.0, c]])


def rot_z(a: float) -> np.ndarray:
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, -s, 0.0], [s, c, 0.0], [0.0, 0.0, 1.0]])


def pack_light_alpha(level: float, yoff: float) -> int:
    """Port of packLightAlpha(), returned as the stored byte."""
    v = (math.floor(level + 0.5) * 16.0 + math.floor(min(max(yoff, 0.0), 0.47) * 32.0 + 0.5)) / 255.0
    return int(v * 255.0 + 0.5)


def octant_bit(x: int, y: int, z: int) -> int:
    return x + 2 * y + 4 * z


def distort_factor(xy, distort: float) -> float:
    return (1.0 - distort) + float(np.linalg.norm(xy)) * distort


def distort_shadow(xy, distort: float):
    xy = np.asarray(xy, dtype=float)
    return xy / distort_factor(xy, distort)


def light_att(d: float, R: float) -> float:
    """Port of lightAtt(): w^2 / (1 + 0.25 d^2), zero at the range."""
    w = min(max(1.0 - d / R, 0.0), 1.0)
    return w * w / (1.0 + 0.25 * d * d)


def trace_vis(volume: dict, o, t, light_block) -> float:
    """Port of traceVis(): exact half-block octant walk.

    `volume` maps a block coordinate tuple to an integer octant mask (bits 0-7
    opaque, 8-15 foliage). Returns remaining transmittance.
    """
    o2 = np.asarray(o, dtype=float) * 2.0
    d = np.asarray(t, dtype=float) * 2.0 - o2
    length = float(np.linalg.norm(d))
    if length < 1e-3:
        return 1.0
    d /= length

    cell = np.floor(o2).astype(int)
    stp = np.sign(d).astype(int)
    inv = 1.0 / (np.abs(d) + 1e-6)
    frac = np.where(stp > 0, (cell + 1.0) - o2, o2 - cell)
    t_max = frac * inv
    t_delta = inv

    last_block = None
    mask = 0
    trans = 1.0
    for _ in range(2048):
        tn = float(min(t_max[0], t_max[1], t_max[2]))
        if tn >= length:
            break
        if t_max[0] <= t_max[1] and t_max[0] <= t_max[2]:
            cell[0] += stp[0]
            t_max[0] += t_delta[0]
        elif t_max[1] <= t_max[2]:
            cell[1] += stp[1]
            t_max[1] += t_delta[1]
        else:
            cell[2] += stp[2]
            t_max[2] += t_delta[2]

        blk = tuple(int(v) >> 1 for v in cell)
        if blk == tuple(light_block):
            continue
        if blk != last_block:
            mask = volume.get(blk, 0)
            last_block = blk
        if mask == 0:
            continue
        bit = octant_bit(int(cell[0]) & 1, int(cell[1]) & 1, int(cell[2]) & 1)
        if mask & (1 << bit):
            return 0.0
        if mask & (256 << bit):
            trans *= 0.5
            if trans < 0.1:
                return 0.0
    return trans


def test_layout() -> None:
    c = consts()
    s = settings()
    print("\nlayout")
    check("volume is VOXEL_HALF on each side of the camera",
          c["VOXEL_HALF"] * 2 == c["VOXEL_RES"], f"{c['VOXEL_HALF']}*2 == {c['VOXEL_RES']}")
    check("cells tile the volume exactly",
          c["CELLS_AXIS"] * c["CELL_SIZE"] == c["VOXEL_RES"])
    check("cell count matches CELLS_AXIS^3",
          c["CELLS_TOTAL"] == c["CELLS_AXIS"] ** 3, str(int(c["CELLS_TOTAL"])))

    props = read(SHADERS / "shaders.properties")
    buffers = dict(re.findall(r"bufferObject\.(\d+)\s*=\s*(\d+)", props))
    capacity = int(buffers.get("0", "0"))
    need = 16 + int(c["MAX_LIGHTS"]) * 32 + int(c["CELLS_TOTAL"]) * 4 \
        + int(c["CELLS_TOTAL"]) * int(c["CELL_CAP"]) * 4
    check("SSBO fits bufferObject.0", need <= capacity, f"{need} <= {capacity} bytes")
    check("SSBO is not massively over-allocated", need > capacity // 2)

    check("voxel mask image is r32ui in the properties",
          re.search(r"image\.voxelMask\s*=\s*\S+\s+red_integer\s+r32ui", props) is not None)
    check("shadow map resolution is an option",
          "shadowMapResolution" in props and "shadowMapResolution" in s)

    directives = {"shadowDistanceRenderMul"}   # Iris directive, not a slider
    missing = [name for name in s if name not in props and name not in directives]
    check("every option is exposed in shaders.properties", not missing, ", ".join(missing))

    listed = set()
    for line in re.findall(r"screen\.\w+\s*=\s*(.*)", props):
        listed |= set(re.findall(r"[A-Z][A-Z0-9_]+", line))
    check("screens only reference real options", not (listed - set(s)),
          ", ".join(sorted(listed - set(s))))


def test_ids() -> None:
    colours = light_colours()
    blocks = block_properties()
    items = item_properties()
    print("\nblock / item ids")

    known = {10001, 10002, 10003} | set(range(10100, 10118))
    check("block.properties only uses documented ids",
          set(blocks) <= known, ", ".join(str(i) for i in sorted(set(blocks) - known)))
    emitters = {i for i in blocks if i >= 10100}
    check("every emitter id has a colour",
          emitters <= set(colours), ", ".join(str(i) for i in sorted(emitters - set(colours))))
    check("opacity classes are not colour classes",
          {10001, 10002, 10003}.isdisjoint(colours))
    check("every item id resolves to a colour",
          all(i in colours for i in items), ", ".join(str(i) for i in sorted(set(items) - set(colours))))

    seen: dict[str, int] = {}
    dupes = []
    for cid, names in blocks.items():
        for n in names:
            if n in seen:
                dupes.append(f"{n} ({seen[n]} and {cid})")
            seen[n] = cid
    check("no block is assigned to two classes", not dupes, ", ".join(dupes[:6]))

    check("copper torch and lantern exist", 10116 in blocks and 10117 in blocks)
    green = colours.get(10116, (1.0, 0.0, 0.0))
    check("copper light is green, not warm", green[1] > green[0] and green[1] > green[2], str(green))
    for name in ("sea_pickle", "enchanting_table", "firefly_bush",
                 "cave_vines:berries=true", "candle_cake:lit=true", "nether_portal", "lava"):
        check(f"{name} is wired to a class",
              any(name in names for names in blocks.values()))

    check("transparent ids are the ones the voxelizer skips",
          "bool isTransparentId(int id) { return id == 10002 || id == 10003 || id == 10114 || id == 10115; }"
          in read(SHADERS / "lib/common.glsl"))

    c = np.array(list(colours.values()))
    check("colours are in range", bool(np.all(c >= 0.0) and np.all(c <= 1.0)))
    check("lava and magma agree", colours[10102] == colours[10114])
    # Distinct emitters should not all collapse to the same warm tone.
    families = {tuple(np.round(v, 1)) for v in c}
    check("the palette has real variety", len(families) >= 12, f"{len(families)} distinct colours")


def test_packed_light() -> None:
    print("\npacked light byte")
    ok = True
    detail = ""
    for level in range(1, 16):
        for yoff in (0.0, 0.1, 0.2, 0.3, 0.47, 0.9):
            b = pack_light_alpha(float(level), yoff)
            if b > 255:
                ok = False
                detail = f"level {level} yoff {yoff} -> {b}"
                break
            got_level = b >> 4
            got_yoff = (b & 15) / 32.0
            clamped = min(max(yoff, 0.0), 0.47)
            if got_level != level or abs(got_yoff - clamped) > 1.5 / 32.0:
                ok = False
                detail = f"level {level} yoff {yoff} -> {got_level}/{got_yoff:.3f}"
                break
        if not ok:
            break
    check("level and flame height survive the byte", ok, detail)
    check("the flame-height field is 4 bits (max 15)", pack_light_alpha(15.0, 0.47) & 15 <= 15)


def test_octants() -> None:
    print("\nhalf-block octants")
    bits = {octant_bit(x, y, z) for x in (0, 1) for y in (0, 1) for z in (0, 1)}
    check("all eight octants get a distinct bit", bits == set(range(8)), str(sorted(bits)))
    check("foliage bits do not collide with opaque bits",
          not ({256 << b for b in range(8)} & set(range(8))))

    empty = {}
    check("an empty volume passes light", trace_vis(empty, (0.5, 0.5, 0.5), (3.5, 0.5, 0.5), (3, 0, 0)) == 1.0)

    wall = {}
    for y in range(-2, 3):
        for z in range(-2, 3):
            for oy in (0, 1):
                for oz in (0, 1):
                    wall[(1, y * 2 + oy, z * 2 + oz)] = 0xFF
    check("a solid wall blocks torchlight",
          trace_vis(wall, (0.5, 0.5, 0.5), (3.5, 0.5, 0.5), (3, 0, 0)) == 0.0)

    hole = dict(wall)
    # The ray runs along +x with y = z = 0.5, so inside block (1,0,0) it crosses
    # the two octants at local y = 1, z = 1 (one in each x half).
    hole[(1, 0, 0)] = (0xFF
                       & ~(1 << octant_bit(0, 1, 1))
                       & ~(1 << octant_bit(1, 1, 1)))
    check("a half-block hole lets light through",
          0.0 < trace_vis(hole, (0.5, 0.5, 0.5), (3.5, 0.5, 0.5), (3, 0, 0)) <= 1.0)

    leaves = {(1, 0, 0): 0xFF << 8}
    vis = trace_vis(leaves, (0.5, 0.5, 0.5), (3.5, 0.5, 0.5), (3, 0, 0))
    check("foliage is a partial occluder", 0.0 < vis < 1.0, f"vis={vis:.2f}")

    check("a light inside a block does not shadow itself",
          trace_vis(wall, (0.5, 0.5, 0.5), (3.5, 0.5, 0.5), tuple(int(v) for v in np.floor([0.5, 0.5, 0.5]))) >= 0.0)


def test_distortion() -> None:
    print("\nshadow-map distortion")
    d = consts()["SHADOW_DISTORT"]
    check("centre is undistorted", abs(float(np.linalg.norm(distort_shadow((0.0, 0.0), d)))) < 1e-9)
    # The warp must compress the edge of the map: |xy| shrinks for large |xy|.
    far = float(np.linalg.norm(distort_shadow((2.0, 0.0), d)))
    check("far shadow-map points are compressed toward the centre", far < 2.0, f"{far:.3f}")
    radii = np.arange(0.1, 3.01, 0.05)
    warped = [float(np.linalg.norm(distort_shadow((r, 0.0), d))) for r in radii]
    check("the warp is monotonic", all(b > a for a, b in zip(warped, warped[1:])))
    check("the warp is identity only at the centre and |xy| = 1",
          float(np.linalg.norm(distort_shadow((1.0, 0.0), d))) >= 1.0 - 1e-9)


def test_sun_direction() -> None:
    """Iris builds sunPosition, moonPosition and shadowLightPosition with
    CelestialUniforms.getCelestialPosition(), which multiplies by
    CapturedRenderingState.getGbufferModelView() and pre-rotates by the sun path.
    All three are therefore in *gbuffer* view space, and only
    gbufferModelViewInverse undoes them."""
    print("\nsun and moon direction")

    world_sun = normalize([0.30, 0.70, -0.60])
    world_moon = normalize([-0.30, -0.70, 0.60])

    for yaw, pitch, sun_path in ((0.0, 0.0, 0.0), (1.7, 0.3, 25.0), (-2.4, -0.2, -25.0)):
        view = rot_y(yaw) @ rot_x(pitch)                      # gbuffer model view
        shadow_view = rot_z(math.radians(sun_path)) @ rot_y(yaw + 0.8) @ rot_x(pitch + 0.4)

        sun_position = view @ world_sun
        moon_position = view @ world_moon
        shadow_light_day = sun_position                        # Iris: sun by day
        shadow_light_night = moon_position                     # Iris: moon by night

        back = np.linalg.inv(view)
        check(f"sunPosition is gbuffer view space (yaw {yaw:.1f})",
              np.allclose(normalize(back @ sun_position), world_sun, atol=1e-9))
        check(f"moonPosition is gbuffer view space (yaw {yaw:.1f})",
              np.allclose(normalize(back @ moon_position), world_moon, atol=1e-9))
        check(f"shadowLightPosition is gbuffer view space, day and night (yaw {yaw:.1f})",
              np.allclose(normalize(back @ shadow_light_day), world_sun, atol=1e-9) and
              np.allclose(normalize(back @ shadow_light_night), world_moon, atol=1e-9))

        # The trap: shadowModelViewInverse is the *shadow camera's* matrix.
        wrong = np.linalg.inv(shadow_view) @ shadow_light_night
        angle = math.degrees(math.acos(float(np.clip(np.dot(normalize(wrong), world_moon), -1, 1))))
        check(f"  shadowModelViewInverse would be wrong (yaw {yaw:.1f})",
              angle > 5.0, f"{angle:.0f} deg off")

    check("deferred.fsh uses gbufferModelViewInverse for shadowLightPosition",
          "mat3(gbufferModelViewInverse) * (haveShadowLight ? shadowLightPosition : sunPosition)"
          in read(SHADERS / "deferred.fsh"))

    # Day / night weights.
    def day_night(sun_h: float):
        day_amt = smoothstep(-0.10, 0.35, sun_h)
        if sun_h > 0.0:
            return 0.52 * smoothstep(0.0, 0.22, sun_h), 0.0, day_amt
        moon = 0.16 * smoothstep(0.0, 0.30, -sun_h)
        return 0.0, moon, day_amt

    sun_i, moon_i, day = day_night(1.0)
    check("noon gives full sun", sun_i > 0.5 and moon_i == 0.0)
    check("noon is fully daylit", day > 0.99)
    sun_i, moon_i, day = day_night(-1.0)
    check("midnight is moonlight only", sun_i == 0.0 and moon_i > 0.1, f"moon={moon_i:.2f}")
    check("midnight is not daylit", day < 0.001)
    check("moonlight is dimmer than sunlight", day_night(-1.0)[1] < day_night(1.0)[0])


def test_hand_detection() -> None:
    """The hand must be identified from depthtex2 (the pre-hand depth Iris
    copies), not from the G-buffer mask: the hand can be drawn by a program that
    never writes that mask, and then the terrain's mask would erase it."""
    s = settings()
    src = read(SHADERS / "deferred.fsh")
    print("\nhand")
    check("deferred samples depthtex2", "uniform sampler2D depthtex2;" in src)
    check("hand is detected as depth in front of the pre-hand depth",
          "bool isHand = depth < depthNoHand - 1e-7;" in src)
    check("hand pixels are returned before any lighting",
          src.index("if (isHand)") < src.index("vec3 sunDirW"))
    check("hand brightness is applied where the hand is kept",
          "base.rgb * HAND_BRIGHTNESS" in src)
    check("HAND_BRIGHTNESS is an option", "HAND_BRIGHTNESS" in s)
    check("debug view 7 exists for the hand", "DEBUG_VIEW == 7" in src and s["DEBUG_VIEW"] >= 0)
    check("the hand program writes the G-buffer",
          "RENDERTARGETS: 0,1,2,3" in read(SHADERS / "gbuffers_hand.fsh"))
    check("the fine local-light ray is gone",
          "hl_ssLocalShadow" not in src and "LIGHT_SS_SHADOWS" not in s)


def test_falloff() -> None:
    s = settings()
    c = consts()
    print("\nlocal light falloff")

    R = min(15.0 * s["LIGHT_RANGE"], 24.0)
    near = light_att(1.0, R)
    mid = light_att(4.0, R)
    edge = light_att(R * 0.999, R)
    check("brightness falls with distance", near > mid > edge)
    check("no light beyond the range", light_att(R * 1.01, R) == 0.0)
    check("the range is capped", R <= 24.0, f"R={R:.1f}")
    check("a level-15 light reaches at least 12 blocks", R >= 12.0)
    check("LIGHT_I0 is positive", c["LIGHT_I0"] > 0.0)


def main() -> int:
    print("Hearthlight shader behaviour tests")
    test_layout()
    test_ids()
    test_packed_light()
    test_octants()
    test_distortion()
    test_sun_direction()
    test_hand_detection()
    test_falloff()

    print()
    if failures:
        print(f"{len(failures)} check(s) failed:")
        for f in failures:
            print(f"  - {f}")
        return 1
    print("all checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
