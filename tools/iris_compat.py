#!/usr/bin/env python3
"""Reproduce Iris' preprocessing, then compile, to catch macro collisions.

The bug this exists for: Iris injects `#define MC_RENDER_STAGE_NONE 0` (and one
per render phase) into *every* program. A pack that declares its own
`const int MC_RENDER_STAGE_NONE = 0;` therefore hands Iris' parser the text
`const int 0 = 0;`, and the pack fails to load with

    ParseCancellationException: line 91:10 no viable alternative at input
    'const int 0'

`tools/validate.py` cannot see that, because it does not inject Iris' macros.
This script does: it mirrors the defines from Iris' StandardMacros.java, runs a
real C preprocessor (pcpp, the same job JCPP does inside Iris), and compiles the
result with glslang. Anything glslang rejects after Iris' defines are applied
would also be rejected (or worse) by Iris.

    python3 tools/iris_compat.py [--glslang PATH] [--verbose]

Needs pcpp: pip install pcpp
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

try:
    from pcpp import Preprocessor
except ImportError:  # pragma: no cover
    sys.exit("pcpp is required: pip install pcpp")

from iris_defines import RESERVED, STANDARD_DEFINES

STAGE_BY_SUFFIX = {".vsh": "vert", ".fsh": "frag", ".csh": "comp", ".gsh": "geom"}


def stage_tree(shaders: Path, destination: Path) -> Path:
    """Copy the pack, rewriting Iris' absolute includes to relative ones.

    Iris resolves `#include "/program/x.vsh"` against the pack root; a plain C
    preprocessor treats the leading slash as a filesystem path. Mirroring the
    tree with the slash stripped keeps the include graph identical.
    """
    for source in shaders.rglob("*"):
        if not source.is_file():
            continue
        relative = source.relative_to(shaders)
        target = destination / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        text = source.read_text(encoding="utf-8")
        text = re.sub(r'(#\s*include\s+)"/([^"]+)"', r'\1"\2"', text)
        target.write_text(text, encoding="utf-8")
    return destination


def preprocess(wrapper: Path, shaders: Path, keep_paths: bool) -> str:
    """Run the C preprocessor with Iris' defines, like JCPP does."""
    preprocessor = Preprocessor()
    preprocessor.add_path(str(shaders))
    preprocessor.line_directive = "#line"
    for name, value in STANDARD_DEFINES.items():
        preprocessor.define(f"{name} {value}" if value is not None else name)

    # pcpp treats a plain string as source text, so pass the contents and name
    # the file separately; the name is what #include resolution searches from.
    preprocessor.parse(wrapper.read_text(encoding="utf-8"), source=str(wrapper))

    import io

    buffer = io.StringIO()
    preprocessor.write(buffer)
    text = buffer.getvalue()
    if not keep_paths:
        text = re.sub(r'^\s*#line .*$', "", text, flags=re.MULTILINE)
    return text


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--glslang", default="glslangValidator")
    parser.add_argument("--verbose", action="store_true")
    args = parser.parse_args()

    repo = Path(__file__).resolve().parent.parent
    shaders = repo / "shaders"
    wrappers = sorted(p for p in shaders.glob("world*/*") if p.suffix in STAGE_BY_SUFFIX)
    if not wrappers:
        print("no program wrappers found", file=sys.stderr)
        return 1

    workdir = Path(tempfile.mkdtemp(prefix="hearthlight-iris-"))
    mirror = stage_tree(shaders, workdir / "tree")
    failures = 0

    try:
        for wrapper in wrappers:
            stage = STAGE_BY_SUFFIX[wrapper.suffix]
            mirrored = mirror / wrapper.relative_to(shaders)
            source = preprocess(mirrored, mirror, keep_paths=False)
            target = workdir / f"{wrapper.parent.name}__{wrapper.stem}.{stage}"
            target.write_text(source, encoding="utf-8")

            result = subprocess.run([args.glslang, str(target)], capture_output=True, text=True)
            ok = result.returncode == 0
            print(f"{'ok  ' if ok else 'FAIL'}  {wrapper.relative_to(repo)}")
            if not ok:
                failures += 1
                print(result.stdout, end="")
                print(result.stderr, end="")
                # Point at the offending line in the preprocessed source, which
                # is what Iris' parser would see.
                for line in (result.stdout + result.stderr).splitlines():
                    match = re.search(r"ERROR: \d+:(\d+)", line)
                    if match:
                        number = int(match.group(1))
                        text = source.splitlines()
                        if 1 <= number <= len(text):
                            print(f"      preprocessed line {number}: {text[number - 1]!r}")
                        break
            elif args.verbose:
                print(f"      {len(source.splitlines())} lines after preprocessing")

        # If the pack declares any name Iris already defines, say so directly:
        # that is the failure mode this script exists for, and the compiler
        # message for it is cryptic.
        declared = set()
        for path in shaders.rglob("*"):
            if path.suffix not in {".glsl", ".vsh", ".fsh", ".csh", ".gsh"}:
                continue
            text = path.read_text(encoding="utf-8")
            declared |= set(re.findall(r"^\s*(?:const\s+\w+|#define)\s+(\w+)", text, re.MULTILINE))
        clashes = sorted(declared & RESERVED)
        print()
        if clashes:
            print(f"reserved identifiers declared by the pack: {', '.join(clashes)}")
            failures += len(clashes)
        else:
            print("no pack identifier collides with an Iris define")
    finally:
        shutil.rmtree(workdir, ignore_errors=True)

    total = len(wrappers)
    print(f"{total - failures if failures <= total else 0}/{total} programs survive Iris' defines")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
