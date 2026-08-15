@echo off
title Gen1Recomp Content Editor
cd /d "%~dp0"
set "EDITOR_SOURCE=%CD%"
set "NEED_PREP="
if not exist "main.lua" (
  set "NEED_PREP=1"
  if exist ".content-editor-runtime\runtime\gen1recomp\src\mods\Runtime.lua" if exist ".content-editor-runtime\runtime\gen1recomp\src\core\Input.lua" set "NEED_PREP="
  if not defined NEED_PREP powershell -NoProfile -ExecutionPolicy Bypass -File "scripts\prepare_content_editor.ps1" -Check >nul 2>nul || set "NEED_PREP=1"
)
if defined NEED_PREP (
  powershell -NoProfile -ExecutionPolicy Bypass -File "scripts\prepare_content_editor.ps1"
  if errorlevel 1 (
    pause
    exit /b 1
  )
  set "EDITOR_SOURCE=%CD%\.content-editor-runtime"
  set "POKEPORT_CONTENT_ROOT=%CD%"
)
if not exist "main.lua" (
  set "EDITOR_SOURCE=%CD%\.content-editor-runtime"
  set "POKEPORT_CONTENT_ROOT=%CD%"
)
if not exist "love\love.exe" (
  echo Missing love\love.exe ??? re-unzip the full pack.
  pause
  exit /b 1
)
start "" "love\love.exe" "%EDITOR_SOURCE%" --content-editor %*
