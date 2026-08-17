#!/bin/sh
set -eu

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
if [ -f "$HERE/love/portable.txt" ]; then
  export POKEPORT_IDENTITY="gen1recomp-content-editor-portable"
fi
EDITOR_SOURCE="$HERE"
if [ ! -f "$HERE/main.lua" ]; then
  if [ ! -f "$HERE/.content-editor-runtime/runtime/gen1recomp/src/mods/Runtime.lua" ] ||
     [ ! -f "$HERE/.content-editor-runtime/runtime/gen1recomp/src/core/Input.lua" ] ||
     ! cmp -s "$HERE/tools/content-editor/RuntimeMount.lua" \
       "$HERE/.content-editor-runtime/tools/content-editor/RuntimeMount.lua" ||
     ! cmp -s "$HERE/tools/save-editor/Kit.lua" \
       "$HERE/.content-editor-runtime/tools/save-editor/Kit.lua"; then
    chmod +x "$HERE/scripts/prepare_content_editor.sh" 2>/dev/null || true
    "$HERE/scripts/prepare_content_editor.sh" >/dev/null
  fi
  EDITOR_SOURCE="$HERE/.content-editor-runtime"
  export POKEPORT_CONTENT_ROOT="$HERE"
fi

# Packs built on Windows often extract without +x.
chmod +x "$0" 2>/dev/null || true
BUNDLED="$HERE/love/love.app/Contents/MacOS/love"
if [ -f "$BUNDLED" ]; then
  chmod +x "$BUNDLED" 2>/dev/null || true
fi

LOVE=""
if [ -x "$BUNDLED" ]; then
  LOVE="$BUNDLED"
elif [ -x "/Applications/love.app/Contents/MacOS/love" ]; then
  LOVE="/Applications/love.app/Contents/MacOS/love"
elif command -v love >/dev/null 2>&1; then
  LOVE=$(command -v love)
fi

if [ -z "$LOVE" ]; then
  echo "LÖVE 11.5 not found." >&2
  echo "Install LÖVE, or from this folder run:  love . --content-editor" >&2
  exit 1
fi

if [ ! -f "$EDITOR_SOURCE/main.lua" ]; then
  echo "main.lua is missing from $EDITOR_SOURCE" >&2
  echo "Run ContentEditor.command from the extracted pack or source folder." >&2
  echo "Do not open love.app directly — that yields 'No code to run'." >&2
  exit 1
fi

exec "$LOVE" "$EDITOR_SOURCE" --content-editor "$@"
