#!/usr/bin/env bash
# Gen1Recomp Content Editor - Linux launcher
set -euo pipefail
cd "$(dirname "$(readlink -f "$0" 2>/dev/null || realpath "$0" 2>/dev/null || echo "$0")")"

# Packs built on Windows often extract without +x. Fix before -x checks.
chmod +x "$0" 2>/dev/null || true
if [[ -f "love/love-11.5-x86_64.AppImage" ]]; then
  chmod +x "love/love-11.5-x86_64.AppImage" 2>/dev/null || true
fi

LOVE=""
if [[ -x "love/love-11.5-x86_64.AppImage" ]]; then
  LOVE="./love/love-11.5-x86_64.AppImage"
elif [[ -f "love/love-11.5-x86_64.AppImage" ]]; then
  echo "The bundled LOVE AppImage is not executable."
  echo "Run: chmod 755 ContentEditor.sh love/love-11.5-x86_64.AppImage"
  echo "If the launcher itself is not executable, start it once with: bash ContentEditor.sh"
  exit 1
elif [[ -x "love/love" ]]; then
  LOVE="./love/love"
elif command -v love >/dev/null 2>&1; then
  LOVE="love"
else
  echo "Missing LOVE runtime."
  echo "Expected love/love-11.5-x86_64.AppImage, or install love 11.5."
  echo "If the AppImage is present: chmod +x ContentEditor.sh love/love-11.5-x86_64.AppImage"
  exit 1
fi

exec "$LOVE" . --content-editor "$@"
