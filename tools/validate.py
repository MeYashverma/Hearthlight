#!/usr/bin/env python3
"""Offline validation for the Hearthlight shader pack.

Iris resolves `#include` directives before compiling, but glslang does not (its
`-I` include support only works together with the Vulkan/HLSL paths). This
script expands the pack's includes into single translation units and then runs
glslang on every program wrapper in `shaders/world*`.

Usage:
    python3 tools/validate.py [--glslang PATH] [--keep]
"""

from __future__ import annotations

import argparse
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from iris_defines import RESERVED, as_prelude

INCLUDE_RE = re.compile(r'^\s*#\s*include\s+"([^"]+)"\s*$')

STAGE_BY_SUFFIX = {
    ".vsh": "vert",
    ".fsh": "frag",
    ".csh": "comp",
    ".gsh": "geom",
    ".tcs": "tesc",
    ".tes": "tese",
}


def expand(path: Path, root: Path, seen: tuple[Path, ...] = ()) -> str:
    if path in seen:
        chain = " -> ".join(p.name for p in (*seen, path))
        raise RuntimeError(f"recursive include: {chain}")
    if not path.is_file():
        raise FileNotFoundError(path)

    out: list[str] = []
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        match = INCLUDE_RE.match(line)
        if not match:
            out.append(line)
            continue

        target = match.group(1)
        resolved = root / target.lstrip("/") if target.startswith("/") else path.parent / target
        out.append(f"// ---- {target} ----")
        out.append(expand(resolved, root, (*seen, path)))

    return "\n".join(out)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--glslang", default="glslangValidator")
    parser.add_argument("--keep", action="store_true", help="keep the expanded sources")
    args = parser.parse_args()

    repo = Path(__file__).resolve().parent.parent
    shaders = repo / "shaders"
    wrappers = sorted(
        p for p in shaders.glob("*") if p.suffix in STAGE_BY_SUFFIX
    )

    if not wrappers:
        print("no program wrappers found", file=sys.stderr)
        return 1

    workdir = Path(tempfile.mkdtemp(prefix="hearthlight-validate-"))
    failures = 0
    compiled: dict[tuple[str, str], Path] = {}

    try:
        for wrapper in wrappers:
            stage = STAGE_BY_SUFFIX[wrapper.suffix]
            expanded = expand(wrapper, shaders)
            # Iris defines MC_RENDER_STAGE_* (and friends) in every program, so a
            # pack that redeclares one of those names gets rewritten into
            # nonsense before any parser sees it. Injecting the same defines is
            # what makes this step able to catch that bug. They must follow the
            # #version line.
            prelude = as_prelude()
            first, newline, rest = expanded.partition("\n")
            if first.lstrip().startswith("#version"):
                expanded = first + newline + prelude + rest
            else:
                expanded = prelude + expanded
            # glslang picks the stage from the extension, which also lets the
            # linker below infer stages without an explicit -S.
            target = workdir / f"{wrapper.parent.name}__{wrapper.stem}.{stage}"
            target.write_text(expanded, encoding="utf-8")
            compiled[(wrapper.parent.name, wrapper.stem)] = target

            result = subprocess.run(
                [args.glslang, str(target)],
                capture_output=True,
                text=True,
            )
            status = "ok" if result.returncode == 0 else "FAILED"
            print(f"{status:>6}  compile  {wrapper.relative_to(repo)}")
            if result.returncode != 0:
                failures += 1
                print(result.stdout, end="")
                print(result.stderr, end="")

        # Linking the vertex and fragment stages catches everything a per-stage
        # compile cannot: mismatched varyings, missing outputs, flat qualifier
        # mismatches. Iris links the pair at load time, so a pack that fails
        # here would fail in game.
        for (folder, name), vert in sorted(compiled.items()):
            if vert.suffix != ".vert":
                continue
            frag = compiled.get((folder, name + ""))
            frag = workdir / f"{folder}__{name}.frag"
            if not frag.exists():
                continue
            result = subprocess.run(
                [args.glslang, "-l", str(vert), str(frag)],
                capture_output=True,
                text=True,
            )
            status = "ok" if result.returncode == 0 else "FAILED"
            print(f"{status:>6}  link     shaders/{folder}/{name}")
            if result.returncode != 0:
                failures += 1
                print(result.stdout, end="")
                print(result.stderr, end="")
    finally:
        if args.keep:
            print(f"expanded sources kept in {workdir}")
        else:
            shutil.rmtree(workdir, ignore_errors=True)

    # Fast, dependency-free lint for the collision above: a name Iris defines
    # that the pack also declares.
    declared = set()
    for path in shaders.rglob("*"):
        if path.suffix not in {".glsl", ".vsh", ".fsh", ".csh", ".gsh"}:
            continue
        declared |= set(
            re.findall(
                r"^\s*(?:const\s+\w+|#define)\s+(\w+)",
                path.read_text(encoding="utf-8"),
                re.MULTILINE,
            )
        )
    clashes = sorted(declared & RESERVED)
    if clashes:
        failures += 1
        print(f"\nreserved identifiers declared by the pack: {', '.join(clashes)}")

    total = len(wrappers)
    passed = max(0, total - failures)
    print(f"\n{passed}/{total} shader stages and links ok")
    if clashes:
        print("(stage failures above are inflated by the collision; fix it first)")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
