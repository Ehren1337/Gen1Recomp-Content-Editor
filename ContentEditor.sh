#!/usr/bin/env bash
# Gen1Recomp Content Editor - Linux launcher
set -euo pipefail
cd "$(dirname "$(readlink -f "$0" 2>/dev/null || realpath "$0" 2>/dev/null || echo "$0")")"
ROOT="$PWD"
if [[ -f "$ROOT/love/portable.txt" ]]; then
  export POKEPORT_IDENTITY="gen1recomp-content-editor-portable"
fi
EDITOR_SOURCE="$ROOT"
if [[ ! -f "$ROOT/main.lua" ]]; then
  if [[ ! -f "$ROOT/.content-editor-runtime/runtime/gen1recomp/src/mods/Runtime.lua" ||
        ! -f "$ROOT/.content-editor-runtime/runtime/gen1recomp/src/core/Input.lua" ]] ||
     ! cmp -s "$ROOT/tools/content-editor/RuntimeMount.lua" \
       "$ROOT/.content-editor-runtime/tools/content-editor/RuntimeMount.lua" ||
     ! cmp -s "$ROOT/tools/save-editor/Kit.lua" \
       "$ROOT/.content-editor-runtime/tools/save-editor/Kit.lua"; then
    chmod +x "$ROOT/scripts/prepare_content_editor.sh" 2>/dev/null || true
    "$ROOT/scripts/prepare_content_editor.sh" >/dev/null
  fi
  EDITOR_SOURCE="$ROOT/.content-editor-runtime"
  export POKEPORT_CONTENT_ROOT="$ROOT"
fi

# Packs built on Windows often extract without +x. Fix before -x checks.
chmod +x "$0" 2>/dev/null || true
if [[ -f "love/love-11.5-x86_64.AppImage" ]]; then
  chmod +x "love/love-11.5-x86_64.AppImage" 2>/dev/null || true
fi

LOVE=""
if [[ -x "love/love-11.5-x86_64.AppImage" ]]; then
  LOVE="./love/love-11.5-x86_64.AppImage"
elif [[ -x "love/love" ]]; then
  LOVE="./love/love"
elif command -v love >/dev/null 2>&1; then
  LOVE="love"
fi

if [[ -z "$LOVE" ]]; then
  echo "LÖVE 11.5 not found."
  echo "Install love 11.5, or from this folder run:  love . --content-editor"
  if [[ -f "love/love-11.5-x86_64.AppImage" ]]; then
    echo "Bundled AppImage is present but not executable:"
    echo "  chmod +x ContentEditor.sh love/love-11.5-x86_64.AppImage"
  fi
  exit 1
fi

if [[ ! -f "$EDITOR_SOURCE/main.lua" ]]; then
  echo "main.lua is missing from $EDITOR_SOURCE" >&2
  exit 1
fi

exec "$LOVE" "$EDITOR_SOURCE" --content-editor "$@"
