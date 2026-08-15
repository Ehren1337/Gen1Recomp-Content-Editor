param()

$ErrorActionPreference = "Stop"
$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$Runtime = Join-Path $Root "runtime\gen1recomp"
$Stage = Join-Path $Root ".content-editor-runtime"

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

Write-Output $Stage
