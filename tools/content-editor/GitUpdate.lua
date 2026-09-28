-- Git checkouts update only by fast-forward. Never reset, clean, stash or force.
local M = {}

function M.script(root, sha, windows, pid, launcher)
  assert(require("SourceUpdate").validSha(sha))
  local function quote(s) return "'" .. s:gsub("'", windows and "''" or "'\\''") .. "'" end
  local lines = {}
  local function add(s) lines[#lines + 1] = s end
  if windows then
    add("$ErrorActionPreference = 'Stop'")
    add("$env:GIT_TERMINAL_PROMPT = '0'")
    add("Set-Location -LiteralPath " .. quote(root))
    if pid then add("while (Get-Process -Id " .. tonumber(pid) .. " -ErrorAction SilentlyContinue) { Start-Sleep -Seconds 1 }") end
    add([[
function Git-Run {
  $result = & git @args
  if ($LASTEXITCODE -ne 0) { throw ('Git update paused: git ' + ($args -join ' ')) }
  return $result
}
if ((Git-Run branch --show-current) -ne 'main') { throw 'Automatic updates require the main branch.' }
if (Git-Run status --porcelain --untracked-files=normal --ignore-submodules=dirty -- . ':(exclude)mods' ':(exclude)*.editor_project.lua') {
  throw 'Automatic update paused: local editor changes must be committed or moved first. Mods are untouched.'
}
]])
    add("$target = " .. quote(sha))
    if not pid then add("Git-Run fetch --no-tags https://github.com/zeak6464/Gen1Recomp-Content-Editor.git $target") end
    add([[
Git-Run merge-base --is-ancestor HEAD $target
$protected = @('mods', 'love', ':(glob)**/mods/**', ':(glob)**/generated/**', ':(glob)**/love/**', ':(glob)**/*.editor_project.lua', ':(glob)**/.gitmodules', '.gitmodules')
& git diff --quiet HEAD $target -- @protected
if ($LASTEXITCODE -ne 0) {
  throw 'Automatic update paused: incoming changes include protected mod, data or dependency paths.'
}
$runtimeOld = $null
$runtimeTarget = $null
$entry = Git-Run ls-tree $target -- runtime/gen1recomp
if ($entry -match '^160000 commit ([a-f0-9]{40})') {
  $runtimeTarget = $Matches[1]
  if (-not (Test-Path -LiteralPath 'runtime/gen1recomp/.git')) { throw 'Initialize the pinned runtime before updating this checkout.' }
  $runtimeOld = Git-Run -C runtime/gen1recomp rev-parse HEAD
  if ($runtimeOld -ne $runtimeTarget) {
    if (Git-Run -C runtime/gen1recomp status --porcelain --untracked-files=normal -- . ':(exclude)mods') {
      throw 'Automatic update paused: the runtime has local changes.'
    }
]])
    if not pid then add("    Git-Run -C runtime/gen1recomp fetch --no-tags origin $runtimeTarget") end
    add([[
    Git-Run -C runtime/gen1recomp merge-base --is-ancestor HEAD $runtimeTarget
    & git -C runtime/gen1recomp diff --quiet HEAD $runtimeTarget -- @protected
    if ($LASTEXITCODE -ne 0) {
      throw 'Automatic update paused: runtime changes include protected mod or data paths.'
    }
  }
}
]])
    if pid then
      add([[
try {
  if ($runtimeTarget -and $runtimeOld -ne $runtimeTarget) { Git-Run -C runtime/gen1recomp checkout --detach $runtimeTarget }
  Git-Run -c submodule.recurse=false merge --ff-only $target
} catch {
  if ($runtimeOld -and $runtimeOld -ne $runtimeTarget) { & git -C runtime/gen1recomp checkout --detach $runtimeOld }
  throw
}
]])
      if launcher then add("Start-Process -FilePath " .. quote(root .. "/" .. launcher) .. " -WorkingDirectory " .. quote(root) .. " -WindowStyle Hidden") end
    end
  else
    add("#!/bin/sh\nset -eu\nexport GIT_TERMINAL_PROMPT=0\ncd " .. quote(root))
    if pid then add("while kill -0 " .. tonumber(pid) .. " 2>/dev/null; do sleep 1; done") end
    add("target=" .. quote(sha))
    add([[
pause() { echo "Automatic update paused: $*" >&2; exit 1; }
[ "$(git branch --show-current)" = main ] || pause 'switch to main first.'
status=$(git status --porcelain --untracked-files=normal --ignore-submodules=dirty -- . ':(exclude)mods' ':(exclude)*.editor_project.lua')
[ -z "$status" ] || pause 'local editor changes must be committed or moved first. Mods are untouched.'
]])
    if not pid then add("git fetch --no-tags https://github.com/zeak6464/Gen1Recomp-Content-Editor.git \"$target\"") end
    add([[
git merge-base --is-ancestor HEAD "$target" || pause 'local history cannot fast-forward to GitHub main.'
protected_changes() {
  git diff --quiet HEAD "$1" -- mods love ':(glob)**/mods/**' ':(glob)**/generated/**' ':(glob)**/love/**' ':(glob)**/*.editor_project.lua' ':(glob)**/.gitmodules' .gitmodules
}
protected_changes "$target" || pause 'incoming changes include protected mod, data or dependency paths.'
entry=$(git ls-tree "$target" -- runtime/gen1recomp)
runtime_target=$(printf '%s\n' "$entry" | sed -n 's/^160000 commit \([a-f0-9]*\).*/\1/p')
runtime_old=''
if [ -n "$runtime_target" ]; then
  [ -e runtime/gen1recomp/.git ] || pause 'initialize the pinned runtime first.'
  runtime_old=$(git -C runtime/gen1recomp rev-parse HEAD)
  if [ "$runtime_old" != "$runtime_target" ]; then
    status=$(git -C runtime/gen1recomp status --porcelain --untracked-files=normal -- . ':(exclude)mods')
    [ -z "$status" ] || pause 'the runtime has local changes.'
]])
    if not pid then add("    git -C runtime/gen1recomp fetch --no-tags origin \"$runtime_target\"") end
    add([[
    git -C runtime/gen1recomp merge-base --is-ancestor HEAD "$runtime_target" || pause 'runtime history cannot fast-forward.'
    (cd runtime/gen1recomp && protected_changes "$runtime_target") || pause 'runtime changes include protected mod or data paths.'
  fi
fi
]])
    if pid then
      add([[
if [ -n "$runtime_target" ] && [ "$runtime_old" != "$runtime_target" ]; then
  git -C runtime/gen1recomp checkout --detach "$runtime_target"
fi
if ! git -c submodule.recurse=false merge --ff-only "$target"; then
  if [ -n "$runtime_old" ] && [ "$runtime_old" != "$runtime_target" ]; then git -C runtime/gen1recomp checkout --detach "$runtime_old"; fi
  exit 1
fi
]])
      if launcher then add("./" .. launcher .. " >/dev/null 2>&1 &") end
    end
  end
  return (windows and "\239\187\191" or "") .. table.concat(lines, "\n") .. "\n"
end

return M
