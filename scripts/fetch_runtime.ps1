# Fills an empty runtime\gen1recomp (git clone without submodules, or GitHub
# "Download ZIP") with the pinned Gen1Recomp commit.
$ErrorActionPreference = "Stop"
$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$Runtime = Join-Path $Root "runtime\gen1recomp"
$Marker = Join-Path $Runtime "src\core\GameVersion.lua"
if (Test-Path -LiteralPath $Marker) { exit 0 }

if ((Test-Path -LiteralPath $Runtime) -and (Get-ChildItem -LiteralPath $Runtime -Force | Select-Object -First 1)) {
  throw "runtime\gen1recomp is incomplete but not empty. Delete it and start again."
}

Write-Host "Downloading the Gen1Recomp runtime (first run only)..."
if ((Test-Path -LiteralPath (Join-Path $Root ".git")) -and (Get-Command git -ErrorAction SilentlyContinue)) {
  & git -C $Root submodule update --init --recursive
  if ($LASTEXITCODE -ne 0) { throw "git submodule update failed." }
} else {
  $pin = Get-Content -LiteralPath (Join-Path $Root ".github\runtime-upstream.json") -Raw | ConvertFrom-Json
  $download = Join-Path $Root "runtime\.download"
  $zip = Join-Path $download "gen1recomp.zip"
  if (Test-Path -LiteralPath $download) { Remove-Item -LiteralPath $download -Recurse -Force }
  New-Item -ItemType Directory -Force -Path $download | Out-Null
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  $ProgressPreference = "SilentlyContinue"
  Invoke-WebRequest -UseBasicParsing -OutFile $zip `
    "https://codeload.github.com/$($pin.repository)/zip/$($pin.integratedCommit)"
  Expand-Archive -LiteralPath $zip -DestinationPath $download
  $extracted = Get-ChildItem -LiteralPath $download -Directory | Select-Object -First 1
  if (Test-Path -LiteralPath $Runtime) { Remove-Item -LiteralPath $Runtime -Force }
  Move-Item -LiteralPath $extracted.FullName -Destination $Runtime
  Remove-Item -LiteralPath $download -Recurse -Force
}

if (-not (Test-Path -LiteralPath $Marker)) { throw "Downloaded runtime is missing src\core\GameVersion.lua." }
Write-Host "Gen1Recomp runtime ready."
