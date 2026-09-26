local runtime = assert(os.getenv("HGSS_RUNTIME"))
local project = assert(os.getenv("HGSS_PROJECT"))
local ffi = require("ffi")
ffi.cdef("int PHYSFS_mount(const char*, const char*, int);")
local physfs = ffi.load("love")
local function mount(path, point, append) return physfs.PHYSFS_mount(path, point, append and 1 or 0) ~= 0 end
assert(mount(runtime, "", true))
assert(mount(os.getenv("APPDATA") .. "/LOVE/pokemon-love2d/firered", "firered", true))
assert(mount(project .. "/mods/firered_hgss_voxel", "mods/firered_hgss_voxel", false))
local items = love.filesystem.getDirectoryItems
love.filesystem.getDirectoryItems = function(path)
  if path == "mods" then return {"firered_hgss_voxel"} end
  return items(path)
end
local Save = require("src.core.SaveData")
local options = Save.defaultOptions()
options.mods = {firered_hgss_voxel=true}
options.modsByVersion = {firered={firered_hgss_voxel=true}}
Save.loadOptions = function() return options end
Save.saveOptions = function() return true end
Save.load = function() return nil end
Save.save = function() return true end
assert(loadfile(runtime .. "/main.lua"))()

