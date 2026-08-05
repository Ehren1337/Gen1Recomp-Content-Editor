-- Resolve LuaJIT for modkit validate (Windows / Linux).
--
-- Do NOT download luajit.exe into the LÖVE save directory: Windows Defender
-- flags that as Behavior:Win32/SuspLua.A. On Windows we install via winget
-- into Program Files; on Linux we use PATH or apt when available.

local LuaJitTool = {}

local function sep()
  return package.config:sub(1, 1)
end

local function isWindows()
  local osName = love and love.system and love.system.getOS and love.system.getOS()
  if osName == "Windows" then return true end
  if osName == "Linux" or osName == "OS X" then return false end
  return sep() == "\\"
end

local function isLinux()
  local osName = love and love.system and love.system.getOS and love.system.getOS()
  if osName == "Linux" then return true end
  if osName == "Windows" or osName == "OS X" then return false end
  return sep() == "/"
end

local function fileExists(path)
  if not path or path == "" then return false end
  local f = io.open(path, "rb")
  if not f then return false end
  f:close()
  return true
end

local function ensureDir(path)
  if isWindows() then
    os.execute('mkdir "' .. path .. '" 2>nul')
  else
    os.execute('mkdir -p "' .. path .. '"')
  end
end

local function runShell(cmd)
  local full = cmd
  if not cmd:find("2>&1", 1, true) then
    full = cmd .. " 2>&1"
  end
  local ok, handle = pcall(io.popen, full)
  if not ok or not handle then
    return false, "shell unavailable: " .. tostring(handle)
  end
  local out = handle:read("*a") or ""
  local okClose, _, code = handle:close()
  local exit = (type(code) == "number" and code)
    or (okClose and 0 or 1)
  return exit == 0, out
end

local function saveToolsRoot()
  local save = love and love.filesystem and love.filesystem.getSaveDirectory
    and love.filesystem.getSaveDirectory()
  if save and save ~= "" then
    return save .. sep() .. "tools"
  end
  return nil
end

-- Old auto-download lived here and trips Defender — remove it if present.
local function scrubLegacyAppDataLuaJit()
  local tools = saveToolsRoot()
  if not tools then return end
  local legacy = tools .. sep() .. "luajit"
  if not fileExists(legacy .. sep() .. "win64" .. sep() .. "bin" .. sep() .. "luajit.exe")
      and not fileExists(legacy .. sep() .. "LuaJIT-win64.zip") then
    return
  end
  if isWindows() then
    runShell(string.format('cmd /C rmdir /S /Q "%s"', legacy))
  else
    runShell(string.format('rm -rf "%s"', legacy))
  end
end

local function isLegacyAppDataLuaJit(path)
  local lower = tostring(path or ""):lower():gsub("\\", "/")
  return lower:find("/love/", 1, true)
    and lower:find("/tools/luajit/", 1, true)
end

local function whichOnPath()
  local cmd = isWindows() and "where luajit 2>nul" or "command -v luajit 2>/dev/null"
  local ok, out = runShell(cmd)
  if not ok then return nil end
  for line in (out or ""):gmatch("[^\r\n]+") do
    line = line:match("^%s*(.-)%s*$")
    if line and line ~= "" and fileExists(line) and not isLegacyAppDataLuaJit(line) then
      return line
    end
  end
  return nil
end

local function works(exe, libDir)
  if not exe or not fileExists(exe) then return false end
  local cmd
  if isWindows() then
    local dir = exe:match("^(.*)[/\\][^/\\]+$") or "."
    cmd = string.format('cmd /C "cd /D "%s" && luajit.exe -e print(1)"', dir)
  else
    local env = ""
    if libDir and libDir ~= "" then
      env = string.format('LD_LIBRARY_PATH="%s:${LD_LIBRARY_PATH:-}" ', libDir)
    end
    cmd = string.format('%s"%s" -e "print(1)"', env, exe)
  end
  local ok, out = runShell(cmd)
  if (out or ""):find("1", 1, true) then return true end
  return ok
end

