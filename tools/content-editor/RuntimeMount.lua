-- Mount the pinned Gen1Recomp directory into the editor's PhysFS root.
-- love.filesystem.mount cannot mount an arbitrary source-relative directory
-- on desktop, so use the same native PHYSFS_mount entry point as Gen1Recomp's
-- cache layer. This bootstrap deliberately has no runtime-module dependency.

local RuntimeMount = {}

local function resolveMount()
  local ok, ffi = pcall(require, "ffi")
  if not ok then return nil end
  pcall(ffi.cdef,
    "int PHYSFS_mount(const char *newDir, const char *mountPoint, int appendToPath);")
  local libraries = {
    function() return ffi.C end,
    function() return ffi.load("love") end,
  }
  for _, getLibrary in ipairs(libraries) do
    local loaded, library = pcall(getLibrary)
    if loaded and library then
      local found, fn = pcall(function() return library.PHYSFS_mount end)
      if found and fn then
        return function(path)
          -- Append: editor-owned tools at the package root must win collisions
          -- such as tools/save-editor/Kit.lua. Runtime-only src/data/assets
          -- still resolve from this mounted archive.
          local called, result = pcall(fn, path, "", 1)
          return called and result ~= 0
        end
      end
    end
  end
end

local function fileExists(path)
  local f = io.open(path, "rb")
  if f then f:close(); return true end
  return false
end

local function join(a, b)
  local sep = package.config:sub(1, 1)
  a = tostring(a or ""):gsub("[/\\]+$", "")
  b = tostring(b or ""):gsub("^[/\\]+", "")
  return a .. sep .. b
end

local function looksLikeRecomp(path)
  if type(path) ~= "string" or path == "" then return false end
  return fileExists(join(path, "src/core/GameVersion.lua"))
    or fileExists(join(path, "src\\core\\GameVersion.lua"))
end

local function unescapeJson(s)
  return (tostring(s or ""):gsub("\\u(%x%x%x%x)", function(h)
    return string.char(tonumber(h, 16) % 256)
  end):gsub("\\/", "/"):gsub("\\\\", "\\"):gsub('\\"', '"'))
end

local function linkedRecompPath()
  local env = os.getenv("POKEPORT_RECOMP")
  if looksLikeRecomp(env) then return env end
  local save = love.filesystem.getSaveDirectory and love.filesystem.getSaveDirectory()
  local prefs = save and join(save, "content_editor_data.json")
  local body = prefs and fileExists(prefs) and (function()
    local f = io.open(prefs, "rb")
    if not f then return nil end
    local text = f:read("*a")
    f:close()
    return text
  end)()
  local raw = body and body:match('"recompRoot"%s*:%s*"([^"]*)"')
  local path = raw and unescapeJson(raw)
  if looksLikeRecomp(path) then return path end
  return nil
end

local function runtimeComplete(fs)
  return fs.getInfo("src/core/GameVersion.lua", "file")
    and fs.getInfo("src/mods/Loader.lua", "file")
end

function RuntimeMount.mount()
  local fs = assert(love and love.filesystem, "LÖVE filesystem unavailable")
  if runtimeComplete(fs) then return true end
  local mount = resolveMount()
  if not mount then return false end

  local separator = package.config:sub(1, 1)
  local source = assert(fs.getSource(), "LÖVE source directory unavailable")
  local root = source:gsub("[/\\]+$", "")
  local archive = root .. separator .. "runtime" .. separator .. "gen1recomp.love"
  local fused = root .. separator .. "love" .. separator .. "gen1recomp.exe"
  local directory = root .. separator .. "runtime" .. separator .. "gen1recomp"
  local candidates = {}
  if fileExists(archive) then candidates[#candidates + 1] = archive end
  if fileExists(fused) then candidates[#candidates + 1] = fused end
  if looksLikeRecomp(directory) then candidates[#candidates + 1] = directory end
  local linked = linkedRecompPath()
  if linked then candidates[#candidates + 1] = linked end

  for i = 1, #candidates do
    if mount(candidates[i]) and runtimeComplete(fs) then
      return true
    end
  end
  return runtimeComplete(fs)
end

return RuntimeMount
