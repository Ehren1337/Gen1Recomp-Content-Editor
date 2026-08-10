# Build a shareable Content Editor pack with no ROM-derived cache.
#
#   .\scripts\pack_content_editor.ps1 [-Platform windows|linux|all]
#
# Outputs under dist/win/ and/or dist/linux/:
#   gen1recomp-content-editor-win64.zip
#   gen1recomp-content-editor-linux64.tar.gz
#
# Excludes data/generated, assets/generated, *.gb/*.gbc, portable.txt.

param(
  [ValidateSet("windows", "linux", "all")]
  [string]$Platform = "all"
)

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$LoveUrl = "https://github.com/love2d/love/releases/download/11.5/love-11.5-x86_64.AppImage"
$LoveAppImageName = "love-11.5-x86_64.AppImage"

function Copy-TreeFiltered {
  param(
    [string]$From,
    [string]$To,
    [string[]]$ExcludeDirNames = @(),
    [string[]]$ExcludeFilePatterns = @()
  )
  if (-not (Test-Path $From)) { return }
  New-Item -ItemType Directory -Force -Path $To | Out-Null
  Get-ChildItem -LiteralPath $From -Force | ForEach-Object {
    $name = $_.Name
    if ($_.PSIsContainer) {
      if ($ExcludeDirNames -contains $name) { return }
      Copy-TreeFiltered -From $_.FullName -To (Join-Path $To $name) `
        -ExcludeDirNames $ExcludeDirNames `
        -ExcludeFilePatterns $ExcludeFilePatterns
    } else {
      foreach ($pat in $ExcludeFilePatterns) {
        if ($name -like $pat) { return }
      }
      Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $To $name) -Force
    }
  }
}

function Clear-RomCache([string]$Stage) {
  @(
    (Join-Path $Stage "portable.txt"),
    (Join-Path $Stage "data\generated"),
    (Join-Path $Stage "assets\generated")
  ) | ForEach-Object {
    if (Test-Path $_) { Remove-Item -LiteralPath $_ -Recurse -Force }
  }
}

