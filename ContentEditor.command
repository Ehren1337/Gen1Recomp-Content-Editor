#!/bin/sh
set -eu

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
LOVE="$HERE/love/love.app/Contents/MacOS/love"

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

if [ ! -f "$HERE/main.lua" ]; then
  echo "main.lua is missing from $HERE" >&2
  echo "Run ContentEditor.command from the extracted pack folder." >&2
  echo "Do not open love.app directly — that yields 'No code to run'." >&2
  exit 1
fi

exec "$LOVE" "$HERE" --content-editor "$@"
