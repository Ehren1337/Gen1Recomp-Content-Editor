@echo off
title Gen1Recomp Content Editor
cd /d "%~dp0"
if not exist "love\love.exe" (
  echo Missing love\love.exe ??? re-unzip the full pack.
  pause
  exit /b 1
)
start "" "love\love.exe" . --content-editor %*
