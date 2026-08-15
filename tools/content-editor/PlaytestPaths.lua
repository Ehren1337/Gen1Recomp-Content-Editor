local PlaytestPaths = {}

local function separator()
  return package.config:sub(1, 1)
end

function PlaytestPaths.absoluteFromRoot(path, root)
  path = tostring(path or "")
  local windowsAbsolute = path:match("^%a:[/\\]") ~= nil
    or path:match("^[/\\][/\\]") ~= nil
  local unixAbsolute = path:sub(1, 1) == "/"
  if windowsAbsolute or unixAbsolute then return path end
  return root .. separator() .. path
end

function PlaytestPaths.same(a, b)
  local sep = separator()
  local function normalize(path)
    path = tostring(path or ""):gsub("[/\\]+", sep):gsub("[/\\]+$", "")
    if sep == "\\" then path = path:lower() end
    return path
  end
  return normalize(a) == normalize(b)
end

function PlaytestPaths.pinnedRuntime(root, isValidRoot, isFile)
  local candidate = tostring(root or "") .. separator()
    .. "runtime" .. separator() .. "gen1recomp"
  if type(isValidRoot) == "function" and isValidRoot(candidate) then
    return candidate
  end
  local archive = candidate .. ".love"
  if type(isFile) == "function" and isFile(archive) then return archive end
  local fused = tostring(root or "") .. separator() .. "love"
    .. separator() .. "gen1recomp.exe"
  if type(isFile) == "function" and isFile(fused) then return fused end
  return nil
end

function PlaytestPaths.windowsLaunch(loveExe, runtimeSource, workDir, version)
  local source = runtimeSource
  if version == nil then
    version, workDir, source = workDir, runtimeSource, "."
  end
  return string.format('cd /d "%s" && start "" "%s" "%s" --game=%s',
    workDir, loveExe, source, version)
end

return PlaytestPaths
