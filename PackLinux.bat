@echo off
title Pack Content Editor (Linux)
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\pack_content_editor.ps1" -Platform linux
if errorlevel 1 (
  echo.
  echo Pack failed.
  pause
  exit /b 1
)
echo.
echo Output: dist\linux\gen1recomp-content-editor-linux64.tar.gz
pause
