#!/usr/bin/env bash
# Gen1Recomp Content Editor - Linux launcher
set -euo pipefail
cd "$(dirname "$(readlink -f "$0" 2>/dev/null || realpath "$0" 2>/dev/null || echo "$0")")"

LOVE=""
if [[ -x "love/love-11.5-x86_64.AppImage" ]]; then
  LOVE="./love/love-11.5-x86_64.AppImage"
elif [[ -x "love/love" ]]; then
  LOVE="./love/love"
elif command -v love >/dev/null 2>&1; then
  LOVE="love"
else
  echo "Missing LOVE runtime."
  echo "Expected love/love-11.5-x86_64.AppImage (chmod +x), or install love 11.5."
  exit 1
fi

exec "$LOVE" . --content-editor "$@"
