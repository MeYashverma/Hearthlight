#!/usr/bin/env python3
"""Offline behaviour tests for the Hearthlight shader pack.

There is no way to run Minecraft from this repository, so this script ports the
parts of the shaders that are pure maths to Python and exercises them on
synthetic scenes. Constants are parsed straight out of the GLSL so the numbers
cannot drift away from the shaders.

Covered here:
  * SSBO / volume layout consistency with shaders.properties
  * block.properties and item.properties id tables against the GLSL tables
  * sun and moon direction, colour and the day/night blend
  * the sun-shadow voxel walk (occlusion, partial opacity, self-shadowing,
    volume exit, step budget)
  * how much direct light a shadow removes
  * the GGX specular highlight
  * local light ranking

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
    """#define NAME value // [options]  from lib/settings.glsl."""
    out: dict[str, float] = {}
    for line in read(SHADERS / "lib/settings.glsl").splitlines():
        m = re.match(r"\s*#define\s+(\w+)\s+(-?[\d.]+)", line)
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
    out: dict[int, tuple[float, float, float]] = {}
    for m in re.finditer(r"if \(id == (\d+)\) return vec3\(([^)]*)\);", text):
        out[int(m.group(1))] = tuple(float(v) for v in m.group(2).split(","))
    return out


def material_classes() -> dict[int, float]:
    """Ids handled by blockMaterialClass(), sliced out of common.glsl."""
    text = read(SHADERS / "lib/common.glsl")
    body = text.split("float blockMaterialClass")[1].split("\n}")[0]
    out: dict[int, float] = {}
    for m in re.finditer(r"if \(id == (\d+)\) return ([\d.]+);", body):
        out[int(m.group(1))] = float(m.group(2))
    return out


def block_properties() -> dict[int, list[str]]:
    out: dict[int, list[str]] = {}
    for line in read(SHADERS / "block.properties").splitlines():
        line = line.split("#")[0].strip()
        m = re.match(r"block\.(\d+)\s*=\s*(.*)", line)
        if not m:
            continue
        names = [n for n in m.group(2).split() if n]
        out.setdefault(int(m.group(1)), []).extend(names)
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


def direct_light(sun_dir, moon_dir) -> tuple[np.ndarray, float, float, float]:
    """Port of hl_direct(): direction, direct amount, sun-only amount, sun share."""
    sd = normalize(sun_dir)
    md = normalize(moon_dir)
    ws = smoothstep(-0.04, 0.06, sd[1])
    wm = smoothstep(-0.04, 0.06, md[1])
    total = max(ws + wm, 1e-3)
    direction = normalize(sd * ws + md * wm)
    day = (ws / total) * smoothstep(-0.02, 0.22, sd[1])
    up = smoothstep(-0.02, 0.22, max(sd[1], md[1])) * (0.40 + 0.60 * (ws / total))
    return direction, up, day, ws / total


def rot_y(angle: float) -> np.ndarray:
    c, s = math.cos(angle), math.sin(angle)
    return np.array([[c, 0.0, s], [0.0, 1.0, 0.0], [-s, 0.0, c]])


def sun_vis(volume: np.ndarray, P, N, direction, steps: int) -> float:
    """Port of hl_sunVis(): Amanatides-Woo walk toward the light."""
    d = normalize(direction)
    o = np.asarray(P, dtype=float) + np.asarray(N, dtype=float) * 0.06 + d * 0.02

    cell = np.floor(o).astype(int)
    stp = np.sign(d).astype(int)
    inv = 1.0 / (np.abs(d) + 1e-6)
    frac = np.where(stp > 0, (cell + 1.0) - o, o - cell)
    t_max = frac * inv
    t_delta = inv

    trans = 1.0
    for _ in range(steps):
        if t_max[0] <= t_max[1] and t_max[0] <= t_max[2]:
            cell[0] += stp[0]
            t_max[0] += t_delta[0]
        elif t_max[1] <= t_max[2]:
            cell[1] += stp[1]
            t_max[1] += t_delta[1]
        else:
            cell[2] += stp[2]
            t_max[2] += t_delta[2]

        if np.any(cell < 0) or np.any(cell >= volume.shape[0]):
            break
        trans *= 1.0 - volume[tuple(int(c) for c in cell)]
        if trans < 0.02:
            return 0.0
    return trans


