param([switch]$Check)

$ErrorActionPreference = "Stop"
$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$Runtime = Join-Path $Root "runtime\gen1recomp"
$Stage = Join-Path $Root ".content-editor-runtime"
$SignatureFile = Join-Path $Stage ".source-signature"

function Get-SourceSignature {
  $inputs = @()
  foreach ($relative in @("tools\content-editor", "tools\save-editor",
      "libs\flexlove")) {
    $base = Join-Path $Root $relative
    if (Test-Path -LiteralPath $base) {
      Get-ChildItem -LiteralPath $base -Recurse -File | Sort-Object FullName |
        ForEach-Object {
          $rel = $_.FullName.Substring($Root.Length).Replace('\', '/')
          $inputs += "$rel=$((Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName).Hash)"
        }
    }
  }
  foreach ($relative in @("tools\modkit.py", "tools\rom_manifest.json",
      "tools\rom_manifest_blue.json", "tools\rom_manifest_yellow.json",
      "tools\rom_manifest_gold.json", "tests\love_stub.lua")) {
    $path = Join-Path $Root $relative
    if (Test-Path -LiteralPath $path) {
      $inputs += "$relative=$((Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash)"
    }
  }
  $pin = (& git -C $Runtime rev-parse HEAD 2>$null)
  if ($LASTEXITCODE -ne 0 -or -not $pin) {
    $pin = (Get-Item -LiteralPath (Join-Path $Runtime "main.lua")).LastWriteTimeUtc.Ticks
  }
  $inputs += "runtime=$pin"
  $bytes = [Text.Encoding]::UTF8.GetBytes(($inputs -join "`n"))
  $sha = [Security.Cryptography.SHA256]::Create()
  try {
    return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace("-", "")
  }
  finally { $sha.Dispose() }
}

$SourceSignature = Get-SourceSignature
if ($Check) {
  if (-not (Test-Path -LiteralPath $SignatureFile)) { exit 1 }
  $staged = (Get-Content -LiteralPath $SignatureFile -Raw).Trim()
  if ($staged -ceq $SourceSignature) { exit 0 }
  exit 1
}

if (-not (Test-Path (Join-Path $Runtime "main.lua"))) {
  throw "Pinned runtime is missing. Run: git submodule update --init --recursive"
}
$expectedStage = [IO.Path]::GetFullPath((Join-Path $Root ".content-editor-runtime"))
if ([IO.Path]::GetFullPath($Stage) -ne $expectedStage -or
    -not $expectedStage.StartsWith($Root + [IO.Path]::DirectorySeparatorChar)) {
  throw "Refusing to replace unexpected staging path: $Stage"
}
if (Test-Path -LiteralPath $Stage) {
  Remove-Item -LiteralPath $Stage -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $Stage | Out-Null

function Copy-Filtered(
  [string]$From,
  [string]$To,
  [string[]]$Excluded = @(),
  [string[]]$RootExcluded = @(),
  [int]$Depth = 0
) {
  if (-not (Test-Path -LiteralPath $From)) { return }
  New-Item -ItemType Directory -Force -Path $To | Out-Null
  Get-ChildItem -LiteralPath $From -Force | ForEach-Object {
    if ($Excluded -contains $_.Name) { return }
    if ($Depth -eq 0 -and $RootExcluded -contains $_.Name) { return }
    $destination = Join-Path $To $_.Name
    if ($_.PSIsContainer) {
      Copy-Filtered $_.FullName $destination $Excluded $RootExcluded ($Depth + 1)
    } elseif (-not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
      Copy-Item -LiteralPath $_.FullName -Destination $destination -Force
    }
  }
}

$nestedRuntime = Join-Path $Stage "runtime\gen1recomp"
Copy-Filtered $Runtime $nestedRuntime @(
  ".git", ".github", "dist", "generated",
  "node_modules", "__pycache__"
) @("mods")
New-Item -ItemType Directory -Force -Path (Join-Path $nestedRuntime "mods") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $Stage "mods") | Out-Null

Copy-Filtered (Join-Path $Root "tools\content-editor") `
  (Join-Path $Stage "tools\content-editor") @("__pycache__")
Copy-Filtered (Join-Path $Root "tools\save-editor") `
  (Join-Path $Stage "tools\save-editor") @("__pycache__")
Copy-Filtered (Join-Path $Root "libs\flexlove") `
  (Join-Path $Stage "libs\flexlove")
Copy-Filtered (Join-Path $Root "tests\fixture_data") `
  (Join-Path $Stage "tests\fixture_data")

foreach ($file in @("modkit.py", "rom_manifest.json", "rom_manifest_blue.json",
    "rom_manifest_yellow.json", "rom_manifest_gold.json")) {
  Copy-Item -LiteralPath (Join-Path $Root "tools\$file") `
    -Destination (Join-Path $Stage "tools\$file") -Force
}
Copy-Item -LiteralPath (Join-Path $Root "tests\love_stub.lua") `
  -Destination (Join-Path $Stage "tests\love_stub.lua") -Force
Copy-Item -LiteralPath (Join-Path $Root "tools\content-editor\runtime\main.lua") `
  -Destination (Join-Path $Stage "main.lua") -Force
Copy-Item -LiteralPath (Join-Path $Root "tools\content-editor\runtime\conf.lua") `
  -Destination (Join-Path $Stage "conf.lua") -Force

Set-Content -LiteralPath $SignatureFile -Value $SourceSignature -NoNewline

Write-Output $Stage
