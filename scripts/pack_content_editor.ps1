# Build a shareable Content Editor pack with no ROM-derived cache.
#
#   .\scripts\pack_content_editor.ps1 [-Platform windows|linux|macos|all]
#
# Outputs under dist/win/ and/or dist/linux/:
#   gen1recomp-content-editor-win64.zip
#   gen1recomp-content-editor-linux64.tar.gz
#   gen1recomp-content-editor-macos-universal.tar.gz
#
# Excludes ROM-derived data and user saves. Release launchers include an empty
# portable marker beside LÖVE so new data remains inside the extracted pack.

param(
  [ValidateSet("windows", "linux", "macos", "all")]
  [string]$Platform = "all"
)

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$LoveUrl = "https://github.com/love2d/love/releases/download/11.5/love-11.5-x86_64.AppImage"
$LoveAppImageName = "love-11.5-x86_64.AppImage"
$LoveMacUrl = "https://github.com/love2d/love/releases/download/11.5/love-11.5-macos.zip"
$LoveMacZipName = "love-11.5-macos.zip"

function Copy-TreeFiltered {
  param(
    [string]$From,
    [string]$To,
    [string[]]$ExcludeDirNames = @(),
    [string[]]$ExcludeFilePatterns = @(),
    [string[]]$RootExcludeDirNames = @(),
    [int]$Depth = 0
  )
  if (-not (Test-Path $From)) { return }
  New-Item -ItemType Directory -Force -Path $To | Out-Null
  Get-ChildItem -LiteralPath $From -Force | ForEach-Object {
    $name = $_.Name
    if ($_.PSIsContainer) {
      if ($ExcludeDirNames -contains $name -or
          ($Depth -eq 0 -and $RootExcludeDirNames -contains $name)) { return }
      Copy-TreeFiltered -From $_.FullName -To (Join-Path $To $name) `
        -ExcludeDirNames $ExcludeDirNames `
        -ExcludeFilePatterns $ExcludeFilePatterns `
        -RootExcludeDirNames $RootExcludeDirNames -Depth ($Depth + 1)
    } else {
      foreach ($pat in $ExcludeFilePatterns) {
        if ($name -like $pat) { return }
      }
      Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $To $name) -Force
    }
  }
}

# Unix launchers must be LF-only. Copy-Item from a Windows checkout can
# leave CR bytes, and macOS then treats the shebang as /bin/sh^M.
function ConvertTo-UnixFile([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path)) { return }
  $text = [System.IO.File]::ReadAllText($Path)
  $unix = $text -replace "`r`n", "`n" -replace "`r", "`n"
  $utf8 = New-Object System.Text.UTF8Encoding $false
  [System.IO.File]::WriteAllText($Path, $unix, $utf8)
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

function ConvertTo-UnixLineEndings([string]$Path) {
  $text = [IO.File]::ReadAllText($Path)
  $text = $text.Replace("`r`n", "`n").Replace("`r", "`n")
  $utf8WithoutBom = New-Object System.Text.UTF8Encoding($false)
  [IO.File]::WriteAllText($Path, $text, $utf8WithoutBom)
}

function Resolve-RuntimeSource {
  $pin = Join-Path $Root "runtime\gen1recomp"
  if (Test-Path (Join-Path $pin "main.lua")) { return $pin }
  $candidates = @()
  if ($env:POKEPORT_RECOMP) { $candidates += $env:POKEPORT_RECOMP }
  $prefs = Join-Path $env:APPDATA "LOVE\pokemon-love2d\content_editor_data.json"
  if (Test-Path -LiteralPath $prefs) {
    $raw = Get-Content -LiteralPath $prefs -Raw
    if ($raw -match '"recompRoot"\s*:\s*"([^"]+)"') {
      $candidates += ($Matches[1] -replace '\\\\', '\')
    }
  }
  foreach ($candidate in $candidates) {
    if (-not $candidate) { continue }
    if ((Test-Path (Join-Path $candidate "main.lua")) -and
        (Test-Path (Join-Path $candidate "src\core\GameVersion.lua"))) {
      Write-Host "Using linked Recomp runtime: $candidate"
      return $candidate
    }
  }
  throw "Pinned runtime is missing. Link a Recomp folder in the editor, or run: git submodule update --init --recursive"
}

function New-RuntimeLoveArchive([string]$Source, [string]$Dest) {
  $payload = @("main.lua", "conf.lua", "src", "data", "assets", "LICENSE.MD")
  $git = Get-Command git -ErrorAction SilentlyContinue
  if ($git -and (Test-Path (Join-Path $Source ".git"))) {
    & git -C $Source archive --format=zip "--output=$Dest" HEAD -- @payload
    if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $Dest)) { return }
  }
  $temp = Join-Path ([IO.Path]::GetTempPath()) ("ce-runtime-" + [guid]::NewGuid().ToString("N"))
  New-Item -ItemType Directory -Force -Path $temp | Out-Null
  try {
    foreach ($name in @("main.lua", "conf.lua", "LICENSE.MD")) {
      $from = Join-Path $Source $name
      if (Test-Path -LiteralPath $from) {
        Copy-Item -LiteralPath $from -Destination (Join-Path $temp $name) -Force
      }
    }
    foreach ($dir in @("src", "data", "assets")) {
      $from = Join-Path $Source $dir
      if (Test-Path -LiteralPath $from) {
        Copy-TreeFiltered -From $from -To (Join-Path $temp $dir) `
          -ExcludeDirNames @(".git", "generated", "__pycache__")
      }
    }
    if (-not (Test-Path (Join-Path $temp "main.lua"))) {
      throw "Runtime source has no main.lua: $Source"
    }
    $zip = "$Dest.zip"
    if (Test-Path -LiteralPath $Dest) { Remove-Item -LiteralPath $Dest -Force }
    if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
    Compress-Archive -Path (Join-Path $temp "*") -DestinationPath $zip -Force
    Move-Item -LiteralPath $zip -Destination $Dest -Force
  } finally {
    Remove-Item -LiteralPath $temp -Recurse -Force
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
    ".DS_Store", "Thumbs.db"
  )

  # Playtest needs a Gen1Recomp runtime. Prefer the pin; otherwise the
  # Recomp folder already linked in the editor. Never pack ROM caches.
  $runtimeSource = Resolve-RuntimeSource
  $runtimeStage = Join-Path $Stage "runtime"
  New-Item -ItemType Directory -Force -Path $runtimeStage | Out-Null
  $runtimeArchive = Join-Path $runtimeStage "gen1recomp.love"
  New-RuntimeLoveArchive -Source $runtimeSource -Dest $runtimeArchive
  if (-not (Test-Path -LiteralPath $runtimeArchive)) {
    throw "Could not build runtime archive."
  }

  foreach ($f in @("README.md", "README.txt", ".gitattributes")) {
    $src = Join-Path $Root $f
    if (Test-Path $src) {
      Copy-Item -LiteralPath $src -Destination (Join-Path $Stage $f) -Force
    }
  }

  $launcher = switch ($Kind) {
    "windows" { "ContentEditor.bat" }
    "linux" { "ContentEditor.sh" }
    "macOS" { "ContentEditor.command" }
    default { throw "Unsupported package kind: $Kind" }
  }
  $launcherPath = Join-Path $Root $launcher
  if (-not (Test-Path $launcherPath)) {
    throw "Missing $launcher - cannot build the $Kind package."
  }
  $launcherDest = Join-Path $Stage $launcher
  Copy-Item -LiteralPath $launcherPath -Destination $launcherDest -Force
  if ($Kind -eq "linux" -or $Kind -eq "macOS") {
    ConvertTo-UnixFile $launcherDest
    $launcherBytes = [System.IO.File]::ReadAllBytes($launcherDest)
    if ($launcherBytes -contains 13) {
      throw "$launcher still has CR bytes after Unix conversion."
    }
  }

  $packReadme = Join-Path $Root "tools\content-editor\PACK_README.md"
  if (-not (Test-Path $packReadme)) {
    $packReadme = Join-Path $Root "PACK_README.md"
  }
  if (Test-Path $packReadme) {
    Copy-Item -LiteralPath $packReadme -Destination (Join-Path $Stage "PACK_README.md") -Force
  }

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
  if (Test-Path (Join-Path $Root "tools\tooling")) {
    Copy-TreeFiltered -From (Join-Path $Root "tools\tooling") `
      -To (Join-Path $toolsStage "tooling") `
      -ExcludeDirNames $excludeDirs -ExcludeFilePatterns $excludeFiles
  }

  # modkit validate (Python) + ROM manifests
  foreach ($extra in @("modkit.py")) {
    $src = Join-Path $Root "tools\$extra"
    if (Test-Path $src) {
      Copy-Item -LiteralPath $src -Destination (Join-Path $toolsStage $extra) -Force
    }
  }
  $manifests = @(Get-ChildItem -LiteralPath (Join-Path $Root "tools") `
    -Filter "rom_manifest*.json")
  foreach ($need in @(
    "rom_manifest.json",
    "rom_manifest_blue.json",
    "rom_manifest_yellow.json",
    "rom_manifest_gold.json"
  )) {
    if (-not ($manifests | Where-Object { $_.Name -eq $need })) {
      throw "Missing tools\$need - cannot build pack."
    }
  }
  foreach ($mf in $manifests) {
    Copy-Item -LiteralPath $mf.FullName `
      -Destination (Join-Path $toolsStage $mf.Name) -Force
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

  foreach ($f in @("main.lua", "conf.lua")) {
    $src = Join-Path $Root "tools\content-editor\runtime\$f"
    if (-not (Test-Path $src)) {
      throw "Missing standalone editor runtime file: $src"
    }
    Copy-Item -LiteralPath $src -Destination (Join-Path $Stage $f) -Force
  }
  # modkit's headless loader requires the LÖVE API shim as well as fixture
  # data. Keep it in the same tests/ module path used by source checkouts so
  # LuaJIT can resolve require("tests.love_stub") on every platform.
  $loveStub = Join-Path $Root "tests\love_stub.lua"
  if (-not (Test-Path $loveStub)) {
    throw "Missing tests\love_stub.lua - packaged validation would not run."
  }
  $testsStage = Join-Path $Stage "tests"
  New-Item -ItemType Directory -Force -Path $testsStage | Out-Null
  Copy-Item -LiteralPath $loveStub `
    -Destination (Join-Path $testsStage "love_stub.lua") -Force

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

function Enable-PortablePersistence([string]$Stage) {
  # Both the editor's love.exe and the fused Playtest executable live here.
  # SaveData checks the executable directory before the mounted source, so a
  # single marker gives both processes the same persistence root.
  $loveDir = Join-Path $Stage "love"
  New-Item -ItemType Directory -Force -Path $loveDir | Out-Null
  Set-Content -LiteralPath (Join-Path $loveDir "portable.txt") `
    -Value "Gen1Recomp Content Editor portable persistence" -Encoding ascii
}

function ConvertTo-WindowsFusedRuntime([string]$Stage) {
  $loveExe = Join-Path $Stage "love\love.exe"
  $archive = Join-Path $Stage "runtime\gen1recomp.love"
  $fused = Join-Path $Stage "love\gen1recomp.exe"
  if (-not (Test-Path $loveExe) -or -not (Test-Path $archive)) {
    throw "Windows runtime fusion requires love.exe and gen1recomp.love."
  }
  $output = [IO.File]::Create($fused)
  try {
    foreach ($source in @($loveExe, $archive)) {
      $input = [IO.File]::OpenRead($source)
      try { $input.CopyTo($output) } finally { $input.Dispose() }
    }
  } finally {
    $output.Dispose()
  }
  Remove-Item -LiteralPath $archive -Force
  $runtimeDir = Join-Path $Stage "runtime"
  if ((Test-Path $runtimeDir) -and
      -not (Get-ChildItem -LiteralPath $runtimeDir -Force | Select-Object -First 1)) {
    Remove-Item -LiteralPath $runtimeDir -Force
  }
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

function Add-MacLove([string]$Stage) {
  $cacheDir = Join-Path $Root "dist\_cache"
  New-Item -ItemType Directory -Force -Path $cacheDir | Out-Null
  $cached = Join-Path $cacheDir $LoveMacZipName
  if (-not (Test-Path $cached)) {
    Write-Host "Downloading $LoveMacUrl ..."
    Invoke-WebRequest -Uri $LoveMacUrl -OutFile $cached -UseBasicParsing
  }
  $expanded = Join-Path $cacheDir "love-11.5-macos"
  if (Test-Path $expanded) { Remove-Item -LiteralPath $expanded -Recurse -Force }
  Expand-Archive -LiteralPath $cached -DestinationPath $expanded -Force
  $app = Get-ChildItem -LiteralPath $expanded -Directory -Filter "love.app" -Recurse |
    Select-Object -First 1
  if (-not $app) { throw "The macOS LÖVE archive did not contain love.app" }
  $loveDir = Join-Path $Stage "love"
  New-Item -ItemType Directory -Force -Path $loveDir | Out-Null
  Copy-Item -LiteralPath $app.FullName -Destination (Join-Path $loveDir "love.app") `
    -Recurse -Force
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
  ConvertTo-WindowsFusedRuntime $Stage
  Enable-PortablePersistence $Stage
  if (Test-Path $ZipPath) { Remove-Item -LiteralPath $ZipPath -Force }
  $parent = Split-Path $Stage -Parent
  $packageName = "gen1recomp-content-editor-win64"
  $packageStage = Join-Path $parent $packageName
  if (Test-Path $packageStage) {
    Remove-Item -LiteralPath $packageStage -Recurse -Force
  }
  Rename-Item -LiteralPath $Stage -NewName $packageName
  try {
    Compress-Archive -Path $packageStage -DestinationPath $ZipPath -Force
  } finally {
    if (Test-Path $packageStage) {
      Rename-Item -LiteralPath $packageStage -NewName (Split-Path $Stage -Leaf)
    }
  }
  $size = (Get-Item $ZipPath).Length
  Write-Host ("Wrote {0} ({1:N1} MB)" -f $ZipPath, ($size / 1MB))
}

function Set-LinuxTarExecBits([string]$TarPath) {
  # Windows tar stores .sh / AppImage as 644. Rewrite modes so extract is +x.
  $py = @"
import io, tarfile, os, tempfile, shutil
src = r'''$TarPath'''
fd, tmp = tempfile.mkstemp(suffix='.tar.gz')
os.close(fd)
want = ('.sh', '.command', '.AppImage', '/Contents/MacOS/love', '/linux-x64/luajit')
launchers = ('ContentEditor.sh', 'ContentEditor.command')
with tarfile.open(src, 'r:gz') as inn, tarfile.open(tmp, 'w:gz') as out:
    for m in inn.getmembers():
        name = m.name.replace('\\', '/')
        base = os.path.basename(name)
        if name.endswith(want) or base in launchers:
            m.mode = 0o755
        f = inn.extractfile(m) if m.isfile() else None
        if f is not None and base in launchers:
            data = f.read().replace(b'\r\n', b'\n').replace(b'\r', b'\n')
            m.size = len(data)
            f = io.BytesIO(data)
        out.addfile(m, f)
shutil.move(tmp, src)
print('exec bits set; launcher CR stripped')
"@
  # $env:TEMP is not guaranteed on Unix PowerShell (including ubuntu-latest).
  $pyFile = Join-Path ([IO.Path]::GetTempPath()) "ce_fix_linux_tar_exec.py"
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
  Enable-PortablePersistence $Stage
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

function Pack-MacOS {
  $OutDir = Join-Path $Root "dist\macos"
  $Stage = Join-Path $Root "dist\_content_editor_stage_macos"
  $TarPath = Join-Path $OutDir "gen1recomp-content-editor-macos-universal.tar.gz"
  New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
  New-ContentEditorStage $Stage "macOS"
  Add-MacLove $Stage
  Enable-PortablePersistence $Stage
  if (Test-Path $TarPath) { Remove-Item -LiteralPath $TarPath -Force }
  $parent = Split-Path $Stage -Parent
  $packageName = "gen1recomp-content-editor-macos-universal"
  $packageStage = Join-Path $parent $packageName
  if (Test-Path $packageStage) {
    Remove-Item -LiteralPath $packageStage -Recurse -Force
  }
  Rename-Item -LiteralPath $Stage -NewName $packageName
  Push-Location $parent
  try {
    tar -czf $TarPath $packageName
    if ($LASTEXITCODE -ne 0) { throw "tar failed with exit $LASTEXITCODE" }
  } finally {
    Pop-Location
    if (Test-Path $packageStage) {
      Rename-Item -LiteralPath $packageStage -NewName (Split-Path $Stage -Leaf)
    }
  }
  Set-LinuxTarExecBits $TarPath
  $size = (Get-Item $TarPath).Length
  Write-Host ("Wrote {0} ({1:N1} MB)" -f $TarPath, ($size / 1MB))
}

if ($Platform -eq "windows" -or $Platform -eq "all") { Pack-Windows }
if ($Platform -eq "linux" -or $Platform -eq "all") { Pack-Linux }
if ($Platform -eq "macos" -or $Platform -eq "all") { Pack-MacOS }
