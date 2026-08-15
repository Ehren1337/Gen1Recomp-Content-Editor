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

function RuntimeMount.mount()
  local fs = assert(love and love.filesystem, "LÖVE filesystem unavailable")
  if fs.getInfo("src/core/GameVersion.lua", "file") then return true end
  local separator = package.config:sub(1, 1)
  local source = assert(fs.getSource(), "LÖVE source directory unavailable")
  local root = source:gsub("[/\\]+$", "")
  local archive = root .. separator .. "runtime" .. separator .. "gen1recomp.love"
  local fused = root .. separator .. "love" .. separator .. "gen1recomp.exe"
  local directory = root .. separator .. "runtime" .. separator .. "gen1recomp"
  local file = io.open(archive, "rb")
  local fusedFile = not file and io.open(fused, "rb") or nil
  local runtime = file and archive or (fusedFile and fused or directory)
  if file then file:close() end
  if fusedFile then fusedFile:close() end
  local mount = resolveMount()
  return mount and mount(runtime) or false
end

return RuntimeMount
