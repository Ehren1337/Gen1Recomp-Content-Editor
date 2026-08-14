#!/bin/sh
set -eu

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
LOVE="$HERE/love/love.app/Contents/MacOS/love"

if [ ! -x "$LOVE" ]; then
  echo "The bundled LÖVE runtime is missing or not executable: $LOVE" >&2
  echo "Run: chmod +x \"$LOVE\" \"$0\"" >&2
  exit 1
fi

exec "$LOVE" "$HERE" --content-editor "$@"

