-- Update editor: checks the editor's GitHub releases for a newer build,
-- downloads it, and installs it with a small helper script that runs after
-- the editor closes (then opens it again).
--
-- Every push to the editor's main branch publishes a release
-- (content-editor-v0.1.N) with a portable pack per platform. LÖVE 11 can't
-- download on its own, so the work is done by the system's own tools, in
-- the background: curl (Windows 10+, Linux, macOS) or PowerShell, then
-- tar / Expand-Archive, then robocopy / cp.
--
-- What an update never touches: mods/ (your projects), the ROM cache
-- (data/generated, assets/generated), saves and settings. A source
-- checkout (a .git folder) is never overwritten: it's told to update with
-- git or GitHub Desktop instead.
--
-- Files live in the editor's save folder under update/: latest.json, the
-- downloaded pack, the unpacked copy, the helper script and its log.

local M = {}

M.REPO = "zeak6464/Gen1Recomp-Content-Editor"
M.VERSION_FILE = "content-editor-version.txt"
M.ASSETS = {
  Windows = "gen1recomp-content-editor-win64.zip",
  Linux = "gen1recomp-content-editor-linux64.tar.gz",
  ["OS X"] = "gen1recomp-content-editor-macos-universal.tar.gz",
}
M.LAUNCHERS = { Windows = "ContentEditor.bat", Linux = "ContentEditor.sh", ["OS X"] = "ContentEditor.command" }

function M.apiUrl()
  local o = os.getenv("POKEPORT_UPDATE_API")
  if o and o ~= "" then return o end
  return "https://api.github.com/repos/" .. M.REPO .. "/releases/latest"
end

function M.releasesPage()
  return "https://github.com/" .. M.REPO .. "/releases/latest"
end

