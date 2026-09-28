-- GUIDES tab data (Guides.lua, GuidesData.lua). Plain LuaJIT, no LOVE. Run
-- from the repository root:
--   luajit tests/content-editor/test_guides.lua
package.path = "tools/content-editor/?.lua;tools/content-editor/panels/?.lua;" .. package.path
local Guides = require("Guides")

local pass, fail = 0, 0
local function run(name, fn)
  local ok, err = pcall(fn)
  if ok then pass = pass + 1; print("ok    " .. name)
  else fail = fail + 1; print("FAIL  " .. name .. "\n      " .. tostring(err)) end
end

run("the shipped guides load and every guide has a topic and steps", function()
  assert(#Guides.CATEGORIES >= 1 and #Guides.GUIDES >= 1)
  local cats = {}
  for _, c in ipairs(Guides.CATEGORIES) do cats[c.id] = true end
  local ids = {}
  for _, g in ipairs(Guides.GUIDES) do
    assert(cats[g.category], g.id .. " has no topic")
    assert(not ids[g.id], "duplicate id " .. g.id); ids[g.id] = true
    assert(type(g.steps) == "table" and #g.steps > 0, g.id .. " has no steps")
  end
end)

run("Take me there switches tab and panel settings", function()
  local S = {}
  Guides.go(S, { tab = "gfx", set = { g3GfxMode = "blocks" } })
  assert(S.tab == "gfx" and S.g3GfxMode == "blocks" and S._tabBarNeedsReveal)
  local T = { tab = "maps" }
  Guides.go(T, nil); Guides.go(T, {})
  assert(T.tab == "maps", "no place to go changes nothing")
end)

print(("\n%d passed, %d failed"):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