def ss_sun_shadow(view_pos, dir_view, sample, cam_f=0.35, steps=20,
                  start=0.12, thickness=0.28, max_dist=32.0):
    """Port of hl_ssSunShadow(). `sample(uv)` returns a scene depth in view
    units, or None for empty sky; `cam_f` is the focal length of the synthetic
    pinhole camera used to project the ray."""
    p = np.asarray(view_pos, dtype=float) + np.asarray(dir_view, dtype=float) * start
    d = normalize(dir_view)
    step_len = 0.18
    travelled = 0.0

    for _ in range(steps):
        dt = min(step_len, max_dist - travelled)
        if dt <= 1e-4:
            break
        p = p + d * dt
        travelled += dt
        step_len *= 1.25

        ray_z = -p[2]
        if ray_z <= 0.05:
            break

        uv = (p[0] / ray_z * cam_f + 0.5, p[1] / ray_z * cam_f + 0.5)
        if not (0.0 <= uv[0] <= 1.0 and 0.0 <= uv[1] <= 1.0):
            break

        depth = sample(uv)
        if depth is None:
            continue
        if ray_z - depth > thickness + 0.012 * travelled:
            return 0.0, 1.0

    return 1.0, smoothstep(1.5, 6.0, travelled)


def shadow_amount(sky_light, NoL, vis, sun_up, strength) -> float:
    return strength * sun_up * NoL * (1.0 - vis) * smoothstep(0.02, 0.25, sky_light)


def material(cls: float):
    """Port of hl_material()."""
    if cls < 0.5:
        return 0.85, 0.03, 0.25
    if cls < 1.5:
        return 0.20, 0.90, 1.00
    if cls < 2.5:
        return 0.33, 0.35, 0.75
    if cls < 3.5:
        return 0.16, 0.18, 0.85
    if cls < 4.5:
        return 0.28, 0.45, 0.70
    return 0.42, 0.18, 0.45


def specular(N, L, V, vis, cls, sun_colour, sun_up, strength_opt) -> np.ndarray:
    """Port of hl_specular()."""
    roughness, reflectance, strength = material(cls)
    N = normalize(N)
    L = normalize(L)
    V = normalize(V)
    if strength <= 0.0 or strength_opt <= 0.0 or sun_up <= 0.001:
        return np.zeros(3)

    H = normalize(L + V)
    NoL = max(float(np.dot(N, L)), 0.0)
    NoV = max(float(np.dot(N, V)), 1e-3)
    NoH = max(float(np.dot(N, H)), 0.0)
    VoH = max(float(np.dot(V, H)), 0.0)
    if NoL <= 0.0:
        return np.zeros(3)

    a = roughness * roughness
    a2 = a * a
    denom = NoH * NoH * (a2 - 1.0) + 1.0
    D = a2 / (math.pi * denom * denom)
    k = a * 0.5
    G = (NoL / (NoL * (1.0 - k) + k)) * (NoV / (NoV * (1.0 - k) + k))
    F = reflectance + (1.0 - reflectance) * (1.0 - VoH) ** 5

    spec = D * G * F / (4.0 * NoL * NoV + 1e-4)
    spec = spec / (1.0 + spec * 0.30)
    return np.asarray(sun_colour) * (spec * NoL * vis * strength * strength_opt * sun_up)


def light_att(d2: float, R: float, att_k: float) -> float:
    x = d2 / (R * R)
    w = min(max(1.0 - x * x, 0.0), 1.0)
    return w * w / (1.0 + att_k * d2)


def estimate(light_pos, level, O, N, att_k, range_scale) -> float:
    P = np.asarray(light_pos) - np.asarray(O)
    d2 = float(np.dot(P, P))
    R = min(level * range_scale, 24.0)
    if d2 >= R * R:
        return 0.0
    ndl = min(max(float(np.dot(N, P / math.sqrt(d2 + 1e-6))) * 0.85 + 0.15, 0.0), 1.0)
    return (level / 15.0) * light_att(d2, R, att_k) * ndl


