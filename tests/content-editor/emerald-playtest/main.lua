local runtime = assert(os.getenv("EMERALD_RUNTIME"))
local project = assert(os.getenv("EDITOR_TEST_ROOT"))
local ffi = require("ffi")
ffi.cdef("int PHYSFS_mount(const char*, const char*, int);")
local physfs = ffi.load("love")
local function mount(path, point, append) return physfs.PHYSFS_mount(path, point, append and 1 or 0) ~= 0 end
assert(mount(runtime, "", true))
assert(mount(project .. "/tests/content-editor/emerald-playtest/mod", "mods/emerald_e2e", false))
local items = love.filesystem.getDirectoryItems
love.filesystem.getDirectoryItems = function(path)
  if path == "mods" then return {"emerald_e2e"} end
  return items(path)
end
local Save = require("src.core.SaveData")
local options = Save.defaultOptions()
options.mods = {emerald_e2e=true}
options.modsByVersion = {emerald={emerald_e2e=true}}
Save.loadOptions = function() return options end
Save.saveOptions = function() return true end
Save.load = function() return nil end
Save.save = function() return true end
assert(loadfile(runtime .. "/main.lua"))()