local function windowsCandidates()
  local s = sep()
  local list = {}
  local pf = os.getenv("ProgramFiles") or "C:\\Program Files"
  local pf86 = os.getenv("ProgramFiles(x86)") or "C:\\Program Files (x86)"
  local localApp = os.getenv("LOCALAPPDATA") or ""
  -- winget DEVCOM.LuaJIT installs here (per-user), not under Program Files.
  local extras = {
    localApp .. s .. "Programs" .. s .. "LuaJIT" .. s .. "bin" .. s .. "luajit.exe",
    localApp .. s .. "Programs" .. s .. "LuaJIT" .. s .. "luajit.exe",
    pf .. s .. "LuaJIT" .. s .. "bin" .. s .. "luajit.exe",
    pf .. s .. "LuaJIT" .. s .. "luajit.exe",
    pf86 .. s .. "LuaJIT" .. s .. "bin" .. s .. "luajit.exe",
    pf .. s .. "luajit" .. s .. "bin" .. s .. "luajit.exe",
  }
  for _, p in ipairs(extras) do
    if p and p ~= "" and not p:find("^" .. s) then
      list[#list + 1] = p
    end
  end
  if localApp ~= "" then
    local roots = {
      localApp .. s .. "Microsoft" .. s .. "WinGet" .. s .. "Packages",
      localApp .. s .. "Programs",
    }
    for _, root in ipairs(roots) do
      local ok, out = runShell(string.format(
        'cmd /C "if exist "%s" dir /s /b "%s\\luajit.exe" 2>nul"', root, root))
      if out then
        for line in out:gmatch("[^\r\n]+") do
          if line:lower():find("luajit%.exe", 1, false) and fileExists(line) then
            list[#list + 1] = line
          end
        end
      end
    end
  end
  return list
end

--- @return string|nil path, string|nil libDir
function LuaJitTool.find()
  scrubLegacyAppDataLuaJit()

  local env = os.getenv("MODKIT_LUAJIT")
  if env and env ~= "" and fileExists(env) and not isLegacyAppDataLuaJit(env) then
    return env, nil
  end

  local onPath = whichOnPath()
  if onPath then return onPath, nil end

  if isWindows() then
    for _, p in ipairs(windowsCandidates()) do
      if fileExists(p) then return p, nil end
    end
  end

  return nil, nil
end

local function installWindowsWinget()
  -- Prefer locating a per-user winget install before (re)running winget.
  for _, p in ipairs(windowsCandidates()) do
    if fileExists(p) then return p, nil end
  end
  local cmd =
    'winget install --id DEVCOM.LuaJIT -e --accept-package-agreements '
    .. '--accept-source-agreements --disable-interactivity'
  local ok, out = runShell(cmd)
  local lower = tostring(out or ""):lower()
  local installedOk = ok
    or lower:find("already installed", 1, true)
    or lower:find("no available upgrade", 1, true)
    or lower:find("successfully installed", 1, true)
  if not installedOk then
    return nil, "winget install failed: " .. tostring(out):sub(1, 240)
  end
  for _, p in ipairs(windowsCandidates()) do
    if fileExists(p) then return p, nil end
  end
  local onPath = whichOnPath()
  if onPath then return onPath, nil end
  return nil,
    "winget finished but luajit.exe was not found "
      .. "(expected under %LOCALAPPDATA%\\Programs\\LuaJIT\\bin)"
end

local function installLinuxApt()
  -- Non-interactive; may fail without sudo — that's OK, we report clearly.
  local cmds = {
    'sudo -n apt-get install -y luajit',
    'sudo -n dnf install -y luajit',
    'sudo -n pacman -S --noconfirm luajit',
  }
  for _, cmd in ipairs(cmds) do
    local ok = runShell(cmd)
    if ok then
      local p = whichOnPath()
      if p then return p, nil end
    end
  end
  return nil,
    "install LuaJIT (e.g. sudo apt install luajit) or set MODKIT_LUAJIT"
end

--- Find LuaJIT or install via the OS package manager.
--- @return string|nil path, string|nil libDir, string|nil err, boolean installed
function LuaJitTool.ensure()
  local path, lib = LuaJitTool.find()
  if path then return path, lib, nil, false end

  if isWindows() then
    local exe, err = installWindowsWinget()
    if exe then return exe, nil, nil, true end
    return nil, nil,
      (err or "LuaJIT missing")
        .. " — run: winget install DEVCOM.LuaJIT   (or set MODKIT_LUAJIT)",
      false
  end

  if isLinux() then
    local exe, err = installLinuxApt()
    if exe then return exe, nil, nil, true end
    return nil, nil, err or "LuaJIT missing", false
  end

  return nil, nil,
    "Install luajit or set MODKIT_LUAJIT (auto-install supports Windows/Linux)",
    false
end

--- Build a shell command that runs `inner` with MODKIT_LUAJIT set.
--- extraEnv: optional map of extra environment variables (e.g. POKEPORT_DATA_DIR).
function LuaJitTool.wrapCommand(innerCmd, luajitPath, libDir, extraEnv)
  local tools = saveToolsRoot() or "."
  ensureDir(tools)
  extraEnv = extraEnv or {}
  if isWindows() then
    local bat = tools .. sep() .. "run_validate.bat"
    local f = io.open(bat, "wb")
    if not f then
      return string.format(
        'cmd /C "set \"MODKIT_LUAJIT=%s\"&& %s"', luajitPath, innerCmd)
    end
    f:write("@echo off\r\n")
    f:write(string.format('set "MODKIT_LUAJIT=%s"\r\n', luajitPath))
    for k, v in pairs(extraEnv) do
      if k and v and v ~= "" then
        f:write(string.format('set "%s=%s"\r\n', k, v))
      end
    end
    f:write(innerCmd .. "\r\n")
    f:close()
    return '"' .. bat .. '"'
  end
  local sh = tools .. sep() .. "run_validate.sh"
  local f = io.open(sh, "wb")
  if not f then
    local exports = string.format('MODKIT_LUAJIT="%s"', luajitPath)
    if libDir and libDir ~= "" then
      exports = exports .. string.format(
        ' LD_LIBRARY_PATH="%s:${LD_LIBRARY_PATH:-}"', libDir)
    end
    for k, v in pairs(extraEnv) do
      if k and v and v ~= "" then
        exports = exports .. string.format(' %s="%s"', k, v)
      end
    end
    return exports .. " " .. innerCmd
  end
  f:write("#!/bin/sh\n")
  f:write(string.format('export MODKIT_LUAJIT="%s"\n', luajitPath))
  if libDir and libDir ~= "" then
    f:write(string.format(
      'export LD_LIBRARY_PATH="%s:${LD_LIBRARY_PATH:-}"\n', libDir))
  end
  for k, v in pairs(extraEnv) do
    if k and v and v ~= "" then
      f:write(string.format('export %s="%s"\n', k, v))
    end
  end
  f:write(innerCmd .. "\n")
  f:close()
  runShell(string.format('chmod +x "%s"', sh))
  return string.format('sh "%s"', sh)
end

function LuaJitTool.platformLabel()
  if isWindows() then return "Windows" end
  if isLinux() then return "Linux" end
  local osName = love and love.system and love.system.getOS and love.system.getOS()
  return osName or "unknown"
end

return LuaJitTool