def rank(scores: list[tuple[float, int]], K: int) -> list[int]:
    """Port of considerCandidate(): descending, first K only."""
    g_score = [0.0] * K
    g_idx = [-1] * K
    for s, idx in scores:
        if s <= g_score[K - 1]:
            continue
        j = K - 1
        while j > 0 and g_score[j - 1] < s:
            g_score[j] = g_score[j - 1]
            g_idx[j] = g_idx[j - 1]
            j -= 1
        g_score[j] = s
        g_idx[j] = idx
    return [i for i in g_idx if i >= 0]


# ---------------------------------------------------------------------------
# tests
# ---------------------------------------------------------------------------
def test_layout() -> None:
    c = consts()
    print("\nlayout")
    check("volume is VOXEL_HALF on each side of the camera",
          c["VOXEL_HALF"] * 2 == c["VOXEL_RES"], f"{c['VOXEL_HALF']}*2 == {c['VOXEL_RES']}")
    check("cells tile the volume exactly",
          c["CELLS_AXIS"] * c["CELL_SIZE"] == c["VOXEL_RES"])
    check("cell count matches CELLS_AXIS^3",
          c["CELLS_TOTAL"] == c["CELLS_AXIS"] ** 3, str(int(c["CELLS_TOTAL"])))

    buffers = dict(re.findall(r"bufferObject\.(\d+)\s*=\s*(\d+)", read(SHADERS / "shaders.properties")))
    capacity = int(buffers.get("0", "0"))
    light_buf = 16 + int(c["MAX_LIGHTS"]) * 32
    cells = int(c["CELLS_TOTAL"]) * 4
    bins = int(c["CELLS_TOTAL"]) * int(c["CELL_CAP"]) * 4
    need = light_buf + cells + bins
    check("SSBO fits bufferObject.0", need <= capacity, f"{need} <= {capacity} bytes")
    check("SSBO is not massively over-allocated", need > capacity // 2)

    res = re.search(r"const int shadowMapResolution = (\d+);", read(SHADERS / "shadow.fsh"))
    check("shadow-map resolution matches SHADOW_RES",
          res is not None and float(res.group(1)) == c["SHADOW_RES"])

    opts = settings()
    props = read(SHADERS / "shaders.properties")
    missing = [name for name in opts if name not in props]
    check("every option is exposed in shaders.properties", not missing, ", ".join(missing))

    screens = set(re.findall(r"screen\.(\w+)\s*=", props))
    listed = set()
    for line in re.findall(r"screen\.\w+\s*=\s*(.*)", props):
        listed |= set(re.findall(r"[A-Z][A-Z0-9_]+", line))
    unknown = listed - set(opts)
    check("screens only reference real options", not unknown, ", ".join(sorted(unknown)))
    check("screens are declared", bool(screens))


def test_ids() -> None:
    colours = light_colours()
    materials = material_classes()
    blocks = block_properties()
    items = item_properties()
    print("\nblock / item ids")

    known = {10001, 10002} | set(range(10100, 10116)) | {10200, 10201, 10202, 10203}
    check("block.properties only uses documented ids",
          set(blocks) <= known, ", ".join(str(i) for i in sorted(set(blocks) - known)))
    check("every id from 10100..10115 has a colour",
          all(i in colours for i in range(10100, 10116)))
    green = colours.get(10114, (1.0, 0.0, 0.0))
    check("copper light is green, not warm", green[1] > green[0] and green[1] > green[2],
          f"{green}")
    check("every material id has a class",
          all(i in materials for i in (10200, 10201, 10202, 10203)))
    check("material classes are unique",
          len(set(materials.values())) == len(materials), str(materials))

    seen: dict[str, int] = {}
    dupes = []
    for cid, names in blocks.items():
        for n in names:
            if n in seen:
                dupes.append(f"{n} ({seen[n]} and {cid})")
            seen[n] = cid
    check("no block is assigned to two classes", not dupes, ", ".join(dupes[:6]))
    check("emitter classes are not empty",
          all(len(blocks.get(i, [])) > 0 for i in range(10100, 10116)))
    check("item ids all resolve to a colour",
          all(i in colours for i in items), ", ".join(str(i) for i in sorted(set(items) - set(colours))))

    c = np.array(list(colours.values()))
    check("colours are in range", bool(np.all(c >= 0.0) and np.all(c <= 1.0)))
    check("colours are distinct", len({tuple(np.round(x, 2)) for x in c}) == len(c))
    check("every colour has some energy", bool(np.all(np.max(c, axis=1) > 0.2)))


def test_sun_geometry() -> None:
    print("\nsun and moon")
    s = settings()

    # A camera yaw must not change the world-space direction of the sun. This is
    # the regression test for using Iris' view-space sunPosition directly.
    world_sun = normalize([0.0, 0.8, 0.6])
    world_moon = normalize([0.0, -0.8, -0.6])
    dirs, ups = [], []
    for yaw in (0.0, 1.3, -2.2, 3.0):
        R = rot_y(yaw)
        sun_position = R @ (world_sun * 100.0)          # what Iris hands the shader
        moon_position = R @ (world_moon * 100.0)
        sd = R.T @ sun_position                          # gbufferModelViewInverse
        md = R.T @ moon_position
        d, up, _, _ = direct_light(sd, md)
        dirs.append(d)
        ups.append(up)
    check("sun direction is independent of camera yaw",
          all(np.allclose(d, world_sun, atol=1e-6) for d in dirs),
          f"max delta {max(float(np.max(np.abs(d - world_sun))) for d in dirs):.2e}")
    check("direct-light amount is independent of camera yaw",
          max(ups) - min(ups) < 1e-9, f"spread {max(ups) - min(ups):.2e}")

    noon_sun = np.array([0.0, 1.0, 0.0])
    noon_moon = np.array([0.0, -1.0, 0.0])
    midnight_sun = np.array([0.0, -1.0, 0.0])
    midnight_moon = np.array([0.0, 1.0, 0.0])

    d, up, day, sun_share = direct_light(noon_sun, noon_moon)
    check("noon light comes from above", d[1] > 0.999 and up > 0.99, f"up={up:.3f}")
    check("noon is sunlight", sun_share > 0.99)
    check("daylight suppression is full at noon", day > 0.99, f"day={day:.3f}")

    d, up, day_night, sun_share = direct_light(midnight_sun, midnight_moon)
    check("midnight light comes from the moon", d[1] > 0.999)
    check("midnight direct light is faint", 0.30 < up < 0.50, f"up={up:.3f}")
    check("midnight is moonlight", sun_share < 0.01)
    check("moonlight never suppresses local lights", day_night < 0.001, f"day={day_night:.3f}")

    # Daytime fades out as the sun approaches the horizon, and the handover to
    # the moon crosses a single dip rather than jumping.
    _, up_noon, _, _ = direct_light(noon_sun, noon_moon)
    _, up_half, _, _ = direct_light(np.array([0.0, 0.1, 0.995]), np.array([0.0, -0.1, -0.995]))
    _, up_set, _, _ = direct_light(np.array([0.0, 0.0, 1.0]), np.array([0.0, 0.0, -1.0]))
    check("direct light fades toward the horizon", up_noon > up_half > up_set,
          f"{up_noon:.2f} > {up_half:.2f} > {up_set:.2f}")
    _, up_just_set, _, _ = direct_light(np.array([0.0, -0.05, 1.0]), np.array([0.0, 0.05, -1.0]))
    check("the handover to moonlight is continuous", abs(up_just_set - up_set) < 0.12,
          f"{up_set:.2f} -> {up_just_set:.2f}")

    d, up, _, _ = direct_light(np.array([0.0, -0.05, 1.0]), np.array([0.0, 0.05, -1.0]))
    check("sun just below the horizon contributes no direct light", up < 0.15, f"up={up:.3f}")

    _, up_night, _, _ = direct_light(midnight_sun, midnight_moon)
    check("shadow strength at night is weaker than at noon",
          s["SUN_SHADOW_STRENGTH"] * up_night < 0.5 * s["SUN_SHADOW_STRENGTH"])


def test_sun_shadows() -> None:
    c = consts()
    s = settings()
    res = int(c["VOXEL_RES"])
    steps = int(s["SUN_SHADOW_STEPS"])
    print("\nsun shadows (voxel walk)")

    empty = np.zeros((res, res, res), dtype=np.float32)
    P = np.array([64.0, 64.0, 64.0])
    up = np.array([0.0, 1.0, 0.0])

    check("open sky is fully lit", abs(sun_vis(empty, P, up, up, steps) - 1.0) < 1e-6)
    check("a ray that leaves the volume is unshadowed",
          abs(sun_vis(empty, np.array([127.0, 127.0, 127.0]), up, normalize([0.5, 1.0, 0.5]), steps) - 1.0) < 1e-6)

    roof = empty.copy()
    roof[60:70, 66:68, 60:70] = 1.0
    check("a roof above the surface blocks the sun",
          sun_vis(roof, P, up, up, steps) == 0.0)

    wall = empty.copy()
    wall[66:68, 60:70, 60:70] = 1.0
    east = normalize([1.0, 0.35, 0.0])
    check("a wall between the surface and a low sun shadows it",
          sun_vis(wall, P, up, east, steps) == 0.0)

    window = wall.copy()
    window[66:68, 64, 64] = 0.0          # one open block in the wall
    flat = normalize([1.0, 0.0, 0.0])
    check("an opening in the wall lets light through",
          sun_vis(window, P, up, flat, steps) > 0.9)
    check("the wall still shadows a ray that misses the opening",
          sun_vis(window, P, up, east, steps) == 0.0)

    leaves = empty.copy()
    leaves[60:70, 66, 60:70] = 0.55
    vis = sun_vis(leaves, P, up, up, steps)
    check("foliage casts a partial shadow", 0.4 < vis < 0.5, f"vis={vis:.3f}")

    check("the surface's own block never shadows it",
          sun_vis(empty, P, up, up, steps) > 0.999)

    # A block literally touching the surface (as a floor does) must be skipped:
    # the walk starts in the cell above it.
    floor = empty.copy()
    floor[60:64, 60:64, 60:64] = 1.0
    check("a floor under the sampled point does not self-shadow",
          sun_vis(floor, P, up, up, steps) > 0.999)

    # Step budget: a caster beyond the step budget is missed. Documented, not a
    # bug: shadows only reach ~SUN_SHADOW_STEPS blocks at a low sun angle.
    far = empty.copy()
    far[64, 64 + 30, 64] = 1.0
    low = normalize([1.0, 0.02, 0.0])
    check("a distant caster at a low sun angle is beyond the step budget",
          sun_vis(far, P, up, low, steps) > 0.99,
          "raise SUN_SHADOW_STEPS for longer shadows")

    _, up_moon, _, _ = direct_light(np.array([0.0, -1.0, 0.0]), np.array([0.0, 1.0, 0.0]))
    check("moonlight still traces shadows", up_moon > 0.3, f"up={up_moon:.3f}")

    check("full sunlight on open ground removes the configured amount",
          abs(shadow_amount(1.0, 1.0, 1.0, 1.0, s["SUN_SHADOW_STRENGTH"]) - 0.0) < 1e-9
          and abs(shadow_amount(1.0, 1.0, 0.0, 1.0, s["SUN_SHADOW_STRENGTH"]) - s["SUN_SHADOW_STRENGTH"]) < 1e-9,
          f"{s['SUN_SHADOW_STRENGTH']:.2f} of the direct light")
    check("caves are untouched", shadow_amount(0.0, 1.0, 0.0, 1.0, s["SUN_SHADOW_STRENGTH"]) == 0.0)
    check("surfaces facing away from the sun are untouched",
          shadow_amount(1.0, 0.0, 0.0, 1.0, s["SUN_SHADOW_STRENGTH"]) == 0.0)
    check("shadow is weaker at night than at noon",
          shadow_amount(1.0, 1.0, 0.0, up_moon, s["SUN_SHADOW_STRENGTH"])
          < shadow_amount(1.0, 1.0, 0.0, 1.0, s["SUN_SHADOW_STRENGTH"]))


def test_specular() -> None:
    s = settings()
    opt = s["SUN_SPECULAR"]
    print("\nspecular")

    N = np.array([0.0, 1.0, 0.0])
    sunlight = np.array([1.0, 0.95, 0.86])

    # Perfect mirror configuration: V is the reflection of L about N, so H == N.
    L = normalize([0.0, 0.8, 0.6])
    V = 2.0 * float(np.dot(N, L)) * N - L
    peak_metal = specular(N, L, V, 1.0, 1.0, sunlight, 1.0, opt)
    peak_ice = specular(N, L, V, 1.0, 3.0, sunlight, 1.0, opt)
    peak_dirt = specular(N, L, V, 1.0, 0.0, sunlight, 1.0, opt)

    check("a metal returns a visible highlight", float(np.max(peak_metal)) > 0.2,
          f"peak={float(np.max(peak_metal)):.3f}")
    check("rough dirt returns almost nothing", float(np.max(peak_dirt)) < 0.01)
    check("smoother materials highlight more",
          float(np.max(peak_ice)) > float(np.max(peak_dirt)))
    check("highlights stay bounded", float(np.max(peak_metal)) < 4.0,
          f"peak={float(np.max(peak_metal)):.3f}")

    check("no highlight without direct light",
          float(np.max(specular(N, L, V, 1.0, 1.0, sunlight, 0.0, opt))) == 0.0)
    check("no highlight in shadow",
          float(np.max(specular(N, L, V, 0.0, 1.0, sunlight, 1.0, opt))) == 0.0)
    check("no highlight when the face looks away",
          float(np.max(specular(N, np.array([0.0, -1.0, 0.0]), V, 1.0, 1.0, sunlight, 1.0, opt))) == 0.0)
    check("SUN_SPECULAR = 0 disables the term",
          float(np.max(specular(N, L, V, 1.0, 1.0, sunlight, 1.0, 0.0))) == 0.0)

    # The lobe should fall off far from the mirror direction.
    away = specular(N, L, normalize([1.0, 0.2, 0.0]), 1.0, 1.0, sunlight, 1.0, opt)
    check("the highlight is local to the mirror direction",
          float(np.max(away)) < 0.5 * float(np.max(peak_metal)))

    # Finite everywhere (no NaNs from the GGX denominator).
    finite = True
    for r in np.linspace(0.0, 1.5, 7):
        v = normalize([math.sin(r), math.cos(r * 0.7), math.cos(r)])
        for cls in (0.0, 1.0, 2.0, 3.0, 4.0, 5.0):
            if not np.all(np.isfinite(specular(N, L, v, 1.0, cls, sunlight, 1.0, opt))):
                finite = False
    check("specular is finite for all angles and classes", finite)


def test_screen_space_shadows() -> None:
    s = settings()
    print("\nfine sun shadows (screen space)")

    # Camera at the origin looking down -Z; a surface two blocks ahead.
    surface = np.array([0.0, -1.0, -2.0])
    up_sun = normalize([0.0, 0.9, -0.3])

    low_sun = normalize([0.0, 0.34, -0.94])
    empty = lambda uv: None
    vis, cov = ss_sun_shadow(surface, low_sun, empty)
    check("an empty screen leaves the surface lit", vis > 0.99, f"vis={vis:.3f}")
    check("a ray that stays on screen is fully trusted", cov > 0.99, f"confidence={cov:.2f}")

    # A big flat wall at 4 blocks in front of the camera.
    wall = lambda uv: 4.0
    vis, cov = ss_sun_shadow(surface, low_sun, wall)
    check("a wall in the ray path shadows the surface", vis < 0.01, f"vis={vis:.3f}")

    # Sun behind the camera: the ray cannot be traced, confidence must fall to
    # 0 so that the voxel shadow is used instead.
    vis, cov = ss_sun_shadow(surface, normalize([0.0, 0.9, 0.4]), empty)
    check("a sun behind the camera is barely trusted", cov < 0.35, f"confidence={cov:.2f}")
    check("an untraceable ray never reports a false shadow", vis > 0.99)

    # Straight overhead: the ray leaves the top of the screen after ~3 blocks,
    # so the voxel shadow keeps the long-range shadows.
    vis, cov = ss_sun_shadow(surface, np.array([0.0, 1.0, 0.0]), empty)
    check("an overhead sun only gets partial confidence", 0.05 < cov < 0.85, f"confidence={cov:.2f}")

    # Thin geometry: a 0.19-block slab (a door is 3/16) that only exists in a
    # narrow window of the screen.
    def door(uv):
        return 2.4 if abs(uv[0] - 0.5) < 0.02 and uv[1] > 0.5 else None

    hit = False
    for i in range(40):
        ang = 0.6 + i * 0.02
        d = normalize([0.0, math.sin(ang), -math.cos(ang)])
        vis, cov = ss_sun_shadow(surface, d, door)
        if vis < 0.5:
            hit = True
            break
    check("thin geometry (a door panel) can cast a fine shadow", hit)

    # A surface the ray moves *towards* must not shadow itself.
    toward = normalize([0.0, -0.2, 0.9])
    vis, cov = ss_sun_shadow(surface, toward, wall)
    check("no self-shadowing when the ray points away from the wall", vis > 0.99, f"vis={vis:.3f}")

    check("SS_SHADOWS is exposed", "SS_SHADOWS" in s and "SS_SHADOW_STEPS" in s)


def test_ranking() -> None:
    c = consts()
    s = settings()
    print("\nlocal lights")

    K = int(s["MAX_LIGHTS_PER_PIXEL"])
    O = np.array([64.0, 64.5, 64.0])
    N = np.array([0.0, 1.0, 0.0])
    positions = [
        (64.0, 65.0, 64.0, 14.0),   # right above the point
        (66.0, 65.0, 64.0, 8.0),
        (70.0, 66.0, 64.0, 15.0),   # bright but far
        (64.0, 64.0, 69.0, 4.0),
        (80.0, 64.0, 64.0, 15.0),   # out of range
        (64.0, 64.0, 67.0, 12.0),
    ]
    scored = [(estimate(p[:3], p[3], O, N, c["ATT_K"], s["LIGHT_RANGE"]), i)
              for i, p in enumerate(positions)]
    order = rank(scored, K)

    check(f"at most {K} lights are kept", len(order) <= K, f"kept {len(order)}")
    check("the brightest nearby light wins", order[0] == 0, f"picked {order[0]}")
    check("out-of-range lights are not chosen", 4 not in order)
    kept = [scored[i][0] for i in order]
    check("kept lights are sorted by score", all(kept[i] >= kept[i + 1] for i in range(len(kept) - 1)))

    far = [(estimate((100.0, 64.0, 100.0), 15.0, O, N, c["ATT_K"], s["LIGHT_RANGE"]), 9)]
    check("a light outside its range scores zero", far[0][0] == 0.0)
    check("an empty candidate list keeps nothing", rank([], K) == [])


def test_light_falloff() -> None:
    c = consts()
    s = settings()
    print("\nlocal light falloff")

    R = min(15.0 * s["LIGHT_RANGE"], 24.0)
    near = light_att(1.0, R, c["ATT_K"])
    mid = light_att(4.0, R, c["ATT_K"])
    edge = light_att(R * R * 0.999, R, c["ATT_K"])
    outside = light_att(R * R * 1.01, R, c["ATT_K"])
    check("brightness falls with distance", near > mid > edge)
    check("no light beyond the range", outside == 0.0)
    check("the range is capped", R <= 24.0, f"R={R:.1f}")
    check("a level-15 light reaches at least 12 blocks", R >= 12.0)


def main() -> int:
    print("Hearthlight shader behaviour tests")
    test_layout()
    test_ids()
    test_sun_geometry()
    test_sun_shadows()
    test_specular()
    test_screen_space_shadows()
    test_ranking()
    test_light_falloff()

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
