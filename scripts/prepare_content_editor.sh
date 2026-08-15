#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
RUNTIME="$ROOT/runtime/gen1recomp"
STAGE="$ROOT/.content-editor-runtime"

if [ ! -f "$RUNTIME/main.lua" ]; then
  echo "Pinned runtime is missing. Run: git submodule update --init --recursive" >&2
  exit 1
fi
case "$STAGE" in
  "$ROOT/.content-editor-runtime") ;;
  *) echo "Refusing to replace unexpected staging path: $STAGE" >&2; exit 1 ;;
esac

rm -rf -- "$STAGE"
mkdir -p "$STAGE"
git -C "$RUNTIME" archive HEAD -- . ':(exclude)mods' | tar -x -C "$STAGE"
for patch in "$ROOT"/runtime/patches/*.patch; do
  [ -f "$patch" ] || continue
  git -C "$ROOT" apply --check --directory=.content-editor-runtime "$patch"
  git -C "$ROOT" apply --directory=.content-editor-runtime "$patch"
done
mkdir -p "$STAGE/mods" "$STAGE/tools" "$STAGE/libs" "$STAGE/tests"
mkdir -p "$STAGE/runtime/gen1recomp"
git -C "$RUNTIME" archive HEAD -- . ':(exclude)mods' \
  | tar -x -C "$STAGE/runtime/gen1recomp"
mkdir -p "$STAGE/runtime/gen1recomp/mods"
for patch in "$ROOT"/runtime/patches/*.patch; do
  [ -f "$patch" ] || continue
  git -C "$ROOT" apply --check \
    --directory=.content-editor-runtime/runtime/gen1recomp "$patch"
  git -C "$ROOT" apply \
    --directory=.content-editor-runtime/runtime/gen1recomp "$patch"
done

cp -R "$ROOT/tools/content-editor" "$STAGE/tools/content-editor"
cp -R "$ROOT/tools/save-editor" "$STAGE/tools/save-editor"
cp -R "$ROOT/libs/flexlove" "$STAGE/libs/flexlove"
cp -R "$ROOT/tests/fixture_data" "$STAGE/tests/fixture_data"
cp "$ROOT/tests/love_stub.lua" "$STAGE/tests/love_stub.lua"
for file in modkit.py rom_manifest.json rom_manifest_blue.json \
  rom_manifest_yellow.json rom_manifest_gold.json; do
  cp "$ROOT/tools/$file" "$STAGE/tools/$file"
done
cp "$ROOT/tools/content-editor/runtime/main.lua" "$STAGE/main.lua"
cp "$ROOT/tools/content-editor/runtime/conf.lua" "$STAGE/conf.lua"
printf '%s\n' "$STAGE"
