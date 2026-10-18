#!/bin/sh
# Build the distributable shader pack.
#
# The zip has to contain the shaders/ folder at its root, plus the licence and
# readme, so that it can be dropped straight into .minecraft/shaderpacks/.
set -eu

cd "$(dirname "$0")/.."

out=Hearthlight.zip
rm -f "$out"

# -X keeps the zip deterministic (no extra file attributes).
zip -r -X "$out" shaders README.md LICENSE -x '*.DS_Store' >/dev/null

echo "wrote $(pwd)/$out"
unzip -l "$out" | tail -n 3
