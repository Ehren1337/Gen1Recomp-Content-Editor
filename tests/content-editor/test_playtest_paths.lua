package.path = "tools/content-editor/?.lua;" .. package.path

-- Keep the packaged editor's common relative --mod path from being mistaken
-- for a different directory than the absolute bundled mods path.
local PlaytestPaths = require("PlaytestPaths")
local sep = package.config:sub(1, 1)

local root = sep == "\\" and "C:\\package" or "/package"
local relative = sep == "\\" and "mods\\my_content" or "mods/my_content"
local expected = sep == "\\" and "C:\\package\\mods\\my_content"
  or "/package/mods/my_content"
local source = PlaytestPaths.absoluteFromRoot(relative, root)
assert(PlaytestPaths.same(source, expected))

local external = sep == "\\" and "D:\\external\\mod" or "/external/mod"
assert(PlaytestPaths.absoluteFromRoot(external, root) == external)

local pinned = PlaytestPaths.pinnedRuntime(root, function(path)
  return PlaytestPaths.same(path,
    sep == "\\" and "C:\\package\\runtime\\gen1recomp"
      or "/package/runtime/gen1recomp")
end)
assert(pinned ~= nil)
assert(PlaytestPaths.pinnedRuntime(root, function() return false end) == nil)

local command = PlaytestPaths.windowsLaunch(
  "C:\\pack\\love\\love.exe", "C:\\pack\\runtime\\gen1recomp", "red")
assert(command:find('cd /d "C:\\pack\\runtime\\gen1recomp"', 1, true))
assert(command:find('"C:\\pack\\love\\love.exe" . --game=red', 1, true))

print("ok playtest paths")
