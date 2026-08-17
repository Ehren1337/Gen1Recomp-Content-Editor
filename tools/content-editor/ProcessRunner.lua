local ProcessRunner = {}
local windowsFfi
local windowsFfiInitialized = false

local function isWindows()
  local osName = love and love.system and love.system.getOS and love.system.getOS()
  if osName then return osName == "Windows" end
  return package.config:sub(1, 1) == "\\"
end

local function readFile(path)
  local file = io.open(path, "rb")
  if not file then return "" end
  local contents = file:read("*a") or ""
  file:close()
  return contents
end

local function portableRun(command)
  local ok, handle = pcall(io.popen, command .. " 2>&1")
  if not ok or not handle then
    return false, "shell unavailable: " .. tostring(handle)
  end
  local output = handle:read("*a") or ""
  local okClose, _, code = handle:close()
  local exitCode = type(code) == "number" and code or (okClose and 0 or 1)
  return exitCode == 0, output, exitCode
end

local function getWindowsFfi()
  if windowsFfiInitialized then return windowsFfi end
  windowsFfiInitialized = true
  local okFfi, ffi = pcall(require, "ffi")
  if not okFfi then return nil end
  local okCdef = pcall(ffi.cdef, [[
    typedef int BOOL;
    typedef unsigned long DWORD;
    typedef void *HANDLE;
    typedef const char *LPCSTR;
    typedef char *LPSTR;
    typedef void *LPVOID;
    typedef struct {
      DWORD cb; LPSTR lpReserved; LPSTR lpDesktop; LPSTR lpTitle;
      DWORD dwX; DWORD dwY; DWORD dwXSize; DWORD dwYSize;
      DWORD dwXCountChars; DWORD dwYCountChars; DWORD dwFillAttribute;
      DWORD dwFlags; unsigned short wShowWindow; unsigned short cbReserved2;
      unsigned char *lpReserved2; HANDLE hStdInput; HANDLE hStdOutput; HANDLE hStdError;
    } STARTUPINFOA;
    typedef struct { HANDLE hProcess; HANDLE hThread; DWORD dwProcessId; DWORD dwThreadId; }
      PROCESS_INFORMATION;
    BOOL CreateProcessA(LPCSTR, LPSTR, LPVOID, LPVOID, BOOL, DWORD, LPVOID,
      LPCSTR, STARTUPINFOA *, PROCESS_INFORMATION *);
    DWORD WaitForSingleObject(HANDLE, DWORD);
    BOOL GetExitCodeProcess(HANDLE, DWORD *);
    BOOL CloseHandle(HANDLE);
  ]])
  if not okCdef then return nil end
  windowsFfi = ffi
  return windowsFfi
end

local function tempBase()
  local tmp = os.getenv("TEMP") or os.getenv("TMP") or os.getenv("TMPDIR")
  local name = "pokeport_ce_" .. tostring(os.time()) .. "_"
    .. tostring(math.random(100000, 999999))
  if tmp and tmp ~= "" then
    return tmp .. package.config:sub(1, 1) .. name
  end
  -- LuaJIT on Windows often returns a drive-root name (\sXXXX) that is not writable.
  local fallback = os.tmpname()
  os.remove(fallback)
  return fallback
end

local function windowsRun(command)
  local ffi = getWindowsFfi()
  if not ffi then return portableRun(command) end

  local base = tempBase()
  local batchPath = base .. ".bat"
  local outputPath = base .. ".out"
  local batch = io.open(batchPath, "wb")
  if not batch then return false, "could not create validation command file" end
  batch:write("@echo off\r\n", command, "\r\nexit /b %errorlevel%\r\n")
  batch:close()

  local commandLine = string.format(
    'cmd.exe /d /s /c "call ""%s"" > ""%s"" 2>&1"', batchPath, outputPath)
  local buffer = ffi.new("char[?]", #commandLine + 1, commandLine)
  local startup = ffi.new("STARTUPINFOA")
  startup.cb = ffi.sizeof(startup)
  local process = ffi.new("PROCESS_INFORMATION")
  local created = ffi.C.CreateProcessA(nil, buffer, nil, nil, 0, 0x08000000,
    nil, nil, startup, process)
  if created == 0 then
    os.remove(batchPath)
    return false, "could not start hidden Windows command"
  end

  ffi.C.CloseHandle(process.hThread)
  ffi.C.WaitForSingleObject(process.hProcess, 0xFFFFFFFF)
  local exitCode = ffi.new("DWORD[1]")
  ffi.C.GetExitCodeProcess(process.hProcess, exitCode)
  ffi.C.CloseHandle(process.hProcess)

  local output = readFile(outputPath)
  os.remove(batchPath)
  os.remove(outputPath)
  local code = tonumber(exitCode[0])
  return code == 0, output, code
end

function ProcessRunner.run(command)
  if isWindows() then return windowsRun(command) end
  return portableRun(command)
end

return ProcessRunner
