#!/bin/sh
set -eu

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
LOVE="$HERE/love/love.app/Contents/MacOS/love"
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
if [ -f "$LOVE" ]; then
  chmod +x "$LOVE" 2>/dev/null || true
fi

if [ ! -x "$LOVE" ]; then
  echo "The bundled LÖVE runtime is missing or not executable: $LOVE" >&2
  echo "Run: chmod +x \"$LOVE\" \"$0\"" >&2
  exit 1
fi

if [ ! -f "$EDITOR_SOURCE/main.lua" ]; then
  echo "main.lua is missing from $EDITOR_SOURCE" >&2
  echo "Run ContentEditor.command from the extracted pack folder." >&2
  echo "Do not open love.app directly — that yields 'No code to run'." >&2
  exit 1
fi

exec "$LOVE" "$EDITOR_SOURCE" --content-editor "$@"
