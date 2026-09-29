-- Build a portable source update without downloading release assets or LÖVE.
local M = {}

function M.validSha(sha)
  return type(sha) == "string" and #sha == 40 and sha:match("^%x+$") ~= nil
end

-- These are application-owned paths. Never include mods, love, or generated data.
M.directories = { "tools/content-editor", "tools/save-editor", "tools/tooling",
  "libs", "tests/fixture_data", "assets/launcher", "assets/logo", "assets/switch", "assets/touch" }
M.files = { "tools/modkit.py", "tests/love_stub.lua", "ContentEditor.bat",
  "ContentEditor.sh", "ContentEditor.command", "docs/content-editor.md", "docs/tiled-map-editing.md" }

-- Replace only these units, so deleted application modules disappear too.
function M.installUnits()
  local units = {}
  for _, list in ipairs({ M.directories, M.files, { "main.lua", "conf.lua",
      "runtime/gen1recomp.love", "tools/rom_manifest.json", "tools/rom_manifest_blue.json",
      "tools/rom_manifest_yellow.json", "tools/rom_manifest_gold.json",
      "content-editor-commit.txt" } }) do
    for _, path in ipairs(list) do units[#units + 1] = path end
  end
  return units
end

function M.installScript(root, stage, pid, windows, launcher, relaunch)
  local function quote(s) return "'" .. s:gsub("'", windows and "''" or "'\\''") .. "'" end
  local lines = {}
  local function add(s) lines[#lines + 1] = s end
  if windows then
    add("$ErrorActionPreference = 'Stop'")
    add("$root = " .. quote(root))
    add("$stage = " .. quote(stage))
    add("while (Get-Process -Id " .. tonumber(pid) .. " -ErrorAction SilentlyContinue) { Start-Sleep -Seconds 1 }")
    add("if (Test-Path -LiteralPath (Join-Path $root '.git')) { throw 'Refusing to update a Git checkout' }")
    add("$backup = Join-Path $stage ('backup-' + [guid]::NewGuid().ToString('N'))")
    add("New-Item -ItemType Directory -Path $backup | Out-Null")
    local units = {}
    for _, path in ipairs(M.installUnits()) do units[#units + 1] = quote(path) end
    add("$units = @(" .. table.concat(units, ",") .. ")")
    add("$changed = @()")
    add("try {")
    add("  foreach ($unit in $units) {")
    add("    $from = Join-Path $stage $unit; $to = Join-Path $root $unit; $old = Join-Path $backup $unit")
    add("    if (-not (Test-Path -LiteralPath $from)) { throw ('Missing update file: ' + $unit) }")
    add("    New-Item -ItemType Directory -Force -Path (Split-Path $old) | Out-Null")
    add("    New-Item -ItemType Directory -Force -Path (Split-Path $to) | Out-Null")
    add("    if (Test-Path -LiteralPath $to) { Move-Item -LiteralPath $to -Destination $old }")
    add("    $changed += $unit")
    add("    Copy-Item -LiteralPath $from -Destination $to -Recurse -Force")
    add("  }")
    add("} catch {")
    add("  [array]::Reverse($changed)")
    add("  foreach ($unit in $changed) {")
    add("    $to = Join-Path $root $unit; $old = Join-Path $backup $unit")
    add("    if (Test-Path -LiteralPath $to) { Remove-Item -LiteralPath $to -Recurse -Force }")
    add("    if (Test-Path -LiteralPath $old) { Move-Item -LiteralPath $old -Destination $to }")
    add("  }")
    add("  throw")
    add("}")
    if relaunch then add("Start-Process -FilePath (Join-Path $root " .. quote(launcher) .. ") -WorkingDirectory $root -WindowStyle Hidden") end
  else
    add("#!/bin/sh\nset -eu")
    add("root=" .. quote(root) .. "\nstage=" .. quote(stage))
    add("while kill -0 " .. tonumber(pid) .. " 2>/dev/null; do sleep 1; done")
    add("test ! -e \"$root/.git\"")
    add("backup=$(mktemp -d \"$stage/backup.XXXXXX\")\nchanged=''")
    add("rollback() { for unit in $changed; do rm -rf \"$root/$unit\"; if [ -e \"$backup/$unit\" ]; then mv \"$backup/$unit\" \"$root/$unit\"; fi; done; }")
    add("trap rollback EXIT\ntrap 'exit 1' HUP INT TERM")
    add("for unit in " .. table.concat(M.installUnits(), " ") .. "; do")
    add("  test -e \"$stage/$unit\"")
    add("  mkdir -p \"$(dirname \"$backup/$unit\")\" \"$(dirname \"$root/$unit\")\"")
    add("  if [ -e \"$root/$unit\" ]; then mv \"$root/$unit\" \"$backup/$unit\"; fi")
    add("  changed=\"$unit $changed\"")
    add("  cp -R \"$stage/$unit\" \"$root/$unit\"")
    add("done\ntrap - EXIT HUP INT TERM")
    if relaunch then add("cd \"$root\"\n./" .. launcher .. " >/dev/null 2>&1 &") end
  end
  return (windows and "\239\187\191" or "") .. table.concat(lines, "\n") .. "\n"
end

function M.stageScript(source, stage, runtimeArchive, windows)
  local lines = {}
  local function add(s) lines[#lines + 1] = s end
  local function ps(s) return "'" .. s:gsub("'", "''") .. "'" end
  local function sh(s) return "'" .. s:gsub("'", "'\\''") .. "'" end
  if windows then
    add("$ErrorActionPreference = 'Stop'")
    add("$source = " .. ps(source))
    add("$stage = " .. ps(stage))
    add("New-Item -ItemType Directory -Force -Path $stage | Out-Null")
    for _, path in ipairs(M.directories) do
      add("$dest = Join-Path $stage " .. ps(path))
      add("New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null")
      add("Copy-Item -LiteralPath (Join-Path $source " .. ps(path) .. ") -Destination $dest -Recurse -Force")
    end
    for _, path in ipairs(M.files) do
      add("New-Item -ItemType Directory -Force -Path (Split-Path (Join-Path $stage " .. ps(path) .. ")) | Out-Null")
      add("Copy-Item -LiteralPath (Join-Path $source " .. ps(path) .. ") -Destination (Join-Path $stage " .. ps(path) .. ") -Force")
    end
    add("Copy-Item -Path (Join-Path $source 'tools/rom_manifest*.json') -Destination (Join-Path $stage 'tools') -Force")
    for _, name in ipairs({ "main.lua", "conf.lua" }) do
      add("Copy-Item -LiteralPath (Join-Path $source 'tools/content-editor/runtime/" .. name .. "') -Destination (Join-Path $stage '" .. name .. "')")
    end
    add("$runtime = Join-Path $stage 'runtime'")
    add("New-Item -ItemType Directory -Force -Path $runtime | Out-Null")
    add("$unpacked = Join-Path $source 'runtime-source'")
    add("New-Item -ItemType Directory -Force -Path $unpacked | Out-Null")
    -- GNU tar (e.g. Git Bash's) reads "C:\..." as a remote host; use Windows' bsdtar.
    add("$tar = Join-Path $env:SystemRoot 'System32\\tar.exe'")
    add("if (-not (Test-Path $tar)) { $tar = 'tar' }")
    add("& $tar -xzf " .. ps(runtimeArchive) .. " -C $unpacked --strip-components=1")
    add("if ($LASTEXITCODE -ne 0) { throw 'Runtime archive extraction failed' }")
    add("if (-not (Test-Path (Join-Path $unpacked 'src/core/Input.lua'))) { throw 'Incomplete runtime source' }")
    add("$items = @('main.lua','conf.lua','src','data','assets') | ForEach-Object { Join-Path $unpacked $_ }")
    add("Compress-Archive -LiteralPath $items -DestinationPath (Join-Path $runtime 'gen1recomp.zip')")
    add("Move-Item -LiteralPath (Join-Path $runtime 'gen1recomp.zip') -Destination (Join-Path $runtime 'gen1recomp.love')")
  else
    add("#!/bin/sh\nset -eu")
    add("command -v zip >/dev/null || { echo 'Source updates require zip'; exit 1; }")
    add("mkdir -p " .. sh(stage .. "/tools") .. " " .. sh(stage .. "/tests") .. " " .. sh(stage .. "/runtime") .. " " .. sh(stage .. "/assets") .. " " .. sh(stage .. "/docs"))
    for _, path in ipairs(M.directories) do add("cp -R " .. sh(source .. "/" .. path) .. " " .. sh(stage .. "/" .. path)) end
    for _, path in ipairs(M.files) do add("cp " .. sh(source .. "/" .. path) .. " " .. sh(stage .. "/" .. path)) end
    add("cp " .. sh(source .. "/tools") .. "/rom_manifest*.json " .. sh(stage .. "/tools/"))
    for _, name in ipairs({ "main.lua", "conf.lua" }) do
      add("cp " .. sh(source .. "/tools/content-editor/runtime/" .. name) .. " " .. sh(stage .. "/" .. name))
    end
    add("mkdir -p " .. sh(source .. "/runtime-source"))
    add("tar -xzf " .. sh(runtimeArchive) .. " -C " .. sh(source .. "/runtime-source") .. " --strip-components=1")
    add("cd " .. sh(source .. "/runtime-source"))
    add("test -f src/core/Input.lua")
    add("zip -qr " .. sh(stage .. "/runtime/gen1recomp.love") .. " main.lua conf.lua src data assets")
    add("chmod +x " .. sh(stage .. "/ContentEditor.sh") .. " " .. sh(stage .. "/ContentEditor.command"))
  end
  return (windows and "\239\187\191" or "") .. table.concat(lines, "\n") .. "\n"
end

return M
