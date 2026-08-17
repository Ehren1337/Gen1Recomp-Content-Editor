@echo off
title Gen1Recomp Content Editor
cd /d "%~dp0"
if exist "love\portable.txt" set "POKEPORT_IDENTITY=gen1recomp-content-editor-portable"
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

set "LOVE_EXE="
if exist "%CD%\love\love.exe" set "LOVE_EXE=%CD%\love\love.exe"
if not defined LOVE_EXE if exist "%CD%\love\love-11.5-win64\love.exe" set "LOVE_EXE=%CD%\love\love-11.5-win64\love.exe"
if not defined LOVE_EXE if exist "%ProgramFiles%\LOVE\love.exe" set "LOVE_EXE=%ProgramFiles%\LOVE\love.exe"
if not defined LOVE_EXE if exist "%ProgramFiles(x86)%\LOVE\love.exe" set "LOVE_EXE=%ProgramFiles(x86)%\LOVE\love.exe"
if not defined LOVE_EXE (
  for /f "delims=" %%I in ('where love 2^>nul') do (
    set "LOVE_EXE=%%I"
    goto :haveLove
  )
)
:haveLove

if not defined LOVE_EXE (
  echo LÖVE 11.5 not found.
  echo Install LÖVE, or from this folder run:  love . --content-editor
  pause
  exit /b 1
)
if not exist "%EDITOR_SOURCE%\main.lua" (
  echo main.lua is missing from %EDITOR_SOURCE%
  pause
  exit /b 1
)

REM /D keeps cwd on the game folder. start otherwise resets cwd to love.exe's
REM directory, so "." becomes love\ (No code to run).
start "" /D "%EDITOR_SOURCE%" "%LOVE_EXE%" "%EDITOR_SOURCE%" --content-editor %*
