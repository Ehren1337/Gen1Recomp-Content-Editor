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

print("ok playtest paths")