-- A small JSON reader (the release API's answer) ------------------------------

function M.decodeJson(text)
  local pos = 1
  local function ws() pos = text:find("[^ \t\r\n]", pos) or #text + 1 end
  local value
  local function str()
    local out, i = {}, pos + 1
    while true do
      local c = text:sub(i, i)
      if c == "" then error("unterminated string") end
      if c == '"' then pos = i + 1; return table.concat(out) end
      if c == "\\" then
        local e = text:sub(i + 1, i + 1)
        local map = { b = "\b", f = "\f", n = "\n", r = "\r", t = "\t", ['"'] = '"', ["\\"] = "\\", ["/"] = "/" }
        if e == "u" then
          local code = tonumber(text:sub(i + 2, i + 5), 16) or 63
          i = i + 6
          if code >= 0xD800 and code <= 0xDBFF and text:sub(i, i + 1) == "\\u" then
            local low = tonumber(text:sub(i + 2, i + 5), 16) or 0xDC00
            code = 0x10000 + (code - 0xD800) * 0x400 + (low - 0xDC00)
            i = i + 6
          end
          if code < 0x80 then out[#out + 1] = string.char(code)
          elseif code < 0x800 then out[#out + 1] = string.char(0xC0 + math.floor(code / 64), 0x80 + code % 64)
          elseif code < 0x10000 then
            out[#out + 1] = string.char(0xE0 + math.floor(code / 4096), 0x80 + math.floor(code / 64) % 64, 0x80 + code % 64)
          else
            out[#out + 1] = string.char(0xF0 + math.floor(code / 262144), 0x80 + math.floor(code / 4096) % 64,
              0x80 + math.floor(code / 64) % 64, 0x80 + code % 64)
          end
        else
          out[#out + 1] = map[e] or e
          i = i + 2
        end
      else
        local j = text:find('["\\]', i)
        if not j then error("unterminated string") end
        out[#out + 1] = text:sub(i, j - 1)
        i = j
      end
    end
  end
  function value()
    ws()
    local c = text:sub(pos, pos)
    if c == "{" then
      local obj = {}
      pos = pos + 1; ws()
      if text:sub(pos, pos) == "}" then pos = pos + 1; return obj end
      while true do
        ws()
        if text:sub(pos, pos) ~= '"' then error("expected a key at " .. pos) end
        local k = str(); ws()
        if text:sub(pos, pos) ~= ":" then error("expected : at " .. pos) end
        pos = pos + 1
        obj[k] = value(); ws()
        local d = text:sub(pos, pos); pos = pos + 1
        if d == "}" then return obj end
        if d ~= "," then error("expected , or } at " .. (pos - 1)) end
      end
    elseif c == "[" then
      local arr = {}
      pos = pos + 1; ws()
      if text:sub(pos, pos) == "]" then pos = pos + 1; return arr end
      while true do
        arr[#arr + 1] = value(); ws()
        local d = text:sub(pos, pos); pos = pos + 1
        if d == "]" then return arr end
        if d ~= "," then error("expected , or ] at " .. (pos - 1)) end
      end
    elseif c == '"' then return str()
    elseif text:sub(pos, pos + 3) == "true" then pos = pos + 4; return true
    elseif text:sub(pos, pos + 4) == "false" then pos = pos + 5; return false
    elseif text:sub(pos, pos + 3) == "null" then pos = pos + 4; return nil
    else
      local num = text:match("^-?%d+%.?%d*[eE]?[-+]?%d*", pos)
      if not num or num == "" then error("unexpected character at " .. pos) end
      pos = pos + #num
      return tonumber(num)
    end
  end
  local ok, result = pcall(value)
  if not ok then return nil, result end
  return result
end

-- Versions ---------------------------------------------------------------------

--- "content-editor-v0.1.104" -> { 0, 1, 104 }, or nil.
function M.parseVersion(tag)
  local v = tostring(tag or ""):match("v?(%d[%d%.]*)%s*$")
  if not v then return nil end
  local nums = {}
  for n in v:gmatch("%d+") do nums[#nums + 1] = tonumber(n) end
  return #nums > 0 and nums or nil
end

--- Is release tag `a` newer than `b`? (b nil = unknown: yes.)
function M.newer(a, b)
  local va, vb = M.parseVersion(a), M.parseVersion(b)
  if not va then return false end
  if not vb then return true end
  for i = 1, math.max(#va, #vb) do
    local x, y = va[i] or 0, vb[i] or 0
    if x ~= y then return x > y end
  end
  return false
end

--- "content-editor-v0.1.104" -> "v0.1.104".
function M.short(tag)
  return tag and (tostring(tag):match("(v[%d%.]+)%s*$") or tostring(tag)) or "unknown"
end

--- The release API's answer -> { tag, name, notes, url, size, page }, or nil and why.
function M.parseRelease(text, platform)
  local data, err = M.decodeJson(text or "")
  if type(data) ~= "table" then return nil, "couldn't read the release list (" .. tostring(err) .. ")" end
  if data.message and not data.tag_name then return nil, "GitHub says: " .. tostring(data.message) end
  if not data.tag_name then return nil, "no release found" end
  local want = M.ASSETS[platform or "Windows"]
  local asset
  for _, a in ipairs(data.assets or {}) do
    if a.name == want then asset = a end
  end
  return {
    tag = data.tag_name, name = data.name or data.tag_name, page = data.html_url or M.releasesPage(),
    notes = M.cleanNotes(data.body), url = asset and asset.browser_download_url, size = asset and asset.size,
    asset = want,
  }
end

--- Release notes as a few plain lines (GitHub's generated notes are markdown).
function M.cleanNotes(body)
  local lines = {}
  for line in tostring(body or ""):gsub("\r", ""):gmatch("[^\n]+") do
    line = line:gsub("%*%*", ""):gsub("^#+%s*", ""):gsub("^[%*%-]%s+", "- ")
      :gsub(" by @[%w%-_]+ in https?://%S+", ""):gsub("%[([^%]]+)%]%([^%)]+%)", "%1")
    if line:match("%S") and not line:match("^Full Changelog") and line ~= "What's Changed" then
      lines[#lines + 1] = line
    end
  end
  return lines
end

-- Where things are -------------------------------------------------------------

local function sep() return package.config:sub(1, 1) end
local function join(a, b) return (a:gsub("[/\\]+$", "")) .. sep() .. b end

local function exists(path)
  local f = io.open(path, "rb")
  if f then f:close() return true end
  return false
end
M.exists = exists

local function readText(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local s = f:read("*a"); f:close()
  return s
end

local function writeText(path, text)
  local f = io.open(path, "wb")
  if not f then return false end
  f:write(text); f:close()
  return true
end

local function fileSize(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local n = f:seek("end"); f:close()
  return n
end

function M.platform()
  return love and love.system and love.system.getOS and love.system.getOS() or (sep() == "\\" and "Windows" or "Linux")
end

--- The editor's own folder (where ContentEditor.bat and main.lua are).
function M.root()
  local configured = os.getenv("POKEPORT_CONTENT_ROOT")
  if configured and configured ~= "" then return configured end
  return love and love.filesystem and love.filesystem.getSource() or "."
end

--- A source checkout (git) -- updated with git, never by the helper.
function M.isCheckout(root)
  root = root or M.root()
  return exists(join(join(root, ".git"), "HEAD")) or exists(join(root, ".git"))
end

function M.currentVersion(root)
  local text = readText(join(root or M.root(), M.VERSION_FILE))
  local tag = text and text:match("%S+")
  return tag
end

--- The working folder, in the editor's save folder.
function M.workDir()
  local o = os.getenv("POKEPORT_UPDATE_DIR")
  if o and o ~= "" then return o end
  love.filesystem.createDirectory("update")
  return join(love.filesystem.getSaveDirectory(), "update")
end

--- A line in update/restart.log (what the Restart button did), for when
-- something doesn't go as expected.
function M.log(line)
  local ok, dir = pcall(M.workDir)
  if not ok then return end
  local f = io.open(join(dir, "restart.log"), "ab")
  if f then f:write(os.date("%Y-%m-%d %H:%M:%S  ") .. tostring(line) .. "\n"); f:close() end
end

--- The release an update just installed (once, the first time the editor
-- opens after it), or nil.
function M.justInstalled()
  local ok, dir = pcall(M.workDir)
  if not ok then return nil end
  local path = join(dir, "installed.txt")
  local text = readText(path)
  if not text then return nil end
  os.remove(path)
  return text:match("%S+")
end

-- Running tools in the background ------------------------------------------------

local ffiC
local function ffi()
  if ffiC ~= nil then return ffiC end
  local ok, lib = pcall(require, "ffi")
  if not ok then ffiC = false return false end
  if M.platform() == "Windows" then
    pcall(lib.cdef, [[
      typedef struct { unsigned long cb; char *lpReserved; char *lpDesktop; char *lpTitle;
        unsigned long dwX, dwY, dwXSize, dwYSize, dwXCountChars, dwYCountChars, dwFillAttribute, dwFlags;
        unsigned short wShowWindow, cbReserved2; unsigned char *lpReserved2; void *hStdInput, *hStdOutput, *hStdError;
      } UPD_STARTUPINFOA;
      typedef struct { void *hProcess; void *hThread; unsigned long dwProcessId, dwThreadId; } UPD_PROCESS_INFORMATION;
      int CreateProcessA(const char *, char *, void *, void *, int, unsigned long, void *, const char *,
        UPD_STARTUPINFOA *, UPD_PROCESS_INFORMATION *);
      int CloseHandle(void *);
      unsigned long GetCurrentProcessId(void);
    ]])
  else
    pcall(lib.cdef, "int getpid(void);")
  end
  ffiC = lib
  return lib
end

function M.pid()
  local lib = ffi()
  if not lib then return 0 end
  local ok, pid
  if M.platform() == "Windows" then ok, pid = pcall(function() return lib.C.GetCurrentProcessId() end)
  else ok, pid = pcall(function() return lib.C.getpid() end) end
  return ok and tonumber(pid) or 0
end

--- Run a script without waiting and without a window. Windows: a .bat
-- (hidden, or `visible` in its own console); elsewhere a sh script.
function M.launch(script, visible)
  if M.platform() == "Windows" then
    local lib = ffi()
    local cmd = ('cmd.exe /d /c ""%s""'):format(script)
    if lib then
      local buf = lib.new("char[?]", #cmd + 1, cmd)
      local si = lib.new("UPD_STARTUPINFOA"); si.cb = lib.sizeof(si)
      local pi = lib.new("UPD_PROCESS_INFORMATION")
      -- CREATE_NO_WINDOW | DETACHED... (hidden) or CREATE_NEW_CONSOLE (visible)
      local flags = visible and 0x00000010 or 0x08000000
      local ok, made = pcall(function() return lib.C.CreateProcessA(nil, buf, nil, nil, 0, flags, nil, nil, si, pi) end)
      if ok and made ~= 0 then
        lib.C.CloseHandle(pi.hThread); lib.C.CloseHandle(pi.hProcess)
        return true
      end
    end
    return os.execute(('start "%s" /min cmd /d /c ""%s""'):format("Content Editor update", script)) ~= nil
  end
  return os.execute(("sh '%s' >/dev/null 2>&1 &"):format(script)) ~= nil
end

local function q(path) -- quoted for the script (Windows paths get backslashes)
  if M.platform() == "Windows" then
    if not path:match("^%a+://") then path = path:gsub("/", "\\") end
    return '"' .. path .. '"'
  end
  return "'" .. path:gsub("'", "'\\''") .. "'"
end

--- A background job: `lines` (script body) run, then `done` holds its exit code.
local function job(name, lines)
  local dir = M.workDir()
  local done = join(dir, name .. ".done")
  os.remove(done)
  local win = M.platform() == "Windows"
  local script = join(dir, name .. (win and ".bat" or ".sh"))
  local body
  if win then
    body = "@echo off\r\ncd /d " .. q(dir) .. "\r\ncall :main\r\n> " .. q(done) .. " echo %errorlevel%\r\nexit /b\r\n:main\r\n"
      .. table.concat(lines, "\r\n") .. "\r\nexit /b %errorlevel%\r\n"
  else
    body = "#!/bin/sh\ncd " .. q(dir) .. "\n( " .. table.concat(lines, "\n") .. "\n)\necho $? > " .. q(done) .. "\n"
  end
  if not writeText(script, body) then return nil, "couldn't write " .. script end
  if not M.launch(script) then return nil, "couldn't start " .. script end
  return { done = done, started = os.time() }
end

--- nil while running; then true / false (and the exit code).
local function finished(j)
  local code = j and readText(j.done)
  if not code then return nil end
  code = tonumber(code:match("%-?%d+")) or 1
  return code == 0, code
end

local function fetchLines(url, out, api)
  local accept = api and "-H \"Accept: application/vnd.github+json\" " or ""
  if M.platform() == "Windows" then
    local o = q(out):sub(2, -2)
    return {
      "where curl.exe >nul 2>nul",
      "if %errorlevel%==0 (",
      "  curl.exe -fsSL --retry 2 --connect-timeout 15 " .. accept .. "-o " .. q(out) .. " " .. q(url),
      ") else (",
      "  powershell -NoProfile -ExecutionPolicy Bypass -Command \"$ProgressPreference='SilentlyContinue'; Invoke-WebRequest -UseBasicParsing -Uri '"
        .. url .. "' -OutFile '" .. o .. "'\"",
      ")",
    }
  end
  return {
    "if command -v curl >/dev/null 2>&1; then curl -fsSL --retry 2 --connect-timeout 15 " .. accept:gsub('"', "'") .. "-o "
      .. q(out) .. " " .. q(url) .. "; else wget -q -O " .. q(out) .. " " .. q(url) .. "; fi",
  }
end

-- The steps --------------------------------------------------------------------
-- M.state: { step = "idle" | "checking" | "ready" | "latest" | "downloading" |
--   "unpacking" | "staged" | "error", release =, error =, auto = }

M.state = { step = "idle" }

function M.check(auto)
  if M.state.step == "checking" or M.state.step == "downloading" or M.state.step == "unpacking" then return end
  local okDir, dir = pcall(M.workDir)
  if not okDir then M.state = { step = "error", error = "no update folder: " .. tostring(dir), auto = auto } return end
  local out = join(dir, "latest.json")
  os.remove(out)
  local j, err = job("check", fetchLines(M.apiUrl(), out, true))
  if not j then M.state = { step = "error", error = err, auto = auto } return end
  M.state = { step = "checking", job = j, file = out, auto = auto }
end

function M.download()
  local rel = M.state.release
  if not rel or not rel.url then return end
  local dir = M.workDir()
  local pkg = join(dir, rel.asset)
  local staged = join(dir, "staged")
  os.remove(pkg)
  local lines = fetchLines(rel.url, pkg)
  if M.platform() == "Windows" then
    lines[#lines + 1] = "if not %errorlevel%==0 exit /b %errorlevel%"
    lines[#lines + 1] = "if exist " .. q(staged) .. " rmdir /s /q " .. q(staged)
    lines[#lines + 1] = "mkdir " .. q(staged)
    lines[#lines + 1] = "tar -xf " .. q(pkg) .. " -C " .. q(staged) .. " 2>nul"
    lines[#lines + 1] = "if not %errorlevel%==0 powershell -NoProfile -ExecutionPolicy Bypass -Command \"Expand-Archive -LiteralPath '"
      .. q(pkg):sub(2, -2) .. "' -DestinationPath '" .. q(staged):sub(2, -2) .. "' -Force\""
  else
    lines[#lines + 1] = "[ -s " .. q(pkg) .. " ] || exit 1"
    lines[#lines + 1] = "rm -rf " .. q(staged) .. " && mkdir -p " .. q(staged)
    lines[#lines + 1] = "tar -xzf " .. q(pkg) .. " -C " .. q(staged)
  end
  local j, err = job("download", lines)
  if not j then M.state.step, M.state.error = "error", err return end
  M.state.step, M.state.job, M.state.pkg, M.state.staged = "downloading", j, pkg, staged
end

--- The unpacked editor folder inside `staged` (the pack has one top folder).
function M.findPackage(staged)
  if exists(join(staged, "main.lua")) then return staged end
  local win = M.platform() == "Windows"
  local list = win and io.popen('dir /b /ad "' .. staged .. '" 2>nul') or io.popen("ls -1 '" .. staged .. "' 2>/dev/null")
  local found
  if list then
    for name in list:lines() do
      local p = join(staged, name)
      if not found and exists(join(p, "main.lua")) then found = p end
    end
    list:close()
  end
  return found
end

--- Call every frame: moves the steps along.
function M.poll()
  local st = M.state
  if st.step == "checking" then
    local ok = finished(st.job)
    if ok == nil then
      if os.time() - st.job.started > 60 then M.state = { step = "error", error = "the check timed out", auto = st.auto } end
      return
    end
    if not ok then M.state = { step = "error", error = "couldn't reach GitHub (offline?)", auto = st.auto } return end
    local rel, err = M.parseRelease(readText(st.file), M.platform())
    if not rel then M.state = { step = "error", error = err, auto = st.auto } return end
    local current = M.currentVersion()
    local newer = M.newer(rel.tag, current)
    M.state = { step = newer and "ready" or "latest", release = rel, current = current, auto = st.auto, checked = os.time() }
  elseif st.step == "downloading" then
    local ok = finished(st.job)
    st.got = fileSize(st.pkg)
    if ok == nil then return end
    if not ok then st.step, st.error = "error", "the download failed" return end
    local pkg = M.findPackage(st.staged)
    if not pkg then st.step, st.error = "error", "the download didn't unpack" return end
    st.step, st.package = "staged", pkg
  end
end

--- Write the helper that swaps the files in once the editor has closed,
-- start it, and return true (the editor should quit straight after).
function M.install()
  local st = M.state
  if st.step ~= "staged" or not st.package then return nil, "nothing downloaded" end
  local root = M.root()
  if M.isCheckout(root) then return nil, "this editor is a git checkout" end
  local dir = M.workDir()
  local win = M.platform() == "Windows"
  local pid = M.pid()
  local tag = st.release.tag
  local launcher = M.LAUNCHERS[M.platform()] or "ContentEditor.sh"
  local log = join(dir, "install.log")
  local script = join(dir, win and "install.bat" or "install.sh")
  local body
  if win then
    body = table.concat({
      "@echo off",
      "title Updating the Content Editor",
      "echo Updating the Content Editor to " .. tag .. " -- this window closes by itself.",
      "set \"PID=" .. pid .. "\"",
      ":wait",
      "timeout /t 1 /nobreak >nul",
      "tasklist /FI \"PID eq %PID%\" 2>nul | find \" %PID% \" >nul && goto wait",
      "echo Copying the new files...",
      "robocopy " .. q(st.package) .. " " .. q(root) .. " /E /R:10 /W:2 /NP /XD "
        .. q(join(st.package, "mods")) .. " > " .. q(log),
      "if %errorlevel% GEQ 8 goto failed",
      "> " .. q(join(root, M.VERSION_FILE)) .. " echo " .. tag,
      "> " .. q(join(dir, "installed.txt")) .. " echo " .. tag,
      "echo Done -- opening the editor again.",
      "timeout /t 2 /nobreak >nul",
      "rmdir /s /q " .. q(dir .. sep() .. "staged"),
      "del /q " .. q(join(dir, st.release.asset)),
      "start \"\" /D " .. q(root) .. " " .. q(join(root, launcher)),
      "exit /b 0",
      ":failed",
      "echo.",
      "echo The update couldn't copy every file (is the game or editor still open?).",
      "echo Your mods weren't touched. Details: " .. log,
      "pause",
    }, "\r\n") .. "\r\n"
  else
    body = table.concat({
      "#!/bin/sh",
      "while kill -0 " .. pid .. " 2>/dev/null; do sleep 1; done",
      "( cd " .. q(st.package) .. " && tar cf - --exclude=./mods . ) | ( cd " .. q(root) .. " && tar xf - ) > " .. q(log) .. " 2>&1 || exit 1",
      "echo " .. tag .. " > " .. q(join(root, M.VERSION_FILE)),
      "echo " .. tag .. " > " .. q(join(dir, "installed.txt")),
      "rm -rf " .. q(join(dir, "staged")) .. " " .. q(join(dir, st.release.asset)),
      "cd " .. q(root) .. " && ( [ -n \"$POKEPORT_UPDATE_NO_RELAUNCH\" ] || ./" .. launcher .. " >/dev/null 2>&1 & )",
    }, "\n") .. "\n"
  end
  if not writeText(script, body) then return nil, "couldn't write the helper" end
  if not M.launch(script, win) then return nil, "couldn't start the helper" end
  st.step = "installing"
  return true
end

return M
