@echo off
title Gen1Recomp Content Editor
cd /d "%~dp0"
set "EDITOR_SOURCE=%CD%"
if not exist "main.lua" (
  powershell -NoProfile -ExecutionPolicy Bypass -File "scripts\prepare_content_editor.ps1"
  if errorlevel 1 (
    pause
    exit /b 1
  )
  set "EDITOR_SOURCE=%CD%\.content-editor-runtime"
  set "POKEPORT_CONTENT_ROOT=%CD%"
)
if not exist "love\love.exe" (
  echo Missing love\love.exe ??? re-unzip the full pack.
  pause
  exit /b 1
)
start "" "love\love.exe" "%EDITOR_SOURCE%" --content-editor %*
