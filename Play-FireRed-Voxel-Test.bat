@echo off
setlocal
cd /d "%~dp0"
set "HGSS_PROJECT=%CD%"
set "HGSS_RUNTIME=%USERPROFILE%\Downloads\gen1recomp-dev\gen1recomp-dev"
if not "%~1"=="" set "HGSS_RUNTIME=%~1"
if not exist "%HGSS_RUNTIME%\src\core\game3\field_view.lua" (
  echo Native FireRed runtime not found. Pass its folder as the first argument.
  pause
  exit /b 1
)
set "POKEPORT_VERSION=firered"
set "POKEPORT_DRIVER=%CD%\tests\content-editor\hgss-playtest\interactive.lua"
"%CD%\love\love.exe" "%CD%\tests\content-editor\hgss-playtest"
endlocal