function New-ContentEditorStage([string]$Stage, [string]$Kind) {
  Write-Host "Staging $Kind from $Root -> $Stage"
  if (Test-Path $Stage) { Remove-Item -LiteralPath $Stage -Recurse -Force }
  New-Item -ItemType Directory -Force -Path $Stage | Out-Null

  $excludeDirs = @(
    ".git", ".cursor", "dist", "generated", "node_modules", "__pycache__"
  )
  $excludeFiles = @(
    "*.gb", "*.gbc", "portable.txt", "*.zip", "*.tar.gz",
    ".DS_Store", "Thumbs.db",
    # Development-only smoke-test drivers are not part of portable builds.
    "_check_driver.lua", "_syntax_check.lua"
  )

  foreach ($f in @(
    "main.lua", "conf.lua",
    "README.md", "README.txt", ".gitattributes"
  )) {
    $src = Join-Path $Root $f
    if (Test-Path $src) {
      Copy-Item -LiteralPath $src -Destination (Join-Path $Stage $f) -Force
    }
  }

  # Always ship both launchers when present (harmless on the other OS).
  foreach ($launcher in @("ContentEditor.bat", "ContentEditor.sh")) {
    $src = Join-Path $Root $launcher
    if (Test-Path $src) {
      Copy-Item -LiteralPath $src -Destination (Join-Path $Stage $launcher) -Force
    }
  }

  $packReadme = Join-Path $Root "tools\content-editor\PACK_README.md"
  if (-not (Test-Path $packReadme)) {
    $packReadme = Join-Path $Root "PACK_README.md"
  }
  if (Test-Path $packReadme) {
    Copy-Item -LiteralPath $packReadme -Destination (Join-Path $Stage "PACK_README.md") -Force
  }

  Copy-TreeFiltered -From (Join-Path $Root "src") -To (Join-Path $Stage "src") `
    -ExcludeDirNames $excludeDirs -ExcludeFilePatterns $excludeFiles
  Copy-TreeFiltered -From (Join-Path $Root "libs") -To (Join-Path $Stage "libs") `
    -ExcludeDirNames $excludeDirs -ExcludeFilePatterns $excludeFiles

  $toolsStage = Join-Path $Stage "tools"
  New-Item -ItemType Directory -Force -Path $toolsStage | Out-Null
  Copy-TreeFiltered -From (Join-Path $Root "tools\content-editor") `
    -To (Join-Path $toolsStage "content-editor") `
    -ExcludeDirNames $excludeDirs -ExcludeFilePatterns $excludeFiles
  Copy-TreeFiltered -From (Join-Path $Root "tools\save-editor") `
    -To (Join-Path $toolsStage "save-editor") `
    -ExcludeDirNames $excludeDirs -ExcludeFilePatterns $excludeFiles

  # modkit validate (Python) + ROM manifests
  foreach ($extra in @("modkit.py")) {
    $src = Join-Path $Root "tools\$extra"
    if (Test-Path $src) {
      Copy-Item -LiteralPath $src -Destination (Join-Path $toolsStage $extra) -Force
    }
  }
  foreach ($mf in @(
    "rom_manifest.json", "rom_manifest_blue.json", "rom_manifest_yellow.json"
  )) {
    $src = Join-Path $Root "tools\$mf"
    if (Test-Path $src) {
      Copy-Item -LiteralPath $src -Destination (Join-Path $toolsStage $mf) -Force
    }
  }

  $dataStage = Join-Path $Stage "data"
  New-Item -ItemType Directory -Force -Path $dataStage | Out-Null
  if (Test-Path (Join-Path $Root "data\scripts")) {
    Copy-TreeFiltered -From (Join-Path $Root "data\scripts") `
      -To (Join-Path $dataStage "scripts") `
      -ExcludeDirNames $excludeDirs -ExcludeFilePatterns $excludeFiles
  }
  foreach ($pf in @("palettes_gbc.lua", "palettes_yellow.lua")) {
    $src = Join-Path $Root "data\$pf"
    if (Test-Path $src) {
      Copy-Item -LiteralPath $src -Destination (Join-Path $dataStage $pf) -Force
    }
  }

  $assetsStage = Join-Path $Stage "assets"
  New-Item -ItemType Directory -Force -Path $assetsStage | Out-Null
  foreach ($sub in @("launcher", "logo", "switch", "touch")) {
    $src = Join-Path $Root "assets\$sub"
    if (Test-Path $src) {
      Copy-TreeFiltered -From $src -To (Join-Path $assetsStage $sub) `
        -ExcludeDirNames $excludeDirs -ExcludeFilePatterns $excludeFiles
    }
  }

  $fixSrc = Join-Path $Root "tests\fixture_data"
  if (Test-Path $fixSrc) {
    Copy-TreeFiltered -From $fixSrc `
      -To (Join-Path $Stage "tests\fixture_data") `
      -ExcludeDirNames $excludeDirs -ExcludeFilePatterns $excludeFiles
  }

  foreach ($doc in @("content-editor.md", "tiled-map-editing.md")) {
    $src = Join-Path $Root "docs\$doc"
    if (Test-Path $src) {
      New-Item -ItemType Directory -Force -Path (Join-Path $Stage "docs") | Out-Null
      Copy-Item -LiteralPath $src -Destination (Join-Path $Stage "docs\$doc") -Force
    }
  }

  $modsStage = Join-Path $Stage "mods"
  New-Item -ItemType Directory -Force -Path $modsStage | Out-Null
  if (Test-Path (Join-Path $Root "mods\examples")) {
    Copy-TreeFiltered -From (Join-Path $Root "mods\examples") `
      -To (Join-Path $modsStage "examples") `
      -ExcludeDirNames $excludeDirs -ExcludeFilePatterns $excludeFiles
  }
  if (Test-Path (Join-Path $Root "mods\New_PokemonTest")) {
    Copy-TreeFiltered -From (Join-Path $Root "mods\New_PokemonTest") `
      -To (Join-Path $modsStage "New_PokemonTest") `
      -ExcludeDirNames $excludeDirs -ExcludeFilePatterns $excludeFiles
  }

  Clear-RomCache $Stage
}

function Add-WindowsLove([string]$Stage) {
  $loveSrc = Join-Path $Root "love"
  $exe = Join-Path $loveSrc "love.exe"
  if (-not (Test-Path $exe)) {
    $nested = Join-Path $loveSrc "love-11.5-win64\love.exe"
    if (-not (Test-Path $nested)) {
      throw "Missing love\love.exe in checkout - cannot build Windows pack."
    }
  }
  Copy-TreeFiltered -From $loveSrc -To (Join-Path $Stage "love") `
    -ExcludeDirNames @(".git") -ExcludeFilePatterns @("*.gb", "*.gbc")
}

function Add-LinuxLove([string]$Stage) {
  $cacheDir = Join-Path $Root "dist\_cache"
  New-Item -ItemType Directory -Force -Path $cacheDir | Out-Null
  $cached = Join-Path $cacheDir $LoveAppImageName
  if (-not (Test-Path $cached)) {
    Write-Host "Downloading $LoveUrl ..."
    Invoke-WebRequest -Uri $LoveUrl -OutFile $cached -UseBasicParsing
  } else {
    Write-Host "Using cached AppImage: $cached"
  }
  $loveDir = Join-Path $Stage "love"
  New-Item -ItemType Directory -Force -Path $loveDir | Out-Null
  Copy-Item -LiteralPath $cached -Destination (Join-Path $loveDir $LoveAppImageName) -Force

  $readme = @(
    "LOVE 11.5 AppImage (x86_64)",
    "",
    "If ContentEditor.sh says the runtime is not executable:",
    "  chmod +x love/$LoveAppImageName ContentEditor.sh"
  ) -join "`n"
  Set-Content -Path (Join-Path $loveDir "README.txt") -Value $readme -Encoding ascii
}

function Write-LinuxReadme([string]$Stage) {
  $text = @(
    "Gen1Recomp Content Editor - portable Linux pack (x86_64)",
    "",
    "1. tar -xzf gen1recomp-content-editor-linux64.tar.gz",
    "2. cd into the extracted folder",
    "3. chmod +x ContentEditor.sh love/love-11.5-x86_64.AppImage",
    "4. ./ContentEditor.sh",
    "5. Project -> GAME DATA -> Link Recomp (or Import ROM)",
    "",
    "This pack has no ROM cache. Share mods as mods/<id>/ only.",
    "Do not ship .gb files or data/generated / assets/generated.",
    "",
    "Full guide: README.md or docs/content-editor.md"
  ) -join "`n"
  Set-Content -Path (Join-Path $Stage "README.txt") -Value $text -Encoding ascii
}

function Pack-Windows {
  $OutDir = Join-Path $Root "dist\win"
  $Stage = Join-Path $Root "dist\_content_editor_stage_win"
  $ZipPath = Join-Path $OutDir "gen1recomp-content-editor-win64.zip"
  New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
  New-ContentEditorStage $Stage "windows"
  Add-WindowsLove $Stage
  if (Test-Path $ZipPath) { Remove-Item -LiteralPath $ZipPath -Force }
  Compress-Archive -Path (Join-Path $Stage "*") -DestinationPath $ZipPath -Force
  $size = (Get-Item $ZipPath).Length
  Write-Host ("Wrote {0} ({1:N1} MB)" -f $ZipPath, ($size / 1MB))
}

function Set-LinuxTarExecBits([string]$TarPath) {
  # Windows tar stores .sh / AppImage as 644. Rewrite modes so extract is +x.
  $py = @"
import tarfile, os, tempfile, shutil
src = r'''$TarPath'''
fd, tmp = tempfile.mkstemp(suffix='.tar.gz')
os.close(fd)
want = ('.sh', '.AppImage')
with tarfile.open(src, 'r:gz') as inn, tarfile.open(tmp, 'w:gz') as out:
    for m in inn.getmembers():
        name = m.name.replace('\\', '/')
        base = os.path.basename(name)
        if base.endswith(want) or base == 'ContentEditor.sh':
            m.mode = (m.mode & 0o777) | 0o755
        f = inn.extractfile(m) if m.isfile() else None
        out.addfile(m, f)
shutil.move(tmp, src)
print('exec bits set on .sh / AppImage')
"@
  $pyFile = Join-Path $env:TEMP "ce_fix_linux_tar_exec.py"
  Set-Content -Path $pyFile -Value $py -Encoding utf8
  $python = $null
  foreach ($c in @("python", "py", "python3")) {
    if (Get-Command $c -ErrorAction SilentlyContinue) { $python = $c; break }
  }
  if (-not $python) {
    Write-Warning "Python not found; tar may need chmod +x on Linux."
    return
  }
  if ($python -eq "py") {
    & $python -3 $pyFile
  } else {
    & $python $pyFile
  }
  if ($LASTEXITCODE -ne 0) {
    Write-Warning "Could not set exec bits in tar (exit $LASTEXITCODE)."
  }
}

function Pack-Linux {
  $OutDir = Join-Path $Root "dist\linux"
  $Stage = Join-Path $Root "dist\_content_editor_stage_linux"
  $TarPath = Join-Path $OutDir "gen1recomp-content-editor-linux64.tar.gz"
  New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
  New-ContentEditorStage $Stage "linux"
  Add-LinuxLove $Stage
  Write-LinuxReadme $Stage

  if (Test-Path $TarPath) { Remove-Item -LiteralPath $TarPath -Force }
  $parent = Split-Path $Stage -Parent
  $tmpName = "gen1recomp-content-editor-linux64"
  $tmpStage = Join-Path $parent $tmpName
  if (Test-Path $tmpStage) { Remove-Item -LiteralPath $tmpStage -Recurse -Force }
  Rename-Item -LiteralPath $Stage -NewName $tmpName
  Push-Location $parent
  try {
    tar -czf $TarPath $tmpName
    if ($LASTEXITCODE -ne 0) { throw "tar failed with exit $LASTEXITCODE" }
  } finally {
    Pop-Location
  }
  # Keep stage around renamed back for inspection
  if (Test-Path $tmpStage) {
    Rename-Item -LiteralPath $tmpStage -NewName (Split-Path $Stage -Leaf)
  }

  Set-LinuxTarExecBits $TarPath

  $size = (Get-Item $TarPath).Length
  Write-Host ("Wrote {0} ({1:N1} MB)" -f $TarPath, ($size / 1MB))
  Write-Host "On Linux: ./ContentEditor.sh  (chmod auto-applied if needed)"
}

if ($Platform -eq "windows" -or $Platform -eq "all") { Pack-Windows }
if ($Platform -eq "linux" -or $Platform -eq "all") { Pack-Linux }
